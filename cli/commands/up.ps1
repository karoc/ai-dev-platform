# ADP-OS Up Command (Phase 2)
# Starts a runtime — auto-creates VM from ISO if needed

[CmdletBinding()]
param(
    [string]$RuntimeName,
    [switch]$NoBootstrap,
    [switch]$NoProvision,
    [switch]$Plan,
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"

if (-not $RuntimeName) {
    $validRuntimes = (Get-AllRuntimeNames) -join ', '
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos up <runtime> ($validRuntimes) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision]" -Chinese "用法: adpos up <runtime> ($validRuntimes) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision]") -Component "cli.up"
    Write-UIHost -English "Run 'adpos up --help' for usage." -Chinese "运行 'adpos up --help' 查看用法。" -ForegroundColor DarkGray
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ADPUnknownRuntimeError -RuntimeName $RuntimeName -CommandText "up" -Component "cli.up"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "adpos up $RuntimeName (Phase 2)" -Chinese "adpos up $RuntimeName（阶段 2）") -Component "cli.up"

$rt = Get-RuntimeConfig $RuntimeName
$config = Get-PlatformConfig
$vmStore = Resolve-Path "vm_store"
$isoCache = Resolve-Path "iso_cache"

# Load vm-factory (still uses .vmx paths internally — NOT part of Provider migration)
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\ssh\ssh.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\resource-conflicts.ps1")
$resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $RuntimeName
$vmName = $resourceProfile.VmName
$vmxPath = $resourceProfile.VmxPath
Initialize-VmFactory -ProjectRoot (Get-ProjectRoot) -IsoCachePath $isoCache -VmStorePath $vmStore
$factoryLayout = Get-ADPVMwareRuntimeLayout `
    -RuntimeName $RuntimeName `
    -VmStorePath $vmStore `
    -SeedRootPath (Join-Path $vmStore "seeds") `
    -Namespace $resourceProfile.RuntimeNamespace `
    -RuntimeResourceName $resourceProfile.RuntimeResourceName

# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null

function Get-RuntimeConnectionIP {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    if ($staticIp) {
        return $staticIp
    }

    $resourceNames = Get-ADPRuntimeResourceNames -TargetRuntime $TargetRuntime
    $ipResult = Get-VMIP -Name $resourceNames.RuntimeResourceName
    if ($ipResult.Success) { return $ipResult.Data }
    return $null
}

function Write-RuntimeConnectionSummary {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $rtConfig = Get-RuntimeConfig $TargetRuntime
    $config = Get-PlatformConfig
    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    $resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $TargetRuntime -VmxPath $TargetVmxPath
    $detectedIp = $null
    try {
        $ipResult = Get-VMIP -Name $resourceProfile.RuntimeResourceName
        if ($ipResult.Success) { $detectedIp = $ipResult.Data }
    } catch {}

    $ip = if ($staticIp) { $staticIp } else { $detectedIp }
    $port = if ($rtConfig.PSObject.Properties.Name -contains "ssh_port" -and $rtConfig.ssh_port) { [int]$rtConfig.ssh_port } else { 22 }
    $user = if ($config.defaults.admin_user) { [string]$config.defaults.admin_user } else { "adp" }
    $keyPath = $resourceProfile.SshKeyPath
    $workspacePath = $resourceProfile.WorkspacePath
    $alias = $resourceProfile.SshAlias

    Write-Host ""
    Write-UIHost -English "Connection details:" -Chinese "连接信息:" -ForegroundColor Cyan
    if ($ip) {
        Write-UIHost -English "  IP:        $ip" -Chinese "  IP:        $ip" -ForegroundColor Cyan
        if ($staticIp -and $detectedIp -and $staticIp -ne $detectedIp) {
            Write-UIHost -English "  Detected:  $detectedIp (VMware reported this, but ADP-OS is using configured static IP)" -Chinese "  探测到:  $detectedIp (VMware 报告了该地址，但 ADP-OS 会使用配置的 static IP)" -ForegroundColor Yellow
        }
        Write-UIHost -English "  SSH:       ssh -i $keyPath -p $port $user@$ip" -Chinese "  SSH:       ssh -i $keyPath -p $port $user@$ip" -ForegroundColor DarkGray
        Write-UIHost -English "  Alias:     ssh $alias" -Chinese "  别名:      ssh $alias" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  IP:        unavailable yet" -Chinese "  IP:        暂不可用" -ForegroundColor Yellow
        Write-UIHost -English "  SSH:       run adpos status $TargetRuntime after the guest finishes booting" -Chinese "  SSH:       guest 启动完成后运行 adpos status $TargetRuntime" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  Workspace: $workspacePath" -Chinese "  工作区:    $workspacePath" -ForegroundColor DarkGray
    Write-UIHost -English "  Sync:      adpos sync start $TargetRuntime" -Chinese "  同步:      adpos sync start $TargetRuntime" -ForegroundColor DarkGray
    Write-UIHost -English "  Status:    adpos status $TargetRuntime" -Chinese "  状态:      adpos status $TargetRuntime" -ForegroundColor DarkGray
    Write-UIHost -English "  Doctor:    adpos doctor" -Chinese "  诊断:      adpos doctor" -ForegroundColor DarkGray
}

function Test-GuestProvisionMarkerViaVmwareTools {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $result = [ordered]@{
        Checked     = $false
        Provisioned = $false
        Detail      = ""
        DetectedIP  = $null
    }

    if (-not (Get-Command Invoke-Vmrun -ErrorAction SilentlyContinue)) {
        $result.Detail = "VMware guest operations are not available in this session"
        return [pscustomobject]$result
    }

    if ([string]::IsNullOrWhiteSpace($TargetVmxPath) -or -not (Test-Path -LiteralPath $TargetVmxPath)) {
        $result.Detail = "VMX path is unavailable for guest operation probe"
        return [pscustomobject]$result
    }

    $platformConfig = Get-PlatformConfig
    $guestUser = if ($platformConfig.defaults.admin_user) { [string]$platformConfig.defaults.admin_user } else { "adp" }
    $guestPassword = if ($platformConfig.defaults.admin_password) { [string]$platformConfig.defaults.admin_password } else { "adp" }
    $markerCommand = "test -f /home/adp/.adp-provisioned"

    try {
        $probe = Invoke-Vmrun `
            -Arguments @("-gu", $guestUser, "-gp", $guestPassword, "runProgramInGuest", $TargetVmxPath, "/bin/bash", "-c", $markerCommand) `
            -TimeoutSeconds 15

        $result.Checked = $true
        if ($probe.Success) {
            $result.Provisioned = $true
            $result.Detail = "/home/adp/.adp-provisioned exists"
        } else {
            $detail = @($probe.StdErr, $probe.StdOut) | Where-Object { $_ } | Select-Object -First 1
            $result.Detail = if ($detail) { $detail } else { "guest operation did not confirm provision marker" }
        }
    } catch {
        $result.Detail = "guest operation probe failed: $_"
    }

    try {
        if (Get-Command Get-VMIPQuick -ErrorAction SilentlyContinue) {
            $detectedIp = Get-VMIPQuick -VmxPath $TargetVmxPath -TimeoutSeconds 5
            if ($detectedIp) {
                $result.DetectedIP = $detectedIp
            }
        }
    } catch {}

    return [pscustomobject]$result
}

function Test-RuntimeConnectionProvisionMarkerViaSSH {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $result = [ordered]@{
        Checked    = $false
        Ready      = $false
        TargetIP   = $null
        DetectedIP = $null
        Detail     = ""
    }

    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    try {
        if (Get-Command Get-VMIPQuick -ErrorAction SilentlyContinue) {
            $detectedIp = Get-VMIPQuick -VmxPath $TargetVmxPath -TimeoutSeconds 5
            if ($detectedIp) { $result.DetectedIP = $detectedIp }
        }
    } catch {}

    $targetIp = if ($staticIp) { $staticIp } else { $result.DetectedIP }
    if (-not $targetIp) {
        $result.Detail = "no ADP connection IP available"
        return [pscustomobject]$result
    }

    $result.TargetIP = $targetIp
    $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    if (-not (Test-Path -LiteralPath $sshKeyPath)) {
        $result.Detail = "SSH key missing at $sshKeyPath"
        return [pscustomobject]$result
    }

    $platformConfig = Get-PlatformConfig
    $guestUser = if ($platformConfig.defaults.admin_user) { [string]$platformConfig.defaults.admin_user } else { "adp" }
    $runtimeConfig = Get-RuntimeConfig $TargetRuntime
    $sshPort = if ($runtimeConfig.PSObject.Properties.Name -contains "ssh_port" -and $runtimeConfig.ssh_port) { [int]$runtimeConfig.ssh_port } else { 22 }

    try {
        $result.Checked = $true
        $probe = Invoke-AdpSshCommand `
            -Host $targetIp `
            -Port $sshPort `
            -User $guestUser `
            -KeyPath $sshKeyPath `
            -Command "test -f /home/adp/.adp-provisioned" `
            -ConnectTimeoutSeconds 5 `
            -TimeoutSeconds 12
        if ($probe.State -eq "command-success") {
            $result.Ready = $true
            $result.Detail = "/home/adp/.adp-provisioned confirmed over SSH at $targetIp"
        } elseif ($probe.State -eq "ssh-timeout") {
            $result.Detail = "SSH provision marker probe timed out at $targetIp (ssh-timeout)"
        } elseif ($probe.State -eq "auth-pending") {
            $result.Detail = "SSH auth-pending at $targetIp; ADP key is not accepted yet"
        } elseif ($probe.State -eq "command-failed") {
            $result.Detail = "SSH reached $targetIp but did not find /home/adp/.adp-provisioned"
        } else {
            $result.Detail = "SSH did not confirm provision marker at $targetIp ($($probe.State))"
        }
    } catch {
        $result.Detail = "SSH provision marker probe failed: $_"
    }

    return [pscustomobject]$result
}

