# ADP-OS CLI help and version output.

function Get-ADPTopLevelCommandRows {
    if ((Get-UILanguage) -eq "zh-CN") {
        return @(
            [pscustomobject]@{ Usage = "adpos setup"; Summary = "一键安装并注册全局 adpos 命令" }
            [pscustomobject]@{ Usage = "adpos init"; Summary = "初始化平台和 VM factory" }
            [pscustomobject]@{ Usage = "adpos init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]"; Summary = "初始化并准备一个运行时" }
            [pscustomobject]@{ Usage = "adpos up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]"; Summary = "启动运行时" }
            [pscustomobject]@{ Usage = "adpos run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]"; Summary = "一键创建并启动运行时" }
            [pscustomobject]@{ Usage = "adpos status [runtime] [-Json]"; Summary = "显示运行时状态和连接信息" }
            [pscustomobject]@{ Usage = "adpos stop <runtime>"; Summary = "停止运行时" }
            [pscustomobject]@{ Usage = "adpos sync <status|start|stop|list> [runtime]"; Summary = "管理同步会话" }
            [pscustomobject]@{ Usage = "adpos workspace <command>"; Summary = "管理工作区 manifest" }
            [pscustomobject]@{ Usage = "adpos capabilities [-Json]"; Summary = "显示已支持和计划中的运行时能力" }
            [pscustomobject]@{ Usage = "adpos isolate [-Plan|-Apply] [-Namespace <name>]"; Summary = "预览或应用多 checkout 本机隔离配置" }
            [pscustomobject]@{ Usage = "adpos network configure-local [-Plan|-Apply]"; Summary = "预览或应用本机 VMnet8 覆盖配置" }
            [pscustomobject]@{ Usage = "adpos network apply <runtime|all> [-Plan]"; Summary = "应用静态 IP 网络配置" }
            [pscustomobject]@{ Usage = "adpos snapshot create <runtime> <name>"; Summary = "创建运行时快照" }
            [pscustomobject]@{ Usage = "adpos restore <runtime> <name> [-Plan] [-Force]"; Summary = "恢复运行时快照" }
            [pscustomobject]@{ Usage = "adpos logs <runtime>"; Summary = "显示运行时日志" }
            [pscustomobject]@{ Usage = "adpos doctor [-FirstRun] [-Json] | adpos doctor -FixMutagen [-Plan] [-Json]"; Summary = "运行诊断和可选 Mutagen 修复" }
            [pscustomobject]@{ Usage = "adpos validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]"; Summary = "运行仓库验证测试" }
            [pscustomobject]@{ Usage = "adpos destroy <runtime> [-Plan] [-Force]"; Summary = "销毁运行时" }
            [pscustomobject]@{ Usage = "adpos completion <powershell|bash>"; Summary = "生成 shell 补全脚本" }
            [pscustomobject]@{ Usage = "adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]"; Summary = "下载 Linux ISO 到缓存" }
            [pscustomobject]@{ Usage = "adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [--help-prereqs]"; Summary = "兼容的一键引导设置入口" }
            [pscustomobject]@{ Usage = "adpos sandbox <command...> [-Distro <name>] [-IsoPath <path>]"; Summary = "在一次性 VM 中运行命令，执行后自动销毁" }
            [pscustomobject]@{ Usage = "adpos serve [-Port <port>] [-Public] [-Json]"; Summary = "启动健康检查 HTTP 服务" }
            [pscustomobject]@{ Usage = "adpos precheck"; Summary = "扫描前提条件并显示状态表" }
            [pscustomobject]@{ Usage = "adpos precheck --help-prereqs"; Summary = "显示完整前提条件列表和安装命令" }
            [pscustomobject]@{ Usage = "adpos uninstall"; Summary = "一键卸载全局 adpos 命令注册，不删除 VM 或 workspace" }
            [pscustomobject]@{ Usage = "adpos version"; Summary = "显示版本信息" }
            [pscustomobject]@{ Usage = "adpos help [command]"; Summary = "显示帮助或指定命令帮助" }
        )
    }

    return @(
        [pscustomobject]@{ Usage = "adpos setup"; Summary = "One-click install and register the global adpos command" }
        [pscustomobject]@{ Usage = "adpos init"; Summary = "Initialize platform and VM factory" }
        [pscustomobject]@{ Usage = "adpos init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]"; Summary = "Initialize and prepare a runtime" }
        [pscustomobject]@{ Usage = "adpos up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]"; Summary = "Start a runtime" }
        [pscustomobject]@{ Usage = "adpos run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]"; Summary = "One-command create and start a runtime" }
        [pscustomobject]@{ Usage = "adpos status [runtime] [-Json]"; Summary = "Show runtime status and connection details" }
        [pscustomobject]@{ Usage = "adpos stop <runtime>"; Summary = "Stop a runtime" }
        [pscustomobject]@{ Usage = "adpos sync <status|start|stop|list> [runtime]"; Summary = "Manage sync sessions" }
        [pscustomobject]@{ Usage = "adpos workspace <command>"; Summary = "Manage workspace manifests" }
        [pscustomobject]@{ Usage = "adpos capabilities [-Json]"; Summary = "Show supported and planned runtime capabilities" }
        [pscustomobject]@{ Usage = "adpos isolate [-Plan|-Apply] [-Namespace <name>]"; Summary = "Plan or apply multi-checkout local isolation settings" }
        [pscustomobject]@{ Usage = "adpos network configure-local [-Plan|-Apply]"; Summary = "Plan or apply local VMnet8 overrides" }
        [pscustomobject]@{ Usage = "adpos network apply <runtime|all> [-Plan]"; Summary = "Apply configured static IP networking" }
        [pscustomobject]@{ Usage = "adpos snapshot create <runtime> <name>"; Summary = "Create runtime snapshot" }
        [pscustomobject]@{ Usage = "adpos restore <runtime> <name> [-Plan] [-Force]"; Summary = "Restore runtime snapshot" }
        [pscustomobject]@{ Usage = "adpos logs <runtime>"; Summary = "Show runtime logs" }
        [pscustomobject]@{ Usage = "adpos doctor [-FirstRun] [-Json] | adpos doctor -FixMutagen [-Plan] [-Json]"; Summary = "Run diagnostics and optional Mutagen remediation" }
        [pscustomobject]@{ Usage = "adpos validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]"; Summary = "Run repository validation tests" }
        [pscustomobject]@{ Usage = "adpos destroy <runtime> [-Plan] [-Force]"; Summary = "Destroy a runtime" }
        [pscustomobject]@{ Usage = "adpos completion <powershell|bash>"; Summary = "Generate shell completion script" }
        [pscustomobject]@{ Usage = "adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]"; Summary = "Download Linux ISO to cache" }
        [pscustomobject]@{ Usage = "adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [--help-prereqs]"; Summary = "Compatibility guided setup entry" }
        [pscustomobject]@{ Usage = "adpos sandbox <command...> [-Distro <name>] [-IsoPath <path>]"; Summary = "Run a command in a disposable VM" }
        [pscustomobject]@{ Usage = "adpos serve [-Port <port>] [-Public] [-Json]"; Summary = "Start health check HTTP service" }
        [pscustomobject]@{ Usage = "adpos precheck"; Summary = "Scan prerequisites and show status table" }
        [pscustomobject]@{ Usage = "adpos precheck --help-prereqs"; Summary = "Show full prerequisite list with install commands" }
        [pscustomobject]@{ Usage = "adpos uninstall"; Summary = "One-click uninstall of global adpos registration; VMs/workspaces stay untouched" }
        [pscustomobject]@{ Usage = "adpos version"; Summary = "Show version information" }
        [pscustomobject]@{ Usage = "adpos help [command]"; Summary = "Show help or command-specific help" }
    )
}

