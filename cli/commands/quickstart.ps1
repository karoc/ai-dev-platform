# ADP-OS Quickstart Wizard
# Guided first-run experience — chains ISO download, init, and doctor
# Designed to reduce the ~15 manual steps to one guided flow

param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor
)

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")

Write-InfoLog -Message (Get-UIText -English "adp quickstart" -Chinese "adp 快速启动") -Component "cli.quickstart"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS Quickstart — One-Command Setup" -Chinese "  ADP-OS 快速启动 — 一键设置" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-UIHost -English "This wizard will guide you through:" -Chinese "本向导将引导您完成：" -ForegroundColor Yellow
Write-UIHost -English "  1. Download Linux ISO (if needed)" -Chinese "  1. 下载 Linux ISO（如需要）" -ForegroundColor DarkGray
Write-UIHost -English "  2. Platform initialization" -Chinese "  2. 平台初始化" -ForegroundColor DarkGray
Write-Host ""
Write-UIHost -English "Prerequisites:" -Chinese "前提条件：" -ForegroundColor Yellow
Write-UIHost -English "  - Windows 11" -Chinese "  - Windows 11" -ForegroundColor DarkGray
Write-UIHost -English "  - VMware Workstation Pro installed" -Chinese "  - 已安装 VMware Workstation Pro" -ForegroundColor DarkGray
Write-UIHost -English "  - PowerShell 7+ (pwsh.exe)" -Chinese "  - PowerShell 7+ (pwsh.exe)" -ForegroundColor DarkGray
Write-UIHost -English "  - WSL with xorriso" -Chinese "  - WSL 安装有 xorriso" -ForegroundColor DarkGray
Write-Host ""

# Check if install.ps1 was already run
$alreadyInstalled = Test-ADPInitialized
if ($alreadyInstalled) {
    Write-UIHost -English "[INFO] install.ps1 already completed — skipping to init." -Chinese "[INFO] install.ps1 已完成 — 跳过安装，直接到 init。" -ForegroundColor Cyan
    Write-Host ""
}

$projectRoot = Get-ProjectRoot
$config = Get-PlatformConfig

# =============================================
# Step 1: ISO Download
# =============================================
if (-not $SkipIsoDownload) {
    $isoCache = Resolve-Path "iso_cache"
    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $isoPath = Join-Path $isoCache $isoName

    if (-not (Test-Path $isoPath) -and -not $IsoPath) {
        Write-UIHost -English "Step 1: Downloading Linux ISO..." -Chinese "步骤 1：下载 Linux ISO..." -ForegroundColor Cyan
        Write-Host ""

        # Run ISO download
        $isoCommand = Join-Path $projectRoot "cli\commands\iso.ps1"
        $isoArgs = @{ Distro = $Distro }
        . $isoCommand @isoArgs

        if ($LASTEXITCODE -ne 0) {
            Write-UIHost -English "  ISO download failed. You can retry or use -SkipIsoDownload to proceed with your own ISO." -Chinese "  ISO 下载失败。您可以重试或使用 -SkipIsoDownload 用自己的 ISO 继续。" -ForegroundColor Yellow
        }
    } elseif ($IsoPath) {
        Write-UIHost -English "Step 1: Using provided ISO: $IsoPath" -Chinese "步骤 1：使用提供的 ISO: $IsoPath" -ForegroundColor Cyan
        Write-Host ""
    } else {
        $sizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
        Write-UIHost -English "Step 1: ISO already cached ($sizeGB GB) — skipping download" -Chinese "步骤 1：ISO 已缓存 ($sizeGB GB) — 跳过下载" -ForegroundColor Cyan
        Write-Host ""
    }
} else {
    Write-UIHost -English "Step 1: ISO download skipped (-SkipIsoDownload)." -Chinese "步骤 1：ISO 下载已跳过 (-SkipIsoDownload)。" -ForegroundColor DarkGray
    Write-Host ""
}

