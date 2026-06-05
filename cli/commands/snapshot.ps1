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

# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
$vmStore = Resolve-Path "vm_store"
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null

$statusResult = Get-VMStatus -Name $RuntimeName
if (-not $statusResult.Success -or $statusResult.Data -eq "not-created") {
    Write-ErrorLog -Message (Get-UIText -English "VM not found for runtime: $RuntimeName" -Chinese "未找到 VM: $RuntimeName") -Component "cli.snapshot"
    exit 1
}

Write-UIHost -English "Creating snapshot '$SnapshotName' for runtime '$RuntimeName'..." -Chinese "正在为运行时 '$RuntimeName' 创建快照 '$SnapshotName'..." -ForegroundColor Yellow

$snapshotListResult = Get-SnapshotList -Name $RuntimeName
$existingSnapshots = if ($snapshotListResult.Success) { @($snapshotListResult.Data) } else { @() }
if ($existingSnapshots -contains $SnapshotName) {
    Write-UIHost -English "  Snapshot '$SnapshotName' already exists." -Chinese "  快照 '$SnapshotName' 已存在。" -ForegroundColor Green
    return
}

$result = New-Snapshot -Name $RuntimeName -SnapshotName $SnapshotName

if ($result.Success) {
    Write-UIHost -English "  Snapshot '$SnapshotName' created successfully." -Chinese "  快照 '$SnapshotName' 创建成功。" -ForegroundColor Green
} else {
    $snapshotsAfterResult = Get-SnapshotList -Name $RuntimeName
    $snapshotsAfterFailure = if ($snapshotsAfterResult.Success) { @($snapshotsAfterResult.Data) } else { @() }
    if ($snapshotsAfterFailure -contains $SnapshotName) {
        Write-WarnLog -Message "Snapshot command reported failure, but snapshot '$SnapshotName' exists: $($result.Error)" -Component "cli.snapshot"
        Write-UIHost -English "  Snapshot '$SnapshotName' exists." -Chinese "  快照 '$SnapshotName' 存在。" -ForegroundColor Green
        return
    }

    Write-ErrorLog -Message (Get-UIText -English "Snapshot creation failed: $($result.Error)" -Chinese "快照创建失败: $($result.Error)") -Component "cli.snapshot"
    exit 1
}
