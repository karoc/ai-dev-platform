# ADP-OS Doctor Command
# System diagnostics — checks all dependencies and platform health

param(
    [switch]$FirstRun,
    [switch]$FixMutagen,
    [switch]$Plan
)

Write-InfoLog -Message (Get-UIText -English "Running: adpos doctor" -Chinese "正在运行: adpos doctor") -Component "cli.doctor"

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\resource-conflicts.ps1")

if ($Plan -and -not $FixMutagen) {
    Write-ErrorLog -Message (Get-UIText -English "-Plan is only supported with -FixMutagen." -Chinese "-Plan 仅支持与 -FixMutagen 一起使用。") -Component "cli.doctor"
    exit 1
}

Write-Host ""
Write-UIHost -English "ADP-OS Doctor — System Diagnostics" -Chinese "ADP-OS Doctor — 系统诊断" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$script:doctorIssues = @()
$script:doctorOk = @()
$script:doctorInfo = @()

function Test-Check {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ""
    )

    if ($Condition) {
        Write-Host "  [OK]    $Name $Detail" -ForegroundColor Green
        $script:doctorOk += $Name
    } else {
        Write-Host "  [FAIL]  $Name $Detail" -ForegroundColor Red
        $script:doctorIssues += $Name
    }
}

function Write-InfoCheck {
    param(
        [string]$Name,
        [string]$Detail = ""
    )

    Write-Host "  [INFO]  $Name $Detail" -ForegroundColor DarkGray
    $script:doctorInfo += $Name
}

function Test-IPv4InCidr {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($Cidr)) {
        return $false
    }

    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) {
        return $false
    }

    $ip = $null
    $network = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) {
        return $false
    }
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$network)) {
        return $false
    }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $network.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt 32) {
        return $false
    }

    $ipBytes = $ip.GetAddressBytes()
    $networkBytes = $network.GetAddressBytes()
    [array]::Reverse($ipBytes)
    [array]::Reverse($networkBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
    $networkInt = [BitConverter]::ToUInt32($networkBytes, 0)
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]::MaxValue -shl (32 - $prefix) }

    return (($ipInt -band $mask) -eq ($networkInt -band $mask))
}

