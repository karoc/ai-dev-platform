# ADP-OS Snapshot Command
# Create named VM snapshots for a runtime

param(
    [string]$SubCommand,
    [string]$RuntimeName,
    [string]$SnapshotName
)

if (-not $SubCommand -or $SubCommand -ne "create") {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp snapshot create <runtime> <snapshot-name>" -Chinese "用法: adp snapshot create <runtime> <snapshot-name>") -Component "cli.snapshot"
    exit 1
}

if (-not $RuntimeName -or -not $SnapshotName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp snapshot create <runtime> <snapshot-name>" -Chinese "用法: adp snapshot create <runtime> <snapshot-name>") -Component "cli.snapshot"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName" -Chinese "未知运行时: $RuntimeName") -Component "cli.snapshot"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Creating snapshot: $RuntimeName/$SnapshotName" -Chinese "正在创建快照: $RuntimeName/$SnapshotName") -Component "cli.snapshot"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-ErrorLog -Message (Get-UIText -English "VM not found: $vmxPath" -Chinese "未找到 VM: $vmxPath") -Component "cli.snapshot"
    exit 1
}

Write-UIHost -English "Creating snapshot '$SnapshotName' for runtime '$RuntimeName'..." -Chinese "正在为运行时 '$RuntimeName' 创建快照 '$SnapshotName'..." -ForegroundColor Yellow

$existingSnapshots = @(List-VMSnapshots -VmxPath $vmxPath)
if ($existingSnapshots -contains $SnapshotName) {
    Write-UIHost -English "  Snapshot '$SnapshotName' already exists." -Chinese "  快照 '$SnapshotName' 已存在。" -ForegroundColor Green
    return
}

$result = Create-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName

if ($result.Success) {
    Write-UIHost -English "  Snapshot '$SnapshotName' created successfully." -Chinese "  快照 '$SnapshotName' 创建成功。" -ForegroundColor Green
} else {
    $snapshotsAfterFailure = @(List-VMSnapshots -VmxPath $vmxPath)
    if ($snapshotsAfterFailure -contains $SnapshotName) {
        Write-WarnLog -Message "Snapshot command reported failure, but snapshot '$SnapshotName' exists: $($result.StdErr)" -Component "cli.snapshot"
        Write-UIHost -English "  Snapshot '$SnapshotName' exists." -Chinese "  快照 '$SnapshotName' 存在。" -ForegroundColor Green
        return
    }

    Write-ErrorLog -Message (Get-UIText -English "Snapshot creation failed: $($result.StdErr)" -Chinese "快照创建失败: $($result.StdErr)") -Component "cli.snapshot"
    exit 1
}
