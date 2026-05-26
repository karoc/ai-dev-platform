# ADP-OS Doctor Command
# System diagnostics — checks all dependencies and platform health

Write-InfoLog -Message "Running: adp doctor" -Component "cli.doctor"

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

Write-Host ""
Write-Host "ADP-OS Doctor — System Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$script:issues = @()
$script:ok = @()

function Test-Check {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ""
    )

    if ($Condition) {
        Write-Host "  [OK]    $Name $Detail" -ForegroundColor Green
        $script:ok += $Name
    } else {
        Write-Host "  [FAIL]  $Name $Detail" -ForegroundColor Red
        $script:issues += $Name
    }
}

# --- Platform ---
Write-Host "Platform:" -ForegroundColor Yellow
$platform = Get-Platform
Test-Check -Name "Platform Detection" -Condition ($platform -eq "windows") -Detail "($platform)"

$osInfo = Get-CimInstance Win32_OperatingSystem
Test-Check -Name "Windows Version" -Condition ([Version]$osInfo.Version -ge [Version]"10.0") -Detail "($($osInfo.Caption))"

Test-Check -Name "PowerShell 7+" -Condition ($PSVersionTable.PSVersion.Major -ge 7) -Detail "(v$($PSVersionTable.PSVersion))"

# --- VMware ---
Write-Host ""
Write-Host "VMware:" -ForegroundColor Yellow
$vmwareOk = Test-VMwareAvailable
Test-Check -Name "vmrun.exe" -Condition $vmwareOk

if ($vmwareOk) {
    Initialize-VMware | Out-Null
    $vmrunPath = Get-VmrunPath
    Test-Check -Name "vmrun path" -Condition (Test-Path $vmrunPath) -Detail "($vmrunPath)"

    $diskManager = Find-VmwareDiskManager
    Test-Check -Name "vmware-vdiskmanager.exe" -Condition ($null -ne $diskManager) -Detail "($diskManager)"

    $isoCreator = Find-ISOCreator
    $isoCreatorDetail = if ($isoCreator) { "$($isoCreator.Type): $($isoCreator.Path)" } else { "missing" }
    Test-Check -Name "seed ISO creator" -Condition ($null -ne $isoCreator) -Detail "($isoCreatorDetail)"

    $isoRemasterTool = Find-ISORemasterTool
    $isoRemasterDetail = if ($isoRemasterTool) { "$($isoRemasterTool.Type): $($isoRemasterTool.Path)" } else { "missing" }
    Test-Check -Name "install ISO remaster" -Condition ($null -ne $isoRemasterTool) -Detail "($isoRemasterDetail)"

    try {
        $vms = Get-RegisteredVMs
        Test-Check -Name "VMware VMs" -Condition $true -Detail "($($vms.Count) registered)"
    } catch {
        Test-Check -Name "VMware accessible" -Condition $false -Detail "($_)"
    }
}

# --- Mutagen ---
Write-Host ""
Write-Host "Mutagen:" -ForegroundColor Yellow
$mutagenPath = Find-Mutagen -ProjectRoot (Get-ProjectRoot)
$hasMutagen = $null -ne $mutagenPath
Test-Check -Name "mutagen" -Condition $hasMutagen
if (-not $hasMutagen) {
    Write-Host "  [INFO]  Install by placing mutagen.exe at .tools\mutagen\mutagen.exe or adding it to PATH." -ForegroundColor DarkGray
}

if ($hasMutagen) {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    $mutagenVersion = Invoke-Mutagen -Arguments @("version") 2>$null | Select-Object -First 1
    Test-Check -Name "mutagen version" -Condition $true -Detail "($mutagenVersion, $mutagenPath)"
}

# --- SSH ---
Write-Host ""
Write-Host "SSH:" -ForegroundColor Yellow
$hasSsh = $null -ne (Get-Command ssh -ErrorAction SilentlyContinue)
Test-Check -Name "OpenSSH Client" -Condition $hasSsh

# --- ISO ---
Write-Host ""
Write-Host "OS ISO:" -ForegroundColor Yellow
$config = Get-PlatformConfig
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$isoCache = Resolve-Path "iso_cache"
$isoPath = Join-Path $isoCache $isoName

if (Test-Path $isoPath) {
    $isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
    Test-Check -Name "ISO present" -Condition $true -Detail "($isoSize GB)"
} else {
    Test-Check -Name "ISO present" -Condition $false -Detail "(not found at $isoPath)"
}

# --- Directories ---
Write-Host ""
Write-Host "Directories:" -ForegroundColor Yellow
$workspaceRoot = Resolve-Path "workspace_root"
$vmStore = Resolve-Path "vm_store"
Test-Check -Name "Workspace root" -Condition (Test-Path $workspaceRoot) -Detail "($workspaceRoot)"
Test-Check -Name "VM store" -Condition (Test-Path $vmStore) -Detail "($vmStore)"
Test-Check -Name "Logs" -Condition (Test-Path (Join-Path (Get-ProjectRoot) "logs"))

# --- Runtime topology ---
Write-Host ""
Write-Host "Runtimes:" -ForegroundColor Yellow
$topology = Get-TopologyConfig
foreach ($name in (Get-AllRuntimeNames)) {
    $rt = $topology.$name
    $profile = Get-OSProfile -OSName $rt.os
    $vmName = "adp-$name"
    $vmPath = Join-Path $vmStore $vmName
    $vmxPath = Join-Path $vmPath "$vmName.vmx"
    $vmdkPath = Join-Path $vmPath "$vmName.vmdk"

    Test-Check -Name "$name topology" -Condition ($profile.seedType -eq "cloud-init" -and $rt.ssh_port -eq 22) -Detail "($($rt.os), ssh:$($rt.ssh_port))"
    if (Test-Path $vmPath) {
        Test-Check -Name "$name VMX" -Condition (Test-Path $vmxPath) -Detail "($vmxPath)"
        Test-Check -Name "$name VMDK" -Condition (Test-Path $vmdkPath) -Detail "($vmdkPath)"
    } else {
        Write-Host "  [INFO]  $name VM not created yet ($vmPath)" -ForegroundColor DarkGray
    }
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Results: $($ok.Count) OK, $($issues.Count) issues" -ForegroundColor $(if ($issues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "Issues found:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
} else {
    Write-Host "All checks passed. Platform is healthy." -ForegroundColor Green
}
