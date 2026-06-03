# Sync ADP-OS from WSL to Windows native path for testing
# Run from WSL: pwsh scripts/sync-to-windows.ps1
# Or from bash: rsync -av --delete /home/karoc/ai-dev-platform/ /mnt/c/Users/qqwto/dev/adp-os/

param(
    [string]$WindowsPath = "D:\Dev\ai-dev-platform"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Syncing ADP-OS to Windows..." -ForegroundColor Cyan
Write-Host "  Source: $repoRoot"
Write-Host "  Target: $WindowsPath"

# Ensure target directory exists
if (-not (Test-Path $WindowsPath)) {
    New-Item -ItemType Directory -Path $WindowsPath -Force | Out-Null
}

# Sync using rsync via WSL bash
$wslSource = (wsl wslpath -u $WindowsPath 2>$null) -replace "`n|`r", ""
if (-not $wslSource) {
    # Fallback: convert Windows path to WSL /mnt/c/ path manually
    $wslSource = "/mnt/" + ($WindowsPath -replace ':\\', '/').ToLower() -replace '\\', '/'
}

$wslCommand = "rsync -av --delete --exclude='.git' /home/karoc/ai-dev-platform/ $wslSource/"
Write-Host "  Running: $wslCommand" -ForegroundColor DarkGray
wsl bash -c $wslCommand

Write-Host ""
Write-Host "Sync complete. Ready for testing:" -ForegroundColor Green
Write-Host "  pwsh.exe -File $WindowsPath\tests\validate.ps1 -Quick" -ForegroundColor Yellow
Write-Host "  pwsh.exe -File $WindowsPath\test-integration.ps1" -ForegroundColor Yellow
