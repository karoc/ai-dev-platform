# ADP-OS Restore Command
# Restore a runtime from a named snapshot
# Protected: requires -Force to execute, -Plan for dry-run preview

param(
    [string]$RuntimeName,
    [string]$SnapshotName,
    [switch]$Plan,
    [switch]$Force
)

if (-not $RuntimeName -or -not $SnapshotName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp restore <runtime> <snapshot-name> [-Plan] [-Force]" -Chinese "用法: adp restore <runtime> <snapshot-name> [-Plan] [-Force]") -Component "cli.restore"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName" -Chinese "未知运行时: $RuntimeName") -Component "cli.restore"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Restoring snapshot: $RuntimeName/$SnapshotName" -Chinese "正在恢复快照: $RuntimeName/$SnapshotName") -Component "cli.restore"

# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot | Out-Null

$statusResult = Get-VMStatus -Name $RuntimeName
if (-not $statusResult.Success -or $statusResult.Data -eq "not-created") {
    Write-ErrorLog -Message (Get-UIText -English "VM not found for runtime: $RuntimeName" -Chinese "未找到 VM: $RuntimeName") -Component "cli.restore"
    exit 1
}

Write-Host ""
Write-UIHost -English "RESTORE runtime: $RuntimeName" -Chinese "恢复运行时: $RuntimeName" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host "  Snapshot: $SnapshotName" -ForegroundColor DarkGray
Write-Host ""

if ($Plan) {
    Write-UIHost -English "Plan only: no changes will be made." -Chinese "仅预览：不会执行任何更改。" -ForegroundColor Cyan
    Write-UIHost -English "  Would stop VM if running" -Chinese "  如果 VM 正在运行将停止" -ForegroundColor DarkGray
    Write-UIHost -English "  Would restore snapshot: '$SnapshotName'" -Chinese "  将恢复快照: '$SnapshotName'" -ForegroundColor DarkGray
    Write-UIHost -English "  Current VM state would be discarded." -Chinese "  当前 VM 状态将被丢弃。" -ForegroundColor DarkGray
    return
}

if (-not $Force) {
    Write-UIHost -English "This will discard the CURRENT VM state and restore snapshot '$SnapshotName'." -Chinese "这将丢弃当前 VM 状态并恢复快照 '$SnapshotName'。" -ForegroundColor Red
    Write-UIHost -English "Run 'adp restore $RuntimeName $SnapshotName -Force' to confirm, or 'adp restore $RuntimeName $SnapshotName -Plan' to preview." -Chinese "运行 'adp restore $RuntimeName $SnapshotName -Force' 确认，或 'adp restore $RuntimeName $SnapshotName -Plan' 预览。" -ForegroundColor Yellow
    return
}

Write-UIHost -English "Restoring runtime '$RuntimeName' from snapshot '$SnapshotName'..." -Chinese "正在从快照 '$SnapshotName' 恢复运行时 '$RuntimeName'..." -ForegroundColor Yellow

$result = Restore-Snapshot -Name $RuntimeName -SnapshotName $SnapshotName

if ($result.Success) {
    Write-UIHost -English "  Restored to snapshot '$SnapshotName'." -Chinese "  已恢复到快照 '$SnapshotName'。" -ForegroundColor Green
} else {
    Write-ErrorLog -Message (Get-UIText -English "Restore failed: $($result.Error)" -Chinese "恢复失败: $($result.Error)") -Component "cli.restore"
    exit 1
}
