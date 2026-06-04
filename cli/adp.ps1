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
$validCommands = @("init", "up", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "validate", "help", "run", "completion", "version", "iso", "quickstart", "precheck", "sandbox")

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
    param(
        [string]$CommandName
    )

    if ($CommandName) {
        Show-CommandHelp -CommandName $CommandName
        return
    }

    Write-Host ""
    Write-Host "ADP-OS CLI — AI Development Platform OS" -ForegroundColor Cyan
    Write-Host ""

    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "命令:" -ForegroundColor Yellow
        Write-Host "  adp init                       初始化平台和 VM factory"
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]  初始化并准备一个运行时"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  启动运行时"
        Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]  一键创建并启动运行时 (init + up + sync start + status)"
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
        Write-Host "  adp destroy <runtime> [-Plan] [-Force]  销毁运行时"
        Write-Host "  adp completion <powershell|bash>  生成 shell 补全脚本"
        Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]  下载 Linux ISO 到缓存（使用 BITS 支持断点续传）"
        Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [--help-prereqs]  一键引导设置"
        Write-Host "  adp sandbox <command...> [-Distro <name>] [-IsoPath <path>]  在一次性 VM 中运行命令，执行后自动销毁"
        Write-Host "  adp precheck                  扫描前提条件并显示状态表"
        Write-Host "  adp precheck --help-prereqs   显示完整前提条件列表和安装命令"
        Write-Host "  adp version                    显示版本信息"
        Write-Host "  adp help                       显示此帮助"
        Write-Host ""
        Write-Host "全局选项:" -ForegroundColor Yellow
        Write-Host "  -Json                          以 JSON 格式输出 (支持: status, doctor, capabilities)"
        Write-Host "  --help, --version              显示帮助或版本信息"
        Write-Host ""
        Write-Host "使用 'adp <command> --help' 查看特定命令的详细帮助。" -ForegroundColor DarkGray
    } else {
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  adp init                       Initialize platform and VM factory"
        Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]  Initialize and prepare a runtime"
        Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]  Start a runtime"
        Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]  One-command create and start a runtime (init + up + sync start + status)"
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
        Write-Host "  adp destroy <runtime> [-Plan] [-Force]  Destroy a runtime"
        Write-Host "  adp completion <powershell|bash>  Generate shell completion script"
        Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]  Download Linux ISO to cache (BITS transfer with resume support)"
        Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [--help-prereqs]  One-command guided setup"
        Write-Host "  adp sandbox <command...> [-Distro <name>] [-IsoPath <path>]  Run a command in a disposable VM (auto-destroyed)"
        Write-Host "  adp precheck                  Scan prerequisites and show status table"
        Write-Host "  adp precheck --help-prereqs   Show full prerequisite list with install commands"
        Write-Host "  adp version                    Show version information"
        Write-Host "  adp help                       Show this help"
        Write-Host ""
        Write-Host "Global options:" -ForegroundColor Yellow
        Write-Host "  -Json                          Output in JSON format (supported: status, doctor, capabilities)"
        Write-Host "  --help, --version              Show help or version information"
        Write-Host ""
        Write-Host "Use 'adp <command> --help' for detailed per-command help." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-CommandHelp {
    param(
        [string]$CommandName
    )

    Write-Host ""
    Write-Host "ADP-OS: adp $CommandName" -ForegroundColor Cyan
    Write-Host ""

    if ((Get-UILanguage) -eq "zh-CN") {
        switch ($CommandName) {
            "init" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp init"
                Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  指定 ISO 路径（跳过缓存查找）"
                Write-Host "  -NoProvision     跳过 VM 创建步骤"
                Write-Host "  -Quick           跳过平台依赖检查，快速初始化"
                Write-Host ""
                Write-Host "说明:" -ForegroundColor Yellow
                Write-Host "  不带参数时初始化平台依赖（VMware、Mutagen、SSH）。"
                Write-Host "  带 <runtime> 参数时额外创建并配置指定运行时。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp init"
                Write-Host "  adp init backend -IsoPath D:\ISOs\ubuntu-22.04.iso"
            }
            "up" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  指定 ISO 路径（跳过缓存查找）"
                Write-Host "  -Plan            仅显示计划（dry-run），不执行实际操作"
                Write-Host "  -NoProvision     跳过 VM 创建/克隆步骤"
                Write-Host "  -NoBootstrap     跳过开机后的 SSH bootstrap 步骤"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp up frontend"
                Write-Host "  adp up agent -IsoPath D:\ISOs\ubuntu-22.04.iso -NoBootstrap"
            }
            "run" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  指定 ISO 路径（跳过缓存查找）"
                Write-Host "  -Plan            仅显示计划（dry-run），不执行实际操作"
                Write-Host "  -NoProvision     跳过 VM 创建步骤"
                Write-Host "  -NoBootstrap     跳过 SSH bootstrap 步骤"
                Write-Host "  -NoSync          跳过自动启动同步会话"
                Write-Host ""
                Write-Host "说明:" -ForegroundColor Yellow
                Write-Host "  一键命令：自动执行 init + up + sync start + status。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp run frontend"
                Write-Host "  adp run agent -Plan"
            }
            "status" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp status [runtime] [-Json]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称，省略时显示所有运行时"
                Write-Host "  -Json            以 JSON 格式输出"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp status"
                Write-Host "  adp status frontend -Json"
            }
            "stop" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp stop <runtime>"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp stop frontend"
            }
            "sync" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp sync <status|start|stop|list> [runtime]"
                Write-Host ""
                Write-Host "子命令:" -ForegroundColor Yellow
                Write-Host "  status            显示同步会话状态"
                Write-Host "  start             启动同步会话"
                Write-Host "  stop              停止同步会话"
                Write-Host "  list              列出所有同步会话"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp sync status frontend"
                Write-Host "  adp sync start backend"
            }
            "workspace" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>"
                Write-Host ""
                Write-Host "子命令:" -ForegroundColor Yellow
                Write-Host "  init              初始化工作区"
                Write-Host "  show              显示工作区信息"
                Write-Host "  plan              显示执行计划"
                Write-Host "  status            显示任务状态"
                Write-Host "  dashboard         显示工作区仪表盘"
                Write-Host "  report            生成报告"
                Write-Host "  recipes           列出可用模板"
                Write-Host "  create            创建工作区"
                Write-Host "  open              打开工作区"
                Write-Host "  sync              同步工作区文件"
                Write-Host "  project           项目管理"
                Write-Host "  task              任务管理"
                Write-Host ""
                Write-Host "通用选项:" -ForegroundColor Yellow
                Write-Host "  -ManifestPath     指定 manifest 文件路径（默认: adp-workspace.json）"
                Write-Host "  -Plan             仅显示计划（dry-run）"
                Write-Host "  -Markdown         以 Markdown 格式输出"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp workspace init"
                Write-Host "  adp workspace dashboard -Markdown"
            }
            "capabilities" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp capabilities [-Json]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  -Json            以 JSON 格式输出"
                Write-Host ""
                Write-Host "说明:" -ForegroundColor Yellow
                Write-Host "  只读命令，不修改任何 VM、同步会话、快照或主机网络。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp capabilities"
                Write-Host "  adp capabilities -Json"
            }
            "network" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp network apply <runtime|all> [-Plan]"
                Write-Host "  adp network configure-local [-Plan|-Apply]  (别名: adp network local)"
                Write-Host ""
                Write-Host "命令:" -ForegroundColor Yellow
                Write-Host "  apply             应用配置的静态 IP 网络到运行时"
                Write-Host "  configure-local   预览或应用本机 VMnet8 覆盖配置"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime|all>     运行时名称或 'all'（全部）"
                Write-Host "  -Plan             仅显示将要应用的配置，不实际更改"
                Write-Host "  -Apply            实际应用配置（与 -Plan 互斥）"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp network configure-local -Plan"
                Write-Host "  adp network apply all -Plan"
            }
            "snapshot" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp snapshot create <runtime> <snapshot-name>"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>          运行时名称 (frontend, backend, agent)"
                Write-Host "  <snapshot-name>    快照名称"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp snapshot create frontend before-update"
            }
            "restore" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp restore <runtime> <snapshot-name>"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>          运行时名称 (frontend, backend, agent)"
                Write-Host "  <snapshot-name>    要恢复的快照名称"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp restore frontend before-update"
            }
            "logs" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp logs <runtime>"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp logs frontend"
            }
            "doctor" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan] [-Json]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  -FirstRun        首次运行检查模式（额外验证）"
                Write-Host "  -FixMutagen      自动修复 Mutagen 配置问题"
                Write-Host "  -Plan            仅诊断不修复（dry-run）"
                Write-Host "  -Json            以 JSON 格式输出"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp doctor"
                Write-Host "  adp doctor -FixMutagen -Json"
            }
            "validate" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  -Quick                仅运行快速验证（语法检查）"
                Write-Host "  -SkipCliSmoke         跳过 CLI 烟雾测试"
                Write-Host "  -SkipInstallerSmoke   跳过安装器烟雾测试"
                Write-Host "  -SkipShellSyntax      跳过 shell 语法检查"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp validate"
                Write-Host "  adp validate -Quick"
            }
            "destroy" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp destroy <runtime> [-Plan] [-Force]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <runtime>        运行时名称 (frontend, backend, agent)"
                Write-Host "  -Plan            仅显示将要销毁的内容（dry-run）"
                Write-Host "  -Force           跳过确认提示，直接销毁"
                Write-Host ""
                Write-Host "警告:" -ForegroundColor Red
                Write-Host "  此操作不可逆。销毁后 VM 和所有数据将永久丢失。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp destroy frontend -Plan"
                Write-Host "  adp destroy backend -Force"
            }
            "completion" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp completion <powershell|bash>"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  powershell        生成 PowerShell 补全脚本"
                Write-Host "  bash              生成 Bash 补全脚本"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp completion powershell"
                Write-Host "  adp completion bash > ~/.adp-completion.bash"
            }
            "iso" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  <distro>         发行版名称（默认: ubuntu）"
                Write-Host "  -Url <url>       自定义 ISO 下载地址"
                Write-Host "  -Force           强制重新下载（覆盖缓存）"
                Write-Host ""
                Write-Host "支持的发行版:" -ForegroundColor Yellow
                Write-Host "  ubuntu, almalinux, rocky, debian"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp iso"
                Write-Host "  adp iso debian -Force"
            }
            "quickstart" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [--help-prereqs]"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  -Distro <name>       发行版名称（默认: ubuntu）"
                Write-Host "  -IsoPath <path>      指定 ISO 路径（跳过下载）"
                Write-Host "  -SkipIsoDownload     跳过 ISO 下载步骤"
                Write-Host "  -SkipDoctor          跳过 doctor 诊断步骤"
                Write-Host "  -Force               跳过前提条件检查，强制执行"
                Write-Host "  -NonInteractive      非交互模式（失败即退出）"
                Write-Host "  --help-prereqs       显示完整前提条件列表和安装命令"
                Write-Host ""
                Write-Host "说明:" -ForegroundColor Yellow
                Write-Host "  一键引导式设置：扫描前提条件、下载 ISO、初始化平台、运行依赖检查。"
                Write-Host "  首次运行自动调用 adp precheck，检测确实的工具并给出安装建议。"
                Write-Host "  适合首次使用的用户，减少 ~15 步手动操作。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp quickstart"
                Write-Host "  adp quickstart -Distro debian -SkipDoctor"
                Write-Host "  adp quickstart -Force"
                Write-Host "  adp quickstart --help-prereqs"
            }
            "precheck" {
                Write-Host "用法:" -ForegroundColor Yellow
                Write-Host "  adp precheck"
                Write-Host "  adp precheck --help-prereqs"
                Write-Host ""
                Write-Host "参数:" -ForegroundColor Yellow
                Write-Host "  --help-prereqs    显示完整前提条件列表和安装命令"
                Write-Host ""
                Write-Host "说明:" -ForegroundColor Yellow
                Write-Host "  扫描系统前提条件并显示状态表。"
                Write-Host "  不带参数时显示当前系统满足哪些前提条件。"
                Write-Host "  --help-prereqs 输出每个前提条件的详细安装说明。"
                Write-Host ""
                Write-Host "示例:" -ForegroundColor Yellow
                Write-Host "  adp precheck"
                Write-Host "  adp precheck --help-prereqs"
            }
            default {
                Write-Host "命令 '$CommandName' 没有详细帮助。使用 'adp help' 查看所有命令。" -ForegroundColor Yellow
            }
        }
    } else {
        switch ($CommandName) {
            "init" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp init"
                Write-Host "  adp init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  Specify ISO path (skip cache lookup)"
                Write-Host "  -NoProvision     Skip VM creation step"
                Write-Host "  -Quick           Skip platform dependency checks, fast init"
                Write-Host ""
                Write-Host "Description:" -ForegroundColor Yellow
                Write-Host "  Without arguments: initializes platform dependencies (VMware, Mutagen, SSH)."
                Write-Host "  With <runtime>: additionally creates and configures the named runtime."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp init"
                Write-Host "  adp init backend -IsoPath D:\ISOs\ubuntu-22.04.iso"
            }
            "up" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  Specify ISO path (skip cache lookup)"
                Write-Host "  -Plan            Plan-only mode (dry-run), do not start VM"
                Write-Host "  -NoProvision     Skip VM creation/clone step"
                Write-Host "  -NoBootstrap     Skip post-boot SSH bootstrap step"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp up frontend"
                Write-Host "  adp up agent -IsoPath D:\ISOs\ubuntu-22.04.iso -NoBootstrap"
            }
            "run" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host "  -IsoPath <path>  Specify ISO path (skip cache lookup)"
                Write-Host "  -Plan            Plan-only mode (dry-run), do not execute"
                Write-Host "  -NoProvision     Skip VM creation step"
                Write-Host "  -NoBootstrap     Skip SSH bootstrap step"
                Write-Host "  -NoSync          Skip auto-starting sync session"
                Write-Host ""
                Write-Host "Description:" -ForegroundColor Yellow
                Write-Host "  One-command shortcut: automatically runs init + up + sync start + status."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp run frontend"
                Write-Host "  adp run agent -Plan"
            }
            "status" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp status [runtime] [-Json]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name; omit to show all runtimes"
                Write-Host "  -Json            Output in JSON format"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp status"
                Write-Host "  adp status frontend -Json"
            }
            "stop" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp stop <runtime>"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp stop frontend"
            }
            "sync" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp sync <status|start|stop|list> [runtime]"
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  status           Show sync session status"
                Write-Host "  start            Start sync session"
                Write-Host "  stop             Stop sync session"
                Write-Host "  list             List all sync sessions"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp sync status frontend"
                Write-Host "  adp sync start backend"
            }
            "workspace" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task>"
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  init             Initialize workspace"
                Write-Host "  show             Show workspace info"
                Write-Host "  plan             Show execution plan"
                Write-Host "  status           Show task status"
                Write-Host "  dashboard        Show workspace dashboard"
                Write-Host "  report           Generate report"
                Write-Host "  recipes          List available templates"
                Write-Host "  create           Create workspace"
                Write-Host "  open             Open workspace"
                Write-Host "  sync             Sync workspace files"
                Write-Host "  project          Project management"
                Write-Host "  task             Task management"
                Write-Host ""
                Write-Host "Common options:" -ForegroundColor Yellow
                Write-Host "  -ManifestPath    Specify manifest file path (default: adp-workspace.json)"
                Write-Host "  -Plan            Show plan only (dry-run)"
                Write-Host "  -Markdown        Output in Markdown format"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp workspace init"
                Write-Host "  adp workspace dashboard -Markdown"
            }
            "capabilities" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp capabilities [-Json]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  -Json            Output in JSON format"
                Write-Host ""
                Write-Host "Description:" -ForegroundColor Yellow
                Write-Host "  Read-only. Does not modify VMs, sync sessions, snapshots, or host networking."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp capabilities"
                Write-Host "  adp capabilities -Json"
            }
            "network" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp network apply <runtime|all> [-Plan]"
                Write-Host "  adp network configure-local [-Plan|-Apply]  (alias: adp network local)"
                Write-Host ""
                Write-Host "Commands:" -ForegroundColor Yellow
                Write-Host "  apply            Apply configured static IP networking to runtimes"
                Write-Host "  configure-local  Plan or apply local VMnet8 overrides"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime|all>    Runtime name or 'all' (every runtime)"
                Write-Host "  -Plan            Show what would be applied, do not change"
                Write-Host "  -Apply           Apply configuration (mutually exclusive with -Plan)"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp network configure-local -Plan"
                Write-Host "  adp network apply all -Plan"
            }
            "snapshot" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp snapshot create <runtime> <snapshot-name>"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>          Runtime name (frontend, backend, agent)"
                Write-Host "  <snapshot-name>    Snapshot name"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp snapshot create frontend before-update"
            }
            "restore" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp restore <runtime> <snapshot-name>"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>          Runtime name (frontend, backend, agent)"
                Write-Host "  <snapshot-name>    Snapshot name to restore"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp restore frontend before-update"
            }
            "logs" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp logs <runtime>"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp logs frontend"
            }
            "doctor" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp doctor [-FirstRun] [-FixMutagen] [-Plan] [-Json]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  -FirstRun        First-run check mode (extra validation)"
                Write-Host "  -FixMutagen      Auto-fix Mutagen configuration issues"
                Write-Host "  -Plan            Diagnose only, do not fix (dry-run)"
                Write-Host "  -Json            Output in JSON format"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp doctor"
                Write-Host "  adp doctor -FixMutagen -Json"
            }
            "validate" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  -Quick                Run quick validation only (syntax checks)"
                Write-Host "  -SkipCliSmoke         Skip CLI smoke test"
                Write-Host "  -SkipInstallerSmoke   Skip installer smoke test"
                Write-Host "  -SkipShellSyntax      Skip shell syntax checks"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp validate"
                Write-Host "  adp validate -Quick"
            }
            "destroy" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp destroy <runtime> [-Plan] [-Force]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <runtime>        Runtime name (frontend, backend, agent)"
                Write-Host "  -Plan            Show what would be destroyed (dry-run)"
                Write-Host "  -Force           Skip confirmation prompt, destroy immediately"
                Write-Host ""
                Write-Host "Warning:" -ForegroundColor Red
                Write-Host "  This operation is irreversible. The VM and all data will be permanently lost."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp destroy frontend -Plan"
                Write-Host "  adp destroy backend -Force"
            }
            "completion" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp completion <powershell|bash>"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  powershell        Generate PowerShell completion script"
                Write-Host "  bash              Generate Bash completion script"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp completion powershell"
                Write-Host "  adp completion bash > ~/.adp-completion.bash"
            }
            "iso" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  <distro>         Distribution name (default: ubuntu)"
                Write-Host "  -Url <url>       Custom ISO download URL"
                Write-Host "  -Force           Force re-download (overwrite cache)"
                Write-Host ""
                Write-Host "Supported distros:" -ForegroundColor Yellow
                Write-Host "  ubuntu, almalinux, rocky, debian"
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp iso"
                Write-Host "  adp iso debian -Force"
            }
            "quickstart" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [--help-prereqs]"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  -Distro <name>       Distribution name (default: ubuntu)"
                Write-Host "  -IsoPath <path>      Specify ISO path (skip download)"
                Write-Host "  -SkipIsoDownload     Skip ISO download step"
                Write-Host "  -SkipDoctor          Skip doctor diagnostic step"
                Write-Host "  -Force               Skip prerequisite checks, force execution"
                Write-Host "  -NonInteractive      Non-interactive mode (fail on error)"
                Write-Host "  --help-prereqs       Show full prerequisite list with install commands"
                Write-Host ""
                Write-Host "Description:" -ForegroundColor Yellow
                Write-Host "  Guided first-run wizard: scans prerequisites, downloads ISO, initializes platform, runs diagnostics."
                Write-Host "  Automatically runs adp precheck on first run, showing missing tools with install suggestions."
                Write-Host "  Designed for new users — reduces ~15 manual steps to one guided flow."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp quickstart"
                Write-Host "  adp quickstart -Distro debian -SkipDoctor"
                Write-Host "  adp quickstart -Force"
                Write-Host "  adp quickstart --help-prereqs"
            }
            "precheck" {
                Write-Host "Usage:" -ForegroundColor Yellow
                Write-Host "  adp precheck"
                Write-Host "  adp precheck --help-prereqs"
                Write-Host ""
                Write-Host "Arguments:" -ForegroundColor Yellow
                Write-Host "  --help-prereqs    Show full prerequisite list with install commands"
                Write-Host ""
                Write-Host "Description:" -ForegroundColor Yellow
                Write-Host "  Scan system prerequisites and display a status table."
                Write-Host "  Without arguments: shows which prerequisites are met."
                Write-Host "  --help-prereqs: outputs detailed install instructions for each prerequisite."
                Write-Host ""
                Write-Host "Examples:" -ForegroundColor Yellow
                Write-Host "  adp precheck"
                Write-Host "  adp precheck --help-prereqs"
            }
            default {
                Write-Host "Command '$CommandName' has no detailed help. Use 'adp help' for all commands." -ForegroundColor Yellow
            }
        }
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
    Show-Help -CommandName $Command
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
