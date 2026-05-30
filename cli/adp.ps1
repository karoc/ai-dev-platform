# ADP-OS CLI Entry Point
# Subcommand routing: init, up, status, stop, sync, snapshot, logs, doctor, destroy, capabilities
# .SYNOPSIS
#   adp.ps1 <command> [args...]

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Load Core ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"

Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs")

# --- Command Router ---
$validCommands = @("init", "up", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "help")

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
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-SkipProvision]  初始化并准备一个运行时"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  启动运行时"
        Write-Host "  adp status [runtime]           显示运行时状态和连接信息"
        Write-Host "  adp stop <runtime>             停止运行时"
        Write-Host "  adp sync status                显示工作区同步状态"
        Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>  管理工作区 manifest"
        Write-Host "  adp capabilities               显示已支持和计划中的运行时能力"
        Write-Host "  adp network configure-local [-Plan|-Apply]  预览/应用本机 VMnet8 覆盖配置"
        Write-Host "  adp network apply <rt|all> [-Plan]  应用已配置的静态 IP 网络"
        Write-Host "  adp snapshot create <rt> <name>  创建运行时快照"
        Write-Host "  adp restore <rt> <name>        恢复运行时快照"
        Write-Host "  adp logs <runtime>             显示运行时日志"
        Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan]  运行诊断和可选 Mutagen 修复"
        Write-Host "  adp destroy <runtime> [-Plan]  销毁运行时"
        Write-Host "  adp help                       显示此帮助"
    } else {
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  adp init                       Initialize platform and VM factory"
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-SkipProvision]  Initialize and prepare a runtime"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  Start a runtime"
        Write-Host "  adp status [runtime]           Show runtime status and connection details"
        Write-Host "  adp stop <runtime>             Stop a runtime"
        Write-Host "  adp sync status                Show workspace sync status"
        Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>  Manage workspace manifests"
        Write-Host "  adp capabilities               Show supported and planned runtime capabilities"
        Write-Host "  adp network configure-local [-Plan|-Apply]  Plan/apply local VMnet8 overrides"
        Write-Host "  adp network apply <rt|all> [-Plan]  Apply configured static IP networking"
        Write-Host "  adp snapshot create <rt> <name>  Create runtime snapshot"
        Write-Host "  adp restore <rt> <name>        Restore runtime snapshot"
        Write-Host "  adp logs <runtime>             Show runtime logs"
        Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan]  Run diagnostics and optional Mutagen remediation"
        Write-Host "  adp destroy <runtime> [-Plan]  Destroy a runtime"
        Write-Host "  adp help                       Show this help"
    }
    Write-Host ""
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
if ($LASTEXITCODE) {
    exit $LASTEXITCODE
}