function Get-ADPCommandHelpLines {
    param([string]$CommandName)

    if ((Get-UILanguage) -eq "zh-CN") {
        switch ($CommandName) {
            "setup" { return @("用法:", "  adpos setup [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand]", "", "说明:", "  一键安装入口。它会执行 precheck、ISO 下载、平台引导、初始化、doctor，并默认注册全局 adpos 命令。", "  首次 clone 后仍可在仓库根目录运行 .\setup.cmd；注册完成后可在任意目录运行 adpos。", "  如果已有全局 adpos 指向其他 checkout，交互模式会询问是否替换；非交互模式会保留现有绑定，除非使用 -Force。", "  如果当前终端还没有刷新 PATH，请打开新终端，或在仓库根目录临时使用 .\adpos.cmd。", "", "示例:", "  .\setup.cmd", "  adpos setup -IsoPath D:\ISOs\ubuntu-26.04-live-server-amd64.iso", "  adpos setup -SkipIsoDownload") }
            "init" { return @("用法:", "  adpos init", "  adpos init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]", "", "参数:", "  <runtime>        运行时名称 (frontend, backend, agent, sandbox)", "  -IsoPath <path>  指定 ISO 路径（跳过缓存查找）", "  -NoProvision     跳过 VM 创建步骤", "  -Quick           跳过平台依赖检查，快速初始化", "", "说明:", "  不带参数时初始化平台依赖；带 <runtime> 参数时额外创建并配置指定运行时。", "", "示例:", "  adpos init", "  adpos init backend -IsoPath D:\ISOs\ubuntu-26.04.iso") }
            "up" { return @("用法:", "  adpos up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]", "", "参数:", "  <runtime>        运行时名称 (frontend, backend, agent, sandbox)", "  -IsoPath <path>  指定 ISO 路径（跳过缓存查找）", "  -Plan            仅显示计划，不执行实际操作", "  -NoProvision     跳过 VM 创建/克隆步骤", "  -NoBootstrap     跳过开机后的 SSH bootstrap 步骤", "", "示例:", "  adpos up frontend", "  adpos up agent -IsoPath D:\ISOs\ubuntu-22.04.iso -NoBootstrap") }
            "run" { return @("用法:", "  adpos run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]", "", "说明:", "  一键执行 init + up + sync start + status。首次 VM 创建通常需要 15-45 分钟，后续热启动约 30 秒。", "", "示例:", "  adpos run frontend", "  adpos run agent -Plan") }
            "status" { return @("用法:", "  adpos status [runtime] [-Json]", "", "参数:", "  <runtime>        运行时名称 (frontend, backend, agent, sandbox)，省略时显示所有运行时", "  -Json            以 JSON 格式输出", "", "示例:", "  adpos status", "  adpos status frontend -Json") }
            "stop" { return @("用法:", "  adpos stop <runtime>", "", "参数:", "  <runtime>        运行时名称 (frontend, backend, agent, sandbox)", "", "示例:", "  adpos stop frontend") }
            "sync" { return @("用法:", "  adpos sync <status|start|stop|list> [runtime]", "", "子命令:", "  status           显示同步会话状态", "  start            启动同步会话", "  stop             停止同步会话", "  list             列出所有同步会话", "", "示例:", "  adpos sync status frontend", "  adpos sync start backend") }
            "workspace" { return @("用法:", "  adpos workspace <command> [-ManifestPath <path>] [-Plan] [-Markdown]", "", "常用子命令:", "  show, plan, status, dashboard, recipes, create, open, sync, project, report", "  task <action> <name> 管理工作区任务；evidence/declare 管理证据链。", "", "选项:", "  -ManifestPath    指定 manifest 文件路径", "  -Plan            仅显示计划", "  -Execute         通过 SSH 在 VM 中执行验证命令（仅 task validate）", "  -Local           本地执行验证命令，无需 VM（仅 task validate）", "  -Markdown        以 Markdown 格式输出", "", "示例:", "  adpos workspace init", "  adpos workspace dashboard -Markdown") }
            "capabilities" { return @("用法:", "  adpos capabilities [-Json]", "", "说明:", "  只读命令，不修改任何 VM、同步会话、快照或主机网络。", "", "示例:", "  adpos capabilities", "  adpos capabilities -Json") }
            "isolate" { return @("用法:", "  adpos isolate [-Plan|-Apply] [-Namespace <name>]", "", "说明:", "  预览或应用第二个 checkout 的本机隔离配置。-Plan 不修改 configs\local.json。", "  -Apply 只写入当前 checkout 被忽略的 configs\local.json；已有文件会先备份为 configs\local.json.bak.<timestamp>。", "  输出或写入建议的 platform.runtime_namespace、workspace_root、vm_store、provider vm_store 和 runtime static_ip。", "  如果全局 adpos 指向其他 checkout，请在当前仓库根目录运行 .\adpos.cmd isolate -Plan。", "", "示例:", "  adpos isolate -Plan", "  .\adpos.cmd isolate -Plan -Namespace v2", "  .\adpos.cmd isolate -Apply -Namespace v2") }
            "network" { return @("用法:", "  adpos network apply <runtime|all> [-Plan]", "  adpos network configure-local [-Plan|-Apply]", "", "说明:", "  apply 将静态 IP 网络配置应用到运行时；runtime 可以是 frontend、backend、agent 或 sandbox；all 会应用到所有已配置运行时。", "  configure-local 预览或写入本机 VMnet8 覆盖配置。", "", "示例:", "  adpos network configure-local -Plan", "  adpos network apply all -Plan") }
            "snapshot" { return @("用法:", "  adpos snapshot create <runtime> <snapshot-name>", "", "示例:", "  adpos snapshot create frontend before-update") }
            "restore" { return @("用法:", "  adpos restore <runtime> <snapshot-name> [-Plan] [-Force]", "", "参数:", "  -Plan            预览将要执行的操作", "  -Force           跳过确认提示，直接恢复", "", "示例:", "  adpos restore frontend before-update -Plan") }
            "logs" { return @("用法:", "  adpos logs <runtime>", "", "示例:", "  adpos logs frontend") }
            "doctor" { return @("用法:", "  adpos doctor [-FirstRun] [-Json]", "  adpos doctor -FixMutagen [-Plan] [-Json]", "", "参数:", "  -FirstRun        首次运行检查模式", "  -FixMutagen      自动修复 Mutagen 配置问题", "  -Plan            预览 Mutagen 修复；仅与 -FixMutagen 一起使用", "  -Json            以 JSON 格式输出", "", "示例:", "  adpos doctor", "  adpos doctor -FixMutagen -Plan", "  adpos doctor -FixMutagen -Json") }
            "validate" { return @("用法:", "  adpos validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]", "", "说明:", "  运行仓库验证测试。-Quick 只运行快速语法/契约检查。", "", "示例:", "  adpos validate", "  adpos validate -Quick") }
            "destroy" { return @("用法:", "  adpos destroy <runtime> [-Plan] [-Force]", "", "警告:", "  此操作不可逆。销毁后 VM 和所有数据将永久丢失。", "", "示例:", "  adpos destroy frontend -Plan") }
            "completion" { return @("用法:", "  adpos completion <powershell|bash>", "", "示例:", "  adpos completion powershell", "  adpos completion bash > ~/.adp-completion.bash") }
            "iso" { return @("用法:", "  adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]", "", "说明:", "  下载受支持的 Linux ISO 到缓存，BITS 传输支持断点续传。", "", "示例:", "  adpos iso", "  adpos iso debian -Force") }
            "quickstart" { return @("用法:", "  adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [--help-prereqs]", "", "说明:", "  兼容入口；新用户优先使用 .\setup.cmd 或 adpos setup。", "  会扫描前提条件、下载 ISO、初始化平台并运行 doctor。默认注册全局 adpos；使用 -NoRegisterCommand 可跳过。", "  如果已有全局 adpos 指向其他 checkout，交互模式会询问是否替换；非交互模式会保留现有绑定，除非使用 -Force。", "", "示例:", "  adpos quickstart", "  adpos quickstart -Force", "  adpos quickstart --help-prereqs") }
            "precheck" { return @("用法:", "  adpos precheck", "  adpos precheck --help-prereqs", "", "说明:", "  扫描系统前提条件并显示状态表；--help-prereqs 输出完整安装说明。", "", "示例:", "  adpos precheck") }
            "sandbox" { return @("用法:", "  adpos sandbox <command...> [-Distro <name>] [-IsoPath <path>]", "", "说明:", "  在一次性 VM 中运行命令，执行后自动销毁。", "", "示例:", "  adpos sandbox echo hello") }
            "serve" { return @("用法:", "  adpos serve [-Port <port>] [-Public] [-Json]", "", "说明:", "  启动轻量 HTTP 健康检查服务；-Json 输出一次性健康报告。", "", "示例:", "  adpos serve", "  adpos serve -Json") }
            "uninstall" { return @("用法:", "  adpos uninstall [-NonInteractive] [-Force]", "", "说明:", "  一键卸载全局 adpos 命令注册。默认安全卸载：只移除属于当前 checkout 的用户 PATH 中 ADP-OS bin 和 adpos.cmd shim。", "  如果全局 adpos 属于另一个 checkout，默认会拒绝卸载；确认要移除该全局绑定时再使用 -Force。", "  不删除 VM、workspace、ISO 缓存、本地工具、日志或仓库文件。如需从仓库根目录卸载，也可运行 .\uninstall.cmd。", "", "示例:", "  adpos uninstall", "  .\uninstall.cmd", "  .\uninstall.cmd -Force") }
            "version" { return @("用法:", "  adpos version", "  adpos --version", "", "说明:", "  显示当前 ADP-OS 版本。") }
            "help" { return @("用法:", "  adpos help", "  adpos help <command>", "  adpos <command> --help", "", "说明:", "  显示命令总览或指定命令的详细帮助。") }
            default { return @("命令 '$CommandName' 没有详细帮助。使用 'adpos help' 查看所有命令。") }
        }
    }

    switch ($CommandName) {
        "setup" { return @("Usage:", "  adpos setup [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand]", "", "Description:", "  One-click install entry. Runs precheck, ISO download, platform bootstrap, init, doctor, and registers the global adpos command by default.", "  Right after cloning, run .\setup.cmd from the repository root. After registration, run adpos from any directory.", "  If global adpos already points to another checkout, interactive setup asks before replacing it; non-interactive setup keeps the existing binding unless -Force is used.", "  If the current terminal has not refreshed PATH yet, open a new terminal or use .\adpos.cmd from the repository root.", "", "Examples:", "  .\setup.cmd", "  adpos setup -IsoPath D:\ISOs\ubuntu-26.04-live-server-amd64.iso", "  adpos setup -SkipIsoDownload") }
        "init" { return @("Usage:", "  adpos init", "  adpos init <runtime> [-IsoPath <path>] [-NoProvision] [-Quick]", "", "Arguments:", "  <runtime>        Runtime name (frontend, backend, agent, sandbox)", "  -IsoPath <path>  Specify ISO path (skip cache lookup)", "  -NoProvision     Skip VM creation step", "  -Quick           Skip platform dependency checks, fast init", "", "Description:", "  Without arguments: initializes platform dependencies. With <runtime>: also creates and configures that runtime.", "", "Examples:", "  adpos init", "  adpos init backend -IsoPath D:\ISOs\ubuntu-22.04.iso") }
        "up" { return @("Usage:", "  adpos up <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]", "", "Arguments:", "  <runtime>        Runtime name (frontend, backend, agent, sandbox)", "  -IsoPath <path>  Specify ISO path (skip cache lookup)", "  -Plan            Plan-only mode; do not start VM", "  -NoProvision     Skip VM creation/clone step", "  -NoBootstrap     Skip post-boot SSH bootstrap step", "", "Examples:", "  adpos up frontend", "  adpos up agent -IsoPath D:\ISOs\ubuntu-22.04.iso -NoBootstrap") }
        "run" { return @("Usage:", "  adpos run <runtime> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]", "", "Description:", "  One-command shortcut: init + up + sync start + status. First VM creation usually takes 15-45 minutes; warm starts are about 30 seconds.", "", "Examples:", "  adpos run frontend", "  adpos run agent -Plan") }
        "status" { return @("Usage:", "  adpos status [runtime] [-Json]", "", "Arguments:", "  <runtime>        Runtime name (frontend, backend, agent, sandbox); omit to show all runtimes", "  -Json            Output in JSON format", "", "Examples:", "  adpos status", "  adpos status frontend -Json") }
        "stop" { return @("Usage:", "  adpos stop <runtime>", "", "Arguments:", "  <runtime>        Runtime name (frontend, backend, agent, sandbox)", "", "Examples:", "  adpos stop frontend") }
        "sync" { return @("Usage:", "  adpos sync <status|start|stop|list> [runtime]", "", "Subcommands:", "  status           Show sync session status", "  start            Start sync session", "  stop             Stop sync session", "  list             List all sync sessions", "", "Examples:", "  adpos sync status frontend", "  adpos sync start backend") }
        "workspace" { return @("Usage:", "  adpos workspace <command> [-ManifestPath <path>] [-Plan] [-Markdown]", "", "Common subcommands:", "  show, plan, status, dashboard, recipes, create, open, sync, project, report", "  task <action> <name> manages workspace tasks; evidence/declare manage the evidence chain.", "", "Options:", "  -ManifestPath    Specify manifest file path", "  -Plan            Show plan only", "  -Execute         Execute validation commands via SSH in VM (task validate only)", "  -Local           Execute validation commands locally, no VM required (task validate only)", "  -Markdown        Output in Markdown format", "", "Examples:", "  adpos workspace init", "  adpos workspace dashboard -Markdown") }
        "capabilities" { return @("Usage:", "  adpos capabilities [-Json]", "", "Description:", "  Read-only. Does not modify VMs, sync sessions, snapshots, or host networking.", "", "Examples:", "  adpos capabilities", "  adpos capabilities -Json") }
        "isolate" { return @("Usage:", "  adpos isolate [-Plan|-Apply] [-Namespace <name>]", "", "Description:", "  Plan or apply local isolation settings for a second checkout. -Plan does not change configs\local.json.", "  -Apply writes only this checkout's ignored configs\local.json; an existing file is backed up as configs\local.json.bak.<timestamp> first.", "  Prints or writes suggested platform.runtime_namespace, workspace_root, vm_store, provider vm_store, and runtime static_ip overrides.", "  If global adpos points to another checkout, run .\adpos.cmd isolate -Plan from this repository root.", "", "Examples:", "  adpos isolate -Plan", "  .\adpos.cmd isolate -Plan -Namespace v2", "  .\adpos.cmd isolate -Apply -Namespace v2") }
        "network" { return @("Usage:", "  adpos network apply <runtime|all> [-Plan]", "  adpos network configure-local [-Plan|-Apply]", "", "Description:", "  apply configures static IP networking on runtimes. Runtime can be frontend, backend, agent, or sandbox; all applies every configured runtime.", "  configure-local plans or writes local VMnet8 overrides.", "", "Examples:", "  adpos network configure-local -Plan", "  adpos network apply all -Plan") }
        "snapshot" { return @("Usage:", "  adpos snapshot create <runtime> <snapshot-name>", "", "Examples:", "  adpos snapshot create frontend before-update") }
        "restore" { return @("Usage:", "  adpos restore <runtime> <snapshot-name> [-Plan] [-Force]", "", "Arguments:", "  -Plan            Show what would be restored", "  -Force           Skip confirmation prompt", "", "Examples:", "  adpos restore frontend before-update -Plan") }
        "logs" { return @("Usage:", "  adpos logs <runtime>", "", "Examples:", "  adpos logs frontend") }
        "doctor" { return @("Usage:", "  adpos doctor [-FirstRun] [-Json]", "  adpos doctor -FixMutagen [-Plan] [-Json]", "", "Arguments:", "  -FirstRun        First-run check mode", "  -FixMutagen      Auto-fix Mutagen configuration issues", "  -Plan            Preview Mutagen remediation; only valid with -FixMutagen", "  -Json            Output in JSON format", "", "Examples:", "  adpos doctor", "  adpos doctor -FixMutagen -Plan", "  adpos doctor -FixMutagen -Json") }
        "validate" { return @("Usage:", "  adpos validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]", "", "Description:", "  Run repository validation tests. -Quick runs syntax and contract checks only.", "", "Examples:", "  adpos validate", "  adpos validate -Quick") }
        "destroy" { return @("Usage:", "  adpos destroy <runtime> [-Plan] [-Force]", "", "Warning:", "  This operation is irreversible. The VM and all data will be permanently lost.", "", "Examples:", "  adpos destroy frontend -Plan") }
        "completion" { return @("Usage:", "  adpos completion <powershell|bash>", "", "Examples:", "  adpos completion powershell", "  adpos completion bash > ~/.adp-completion.bash") }
        "iso" { return @("Usage:", "  adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force]", "", "Description:", "  Download a supported Linux ISO to cache. BITS transfer supports resume.", "", "Examples:", "  adpos iso", "  adpos iso debian -Force") }
        "quickstart" { return @("Usage:", "  adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [--help-prereqs]", "", "Description:", "  Compatibility entry; new users should prefer .\setup.cmd or adpos setup.", "  Scans prerequisites, downloads ISO, initializes the platform, and runs doctor. Registers global adpos by default; use -NoRegisterCommand to skip.", "  If global adpos already points to another checkout, interactive setup asks before replacing it; non-interactive setup keeps the existing binding unless -Force is used.", "", "Examples:", "  adpos quickstart", "  adpos quickstart -Force", "  adpos quickstart --help-prereqs") }
        "precheck" { return @("Usage:", "  adpos precheck", "  adpos precheck --help-prereqs", "", "Description:", "  Scan system prerequisites and show a status table. --help-prereqs prints full install guidance.", "", "Examples:", "  adpos precheck") }
        "sandbox" { return @("Usage:", "  adpos sandbox <command...> [-Distro <name>] [-IsoPath <path>]", "", "Description:", "  Run a command in a disposable VM and auto-destroy it afterward.", "", "Examples:", "  adpos sandbox echo hello") }
        "serve" { return @("Usage:", "  adpos serve [-Port <port>] [-Public] [-Json]", "", "Description:", "  Start a lightweight HTTP health check service. -Json outputs a one-shot health report.", "", "Examples:", "  adpos serve", "  adpos serve -Json") }
        "uninstall" { return @("Usage:", "  adpos uninstall [-NonInteractive] [-Force]", "", "Description:", "  One-click uninstall of the global adpos command registration. Safe default: removes only the ADP-OS user PATH bin and adpos.cmd shim owned by the current checkout.", "  If global adpos belongs to another checkout, uninstall refuses by default; use -Force only when you intend to remove that global binding.", "  It does not delete VMs, workspaces, ISO cache, local tools, logs, or repository files. From the repository root, .\uninstall.cmd does the same thing.", "", "Examples:", "  adpos uninstall", "  .\uninstall.cmd", "  .\uninstall.cmd -Force") }
        "version" { return @("Usage:", "  adpos version", "  adpos --version", "", "Description:", "  Show the current ADP-OS version.") }
        "help" { return @("Usage:", "  adpos help", "  adpos help <command>", "  adpos <command> --help", "", "Description:", "  Show the command overview or detailed help for one command.") }
        default { return @("Command '$CommandName' has no detailed help. Use 'adpos help' for all commands.") }
    }
}

