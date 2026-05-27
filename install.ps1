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
. "$script:ProjectRoot\runtimes\vmware\vm-factory.ps1"

# --- Initialize ---
Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs") -Level "INFO"
Write-InfoLog -Message "ADP-OS Install starting..." -Component "install"
Write-InfoLog -Message "Project root: $script:ProjectRoot" -Component "install"

function Add-DependencyResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Path = "",
        [string]$Remediation = ""
    )

    $script:deps += @{
        Name        = $Name
        Status      = $Status
        Path        = $Path
        Remediation = $Remediation
    }
}

function Write-DependencyLine {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [string]$Remediation = ""
    )

    $color = switch ($Status) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "MISSING" { "Red" }
        default { "DarkGray" }
    }
    $suffix = if ($Detail) { " — $Detail" } else { "" }
    Write-Host "  $Name [$Status]$suffix" -ForegroundColor $color
    if ($Remediation) {
        Write-Host "    $Remediation" -ForegroundColor DarkGray
    }
}

function Test-WSLCommand {
    param([string]$Command)

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $false
    }

    & $wsl.Source bash -lc "command -v $Command >/dev/null 2>&1" 2>$null
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

$script:deps = @()

if ($SkipDependencyCheck) {
    Write-Host "  Dependency checks skipped by -SkipDependencyCheck." -ForegroundColor Yellow
} else {
    # PowerShell 7+
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 7) {
        Write-DependencyLine -Name "PowerShell 7+" -Status "OK" -Detail "v$psVersion"
        Add-DependencyResult -Name "PowerShell 7+" -Status "OK"
    } else {
        $remediation = "Install PowerShell 7 or newer."
        Write-DependencyLine -Name "PowerShell 7+" -Status "WARN" -Detail "v$psVersion" -Remediation $remediation
        Add-DependencyResult -Name "PowerShell 7+" -Status "WARN" -Remediation $remediation
    }

    # VMware Workstation / vmrun
    $vmwareStatus = Test-VMwareAvailable
    if ($vmwareStatus) {
        $vmrunPath = Find-Vmrun
        Write-DependencyLine -Name "VMware Workstation (vmrun)" -Status "OK" -Detail $vmrunPath
        Add-DependencyResult -Name "VMware Workstation (vmrun)" -Status "OK" -Path $vmrunPath
    } else {
        $remediation = "Install VMware Workstation Pro and ensure vmrun.exe is available."
        Write-DependencyLine -Name "VMware Workstation (vmrun)" -Status "MISSING" -Detail "vmrun.exe not found" -Remediation $remediation
        Add-DependencyResult -Name "VMware Workstation (vmrun)" -Status "MISSING" -Remediation $remediation
    }

    $diskManager = Find-VmwareDiskManager
    if ($diskManager) {
        Write-DependencyLine -Name "VMware disk manager" -Status "OK" -Detail $diskManager
        Add-DependencyResult -Name "VMware disk manager" -Status "OK" -Path $diskManager
    } else {
        $remediation = "Install VMware Workstation Pro with vmware-vdiskmanager.exe."
        Write-DependencyLine -Name "VMware disk manager" -Status "MISSING" -Detail "vmware-vdiskmanager.exe not found" -Remediation $remediation
        Add-DependencyResult -Name "VMware disk manager" -Status "MISSING" -Remediation $remediation
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        Write-DependencyLine -Name "WSL" -Status "OK" -Detail $wsl.Source
        Add-DependencyResult -Name "WSL" -Status "OK" -Path $wsl.Source
    } else {
        $remediation = "Install or enable WSL before remastering Ubuntu autoinstall ISOs."
        Write-DependencyLine -Name "WSL" -Status "MISSING" -Detail "wsl.exe not found" -Remediation $remediation
        Add-DependencyResult -Name "WSL" -Status "MISSING" -Remediation $remediation
    }

    if (Test-WSLCommand -Command "xorriso") {
        Write-DependencyLine -Name "WSL xorriso" -Status "OK"
        Add-DependencyResult -Name "WSL xorriso" -Status "OK"
    } else {
        $remediation = "Install with: wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`""
        Write-DependencyLine -Name "WSL xorriso" -Status "MISSING" -Detail "required for Ubuntu autoinstall ISO remastering" -Remediation $remediation
        Add-DependencyResult -Name "WSL xorriso" -Status "MISSING" -Remediation $remediation
    }

    $isoRemasterTool = Find-ISORemasterTool
    if ($isoRemasterTool) {
        Write-DependencyLine -Name "ISO remaster tool" -Status "OK" -Detail "$($isoRemasterTool.Type): $($isoRemasterTool.Path)"
        Add-DependencyResult -Name "ISO remaster tool" -Status "OK" -Path $isoRemasterTool.Path
    } else {
        $remediation = "Install xorriso natively or in WSL."
        Write-DependencyLine -Name "ISO remaster tool" -Status "MISSING" -Detail "xorriso not found" -Remediation $remediation
        Add-DependencyResult -Name "ISO remaster tool" -Status "MISSING" -Remediation $remediation
    }

    # Mutagen
    $mutagen = Find-Mutagen -ProjectRoot $script:ProjectRoot
    if ($mutagen) {
        $mutagenVersion = (& $mutagen version 2>$null | Select-Object -First 1)
        if ("$mutagenVersion" -match '^0\.18\.') {
            Write-DependencyLine -Name "Mutagen" -Status "OK" -Detail "$mutagenVersion at $mutagen"
            Add-DependencyResult -Name "Mutagen" -Status "OK" -Path $mutagen
        } else {
            $remediation = "ADP-OS is tested with Mutagen 0.18.x."
            Write-DependencyLine -Name "Mutagen" -Status "WARN" -Detail "$mutagenVersion at $mutagen" -Remediation $remediation
            Add-DependencyResult -Name "Mutagen" -Status "WARN" -Path $mutagen -Remediation $remediation
        }
    } else {
        $remediation = "Download Mutagen 0.18.x, place mutagen.exe at .tools\mutagen\mutagen.exe, or add it to PATH."
        Write-DependencyLine -Name "Mutagen" -Status "MISSING" -Detail "needed for workspace sync" -Remediation $remediation
        Add-DependencyResult -Name "Mutagen" -Status "MISSING" -Remediation $remediation
    }

    # OpenSSH Client
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if ($ssh) {
        Write-DependencyLine -Name "OpenSSH Client" -Status "OK" -Detail $ssh.Source
        Add-DependencyResult -Name "OpenSSH Client" -Status "OK" -Path $ssh.Source
    } else {
        $remediation = "Install the Windows OpenSSH Client optional feature."
        Write-DependencyLine -Name "OpenSSH Client" -Status "MISSING" -Remediation $remediation
        Add-DependencyResult -Name "OpenSSH Client" -Status "MISSING" -Remediation $remediation
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
    if (-not (Test-ISOReasonable -Path $IsoPath)) {
        Write-Host "  ISO warning: file should be a .iso and usually larger than 1 GB: $IsoPath" -ForegroundColor Yellow
    }
    if (-not (Test-Path $isoCache)) { New-Item -ItemType Directory -Path $isoCache -Force | Out-Null }
    Copy-Item $IsoPath $storedIso -Force
    Write-Host "  ISO copied to cache: $storedIso" -ForegroundColor Green
} elseif (Test-Path $storedIso) {
    $isoSize = [math]::Round((Get-Item $storedIso).Length / 1GB, 1)
    Write-Host "  ISO found in cache: $storedIso ($isoSize GB)" -ForegroundColor Green
    if (-not (Test-ISOReasonable -Path $storedIso)) {
        Write-Host "  ISO warning: file should be a .iso and usually larger than 1 GB." -ForegroundColor Yellow
    }
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

$missing = $script:deps | Where-Object { $_.Status -eq "MISSING" }
$warnings = $script:deps | Where-Object { $_.Status -eq "WARN" }
if ($SkipDependencyCheck) {
    Write-Host "Dependency checks were skipped." -ForegroundColor Yellow
} elseif ($missing) {
    Write-Host "Missing dependencies:" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Name)" -ForegroundColor Yellow
        if ($m.Remediation) {
            Write-Host "    $($m.Remediation)" -ForegroundColor DarkGray
        }
    }
    if ($warnings) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($w in $warnings) {
            Write-Host "  - $($w.Name)" -ForegroundColor Yellow
            if ($w.Remediation) {
                Write-Host "    $($w.Remediation)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
    Write-Host "Install missing items then re-run install.ps1" -ForegroundColor DarkGray
} elseif ($warnings) {
    Write-Host "Dependency warnings:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  - $($w.Name)" -ForegroundColor Yellow
        if ($w.Remediation) {
            Write-Host "    $($w.Remediation)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "All dependencies satisfied." -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  Place a supported Linux ISO in: $isoCache" -ForegroundColor DarkGray
Write-Host "  Then run Phase 2: adp init" -ForegroundColor DarkGray
Write-Host ""

Write-InfoLog -Message "ADP-OS Phase 1 install complete" -Component "install"
