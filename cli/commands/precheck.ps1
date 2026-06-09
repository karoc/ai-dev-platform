# ADP-OS Precheck Command
# Lightweight prerequisite scan.
# Checks all prerequisites and prints a table with status and remediation
# Non-blocking by default: reports results but doesn't exit with error

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$HelpPrereqs
)

Write-InfoLog -Message (Get-UIText -English "Running: adpos precheck" -Chinese "正在运行: adpos precheck") -Component "cli.precheck"
$global:PrecheckPassed = $false
$global:PrecheckIssues = 0
$global:PrecheckResults = @()

# --- Help prereqs: just print the full requirements list ---
if ($HelpPrereqs) {
    Write-Host ""
    Write-UIHost -English "ADP-OS Prerequisites" -Chinese "ADP-OS 前提条件" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "ADP-OS 需要以下工具才能运行:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  1. Windows 11" -ForegroundColor White
        Write-Host "     需要: Windows 11"
        Write-Host ""
        Write-Host "  2. PowerShell 7+" -ForegroundColor White
        Write-Host "     安装: winget install --id Microsoft.PowerShell --source winget"
        Write-Host "     或: https://github.com/PowerShell/PowerShell/releases"
        Write-Host ""
        Write-Host "  3. VMware Workstation Pro" -ForegroundColor White
        Write-Host "     需要 vmrun.exe 和 vmware-vdiskmanager.exe"
        Write-Host "     下载: https://www.vmware.com/products/workstation-pro.html"
        Write-Host ""
        Write-Host "  4. WSL (Windows Subsystem for Linux)" -ForegroundColor White
        Write-Host "     安装: wsl --install"
        Write-Host "     WSL 中需要 xorriso:"
        Write-Host "       wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`""
        Write-Host ""
        Write-Host "  5. Mutagen 0.18.x" -ForegroundColor White
        Write-Host "     自动安装: .\adpos.cmd doctor -FixMutagen"
        Write-Host "     或手动放到: .tools\mutagen\mutagen.exe"
        Write-Host "     下载: https://github.com/mutagen-io/mutagen/releases"
        Write-Host ""
        Write-Host "  6. OpenSSH Client" -ForegroundColor White
        Write-Host "     安装: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        Write-Host ""
        Write-Host "macOS/Linux 支持保留给未来阶段。" -ForegroundColor DarkGray
    } else {
        Write-Host "ADP-OS requires the following tools to run:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  1. Windows 11" -ForegroundColor White
        Write-Host "     Requires: Windows 11"
        Write-Host ""
        Write-Host "  2. PowerShell 7+" -ForegroundColor White
        Write-Host "     Install: winget install --id Microsoft.PowerShell --source winget"
        Write-Host "     Or: https://github.com/PowerShell/PowerShell/releases"
        Write-Host ""
        Write-Host "  3. VMware Workstation Pro" -ForegroundColor White
        Write-Host "     Requires vmrun.exe and vmware-vdiskmanager.exe"
        Write-Host "     Download: https://www.vmware.com/products/workstation-pro.html"
        Write-Host ""
        Write-Host "  4. WSL (Windows Subsystem for Linux)" -ForegroundColor White
        Write-Host "     Install: wsl --install"
        Write-Host "     xorriso is required inside WSL:"
        Write-Host "       wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`""
        Write-Host ""
        Write-Host "  5. Mutagen 0.18.x" -ForegroundColor White
        Write-Host "     Auto-install: .\adpos.cmd doctor -FixMutagen"
        Write-Host "     Or place manually at: .tools\mutagen\mutagen.exe"
        Write-Host "     Download: https://github.com/mutagen-io/mutagen/releases"
        Write-Host ""
        Write-Host "  6. OpenSSH Client" -ForegroundColor White
        Write-Host "     Install: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0"
        Write-Host ""
        Write-Host "macOS/Linux support reserved for future phases." -ForegroundColor DarkGray
    }
    Write-Host ""
    exit 0
}

# --- Load helpers ---
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\vmware\vmware.ps1")

# --- Platform check ---
$platform = Get-Platform
if ($platform -ne "windows") {
    if ($Json) {
        $result = @{
            Command   = "precheck"
            Platform  = $platform
            Supported = $false
            Message   = Get-UIText -English "macOS/Linux not yet supported. ADP-OS currently requires Windows." -Chinese "macOS/Linux 尚未支持。ADP-OS 当前需要 Windows。"
            Checks    = @()
        }
        $result | ConvertTo-Json -Depth 3
        exit 1
    }

    Write-Host ""
    Write-UIHost -English "ADP-OS Precheck — macO/Linux not yet supported" -Chinese "ADP-OS Precheck — macOS/Linux 尚未支持" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-UIHost -English "ADP-OS currently requires Windows. Detected platform: $platform" -Chinese "ADP-OS 当前需要 Windows。检测到平台: $platform" -ForegroundColor Yellow
    Write-UIHost -English "macOS/Linux support is reserved for future phases." -Chinese "macOS/Linux 支持保留给未来阶段。" -ForegroundColor DarkGray
    Write-Host ""

    $global:PrecheckPassed = $false
    $global:PrecheckIssues = 1
    exit 1
}

