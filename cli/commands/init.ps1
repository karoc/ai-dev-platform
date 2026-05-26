# ADP-OS Init Command (Phase 2)
# Full platform initialization: dependencies, VM factory, SSH, bootstrap readiness
# Optionally provisions the first VM from ISO

param(
    [string]$RuntimeName,
    [string]$IsoPath,
    [switch]$SkipProvision
)

Write-InfoLog -Message "adp init (Phase 2)" -Component "cli.init"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ADP-OS Init — Phase 2" -ForegroundColor Cyan
Write-Host "  Platform Initialization + VM Factory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$config = Get-PlatformConfig
$topology = Get-TopologyConfig

# =============================================
# Step 1: Verify VMware
# =============================================
Write-Host "[1/6] VMware Workstation" -ForegroundColor Yellow
if (-not (Test-VMwareAvailable)) {
    Write-ErrorLog -Message "VMware Workstation not found." -Component "cli.init"
    Write-Host "  Install VMware Workstation Pro and re-run." -ForegroundColor Red
    exit 1
}
Initialize-VMware
Write-Host "  vmrun: $(Get-VmrunPath) [OK]" -ForegroundColor Green

# =============================================
# Step 2: ISO Setup
# =============================================
Write-Host "[2/6] OS ISO" -ForegroundColor Yellow
$isoCache = Resolve-Path "iso_cache"
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }

if ($IsoPath) {
    if (-not (Test-Path $IsoPath)) {
        Write-ErrorLog -Message "ISO not found: $IsoPath" -Component "cli.init"
        exit 1
    }
    if (-not (Test-Path $isoCache)) {
        New-Item -ItemType Directory -Path $isoCache -Force | Out-Null
    }
    $destPath = Join-Path $isoCache $isoName
    if ((Get-Item $IsoPath).FullName -ne (Get-Item $destPath -ErrorAction SilentlyContinue).FullName) {
        Copy-Item $IsoPath $destPath -Force
    }
    Write-Host "  ISO cached: $destPath [OK]" -ForegroundColor Green
} else {
    $isoPath = Join-Path $isoCache $isoName
    if (Test-Path $isoPath) {
        $sizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
        Write-Host "  ISO found: $isoPath ($sizeGB GB) [OK]" -ForegroundColor Green
    } else {
        Write-Host "  ISO not found at: $isoPath" -ForegroundColor Red
        Write-Host "  Run: adp init -IsoPath <path-to-linux-iso>" -ForegroundColor Yellow
        Write-Host "  Or place ISO at: $isoPath" -ForegroundColor Yellow
    }
}

# =============================================
# Step 3: SSH Keys
# =============================================
Write-Host "[3/6] SSH Keys" -ForegroundColor Yellow
. (Join-Path (Get-ProjectRoot) "adapters\windows\ssh\ssh.ps1")
$keyPath = Initialize-SSH
$pubKey = Get-SSHPubKey
Write-Host "  Key: $keyPath [OK]" -ForegroundColor Green
Write-Host "  Public: $($pubKey.Substring(0, [Math]::Min(60, $pubKey.Length)))..." -ForegroundColor DarkGray

# =============================================
# Step 4: Directories
# =============================================
Write-Host "[4/6] Platform Directories" -ForegroundColor Yellow
$workspaceRoot = Resolve-Path "workspace_root"
$vmStore = Resolve-Path "vm_store"
Initialize-Filesystem -BasePath $workspaceRoot
Initialize-Filesystem -BasePath $vmStore

foreach ($name in (Get-AllRuntimeNames)) {
    $wsPath = Join-Path $workspaceRoot $name
    if (-not (Test-Path $wsPath)) {
        New-Item -ItemType Directory -Path $wsPath -Force | Out-Null
    }
}
Write-Host "  Workspaces: $workspaceRoot [OK]" -ForegroundColor Green
Write-Host "  VM Store:   $vmStore [OK]" -ForegroundColor Green

# =============================================
# Step 5: VM Factory Init + Optional Provision
# =============================================
Write-Host "[5/6] VM Factory" -ForegroundColor Yellow
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
Initialize-VmFactory -ProjectRoot (Get-ProjectRoot) -IsoCachePath $isoCache -VmStorePath $vmStore
Write-Host "  VM Factory initialized [OK]" -ForegroundColor Green

# =============================================
# Step 6: Topology Summary
# =============================================
Write-Host "[6/6] Runtime Topology" -ForegroundColor Yellow
foreach ($name in (Get-AllRuntimeNames)) {
    $rt = Get-RuntimeConfig $name
    $vmName = "adp-$name"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"
    $exists = Test-Path $vmxPath

    $statusStr = if ($exists) { "EXISTS" } else { "pending" }
    $color = if ($exists) { "Green" } else { "DarkGray" }

    Write-Host "  $name" -ForegroundColor $color -NoNewline
    Write-Host " : CPU=$($rt.cpu) RAM=$($rt.memory)MB Disk=$($rt.disk)GB [$statusStr]" -ForegroundColor DarkGray
}

# =============================================
# Provision first VM if requested
# =============================================
if ($RuntimeName) {
    Write-Host ""
    Write-Host "Provisioning initial runtime: $RuntimeName" -ForegroundColor Cyan

    $isoCheck = Join-Path $isoCache $isoName
    if (-not (Test-Path $isoCheck) -and -not $IsoPath) {
        Write-Host "  Cannot provision: ISO not cached and no -IsoPath given." -ForegroundColor Red
    } else {
        & (Join-Path (Get-ProjectRoot) "cli\commands\up.ps1") `
            -RuntimeName $RuntimeName -IsoPath $IsoPath -NoBootstrap:$SkipProvision
    }
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ADP-OS Phase 2 Init Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next: adp up <runtime>     Start/auto-create a runtime" -ForegroundColor Cyan
Write-Host "      adp doctor            Check platform health" -ForegroundColor Cyan
Write-Host ""
