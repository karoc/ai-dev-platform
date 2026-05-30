# ADP-OS Install Script
# Phase 1: Project structure + config + VMware adapter bootstrap
# This script bootstraps the ADP-OS platform on Windows

param(
    [switch]$SkipDependencyCheck,
    [switch]$SkipVMValidation,
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = $PSScriptRoot

# --- Source Modules ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"
. "$script:ProjectRoot\adapters\windows\mutagen\mutagen.ps1"
. "$script:ProjectRoot\runtimes\vmware\vm-factory.ps1"

# --- Initialize ---
Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs") -Level "INFO"

function Get-InstallText {
    param(
        [string]$English,
        [string]$Chinese
    )

    if ((Get-UILanguage) -eq "zh-CN") {
        return $Chinese
    }

    return $English
}

function Write-InstallHost {
    param(
        [string]$English,
        [string]$Chinese,
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Gray
    )

    Write-Host (Get-InstallText -English $English -Chinese $Chinese) -ForegroundColor $ForegroundColor
}

function Write-InstallBanner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ADP-OS: AI Development Platform OS" -ForegroundColor Cyan
    Write-InstallHost -English "  Phase 1 — Platform Bootstrap" -Chinese "  阶段 1 — 平台引导" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

Write-InstallBanner
Write-InfoLog -Message (Get-InstallText -English "ADP-OS Install starting..." -Chinese "ADP-OS 安装开始...") -Component "install"
Write-InfoLog -Message (Get-InstallText -English "Project root: $script:ProjectRoot" -Chinese "项目根目录: $script:ProjectRoot") -Component "install"

function Add-DependencyResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Path = "",
        [string]$Remediation = ""
    )

    $script:deps += @{
        Name        = $Name
        Status      = $Status
        Path        = $Path
        Remediation = $Remediation
    }
}

function Write-DependencyLine {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [string]$Remediation = ""
    )

    $color = switch ($Status) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "MISSING" { "Red" }
        default { "DarkGray" }
    }
    $displayStatus = switch ($Status) {
        "OK" { "OK" }
        "WARN" { Get-InstallText -English "WARN" -Chinese "警告" }
        "MISSING" { Get-InstallText -English "MISSING" -Chinese "缺失" }
        default { $Status }
    }
    $suffix = if ($Detail) { " — $Detail" } else { "" }
    Write-Host "  $Name [$displayStatus]$suffix" -ForegroundColor $color
    if ($Remediation) {
        Write-Host "    $Remediation" -ForegroundColor DarkGray
    }
}

function Test-WSLCommand {
    param([string]$Command)

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $false
    }

    & $wsl.Source bash -lc "command -v $Command >/dev/null 2>&1" 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-ISOReasonable {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $item = Get-Item $Path
    return ($item.Length -ge 1GB -and $item.Extension -ieq ".iso")
}

# =============================================
# Step 1: Platform Detection
# =============================================
Write-InstallHost -English "`n[1/6] Detecting platform..." -Chinese "`n[1/6] 检测平台..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "Platform detection starting" -Chinese "平台检测开始") -Component "install"

$platform = Get-Platform
Write-InfoLog -Message (Get-InstallText -English "Detected platform: $platform" -Chinese "检测到平台: $platform") -Component "install"

if ($platform -ne "windows") {
    Write-WarnLog -Message (Get-InstallText -English "ADP-OS MVP requires Windows 11. Detected: $platform" -Chinese "ADP-OS MVP 需要 Windows 11。检测到: $platform") -Component "install"
    Write-WarnLog -Message (Get-InstallText -English "macOS/Linux support reserved for future phases" -Chinese "macOS/Linux 支持保留给未来阶段") -Component "install"
}

# Verify Windows 11
$osInfo = Get-CimInstance Win32_OperatingSystem
$winVersion = [Version]$osInfo.Version
if ($winVersion.Major -lt 10) {
    Write-ErrorLog -Message "Windows 10+ required. Detected: $($osInfo.Caption)" -Component "install"
    throw "Unsupported Windows version"
}
Write-InfoLog -Message (Get-InstallText -English "Windows version: $($osInfo.Caption) ($winVersion)" -Chinese "Windows 版本: $($osInfo.Caption) ($winVersion)") -Component "install"
Write-InstallHost -English "  Platform: Windows (supported)" -Chinese "  平台: Windows（已支持）" -ForegroundColor Green