# --- Check functions ---
$script:checks = @()

function Add-PrecheckResult {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = "",
        [string]$Remediation = ""
    )

    $script:checks += @{
        Name        = $Name
        Status      = $Status
        Detail      = $Detail
        Remediation = $Remediation
    }
}

function Test-WSLCommand {
    param([string]$Command)

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $false
    }

    $null = & $wsl.Source bash -lc "command -v $Command >/dev/null 2>&1" 2>$null
    return $LASTEXITCODE -eq 0
}

# --- Run checks ---
$projectRoot = Get-ProjectRoot

# 1. Windows Version
$osInfo = Get-CimInstance Win32_OperatingSystem
$winVersion = [Version]$osInfo.Version
$isWindows11 = $winVersion.Major -gt 10 -or ($winVersion.Major -eq 10 -and $winVersion.Build -ge 22000)
if ($isWindows11) {
    Add-PrecheckResult -Name "Windows 11" -Status "OK" -Detail $osInfo.Caption
} else {
    Add-PrecheckResult -Name "Windows 11" -Status "MISSING" `
        -Detail $osInfo.Caption `
        -Remediation (Get-UIText -English "Upgrade to Windows 11." -Chinese "升级到 Windows 11。")
}

# 2. PowerShell 7+
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Add-PrecheckResult -Name "PowerShell 7+" -Status "OK" -Detail "v$psVersion"
} else {
    Add-PrecheckResult -Name "PowerShell 7+" -Status "MISSING" `
        -Detail "v$psVersion" `
        -Remediation (Get-UIText -English "Install: winget install --id Microsoft.PowerShell --source winget" -Chinese "安装: winget install --id Microsoft.PowerShell --source winget")
}

