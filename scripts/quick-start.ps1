# ADP-OS Quick Start — One-Click Setup Script
# Run this after cloning the repository to get from zero to a ready platform.
# Chains: precheck -> ISO download -> install -> init -> doctor
#
# Usage:
#   .\scripts\quick-start.ps1                        Interactive guided setup
#   .\scripts\quick-start.ps1 -IsoPath C:\...\ubuntu.iso  Use a pre-downloaded ISO
#   .\scripts\quick-start.ps1 -SkipIsoDownload        Skip ISO download (already cached)
#   .\scripts\quick-start.ps1 -NonInteractive         Run without prompts (for scripts/CI)
#   .\scripts\quick-start.ps1 -Force                  Skip precheck, proceed anyway

param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Resolve project root (works whether run from scripts\ or repo root)
$script:ProjectRoot = $PSScriptRoot
if ((Split-Path $PSScriptRoot -Leaf) -eq "scripts") {
    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
}

# Delegate to the main setup.ps1 which handles the full chain
$setupPath = Join-Path $script:ProjectRoot "setup.ps1"

if (-not (Test-Path $setupPath)) {
    Write-Host "ERROR: setup.ps1 not found at $setupPath" -ForegroundColor Red
    Write-Host "Make sure you are running from within the ai-dev-platform repository." -ForegroundColor Red
    exit 1
}

# Forward all parameters to setup.ps1
$setupArgs = @{
    Distro         = $Distro
    NonInteractive = $NonInteractive
    Force          = $Force
}
if ($IsoPath) {
    $setupArgs.IsoPath = $IsoPath
}
if ($SkipIsoDownload) {
    $setupArgs.SkipIsoDownload = $true
}
if ($SkipDoctor) {
    $setupArgs.SkipDoctor = $true
}

Write-Host "ADP-OS Quick Start — delegating to setup.ps1..." -ForegroundColor DarkGray
Write-Host ""

& $setupPath @setupArgs
exit $LASTEXITCODE
