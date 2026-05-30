# ADP-OS Status Command
# Shows runtime status and connection details without changing VM, sync, or guest state.

param(
    [string]$RuntimeName
)

$ErrorActionPreference = "Stop"

if ($RuntimeName -and -not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Chinese "未知运行时: $RuntimeName。可用: $((Get-AllRuntimeNames) -join ', ')") -Component "cli.status"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

function Get-StatusVmxPath {
    param([string]$TargetRuntime)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$TargetRuntime"
    return (Join-Path $vmStore "$vmName\$vmName.vmx")
}

function Get-StatusRuntimeState {
    param(
        [string]$TargetRuntime,
        [bool]$VmwareAvailable,
        [string[]]$RunningVmxPaths
    )

    $vmxPath = Get-StatusVmxPath -TargetRuntime $TargetRuntime
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Status     = "not-created"
            DetectedIp = ""
            VmxPath    = $vmxPath
        }
    }

    if (-not $VmwareAvailable) {
        return [pscustomobject]@{
            Status     = "exists-vmware-unavailable"
            DetectedIp = ""
            VmxPath    = $vmxPath
        }
    }

    $fullVmxPath = [System.IO.Path]::GetFullPath($vmxPath)
    $status = if ($RunningVmxPaths -contains $fullVmxPath) { "running" } else { "stopped" }
    $detectedIp = ""
    try {
        $quick = Invoke-Vmrun -Arguments @("getGuestIPAddress", $vmxPath) -TimeoutSeconds 5
        if ($quick.Success) {
            $detectedIp = Select-VMIPv4FromText -Text $quick.StdOut
        }
        if (-not $detectedIp) {
            $detectedIp = Get-VMIPFromDhcpLeases -VmxPath $vmxPath
        }
        if ($detectedIp) {
            $status = "running"
        }
    } catch {
        $detectedIp = ""
    }

    return [pscustomobject]@{
        Status     = $status
        DetectedIp = $detectedIp
        VmxPath    = $vmxPath
    }
}

function Test-StatusSSHReachable {
    param(
        [string]$HostAddress,
        [int]$Port = 22
    )

    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        return "not-configured"
    }

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return "ssh-unavailable"
    }

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    if (-not (Test-Path -LiteralPath $keyPath)) {
        return "key-missing"
    }

    $sshOutput = & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=5 `
        -o BatchMode=yes `
        -p $Port `
        "adp@$HostAddress" `
        "echo ok" 2>&1

    $sshExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $sshText = ($sshOutput | Where-Object { $_ }) -join "`n"

    if ($sshExit -eq 0) {
        return "reachable"
    }
    if ($sshExit -eq 255 -and $sshText -match "Permission denied") {
        return "auth-pending"
    }

    return "unreachable"
}

function Get-StatusSyncState {
    param(
        [string]$TargetRuntime,
        [bool]$MutagenAvailable,
        [string]$ExpectedLocalPath,
        [string]$ExpectedRemoteUrl,
        [bool]$RuntimeCreated
    )

    if (-not $MutagenAvailable) {
        return "mutagen-unavailable"
    }

    $sessionName = "adp-$TargetRuntime"
    try {
        $session = Get-SyncSessionInfo -SessionName $sessionName -ExpectedLocalPath $ExpectedLocalPath -ExpectedRemoteUrl $ExpectedRemoteUrl
        if (-not $session.Exists) {
            return "not-started"
        }
        if (-not $RuntimeCreated) {
            return "stale-session"
        }
        if ($session.Health -eq "healthy") {
            return "healthy"
        }
        if ($session.Health -eq "present") {
            return "present"
        }
        return $session.Health
    } catch {
        return "unknown"
    }
}