function Write-ProvisionedNetworkNotReadyGuidance {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath,
        [object]$ProvisionMarker
    )

    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    $detectedIp = if ($ProvisionMarker -and $ProvisionMarker.DetectedIP) { [string]$ProvisionMarker.DetectedIP } else { $null }

    Write-Host ""
    Write-UIHost -English "VM is already provisioned, but ADP cannot confirm SSH readiness." -Chinese "VM 已完成 provisioning，但 ADP 无法确认 SSH 就绪。" -ForegroundColor Yellow
    Write-UIHost -English "  VMware Tools confirmed /home/adp/.adp-provisioned inside the guest." -Chinese "  VMware Tools 已在 guest 内确认 /home/adp/.adp-provisioned。" -ForegroundColor Green
    Write-UIHost -English "  This is not an Ubuntu install in progress; ADP will not enter the INSTALLING monitor for this VM." -Chinese "  这不是 Ubuntu 仍在安装；ADP 不会让此 VM 继续进入 INSTALLING 监控。" -ForegroundColor Yellow
    Write-UIHost -English "  State: provisioned, network/SSH not ready." -Chinese "  状态: 已 provision，network/SSH 尚未就绪。" -ForegroundColor Yellow

    if ($staticIp) {
        Write-UIHost -English "  Configured IP: $staticIp" -Chinese "  配置 IP: $staticIp" -ForegroundColor DarkGray
    }
    if ($detectedIp) {
        Write-UIHost -English "  VMware detected IP: $detectedIp" -Chinese "  VMware 探测 IP: $detectedIp" -ForegroundColor DarkGray
    }
    if ($staticIp -and $detectedIp -and $staticIp -ne $detectedIp) {
        Write-UIHost -English "  Network drift likely: the guest is on $detectedIp, but ADP expects $staticIp." -Chinese "  很可能存在网络漂移: guest 当前为 $detectedIp，但 ADP 期望 $staticIp。" -ForegroundColor Yellow
    } elseif ($staticIp -and -not $detectedIp) {
        Write-UIHost -English "  Network drift is possible: VMware did not report a usable guest IP during the quick probe." -Chinese "  可能存在网络漂移: VMware quick probe 未报告可用 guest IP。" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-UIHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
    Write-UIHost -English "  1. Inspect the current runtime and host NAT diagnosis:" -Chinese "  1. 查看当前 runtime 与 host NAT 诊断:" -ForegroundColor DarkGray
    Write-Host "     adpos status $TargetRuntime" -ForegroundColor DarkGray
    Write-Host "     adpos doctor" -ForegroundColor DarkGray
    Write-UIHost -English "  2. If network drift is reported, preview the in-place guest network fix:" -Chinese "  2. 如果报告 network drift，先预览 guest 内网络修复:" -ForegroundColor DarkGray
    Write-Host "     adpos network apply $TargetRuntime -Plan" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Apply only after the plan identifies the expected runtime/IP change:" -Chinese "  3. 仅在计划确认目标 runtime/IP 变更后再应用:" -ForegroundColor DarkGray
    Write-Host "     adpos network apply $TargetRuntime" -ForegroundColor DarkGray
    Write-UIHost -English "  Bootstrap will resume after SSH is reachable: adpos up $TargetRuntime" -Chinese "  SSH 可达后再继续 bootstrap: adpos up $TargetRuntime" -ForegroundColor DarkGray
}

