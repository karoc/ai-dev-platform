# ADP-OS Quickstart Wizard
# Guided first-run experience — chains precheck, ISO download, install, init, and doctor
# Designed to reduce the ~15 manual steps to one guided flow

[CmdletBinding()]
param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoRegisterCommand,
    [switch]$Plan,
    [switch]$HelpPrereqs
)

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "scripts\adpos-registration.ps1")

function Show-QuickstartPlan {
    param(
        [string]$Distro,
        [string]$IsoPath,
        [switch]$SkipIsoDownload,
        [switch]$SkipDoctor,
        [switch]$NonInteractive,
        [switch]$Force,
        [switch]$NoRegisterCommand
    )

    Write-Host ""
    Write-UIHost -English "ADP-OS Quickstart Plan" -Chinese "ADP-OS 快速启动计划" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-UIHost -English "Plan only: no precheck remediation, ISO download, install, init, doctor, global command registration, VM, sync, or host configuration changes will be made." -Chinese "仅预览：不会执行 precheck 修复、ISO 下载、安装、初始化、doctor、全局命令注册、VM、同步或主机配置更改。" -ForegroundColor Yellow
    Write-Host ""
    Write-UIHost -English "Requested options:" -Chinese "请求的选项:" -ForegroundColor Cyan
    Write-UIHost -English "  Distro: $Distro" -Chinese "  发行版: $Distro" -ForegroundColor DarkGray
    Write-UIHost -English "  ISO path: $(if ($IsoPath) { $IsoPath } else { '(cache/default)' })" -Chinese "  ISO 路径: $(if ($IsoPath) { $IsoPath } else { '(缓存/默认)' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Skip ISO download: $(if ($SkipIsoDownload) { 'true' } else { 'false' })" -Chinese "  跳过 ISO 下载: $(if ($SkipIsoDownload) { 'true' } else { 'false' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Skip doctor: $(if ($SkipDoctor) { 'true' } else { 'false' })" -Chinese "  跳过 doctor: $(if ($SkipDoctor) { 'true' } else { 'false' })" -ForegroundColor DarkGray
    Write-UIHost -English "  NonInteractive: $(if ($NonInteractive) { 'true' } else { 'false' })" -Chinese "  非交互: $(if ($NonInteractive) { 'true' } else { 'false' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Force: $(if ($Force) { 'true' } else { 'false' })" -Chinese "  强制: $(if ($Force) { 'true' } else { 'false' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Register global command: $(if ($NoRegisterCommand) { 'no' } else { 'yes' })" -Chinese "  注册全局命令: $(if ($NoRegisterCommand) { '否' } else { '是' })" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Would run:" -Chinese "将执行:" -ForegroundColor Cyan
    if (-not $Force) {
        Write-UIHost -English "  1. adpos precheck" -Chinese "  1. adpos precheck" -ForegroundColor DarkGray
        Write-UIHost -English "     Mutagen-only remediation would be reported but not installed in -Plan." -Chinese "     在 -Plan 中只报告 Mutagen-only 修复，不安装。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  1. Skip prerequisite scan (-Force)." -Chinese "  1. 跳过前提条件扫描 (-Force)。" -ForegroundColor DarkGray
    }
    if ($SkipIsoDownload) {
        Write-UIHost -English "  2. Skip ISO download (-SkipIsoDownload)." -Chinese "  2. 跳过 ISO 下载 (-SkipIsoDownload)。" -ForegroundColor DarkGray
    } elseif ($IsoPath) {
        Write-UIHost -English "  2. Use provided ISO: $IsoPath" -Chinese "  2. 使用提供的 ISO: $IsoPath" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Download or reuse the configured ISO cache." -Chinese "  2. 下载或复用配置的 ISO 缓存。" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  3. install.ps1 (global adpos registration: $(if ($NoRegisterCommand) { 'skipped' } else { 'enabled' }))" -Chinese "  3. install.ps1（全局 adpos 注册: $(if ($NoRegisterCommand) { '跳过' } else { '启用' })）" -ForegroundColor DarkGray
    Write-UIHost -English "  4. adpos init -Quick" -Chinese "  4. adpos init -Quick" -ForegroundColor DarkGray
    if ($SkipDoctor) {
        Write-UIHost -English "  5. Skip doctor (-SkipDoctor)." -Chinese "  5. 跳过 doctor (-SkipDoctor)。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  5. adpos doctor" -Chinese "  5. adpos doctor" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-UIHost -English "To execute: run the same quickstart command without -Plan." -Chinese "要执行: 去掉 -Plan 后运行同一个 quickstart 命令。" -ForegroundColor Cyan
    Write-Host ""
}

if ($Plan) {
    Show-QuickstartPlan `
        -Distro $Distro `
        -IsoPath $IsoPath `
        -SkipIsoDownload:$SkipIsoDownload `
        -SkipDoctor:$SkipDoctor `
        -NonInteractive:$NonInteractive `
        -Force:$Force `
        -NoRegisterCommand:$NoRegisterCommand
    exit 0
}

Write-InfoLog -Message (Get-UIText -English "adpos quickstart" -Chinese "adpos 快速启动") -Component "cli.quickstart"

function Reset-QuickstartExitCode {
    $global:LASTEXITCODE = 0
}

function Get-QuickstartExitCode {
    if ($null -eq $global:LASTEXITCODE -or [string]::IsNullOrWhiteSpace([string]$global:LASTEXITCODE)) {
        return 0
    }

    return [int]$global:LASTEXITCODE
}

function Write-QuickstartRegistrationResult {
    param([Parameter(Mandatory = $true)][object]$Registration)

    if ($Registration.Skipped) {
        Write-UIHost -English "Step 2b: Global command kept: adpos" -Chinese "步骤 2b：已保留全局命令: adpos" -ForegroundColor Yellow
        Write-UIHost -English "  Existing binding: $($Registration.PreviousHome)" -Chinese "  现有绑定: $($Registration.PreviousHome)" -ForegroundColor DarkGray
        Write-UIHost -English "  Use this checkout locally: .\adpos.cmd" -Chinese "  使用当前版本请在本仓库运行: .\adpos.cmd" -ForegroundColor DarkGray
        Write-QuickstartMultiCheckoutGuidance
        Write-Host ""
        return
    }

    if (-not $NonInteractive) {
        $english = if ($Registration.Replaced) { "Step 2b: Global command replaced: adpos" } else { "Step 2b: Global command registered: adpos" }
        $chinese = if ($Registration.Replaced) { "步骤 2b：已替换全局命令: adpos" } else { "步骤 2b：已注册全局命令: adpos" }
        Write-UIHost -English $english -Chinese $chinese -ForegroundColor Green
        Write-Host "  $($Registration.ShimPath)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Write-QuickstartMultiCheckoutGuidance {
    $guidance = Get-ADPOSMultiCheckoutGuidance -LocalCommand ".\adpos.cmd"
    Write-UIHost -English "  Multi-checkout isolation before running VMs here:" -Chinese "  在当前版本运行 VM 前，请先完成多版本隔离:" -ForegroundColor Cyan
    Write-UIHost -English "    Configure ignored $($guidance.ConfigPath) with unique values for:" -Chinese "    在已忽略的 $($guidance.ConfigPath) 中配置唯一值:" -ForegroundColor DarkGray
    foreach ($key in $guidance.ConfigKeys) {
        Write-Host "      - $key" -ForegroundColor DarkGray
    }
    Write-UIHost -English "    Validate this checkout:" -Chinese "    验收当前版本:" -ForegroundColor DarkGray
    foreach ($command in $guidance.ValidationCommands) {
        Write-Host "      - $command" -ForegroundColor DarkGray
    }
}

function Test-QuickstartMutagenOnlyPrecheckIssue {
    param([object[]]$PrecheckResults)

    $issues = @($PrecheckResults | Where-Object { $_.Status -in @("MISSING", "WARN") })
    if ($issues.Count -eq 0) {
        return $false
    }

    return (@($issues | Where-Object { $_.Name -ne "Mutagen 0.18.x" }).Count -eq 0)
}

function Invoke-QuickstartMutagenRemediation {
    param([switch]$NonInteractive)

    Write-Host ""
    Write-UIHost `
        -English "Mutagen is the only missing prerequisite. Installing the tested local Mutagen binary..." `
        -Chinese "Mutagen 是唯一缺失的前提条件。正在安装测试过的本地 Mutagen binary..." `
        -ForegroundColor Cyan
    Write-UIHost `
        -English "  This uses the same ignored .tools\\mutagen location as: adpos doctor -FixMutagen" `
        -Chinese "  这会使用与 adpos doctor -FixMutagen 相同的已忽略 .tools\\mutagen 位置" `
        -ForegroundColor DarkGray

    $doctorCommand = Join-Path (Get-ProjectRoot) "cli\commands\doctor.ps1"
    Reset-QuickstartExitCode
    . $doctorCommand -FixMutagen
    Reset-QuickstartExitCode
}

# --- --help-prereqs: delegate to precheck ---
if ($HelpPrereqs) {
    $precheckCommand = Join-Path (Get-ProjectRoot) "cli\commands\precheck.ps1"
    Reset-QuickstartExitCode
    . $precheckCommand -HelpPrereqs
    exit (Get-QuickstartExitCode)
}

# --- Precheck scan ---
if (-not $NonInteractive) {
    Write-Host ""
    Write-UIHost -English "ADP-OS Quickstart — One-Command Setup" -Chinese "ADP-OS 快速启动 — 一键设置" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

if (-not $Force) {
    $precheckCommand = Join-Path (Get-ProjectRoot) "cli\commands\precheck.ps1"
    $mutagenRemediated = $false
    Reset-QuickstartExitCode
    . $precheckCommand

    if (-not $global:PrecheckPassed -and (Test-QuickstartMutagenOnlyPrecheckIssue -PrecheckResults $global:PrecheckResults)) {
        Invoke-QuickstartMutagenRemediation -NonInteractive:$NonInteractive
        $mutagenRemediated = $true
        Reset-QuickstartExitCode
        . $precheckCommand
    }

    if (-not $global:PrecheckPassed) {
        $issuesCount = if ($global:PrecheckIssues) { $global:PrecheckIssues } else { 1 }
        if ($NonInteractive) {
            # In NonInteractive mode, precheck failures are fatal
            Write-ErrorLog -Message "$issuesCount prerequisite issue(s) detected. Aborting in non-interactive mode." -Component "cli.quickstart"
            Write-UIHost -English "$issuesCount prerequisite issue(s) detected. Use -Force to skip." -Chinese "检测到 $issuesCount 个前提条件问题。使用 -Force 跳过。" -ForegroundColor Red
            exit 1
        }
        Write-Host ""
        if ((Get-UILanguage) -eq "zh-CN") {
            Write-Host "检测到 $issuesCount 个前提条件问题。" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "要继续并忽略警告？" -ForegroundColor Cyan
            Write-Host "  adpos quickstart -Force   跳过前提条件检查" -ForegroundColor DarkGray
            Write-Host "  adpos precheck --help-prereqs   查看完整要求和安装说明" -ForegroundColor DarkGray
        } else {
            Write-Host "$issuesCount prerequisite issue(s) detected." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Want to continue anyway?" -ForegroundColor Cyan
            Write-Host "  adpos quickstart -Force   Skip prerequisite checks" -ForegroundColor DarkGray
            Write-Host "  adpos precheck --help-prereqs   View full requirements and install instructions" -ForegroundColor DarkGray
        }
        Write-Host ""
        exit 1
    }

    if (-not $NonInteractive) {
        if ($mutagenRemediated) {
            Write-UIHost -English "Mutagen remediation succeeded. All prerequisites met. Proceeding with setup..." -Chinese "Mutagen 修复成功。所有前提条件已满足。继续设置..." -ForegroundColor Green
        } else {
            Write-UIHost -English "All prerequisites met. Proceeding with setup..." -Chinese "所有前提条件已满足。继续设置..." -ForegroundColor Green
        }
        Write-Host ""
    }
} else {
    if (-not $NonInteractive) {
        Write-UIHost -English "Prerequisite checks skipped (-Force). Proceeding with setup..." -Chinese "前提条件检查已跳过 (-Force)。继续设置..." -ForegroundColor Yellow

        # Still show a brief requirements summary for context
        Write-Host ""
        Write-UIHost -English "Required: Windows 11, PowerShell 7+, VMware Workstation Pro, WSL+xorriso, Mutagen 0.18.x, OpenSSH" -Chinese "需要: Windows 11, PowerShell 7+, VMware Workstation Pro, WSL+xorriso, Mutagen 0.18.x, OpenSSH" -ForegroundColor DarkGray
        Write-Host ""
    }
}

if (-not $NonInteractive) {
    Write-UIHost -English "This wizard will guide you through:" -Chinese "本向导将引导您完成：" -ForegroundColor Yellow
    Write-UIHost -English "  1. Download Linux ISO (if needed, ~2.6 GB, 10-30 min)" -Chinese "  1. 下载 Linux ISO（如需要，~2.6 GB, 10-30 分钟）" -ForegroundColor DarkGray
    Write-UIHost -English "  2. Platform bootstrap and global adpos registration (~30s)" -Chinese "  2. 平台引导并注册全局 adpos 命令 (~30s)" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Platform initialization and diagnostics (~1 min)" -Chinese "  3. 平台初始化和系统诊断 (~1 分钟)" -ForegroundColor DarkGray
    Write-Host ""
}

# Check if install.ps1 was already run
$alreadyInstalled = Test-ADPInitialized
if ($alreadyInstalled -and -not $NonInteractive) {
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
        if (-not $NonInteractive) {
            Write-UIHost -English "Step 1: Downloading Linux ISO... (~2.6 GB, 10-30 min)" -Chinese "步骤 1：下载 Linux ISO... (~2.6 GB, 10-30 分钟)" -ForegroundColor Cyan
            Write-Host ""
        }

        # Run ISO download (pass -NonInteractive through)
        $isoCommand = Join-Path $projectRoot "cli\commands\iso.ps1"
        $isoArgs = @{ Distro = $Distro }
        if ($NonInteractive) {
            $isoArgs.NonInteractive = $true
        }
        Reset-QuickstartExitCode
        . $isoCommand @isoArgs

        if ((Get-QuickstartExitCode) -ne 0) {
            Write-UIHost -English "  ISO download failed. You can retry or use -SkipIsoDownload to proceed with your own ISO." -Chinese "  ISO 下载失败。您可以重试或使用 -SkipIsoDownload 用自己的 ISO 继续。" -ForegroundColor Yellow
        }
    } elseif ($IsoPath) {
        if (-not $NonInteractive) {
            Write-UIHost -English "Step 1: Using provided ISO: $IsoPath" -Chinese "步骤 1：使用提供的 ISO: $IsoPath" -ForegroundColor Cyan
            Write-Host ""
        }
    } else {
        if (-not $NonInteractive) {
            $sizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
            Write-UIHost -English "Step 1: ISO already cached ($sizeGB GB) — skipping download" -Chinese "步骤 1：ISO 已缓存 ($sizeGB GB) — 跳过下载" -ForegroundColor Cyan
            Write-Host ""
        }
    }
} else {
    if (-not $NonInteractive) {
        Write-UIHost -English "Step 1: ISO download skipped (-SkipIsoDownload)." -Chinese "步骤 1：ISO 下载已跳过 (-SkipIsoDownload)。" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# =============================================
# Step 2: Run install.ps1 (if not already done)
# =============================================
if (-not $alreadyInstalled) {
    if (-not $NonInteractive) {
        Write-UIHost -English "Step 2: Running platform bootstrap... (~30s)" -Chinese "步骤 2：运行平台引导... (~30s)" -ForegroundColor Cyan
        Write-Host ""
    }

    $installScript = Join-Path $projectRoot "install.ps1"
    $installArgs = @()
    if ($IsoPath) {
        $installArgs += "-IsoPath", $IsoPath
    }
    if ($NoRegisterCommand) {
        $installArgs += "-NoRegisterCommand"
    }
    if ($NonInteractive) {
        $installArgs += "-NonInteractive"
    }
    if ($Force) {
        $installArgs += "-RegisterCommandForce"
    }

    Reset-QuickstartExitCode
    & $installScript @installArgs
    $installExitCode = Get-QuickstartExitCode

    if ($installExitCode -ne 0) {
        Write-ErrorLog -Message "install.ps1 failed with exit code $installExitCode" -Component "cli.quickstart"
        Write-UIHost -English "  Platform bootstrap failed. Check output above for details." -Chinese "  平台引导失败。请查看上方输出了解详情。" -ForegroundColor Red
        exit 1
    }
} else {
    if (-not $NonInteractive) {
        Write-UIHost -English "Step 2: Platform already bootstrapped — skipping install.ps1" -Chinese "步骤 2：平台已引导 — 跳过 install.ps1" -ForegroundColor DarkGray
        Write-Host ""
    }
    if (-not $NoRegisterCommand) {
        $registration = Install-ADPOSCommandRegistration -ProjectRoot $projectRoot -NonInteractive:$NonInteractive -Force:$Force
        Write-QuickstartRegistrationResult -Registration $registration
    }
}

# =============================================
# Step 3: adpos init -Quick
# =============================================
if (-not $NonInteractive) {
    Write-UIHost -English "Step 3: Initializing platform... (~30s)" -Chinese "步骤 3：初始化平台... (~30s)" -ForegroundColor Cyan
    Write-Host ""
}

$initCommand = Join-Path $projectRoot "cli\commands\init.ps1"
$initArgs = @{ Quick = $true; NonInteractive = $NonInteractive }
if ($IsoPath) {
    $initArgs.IsoPath = $IsoPath
}

Reset-QuickstartExitCode
. $initCommand @initArgs
$initExitCode = Get-QuickstartExitCode

if ($initExitCode -ne 0) {
    Write-ErrorLog -Message "adpos init failed with exit code $initExitCode" -Component "cli.quickstart"
    Write-UIHost -English "  Platform init failed. Try running 'adpos init' directly to see detailed errors." -Chinese "  平台初始化失败。尝试直接运行 'adpos init' 查看详细错误。" -ForegroundColor Red
    exit 1
}

# =============================================
# Step 4: adpos doctor
# =============================================
if (-not $SkipDoctor) {
    if (-not $NonInteractive) {
        Write-UIHost -English "Step 4: Running system diagnostics... (~10s)" -Chinese "步骤 4：运行系统诊断... (~10s)" -ForegroundColor Cyan
        Write-Host ""
    }

    $doctorCommand = Join-Path $projectRoot "cli\commands\doctor.ps1"
    Reset-QuickstartExitCode
    . $doctorCommand
    $doctorExitCode = Get-QuickstartExitCode

    if ($doctorExitCode -ne 0) {
        Write-WarnLog -Message "adpos doctor reported issues (exit code $doctorExitCode)" -Component "cli.quickstart"
        Write-UIHost -English "  Doctor found issues. Review the output above for remediation steps." -Chinese "  Doctor 发现问题。请查看上方输出了解修复步骤。" -ForegroundColor Yellow
    }
} else {
    if (-not $NonInteractive) {
        Write-UIHost -English "Step 4: Doctor skipped (-SkipDoctor)." -Chinese "步骤 4：Doctor 已跳过 (-SkipDoctor)。" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# =============================================
# Summary
# =============================================
$currentRegistration = Get-ADPOSExistingRegistration -ProjectRoot $projectRoot
$nextCommand = if ($NoRegisterCommand -or $currentRegistration.IsDifferentHome) { ".\adpos.cmd" } else { "adpos" }

if (-not $NonInteractive) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-UIHost -English "  Quickstart Complete! (~1-2 min)" -Chinese "  快速启动完成！(~1-2 分钟)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-UIHost -English "  Platform initialized successfully." -Chinese "  平台已成功初始化。" -ForegroundColor Green
    Write-Host ""
    Write-UIHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
    Write-UIHost -English "  $nextCommand up frontend    Start your first runtime (creates VM from ISO, ~15-45 min first time)" -Chinese "  $nextCommand up frontend    启动第一个运行时（从 ISO 创建 VM，首次约 15-45 分钟）" -ForegroundColor DarkGray
    Write-UIHost -English "  $nextCommand doctor         Check platform health" -Chinese "  $nextCommand doctor         检查平台健康状态" -ForegroundColor DarkGray
    Write-UIHost -English "  $nextCommand help [command] See all commands or command help" -Chinese "  $nextCommand help [command] 查看所有命令或指定命令帮助" -ForegroundColor DarkGray
    if ($currentRegistration.IsDifferentHome) {
        Write-UIHost -English "  Global adpos is unchanged; uninstall it from its owning checkout if needed." -Chinese "  全局 adpos 未改变；如需卸载，请在其所属 checkout 中执行。" -ForegroundColor DarkGray
        Write-QuickstartMultiCheckoutGuidance
    } elseif (-not $NoRegisterCommand) {
        Write-UIHost -English "  adpos uninstall      Remove the global command registration" -Chinese "  adpos uninstall      移除全局命令注册" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  If this terminal cannot find adpos yet, open a new terminal or use .\adpos.cmd from this repository." -Chinese "  如果当前终端暂时找不到 adpos，请打开新终端，或在本仓库中使用 .\adpos.cmd。" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "  For more info: https://github.com/karoc/ai-dev-platform" -Chinese "  更多信息：https://github.com/karoc/ai-dev-platform" -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-InfoLog -Message "Quickstart completed successfully (non-interactive)" -Component "cli.quickstart"
}

exit 0
