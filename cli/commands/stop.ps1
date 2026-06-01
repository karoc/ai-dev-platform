# ADP-OS Stop Command
# Stop a named runtime VM

param(
    [string]$RuntimeName
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp stop <runtime> (frontend|backend|agent)" -Chinese "用法: adp stop <runtime> (frontend|backend|agent)") -Component "cli.stop"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName" -Chinese "未知运行时: $RuntimeName") -Component "cli.stop"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Stopping runtime: $RuntimeName" -Chinese "正在停止运行时: $RuntimeName") -Component "cli.stop"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-UIHost -English "VM not found: $vmxPath" -Chinese "未找到 VM: $vmxPath" -ForegroundColor Yellow
    Write-UIHost -English "  Runtime '$RuntimeName' does not exist." -Chinese "  运行时 '$RuntimeName' 不存在。" -ForegroundColor DarkGray
    return
}

Write-UIHost -English "Stopping runtime: $RuntimeName" -Chinese "正在停止运行时: $RuntimeName" -ForegroundColor Yellow

$status = Get-VMStatus $vmxPath
Write-UIHost -English "  Current status: $status" -Chinese "  当前状态: $status" -ForegroundColor DarkGray

$result = Stop-VM -VmxPath $vmxPath -Mode "soft"

if ($result.Success) {
    Write-UIHost -English "  Runtime '$RuntimeName' stopped." -Chinese "  运行时 '$RuntimeName' 已停止。" -ForegroundColor Green
} else {
    Write-WarnLog -Message (Get-UIText -English "Soft stop failed, trying hard stop..." -Chinese "软停止失败，正在尝试强制停止...") -Component "cli.stop"
    $result = Stop-VM -VmxPath $vmxPath -Mode "hard"
    if ($result.Success) {
        Write-UIHost -English "  Runtime '$RuntimeName' force-stopped." -Chinese "  运行时 '$RuntimeName' 已强制停止。" -ForegroundColor Yellow
    } else {
        Write-ErrorLog -Message (Get-UIText -English "Failed to stop VM: $($result.StdErr)" -Chinese "停止 VM 失败: $($result.StdErr)") -Component "cli.stop"
        exit 1
    }
}
