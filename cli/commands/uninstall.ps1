# ADP-OS uninstall command.
# Safe default: unregisters the global adpos command only.

[CmdletBinding()]
param(
    [switch]$NonInteractive,
    [switch]$Force
)

$uninstallScript = Join-Path (Get-ProjectRoot) "uninstall.ps1"
$uninstallArgs = @()
if ($NonInteractive) { $uninstallArgs += "-NonInteractive" }
if ($Force) { $uninstallArgs += "-Force" }

& $uninstallScript @uninstallArgs
exit $LASTEXITCODE
