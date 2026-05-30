# ADP-OS Network Command
# Apply configured runtime networking to existing VMs.

param(
    [string]$SubCommand,
    [string]$RuntimeName,
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if (-not $SubCommand -or $SubCommand -notin @("apply", "configure-local", "local")) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp network apply <runtime|all> [-Plan] | adp network configure-local [-Plan|-Apply]" -Chinese "用法: adp network apply <runtime|all> [-Plan] | adp network configure-local [-Plan|-Apply]") -Component "cli.network"
    exit 1
}

if ($SubCommand -eq "apply" -and -not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp network apply <runtime|all> [-Plan]" -Chinese "用法: adp network apply <runtime|all> [-Plan]") -Component "cli.network"
    exit 1
}

if ($SubCommand -eq "apply" -and $Apply) {
    Write-ErrorLog -Message (Get-UIText -English "-Apply is only supported with: adp network configure-local -Apply" -Chinese "-Apply 仅支持: adp network configure-local -Apply") -Component "cli.network"
    exit 1
}

if ($SubCommand -in @("configure-local", "local") -and $Plan -and $Apply) {
    Write-ErrorLog -Message (Get-UIText -English "Use either -Plan or -Apply, not both." -Chinese "-Plan 与 -Apply 只能二选一。") -Component "cli.network"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "adapters\windows\ssh\ssh.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Ensure-JsonObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Object.PSObject.Properties.Name -notcontains $Name -or -not $Object.$Name) {
        Set-JsonProperty -Object $Object -Name $Name -Value ([pscustomobject]@{})
    }

    return $Object.$Name
}

function Get-IPv4HostOffset {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($Cidr)) {
        return $null
    }

    try {
        $parts = $Cidr -split '/', 2
        if ($parts.Count -ne 2) {
            return $null
        }

        $prefix = [int]$parts[1]
        $networkInt = ConvertTo-ADPIPv4UInt32 -Address $parts[0]
        $mask = Get-ADPIPv4MaskUInt32 -PrefixLength $prefix
        $network = $networkInt -band $mask
        $addressInt = ConvertTo-ADPIPv4UInt32 -Address $Address
        return [int]($addressInt - $network)
    } catch {
        return $null
    }
}

function Get-RuntimeHostOffset {
    param(
        [string]$RuntimeName,
        [object]$Runtime,
        [string]$ConfiguredCidr
    )

    if ($Runtime -and $Runtime.PSObject.Properties.Name -contains "static_ip" -and $Runtime.static_ip) {
        $offset = Get-IPv4HostOffset -Address ([string]$Runtime.static_ip) -Cidr $ConfiguredCidr
        if ($null -ne $offset -and $offset -gt 2) {
            return $offset
        }
    }

    switch ($RuntimeName) {
        "frontend" { return 131 }
        "backend" { return 133 }
        "agent" { return 135 }
        default { return 150 }
    }
}

function Get-VMwareLocalNetworkPlan {
    $hostNat = Get-VMwareNatNetwork
    if (-not $hostNat) {
        throw "VMnet8 host network was not detected. Open VMware Virtual Network Editor, confirm the NAT network, then update configs\local.json manually."
    }

    $config = Get-PlatformConfig
    $topology = Get-TopologyConfig
    $currentNat = $config.network.vmware_nat
    $currentCidr = if ($currentNat -and $currentNat.cidr) { [string]$currentNat.cidr } else { $hostNat.Cidr }
    $gateway = if ($hostNat.Source -eq "vmnetnat.conf" -and $hostNat.Address) {
        [string]$hostNat.Address
    } else {
        Get-ADPIPv4AddressInCidr -Cidr $hostNat.Cidr -HostOffset 2
    }

    $runtimePlans = [System.Collections.Generic.List[object]]::new()
    foreach ($name in (Get-AllRuntimeNames)) {
        $rt = $topology.$name
        $offset = Get-RuntimeHostOffset -RuntimeName $name -Runtime $rt -ConfiguredCidr $currentCidr
        $runtimePlans.Add([pscustomobject]@{
            Name      = $name
            Offset    = $offset
            StaticIp  = Get-ADPIPv4AddressInCidr -Cidr $hostNat.Cidr -HostOffset $offset
            CurrentIp = if ($rt.PSObject.Properties.Name -contains "static_ip") { [string]$rt.static_ip } else { "" }
        }) | Out-Null
    }

    return [pscustomobject]@{
        HostCidr       = [string]$hostNat.Cidr
        HostAddress    = [string]$hostNat.Address
        HostSource     = [string]$hostNat.Source
        HostInterface  = [string]$hostNat.InterfaceAlias
        Prefix         = [int]$hostNat.Prefix
        Gateway        = $gateway
        Dns            = @($gateway, "1.1.1.1")
        RuntimePlans   = @($runtimePlans)
        LocalConfigPath = Join-Path (Get-ProjectRoot) "configs\local.json"
    }
}

