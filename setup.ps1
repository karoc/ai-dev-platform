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

param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot

# --- Source Core Modules (same as adp.ps1) ---
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
    Write-Host "  3. Platform bootstrap (install)" -ForegroundColor DarkGray
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

Write-InfoLog -Message "setup.ps1 → quickstart.ps1" -Component "setup"
. $quickstartPath @quickstartArgs

exit $LASTEXITCODE
