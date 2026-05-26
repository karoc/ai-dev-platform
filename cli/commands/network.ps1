# ADP-OS Network Command
# Apply configured runtime networking to existing VMs.

param(
    [string]$SubCommand,
    [string]$RuntimeName
)

$ErrorActionPreference = "Stop"

if (-not $SubCommand -or $SubCommand -ne "apply") {
    Write-ErrorLog -Message "Usage: adp network apply <runtime|all>" -Component "cli.network"
    exit 1
}

if (-not $RuntimeName) {
    Write-ErrorLog -Message "Usage: adp network apply <runtime|all>" -Component "cli.network"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "adapters\windows\ssh\ssh.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

Initialize-VMware | Out-Null
Initialize-SSH | Out-Null

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
    param([string]$TargetRuntime)

    if (-not (Test-RuntimeExists $TargetRuntime)) {
        throw "Unknown runtime: $TargetRuntime"
    }

    $rt = Get-RuntimeConfig $TargetRuntime
    $network = Get-ConfiguredNetwork -TargetRuntime $TargetRuntime
    $netplan = New-NetplanConfig -Network $network

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

    if (-not $currentIp) {
        $currentIp = $network.Address
    }

    Write-Host "Applying static network for '$TargetRuntime'..." -ForegroundColor Yellow
    Write-Host "  VM status: $status" -ForegroundColor DarkGray
    Write-Host "  Current: $currentIp" -ForegroundColor DarkGray
    Write-Host "  Target:  $($network.Address)/$($network.Prefix) via $($network.Gateway)" -ForegroundColor DarkGray

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
Write-Host "ADP-OS Network" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$targets = if ($RuntimeName -eq "all") { Get-AllRuntimeNames } else { @($RuntimeName) }

foreach ($target in $targets) {
    try {
        Apply-RuntimeNetwork -TargetRuntime $target
    } catch {
        Write-ErrorLog -Message "$target network apply failed: $_" -Component "cli.network"
        exit 1
    }
}
