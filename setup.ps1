# ADP-OS One-Click Setup
# Run this script immediately after cloning the repository.
# It chains: precheck → ISO download → install → init → doctor
#
# Usage:
#   .\setup.ps1                        Interactive guided setup
#   .\setup.ps1 -IsoPath C:\...\ubuntu.iso   Use a pre-downloaded ISO
#   .\setup.ps1 -SkipIsoDownload        Skip ISO download (ISO already cached)
#   .\setup.ps1 -NonInteractive         Run without prompts (for scripts/CI)
#   .\setup.ps1 -Force                  Skip precheck, proceed anyway
#   .\setup.ps1 -NoRegisterCommand      Do not register the global adpos command

param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoRegisterCommand
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot

function Find-ADPPowerShell7 {
    $candidates = @(
        (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source,
        (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "PowerShell\7\pwsh.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\PowerShell\7\pwsh.exe"),
        (Join-Path $env:USERPROFILE "AppData\Local\Microsoft\WindowsApps\pwsh.exe")
    ) | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (Test-ADPPowerShell7 -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-ADPPowerShell7 {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) {
        return $false
    }

    try {
        & $Path -NoProfile -Command "if (`$PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }" *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Install-ADPPowerShell7WithWinget {
    $winget = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
    if (-not $winget) {
        return $false
    }

    Write-Host ""
    Write-Host "PowerShell 7 was not found. Installing PowerShell 7 with winget..." -ForegroundColor Cyan
    & $winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
    return $LASTEXITCODE -eq 0
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwsh = Find-ADPPowerShell7
    if (-not $pwsh) {
        if (Install-ADPPowerShell7WithWinget) {
            $pwsh = Find-ADPPowerShell7
        }
    }

    if ($pwsh) {
        $forwardArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
        if ($Distro -and $Distro -ne "ubuntu") { $forwardArgs += @("-Distro", $Distro) }
        if ($IsoPath) { $forwardArgs += @("-IsoPath", $IsoPath) }
        if ($SkipIsoDownload) { $forwardArgs += "-SkipIsoDownload" }
        if ($SkipDoctor) { $forwardArgs += "-SkipDoctor" }
        if ($NonInteractive) { $forwardArgs += "-NonInteractive" }
        if ($Force) { $forwardArgs += "-Force" }
        if ($NoRegisterCommand) { $forwardArgs += "-NoRegisterCommand" }

        Write-Host "Restarting ADP-OS setup with PowerShell 7: $pwsh" -ForegroundColor Cyan
        & $pwsh @forwardArgs
        exit $LASTEXITCODE
    }

    Write-Host ""
    Write-Host "ADP-OS requires PowerShell 7+ (pwsh.exe)." -ForegroundColor Red
    Write-Host "setup.ps1 tried to install it automatically with winget but could not find a working pwsh.exe." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install PowerShell 7, then rerun .\setup.ps1:" -ForegroundColor Cyan
    Write-Host "  winget install --id Microsoft.PowerShell --source winget" -ForegroundColor White
    Write-Host "Or download the MSI from:" -ForegroundColor Cyan
    Write-Host "  https://github.com/PowerShell/PowerShell/releases" -ForegroundColor White
    Write-Host ""
    exit 1
}

# --- Source Core Modules (same as the internal CLI) ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\core\utility\circuit-breaker.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\core\provider\provider-result.ps1"
. "$script:ProjectRoot\core\provider\provider-discovery.ps1"

Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs")

# Provider init — best-effort (may fail on systems without VMware)
$script:ProviderMode = Get-ProviderMode
if ($script:ProviderMode -eq "vmware-provider") {
    . "$script:ProjectRoot\adapters\windows\vmware\vmware-provider.ps1"
    try {
        $vmStore = Resolve-Path "vm_store"
        Initialize-Provider -ProviderType "vmware-workstation" -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null
    } catch {
        Write-WarnLog -Message "Provider init skipped (VMware not available): $_" -Component "setup"
    }
} else {
    . "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"
    try {
        Initialize-VMware | Out-Null
    } catch {
        Write-WarnLog -Message "VMware adapter init skipped (vmware not available): $_" -Component "setup"
    }
}

# --- Banner ---
if (-not $NonInteractive) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ADP-OS One-Click Setup" -ForegroundColor Cyan
    Write-Host "  AI Development Platform — Local Sandbox Infrastructure" -ForegroundColor DarkGray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "This will guide you through:" -ForegroundColor Yellow
    Write-Host "  1. Scan prerequisites (precheck)" -ForegroundColor DarkGray
    Write-Host "  2. Download Linux ISO (~2.6 GB, if needed)" -ForegroundColor DarkGray
    Write-Host "  3. Platform bootstrap and global adpos registration (install)" -ForegroundColor DarkGray
    Write-Host "  4. Platform initialization (init)" -ForegroundColor DarkGray
    Write-Host "  5. System diagnostics (doctor)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Estimated time: 15-30 min (mostly ISO download)" -ForegroundColor DarkGray
    Write-Host "Use -SkipIsoDownload if you already have the ISO cached." -ForegroundColor DarkGray
    Write-Host ""
}

# --- Delegate to quickstart (which handles precheck → ISO → install → init → doctor) ---
$quickstartPath = Join-Path $script:ProjectRoot "cli\commands\quickstart.ps1"
$quickstartArgs = @{
    Distro           = $Distro
    NonInteractive   = $NonInteractive
    Force            = $Force
}

if ($IsoPath) {
    $quickstartArgs.IsoPath = $IsoPath
}
if ($SkipIsoDownload) {
    $quickstartArgs.SkipIsoDownload = $true
}
if ($SkipDoctor) {
    $quickstartArgs.SkipDoctor = $true
}
if ($NoRegisterCommand) {
    $quickstartArgs.NoRegisterCommand = $true
}

Write-InfoLog -Message "setup.ps1 → quickstart.ps1" -Component "setup"
. $quickstartPath @quickstartArgs

exit $LASTEXITCODE
