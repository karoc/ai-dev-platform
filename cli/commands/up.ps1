# ADP-OS Up Command (Phase 2)
# Starts a runtime — auto-creates VM from ISO if needed

param(
    [string]$RuntimeName,
    [switch]$NoBootstrap,
    [switch]$NoProvision,
    [switch]$Plan,
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp up <runtime> (frontend|backend|agent) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision]" -Chinese "用法: adp up <runtime> (frontend|backend|agent) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision]") -Component "cli.up"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Chinese "未知运行时: $RuntimeName。可用: $((Get-AllRuntimeNames) -join ', ')") -Component "cli.up"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "adp up $RuntimeName (Phase 2)" -Chinese "adp up $RuntimeName（阶段 2）") -Component "cli.up"

$rt = Get-RuntimeConfig $RuntimeName
$config = Get-PlatformConfig
$vmStore = Resolve-Path "vm_store"
$isoCache = Resolve-Path "iso_cache"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
Initialize-VmFactory -ProjectRoot (Get-ProjectRoot) -IsoCachePath $isoCache -VmStorePath $vmStore

function Get-RuntimeConnectionIP {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    if ($staticIp) {
        return $staticIp
    }

    return Get-VMIP $TargetVmxPath
}

function Write-RuntimeConnectionSummary {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath
    )

    $rtConfig = Get-RuntimeConfig $TargetRuntime
    $config = Get-PlatformConfig
    $staticIp = Get-RuntimeStaticIP $TargetRuntime
    $detectedIp = $null
    try {
        $detectedIp = Get-VMIP $TargetVmxPath
    } catch {}

    $ip = if ($staticIp) { $staticIp } else { $detectedIp }
    $port = if ($rtConfig.PSObject.Properties.Name -contains "ssh_port" -and $rtConfig.ssh_port) { [int]$rtConfig.ssh_port } else { 22 }
    $user = if ($config.defaults.admin_user) { [string]$config.defaults.admin_user } else { "adp" }
    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    $workspaceRoot = Resolve-Path "workspace_root"
    $workspacePath = Join-Path $workspaceRoot $rtConfig.workspace
    $alias = "adp-os-adp-$TargetRuntime"

    Write-Host ""
    Write-UIHost -English "Connection details:" -Chinese "连接信息:" -ForegroundColor Cyan
    if ($ip) {
        Write-Host "  IP:        $ip" -ForegroundColor Cyan
        if ($staticIp -and $detectedIp -and $staticIp -ne $detectedIp) {
            Write-UIHost -English "  Detected:  $detectedIp (VMware reported this, but ADP-OS is using configured static IP)" -Chinese "  探测到:  $detectedIp (VMware 报告了该地址，但 ADP-OS 会使用配置的 static IP)" -ForegroundColor Yellow
        }
        Write-Host "  SSH:       ssh -i $keyPath -p $port $user@$ip" -ForegroundColor DarkGray
        Write-Host "  Alias:     ssh $alias" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  IP:        unavailable yet" -Chinese "  IP:        暂不可用" -ForegroundColor Yellow
        Write-UIHost -English "  SSH:       run adp status $TargetRuntime after the guest finishes booting" -Chinese "  SSH:       guest 启动完成后运行 adp status $TargetRuntime" -ForegroundColor DarkGray
    }
    Write-Host "  Workspace: $workspacePath" -ForegroundColor DarkGray
    Write-Host "  Sync:      adp sync start $TargetRuntime" -ForegroundColor DarkGray
    Write-Host "  Status:    adp status $TargetRuntime" -ForegroundColor DarkGray
    Write-Host "  Doctor:    adp doctor" -ForegroundColor DarkGray
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
        Write-Host "    .\cli\adp.ps1 network configure-local -Plan" -ForegroundColor DarkGray
        Write-Host "    .\cli\adp.ps1 network configure-local -Apply" -ForegroundColor DarkGray
        Write-UIHost -English "  Option B: Keep ADP's configured subnet and change VMware VMnet8 to $($hostNat.ConfiguredCidr) in Virtual Network Editor." -Chinese "  方案 B：保留 ADP 配置的网段，并在 VMware Virtual Network Editor 中把 VMnet8 改为 $($hostNat.ConfiguredCidr)。" -ForegroundColor DarkGray
        Write-UIHost -English "  Then rerun: .\cli\adp.ps1 doctor -FirstRun" -Chinese "  然后重新运行: .\cli\adp.ps1 doctor -FirstRun" -ForegroundColor DarkGray
        Write-UIHost -English "  No VM was created." -Chinese "  未创建任何 VM。" -ForegroundColor DarkGray
        exit 1
    }
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

    $ready = Test-AutoinstallReady -RuntimeName $TargetRuntime
    if (-not $ready) {
        if ($WaitForProvisioning) {
            Write-Host ""
            Write-UIHost -English "VM is still in Ubuntu install/provisioning. ADP will keep monitoring readiness signals." -Chinese "VM 仍在进行 Ubuntu 安装/provisioning。ADP 会继续监控 readiness signals。" -ForegroundColor Yellow
            Write-UIHost -English "  This can take 15-45 minutes on first creation; it is not an SSH failure while install-monitor heartbeats continue." -Chinese "  首次创建通常需要 15-45 分钟；只要 install-monitor 心跳仍在继续，这不是 SSH 失败。" -ForegroundColor DarkGray
            $ready = Wait-AutoinstallComplete -VmxPath $TargetVmxPath -RuntimeName $TargetRuntime -TimeoutMinutes 60
        }
    }

    if (-not $ready) {
        Write-Host ""
        Write-UIHost -English "VM is still installing or provisioning. Once the install finishes, run:" -Chinese "VM 仍在安装或 provisioning。安装完成后运行:" -ForegroundColor Yellow
        Write-Host "  adp up $TargetRuntime" -ForegroundColor DarkGray
        Write-UIHost -English "  (it will detect the VM and skip creation)" -Chinese "  (它会检测已有 VM 并跳过创建)" -ForegroundColor DarkGray
        Write-Host "  adp status $TargetRuntime" -ForegroundColor DarkGray
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
            Write-WarnLog -Message "Bootstrap did not complete cleanly. Try: adp doctor" -Component "cli.up"
        }
    } catch {
        Write-WarnLog -Message "Bootstrap had issues but VM is running. Try: adp doctor" -Component "cli.up"
    }

    Write-RuntimeConnectionSummary -TargetRuntime $TargetRuntime -TargetVmxPath $TargetVmxPath
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS: Starting $RuntimeName" -Chinese "  ADP-OS: 正在启动 $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CPU: $($rt.cpu) cores  |  RAM: $($rt.memory) MB  |  Disk: $($rt.disk) GB" -ForegroundColor DarkGray
if ($rt.danger) {
    Write-UIHost -English "  Agent profile: high-IO runtime for AI agent workloads" -Chinese "  Agent profile: 面向 AI agent 工作负载的 high-IO 运行时" -ForegroundColor Yellow
    Write-UIHost -English "  Snapshot recommended before destructive or large-scale tasks." -Chinese "  建议在破坏性或大规模任务前创建快照。" -ForegroundColor DarkGray
}
Write-Host ""

