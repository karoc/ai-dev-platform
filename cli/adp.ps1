# ADP-OS CLI Entry Point
# Subcommand routing: init, up, status, stop, sync, snapshot, logs, doctor, destroy, capabilities, run, completion, iso, quickstart
# .SYNOPSIS
#   adp.ps1 <command> [args...] [-Json]

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Global JSON output mode ---
if ($Json) {
    $global:ADPOutputJson = $true
} else {
    $global:ADPOutputJson = $false
}

# --- Load Core ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"

Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs")

# --- Command Router ---
$validCommands = @("init", "up", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "validate", "help", "run", "completion", "version", "iso", "quickstart")

function Quote-PowerShellArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Invoke-CommandFile {
    param(
        [string]$Path,
        [string[]]$RawArguments
    )

    $parts = @(". $(Quote-PowerShellArgument $Path)")
    foreach ($arg in $RawArguments) {
        if ($arg -match '^-{1,2}[A-Za-z][A-Za-z0-9_-]*$') {
            $parts += $arg
        } else {
            $parts += (Quote-PowerShellArgument $arg)
        }
    }

    $scriptBlock = [scriptblock]::Create($parts -join " ")
    & $scriptBlock
}

function Show-Help {
    Write-Host ""
    Write-Host "ADP-OS CLI — AI Development Platform OS" -ForegroundColor Cyan
    Write-Host ""

    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "命令:" -ForegroundColor Yellow
        Write-Host "  adp init                       初始化平台和 VM factory"
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]  初始化并准备一个运行时"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  启动运行时"
        Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  一键创建并启动运行时 (init + up + sync start + status)"
        Write-Host "  adp status [runtime] [-Json]   显示运行时状态和连接信息"
        Write-Host "  adp stop <runtime>             停止运行时"
        Write-Host "  adp sync <status|start|stop|list> [runtime]  管理同步会话"
        Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>  管理工作区 manifest"
        Write-Host "  adp capabilities [-Json]       显示已支持和计划中的运行时能力"
        Write-Host "  adp network configure-local [-Plan|-Apply]  预览/应用本机 VMnet8 覆盖配置 (别名: local)"
        Write-Host "  adp network apply <rt|all> [-Plan]  应用已配置的静态 IP 网络"
        Write-Host "  adp snapshot create <rt> <name>  创建运行时快照"
        Write-Host "  adp restore <rt> <name>        恢复运行时快照"
        Write-Host "  adp logs <runtime>             显示运行时日志"
        Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan] [-Json]  运行诊断和可选 Mutagen 修复"
        Write-Host "  adp validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]  运行仓库验证测试"
        Write-Host "  adp destroy <runtime> [-Plan]  销毁运行时"
        Write-Host "  adp completion <powershell|bash>  生成 shell 补全脚本"
        Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]  下载 Linux ISO 到缓存"
        Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor]  一键引导设置"
        Write-Host "  adp version                    显示版本信息"
        Write-Host "  adp help                       显示此帮助"
        Write-Host ""
        Write-Host "全局选项:" -ForegroundColor Yellow
        Write-Host "  -Json                          以 JSON 格式输出 (支持: status, doctor, capabilities)"
        Write-Host "  --help, --version              显示帮助或版本信息"
    } else {
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  adp init                       Initialize platform and VM factory"
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]  Initialize and prepare a runtime"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  Start a runtime"
        Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  One-command create and start a runtime (init + up + sync start + status)"
        Write-Host "  adp status [runtime] [-Json]   Show runtime status and connection details"
        Write-Host "  adp stop <runtime>             Stop a runtime"
        Write-Host "  adp sync <status|start|stop|list> [runtime]  Manage sync sessions"
        Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>  Manage workspace manifests"
        Write-Host "  adp capabilities [-Json]       Show supported and planned runtime capabilities"
        Write-Host "  adp network configure-local [-Plan|-Apply]  Plan/apply local VMnet8 overrides (alias: local)"
        Write-Host "  adp network apply <rt|all> [-Plan]  Apply configured static IP networking"
        Write-Host "  adp snapshot create <rt> <name>  Create runtime snapshot"
        Write-Host "  adp restore <rt> <name>        Restore runtime snapshot"
        Write-Host "  adp logs <runtime>             Show runtime logs"
        Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan] [-Json]  Run diagnostics and optional Mutagen remediation"
        Write-Host "  adp validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]  Run repository validation tests"
        Write-Host "  adp destroy <runtime> [-Plan]  Destroy a runtime"
        Write-Host "  adp completion <powershell|bash>  Generate shell completion script"
        Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]  Download Linux ISO to cache"
        Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor]  One-command guided setup"
        Write-Host "  adp version                    Show version information"
        Write-Host "  adp help                       Show this help"
        Write-Host ""
        Write-Host "Global options:" -ForegroundColor Yellow
        Write-Host "  -Json                          Output in JSON format (supported: status, doctor, capabilities)"
        Write-Host "  --help, --version              Show help or version information"
    }
    Write-Host ""
}

function Show-Version {
    $versionFile = Join-Path $script:ProjectRoot "VERSION"
    if (Test-Path $versionFile) {
        $version = (Get-Content $versionFile -Raw).Trim()
        Write-Host "ADP-OS version $version"
    } else {
        Push-Location $script:ProjectRoot
        try {
            $gitVersion = & git describe --tags --always --dirty 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "ADP-OS version dev-$gitVersion"
            } else {
                Write-Host "ADP-OS version dev (unknown)"
            }
        } finally {
            Pop-Location
        }
    }
}

# --- Help / Version flag detection ---
$helpFlags = @('--help', '-Help', '-?')

# Bare --help or --version as command
if ($Command -and ($helpFlags -contains $Command)) {
    Show-Help
    exit 0
}
if ($Command -eq '--version') {
    Show-Version
    exit 0
}

# Subcommand --help: "adp up --help"
if ($Command -and $Command -in $validCommands -and $Arguments -and ($helpFlags -contains $Arguments[0])) {
    Write-Host ""
    Write-Host "ADP-OS: adp $Command" -ForegroundColor Cyan
    Show-Help
    exit 0
}

if (-not $Command -or $Command -eq "help") {
    Show-Help
    exit 0
}

$commandFile = Join-Path $script:ProjectRoot "cli\commands\$Command.ps1"

if ($Command -notin $validCommands) {
    $unknownCommandMessage = if ((Get-UILanguage) -eq "zh-CN") { "未知命令: $Command" } else { "Unknown command: $Command" }
    Write-ErrorLog -Message $unknownCommandMessage -Component "cli"
    Write-Host ""
    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "可用命令: $($validCommands -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "Valid commands: $($validCommands -join ', ')" -ForegroundColor Yellow
    }
    exit 1
}

if (-not (Test-Path $commandFile)) {
    $reservedLogMessage = if ((Get-UILanguage) -eq "zh-CN") { "命令尚未实现: $Command" } else { "Command not yet implemented: $Command" }
    Write-WarnLog -Message $reservedLogMessage -Component "cli"
    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "  命令 '$Command' 已为未来阶段保留。" -ForegroundColor DarkGray
    } else {
        Write-Host "  Command '$Command' is reserved for a future phase." -ForegroundColor DarkGray
    }
    exit 1
}

Write-DebugLog -Message "Executing command: $Command with args: $Arguments" -Component "cli"
$global:LASTEXITCODE = 0
Invoke-CommandFile -Path $commandFile -RawArguments $Arguments
if ($LASTEXITCODE -gt 0) {
    exit $LASTEXITCODE
}