# 3. VMware Workstation Pro
# Initialize Provider to check VMware availability
$vmwareAvailable = $false
try {
    . (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
    $providerType = Get-ConfiguredProviderType
    $vmStore = Resolve-Path "vm_store"
    Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null
    $vmwareAvailable = $true
} catch {
    $vmwareAvailable = $false
}

if ($vmwareAvailable) {
    $info = Get-ProviderInfo
    Add-PrecheckResult -Name "VMware Workstation Pro" -Status "OK" -Detail "Provider: $($info.Data.Name)"
} else {
    Add-PrecheckResult -Name "VMware Workstation Pro" -Status "MISSING" `
        -Detail (Get-UIText -English "vmrun.exe not found" -Chinese "未找到 vmrun.exe") `
        -Remediation (Get-UIText -English "Install VMware Workstation Pro: https://www.vmware.com/products/workstation-pro.html" -Chinese "安装 VMware Workstation Pro: https://www.vmware.com/products/workstation-pro.html")
}

# 4. WSL + xorriso
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
$hasXorriso = Test-WSLCommand -Command "xorriso"

if ($wsl -and $hasXorriso) {
    Add-PrecheckResult -Name "WSL + xorriso" -Status "OK" -Detail $wsl.Source
} elseif ($wsl) {
    Add-PrecheckResult -Name "WSL + xorriso" -Status "WARN" `
        -Detail (Get-UIText -English "WSL found, xorriso missing" -Chinese "已安装 WSL，缺少 xorriso") `
        -Remediation (Get-UIText -English 'Install: wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"' -Chinese '安装: wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"')
} else {
    Add-PrecheckResult -Name "WSL + xorriso" -Status "MISSING" `
        -Detail (Get-UIText -English "wsl.exe not found" -Chinese "未找到 wsl.exe") `
        -Remediation (Get-UIText -English "Install WSL: wsl --install" -Chinese "安装 WSL: wsl --install")
}

# 5. Mutagen 0.18.x
$mutagen = Find-Mutagen -ProjectRoot $projectRoot
if ($mutagen) {
    $mutagenVersion = Get-MutagenVersion -Path $mutagen
    if (Test-MutagenVersionSupported -VersionText $mutagenVersion) {
        Add-PrecheckResult -Name "Mutagen 0.18.x" -Status "OK" -Detail "$mutagenVersion"
    } else {
        Add-PrecheckResult -Name "Mutagen 0.18.x" -Status "WARN" `
            -Detail "$mutagenVersion (tested with 0.18.x)" `
            -Remediation (Get-UIText -English "Run: .\adpos.cmd doctor -FixMutagen" -Chinese "运行: .\adpos.cmd doctor -FixMutagen")
    }
} else {
    Add-PrecheckResult -Name "Mutagen 0.18.x" -Status "MISSING" `
        -Detail (Get-UIText -English "not installed" -Chinese "未安装") `
        -Remediation (Get-UIText -English "Run: .\adpos.cmd doctor -FixMutagen, or place mutagen.exe at .tools\mutagen\mutagen.exe" -Chinese "运行: .\adpos.cmd doctor -FixMutagen，或把 mutagen.exe 放到 .tools\mutagen\mutagen.exe")
}

# 6. OpenSSH Client
$ssh = Get-Command ssh -ErrorAction SilentlyContinue
if ($ssh) {
    Add-PrecheckResult -Name "OpenSSH Client" -Status "OK" -Detail $ssh.Source
} else {
    Add-PrecheckResult -Name "OpenSSH Client" -Status "MISSING" `
        -Detail (Get-UIText -English "ssh not found" -Chinese "未找到 ssh") `
        -Remediation (Get-UIText -English "Install: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -Chinese "安装: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0")
}

# --- Compute results ---
$missing = @($script:checks | Where-Object { $_.Status -eq "MISSING" })
$warnings = @($script:checks | Where-Object { $_.Status -eq "WARN" })
$okCount = ($script:checks | Where-Object { $_.Status -eq "OK" }).Count
$warnCount = $warnings.Count
$missingCount = $missing.Count

# --- JSON output ---
if ($Json) {
    $result = @{
        Command   = "precheck"
        Platform  = "windows"
        Passed    = ($missingCount -eq 0)
        Summary   = @{
            Total   = $script:checks.Count
            OK      = $okCount
            WARN    = $warnCount
            MISSING = $missingCount
        }
        Checks    = @($script:checks | ForEach-Object {
            @{
                Name        = $_.Name
                Status      = $_.Status
                Detail      = $_.Detail
                Remediation = $_.Remediation
            }
        })
    }
    $result | ConvertTo-Json -Depth 3
    if ($missingCount -gt 0) {
        exit 1
    }
    exit 0
}

# --- Human-readable output ---
Write-Host ""
Write-UIHost -English "ADP-OS Precheck — Prerequisite Scan" -Chinese "ADP-OS Precheck — 前提条件扫描" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Table header
if ((Get-UILanguage) -eq "zh-CN") {
    Write-Host ("{0,-28} {1,-10} {2}" -f "项目", "状态", "详情") -ForegroundColor Yellow
    Write-Host ("{0,-28} {1,-10} {2}" -f "----", "----", "----") -ForegroundColor DarkGray
} else {
    Write-Host ("{0,-28} {1,-10} {2}" -f "Item", "Status", "Detail") -ForegroundColor Yellow
    Write-Host ("{0,-28} {1,-10} {2}" -f "----", "------", "------") -ForegroundColor DarkGray
}

foreach ($check in $script:checks) {
    $color = switch ($check.Status) {
        "OK"      { "Green" }
        "WARN"    { "Yellow" }
        "MISSING" { "Red" }
        default   { "DarkGray" }
    }

    $displayStatus = switch ($check.Status) {
        "OK"      { "[OK]     " }
        "WARN"    { "[WARN]   " }
        "MISSING" { "[MISSING]" }
        default   { $check.Status }
    }

    if ((Get-UILanguage) -eq "zh-CN") {
        $displayStatus = switch ($check.Status) {
            "OK"      { "[通过]   " }
            "WARN"    { "[警告]   " }
            "MISSING" { "[缺失]   " }
            default   { $check.Status }
        }
    }

    Write-Host ("{0,-28} " -f $check.Name) -NoNewline
    Write-Host $displayStatus -NoNewline -ForegroundColor $color
    Write-Host " $($check.Detail)" -ForegroundColor DarkGray
}

# Remediation section for non-OK items
$needsRemediation = @($script:checks | Where-Object { $_.Status -in @("MISSING", "WARN") -and $_.Remediation })
if ($needsRemediation.Count -gt 0) {
    Write-Host ""
    Write-UIHost -English "Remediation steps:" -Chinese "修复步骤:" -ForegroundColor Cyan

    foreach ($item in $needsRemediation) {
        $color = if ($item.Status -eq "MISSING") { "Red" } else { "Yellow" }
        Write-Host ("  [{0}] {1}" -f $item.Status, $item.Name) -ForegroundColor $color
        Write-Host ("    {0}" -f $item.Remediation) -ForegroundColor DarkGray
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

$summaryColor = if ($missingCount -eq 0 -and $warnCount -eq 0) { "Green" }
    elseif ($missingCount -eq 0) { "Yellow" }
    else { "Red" }

if ((Get-UILanguage) -eq "zh-CN") {
    Write-Host ("结果: {0} 通过, {1} 警告, {2} 缺失" -f $okCount, $warnCount, $missingCount) -ForegroundColor $summaryColor
} else {
    Write-Host ("Result: {0} OK, {1} WARN, {2} MISSING" -f $okCount, $warnCount, $missingCount) -ForegroundColor $summaryColor
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($missingCount -gt 0) {
    Write-UIHost -English "One or more required tools are missing. Install them and re-run precheck." -Chinese "缺少一个或多个必需工具。请安装后重新运行 precheck。" -ForegroundColor Yellow
    Write-Host ""
    Write-UIHost -English "To see the full requirements list: adpos precheck --help-prereqs" -Chinese "查看完整需求列表: adpos precheck --help-prereqs" -ForegroundColor DarkGray
    Write-Host ""
}

# Store result for callers (e.g. quickstart)
$global:PrecheckPassed = ($missingCount -eq 0)
$global:PrecheckIssues = ($missingCount + $warnCount)
$global:PrecheckResults = @($script:checks | ForEach-Object { [pscustomobject]$_ })