function Test-RuntimeSSHReachable {
    param(
        [string]$HostAddress,
        [int]$Port = 22
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    if (-not (Test-Path $keyPath)) {
        return $false
    }

    $result = & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=5 `
        -o BatchMode=yes `
        -p $Port `
        "adp@$HostAddress" `
        "echo ok" 2>$null

    return ($LASTEXITCODE -eq 0 -and $result -eq "ok")
}

function Get-DoctorSeedNetwork {
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

function Write-NetworkDriftRemediation {
    param(
        [string]$TargetRuntime,
        [object]$SeedNetwork,
        [string]$ConfiguredIp
    )

    Write-UIHost -English "  [INFO]  Remediation options for $TargetRuntime network drift:" -Chinese "  [INFO]  $TargetRuntime 网络漂移修复选项:" -ForegroundColor DarkGray
    Write-UIHost -English "          1. Rebuild when the VM can be recreated: adpos destroy $TargetRuntime -Plan, then adpos up $TargetRuntime." -Chinese "          1. 如果 VM 可以重建：先运行 adpos destroy $TargetRuntime -Plan，再用 adpos up $TargetRuntime 重建。" -ForegroundColor DarkGray
    Write-UIHost -English "          2. In-place guest fix when the seed-era address is reachable: adpos network apply $TargetRuntime -Plan." -Chinese "          2. 如果 seed-era 地址可连接：运行 adpos network apply $TargetRuntime -Plan 预览 guest 内修复。" -ForegroundColor DarkGray
    Write-UIHost -English "          3. Admin-only temporary host-route workaround only to regain SSH to $($SeedNetwork.Address); ADP will not apply host routes automatically." -Chinese "          3. 仅管理员可用的临时 host-route workaround 用于恢复到 $($SeedNetwork.Address) 的 SSH；ADP 不会自动应用 host routes。" -ForegroundColor DarkGray
    Write-UIHost -English "          Seed-era network: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); target: $ConfiguredIp." -Chinese "          Seed-era 网络: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); 目标: $ConfiguredIp。" -ForegroundColor DarkGray
}

function Test-WSLCommand {
    param([string]$Command)

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $false
    }

    $null = & $wsl.Source bash -lc "command -v $Command >/dev/null 2>&1" 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-ISOReasonable {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $item = Get-Item $Path
    return ($item.Length -ge 1GB -and $item.Extension -ieq ".iso")
}

# --- Platform ---
Write-UIHost -English "Platform:" -Chinese "平台:" -ForegroundColor Yellow
$platform = Get-Platform
Test-Check -Name "Platform Detection" -Condition ($platform -eq "windows") -Detail "($platform)"

$osInfo = Get-CimInstance Win32_OperatingSystem
Test-Check -Name "Windows Version" -Condition ([Version]$osInfo.Version -ge [Version]"10.0") -Detail "($($osInfo.Caption))"

Test-Check -Name "PowerShell 7+" -Condition ($PSVersionTable.PSVersion.Major -ge 7) -Detail "(v$($PSVersionTable.PSVersion))"

# --- Configuration ---
Write-Host ""
Write-UIHost -English "Configuration:" -Chinese "配置:" -ForegroundColor Yellow
$localConfigStatus = Get-LocalConfigStatus
if ($localConfigStatus.Exists) {
    if ($localConfigStatus.Empty) {
        Test-Check -Name "local config" -Condition $true -Detail "(empty, ignored: $($localConfigStatus.Path))"
    } elseif ($localConfigStatus.Applied) {
        Test-Check -Name "local config" -Condition $true -Detail "(applied sections: $($localConfigStatus.Sections -join ', '))"
    } else {
        Test-Check -Name "local config" -Condition $true -Detail "(present, no supported sections)"
        Write-UIHost -English "  [INFO]  Supported sections: platform, topology, sync_profiles" -Chinese "  [INFO]  支持的配置段: platform, topology, sync_profiles" -ForegroundColor DarkGray
    }
} else {
    Test-Check -Name "local config" -Condition $true -Detail "(not present, using committed defaults)"
    Write-UIHost -English "  [INFO]  Optional: copy configs\local.example.json to configs\local.json for machine-local overrides." -Chinese "  [INFO]  可选：复制 configs\local.example.json 到 configs\local.json，用于本机覆盖配置。" -ForegroundColor DarkGray
}
if ($localConfigStatus.Exists -and -not $localConfigStatus.Empty) {
    $unsupportedSections = @($localConfigStatus.UnsupportedSections)
    Test-Check -Name "local config supported sections" -Condition ($unsupportedSections.Count -eq 0) -Detail "$(if ($unsupportedSections.Count -gt 0) { '(' + ($unsupportedSections -join ', ') + ')' } else { '(platform, topology, sync_profiles)' })"
}

$config = Get-PlatformConfig
$topology = Get-TopologyConfig
$commandContext = Get-ADPCheckoutCommandContext
if ($commandContext.BindingStatus -eq "current-checkout") {
    Test-Check -Name "global adpos binding" -Condition $true -Detail "(current checkout)"
} elseif ($commandContext.BindingStatus -eq "different-checkout") {
    Write-InfoCheck -Name "global adpos binding" -Detail "(points to another checkout: $($commandContext.GlobalHome); use .\adpos.cmd here)"
} else {
    Write-InfoCheck -Name "global adpos binding" -Detail "($($commandContext.BindingStatus); local command: .\adpos.cmd)"
}
Test-Check -Name "platform paths" -Condition ($config.paths.workspace_root -and $config.paths.iso_cache -and $config.paths.vm_store) -Detail "(workspace_root, iso_cache, vm_store)"
Test-Check -Name "platform defaults" -Condition ($config.defaults.ubuntu_iso -and $config.defaults.admin_user -and $config.defaults.admin_password) -Detail "(ubuntu_iso, admin_user, admin_password)"
Test-Check -Name "network mode" -Condition ($config.network.mode -eq "static") -Detail "($($config.network.mode))"

if ($config.network.vmware_nat) {
    $nat = $config.network.vmware_nat
    Test-Check -Name "VMware NAT config" -Condition ($nat.cidr -and $nat.gateway -and $nat.prefix) -Detail "($($nat.cidr), gateway $($nat.gateway), prefix $($nat.prefix))"
    if ($nat.cidr -and $nat.gateway) {
        Test-Check -Name "VMware NAT gateway range" -Condition (Test-IPv4InCidr -Address $nat.gateway -Cidr $nat.cidr) -Detail "($($nat.gateway) in $($nat.cidr))"
    }
    $hostNat = Test-VMwareNatConfigMatchesHost -ConfiguredNat $nat
    if ($hostNat.Checked) {
        Test-Check -Name "VMware NAT host match" -Condition $hostNat.Matches -Detail "(configured $($hostNat.ConfiguredCidr), host $($hostNat.HostCidr) via $($hostNat.HostSource))"
        Test-Check -Name "VMware NAT gateway host range" -Condition $hostNat.GatewayInHostCidr -Detail "($($nat.gateway) in host $($hostNat.HostCidr))"
        if (-not $hostNat.Matches) {
            Write-UIHost -English "  [INFO]  ADP configuration and host VMware NAT disagree; choose one remediation before creating VMs." -Chinese "  [INFO]  ADP 配置与主机 VMware NAT 不一致；创建 VM 前需要先选择一种修复方式。" -ForegroundColor DarkGray
            Write-UIHost -English "  [INFO]  Option A: align ADP local overrides: adpos network configure-local -Plan, then adpos network configure-local -Apply" -Chinese "  [INFO]  方案 A：将 ADP 本机覆盖对齐到当前主机：adpos network configure-local -Plan，然后 adpos network configure-local -Apply" -ForegroundColor DarkGray
            Write-UIHost -English "  [INFO]  Option B: keep ADP's configured subnet and change VMware VMnet8 to $($hostNat.ConfiguredCidr) in Virtual Network Editor." -Chinese "  [INFO]  方案 B：保留 ADP 配置的网段，并在 VMware Virtual Network Editor 中把 VMnet8 改为 $($hostNat.ConfiguredCidr)。" -ForegroundColor DarkGray
        }
    } else {
        Write-InfoCheck -Name "VMware NAT host match" -Detail "($($hostNat.Reason); confirm VMnet8/NAT subnet in VMware Virtual Network Editor)"
    }
    Write-InfoCheck -Name "VMware NAT prerequisites" -Detail "(ADP compares configured NAT with host VMnet8 when detectable; override configs\local.json if it differs)"
}

# --- VMware ---
Write-Host ""
Write-UIHost -English "VMware:" -Chinese "VMware:" -ForegroundColor Yellow
# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
$vmStore = Resolve-Path "vm_store"
try {
    Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null
    $vmwareOk = $true
} catch {
    $vmwareOk = $false
}
$runningVmxPaths = @()
Test-Check -Name "vmrun.exe" -Condition $vmwareOk

if ($vmwareOk) {
    $info = Get-ProviderInfo
    if ($info.Success) {
        Test-Check -Name "vmrun path" -Condition $true -Detail "(Provider: $($info.Data.Name))"
    }
    $providerCaps = Get-ProviderCapabilities
    $diskManagerOk = ($providerCaps.Success)
    Test-Check -Name "vmware-vdiskmanager.exe" -Condition $diskManagerOk -Detail "(via Provider)"

    $isoCreator = Find-ISOCreator
    $isoCreatorDetail = if ($isoCreator) { "$($isoCreator.Type): $($isoCreator.Path)" } else { "missing" }
    Test-Check -Name "seed ISO creator" -Condition ($null -ne $isoCreator) -Detail "($isoCreatorDetail)"

    $isoRemasterTool = Find-ISORemasterTool
    $isoRemasterDetail = if ($isoRemasterTool) { "$($isoRemasterTool.Type): $($isoRemasterTool.Path)" } else { "missing" }
    Test-Check -Name "install ISO remaster" -Condition ($null -ne $isoRemasterTool) -Detail "($isoRemasterDetail)"
    if (-not $isoRemasterTool) {
        Write-UIHost -English "  [INFO]  Install xorriso natively or in WSL:" -Chinese "  [INFO]  在本地或 WSL 中安装 xorriso:" -ForegroundColor DarkGray
        Write-UIHost -English "          wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`"" -Chinese "          wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`"" -ForegroundColor DarkGray
    }

    try {
        $vms = Get-RunningVMs
        $runningVmxPaths = @($vms | ForEach-Object { Normalize-VMXPath -VmxPath $_ })
        Test-Check -Name "VMware running VMs" -Condition $true -Detail "($($vms.Count) running)"
    } catch {
        Test-Check -Name "VMware accessible" -Condition $false -Detail "($_)"
    }
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
Test-Check -Name "WSL" -Condition ($null -ne $wsl) -Detail "$(if ($wsl) { '(' + $wsl.Source + ')' } else { '(wsl.exe not found)' })"
Test-Check -Name "WSL xorriso" -Condition (Test-WSLCommand -Command "xorriso") -Detail "(required for Ubuntu autoinstall ISO remastering)"

# --- Mutagen ---
Write-Host ""
Write-UIHost -English "Mutagen:" -Chinese "Mutagen:" -ForegroundColor Yellow
$mutagenPath = Find-Mutagen -ProjectRoot (Get-ProjectRoot)
$hasMutagen = $null -ne $mutagenPath
Test-Check -Name "mutagen" -Condition $hasMutagen
if (-not $hasMutagen) {
    Write-UIHost -English "  [INFO]  Install by placing mutagen.exe at .tools\mutagen\mutagen.exe or adding it to PATH." -Chinese "  [INFO]  安装方式：将 mutagen.exe 放到 .tools\mutagen\mutagen.exe，或加入 PATH。" -ForegroundColor DarkGray
    Write-UIHost -English "  [INFO]  Or run: adpos doctor -FixMutagen -Plan" -Chinese "  [INFO]  或运行：adpos doctor -FixMutagen -Plan" -ForegroundColor DarkGray
}

if ($hasMutagen) {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    $mutagenVersion = Get-MutagenVersion -Path $mutagenPath
    $mutagenVersionOk = Test-MutagenVersionSupported -VersionText $mutagenVersion
    Test-Check -Name "mutagen version" -Condition $mutagenVersionOk -Detail "($mutagenVersion, $mutagenPath)"
    if (-not $mutagenVersionOk) {
        Write-UIHost -English "  [INFO]  ADP-OS is tested with Mutagen 0.18.x." -Chinese "  [INFO]  ADP-OS 已测试 Mutagen 0.18.x。" -ForegroundColor DarkGray
        Write-UIHost -English "  [INFO]  To install the tested local version, run: adpos doctor -FixMutagen -Plan" -Chinese "  [INFO]  安装测试版本，请运行：adpos doctor -FixMutagen -Plan" -ForegroundColor DarkGray
    }
}

if ($FixMutagen) {
    Write-Host ""
    Write-UIHost -English "Mutagen remediation:" -Chinese "Mutagen 修复:" -ForegroundColor Cyan
    $remediationPlan = Install-LocalMutagen -ProjectRoot (Get-ProjectRoot) -Plan
    if ($Plan) {
        $remediation = $remediationPlan
        Write-UIHost -English "  Plan only: no files will be downloaded, expanded, or overwritten." -Chinese "  仅预览：不会下载、解压或覆盖任何文件。" -ForegroundColor Yellow
        Write-UIHost -English "  Version: $($remediation.Version)" -Chinese "  版本: $($remediation.Version)" -ForegroundColor DarkGray
        Write-UIHost -English "  Download: $($remediation.Url)" -Chinese "  下载: $($remediation.Url)" -ForegroundColor DarkGray
        if ($remediation.ConfiguredArchivePath) {
            Write-UIHost -English "  Offline archive: $($remediation.ConfiguredArchivePath)" -Chinese "  离线归档: $($remediation.ConfiguredArchivePath)" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "  Offline archive: not configured; place the archive at $($remediation.ZipPath) to avoid downloading." -Chinese "  离线归档: 未配置；将归档放到 $($remediation.ZipPath) 可跳过下载。" -ForegroundColor DarkGray
        }
        Write-UIHost -English "  Archive:  $($remediation.ZipPath)" -Chinese "  归档:  $($remediation.ZipPath)" -ForegroundColor DarkGray
        Write-UIHost -English "  Target:   $($remediation.TargetPath)" -Chinese "  目标:   $($remediation.TargetPath)" -ForegroundColor DarkGray
        Write-UIHost -English "  SHA256:   $(if ($remediation.Sha256) { $remediation.Sha256 } else { 'not configured; archive hash verification will be skipped' })" -Chinese "  SHA256:   $(if ($remediation.Sha256) { $remediation.Sha256 } else { '未配置；将跳过归档哈希校验' })" -ForegroundColor DarkGray
        Write-UIHost -English "  Timeout:  connection=$($remediation.ConnectionTimeoutSeconds)s hard=$($remediation.DownloadTimeoutSeconds)s" -Chinese "  超时:  连接=$($remediation.ConnectionTimeoutSeconds)s 硬性=$($remediation.DownloadTimeoutSeconds)s" -ForegroundColor DarkGray
        Write-UIHost -English "  Local overrides: platform.tools.mutagen.download_url, archive_path, sha256, connection_timeout_seconds, download_timeout_seconds" -Chinese "  本机覆盖: platform.tools.mutagen.download_url, archive_path, sha256, connection_timeout_seconds, download_timeout_seconds" -ForegroundColor DarkGray
        Write-UIHost -English "  To install: adpos doctor -FixMutagen" -Chinese "  安装: adpos doctor -FixMutagen" -ForegroundColor DarkGray
    } else {
        try {
            $remediation = Install-LocalMutagen -ProjectRoot (Get-ProjectRoot)
        } catch {
            $reason = $_.Exception.Message
            Write-ErrorLog -Message "Mutagen remediation failed: $reason" -Component "cli.doctor"
            Write-UIHost -English "  Mutagen remediation failed." -Chinese "  Mutagen 修复失败。" -ForegroundColor Red
            Write-UIHost -English "  Reason: $reason" -Chinese "  原因: $reason" -ForegroundColor Red
            Write-UIHost -English "  Retry:  adpos doctor -FixMutagen" -Chinese "  重试:  adpos doctor -FixMutagen" -ForegroundColor DarkGray
            Write-UIHost -English "  Manual: download $($remediationPlan.Url)" -Chinese "  手动: 下载 $($remediationPlan.Url)" -ForegroundColor DarkGray
            Write-UIHost -English "          place it at $($remediationPlan.ZipPath), then rerun the command." -Chinese "          放到 $($remediationPlan.ZipPath)，然后重新运行该命令。" -ForegroundColor DarkGray
            if ($remediationPlan.ConfiguredArchivePath) {
                Write-UIHost -English "  Offline: configured archive path was $($remediationPlan.ConfiguredArchivePath)" -Chinese "  离线: 配置的归档路径为 $($remediationPlan.ConfiguredArchivePath)" -ForegroundColor DarkGray
            }
            Write-UIHost -English "  Verify: set platform.tools.mutagen.sha256 in configs\\local.json to enforce archive hash verification." -Chinese "  校验: 在 configs\\local.json 中设置 platform.tools.mutagen.sha256 来强制归档哈希校验。" -ForegroundColor DarkGray
            Write-UIHost -English "  Or place mutagen.exe directly at: $($remediationPlan.TargetPath)" -Chinese "  或将 mutagen.exe 直接放到: $($remediationPlan.TargetPath)" -ForegroundColor DarkGray
            Write-UIHost -English "  No VMs, sync sessions, SSH config, or configs\local.json were changed by this failed remediation." -Chinese "  本次失败的修复没有修改 VM、sync session、SSH 配置或 configs\local.json。" -ForegroundColor DarkGray
            exit 1
        }

        Write-UIHost -English "  Mutagen installed locally." -Chinese "  Mutagen 已安装到本地。" -ForegroundColor Green
        Write-UIHost -English "  Version: $($remediation.VersionText)" -Chinese "  版本: $($remediation.VersionText)" -ForegroundColor DarkGray
        Write-UIHost -English "  Target:  $($remediation.TargetPath)" -Chinese "  目标:  $($remediation.TargetPath)" -ForegroundColor DarkGray
        Write-UIHost -English "  Archive: $($remediation.ZipPath)" -Chinese "  归档: $($remediation.ZipPath)" -ForegroundColor DarkGray
        $script:doctorIssues = @($script:doctorIssues | Where-Object { $_ -notin @("mutagen", "mutagen version") })
        $script:doctorOk += "mutagen remediation"
    }
}

# --- SSH ---
Write-Host ""
Write-UIHost -English "SSH:" -Chinese "SSH:" -ForegroundColor Yellow
$hasSsh = $null -ne (Get-Command ssh -ErrorAction SilentlyContinue)
Test-Check -Name "OpenSSH Client" -Condition $hasSsh

# --- ISO ---
Write-Host ""
Write-UIHost -English "OS ISO:" -Chinese "OS ISO:" -ForegroundColor Yellow
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$isoCache = Resolve-Path "iso_cache"
$isoPath = Join-Path $isoCache $isoName

if (Test-Path $isoPath) {
    $isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
    Test-Check -Name "ISO present" -Condition $true -Detail "($isoSize GB)"
    Test-Check -Name "ISO shape" -Condition (Test-ISOReasonable -Path $isoPath) -Detail "(.iso and >= 1 GB)"
} else {
    Test-Check -Name "ISO present" -Condition $false -Detail "(not found at $isoPath)"
}

# --- Directories ---
Write-Host ""
Write-UIHost -English "Directories:" -Chinese "目录:" -ForegroundColor Yellow
$workspaceRoot = Resolve-Path "workspace_root"
$vmStore = Resolve-Path "vm_store"
Test-Check -Name "Workspace root" -Condition (Test-Path $workspaceRoot) -Detail "($workspaceRoot)"
Test-Check -Name "VM store" -Condition (Test-Path $vmStore) -Detail "($vmStore)"
Test-Check -Name "Logs" -Condition (Test-Path (Join-Path (Get-ProjectRoot) "logs"))

# --- Runtime topology ---
Write-Host ""
Write-UIHost -English "Runtimes:" -Chinese "运行时:" -ForegroundColor Yellow
$staticIpOwners = @{}
foreach ($name in (Get-AllRuntimeNames)) {
    $rt = $topology.$name
    $profile = Get-OSProfile -OSName $rt.os
    $vmName = "adp-$name"
    $vmPath = Join-Path $vmStore $vmName
    $vmxPath = Join-Path $vmPath "$vmName.vmx"
    $vmdkPath = Join-Path $vmPath "$vmName.vmdk"
    $hasCurrentRuntimeVm = Test-Path -LiteralPath $vmPath

    $topologyOk = ($profile.seedType -eq "cloud-init" -and $rt.ssh_port -eq 22 -and $rt.cpu -gt 0 -and $rt.memory -gt 0 -and $rt.disk -gt 0 -and $rt.workspace -and $rt.sync_profile -and $rt.bootstrap_profile)
    Test-Check -Name "$name topology" -Condition $topologyOk -Detail "($($rt.os), cpu:$($rt.cpu), memory:$($rt.memory), disk:$($rt.disk), ssh:$($rt.ssh_port))"

    if ($rt.static_ip) {
        $ipDuplicate = $staticIpOwners.ContainsKey($rt.static_ip)
        if ($ipDuplicate) {
            Test-Check -Name "$name static IP unique" -Condition $false -Detail "($($rt.static_ip) also used by $($staticIpOwners[$rt.static_ip]))"
        } else {
            $staticIpOwners[$rt.static_ip] = $name
            Test-Check -Name "$name static IP unique" -Condition $true -Detail "($($rt.static_ip))"
        }

        if ($config.network.vmware_nat.cidr) {
            Test-Check -Name "$name static IP range" -Condition (Test-IPv4InCidr -Address $rt.static_ip -Cidr $config.network.vmware_nat.cidr) -Detail "($($rt.static_ip) in $($config.network.vmware_nat.cidr))"
        }
    } else {
        Test-Check -Name "$name static IP" -Condition $false -Detail "(missing)"
    }

    $syncProfile = $null
    try {
        $syncProfile = Get-SyncProfile $rt.sync_profile
        Test-Check -Name "$name sync profile" -Condition ($syncProfile.mode -and $syncProfile.ignore) -Detail "($($rt.sync_profile), $($syncProfile.mode))"
    } catch {
        Test-Check -Name "$name sync profile" -Condition $false -Detail "($($rt.sync_profile): $_)"
    }

    if ($vmwareOk) {
        $resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $name -VmxPath $vmxPath
        $resourceConflict = Get-ADPRuntimeDuplicateConflict -TargetRuntime $name -ManagedVmxPath $vmxPath -RunningVmxPaths $runningVmxPaths
        $duplicateRunningVms = @($resourceConflict.DuplicateVms)
        $hasDuplicateRunningVm = $resourceConflict.HasDuplicateRunningVm
        Test-Check -Name "$name duplicate running VM" -Condition (-not $hasDuplicateRunningVm) -Detail "$(if ($hasDuplicateRunningVm) { '(' + ($duplicateRunningVms.NormalizedVmxPath -join '; ') + ')' } else { '(none)' })"
        if ($hasDuplicateRunningVm) {
            Write-UIHost -English "  [INFO]  Stop or rename stale duplicate ADP VMs before diagnosing SSH or network issues." -Chinese "  [INFO]  排查 SSH 或网络前，请先停止或重命名 stale duplicate ADP VM。" -ForegroundColor DarkGray
            Write-UIHost -English "  [INFO]  Current checkout VMX: $vmxPath" -Chinese "  [INFO]  当前 checkout VMX: $vmxPath" -ForegroundColor DarkGray
            Write-ADPRuntimeResourceConflictGuidance -Profile $resourceProfile -Conflict $resourceConflict -CommandContext $commandContext -Action "doctor diagnosis"
        }
    }

    if (Test-Path $vmPath) {
        Test-Check -Name "$name VMX" -Condition (Test-Path $vmxPath) -Detail "($vmxPath)"
        Test-Check -Name "$name VMDK" -Condition (Test-Path $vmdkPath) -Detail "($vmdkPath)"
        $seedNetwork = Get-DoctorSeedNetwork -TargetRuntime $name
        if ($seedNetwork -and $rt.static_ip) {
            Test-Check -Name "$name seed network drift" -Condition ($seedNetwork.Address -eq $rt.static_ip) -Detail "(seed $($seedNetwork.Address)/$($seedNetwork.Prefix), configured $($rt.static_ip))"
            if ($seedNetwork.Address -ne $rt.static_ip) {
                Write-NetworkDriftRemediation -TargetRuntime $name -SeedNetwork $seedNetwork -ConfiguredIp $rt.static_ip
            }
        } else {
            Write-InfoCheck -Name "$name seed network drift" -Detail "(seed user-data not found or static IP missing)"
        }
        $statusResult = Get-VMStatus -Name $name
        $status = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }
        Test-Check -Name "$name VM status" -Condition ($status -match "running|stopped") -Detail "($status)"
        if ($status -match "running" -and $rt.static_ip) {
            Test-Check -Name "$name SSH reachable" -Condition (Test-RuntimeSSHReachable -HostAddress $rt.static_ip -Port $rt.ssh_port) -Detail "($($rt.static_ip):$($rt.ssh_port))"
        } else {
            Write-InfoCheck -Name "$name SSH reachable" -Detail "(skipped, VM status: $status)"
        }
    } else {
        Write-InfoCheck -Name "$name VM" -Detail "(not created yet: $vmPath)"
    }

    if ($hasMutagen) {
        $sessionName = "adp-$name"
        try {
            $expectedLocalPath = Join-Path $workspaceRoot $rt.workspace
            $expectedRemoteUrl = "adp-os-$sessionName`:/home/adp/workspace"
            $recovery = Get-SyncSessionRecoveryInfo `
                -SessionName $sessionName `
                -ExpectedLocalPath $expectedLocalPath `
                -ExpectedRemoteUrl $expectedRemoteUrl `
                -RuntimeCreated $hasCurrentRuntimeVm `
                -RuntimeName $name

            if (-not $recovery.Exists) {
                Write-InfoCheck -Name "$name Mutagen session" -Detail "(not started: $sessionName)"
            } elseif ($recovery.RecoveryScenario -eq "none") {
                # Healthy or present session
                $syncOk = ($recovery.Health -in @("healthy", "present"))
                if ($hasCurrentRuntimeVm) {
                    Test-Check -Name "$name Mutagen session" -Condition $syncOk -Detail "($sessionName, $($recovery.Health), $($recovery.Detail))"
                    if (-not $syncOk) {
                        Write-UIHost -English "  [INFO]  Remediation: adpos sync stop $name; adpos sync start $name" -Chinese "  [INFO]  修复: adpos sync stop $name; adpos sync start $name" -ForegroundColor DarkGray
                        Write-UIHost -English "  [INFO]  Current local: $($recovery.AlphaUrl); expected: $expectedLocalPath" -Chinese "  [INFO]  当前 local: $($recovery.AlphaUrl); 期望: $expectedLocalPath" -ForegroundColor DarkGray
                        Write-UIHost -English "  [INFO]  Current remote: $($recovery.BetaUrl); expected: $expectedRemoteUrl" -Chinese "  [INFO]  当前 remote: $($recovery.BetaUrl); 期望: $expectedRemoteUrl" -ForegroundColor DarkGray
                    }
                } else {
                    Write-InfoCheck -Name "$name Mutagen session" -Detail "(running session: $sessionName, $($recovery.Health), $($recovery.Detail))"
                }
            } else {
                # Recovery scenario detected
                Write-UIHost -English "  [SYNC]  $($recovery.RecoveryTitle)" -Chinese "  [SYNC]  $($recovery.RecoveryTitle)" -ForegroundColor Yellow
                Write-UIHost -English "  [SYNC]  $($recovery.RecoveryDetail)" -Chinese "  [SYNC]  $($recovery.RecoveryDetail)" -ForegroundColor DarkGray
                foreach ($step in $recovery.RecoverySteps) {
                    Write-UIHost -English "  [SYNC]  → $step" -Chinese "  [SYNC]  → $step" -ForegroundColor DarkGray
                }
                if ($recovery.SafeCleanup) {
                    Write-UIHost -English "  [SYNC]  Stopping the stale session does not delete workspace files on either side." -Chinese "  [SYNC]  停止 stale session 不会删除任何一侧的 workspace 文件。" -ForegroundColor Green
                }
                Write-UIHost -English "  [INFO]  Current local: $($recovery.AlphaUrl); expected: $expectedLocalPath" -Chinese "  [INFO]  当前 local: $($recovery.AlphaUrl); 期望: $expectedLocalPath" -ForegroundColor DarkGray
                Write-UIHost -English "  [INFO]  Current remote: $($recovery.BetaUrl); expected: $expectedRemoteUrl" -Chinese "  [INFO]  当前 remote: $($recovery.BetaUrl); 期望: $expectedRemoteUrl" -ForegroundColor DarkGray
                if ($recovery.RecoveryScenario -eq "stale-before-creation") {
                    Write-InfoCheck -Name "$name Mutagen session" -Detail "(stale before runtime creation: $sessionName, $($recovery.Health), $($recovery.Detail))"
                } else {
                    $script:doctorIssues += "$name sync recovery: $($recovery.RecoveryScenario)"
                }
            }
        } catch {
            Write-InfoCheck -Name "$name Mutagen session" -Detail "(status unavailable: $_)"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  Results: $($script:doctorOk.Count) OK, $($script:doctorIssues.Count) issues, $($script:doctorInfo.Count) info" -Chinese "  结果: $($script:doctorOk.Count) OK, $($script:doctorIssues.Count) 个问题, $($script:doctorInfo.Count) 条信息" -ForegroundColor $(if ($script:doctorIssues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($script:doctorIssues.Count -gt 0) {
    Write-UIHost -English "Issues found:" -Chinese "发现的问题:" -ForegroundColor Red
    foreach ($issue in $script:doctorIssues) {
        Write-UIHost -English "  - $issue" -Chinese "  - $issue" -ForegroundColor Red
    }
} else {
    Write-UIHost -English "All checks passed. Platform is healthy." -Chinese "所有检查通过。平台状态健康。" -ForegroundColor Green
}

if ($FirstRun) {
    Write-Host ""
    Write-UIHost -English "First-run checklist — Complete these steps to get your first runtime ready" -Chinese "首次使用检查清单 — 完成以下步骤即可启动第一个运行环境" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-UIHost -English "  Estimated total time: 3-5 minutes (setup) + 20-30 minutes (first VM build)" -Chinese "  预计总耗时: 3-5 分钟（设置）+ 20-30 分钟（首次 VM 构建）" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "Tip: Run 'adpos quickstart' for a one-command guided setup that chains these steps." -Chinese "提示: 运行 'adpos quickstart' 可一键引导完成以下步骤。" -ForegroundColor Green

    Write-Host ""
    Write-UIHost -English "Platform Setup (~3-5 min)" -Chinese "平台设置 (~3-5 分钟)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor DarkGray

    Write-UIHost -English "  1. Align VMware NAT with ADP config (~30s):" -Chinese "  1. 对齐 VMware NAT 与 ADP 配置 (~30s):" -ForegroundColor White
    Write-UIHost -English "     Preview changes:" -Chinese "     预览变更:" -ForegroundColor DarkGray
    Write-Host "     adpos network configure-local -Plan" -ForegroundColor DarkGray
    Write-UIHost -English "     Apply if alignment is needed:" -Chinese "     如需对齐则应用:" -ForegroundColor DarkGray
    Write-Host "     adpos network configure-local -Apply" -ForegroundColor DarkGray
    Write-UIHost -English "     Or keep ADP's subnet and change VMware VMnet8 in Virtual Network Editor." -Chinese "     或者保留 ADP 配置的网段，并在 VMware Virtual Network Editor 中修改 VMnet8。" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "  2. Confirm ISO is available (~10s):" -Chinese "  2. 确认 ISO 可用 (~10s):" -ForegroundColor White
    Write-Host "     adpos iso download                                         # Download Ubuntu ISO (~2.6 GB, 10-30 min)" -ForegroundColor DarkGray
    Write-Host "     .\\install.ps1 -IsoPath C:\\path\\to\\ubuntu-26.04-live-server-amd64.iso  # Or provide your own" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "  3. Initialize platform (~30s):" -Chinese "  3. 初始化平台 (~30s):" -ForegroundColor White
    Write-Host "     .\\install.ps1     # Or .\\install.ps1 -Quick if already initialized" -ForegroundColor DarkGray
    Write-Host "     adpos init [-Quick] [-IsoPath <path>]" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "First Runtime (~20-30 min for initial VM build)" -Chinese "首次运行时（初始 VM 构建 ~20-30 分钟）" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor DarkGray

    Write-UIHost -English "  4. Preview before running (~5s):" -Chinese "  4. 运行前预览 (~5s):" -ForegroundColor White
    Write-Host "     adpos up agent -Plan            # See what will be created" -ForegroundColor DarkGray

    Write-UIHost -English "  5. Start first runtime (~20-30 min):" -Chinese "  5. 启动第一个运行时 (~20-30 分钟):" -ForegroundColor White
    Write-Host "     adpos up agent                  # Creates VM from ISO, installs Ubuntu, bootstraps" -ForegroundColor DarkGray
    Write-UIHost -English "     The first VM build takes 20-30 minutes. ADP-OS shows install-monitor heartbeats." -Chinese "     首次 VM 构建需要 20-30 分钟。ADP-OS 会显示 install-monitor 心跳。" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "After VM is Ready (~2 min)" -Chinese "VM 就绪后 (~2 分钟)" -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor DarkGray

    Write-UIHost -English "  6. Check runtime status (~5s):" -Chinese "  6. 检查运行时状态 (~5s):" -ForegroundColor White
    Write-Host "     adpos status agent" -ForegroundColor DarkGray

    Write-UIHost -English "  7. Start file sync (~10s):" -Chinese "  7. 启动文件同步 (~10s):" -ForegroundColor White
    Write-Host "     adpos sync start agent" -ForegroundColor DarkGray

    Write-UIHost -English "  8. Place target project under workspace:" -Chinese "  8. 放置目标项目到工作区:" -ForegroundColor White
    Write-Host "     $workspaceRoot\\agent\\your-project" -ForegroundColor DarkGray

    Write-UIHost -English "  9. Create a VM snapshot before risky work (~30s):" -Chinese "  9. 高风险操作前创建 VM 快照 (~30s):" -ForegroundColor White
    Write-Host "     adpos snapshot create agent before-risky-task" -ForegroundColor DarkGray

    Write-Host ""
    Write-UIHost -English "  For more: https://github.com/karoc/ai-dev-platform" -Chinese "  更多信息: https://github.com/karoc/ai-dev-platform" -ForegroundColor DarkGray
    Write-Host ""
}
