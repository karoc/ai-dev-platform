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
    $partWatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "SMOKE PART start: $part"
    try {
        . (Join-Path $PSScriptRoot $part)
        $partWatch.Stop()
        Write-Host ("SMOKE PART ok: {0} ({1:n1}s)" -f $part, $partWatch.Elapsed.TotalSeconds)
    } catch {
        $partWatch.Stop()
        Write-Host ("SMOKE PART failed: {0} ({1:n1}s)" -f $part, $partWatch.Elapsed.TotalSeconds)
        throw
    }
}

Write-Output "CLI smoke tests OK"
