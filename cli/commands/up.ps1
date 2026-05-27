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
    Write-ErrorLog -Message "Usage: adp up <runtime> (frontend|backend|agent) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision]" -Component "cli.up"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Component "cli.up"
    exit 1
}

Write-InfoLog -Message "adp up $RuntimeName (Phase 2)" -Component "cli.up"

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

function Invoke-BootstrapIfReady {
    param(
        [string]$TargetRuntime,
        [string]$TargetVmxPath,
        [switch]$WaitForProvisioning
    )

    if ($NoBootstrap) {
        return
    }

    $ready = Test-AutoinstallReady -RuntimeName $TargetRuntime
    if (-not $ready) {
        if ($WaitForProvisioning) {
            Write-Host ""
            Write-Host "VM is still provisioning. Continuing to wait..." -ForegroundColor Yellow
            $ready = Wait-AutoinstallComplete -VmxPath $TargetVmxPath -TimeoutMinutes 60
        }
    }

    if (-not $ready) {
        Write-Host ""
        Write-Host "VM is still provisioning. Once ready, run:" -ForegroundColor Yellow
        Write-Host "  adp up $TargetRuntime" -ForegroundColor DarkGray
        Write-Host "  (it will detect the VM and skip creation)" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "VM is ready. Running bootstrap..." -ForegroundColor Yellow

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
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS: Starting $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CPU: $($rt.cpu) cores  |  RAM: $($rt.memory) MB  |  Disk: $($rt.disk) GB" -ForegroundColor DarkGray
if ($rt.danger) {
    Write-Host "  Agent profile: high-IO runtime for AI agent workloads" -ForegroundColor Yellow
    Write-Host "  Snapshot recommended before destructive or large-scale tasks." -ForegroundColor DarkGray
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
    Write-Host "Plan only: no VM will be created, started, provisioned, or bootstrapped." -ForegroundColor Cyan
    Write-Host "  Runtime:      $RuntimeName" -ForegroundColor DarkGray
    Write-Host "  VMX:          $vmxPath" -ForegroundColor DarkGray
    Write-Host "  Current:      $status" -ForegroundColor DarkGray
    Write-Host "  ISO:          $plannedIsoPath" -ForegroundColor DarkGray
    Write-Host "  Static IP:    $(if ($rt.static_ip) { $rt.static_ip } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Workspace:    $(Join-Path (Resolve-Path 'workspace_root') $rt.workspace)" -ForegroundColor DarkGray
    if (-not $exists) {
        Write-Host "  Would create VM from ISO and start provisioning unless -NoProvision is used." -ForegroundColor DarkGray
    } elseif ($status -match "running") {
        Write-Host "  Would detect running VM and continue bootstrap readiness checks unless -NoBootstrap is used." -ForegroundColor DarkGray
    } else {
        Write-Host "  Would start existing VM and continue bootstrap readiness checks unless -NoBootstrap is used." -ForegroundColor DarkGray
    }
    return
}

Initialize-VMware | Out-Null

# --- Case 1: VM exists ---
if (Test-Path $vmxPath) {
    $status = Get-VMStatus $vmxPath

    if ($NoProvision) {
        Write-Host "Runtime '$RuntimeName' definition exists (status: $status). Provisioning/start skipped." -ForegroundColor Yellow
        Write-Host "  VMX: $vmxPath" -ForegroundColor DarkGray
        return
    }

    if ($status -match "running") {
        Write-Host "Runtime '$RuntimeName' is already running." -ForegroundColor Green
        try {
            $ip = Get-RuntimeConnectionIP -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath
            Write-Host "  IP: $ip" -ForegroundColor Cyan
            Write-Host "  SSH: ssh -i ~/.ssh/adp-os/adp-os adp@$ip" -ForegroundColor DarkGray
        } catch {
            Write-Host "  IP not yet available." -ForegroundColor Yellow
        }
        Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath -WaitForProvisioning
        return
    }

    Write-Host "VM exists (status: $status). Starting..." -ForegroundColor Yellow
    $startResult = Start-VM -VmxPath $vmxPath -Mode "nogui"
    if (-not $startResult.Success) {
        Write-ErrorLog -Message "Failed to start VM: $($startResult.StdErr)" -Component "cli.up"
        exit 1
    }

    Write-Host "  VM started." -ForegroundColor Green
    Start-Sleep -Seconds 15

    try {
        $ip = Get-RuntimeConnectionIP -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath
        Write-Host "  IP: $ip" -ForegroundColor Cyan
        Write-Host "  SSH: ssh -i ~/.ssh/adp-os/adp-os adp@$ip" -ForegroundColor DarkGray
    } catch {
        Write-Host "  Waiting for IP..." -ForegroundColor Yellow
    }
    Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath -WaitForProvisioning
    return
}

# --- Case 2: VM doesn't exist — auto-create with Phase 2 VM Factory ---
Write-Host "VM does not exist. Phase 2: Auto-provisioning from ISO..." -ForegroundColor Yellow
Write-Host ""

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
    Write-Host "Please download a supported Linux ISO and run:" -ForegroundColor Yellow
    Write-Host "  adp up $RuntimeName -IsoPath <path-to-iso>" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Or place the ISO at: $isoPath" -ForegroundColor DarkGray
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
    Write-Host "Runtime '$RuntimeName' definition is ready. Provisioning, startup, and bootstrap were skipped." -ForegroundColor Yellow
    return
}

# --- Bootstrap (if not skipped) ---
Invoke-BootstrapIfReady -TargetRuntime $RuntimeName -TargetVmxPath $vmxPath

Write-Host ""
Write-Host "Runtime '$RuntimeName' ready." -ForegroundColor Green
