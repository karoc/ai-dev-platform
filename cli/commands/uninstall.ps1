# ADP-OS uninstall command.
# Safe default: unregisters the global adpos command only.

param(
    [switch]$NonInteractive
)

$uninstallScript = Join-Path (Get-ProjectRoot) "uninstall.ps1"
$uninstallArgs = @()
if ($NonInteractive) { $uninstallArgs += "-NonInteractive" }

& $uninstallScript @uninstallArgs
exit $LASTEXITCODE