function Assert-VMwareNatReadyForRuntimeCreate {
    param([string]$TargetRuntime)

    $config = Get-PlatformConfig
    $nat = $config.network.vmware_nat
    if (-not $nat) {
        return
    }

    $hostNat = Test-VMwareNatConfigMatchesHost -ConfiguredNat $nat
    if (-not $hostNat.Checked) {
        Write-UIHost -English "VMware NAT preflight: $($hostNat.Reason). Continuing because host NAT could not be detected." -Chinese "VMware NAT 预检查: $($hostNat.Reason)。由于无法探测 host NAT，将继续执行。" -ForegroundColor Yellow
        Write-UIHost -English "  Confirm VMnet8 in VMware Virtual Network Editor if provisioning later fails." -Chinese "  如果后续 provisioning 失败，请在 VMware Virtual Network Editor 中确认 VMnet8。" -ForegroundColor DarkGray
        return
    }

    if (-not $hostNat.Matches -or -not $hostNat.GatewayInHostCidr) {
        Write-ErrorLog -Message (Get-UIText -English "VMware NAT preflight failed for '$TargetRuntime': configured $($hostNat.ConfiguredCidr), host $($hostNat.HostCidr)." -Chinese "'$TargetRuntime' 的 VMware NAT 预检查失败：配置为 $($hostNat.ConfiguredCidr)，主机为 $($hostNat.HostCidr)。") -Component "cli.up"
        Write-Host ""
        Write-UIHost -English "VMware NAT mismatch detected before VM creation." -Chinese "创建 VM 前检测到 VMware NAT 不匹配。" -ForegroundColor Red
        Write-UIHost -English "  Configured: $($hostNat.ConfiguredCidr), gateway $($nat.gateway)" -Chinese "  当前配置: $($hostNat.ConfiguredCidr), gateway $($nat.gateway)" -ForegroundColor DarkGray
        Write-UIHost -English "  Host VMnet8: $($hostNat.HostCidr) ($($hostNat.HostAddress), $($hostNat.HostSource))" -Chinese "  主机 VMnet8: $($hostNat.HostCidr) ($($hostNat.HostAddress), $($hostNat.HostSource))" -ForegroundColor DarkGray
        Write-UIHost -English "  ADP configuration and host VMware NAT disagree. Choose one remediation path:" -Chinese "  ADP 配置与主机 VMware NAT 不一致。请选择一种修复路径:" -ForegroundColor Yellow
        Write-UIHost -English "  Option A: Align ADP local overrides to current host VMnet8:" -Chinese "  方案 A：将 ADP 本机覆盖对齐到当前 host VMnet8:" -ForegroundColor DarkGray
        Write-Host "    adpos network configure-local -Plan" -ForegroundColor DarkGray
        Write-Host "    adpos network configure-local -Apply" -ForegroundColor DarkGray
        Write-UIHost -English "  Option B: Keep ADP's configured subnet and change VMware VMnet8 to $($hostNat.ConfiguredCidr) in Virtual Network Editor." -Chinese "  方案 B：保留 ADP 配置的网段，并在 VMware Virtual Network Editor 中把 VMnet8 改为 $($hostNat.ConfiguredCidr)。" -ForegroundColor DarkGray
        Write-UIHost -English "  Then rerun: adpos doctor -FirstRun" -Chinese "  然后重新运行: adpos doctor -FirstRun" -ForegroundColor DarkGray
        Write-UIHost -English "  No VM was created." -Chinese "  未创建任何 VM。" -ForegroundColor DarkGray
        exit 1
    }
}

