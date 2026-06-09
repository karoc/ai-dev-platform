# ADP-OS Destroy Command
# Destroy a runtime VM completely

[CmdletBinding()]
param(
    [string]$RuntimeName,
    [switch]$Force,
    [switch]$Plan
)

$validRuntimes = (Get-AllRuntimeNames) -join ', '

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos destroy <runtime> [-Plan] [-Force]" -Chinese "用法: adpos destroy <runtime> [-Plan] [-Force]") -Component "cli.destroy"
    Write-UIHost -English "Runtime can be: $validRuntimes" -Chinese "运行时可以是: $validRuntimes" -ForegroundColor DarkGray
    Write-UIHost -English "Run 'adpos destroy --help' for usage." -Chinese "运行 'adpos destroy --help' 查看用法。" -ForegroundColor DarkGray
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ADPUnknownRuntimeError -RuntimeName $RuntimeName -CommandText "destroy" -Component "cli.destroy"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Destroying runtime: $RuntimeName" -Chinese "正在销毁运行时: $RuntimeName") -Component "cli.destroy"

# Initialize VM provider
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
$vmStore = Resolve-Path "vm_store"
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null

$statusResult = Get-VMStatus -Name $RuntimeName
if (-not $statusResult.Success -or $statusResult.Data -eq "not-created") {
    Write-UIHost -English "Runtime '$RuntimeName' does not exist." -Chinese "运行时 '$RuntimeName' 不存在。" -ForegroundColor Yellow
    return
}

Write-Host ""
Write-UIHost -English "DESTROY runtime: $RuntimeName" -Chinese "销毁运行时: $RuntimeName" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""

if ($Plan) {
    Write-UIHost -English "Plan only: no files will be deleted." -Chinese "仅预览：不会删除任何文件。" -ForegroundColor Cyan
    Write-UIHost -English "  Would stop VM if running" -Chinese "  如果 VM 正在运行将停止" -ForegroundColor DarkGray
    Write-UIHost -English "  Would remove VM and all its files" -Chinese "  将删除 VM 及其所有文件" -ForegroundColor DarkGray
    Write-UIHost -English "  Workspace data under workspace_root is not removed by destroy." -Chinese "  workspace_root 下的工作区数据不会被销毁。" -ForegroundColor DarkGray
    return
}

if (-not $Force) {
    Write-UIHost -English "This will PERMANENTLY DELETE this runtime and ALL its data." -Chinese "这将永久删除该运行时及其所有数据。" -ForegroundColor Red
    Write-UIHost -English "Run 'adpos destroy $RuntimeName -Force' to confirm, or 'adpos destroy $RuntimeName -Plan' to preview." -Chinese "运行 'adpos destroy $RuntimeName -Force' 确认，或 'adpos destroy $RuntimeName -Plan' 预览。" -ForegroundColor Yellow
    return
}

# Stop and remove VM via Provider
$result = Remove-VM -Name $RuntimeName -DeleteFiles $true

if ($result.Success) {
    Write-UIHost -English "Runtime '$RuntimeName' destroyed." -Chinese "运行时 '$RuntimeName' 已销毁。" -ForegroundColor Green
    Write-InfoLog -Message (Get-UIText -English "Runtime destroyed: $RuntimeName" -Chinese "运行时已销毁: $RuntimeName") -Component "cli.destroy"
} else {
    Write-ErrorLog -Message (Get-UIText -English "Failed to destroy runtime: $($result.Error)" -Chinese "销毁运行时失败: $($result.Error)") -Component "cli.destroy"
    exit 1
}