if ($Plan) {
    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $plannedIsoPath = if ($IsoPath) { $IsoPath } else { Join-Path $isoCache $isoName }
    $exists = Test-Path $vmxPath
    $status = "not-created"
    if ($exists) {
        if (Test-VMwareAvailable) {
            Initialize-VMware | Out-Null
            $status = Get-VMStatus $vmxPath
        } else {
            $status = "exists-vmware-unavailable"
        }
    }
    Write-UIHost -English "Plan only: no VM will be created, started, provisioned, or bootstrapped." -Chinese "仅预览：不会创建、启动、provision 或 bootstrap 任何 VM。" -ForegroundColor Cyan
    Write-UIHost -English "  Runtime:      $RuntimeName" -Chinese "  运行时:      $RuntimeName" -ForegroundColor DarkGray
    Write-Host "  VMX:          $vmxPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Current:      $status" -Chinese "  当前状态:    $status" -ForegroundColor DarkGray
    Write-Host "  ISO:          $plannedIsoPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Static IP:    $(if ($rt.static_ip) { $rt.static_ip } else { 'not configured' })" -Chinese "  Static IP:    $(if ($rt.static_ip) { $rt.static_ip } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Workspace:    $(Join-Path (Resolve-Path 'workspace_root') $rt.workspace)" -Chinese "  工作区:      $(Join-Path (Resolve-Path 'workspace_root') $rt.workspace)" -ForegroundColor DarkGray
    if (-not $exists) {
        Write-UIHost -English "  Would create VM from ISO and start provisioning unless -NoProvision is used." -Chinese "  将从 ISO 创建 VM 并开始 provisioning，除非使用 -NoProvision。" -ForegroundColor DarkGray
    } elseif ($status -match "running") {
        Write-UIHost -English "  Would detect running VM and continue bootstrap readiness checks unless -NoBootstrap is used." -Chinese "  将检测到运行中的 VM 并继续 bootstrap readiness 检查，除非使用 -NoBootstrap。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  Would start existing VM and continue bootstrap readiness checks unless -NoBootstrap is used." -Chinese "  将启动已有 VM 并继续 bootstrap readiness 检查，除非使用 -NoBootstrap。" -ForegroundColor DarkGray
    }
    return
}