function Check-PreRuntimeStaleSessions {
    param([string]$TargetRuntime)

    $mutagenAvailable = $false
    try {
        . (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
        $mutagenAvailable = $true
    } catch {
        return
    }

    $resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $TargetRuntime
    $sessionName = $resourceProfile.MutagenSession
    $expectedLocalPath = $resourceProfile.WorkspacePath
    $expectedRemoteUrl = $resourceProfile.ExpectedRemoteUrl

    $session = Get-SyncSessionInfo -SessionName $sessionName -ExpectedLocalPath $expectedLocalPath -ExpectedRemoteUrl $expectedRemoteUrl
    if (-not $session.Exists) {
        return
    }

    # Check if VM exists via Provider
    $statusResult = Get-VMStatus -Name $TargetRuntime
    $runtimeCreated = ($statusResult.Success -and $statusResult.Data -ne "not-created")

    $recovery = Get-SyncSessionRecoveryInfo `
        -SessionName $sessionName `
        -ExpectedLocalPath $expectedLocalPath `
        -ExpectedRemoteUrl $expectedRemoteUrl `
        -RuntimeCreated $runtimeCreated `
        -RuntimeName $TargetRuntime

    if ($recovery.RecoveryScenario -eq "none") {
        return
    }

    Write-Host ""
    Write-UIHost -English "Sync note: a Mutagen session '$sessionName' exists but doesn't match the current environment." -Chinese "同步提示: Mutagen session '$sessionName' 已存在，但与当前环境不匹配。" -ForegroundColor Yellow
    Write-UIHost -English "  This happens when a session was created from a different clone or a previous VM." -Chinese "  这通常是之前的 clone 或旧 VM 留下来的 session。" -ForegroundColor DarkGray
    Write-UIHost -English "  Stopping a stale session is safe — workspace files on both sides are not deleted." -Chinese "  停止 stale session 是安全的 — 不会删除任何一侧的 workspace 文件。" -ForegroundColor Green
    Write-UIHost -English "  To clean up before proceeding: adpos sync stop $TargetRuntime" -Chinese "  继续之前先清理: adpos sync stop $TargetRuntime" -ForegroundColor Yellow
    Write-UIHost -English "  Then restart sync after the runtime is ready: adpos sync start $TargetRuntime" -Chinese "  等 runtime 就绪后再启动同步: adpos sync start $TargetRuntime" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-BootstrapIfReady {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath,
        [switch]$WaitForProvisioning
    )

    if ($NoBootstrap) {
        Write-Host ""
        Write-UIHost -English "Bootstrap skipped." -Chinese "已跳过 bootstrap。" -ForegroundColor Yellow
        Write-RuntimeConnectionSummary -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
        return
    }

    $ready = Test-AutoinstallReady -RuntimeName $TargetRuntime -VmxPath $TargetVmxPath
    if (-not $ready) {
        $sshMarker = Test-RuntimeConnectionProvisionMarkerViaSSH -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
        if ($sshMarker.Ready) {
            $ready = $true
        }
    }

    if (-not $ready) {
        $provisionMarker = Test-GuestProvisionMarkerViaVmwareTools -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
        if ($provisionMarker.Provisioned) {
            Write-ProvisionedNetworkNotReadyGuidance -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath -ProvisionMarker $provisionMarker
            return
        }

        if ($WaitForProvisioning) {
            Write-Host ""
            Write-UIHost -English "VM is still in Ubuntu install/provisioning. ADP will keep monitoring readiness signals." -Chinese "VM 仍在进行 Ubuntu 安装/provisioning。ADP 会继续监控 readiness signals。" -ForegroundColor Yellow
            Write-UIHost -English "  This can take 15-45 minutes on first creation; it is not an SSH failure while install-monitor heartbeats continue." -Chinese "  首次创建通常需要 15-45 分钟；只要 install-monitor 心跳仍在继续，这不是 SSH 失败。" -ForegroundColor DarkGray
            $ready = Wait-AutoinstallComplete -VmxPath $TargetVmxPath -RuntimeName $TargetRuntime -TimeoutMinutes 60
        }
    }

    if (-not $ready) {
        $provisionMarker = Test-GuestProvisionMarkerViaVmwareTools -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
        if ($provisionMarker.Provisioned) {
            Write-ProvisionedNetworkNotReadyGuidance -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath -ProvisionMarker $provisionMarker
            return
        }

        Write-Host ""
        Write-UIHost -English "VM is still installing or provisioning. Once the install finishes, run:" -Chinese "VM 仍在安装或 provisioning。安装完成后运行:" -ForegroundColor Yellow
        Write-Host "  adpos up $TargetRuntime" -ForegroundColor DarkGray
        Write-UIHost -English "  (it will detect the VM and skip creation)" -Chinese "  (它会检测已有 VM 并跳过创建)" -ForegroundColor DarkGray
        Write-Host "  adpos status $TargetRuntime" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-UIHost -English "VM is ready. Running bootstrap..." -Chinese "VM 已就绪，正在运行 bootstrap..." -ForegroundColor Yellow

    . (Join-Path (Get-ProjectRoot) "core\bootstrap\bootstrap.ps1")
    Initialize-BootstrapOrchestrator -ProjectRoot (Get-ProjectRoot)

    try {
        $ip = Get-RuntimeConnectionIP -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
        $rtConfig = Get-RuntimeConfig $TargetRuntime
        $bootstrapSucceeded = Invoke-RuntimeBootstrap -RuntimeName $TargetRuntime -SSHHost $ip -Port $rtConfig.ssh_port
        if (-not $bootstrapSucceeded) {
            Write-WarnLog -Message "Bootstrap did not complete cleanly. Try: adpos doctor" -Component "cli.up"
        }
    } catch {
        Write-WarnLog -Message "Bootstrap had issues but VM is running. Try: adpos doctor" -Component "cli.up"
    }

    Write-RuntimeConnectionSummary -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS: Starting $RuntimeName" -Chinese "  ADP-OS: 正在启动 $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  CPU: $($rt.cpu) cores  |  RAM: $($rt.memory) MB  |  Disk: $($rt.disk) GB" -Chinese "  CPU: $($rt.cpu) 核  |  内存: $($rt.memory) MB  |  磁盘: $($rt.disk) GB" -ForegroundColor DarkGray
foreach ($notice in (Get-RuntimeProfileNoticeItems -RuntimeName $RuntimeName -Runtime $rt)) {
    Write-Host $notice.Text -ForegroundColor $notice.Color
}
Write-Host ""

# Check for stale Mutagen sessions before proceeding
Check-PreRuntimeStaleSessions -TargetRuntime $RuntimeName

$runningVmxPaths = Get-ADPRunningVmxPathsForResourceCheck
$resourceConflict = Get-ADPRuntimeDuplicateConflict -TargetRuntime $RuntimeName -ManagedVmxPath $vmxPath -RunningVmxPaths $runningVmxPaths
if ($resourceConflict.HasDuplicateRunningVm) {
    Write-ADPRuntimeResourceConflictGuidance -Profile $resourceProfile -Conflict $resourceConflict -CommandContext (Get-ADPCheckoutCommandContext) -Action "$(if ($Plan) { 'up plan' } else { 'up runtime start/create' })"
    if (-not $Plan) {
        Write-ErrorLog -Message (Get-UIText -English "Runtime '$RuntimeName' has a duplicate running VM. Stop the stale duplicate or isolate this checkout before running up." -Chinese "运行时 '$RuntimeName' 存在重复运行的 VM。请先停止 stale duplicate，或隔离当前 checkout 后再运行 up。") -Component "cli.up"
        exit 1
    }
}

if ($Plan) {
    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $plannedIsoPath = if ($IsoPath) { $IsoPath } else { Join-Path $isoCache $isoName }
    $statusResult = Get-VMStatus -Name $resourceProfile.RuntimeResourceName
    $status = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }
    Write-UIHost -English "Plan only: no VM will be created, started, provisioned, or bootstrapped." -Chinese "仅预览：不会创建、启动、provision 或 bootstrap 任何 VM。" -ForegroundColor Cyan
    Write-UIHost -English "  Runtime:      $RuntimeName" -Chinese "  运行时:      $RuntimeName" -ForegroundColor DarkGray
    if ($resourceProfile.RuntimeNamespace) {
        Write-UIHost -English "  Namespace:    $($resourceProfile.RuntimeNamespace) (resource: $($resourceProfile.RuntimeResourceName))" -Chinese "  Namespace:    $($resourceProfile.RuntimeNamespace) (资源: $($resourceProfile.RuntimeResourceName))" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  VMX:          $vmxPath" -Chinese "  VMX:          $vmxPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Current:      $status" -Chinese "  当前状态:    $status" -ForegroundColor DarkGray
    Write-UIHost -English "  ISO:          $plannedIsoPath" -Chinese "  ISO:          $plannedIsoPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Static IP:    $(if ($rt.static_ip) { $rt.static_ip } else { 'not configured' })" -Chinese "  Static IP:    $(if ($rt.static_ip) { $rt.static_ip } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Workspace:    $(Join-Path (Resolve-Path 'workspace_root') $rt.workspace)" -Chinese "  工作区:      $(Join-Path (Resolve-Path 'workspace_root') $rt.workspace)" -ForegroundColor DarkGray
    if ($status -eq "not-created") {
        Write-UIHost -English "  Would create VM from ISO and start provisioning unless -NoProvision is used." -Chinese "  将从 ISO 创建 VM 并开始 provisioning，除非使用 -NoProvision。" -ForegroundColor DarkGray
    } elseif ($status -match "running") {
        Write-UIHost -English "  Would detect running VM and continue bootstrap readiness checks unless -NoBootstrap is used." -Chinese "  将检测到运行中的 VM 并继续 bootstrap readiness 检查，除非使用 -NoBootstrap。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  Would start existing VM and continue bootstrap readiness checks unless -NoBootstrap is used." -Chinese "  将启动已有 VM 并继续 bootstrap readiness 检查，除非使用 -NoBootstrap。" -ForegroundColor DarkGray
    }
    return
}

# --- Case 1: VM exists ---
$statusResult = Get-VMStatus -Name $resourceProfile.RuntimeResourceName
$vmExists = ($statusResult.Success -and $statusResult.Data -ne "not-created")
$status = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }

if ($vmExists) {

    if ($NoProvision) {
        Write-UIHost -English "Runtime '$RuntimeName' definition exists (status: $status). Provisioning/start skipped." -Chinese "运行时 '$RuntimeName' 定义已存在（状态: $status）。已跳过 provisioning/start。" -ForegroundColor Yellow
        Write-UIHost -English "  VMX: $vmxPath" -Chinese "  VMX: $vmxPath" -ForegroundColor DarkGray
        return
    }

    if ($status -match "running") {
        Write-UIHost -English "Runtime '$RuntimeName' is already running." -Chinese "运行时 '$RuntimeName' 已在运行。" -ForegroundColor Green
        Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath -WaitForProvisioning
        return
    }

    Write-UIHost -English "VM exists (status: $status). Starting..." -Chinese "VM 已存在（状态: $status）。正在启动..." -ForegroundColor Yellow
    $startResult = Start-VM -Name $resourceProfile.RuntimeResourceName -Mode "nogui"
    if (-not $startResult.Success) {
        Write-ErrorLog -Message "Failed to start VM: $($startResult.Error)" -Component "cli.up"
        exit 1
    }

    Write-UIHost -English "  VM started." -Chinese "  VM 已启动。" -ForegroundColor Green
    Start-Sleep -Seconds 15

    Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath -WaitForProvisioning
    return
}

# --- Case 2: VM doesn't exist — auto-create with Phase 2 VM Factory ---
Write-UIHost -English "VM does not exist. Phase 2: Auto-provisioning from ISO..." -Chinese "VM 不存在。阶段 2：将从 ISO 自动 provisioning..." -ForegroundColor Yellow
Write-Host ""
if ($resourceProfile.RuntimeNamespace) {
    Write-UIHost -English "  Namespace: $($resourceProfile.RuntimeNamespace) (resource: $($resourceProfile.RuntimeResourceName))" -Chinese "  Namespace: $($resourceProfile.RuntimeNamespace) (资源: $($resourceProfile.RuntimeResourceName))" -ForegroundColor Cyan
    Write-UIHost -English "  VMX:       $($factoryLayout.VmxPath)" -Chinese "  VMX:       $($factoryLayout.VmxPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  Ensure this checkout uses distinct vm_store, workspace_root, and static IP values before running another version at the same time." -Chinese "  同时运行另一个版本前，请确保当前 checkout 使用独立的 vm_store、workspace_root 和 static IP。" -ForegroundColor Yellow
}
Assert-VMwareNatReadyForRuntimeCreate -TargetRuntime $RuntimeName

# Check ISO
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
if ($IsoPath) {
    $isoPath = $IsoPath
} else {
    $isoPath = Join-Path $isoCache $isoName
}

if (-not (Test-Path $isoPath)) {
    Write-ErrorLog -Message "OS ISO not found: $isoPath" -Component "cli.up"
    Write-Host ""
    Write-UIHost -English "Please download a supported Linux ISO and run:" -Chinese "请下载受支持的 Linux ISO 并运行:" -ForegroundColor Yellow
    Write-Host "  adpos up $RuntimeName -IsoPath <path-to-iso>" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Or place the ISO at: $isoPath" -Chinese "或将 ISO 放到: $isoPath" -ForegroundColor DarkGray
    exit 1
}

# Create the VM with full autoinstall
try {
    $vmxPath = New-RuntimeVM -RuntimeName $RuntimeName -IsoPath $IsoPath -Layout $factoryLayout -StartAfterCreate:(!$NoProvision) -SkipProvision:$NoProvision
} catch {
    Write-ErrorLog -Message "VM creation failed: $_" -Component "cli.up"
    exit 1
}

if ($NoProvision) {
    Write-Host ""
    Write-UIHost -English "Runtime '$RuntimeName' definition is ready. Provisioning, startup, and bootstrap were skipped." -Chinese "运行时 '$RuntimeName' 定义已就绪。已跳过 provisioning、startup 和 bootstrap。" -ForegroundColor Yellow
    Write-UIHost -English "  Start later: adpos up $RuntimeName" -Chinese "  稍后启动: adpos up $RuntimeName" -ForegroundColor DarkGray
    Write-UIHost -English "  Status:      adpos status $RuntimeName" -Chinese "  状态:      adpos status $RuntimeName" -ForegroundColor DarkGray
    return
}

# --- Bootstrap (if not skipped) ---
Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath

Write-Host ""
Write-UIHost -English "Runtime '$RuntimeName' ready." -Chinese "运行时 '$RuntimeName' 已就绪。" -ForegroundColor Green
