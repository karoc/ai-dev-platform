# ADP-OS uninstall script.
# Safe default: unregisters the global adpos command only.
# This script intentionally supports Windows PowerShell 5.1 because uninstalling
# the command shim should not require the ADP-OS PowerShell 7 control plane.

param(
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot

. "$script:ProjectRoot\scripts\adpos-registration.ps1"

if (-not $NonInteractive) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ADP-OS Uninstall" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

$result = Uninstall-ADPOSCommandRegistration

if (-not $NonInteractive) {
    if ($result.RemovedShim) {
        Write-Host "Removed global command: adpos" -ForegroundColor Green
    } else {
        Write-Host "Global command was not registered: adpos" -ForegroundColor Yellow
    }
    Write-Host "  Shim: $($result.ShimPath)" -ForegroundColor DarkGray
    Write-Host "  PATH entry removed: $($result.BinPath)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "No VMs, workspace files, ISO cache, local tools, logs, or repository files were removed." -ForegroundColor Yellow
    Write-Host "Use explicit ADP-OS lifecycle commands before deleting runtime or workspace data." -ForegroundColor DarkGray
    Write-Host ""
}
