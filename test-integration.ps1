# ADP-OS Integration Test Script
# Tests OS Profile framework integration with vm-factory.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS Integration Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load modules
Remove-Variable -Name '_ProjectRoot' -Scope Script -ErrorAction SilentlyContinue
. "$PSScriptRoot\core\config\config.ps1"
. "$PSScriptRoot\core\logging\logger.ps1"
. "$PSScriptRoot\runtimes\vmware\os-profiles.ps1"
. "$PSScriptRoot\runtimes\vmware\vm-factory.ps1"

$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Initialize-Logging -LogDirectory $logDir -Level "INFO"

# Test 1: OS Profile Framework
Write-Host "[Test 1] OS Profile Framework" -ForegroundColor Yellow
$profiles = Get-AvailableOSProfiles
Write-Host "  Available profiles: $($profiles.Count)" -ForegroundColor Green
foreach ($p in $profiles) {
    $profile = Get-OSProfile -OSName $p
    Write-Host "    $p -> guestOS=$($profile.guestOS), seedType=$($profile.seedType)" -ForegroundColor DarkGray
}

# Test 2: Topology Configuration
Write-Host ""
Write-Host "[Test 2] Topology Configuration" -ForegroundColor Yellow
Initialize-Config -ProjectRoot $PSScriptRoot
$topology = Get-TopologyConfig
foreach ($name in @('frontend', 'backend', 'agent')) {
    $rt = $topology.$name
    Write-Host "  ${name}:" -ForegroundColor Yellow
    Write-Host "    os: $($rt.os)" -ForegroundColor Green
    Write-Host "    cpu: $($rt.cpu), memory: $($rt.memory)MB, disk: $($rt.disk)GB" -ForegroundColor DarkGray
}

# Test 3: Seed Type Mapping
Write-Host ""
Write-Host "[Test 3] Seed Type Mapping" -ForegroundColor Yellow
$testCases = @(
    @{ Name = 'frontend'; ExpectedSeedType = 'cloud-init' },
    @{ Name = 'backend'; ExpectedSeedType = 'cloud-init' },
    @{ Name = 'agent'; ExpectedSeedType = 'cloud-init' }
)
foreach ($tc in $testCases) {
    $rt = Get-RuntimeConfig $tc.Name
    $profile = Get-OSProfile -OSName $rt.os
    if ($profile.seedType -eq $tc.ExpectedSeedType) {
        $status = 'OK'
        $color = 'Green'
    } else {
        $status = 'FAIL'
        $color = 'Red'
    }
    $msg = "  $($tc.Name): expected=$($tc.ExpectedSeedType), actual=$($profile.seedType) [$status]"
    Write-Host $msg -ForegroundColor $color
}

# Test 4: VM Factory Initialization
Write-Host ""
Write-Host "[Test 4] VM Factory Initialization" -ForegroundColor Yellow
Initialize-VmFactory -ProjectRoot $PSScriptRoot -IsoCachePath (Resolve-Path "iso_cache") -VmStorePath (Resolve-Path "vm_store")
Write-Host "  VM Factory initialized [OK]" -ForegroundColor Green

# Test 5: Platform Config ISO Path
Write-Host ""
Write-Host "[Test 5] Platform Config ISO Path" -ForegroundColor Yellow
$config = Get-PlatformConfig
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
Write-Host "  ISO name: $isoName" -ForegroundColor Green

# Test 6: Provisioning Plan
Write-Host ""
Write-Host "[Test 6] Provisioning Plan" -ForegroundColor Yellow
foreach ($name in @('frontend', 'backend', 'agent')) {
    $checks = Test-RuntimeProvisioningPlan -RuntimeName $name
    $failed = @($checks | Where-Object { -not $_.Passed })
    if ($failed.Count -eq 0) {
        Write-Host "  ${name}: OK ($($checks.Count) checks)" -ForegroundColor Green
    } else {
        Write-Host "  ${name}: FAIL" -ForegroundColor Red
        foreach ($check in $failed) {
            Write-Host "    $($check.Name): $($check.Detail)" -ForegroundColor Red
        }
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  All tests completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