# =============================================
# Step 2: Dependency Checks
# =============================================
Write-InstallHost -English "`n[2/6] Checking dependencies..." -Chinese "`n[2/6] 检查依赖..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "Dependency check starting" -Chinese "依赖检查开始") -Component "install"

$script:deps = @()

if ($SkipDependencyCheck) {
    Write-InstallHost -English "  Dependency checks skipped by -SkipDependencyCheck." -Chinese "  已通过 -SkipDependencyCheck 跳过依赖检查。" -ForegroundColor Yellow
} else {
    # PowerShell 7+
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 7) {
        Write-DependencyLine -Name "PowerShell 7+" -Status "OK" -Detail "v$psVersion"
        Add-DependencyResult -Name "PowerShell 7+" -Status "OK"
    } else {
        $remediation = Get-InstallText -English "Install PowerShell 7 or newer." -Chinese "安装 PowerShell 7 或更新版本。"
        Write-DependencyLine -Name "PowerShell 7+" -Status "WARN" -Detail "v$psVersion" -Remediation $remediation
        Add-DependencyResult -Name "PowerShell 7+" -Status "WARN" -Remediation $remediation
    }

    # VMware Workstation / vmrun
    $vmwareStatus = Test-VMwareAvailable
    if ($vmwareStatus) {
        $vmrunPath = Find-Vmrun
        Write-DependencyLine -Name "VMware Workstation (vmrun)" -Status "OK" -Detail $vmrunPath
        Add-DependencyResult -Name "VMware Workstation (vmrun)" -Status "OK" -Path $vmrunPath
    } else {
        $remediation = Get-InstallText -English "Install VMware Workstation Pro and ensure vmrun.exe is available." -Chinese "安装 VMware Workstation Pro，并确保 vmrun.exe 可用。"
        Write-DependencyLine -Name "VMware Workstation (vmrun)" -Status "MISSING" -Detail (Get-InstallText -English "vmrun.exe not found" -Chinese "未找到 vmrun.exe") -Remediation $remediation
        Add-DependencyResult -Name "VMware Workstation (vmrun)" -Status "MISSING" -Remediation $remediation
    }

    $diskManager = Find-VmwareDiskManager
    if ($diskManager) {
        Write-DependencyLine -Name "VMware disk manager" -Status "OK" -Detail $diskManager
        Add-DependencyResult -Name "VMware disk manager" -Status "OK" -Path $diskManager
    } else {
        $remediation = Get-InstallText -English "Install VMware Workstation Pro with vmware-vdiskmanager.exe." -Chinese "安装包含 vmware-vdiskmanager.exe 的 VMware Workstation Pro。"
        Write-DependencyLine -Name "VMware disk manager" -Status "MISSING" -Detail (Get-InstallText -English "vmware-vdiskmanager.exe not found" -Chinese "未找到 vmware-vdiskmanager.exe") -Remediation $remediation
        Add-DependencyResult -Name "VMware disk manager" -Status "MISSING" -Remediation $remediation
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        Write-DependencyLine -Name "WSL" -Status "OK" -Detail $wsl.Source
        Add-DependencyResult -Name "WSL" -Status "OK" -Path $wsl.Source
    } else {
        $remediation = Get-InstallText -English "Install or enable WSL before remastering Ubuntu autoinstall ISOs." -Chinese "在重制 Ubuntu autoinstall ISO 前安装或启用 WSL。"
        Write-DependencyLine -Name "WSL" -Status "MISSING" -Detail (Get-InstallText -English "wsl.exe not found" -Chinese "未找到 wsl.exe") -Remediation $remediation
        Add-DependencyResult -Name "WSL" -Status "MISSING" -Remediation $remediation
    }

    if (Test-WSLCommand -Command "xorriso") {
        Write-DependencyLine -Name "WSL xorriso" -Status "OK"
        Add-DependencyResult -Name "WSL xorriso" -Status "OK"
    } else {
        $remediation = Get-InstallText -English "Install with: wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`"" -Chinese "安装命令: wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`""
        Write-DependencyLine -Name "WSL xorriso" -Status "MISSING" -Detail (Get-InstallText -English "required for Ubuntu autoinstall ISO remastering" -Chinese "Ubuntu autoinstall ISO 重制需要此工具") -Remediation $remediation
        Add-DependencyResult -Name "WSL xorriso" -Status "MISSING" -Remediation $remediation
    }

    $isoRemasterTool = Find-ISORemasterTool
    if ($isoRemasterTool) {
        Write-DependencyLine -Name "ISO remaster tool" -Status "OK" -Detail "$($isoRemasterTool.Type): $($isoRemasterTool.Path)"
        Add-DependencyResult -Name "ISO remaster tool" -Status "OK" -Path $isoRemasterTool.Path
    } else {
        $remediation = Get-InstallText -English "Install xorriso natively or in WSL." -Chinese "在本机或 WSL 中安装 xorriso。"
        Write-DependencyLine -Name "ISO remaster tool" -Status "MISSING" -Detail (Get-InstallText -English "xorriso not found" -Chinese "未找到 xorriso") -Remediation $remediation
        Add-DependencyResult -Name "ISO remaster tool" -Status "MISSING" -Remediation $remediation
    }

    # Mutagen
    $mutagen = Find-Mutagen -ProjectRoot $script:ProjectRoot
    if ($mutagen) {
        $mutagenVersion = Get-MutagenVersion -Path $mutagen
        if (Test-MutagenVersionSupported -VersionText $mutagenVersion) {
            Write-DependencyLine -Name "Mutagen" -Status "OK" -Detail "$mutagenVersion at $mutagen"
            Add-DependencyResult -Name "Mutagen" -Status "OK" -Path $mutagen
        } else {
            $remediation = Get-InstallText -English "ADP-OS is tested with Mutagen 0.18.x. Run: .\cli\adp.ps1 doctor -FixMutagen -Plan" -Chinese "ADP-OS 使用 Mutagen 0.18.x 测试。运行: .\cli\adp.ps1 doctor -FixMutagen -Plan"
            Write-DependencyLine -Name "Mutagen" -Status "WARN" -Detail "$mutagenVersion at $mutagen" -Remediation $remediation
            Add-DependencyResult -Name "Mutagen" -Status "WARN" -Path $mutagen -Remediation $remediation
        }
    } else {
        $remediation = Get-InstallText -English "Run: .\cli\adp.ps1 doctor -FixMutagen -Plan, or place Mutagen 0.18.x at .tools\mutagen\mutagen.exe." -Chinese "运行: .\cli\adp.ps1 doctor -FixMutagen -Plan，或把 Mutagen 0.18.x 放到 .tools\mutagen\mutagen.exe。"
        Write-DependencyLine -Name "Mutagen" -Status "MISSING" -Detail (Get-InstallText -English "needed for workspace sync" -Chinese "工作区同步需要此工具") -Remediation $remediation
        Add-DependencyResult -Name "Mutagen" -Status "MISSING" -Remediation $remediation
    }

    # OpenSSH Client
    $ssh = Get-Command ssh -ErrorAction SilentlyContinue
    if ($ssh) {
        Write-DependencyLine -Name "OpenSSH Client" -Status "OK" -Detail $ssh.Source
        Add-DependencyResult -Name "OpenSSH Client" -Status "OK" -Path $ssh.Source
    } else {
        $remediation = Get-InstallText -English "Install the Windows OpenSSH Client optional feature." -Chinese "安装 Windows OpenSSH Client 可选功能。"
        Write-DependencyLine -Name "OpenSSH Client" -Status "MISSING" -Remediation $remediation
        Add-DependencyResult -Name "OpenSSH Client" -Status "MISSING" -Remediation $remediation
    }
}

# =============================================
# Step 3: Directory Structure
# =============================================
Write-InstallHost -English "`n[3/6] Creating directory structure..." -Chinese "`n[3/6] 创建目录结构..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "Directory creation starting" -Chinese "目录创建开始") -Component "install"

$workspaceRoot = Resolve-Path "workspace_root"
$isoCache = Resolve-Path "iso_cache"
$vmStore = Resolve-Path "vm_store"

Initialize-Filesystem -BasePath $workspaceRoot
Initialize-Filesystem -BasePath $vmStore

Write-InstallHost -English "  Workspaces: $workspaceRoot" -Chinese "  工作区: $workspaceRoot" -ForegroundColor Green
Write-InstallHost -English "  ISO Cache:  $isoCache" -Chinese "  ISO 缓存:  $isoCache" -ForegroundColor Green
Write-InstallHost -English "  VM Store:   $vmStore" -Chinese "  VM 存储:   $vmStore" -ForegroundColor Green

# =============================================
# Step 4: ISO Check
# =============================================
Write-InstallHost -English "`n[4/6] Checking OS ISO..." -Chinese "`n[4/6] 检查 OS ISO..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "ISO check starting" -Chinese "ISO 检查开始") -Component "install"

$config = Get-PlatformConfig
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$storedIso = Join-Path $isoCache $isoName

if ($IsoPath) {
    Write-InfoLog -Message (Get-InstallText -English "User provided ISO: $IsoPath" -Chinese "用户提供的 ISO: $IsoPath") -Component "install"
    if (-not (Test-Path $IsoPath)) {
        throw "Specified ISO not found: $IsoPath"
    }
    if (-not (Test-ISOReasonable -Path $IsoPath)) {
        Write-InstallHost -English "  ISO warning: file should be a .iso and usually larger than 1 GB: $IsoPath" -Chinese "  ISO 警告: 文件应为 .iso，且通常大于 1 GB: $IsoPath" -ForegroundColor Yellow
    }
    if (-not (Test-Path $isoCache)) { New-Item -ItemType Directory -Path $isoCache -Force | Out-Null }
    Copy-Item $IsoPath $storedIso -Force
    Write-InstallHost -English "  ISO copied to cache: $storedIso" -Chinese "  ISO 已复制到缓存: $storedIso" -ForegroundColor Green
} elseif (Test-Path $storedIso) {
    $isoSize = [math]::Round((Get-Item $storedIso).Length / 1GB, 1)
    Write-InstallHost -English "  ISO found in cache: $storedIso ($isoSize GB)" -Chinese "  在缓存中找到 ISO: $storedIso ($isoSize GB)" -ForegroundColor Green
    if (-not (Test-ISOReasonable -Path $storedIso)) {
        Write-InstallHost -English "  ISO warning: file should be a .iso and usually larger than 1 GB." -Chinese "  ISO 警告: 文件应为 .iso，且通常大于 1 GB。" -ForegroundColor Yellow
    }
    Write-InfoLog -Message (Get-InstallText -English "ISO found in cache" -Chinese "在缓存中找到 ISO") -Component "install"
} else {
    Write-InstallHost -English "  ISO not found. Please download a supported Linux ISO:" -Chinese "  未找到 ISO。请下载受支持的 Linux ISO:" -ForegroundColor Yellow
    Write-Host "    Ubuntu Server 26.04 LTS: https://releases.ubuntu.com/26.04/" -ForegroundColor DarkGray
    Write-Host "    AlmaLinux 9: https://almalinux.org/get-almalinux/" -ForegroundColor DarkGray
    Write-Host "    Rocky Linux 9: https://rockylinux.org/download/" -ForegroundColor DarkGray
    Write-Host "    Debian 12: https://www.debian.org/distrib/" -ForegroundColor DarkGray
    Write-InstallHost -English "  Place it at: $storedIso" -Chinese "  放置到: $storedIso" -ForegroundColor DarkGray
    Write-InstallHost -English "  Or run: .\install.ps1 -IsoPath <path-to-iso>" -Chinese "  或运行: .\install.ps1 -IsoPath <path-to-iso>" -ForegroundColor DarkGray
}

# =============================================
# Step 5: VMware Adapter Init
# =============================================
Write-InstallHost -English "`n[5/6] Initializing VMware adapter..." -Chinese "`n[5/6] 初始化 VMware adapter..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "VMware adapter initialization" -Chinese "VMware adapter 初始化") -Component "install"

if ($SkipVMValidation) {
    Write-InstallHost -English "  VMware validation skipped by -SkipVMValidation." -Chinese "  已通过 -SkipVMValidation 跳过 VMware 验证。" -ForegroundColor Yellow
} else {
    try {
        $vmrunPath = Initialize-VMware
        Write-Host "  vmrun: $vmrunPath [OK]" -ForegroundColor Green

        $registeredVMs = Get-RegisteredVMs
        Write-InstallHost -English "  Registered VMs: $($registeredVMs.Count)" -Chinese "  已注册 VM: $($registeredVMs.Count)" -ForegroundColor Cyan
        foreach ($vm in $registeredVMs) {
            Write-Host "    - $(Split-Path $vm -Leaf)" -ForegroundColor DarkGray
        }
    } catch {
        Write-ErrorLog -Message "VMware initialization failed: $_" -Component "install"
        throw
    }
}

# =============================================
# Step 6: Config Finalization
# =============================================
Write-InstallHost -English "`n[6/6] Finalizing configuration..." -Chinese "`n[6/6] 完成配置..." -ForegroundColor Yellow
Write-InfoLog -Message (Get-InstallText -English "Config finalization" -Chinese "配置收尾") -Component "install"

Set-ADPInitialized

$topology = Get-TopologyConfig
$runtimeNames = Get-AllRuntimeNames

Write-InstallHost -English "  Configured runtimes:" -Chinese "  已配置运行时:" -ForegroundColor Cyan
foreach ($name in $runtimeNames) {
    $rt = $topology.$name
    $profileBadge = Get-RuntimeProfileBadge -RuntimeName $name -Runtime $rt
    Write-Host "    $name — CPU: $($rt.cpu), RAM: $($rt.memory)MB, Disk: $($rt.disk)GB$profileBadge" -ForegroundColor DarkGray
}

# =============================================
# Summary
# =============================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-InstallHost -English "  ADP-OS Phase 1 Bootstrap Complete" -Chinese "  ADP-OS 阶段 1 平台引导完成" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$missing = $script:deps | Where-Object { $_.Status -eq "MISSING" }
$warnings = $script:deps | Where-Object { $_.Status -eq "WARN" }
if ($SkipDependencyCheck) {
    Write-InstallHost -English "Dependency checks were skipped." -Chinese "依赖检查已跳过。" -ForegroundColor Yellow
} elseif ($missing) {
    Write-InstallHost -English "Missing dependencies:" -Chinese "缺失依赖:" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Name)" -ForegroundColor Yellow
        if ($m.Remediation) {
            Write-Host "    $($m.Remediation)" -ForegroundColor DarkGray
        }
    }
    if ($warnings) {
        Write-Host ""
        Write-InstallHost -English "Warnings:" -Chinese "警告:" -ForegroundColor Yellow
        foreach ($w in $warnings) {
            Write-Host "  - $($w.Name)" -ForegroundColor Yellow
            if ($w.Remediation) {
                Write-Host "    $($w.Remediation)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
    Write-InstallHost -English "Install missing items then re-run install.ps1" -Chinese "安装缺失项后重新运行 install.ps1" -ForegroundColor DarkGray
} elseif ($warnings) {
    Write-InstallHost -English "Dependency warnings:" -Chinese "依赖警告:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  - $($w.Name)" -ForegroundColor Yellow
        if ($w.Remediation) {
            Write-Host "    $($w.Remediation)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-InstallHost -English "All dependencies satisfied." -Chinese "所有依赖均已满足。" -ForegroundColor Green
}

Write-Host ""
Write-InstallHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
Write-InstallHost -English "  Place a supported Linux ISO in: $isoCache" -Chinese "  将受支持的 Linux ISO 放到: $isoCache" -ForegroundColor DarkGray
Write-InstallHost -English "  Then run Phase 2: adp init" -Chinese "  然后运行阶段 2: adp init" -ForegroundColor DarkGray
Write-Host ""

Write-InfoLog -Message (Get-InstallText -English "ADP-OS Phase 1 install complete" -Chinese "ADP-OS 阶段 1 安装完成") -Component "install"
