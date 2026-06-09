# ADP-OS Stop Command
# Stop a named runtime VM

[CmdletBinding()]
param(
    [string]$RuntimeName
)

$validRuntimes = (Get-AllRuntimeNames) -join ', '

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos stop <runtime> ($validRuntimes)" -Chinese "用法: adpos stop <runtime> ($validRuntimes)") -Component "cli.stop"
    Write-UIHost -English "Run 'adpos stop --help' for usage." -Chinese "运行 'adpos stop --help' 查看用法。" -ForegroundColor DarkGray
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ADPUnknownRuntimeError -RuntimeName $RuntimeName -CommandText "stop" -Component "cli.stop"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Stopping runtime: $RuntimeName" -Chinese "正在停止运行时: $RuntimeName") -Component "cli.stop"

# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
$vmStore = Resolve-Path "vm_store"
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null

$statusResult = Get-VMStatus -Name $RuntimeName
if (-not $statusResult.Success -or $statusResult.Data -eq "not-created") {
    Write-UIHost -English "VM not found for runtime: $RuntimeName" -Chinese "未找到 VM: $RuntimeName" -ForegroundColor Yellow
    Write-UIHost -English "  Runtime '$RuntimeName' does not exist." -Chinese "  运行时 '$RuntimeName' 不存在。" -ForegroundColor DarkGray
    return
}

Write-UIHost -English "Stopping runtime: $RuntimeName" -Chinese "正在停止运行时: $RuntimeName" -ForegroundColor Yellow

$status = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }
Write-UIHost -English "  Current status: $status" -Chinese "  当前状态: $status" -ForegroundColor DarkGray

$result = Stop-VM -Name $RuntimeName -Mode "soft"

if ($result.Success) {
    Write-UIHost -English "  Runtime '$RuntimeName' stopped." -Chinese "  运行时 '$RuntimeName' 已停止。" -ForegroundColor Green
} else {
    Write-WarnLog -Message (Get-UIText -English "Soft stop failed, trying hard stop..." -Chinese "软停止失败，正在尝试强制停止...") -Component "cli.stop"
    $result = Stop-VM -Name $RuntimeName -Mode "hard"
    if ($result.Success) {
        Write-UIHost -English "  Runtime '$RuntimeName' force-stopped." -Chinese "  运行时 '$RuntimeName' 已强制停止。" -ForegroundColor Yellow
    } else {
        Write-ErrorLog -Message (Get-UIText -English "Failed to stop VM: $($result.Error)" -Chinese "停止 VM 失败: $($result.Error)") -Component "cli.stop"
        exit 1
    }
}
