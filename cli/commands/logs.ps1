# ADP-OS Logs Command
# Show runtime logs (bootstrap, system, sync)

param(
    [string]$RuntimeName
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message "Usage: adp logs <runtime> (frontend|backend|agent)" -Component "cli.logs"
    exit 1
}

Write-InfoLog -Message "Showing logs for: $RuntimeName" -Component "cli.logs"

$logsDir = Join-Path (Get-ProjectRoot) "logs"

Write-Host ""
Write-Host "Logs for runtime: $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Platform logs
$platformLog = Join-Path $logsDir "adp-$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $platformLog) {
    Write-Host "--- Platform Log ($platformLog) ---" -ForegroundColor Yellow
    $lines = Get-Content $platformLog -Tail 50
    foreach ($line in $lines) {
        if ($line -match $RuntimeName) {
            Write-Host $line -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "For VM console output, check VMware Workstation." -ForegroundColor DarkGray
