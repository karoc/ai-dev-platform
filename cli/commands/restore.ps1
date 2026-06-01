# ADP-OS Restore Command
# Restore a runtime from a named snapshot

param(
    [string]$RuntimeName,
    [string]$SnapshotName
)

if (-not $RuntimeName -or -not $SnapshotName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp restore <runtime> <snapshot-name>" -Chinese "用法: adp restore <runtime> <snapshot-name>") -Component "cli.restore"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName" -Chinese "未知运行时: $RuntimeName") -Component "cli.restore"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Restoring snapshot: $RuntimeName/$SnapshotName" -Chinese "正在恢复快照: $RuntimeName/$SnapshotName") -Component "cli.restore"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-ErrorLog -Message (Get-UIText -English "VM not found: $vmxPath" -Chinese "未找到 VM: $vmxPath") -Component "cli.restore"
    exit 1
}

Write-UIHost -English "Restoring runtime '$RuntimeName' from snapshot '$SnapshotName'..." -Chinese "正在从快照 '$SnapshotName' 恢复运行时 '$RuntimeName'..." -ForegroundColor Yellow
Write-WarnLog -Message (Get-UIText -English "This will discard current VM state." -Chinese "这将丢弃当前 VM 状态。") -Component "cli.restore"

$result = Restore-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName

if ($result.Success) {
    Write-UIHost -English "  Restored to snapshot '$SnapshotName'." -Chinese "  已恢复到快照 '$SnapshotName'。" -ForegroundColor Green
} else {
    Write-ErrorLog -Message (Get-UIText -English "Restore failed: $($result.StdErr)" -Chinese "恢复失败: $($result.StdErr)") -Component "cli.restore"
    exit 1
}
