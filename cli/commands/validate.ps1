# ADP-OS Validate Command
# Runs the shared repository validation suite (tests/validate.ps1).
# Accepts the same flags: -Quick, -SkipCliSmoke, -SkipInstallerSmoke, -SkipShellSyntax.

[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$SkipCliSmoke,
    [switch]$SkipInstallerSmoke,
    [switch]$SkipShellSyntax
)

$ErrorActionPreference = "Stop"

$validateScript = Join-Path $script:ProjectRoot "tests\validate.ps1"

Write-Host ""
Write-UIHost -English "ADP-OS Repository Validation" -Chinese "ADP-OS 仓库验证" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$validateArgs = @()
if ($Quick) { $validateArgs += "-Quick" }
if ($SkipCliSmoke) { $validateArgs += "-SkipCliSmoke" }
if ($SkipInstallerSmoke) { $validateArgs += "-SkipInstallerSmoke" }
if ($SkipShellSyntax) { $validateArgs += "-SkipShellSyntax" }

& $validateScript @validateArgs
if ($LASTEXITCODE) {
    exit $LASTEXITCODE
}
