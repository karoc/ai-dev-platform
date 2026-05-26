# ADP-OS Deployment Pre-check Script
# Validates all prerequisites before VM creation

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS Deployment Pre-check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load modules
Remove-Variable -Name '_ProjectRoot' -Scope Script -ErrorAction SilentlyContinue
. "$PSScriptRoot\core\config\config.ps1"
. "$PSScriptRoot\core\logging\logger.ps1"
. "$PSScriptRoot\adapters\windows\vmware\vmware.ps1"
. "$PSScriptRoot\runtimes\vmware\os-profiles.ps1"
. "$PSScriptRoot\runtimes\vmware\vm-factory.ps1"

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Initialize-Logging -LogDirectory $logDir -Level "INFO"

Initialize-Config -ProjectRoot $PSScriptRoot

# Step 1: Check VMware
Write-Host "[Step 1] Checking VMware..." -ForegroundColor Yellow
$vmwareOk = Test-VMwareAvailable
if ($vmwareOk) {
    Initialize-VMware | Out-Null
    $vmrunPath = Get-VmrunPath
    Write-Host "  vmrun: $vmrunPath [OK]" -ForegroundColor Green
} else {
    Write-Host "  VMware not found. Install VMware Workstation Pro." -ForegroundColor Red
    exit 1
}

# Step 2: Check ISO
Write-Host ""
Write-Host "[Step 2] Checking ISO..." -ForegroundColor Yellow
$config = Get-PlatformConfig
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$isoCache = Resolve-Path "iso_cache"
$isoPath = Join-Path $isoCache $isoName

if (Test-Path $isoPath) {
    $sizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
    Write-Host "  ISO found: $isoPath ($sizeGB GB) [OK]" -ForegroundColor Green
} else {
    Write-Host "  ISO not found: $isoPath" -ForegroundColor Red
    Write-Host "  Download Ubuntu Server 26.04 LTS or AlmaLinux 9:" -ForegroundColor Yellow
    Write-Host "    https://releases.ubuntu.com/26.04/" -ForegroundColor DarkGray
    Write-Host "    https://almalinux.org/get-almalinux/" -ForegroundColor DarkGray
    exit 1
}

# Step 3: Initialize VM Factory
Write-Host ""
Write-Host "[Step 3] Initializing VM Factory..." -ForegroundColor Yellow
$vmStore = Resolve-Path "vm_store"
Initialize-VmFactory -ProjectRoot $PSScriptRoot -IsoCachePath $isoCache -VmStorePath $vmStore
Write-Host "  VM Factory initialized [OK]" -ForegroundColor Green

# Step 4: Runtime Configuration
Write-Host ""
Write-Host "[Step 4] Runtime Configuration:" -ForegroundColor Yellow
$topology = Get-TopologyConfig
foreach ($name in @('frontend', 'backend', 'agent')) {
    $rt = $topology.$name
    $profile = Get-OSProfile -OSName $rt.os
    Write-Host "  ${name}:" -ForegroundColor Cyan
    Write-Host "    OS: $($rt.os) ($($profile.seedType))" -ForegroundColor Green
    Write-Host "    CPU: $($rt.cpu), RAM: $($rt.memory)MB, Disk: $($rt.disk)GB" -ForegroundColor DarkGray
    Write-Host "    SSH: VM IP port $($rt.ssh_port)" -ForegroundColor DarkGray

    $planChecks = Test-RuntimeProvisioningPlan -RuntimeName $name
    $failedChecks = @($planChecks | Where-Object { -not $_.Passed })
    if ($failedChecks.Count -gt 0) {
        foreach ($check in $failedChecks) {
            Write-Host "    [FAIL] $($check.Name): $($check.Detail)" -ForegroundColor Red
        }
        exit 1
    }
}

# Step 5: Check SSH Keys
Write-Host ""
Write-Host "[Step 5] Checking SSH Keys..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot "adapters\windows\ssh\ssh.ps1")
try {
    $keyPath = Initialize-SSH
    $pubKey = Get-SSHPubKey
    Write-Host "  SSH key: $keyPath [OK]" -ForegroundColor Green
} catch {
    Write-Host "  SSH initialization failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  All checks passed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Ready to deploy. Run:" -ForegroundColor Cyan
Write-Host "  pwsh cli/adp.ps1 up frontend" -ForegroundColor DarkGray
Write-Host ""
