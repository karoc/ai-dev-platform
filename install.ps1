# ADP-OS Install Script
# Phase 1: Project structure + config + VMware adapter bootstrap
# This script bootstraps the ADP-OS platform on Windows

param(
    [switch]$SkipDependencyCheck,
    [switch]$SkipVMValidation,
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot

# --- Banner ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS: AI Development Platform OS" -ForegroundColor Cyan
Write-Host "  Phase 1 — Platform Bootstrap" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Source Modules ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"
. "$script:ProjectRoot\adapters\windows\mutagen\mutagen.ps1"

# --- Initialize ---
Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs") -Level "INFO"
Write-InfoLog -Message "ADP-OS Install starting..." -Component "install"
Write-InfoLog -Message "Project root: $script:ProjectRoot" -Component "install"

# =============================================
# Step 1: Platform Detection
# =============================================
Write-Host "`n[1/6] Detecting platform..." -ForegroundColor Yellow
Write-InfoLog -Message "Platform detection starting" -Component "install"

$platform = Get-Platform
Write-InfoLog -Message "Detected platform: $platform" -Component "install"

if ($platform -ne "windows") {
    Write-WarnLog -Message "ADP-OS MVP requires Windows 11. Detected: $platform" -Component "install"
    Write-WarnLog -Message "macOS/Linux support reserved for future phases" -Component "install"
}

# Verify Windows 11
$osInfo = Get-CimInstance Win32_OperatingSystem
$winVersion = [Version]$osInfo.Version
if ($winVersion.Major -lt 10) {
    Write-ErrorLog -Message "Windows 10+ required. Detected: $($osInfo.Caption)" -Component "install"
    throw "Unsupported Windows version"
}
Write-InfoLog -Message "Windows version: $($osInfo.Caption) ($winVersion)" -Component "install"
Write-Host "  Platform: Windows (supported)" -ForegroundColor Green

# =============================================
# Step 2: Dependency Checks
# =============================================
Write-Host "`n[2/6] Checking dependencies..." -ForegroundColor Yellow
Write-InfoLog -Message "Dependency check starting" -Component "install"

$deps = @()

if ($SkipDependencyCheck) {
    Write-Host "  Dependency checks skipped by -SkipDependencyCheck." -ForegroundColor Yellow
} else {
    # PowerShell 7+
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 7) {
        Write-Host "  PowerShell $psVersion [OK]" -ForegroundColor Green
        $deps += @{ Name = "PowerShell 7+"; Status = "OK" }
    } else {
        Write-Host "  PowerShell $psVersion [WARN] — PowerShell 7+ recommended" -ForegroundColor Yellow
        $deps += @{ Name = "PowerShell 7+"; Status = "WARN" }
    }

    # VMware Workstation / vmrun
    $vmwareStatus = Test-VMwareAvailable
    if ($vmwareStatus) {
        $vmrunPath = Find-Vmrun
        Write-Host "  VMware Workstation (vmrun) [OK] — $vmrunPath" -ForegroundColor Green
        $deps += @{ Name = "VMware Workstation"; Status = "OK"; Path = $vmrunPath }
    } else {
        Write-Host "  VMware Workstation [MISSING] — vmrun.exe not found" -ForegroundColor Red
        Write-Host "    Install from: https://www.vmware.com/products/workstation-pro.html" -ForegroundColor DarkGray
        $deps += @{ Name = "VMware Workstation"; Status = "MISSING" }
    }

    # Mutagen
    $mutagen = Find-Mutagen -ProjectRoot $script:ProjectRoot
    if ($mutagen) {
        Write-Host "  Mutagen [OK] — $mutagen" -ForegroundColor Green
        $deps += @{ Name = "Mutagen"; Status = "OK" }
    } else {
        Write-Host "  Mutagen [MISSING] — will be needed for Phase 3 sync" -ForegroundColor Yellow
        Write-Host "    Download: https://github.com/mutagen-io/mutagen/releases" -ForegroundColor DarkGray
        Write-Host "    Place:    .tools\mutagen\mutagen.exe" -ForegroundColor DarkGray
        $deps += @{ Name = "Mutagen"; Status = "MISSING" }
    }

    # OpenSSH Client
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if ($ssh) {
        Write-Host "  OpenSSH Client [OK]" -ForegroundColor Green
        $deps += @{ Name = "OpenSSH Client"; Status = "OK" }
    } else {
        Write-Host "  OpenSSH Client [MISSING]" -ForegroundColor Yellow
        $deps += @{ Name = "OpenSSH Client"; Status = "MISSING" }
    }
}

# =============================================
# Step 3: Directory Structure
# =============================================
Write-Host "`n[3/6] Creating directory structure..." -ForegroundColor Yellow
Write-InfoLog -Message "Directory creation starting" -Component "install"

