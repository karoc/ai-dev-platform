# ADP-OS Init Command (Phase 2)
# Full platform initialization: dependencies, VM factory, SSH, bootstrap readiness
# Optionally provisions the first VM from ISO

param(
    [string]$RuntimeName,
    [string]$IsoPath,
    [switch]$SkipProvision
)

Write-InfoLog -Message (Get-UIText -English "adp init (Phase 2)" -Chinese "adp init（阶段 2）") -Component "cli.init"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS Init — Phase 2" -Chinese "  ADP-OS 初始化 — 阶段 2" -ForegroundColor Cyan
Write-UIHost -English "  Platform Initialization + VM Factory" -Chinese "  平台初始化 + VM Factory" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$config = Get-PlatformConfig
$topology = Get-TopologyConfig

# =============================================
# Step 1: Verify VMware
# =============================================
Write-UIHost -English "[1/6] VMware Workstation" -Chinese "[1/6] VMware Workstation" -ForegroundColor Yellow
if (-not (Test-VMwareAvailable)) {
    Write-ErrorLog -Message (Get-UIText -English "VMware Workstation not found." -Chinese "未找到 VMware Workstation。") -Component "cli.init"
    Write-UIHost -English "  Install VMware Workstation Pro and re-run." -Chinese "  安装 VMware Workstation Pro 后重新运行。" -ForegroundColor Red
    exit 1
}
Initialize-VMware
Write-Host "  vmrun: $(Get-VmrunPath) [OK]" -ForegroundColor Green

# =============================================
# Step 2: ISO Setup
# =============================================
Write-UIHost -English "[2/6] OS ISO" -Chinese "[2/6] OS ISO" -ForegroundColor Yellow
$isoCache = Resolve-Path "iso_cache"
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }

if ($IsoPath) {
    if (-not (Test-Path $IsoPath)) {
        Write-ErrorLog -Message (Get-UIText -English "ISO not found: $IsoPath" -Chinese "未找到 ISO: $IsoPath") -Component "cli.init"
        exit 1
    }
    if (-not (Test-Path $isoCache)) {
        New-Item -ItemType Directory -Path $isoCache -Force | Out-Null
    }
    $destPath = Join-Path $isoCache $isoName
    if ((Get-Item $IsoPath).FullName -ne (Get-Item $destPath -ErrorAction SilentlyContinue).FullName) {
        Copy-Item $IsoPath $destPath -Force
    }
    Write-UIHost -English "  ISO cached: $destPath [OK]" -Chinese "  ISO 已缓存: $destPath [OK]" -ForegroundColor Green
} else {
    $isoPath = Join-Path $isoCache $isoName
    if (Test-Path $isoPath) {
        $sizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
        Write-UIHost -English "  ISO found: $isoPath ($sizeGB GB) [OK]" -Chinese "  找到 ISO: $isoPath ($sizeGB GB) [OK]" -ForegroundColor Green
    } else {
        Write-UIHost -English "  ISO not found at: $isoPath" -Chinese "  未在此处找到 ISO: $isoPath" -ForegroundColor Red
        Write-UIHost -English "  Run: adp init -IsoPath <path-to-linux-iso>" -Chinese "  运行: adp init -IsoPath <path-to-linux-iso>" -ForegroundColor Yellow
        Write-UIHost -English "  Or place ISO at: $isoPath" -Chinese "  或将 ISO 放到: $isoPath" -ForegroundColor Yellow
    }
}

# =============================================
# Step 3: SSH Keys
# =============================================
Write-UIHost -English "[3/6] SSH Keys" -Chinese "[3/6] SSH 密钥" -ForegroundColor Yellow
. (Join-Path (Get-ProjectRoot) "adapters\windows\ssh\ssh.ps1")
$keyPath = Initialize-SSH
$pubKey = Get-SSHPubKey
Write-UIHost -English "  Key: $keyPath [OK]" -Chinese "  密钥: $keyPath [OK]" -ForegroundColor Green
Write-UIHost -English "  Public: $($pubKey.Substring(0, [Math]::Min(60, $pubKey.Length)))..." -Chinese "  公钥: $($pubKey.Substring(0, [Math]::Min(60, $pubKey.Length)))..." -ForegroundColor DarkGray

# =============================================
# Step 4: Directories
# =============================================
Write-UIHost -English "[4/6] Platform Directories" -Chinese "[4/6] 平台目录" -ForegroundColor Yellow
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
Write-UIHost -English "  Workspaces: $workspaceRoot [OK]" -Chinese "  工作区: $workspaceRoot [OK]" -ForegroundColor Green
Write-UIHost -English "  VM Store:   $vmStore [OK]" -Chinese "  VM 存储:   $vmStore [OK]" -ForegroundColor Green

# =============================================
# Step 5: VM Factory Init + Optional Provision
# =============================================
Write-UIHost -English "[5/6] VM Factory" -Chinese "[5/6] VM Factory" -ForegroundColor Yellow
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
Initialize-VmFactory -ProjectRoot (Get-ProjectRoot) -IsoCachePath $isoCache -VmStorePath $vmStore
Write-UIHost -English "  VM Factory initialized [OK]" -Chinese "  VM Factory 已初始化 [OK]" -ForegroundColor Green

# =============================================
# Step 6: Topology Summary
# =============================================
Write-UIHost -English "[6/6] Runtime Topology" -Chinese "[6/6] 运行时拓扑" -ForegroundColor Yellow
foreach ($name in (Get-AllRuntimeNames)) {
    $rt = Get-RuntimeConfig $name
    $vmName = "adp-$name"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"
    $exists = Test-Path $vmxPath

    $statusStr = if ($exists) { Get-UIText -English "EXISTS" -Chinese "已存在" } else { Get-UIText -English "pending" -Chinese "待创建" }
    $color = if ($exists) { "Green" } else { "DarkGray" }

    Write-Host "  $name" -ForegroundColor $color -NoNewline
    Write-Host " : CPU=$($rt.cpu) RAM=$($rt.memory)MB Disk=$($rt.disk)GB [$statusStr]" -ForegroundColor DarkGray
}

# =============================================
# Provision first VM if requested
# =============================================
if ($RuntimeName) {
    Write-Host ""
    Write-UIHost -English "Provisioning initial runtime: $RuntimeName" -Chinese "正在准备初始运行时: $RuntimeName" -ForegroundColor Cyan

    $isoCheck = Join-Path $isoCache $isoName
    if (-not (Test-Path $isoCheck) -and -not $IsoPath) {
        Write-UIHost -English "  Cannot provision: ISO not cached and no -IsoPath given." -Chinese "  无法准备：ISO 未缓存，且未提供 -IsoPath。" -ForegroundColor Red
    } else {
        $upCommand = Join-Path (Get-ProjectRoot) "cli\commands\up.ps1"
        $upArgs = @{
            RuntimeName = $RuntimeName
            NoProvision = $SkipProvision
        }
        if ($IsoPath) {
            $upArgs.IsoPath = $IsoPath
        }

        . $upCommand @upArgs
    }
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-UIHost -English "  ADP-OS Phase 2 Init Complete" -Chinese "  ADP-OS 阶段 2 初始化完成" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-UIHost -English "Next: adp up <runtime>     Start/auto-create a runtime" -Chinese "下一步: adp up <runtime>     启动/自动创建运行时" -ForegroundColor Cyan
Write-UIHost -English "      adp doctor            Check platform health" -Chinese "      adp doctor            检查平台健康状态" -ForegroundColor Cyan
Write-Host ""
