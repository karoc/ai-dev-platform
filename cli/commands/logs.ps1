# ADP-OS Logs Command
# Show runtime logs (bootstrap, system, sync)

param(
    [string]$RuntimeName
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos logs <runtime> (frontend|backend|agent)" -Chinese "用法: adpos logs <runtime> (frontend|backend|agent)") -Component "cli.logs"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Chinese "未知运行时: $RuntimeName。可用: $((Get-AllRuntimeNames) -join ', ')") -Component "cli.logs"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Showing logs for: $RuntimeName" -Chinese "正在显示日志: $RuntimeName") -Component "cli.logs"

$logsDir = Join-Path (Get-ProjectRoot) "logs"

Write-Host ""
Write-UIHost -English "Logs for runtime: $RuntimeName" -Chinese "运行时日志: $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Platform logs
$platformLog = Join-Path $logsDir "adp-$(Get-Date -Format 'yyyy-MM-dd').log"
if (Test-Path $platformLog) {
    Write-UIHost -English "--- Platform Log ($platformLog) ---" -Chinese "--- 平台日志 ($platformLog) ---" -ForegroundColor Yellow
    $lines = Get-Content $platformLog -Tail 50
    foreach ($line in $lines) {
        if ($line -match $RuntimeName) {
            Write-Host $line -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-UIHost -English "For VM console output, check VMware Workstation." -Chinese "如需查看 VM 控制台输出，请检查 VMware Workstation。" -ForegroundColor DarkGray
