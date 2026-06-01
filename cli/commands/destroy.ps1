# ADP-OS Destroy Command
# Destroy a runtime VM completely

param(
    [string]$RuntimeName,
    [switch]$Force,
    [switch]$Plan
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp destroy <runtime> [-Plan] [-Force]" -Chinese "用法: adp destroy <runtime> [-Plan] [-Force]") -Component "cli.destroy"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName" -Chinese "未知运行时: $RuntimeName") -Component "cli.destroy"
    exit 1
}

Write-InfoLog -Message (Get-UIText -English "Destroying runtime: $RuntimeName" -Chinese "正在销毁运行时: $RuntimeName") -Component "cli.destroy"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmPath = Join-Path $vmStore $vmName
$vmxPath = Join-Path $vmPath "$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-UIHost -English "Runtime '$RuntimeName' does not exist." -Chinese "运行时 '$RuntimeName' 不存在。" -ForegroundColor Yellow
    return
}

Write-Host ""
Write-UIHost -English "DESTROY runtime: $RuntimeName" -Chinese "销毁运行时: $RuntimeName" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host "  VMX: $vmxPath" -ForegroundColor DarkGray
Write-Host "  Directory: $vmPath" -ForegroundColor DarkGray
Write-Host ""

if ($Plan) {
    Write-UIHost -English "Plan only: no files will be deleted." -Chinese "仅预览：不会删除任何文件。" -ForegroundColor Cyan
    Write-UIHost -English "  Would stop VM if running: $vmxPath" -Chinese "  如果 VM 正在运行将停止: $vmxPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Would remove directory:   $vmPath" -Chinese "  将删除目录:               $vmPath" -ForegroundColor DarkGray
    Write-UIHost -English "  Workspace data under workspace_root is not removed by destroy." -Chinese "  workspace_root 下的工作区数据不会被销毁。" -ForegroundColor DarkGray
    return
}

if (-not $Force) {
    Write-UIHost -English "This will PERMANENTLY DELETE this runtime and ALL its data." -Chinese "这将永久删除该运行时及其所有数据。" -ForegroundColor Red
    Write-UIHost -English "Run 'adp destroy $RuntimeName -Force' to confirm, or 'adp destroy $RuntimeName -Plan' to preview." -Chinese "运行 'adp destroy $RuntimeName -Force' 确认，或 'adp destroy $RuntimeName -Plan' 预览。" -ForegroundColor Yellow
    return
}

# Stop VM first if running
$result = Stop-VM -VmxPath $vmxPath -Mode "soft"
if (-not $result.Success) {
    Stop-VM -VmxPath $vmxPath -Mode "hard" | Out-Null
}

# Remove VM directory
Remove-Item -LiteralPath $vmPath -Recurse -Force -ErrorAction SilentlyContinue
Write-UIHost -English "Runtime '$RuntimeName' destroyed." -Chinese "运行时 '$RuntimeName' 已销毁。" -ForegroundColor Green
Write-InfoLog -Message (Get-UIText -English "Runtime destroyed: $RuntimeName" -Chinese "运行时已销毁: $RuntimeName") -Component "cli.destroy"