Initialize-VMware | Out-Null

# --- Case 1: VM exists ---
if (Test-Path $vmxPath) {
    $status = Get-VMStatus $vmxPath

    if ($NoProvision) {
        Write-UIHost -English "Runtime '$RuntimeName' definition exists (status: $status). Provisioning/start skipped." -Chinese "运行时 '$RuntimeName' 定义已存在（状态: $status）。已跳过 provisioning/start。" -ForegroundColor Yellow
        Write-Host "  VMX: $vmxPath" -ForegroundColor DarkGray
        return
    }

    if ($status -match "running") {
        Write-UIHost -English "Runtime '$RuntimeName' is already running." -Chinese "运行时 '$RuntimeName' 已在运行。" -ForegroundColor Green
        Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath -WaitForProvisioning
        return
    }

    Write-UIHost -English "VM exists (status: $status). Starting..." -Chinese "VM 已存在（状态: $status）。正在启动..." -ForegroundColor Yellow
    $startResult = Start-VM -VmxPath $vmxPath -Mode "nogui"
    if (-not $startResult.Success) {
        Write-ErrorLog -Message "Failed to start VM: $($startResult.StdErr)" -Component "cli.up"
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
    Write-Host "  adp up $RuntimeName -IsoPath <path-to-iso>" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Or place the ISO at: $isoPath" -Chinese "或将 ISO 放到: $isoPath" -ForegroundColor DarkGray
    exit 1
}

# Create the VM with full autoinstall
try {
    $vmxPath = New-RuntimeVM -RuntimeName $RuntimeName -IsoPath $IsoPath -StartAfterCreate:(!$NoProvision) -SkipProvision:$NoProvision
} catch {
    Write-ErrorLog -Message "VM creation failed: $_" -Component "cli.up"
    exit 1
}

if ($NoProvision) {
    Write-Host ""
    Write-UIHost -English "Runtime '$RuntimeName' definition is ready. Provisioning, startup, and bootstrap were skipped." -Chinese "运行时 '$RuntimeName' 定义已就绪。已跳过 provisioning、startup 和 bootstrap。" -ForegroundColor Yellow
    Write-UIHost -English "  Start later: adp up $RuntimeName" -Chinese "  稍后启动: adp up $RuntimeName" -ForegroundColor DarkGray
    Write-Host "  Status:      adp status $RuntimeName" -ForegroundColor DarkGray
    return
}

# --- Bootstrap (if not skipped) ---
Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath

Write-Host ""
Write-UIHost -English "Runtime '$RuntimeName' ready." -Chinese "运行时 '$RuntimeName' 已就绪。" -ForegroundColor Green