function Format-LocalNetworkValue {
    param($Value)

    if ($null -eq $Value) {
        return "(not set)"
    }

    if ($Value -is [array]) {
        $items = @($Value | Where-Object { $null -ne $_ -and "$_".Length -gt 0 })
        if ($items.Count -eq 0) {
            return "(not set)"
        }
        return ($items -join ", ")
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return "(not set)"
    }
    return $text
}

function New-LocalNetworkChange {
    param(
        [string]$Path,
        $Current,
        $Target
    )

    return [pscustomobject]@{
        Path    = $Path
        Current = (Format-LocalNetworkValue $Current)
        Target  = (Format-LocalNetworkValue $Target)
    }
}

function Get-LocalNetworkChangeSet {
    param([object]$NetworkPlan)

    $config = Get-PlatformConfig
    $topology = Get-TopologyConfig
    $nat = $config.network.vmware_nat
    $changes = [System.Collections.Generic.List[object]]::new()

    $changes.Add((New-LocalNetworkChange -Path "platform.network.mode" -Current $config.network.mode -Target "static")) | Out-Null
    $changes.Add((New-LocalNetworkChange -Path "platform.network.vmware_nat.cidr" -Current $nat.cidr -Target $NetworkPlan.HostCidr)) | Out-Null
    $changes.Add((New-LocalNetworkChange -Path "platform.network.vmware_nat.prefix" -Current $nat.prefix -Target $NetworkPlan.Prefix)) | Out-Null
    $changes.Add((New-LocalNetworkChange -Path "platform.network.vmware_nat.gateway" -Current $nat.gateway -Target $NetworkPlan.Gateway)) | Out-Null
    $changes.Add((New-LocalNetworkChange -Path "platform.network.vmware_nat.dns" -Current @($nat.dns) -Target @($NetworkPlan.Dns))) | Out-Null

    foreach ($runtimePlan in @($NetworkPlan.RuntimePlans)) {
        $runtimeProperty = $topology.PSObject.Properties[$runtimePlan.Name]
        $rt = if ($runtimeProperty) { $runtimeProperty.Value } else { $null }
        $currentIp = if ($rt -and $rt.PSObject.Properties.Name -contains "static_ip") { $rt.static_ip } else { "" }
        $changes.Add((New-LocalNetworkChange -Path "topology.$($runtimePlan.Name).static_ip" -Current $currentIp -Target $runtimePlan.StaticIp)) | Out-Null
    }

    return @($changes)
}

function Get-ChangedLocalNetworkFields {
    param([object[]]$Changes)

    return @($Changes | Where-Object { $_.Current -ne $_.Target })
}

function Write-LocalNetworkChangeSet {
    param([object[]]$Changes)

    $changed = @(Get-ChangedLocalNetworkFields -Changes $Changes)
    Write-UIHost -English "  Proposed local config changes:" -Chinese "  建议的本机配置变更:" -ForegroundColor DarkGray
    if ($changed.Count -eq 0) {
        Write-UIHost -English "    none; local ADP configuration already matches detected host VMnet8." -Chinese "    无；本机 ADP 配置已匹配探测到的 host VMnet8。" -ForegroundColor DarkGray
        return
    }

    foreach ($change in $changed) {
        Write-Host "    $($change.Path):" -ForegroundColor DarkGray
        Write-Host "      $($change.Current) -> $($change.Target)" -ForegroundColor DarkGray
    }
}

