# ADP-OS Snapshot Command
# Create named VM snapshots for a runtime

param(
    [string]$SubCommand,
    [string]$RuntimeName,
    [string]$SnapshotName
)

if (-not $SubCommand -or $SubCommand -ne "create") {
    Write-ErrorLog -Message "Usage: adp snapshot create <runtime> <snapshot-name>" -Component "cli.snapshot"
    exit 1
}

if (-not $RuntimeName -or -not $SnapshotName) {
    Write-ErrorLog -Message "Usage: adp snapshot create <runtime> <snapshot-name>" -Component "cli.snapshot"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName" -Component "cli.snapshot"
    exit 1
}

Write-InfoLog -Message "Creating snapshot: $RuntimeName/$SnapshotName" -Component "cli.snapshot"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-ErrorLog -Message "VM not found: $vmxPath" -Component "cli.snapshot"
    exit 1
}

Write-Host "Creating snapshot '$SnapshotName' for runtime '$RuntimeName'..." -ForegroundColor Yellow

$existingSnapshots = @(List-VMSnapshots -VmxPath $vmxPath)
if ($existingSnapshots -contains $SnapshotName) {
    Write-Host "  Snapshot '$SnapshotName' already exists." -ForegroundColor Green
    return
}

$result = Create-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName

if ($result.Success) {
    Write-Host "  Snapshot '$SnapshotName' created successfully." -ForegroundColor Green
} else {
    $snapshotsAfterFailure = @(List-VMSnapshots -VmxPath $vmxPath)
    if ($snapshotsAfterFailure -contains $SnapshotName) {
        Write-WarnLog -Message "Snapshot command reported failure, but snapshot '$SnapshotName' exists: $($result.StdErr)" -Component "cli.snapshot"
        Write-Host "  Snapshot '$SnapshotName' exists." -ForegroundColor Green
        return
    }

    Write-ErrorLog -Message "Snapshot creation failed: $($result.StdErr)" -Component "cli.snapshot"
    exit 1
}