function Write-ADPHelpLines {
    param([string[]]$Lines)

    foreach ($line in $Lines) {
        if ($line -match '^[^ ].+:$') {
            Write-Host $line -ForegroundColor Yellow
        } else {
            Write-Host $line
        }
    }
}

function Write-ADPHelpCommandRow {
    param(
        [string]$Usage,
        [string]$Summary
    )

    $usageWidth = 86
    if ($Usage.Length -le $usageWidth) {
        Write-Host ("  {0,-86} {1}" -f $Usage, $Summary)
        return
    }

    Write-Host "  $Usage"
    Write-Host ("  {0,-86} {1}" -f "", $Summary)
}

function Show-Help {
    param([string]$CommandName)

    if ($CommandName) {
        Show-CommandHelp -CommandName $CommandName
        return
    }

    Write-Host ""
    Write-Host "ADP-OS CLI - AI Development Platform OS" -ForegroundColor Cyan
    Write-Host ""

    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "命令:" -ForegroundColor Yellow
    } else {
        Write-Host "Commands:" -ForegroundColor Yellow
    }

    foreach ($row in (Get-ADPTopLevelCommandRows)) {
        Write-ADPHelpCommandRow -Usage $row.Usage -Summary $row.Summary
    }

    Write-Host ""
    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "全局选项:" -ForegroundColor Yellow
        Write-Host "  -Json                          以 JSON 格式输出 (支持: status, doctor, capabilities, serve)"
        Write-Host "  --help, --version              显示帮助或版本信息"
        Write-Host ""
        Write-Host "使用 'adpos help <command>' 或 'adpos <command> --help' 查看特定命令的详细帮助。" -ForegroundColor DarkGray
    } else {
        Write-Host "Global options:" -ForegroundColor Yellow
        Write-Host "  -Json                          Output in JSON format (supported: status, doctor, capabilities, serve)"
        Write-Host "  --help, --version              Show help or version information"
        Write-Host ""
        Write-Host "Use 'adpos help <command>' or 'adpos <command> --help' for detailed per-command help." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-CommandHelp {
    param([string]$CommandName)

    Write-Host ""
    Write-Host "ADP-OS: adpos $CommandName" -ForegroundColor Cyan
    Write-Host ""
    Write-ADPHelpLines -Lines (Get-ADPCommandHelpLines -CommandName $CommandName)
    Write-Host ""
}

function Show-Version {
    $versionFile = Join-Path $script:ProjectRoot "VERSION"
    if (Test-Path $versionFile) {
        $version = (Get-Content $versionFile -Raw).Trim()
        Write-Host "ADP-OS version $version"
        return
    }

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