function Get-StatusSeedNetwork {
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

function Write-StatusNetworkDriftRemediation {
    param(
        [string]$TargetRuntime,
        [object]$SeedNetwork,
        [string]$ConfiguredIp
    )

    Write-UIHost -English "  remediation:" -Chinese "  修复建议:" -ForegroundColor Yellow
    Write-UIHost -English "    1. Rebuild when the VM can be recreated: adp destroy $TargetRuntime -Plan, then recreate with adp up $TargetRuntime." -Chinese "    1. 如果 VM 可以重建：先运行 adp destroy $TargetRuntime -Plan，再用 adp up $TargetRuntime 重建。" -ForegroundColor Yellow
    Write-UIHost -English "    2. In-place guest fix when the seed-era address is reachable: adp network apply $TargetRuntime -Plan." -Chinese "    2. 如果 seed-era 地址可连接：运行 adp network apply $TargetRuntime -Plan 预览 guest 内修复。" -ForegroundColor Yellow
    Write-UIHost -English "    3. Admin-only temporary host-route workaround only to regain SSH to $($SeedNetwork.Address); ADP will not apply host routes automatically." -Chinese "    3. 仅管理员可用的临时 host-route workaround 用于恢复到 $($SeedNetwork.Address) 的 SSH；ADP 不会自动应用 host routes。" -ForegroundColor Yellow
    Write-UIHost -English "    Seed-era network: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); target: $ConfiguredIp." -Chinese "    Seed-era 网络: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); 目标: $ConfiguredIp。" -ForegroundColor DarkGray
}

function Write-StatusRuntime {
    param(
        [string]$TargetRuntime,
        [bool]$VmwareAvailable,
        [bool]$MutagenAvailable,
        [string[]]$RunningVmxPaths,
        [string]$AdminUser,
        [string]$KeyPath
    )

    $rt = Get-RuntimeConfig $TargetRuntime
    $state = Get-StatusRuntimeState -TargetRuntime $TargetRuntime -VmwareAvailable $VmwareAvailable -RunningVmxPaths $RunningVmxPaths
    $configuredIp = Get-RuntimeStaticIP $TargetRuntime
    $connectIp = if ($configuredIp) { $configuredIp } else { $state.DetectedIp }
    $port = if ($rt.PSObject.Properties.Name -contains "ssh_port" -and $rt.ssh_port) { [int]$rt.ssh_port } else { 22 }
    $seedNetwork = Get-StatusSeedNetwork -TargetRuntime $TargetRuntime
    $alias = "adp-os-adp-$TargetRuntime"
    $workspaceRoot = Resolve-Path "workspace_root"
    $workspacePath = Join-Path $workspaceRoot $rt.workspace
    $expectedRemoteUrl = "${alias}:/home/adp/workspace"
    $runtimeCreated = ($state.Status -ne "not-created")
    $syncState = Get-StatusSyncState -TargetRuntime $TargetRuntime -MutagenAvailable $MutagenAvailable -ExpectedLocalPath $workspacePath -ExpectedRemoteUrl $expectedRemoteUrl -RuntimeCreated $runtimeCreated
    $adpRunningVms = @()
    if ($VmwareAvailable) {
        $adpRunningVms = @(Get-ADPRunningRuntimeVMs -RunningVmxPaths $RunningVmxPaths -RuntimeName $TargetRuntime -ManagedVmxPath $state.VmxPath)
    }
    $duplicateRunningVms = @($adpRunningVms | Where-Object { -not $_.IsManagedByCurrentCheckout })
    $hasDuplicateRunningVm = ($adpRunningVms.Count -gt 1 -or $duplicateRunningVms.Count -gt 0)
    $sshState = if ($hasDuplicateRunningVm) {
        "ambiguous-duplicate"
    } elseif ($state.Status -match "running") {
        Test-StatusSSHReachable -HostAddress $connectIp -Port $port
    } else {
        "skipped"
    }

    Write-Host "$TargetRuntime" -ForegroundColor Yellow
    Write-UIHost -English "  status:        $($state.Status)" -Chinese "  状态:          $($state.Status)" -ForegroundColor DarkGray
    Write-UIHost -English "  configured IP: $(if ($configuredIp) { $configuredIp } else { 'not configured' })" -Chinese "  配置 IP:       $(if ($configuredIp) { $configuredIp } else { '未配置' })" -ForegroundColor DarkGray
    if ($state.DetectedIp) {
        Write-UIHost -English "  detected IP:   $($state.DetectedIp)" -Chinese "  探测 IP:       $($state.DetectedIp)" -ForegroundColor DarkGray
        if ($configuredIp -and $state.DetectedIp -ne $configuredIp) {
            Write-UIHost -English "  note:          VMware detected $($state.DetectedIp), but ADP-OS will use configured static IP $configuredIp" -Chinese "  说明:          VMware 探测到 $($state.DetectedIp)，但 ADP-OS 会使用配置的 static IP $configuredIp" -ForegroundColor Yellow
        }
    } elseif ($state.Status -match "running") {
        Write-UIHost -English "  detected IP:   unavailable" -Chinese "  探测 IP:       暂不可用" -ForegroundColor Yellow
    }
    if ($seedNetwork -and $configuredIp -and $seedNetwork.Address -and $seedNetwork.Address -ne $configuredIp) {
        Write-UIHost -English "  network drift: seed uses $($seedNetwork.Address)/$($seedNetwork.Prefix), current config uses $configuredIp" -Chinese "  网络漂移:      seed 使用 $($seedNetwork.Address)/$($seedNetwork.Prefix)，当前配置使用 $configuredIp" -ForegroundColor Red
        Write-StatusNetworkDriftRemediation -TargetRuntime $TargetRuntime -SeedNetwork $seedNetwork -ConfiguredIp $configuredIp
    }
    Write-Host "  ssh:           $sshState" -ForegroundColor DarkGray
    if ($sshState -eq "auth-pending") {
        Write-UIHost -English "  note:          SSH port is open, but the ADP key is not accepted yet. During autoinstall this usually means the installer or first boot is still preparing the target user." -Chinese "  说明:          SSH 端口已打开，但 ADP key 还未被接受。autoinstall 期间这通常表示安装器或首次启动仍在准备目标用户。" -ForegroundColor Yellow
    }
    if ($hasDuplicateRunningVm) {
        Write-UIHost -English "  duplicate VM:  running ADP runtime name also found outside this checkout" -Chinese "  重复 VM:       当前 checkout 外也发现同名 ADP runtime 正在运行" -ForegroundColor Red
        Write-UIHost -English "  current VMX:   $($state.VmxPath)" -Chinese "  当前 VMX:      $($state.VmxPath)" -ForegroundColor DarkGray
        foreach ($vm in $adpRunningVms) {
            $owner = if ($vm.IsManagedByCurrentCheckout) { Get-UIText -English "current checkout" -Chinese "当前 checkout" } else { Get-UIText -English "other checkout or stale VM" -Chinese "其他 checkout 或 stale VM" }
            Write-Host "  running VMX:   $($vm.NormalizedVmxPath) [$owner]" -ForegroundColor Yellow
        }
        Write-UIHost -English "  remediation:   stop or rename the stale duplicate before diagnosing SSH or network issues" -Chinese "  修复建议:      排查 SSH 或网络前，先停止或重命名 stale duplicate VM" -ForegroundColor Yellow
    }
    Write-Host "  sync:          $syncState" -ForegroundColor DarkGray
    if ($syncState -in @("wrong-local", "wrong-remote", "unhealthy")) {
        Write-UIHost -English "  sync note:     existing Mutagen session is not usable for this checkout/runtime" -Chinese "  sync 说明:     现有 Mutagen session 不适用于当前 checkout/runtime" -ForegroundColor Yellow
        Write-UIHost -English "  sync fix:      adp sync stop $TargetRuntime; adp sync start $TargetRuntime" -Chinese "  sync 修复:     adp sync stop $TargetRuntime; adp sync start $TargetRuntime" -ForegroundColor Yellow
    } elseif ($syncState -eq "stale-session") {
        Write-UIHost -English "  sync note:     old Mutagen session exists, but this runtime is not created in the current checkout" -Chinese "  sync 说明:     存在旧 Mutagen session，但当前 checkout 尚未创建该运行时" -ForegroundColor Yellow
        Write-UIHost -English "  sync cleanup:  adp sync stop $TargetRuntime" -Chinese "  sync 清理:     adp sync stop $TargetRuntime" -ForegroundColor Yellow
        Write-UIHost -English "  sync next:     adp up $TargetRuntime; adp sync start $TargetRuntime" -Chinese "  sync 下一步:   adp up $TargetRuntime; adp sync start $TargetRuntime" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  workspace:     $workspacePath" -Chinese "  工作区:        $workspacePath" -ForegroundColor DarkGray
    Write-Host "  VMX:           $($state.VmxPath)" -ForegroundColor DarkGray
    if ($connectIp) {
        Write-Host "  connect:       ssh -i $KeyPath -p $port $AdminUser@$connectIp" -ForegroundColor Cyan
        Write-Host "  alias:         ssh $alias" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  connect:       unavailable until a static IP or detected guest IP is available" -Chinese "  连接:          需要 static IP 或探测到 guest IP 后才可用" -ForegroundColor Yellow
    }
    Write-UIHost -English "  next:          adp up $TargetRuntime | adp sync start $TargetRuntime | adp doctor" -Chinese "  下一步:        adp up $TargetRuntime | adp sync start $TargetRuntime | adp doctor" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host ""
Write-UIHost -English "ADP-OS Status" -Chinese "ADP-OS 状态" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "Status only: no VMs, sync sessions, snapshots, guest files, or workspace files will be changed." -Chinese "仅查看状态：不会修改 VM、sync session、快照、guest 文件或工作区文件。" -ForegroundColor Cyan
Write-Host ""

$config = Get-PlatformConfig
$localConfigStatus = Get-LocalConfigStatus
$adminUser = if ($config.defaults.admin_user) { [string]$config.defaults.admin_user } else { "adp" }
$keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"

if ($localConfigStatus.Exists) {
    if ($localConfigStatus.Empty) {
        Write-UIHost -English "Local config: empty, ignored ($($localConfigStatus.Path))" -Chinese "本机配置: 空文件，已忽略 ($($localConfigStatus.Path))" -ForegroundColor DarkGray
    } elseif ($localConfigStatus.Applied) {
        Write-UIHost -English "Local config: applied sections $($localConfigStatus.Sections -join ', ') ($($localConfigStatus.Path))" -Chinese "本机配置: 已应用配置段 $($localConfigStatus.Sections -join ', ') ($($localConfigStatus.Path))" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "Local config: present, no supported sections ($($localConfigStatus.Path))" -Chinese "本机配置: 文件存在，但没有支持的配置段 ($($localConfigStatus.Path))" -ForegroundColor Yellow
    }
} else {
    Write-UIHost -English "Local config: not present, using committed defaults" -Chinese "本机配置: 不存在，使用仓库默认配置" -ForegroundColor DarkGray
}

if ($config.network.vmware_nat) {
    Write-UIHost -English "Network:      $($config.network.vmware_nat.cidr), gateway $($config.network.vmware_nat.gateway)" -Chinese "网络:        $($config.network.vmware_nat.cidr), gateway $($config.network.vmware_nat.gateway)" -ForegroundColor DarkGray
}
Write-UIHost -English "SSH key:      $keyPath" -Chinese "SSH 密钥:    $keyPath" -ForegroundColor DarkGray
Write-Host ""

$vmwareAvailable = Test-VMwareAvailable
$runningVmxPaths = @()
if ($vmwareAvailable) {
    Initialize-VMware | Out-Null
    try {
        $runningVmxPaths = @(Get-RunningVMs | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
    } catch {
        $runningVmxPaths = @()
    }
} else {
    Write-UIHost -English "VMware:      unavailable; VM status is limited to local VMX presence." -Chinese "VMware:      不可用；VM 状态仅能基于本地 VMX 是否存在判断。" -ForegroundColor Yellow
    Write-Host ""
}

$mutagenAvailable = $false
try {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    $mutagenAvailable = $true
} catch {
    $mutagenAvailable = $false
}

$targets = if ($RuntimeName) { @($RuntimeName) } else { Get-AllRuntimeNames }
foreach ($target in $targets) {
    Write-StatusRuntime -TargetRuntime $target -VmwareAvailable $vmwareAvailable -MutagenAvailable $mutagenAvailable -RunningVmxPaths $runningVmxPaths -AdminUser $adminUser -KeyPath $keyPath
}
