# ADP-OS Stop Command
# Stop a named runtime VM

param(
    [string]$RuntimeName
)

if (-not $RuntimeName) {
    Write-ErrorLog -Message "Usage: adp stop <runtime> (frontend|backend|agent)" -Component "cli.stop"
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName" -Component "cli.stop"
    exit 1
}

Write-InfoLog -Message "Stopping runtime: $RuntimeName" -Component "cli.stop"

Initialize-VMware | Out-Null

$vmStore = Resolve-Path "vm_store"
$vmName = "adp-$RuntimeName"
$vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

if (-not (Test-Path $vmxPath)) {
    Write-Host "VM not found: $vmxPath" -ForegroundColor Yellow
    Write-Host "  Runtime '$RuntimeName' does not exist." -ForegroundColor DarkGray
    return
}

Write-Host "Stopping runtime: $RuntimeName" -ForegroundColor Yellow

$status = Get-VMStatus $vmxPath
Write-Host "  Current status: $status" -ForegroundColor DarkGray

$result = Stop-VM -VmxPath $vmxPath -Mode "soft"

if ($result.Success) {
    Write-Host "  Runtime '$RuntimeName' stopped." -ForegroundColor Green
} else {
    Write-WarnLog -Message "Soft stop failed, trying hard stop..." -Component "cli.stop"
    $result = Stop-VM -VmxPath $vmxPath -Mode "hard"
    if ($result.Success) {
        Write-Host "  Runtime '$RuntimeName' force-stopped." -ForegroundColor Yellow
    } else {
        Write-ErrorLog -Message "Failed to stop VM: $($result.StdErr)" -Component "cli.stop"
        exit 1
    }
}
