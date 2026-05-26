# ADP-OS Destroy Command
# Destroy a runtime VM completely

param(
    [string]$RuntimeName,
    [switch]$Force
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message "Usage: adp destroy <runtime> [-Force]" -Component "cli.destroy"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName" -Component "cli.destroy"
    exit 1
}

Write-InfoLog -Message "Destroying runtime: $RuntimeName" -Component "cli.destroy"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmPath = Join-Path $vmStore $vmName
$vmxPath = Join-Path $vmPath "$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-Host "Runtime '$RuntimeName' does not exist." -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "DESTROY runtime: $RuntimeName" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host "  VMX: $vmxPath" -ForegroundColor DarkGray
Write-Host "  Directory: $vmPath" -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) {
    Write-Host "This will PERMANENTLY DELETE this runtime and ALL its data." -ForegroundColor Red
    Write-Host "Run 'adp destroy $RuntimeName -Force' to confirm." -ForegroundColor Yellow
    return
}

# Stop VM first if running
$result = Stop-VM -VmxPath $vmxPath -Mode "soft"
if (-not $result.Success) {
    Stop-VM -VmxPath $vmxPath -Mode "hard" | Out-Null
}

# Remove VM directory
Remove-Item -LiteralPath $vmPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Runtime '$RuntimeName' destroyed." -ForegroundColor Green
Write-InfoLog -Message "Runtime destroyed: $RuntimeName" -Component "cli.destroy"
