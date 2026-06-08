# ADP-OS CLI smoke tests
# Non-destructive behavior checks for command dispatch, preview paths, and input errors.

$ErrorActionPreference = "Stop"

$smokeParts = @(
    "lib\cli-smoke-common.ps1",
    "cli-smoke-core.ps1",
    "cli-smoke-workspace-readonly.ps1",
    "cli-smoke-workspace-task.ps1",
    "cli-smoke-workspace-manifest.ps1",
    "cli-smoke-misc.ps1"
)

foreach ($part in $smokeParts) {
    . (Join-Path $PSScriptRoot $part)
}

Write-Output "CLI smoke tests OK"