$workspaceRoot = Resolve-Path "workspace_root"
$isoCache = Resolve-Path "iso_cache"
$vmStore = Resolve-Path "vm_store"

Initialize-Filesystem -BasePath $workspaceRoot
Initialize-Filesystem -BasePath $vmStore

Write-Host "  Workspaces: $workspaceRoot" -ForegroundColor Green
Write-Host "  ISO Cache:  $isoCache" -ForegroundColor Green
Write-Host "  VM Store:   $vmStore" -ForegroundColor Green

# =============================================
# Step 4: ISO Check
# =============================================
Write-Host "`n[4/6] Checking OS ISO..." -ForegroundColor Yellow
Write-InfoLog -Message "ISO check starting" -Component "install"

$config = Get-PlatformConfig
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$storedIso = Join-Path $isoCache $isoName

if ($IsoPath) {
    Write-InfoLog -Message "User provided ISO: $IsoPath" -Component "install"
    if (-not (Test-Path $IsoPath)) {
        throw "Specified ISO not found: $IsoPath"
    }
    if (-not (Test-Path $isoCache)) { New-Item -ItemType Directory -Path $isoCache -Force | Out-Null }
    Copy-Item $IsoPath $storedIso -Force
    Write-Host "  ISO copied to cache: $storedIso" -ForegroundColor Green
} elseif (Test-Path $storedIso) {
    Write-Host "  ISO found in cache: $storedIso" -ForegroundColor Green
    Write-InfoLog -Message "ISO found in cache" -Component "install"
} else {
    Write-Host "  ISO not found. Please download a supported Linux ISO:" -ForegroundColor Yellow
    Write-Host "    Ubuntu Server 26.04 LTS: https://releases.ubuntu.com/26.04/" -ForegroundColor DarkGray
    Write-Host "    AlmaLinux 9: https://almalinux.org/get-almalinux/" -ForegroundColor DarkGray
    Write-Host "    Rocky Linux 9: https://rockylinux.org/download/" -ForegroundColor DarkGray
    Write-Host "    Debian 12: https://www.debian.org/distrib/" -ForegroundColor DarkGray
    Write-Host "  Place it at: $storedIso" -ForegroundColor DarkGray
    Write-Host "  Or run: .\install.ps1 -IsoPath <path-to-iso>" -ForegroundColor DarkGray
}

# =============================================
# Step 5: VMware Adapter Init
# =============================================
Write-Host "`n[5/6] Initializing VMware adapter..." -ForegroundColor Yellow
Write-InfoLog -Message "VMware adapter initialization" -Component "install"

if ($SkipVMValidation) {
    Write-Host "  VMware validation skipped by -SkipVMValidation." -ForegroundColor Yellow
} else {
    try {
        $vmrunPath = Initialize-VMware
        Write-Host "  vmrun: $vmrunPath [OK]" -ForegroundColor Green

        $registeredVMs = Get-RegisteredVMs
        Write-Host "  Registered VMs: $($registeredVMs.Count)" -ForegroundColor Cyan
        foreach ($vm in $registeredVMs) {
            Write-Host "    - $(Split-Path $vm -Leaf)" -ForegroundColor DarkGray
        }
    } catch {
        Write-ErrorLog -Message "VMware initialization failed: $_" -Component "install"
        throw
    }
}

# =============================================
# Step 6: Config Finalization
# =============================================
Write-Host "`n[6/6] Finalizing configuration..." -ForegroundColor Yellow
Write-InfoLog -Message "Config finalization" -Component "install"

Set-ADPInitialized

$topology = Get-TopologyConfig
$runtimeNames = Get-AllRuntimeNames

Write-Host "  Configured runtimes:" -ForegroundColor Cyan
foreach ($name in $runtimeNames) {
    $rt = $topology.$name
    $danger = if ($rt.danger) { " [DANGER]" } else { "" }
    Write-Host "    $name — CPU: $($rt.cpu), RAM: $($rt.memory)MB, Disk: $($rt.disk)GB$danger" -ForegroundColor DarkGray
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS Phase 1 Bootstrap Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$missing = $deps | Where-Object { $_.Status -eq "MISSING" }
if ($SkipDependencyCheck) {
    Write-Host "Dependency checks were skipped." -ForegroundColor Yellow
} elseif ($missing) {
    Write-Host "Missing dependencies:" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Name)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Install missing items then re-run install.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "All dependencies satisfied." -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  Place a supported Linux ISO in: $isoCache" -ForegroundColor DarkGray
Write-Host "  Then run Phase 2: adp init" -ForegroundColor DarkGray
Write-Host ""

Write-InfoLog -Message "ADP-OS Phase 1 install complete" -Component "install"