# =============================================
# Step 2: Run install.ps1 (if not already done)
# =============================================
if (-not $alreadyInstalled) {
    Write-UIHost -English "Step 2: Running platform bootstrap..." -Chinese "步骤 2：运行平台引导..." -ForegroundColor Cyan
    Write-Host ""

    $installScript = Join-Path $projectRoot "install.ps1"
    $installArgs = @()
    if ($IsoPath) {
        $installArgs += "-IsoPath", $IsoPath
    }

    & $installScript @installArgs

    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog -Message "install.ps1 failed with exit code $LASTEXITCODE" -Component "cli.quickstart"
        Write-UIHost -English "  Platform bootstrap failed. Check output above for details." -Chinese "  平台引导失败。请查看上方输出了解详情。" -ForegroundColor Red
        exit 1
    }
} else {
    Write-UIHost -English "Step 2: Platform already bootstrapped — skipping install.ps1" -Chinese "步骤 2：平台已引导 — 跳过 install.ps1" -ForegroundColor DarkGray
    Write-Host ""
}

# =============================================
# Step 3: adp init -Quick
# =============================================
Write-UIHost -English "Step 3: Initializing platform..." -Chinese "步骤 3：初始化平台..." -ForegroundColor Cyan
Write-Host ""

$initCommand = Join-Path $projectRoot "cli\commands\init.ps1"
$initArgs = @{ Quick = $true }
if ($IsoPath) {
    $initArgs.IsoPath = $IsoPath
}

. $initCommand @initArgs

if ($LASTEXITCODE -ne 0) {
    Write-ErrorLog -Message "adp init failed with exit code $LASTEXITCODE" -Component "cli.quickstart"
    Write-UIHost -English "  Platform init failed. Try running 'adp init' directly to see detailed errors." -Chinese "  平台初始化失败。尝试直接运行 'adp init' 查看详细错误。" -ForegroundColor Red
    exit 1
}

# =============================================
# Step 4: adp doctor
# =============================================
if (-not $SkipDoctor) {
    Write-UIHost -English "Step 4: Running system diagnostics..." -Chinese "步骤 4：运行系统诊断..." -ForegroundColor Cyan
    Write-Host ""

    $doctorCommand = Join-Path $projectRoot "cli\commands\doctor.ps1"
    . $doctorCommand

    if ($LASTEXITCODE -ne 0) {
        Write-WarnLog -Message "adp doctor reported issues (exit code $LASTEXITCODE)" -Component "cli.quickstart"
        Write-UIHost -English "  Doctor found issues. Review the output above for remediation steps." -Chinese "  Doctor 发现问题。请查看上方输出了解修复步骤。" -ForegroundColor Yellow
    }
} else {
    Write-UIHost -English "Step 4: Doctor skipped (-SkipDoctor)." -Chinese "步骤 4：Doctor 已跳过 (-SkipDoctor)。" -ForegroundColor DarkGray
    Write-Host ""
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  Quickstart Complete!" -Chinese "  快速启动完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-UIHost -English "  Platform initialized successfully." -Chinese "  平台已成功初始化。" -ForegroundColor Green
Write-Host ""
Write-UIHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
Write-UIHost -English "  adp up frontend    Start your first runtime (creates VM from ISO, ~20-30 min)" -Chinese "  adp up frontend    启动第一个运行时（从 ISO 创建 VM，约 20-30 分钟）" -ForegroundColor DarkGray
Write-UIHost -English "  adp doctor         Check platform health" -Chinese "  adp doctor         检查平台健康状态" -ForegroundColor DarkGray
Write-UIHost -English "  adp help           See all commands" -Chinese "  adp help           查看所有命令" -ForegroundColor DarkGray
Write-Host ""
Write-UIHost -English "  For more info: https://github.com/karoc/ai-dev-platform" -Chinese "  更多信息：https://github.com/karoc/ai-dev-platform" -ForegroundColor DarkGray
Write-Host ""
