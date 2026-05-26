# ADP-OS Restore Command
# Restore a runtime from a named snapshot

param(
    [string]$RuntimeName,
    [string]$SnapshotName
)

if (-not $RuntimeName -or -not $SnapshotName) {
    Write-ErrorLog -Message "Usage: adp restore <runtime> <snapshot-name>" -Component "cli.restore"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName" -Component "cli.restore"
    exit 1
}

Write-InfoLog -Message "Restoring snapshot: $RuntimeName/$SnapshotName" -Component "cli.restore"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-ErrorLog -Message "VM not found: $vmxPath" -Component "cli.restore"
    exit 1
}

Write-Host "Restoring runtime '$RuntimeName' from snapshot '$SnapshotName'..." -ForegroundColor Yellow
Write-WarnLog -Message "This will discard current VM state." -Component "cli.restore"

$result = Restore-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName

if ($result.Success) {
    Write-Host "  Restored to snapshot '$SnapshotName'." -ForegroundColor Green
} else {
    Write-ErrorLog -Message "Restore failed: $($result.StdErr)" -Component "cli.restore"
    exit 1
}