function Backup-LocalNetworkConfig {
    param([string]$LocalConfigPath)

    if (-not (Test-Path -LiteralPath $LocalConfigPath)) {
        return ""
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$LocalConfigPath.bak.$timestamp"
    Copy-Item -LiteralPath $LocalConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Set-LocalNetworkConfig {
    param([object]$NetworkPlan)

    $localPath = $NetworkPlan.LocalConfigPath
    if (Test-Path -LiteralPath $localPath) {
        $raw = Get-Content -LiteralPath $localPath -Raw
        $localConfig = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
    } else {
        $localConfig = [pscustomobject]@{}
    }

    $platform = Ensure-JsonObjectProperty -Object $localConfig -Name "platform"
    $network = Ensure-JsonObjectProperty -Object $platform -Name "network"
    $vmwareNat = Ensure-JsonObjectProperty -Object $network -Name "vmware_nat"
    Set-JsonProperty -Object $network -Name "mode" -Value "static"
    Set-JsonProperty -Object $vmwareNat -Name "cidr" -Value $NetworkPlan.HostCidr
    Set-JsonProperty -Object $vmwareNat -Name "prefix" -Value $NetworkPlan.Prefix
    Set-JsonProperty -Object $vmwareNat -Name "gateway" -Value $NetworkPlan.Gateway
    Set-JsonProperty -Object $vmwareNat -Name "dns" -Value @($NetworkPlan.Dns)
    if ($vmwareNat.PSObject.Properties.Name -notcontains "interface_match" -or [string]::IsNullOrWhiteSpace([string]$vmwareNat.interface_match)) {
        Set-JsonProperty -Object $vmwareNat -Name "interface_match" -Value "en*"
    }

    $topology = Ensure-JsonObjectProperty -Object $localConfig -Name "topology"
    foreach ($runtimePlan in @($NetworkPlan.RuntimePlans)) {
        $runtime = Ensure-JsonObjectProperty -Object $topology -Name $runtimePlan.Name
        Set-JsonProperty -Object $runtime -Name "static_ip" -Value $runtimePlan.StaticIp
    }

    $backupPath = Backup-LocalNetworkConfig -LocalConfigPath $localPath
    $json = $localConfig | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $localPath -Value $json -Encoding utf8
    return $backupPath
}

function Invoke-ConfigureLocalNetwork {
    param([switch]$ApplyChanges)

    $plan = Get-VMwareLocalNetworkPlan
    $config = Get-PlatformConfig
    $nat = $config.network.vmware_nat
    $changes = @(Get-LocalNetworkChangeSet -NetworkPlan $plan)

    Write-UIHost -English "Local VMware NAT override plan..." -Chinese "本机 VMware NAT 覆盖计划..." -ForegroundColor Yellow
    Write-UIHost -English "  Host VMnet8: $($plan.HostCidr) ($($plan.HostAddress), $($plan.HostSource))" -Chinese "  Host VMnet8: $($plan.HostCidr) ($($plan.HostAddress), $($plan.HostSource))" -ForegroundColor DarkGray
    Write-UIHost -English "  Local config: $($plan.LocalConfigPath)" -Chinese "  本机配置: $($plan.LocalConfigPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  Current configured NAT: $($nat.cidr), gateway $($nat.gateway)" -Chinese "  当前配置 NAT: $($nat.cidr), gateway $($nat.gateway)" -ForegroundColor DarkGray
    Write-UIHost -English "  Target local NAT:      $($plan.HostCidr), gateway $($plan.Gateway)" -Chinese "  目标本机 NAT: $($plan.HostCidr), gateway $($plan.Gateway)" -ForegroundColor DarkGray
    Write-UIHost -English "  Target DNS:            $(@($plan.Dns) -join ', ')" -Chinese "  目标 DNS:      $(@($plan.Dns) -join ', ')" -ForegroundColor DarkGray
    Write-UIHost -English "  Runtime static IPs:" -Chinese "  运行时 static IP:" -ForegroundColor DarkGray
    foreach ($runtimePlan in @($plan.RuntimePlans)) {
        Write-Host "    $($runtimePlan.Name): $($runtimePlan.CurrentIp) -> $($runtimePlan.StaticIp)" -ForegroundColor DarkGray
    }
    Write-LocalNetworkChangeSet -Changes $changes
    Write-UIHost -English "  Preserved: unrelated configs\local.json fields are left unchanged." -Chinese "  保留: configs\local.json 中无关字段保持不变。" -ForegroundColor DarkGray
    Write-UIHost -English "  Not changed: VMware VMnet8, VM files, guest networking, SSH, sync sessions, and runtimes." -Chinese "  不会修改: VMware VMnet8、VM 文件、guest 网络、SSH、sync session 和运行时。" -ForegroundColor DarkGray
    Write-UIHost -English "  Alternative: keep ADP's configured subnet and change VMware VMnet8 in Virtual Network Editor to match it." -Chinese "  替代方案: 保留 ADP 配置的网段，并在 VMware Virtual Network Editor 中修改 VMnet8 使其匹配。" -ForegroundColor DarkGray

    if (-not $ApplyChanges) {
        Write-UIHost -English "  Plan only: configs\local.json will not be changed." -Chinese "  仅预览：不会修改 configs\local.json。" -ForegroundColor Cyan
        Write-UIHost -English "  No files changed." -Chinese "  未修改任何文件。" -ForegroundColor Cyan
        Write-UIHost -English "  To apply this local override: .\cli\adp.ps1 network configure-local -Apply" -Chinese "  如要应用该本机覆盖: .\cli\adp.ps1 network configure-local -Apply" -ForegroundColor DarkGray
        Write-UIHost -English "  Then rerun: .\cli\adp.ps1 doctor -FirstRun" -Chinese "  然后重新运行: .\cli\adp.ps1 doctor -FirstRun" -ForegroundColor DarkGray
        return
    }

    $backupPath = Set-LocalNetworkConfig -NetworkPlan $plan
    Write-UIHost -English "  Updated configs\local.json with host VMnet8 NAT settings." -Chinese "  已用 host VMnet8 NAT 设置更新 configs\local.json。" -ForegroundColor Green
    if ($backupPath) {
        Write-UIHost -English "  Backup: $backupPath" -Chinese "  备份: $backupPath" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  Backup: none; configs\local.json did not exist before apply." -Chinese "  备份: 无；apply 前 configs\local.json 不存在。" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  Next: .\cli\adp.ps1 doctor -FirstRun" -Chinese "  下一步: .\cli\adp.ps1 doctor -FirstRun" -ForegroundColor DarkGray
    Write-UIHost -English "  Then: .\cli\adp.ps1 up <runtime> -Plan" -Chinese "  然后: .\cli\adp.ps1 up <runtime> -Plan" -ForegroundColor DarkGray
}

function Get-ConfiguredNetwork {
    param([string]$TargetRuntime)

    $config = Get-PlatformConfig
    $rt = Get-RuntimeConfig $TargetRuntime

    if (-not $config.network -or $config.network.mode -ne "static") {
        throw "Static networking is not enabled. Set platform.json network.mode to 'static'."
    }

    if ([string]::IsNullOrWhiteSpace($rt.static_ip)) {
        throw "Runtime '$TargetRuntime' has no static_ip in topology.json."
    }

    $nat = $config.network.vmware_nat
    if (-not $nat) {
        throw "platform.json network.vmware_nat is required."
    }

    return [pscustomobject]@{
        Address        = $rt.static_ip
        Prefix         = if ($nat.prefix) { [int]$nat.prefix } else { 24 }
        Gateway        = $nat.gateway
        Dns            = @($nat.dns)
        InterfaceMatch = if ($nat.interface_match) { $nat.interface_match } else { "en*" }
    }
}

function New-NetplanConfig {
    param([object]$Network)

    $dns = (@($Network.Dns) | Where-Object { $_ }) -join ", "
    if (-not $dns) {
        $dns = $Network.Gateway
    }

    return @"
network:
  version: 2
  renderer: networkd
  ethernets:
    adp0:
      match:
        name: "$($Network.InterfaceMatch)"
      dhcp4: false
      dhcp6: false
      addresses:
        - $($Network.Address)/$($Network.Prefix)
      routes:
        - to: default
          via: $($Network.Gateway)
      nameservers:
        addresses: [$dns]
"@
}

function Invoke-SSH {
    param(
        [string]$HostAddress,
        [string]$Command
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=10 `
        -o BatchMode=yes `
        "adp@$HostAddress" `
        $Command
}

function Copy-File {
    param(
        [string]$HostAddress,
        [string]$LocalPath,
        [string]$RemotePath
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    & scp -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        $LocalPath `
        "adp@${HostAddress}:$RemotePath"
}

function Test-RuntimeSSH {
    param([string]$HostAddress)

    $result = Invoke-SSH -HostAddress $HostAddress -Command "echo ok" 2>$null
    return ($LASTEXITCODE -eq 0 -and $result -eq "ok")
}

function Get-NetworkSeedNetwork {
    param([string]$TargetRuntime)

    $vmStore = Resolve-Path "vm_store"
    $seedUserData = Join-Path $vmStore "seeds\$TargetRuntime\user-data"
    if (-not (Test-Path -LiteralPath $seedUserData)) {
        return $null
    }

    $text = Get-Content -LiteralPath $seedUserData -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $address = ""
    $prefix = ""
    $gateway = ""
    if ($text -match '(?m)^\s*-\s*((?:\d{1,3}\.){3}\d{1,3})/(\d{1,2})\s*$') {
        $address = $matches[1]
        $prefix = $matches[2]
    }
    if ($text -match '(?m)^\s*via:\s*((?:\d{1,3}\.){3}\d{1,3})\s*$') {
        $gateway = $matches[1]
    }

    if (-not $address -and -not $gateway) {
        return $null
    }

    return [pscustomobject]@{
        Address = $address
        Prefix  = $prefix
        Gateway = $gateway
        Path    = $seedUserData
    }
}

function Wait-RuntimeSSH {
    param(
        [string]$HostAddress,
        [int]$TimeoutSeconds = 120
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-RuntimeSSH -HostAddress $HostAddress) {
            return $true
        }
        Start-Sleep -Seconds 5
    }

    return $false
}

function Apply-RuntimeNetwork {
    param(
        [string]$TargetRuntime,
        [switch]$PlanOnly
    )

    if (-not (Test-RuntimeExists $TargetRuntime)) {
        throw "Unknown runtime: $TargetRuntime"
    }

    $rt = Get-RuntimeConfig $TargetRuntime
    $network = Get-ConfiguredNetwork -TargetRuntime $TargetRuntime
    $netplan = New-NetplanConfig -Network $network
    $seedNetwork = Get-NetworkSeedNetwork -TargetRuntime $TargetRuntime

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$TargetRuntime"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"
    if (-not (Test-Path $vmxPath)) {
        throw "VM not found for runtime '$TargetRuntime'. Run: adp up $TargetRuntime"
    }

    $status = Get-VMStatus $vmxPath

    $currentIp = $null
    try {
        $currentIp = Get-VMIP $vmxPath
    } catch {}

    if (-not $currentIp -and $seedNetwork -and $seedNetwork.Address -and $seedNetwork.Address -ne $network.Address) {
        $currentIp = $seedNetwork.Address
    }

    if (-not $currentIp) {
        $currentIp = $network.Address
    }

    Write-UIHost -English "Applying static network for '$TargetRuntime'..." -Chinese "正在为 '$TargetRuntime' 应用静态网络..." -ForegroundColor Yellow
    Write-UIHost -English "  VM status: $status" -Chinese "  VM 状态: $status" -ForegroundColor DarkGray
    Write-UIHost -English "  Current: $currentIp" -Chinese "  当前: $currentIp" -ForegroundColor DarkGray
    Write-UIHost -English "  Target:  $($network.Address)/$($network.Prefix) via $($network.Gateway)" -Chinese "  目标: $($network.Address)/$($network.Prefix) via $($network.Gateway)" -ForegroundColor DarkGray

    if ($PlanOnly) {
        Write-UIHost -English "  Plan only: no guest files will be changed." -Chinese "  仅预览：不会修改任何 guest 文件。" -ForegroundColor Cyan
        if ($seedNetwork -and $seedNetwork.Address -and $seedNetwork.Address -ne $network.Address) {
            Write-Host "  Network drift detected: seed uses $($seedNetwork.Address)/$($seedNetwork.Prefix), target is $($network.Address)/$($network.Prefix)." -ForegroundColor Yellow
            Write-Host "  This plan covers the in-place guest netplan fix path only." -ForegroundColor Yellow
            Write-Host "  If the VM can be recreated, preview rebuild first: adp destroy $TargetRuntime -Plan" -ForegroundColor DarkGray
            Write-Host "  If SSH is only reachable through the seed-era network, use an admin-only temporary host-route workaround outside ADP, then rerun this command." -ForegroundColor DarkGray
            Write-Host "  ADP will not add, change, or remove host routes automatically." -ForegroundColor DarkGray
        }
        Write-Host "  Would verify SSH at: $currentIp" -ForegroundColor DarkGray
        Write-Host "  Would upload: /tmp/99-adp-static.yaml" -ForegroundColor DarkGray
        Write-Host "  Would install: /etc/netplan/99-adp-static.yaml" -ForegroundColor DarkGray
        Write-Host "  Would wait for target SSH: $($network.Address)" -ForegroundColor DarkGray
        Write-Host "  Would update Mutagen SSH alias: adp-os-adp-$TargetRuntime" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-RuntimeSSH -HostAddress $currentIp)) {
        throw "SSH is not reachable at current address $currentIp"
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempFile -Value $netplan -Encoding ascii
        Copy-File -HostAddress $currentIp -LocalPath $tempFile -RemotePath "/tmp/99-adp-static.yaml" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to upload netplan config to $TargetRuntime"
        }

        $applyCommand = "printf '%s\n' 'adp' | sudo -S bash -lc 'mv /tmp/99-adp-static.yaml /etc/netplan/99-adp-static.yaml && chmod 600 /etc/netplan/99-adp-static.yaml && netplan generate && (sleep 2; netplan apply) >/tmp/adp-netplan-apply.log 2>&1 &'"
        Invoke-SSH -HostAddress $currentIp -Command $applyCommand 2>$null | Out-Null
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Wait-RuntimeSSH -HostAddress $network.Address -TimeoutSeconds 120)) {
        throw "Static IP $($network.Address) did not become reachable for '$TargetRuntime'"
    }

    try {
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
        $sessionName = "adp-$TargetRuntime"
        $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
        Set-MutagenSSHHostConfig `
            -HostAlias "adp-os-$sessionName" `
            -SSHHost $network.Address `
            -SSHUser "adp" `
            -SSHPort $rt.ssh_port `
            -SSHKeyPath $sshKeyPath | Out-Null
    } catch {
        Write-WarnLog -Message "Static IP applied, but Mutagen SSH alias update failed: $_" -Component "cli.network"
    }

    Write-Host "  Static IP active: $($network.Address)" -ForegroundColor Green
}

Write-Host ""
Write-UIHost -English "ADP-OS Network" -Chinese "ADP-OS 网络" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($SubCommand -in @("configure-local", "local")) {
    try {
        Invoke-ConfigureLocalNetwork -ApplyChanges:$Apply
    } catch {
        Write-ErrorLog -Message "local network configuration failed: $_" -Component "cli.network"
        exit 1
    }
    return
}

$targets = if ($RuntimeName -eq "all") { Get-AllRuntimeNames } else { @($RuntimeName) }

Initialize-VMware | Out-Null
Initialize-SSH | Out-Null

foreach ($target in $targets) {
    try {
        Apply-RuntimeNetwork -TargetRuntime $target -PlanOnly:$Plan
    } catch {
        Write-ErrorLog -Message "$target network apply failed: $_" -Component "cli.network"
        exit 1
    }
}
