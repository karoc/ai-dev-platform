# 变更日志

简体中文 | [English](CHANGELOG.md)

这里记录 AI Dev Platform OS 的重要公开变更。

版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)（`MAJOR.MINOR.PATCH`）。变更按发布版本分组，版本内按日期排列。最新版本在最上方。

注意：自 2026-06-08 起，面向用户的 shell 命令为 `adpos`。较早条目可能因历史准确性提到已退役的 `adp` shell 命令；当前操作请使用 `adpos`。

## [v1.0.0] — 2026-06-04

首次公开发布。

### 2026-06-09

### 新增

- 在 survival demo 路径中新增仅公开材料录制和现场演示核对护栏，覆盖公开 artifact 边界、隐私复查、evidence ZIP 检查、sync fence，以及发布或外联前必须获得 maintainer 批准的边界。

### 修复

- 修正 release 和 security 文档，明确项目已有 `v1.0.0` 公开 release，同时保持安全修复以最新 `main` 分支为准，除非未来引入正式的 release 维护策略。
- 修正 `adpos status [-Json]` 与 `validation_failed` task lifecycle state 的公开命令参考，使 README 和 workspace 文档与 survival demo 脚本及 CLI contract 保持一致。
- 将 GitHub Actions workflows 固定到显式 `windows-2025-vs2026` runner image，并升级 checkout 到 `actions/checkout@v6`，避免即将到来的 `windows-latest` 与 Node 20 action runtime 漂移。

### 2026-06-08

### 新增

- 新增 `adpos` 作为唯一面向用户的 shell 命令。`setup.cmd` / `setup.ps1` 现在默认会在 `%LOCALAPPDATA%\ADP-OS\bin` 下注册用户级 `adpos` shim，并且只把该 bin 目录加入用户 `PATH`。
- 新增一键安全卸载入口：`adpos uninstall` 以及仓库根目录的 `uninstall.cmd` wrapper。默认卸载只移除全局 `adpos` 命令注册，不删除 VM、workspace、ISO 缓存、本地工具、日志或仓库文件。
- 改进 stock Windows shell 的一键 bootstrap 行为。缺少 `pwsh.exe` 时，`setup.cmd`、`setup.ps1` 和 `install.ps1` 现在会尝试用 `winget` 安装 PowerShell 7，然后继续用 PowerShell 7 执行 setup。PowerShell 7 不可用时，`uninstall.cmd` 也可以通过 Windows PowerShell 5.1 移除命令注册。
- 新增 `adpos isolate -Plan [-Namespace <name>]`，用于预览多 checkout 的本机隔离覆盖配置，并且不会修改 `configs\local.json`、VM、SSH alias、sync session、`PATH` 或全局 `adpos` 绑定。
- 新增 `adpos isolate -Apply [-Namespace <name>]`，可安全地把预览出的 checkout 隔离覆盖配置写入当前 checkout 被忽略的 `configs\local.json`，保留无关本机字段，并在已有文件时先创建备份。

### 变更

- 移除仓库根目录的 `adp.cmd` 兼容 wrapper，并停止在 shell completion 中暴露 `adp` / `adp.cmd`。公开文档、PR 模板、部署提示和扩展文档现在统一使用 `adpos` 或仓库本地 `.\adpos.cmd`。
- setup 现在会通过 `ADPOS_HOME`、用户/系统 `PATH` 和生成的 shim 检测已有全局 `adpos` 绑定。交互模式发现其他 checkout 时会询问是否替换；非交互模式会保留现有绑定，除非使用 `-Force`，并提示当前 checkout 使用 `.\adpos.cmd`，同时列出在该 checkout 运行 VM 前需要配置的本地隔离项和验收命令。

### 修复

- 将首批用户支持和反馈入口对齐到当前公开状态。README badge 和社区区块现在指向 GitHub Issues，issue 模板统一使用正式 `adpos` 命令，Discord 被标注为搭建计划而非当前可用支持渠道，GitHub Discussions 在实际启用前不再作为已上线入口展示。

- 加固 survival demo 路径中的 restore 后 runtime readiness 检查。ADP 管理的 SSH 探测现在使用有界进程 timeout，将 `ssh-timeout` 与 `auth-pending`、`unreachable` 分开分类，readiness 检查不依赖 direct OpenSSH 的 stale known-hosts 状态，并让 VMware 控制操作保持有界，避免 `status`、`up -NoBootstrap` 和 `stop` 在 restore 后 half-ready VM 上表现为无限等待。

- 修复 `adpos workspace evidence -Snapshot` 和 `adpos workspace evidence -Export -Path <zip>` 在 `-ManifestPath` 指向已存在 manifest 时失败的问题。workspace evidence 代码现在会显式调用 PowerShell 内置的 `Resolve-Path` 处理文件系统路径，ZIP 输入/输出使用 provider 文件系统路径，并为导出绑定文档承诺的 `-Path` 别名，避免 survival demo 记录证据时出现路径解析器或 provider-qualified 路径错误。

### 2026-06-05

### 新增

- 在 README（英文和简体中文）中添加 Discord 社区 badge，链接至搭建指南，并更新 Discord 搭建指南增加服务器创建的快速参考检查清单。badge 和邀请基础设施已就绪 — Discord 服务器链接为占位符，待服务器创建后更新。

- 添加同步恢复诊断，覆盖 dogfooding 暴露的三类边界情况：Mutagen 单边 root 清空保护、跨 clone 的全局同名 stale session、运行前 stale session 清理。`adapters/windows/mutagen/mutagen.ps1` 中新增 `Get-SyncSessionRecoveryInfo`，对同步恢复场景进行结构化分类并提供恢复步骤。`adp status`、`adp doctor` 和 `adp sync status` 现在能检测并标注具体恢复场景（root-emptying、stale-before-creation、wrong-local-endpoint、wrong-remote-endpoint、unhealthy-session），双语诊断输出包含场景标题、详情描述、编号恢复步骤和显式安全提示。双语义档（`docs/troubleshooting.md`、`docs/zh-CN/troubleshooting.md`）新增「跨 Clone 的 Stale Session」和「运行时创建前的 Stale Session 清理」恢复章节，含诊断命令和恢复路径。root-emptying 检测现在显式识别该条件，而非报告泛型 `unhealthy`。

- 添加社区基础设施：安装帮助 issue 模板（`.github/ISSUE_TEMPLATE/install_help.yml`）、增强的 CONTRIBUTING.zh-CN.md（含分步开发环境搭建和 PR 流程）、Discord 社区搭建指南（`docs/discord-setup.md`、`docs/zh-CN/discord-setup.md`，含频道结构和社区准则）、演示视频脚本与分镜（`docs/demo-script.md`）。在 README 和双语文档索引中添加了「社区」板块。

- 新增 `setup.ps1` — 根目录级别的一键引导脚本，将前提条件扫描、ISO 下载、平台安装、初始化和诊断整合为一条命令。克隆后，用户只需运行 `.\setup.ps1`（无需 `.\cli\adp.ps1 quickstart`）即可获得更简单的首次运行体验。支持 `-IsoPath`、`-SkipIsoDownload`、`-NonInteractive` 和 `-Force` 标志。更新了 README（英文和简体中文）、入门指南和 CLI smoke 测试。

### 2026-06-04

### 新增

- 新增 Copilot SDK 集成指南（`docs/zh-CN/copilot-sdk-integration.md` 简体中文，同时提供英文版）。文档说明如何在 GitHub Copilot Agent SDK session 中加载 ADP-OS 作为 MCP 服务器。包含 Python 和 TypeScript 快速开始示例、环境变量参考、18 工具目录、plan-only 安全默认值和权限处理器模式。（Copilot SDK 原生兼容，ADP-OS 无需任何代码修改。）
- 新增熔断器模块 (`core/utility/circuit-breaker.ps1`)，提供 `New-CircuitBreaker`、`Test-CircuitBreaker`、`Reset-CircuitBreaker` 和 `Get-CircuitBreakerSummary` 函数。追踪连续相同的错误键，当同一错误重复 MaxConsecutiveErrors 次后断开熔断——防止长时间运行操作中的无限重试循环。
- 新增熔断器集成到 `Wait-AutoinstallComplete`（`runtimes/vmware/vm-factory.ps1`）。在 Ubuntu 自动安装期间监控就绪信号类别（`no-guest-ip`、`auth-pending`、`ssh-not-ready`、`provision-not-ready` 等）。当同一错误类别持续超过可配置阈值（`-AutoinstallCircuitBreakerMinutes`，默认 20 分钟）时，熔断器断开：停止重试、发出双语警告，并返回以允许操作者排查。防止 agent 在 VM 安装卡住时无限循环。
- 在操作指南和故障排除文档中添加了 SSH 密钥生命周期文档（英文和简体中文）。新文档涵盖密钥位置（`%USERPROFILE%\\.ssh\\adp-os\\`）、密钥格式（ed25519，无密码）、首次自动创建、带备份和 VM 影响警告的密钥重新生成、密钥安全、直接 SSH/scp 用法，以及 `key-missing`、`auth-pending`、`Permission denied`、`bad permissions`、密钥删除和多用户环境的故障排除。（Phase 2 roadmap 项目。）
- 新增 `adp validate` 命令，作为共享仓库验证套件的独立 CLI 入口。支持 `-Quick`、`-SkipCliSmoke`、`-SkipInstallerSmoke` 和 `-SkipShellSyntax` 标志，提供双语输出。（Phase 2 roadmap 项目。）
- 新增 `adp doctor` 剩余用户界面诊断输出的本地化：网络漂移修复选项、VMware/xorriso 指导、Mutagen 修复计划和安装详情、重复 VM 警告、stale session 清理指导以及问题列表。现在所有 `adp doctor` 输出路径的英文和简体中文文本保持一致。
- 本地化 `adp workspace report`、`adp workspace recipes` 和所有工作区报告子部分（发布交接摘要、治理循环、决策队列、里程碑检查点、里程碑审查汇总、验证执行队列、评估队列、发布决策策略、陈旧任务修复和每个任务的报告包），使用 Write-UIHost 提供双语输出。章节标题、字段标签、边界声明、检查清单项目和交接命令现在响应 `ADP_LANG=zh-CN`。
- 新增 `adp status`（ssh、running VMX、sync、VMX、connect、alias）和 `adp up` 连接摘要（IP、SSH、Alias、Workspace、Sync、Status、Doctor、CPU/RAM/Disk、VMX、ISO）中剩余用户界面数据标签的本地化。所有 CLI 输出标签现在均遵循配置的 UI 语言偏好。
- 新增 `adp network` 剩余用户界面输出的本地化：seed 网络漂移检测消息、guest netplan 原地修复指导、重建/host route 变通方案、plan-preview 操作步骤（验证 SSH、上传、安装、等待、更新 Mutagen 别名）以及静态 IP 激活成功消息。现在 `network apply` plan-only 输出和 `network configure-local` 路径的英文和简体中文文本保持一致。
- 开始 `adp workspace` 入口命令的双语本地化。调度部分和五个入口命令界面现使用 `Write-UIHost` 进行一致的语言选择：`workspace show`/`plan`（Write-WorkspaceSummary）、`workspace create`（Write-WorkspaceCreate）、`workspace open`（Write-WorkspaceOpen）和 `workspace sync`（Write-WorkspaceSyncGuide）。共享的 `Write-WorkspaceCheck` helper 现已支持双语输出，可选择性传入 `-ChineseName` 和 `-ChineseDetail` 参数。
- 继续 `adp workspace` 双语本地化，完成 `workspace status`（Write-WorkspaceStatus），涵盖清单信息、项目就绪状态、里程碑、评估和任务生命周期字段。所有面向用户的标签、区块标题和检查项名称现在均遵循配置的 UI 语言偏好。其余 workspace 界面（dashboard、report、recipes、project、task lifecycle）将在后续批次跟随。
- 继续 `adp workspace` 双语本地化，完成 `workspace dashboard`（Write-WorkspaceDashboard），涵盖区块标题（概览、项目就绪状态、里程碑检查点、评估钩子、任务生命周期）、检查项名称（清单、状态、项目、里程碑、评估、任务）、空状态消息以及任务生命周期命令提示（准备、运行、审查）。所有仪表盘输出现在均遵循配置的 UI 语言偏好。其余 workspace 界面（report、recipes、project、task lifecycle）将在后续批次跟随。
- 完成 `workspace.ps1` 中所有剩余 Write-Host 调用的双语本地化：用法/帮助示例（Show-WorkspaceUsage）、审查/提交决策下一步提示行（Write-WorkspaceReviewDecision、Write-WorkspaceCommitDecision）、验证详情行（Write-WorkspaceValidationDetailLines）、检查点标题（Write-WorkspaceTaskSnapshot），以及所有任务标记边界消息和状态显示（Write-WorkspaceTaskMark）。现在所有 `adp workspace` 面向用户的输出均使用 `Write-UIHost`，支持英文和简体中文（共 521 处 Write-UIHost 调用，Write-Host 已清零）。
- 新增 ADP-OS MCP (Model Context Protocol) 服务器，位于 `cli/mcp/server.py`。暴露 11 个 MCP 工具用于 agent-native 沙箱编排：`adp_status`、`adp_doctor`、`adp_workspace_list`、`adp_workspace_create`、`adp_workspace_open`、`adp_workspace_sync`、`adp_workspace_status`、`adp_workspace_recipes`、`adp_sync_status`、`adp_sync_stop` 和 `adp_capabilities`。服务器通过 `pwsh.exe` 子进程调用 ADP-OS PowerShell CLI，使用 FastMCP 通过 stdio 通信。包含 `README.md`，提供针对 Claude Desktop 等 MCP 客户端的安装和配置指南。
- 将 MCP 服务器从 11 个工具扩展到 18 个，新增运行时管理、工作空间生命周期和关闭支持。新工具：`adp_up`（启动 VM，默认 plan-only）、`adp_down`（销毁 VM，默认 plan-only）、`adp_stop`（优雅关闭）、`adp_workspace_close`（停止项目运行时的同步，默认 plan-only）、`adp_workspace_project`（单项目生命周期视图）、`adp_workspace_dashboard`（任务生命周期概览）和 `adp_workspace_report`（Markdown 发布证据）。更新 `README.md`，添加 Claude Desktop 安装说明和故障排除指南。
- 新增 MCP 服务器测试套件 `tests/test-mcp-server.py`，包含 14 个测试：模块导入、工具注册（验证 18 个工具）、输出格式化（成功/stderr/失败/空/超时）、清单加载、项目到运行时解析、路径解析、pwsh 检测和工具签名默认值验证。
- 新增 MCP 服务器 JSON 结构化输出。所有 18 个工具现在返回结构化字典（包含 `_text`、`_exit_code`、`_success` 元数据字段），取代纯文本字符串。平台工具（`adp_status`、`adp_doctor`、`adp_capabilities`）和工作空间/运行时工具（`adp_workspace_list`、`adp_sync_status`）输出包含命令特定的解析字段，便于 Agent 程序化消费。新增 9 个结构化输出和解析测试（共 23 个）。更新 `cli/mcp/README.md` 记录结构化响应格式。
- 新增 `--help` 长选项支持到所有子命令。`adp --help`、`adp help` 和 `adp <command> --help` 均可正常使用（也支持 `-Help` 和 `-?` 短形式）。
- 新增 `adp version` 命令和 `--version` 全局标志。从 `VERSION` 文件读取版本号（dev 版本回退到 `git describe`）。
- 新增项目根目录 `adp.cmd` 包装脚本，用户可直接输入 `adp <command>` 而非 `.\\cli\\adp.ps1 <command>`。
- 新增 `adp serve` 健康检查 HTTP 服务器 (`cli/commands/serve.ps1`)。使用 .NET HttpListener 启动轻量级 HTTP 服务器，暴露 `GET /health` 端点，返回 JSON 格式的运行时状态和同步健康信息。支持 `-Port`（默认 9080）、`-Public`（监听所有网络接口）和 `-Json`（一次性健康报告，不启动服务器）。健康端点报告 VM 状态（running/stopped/not-created）、同步会话健康（healthy/present/unhealthy/not-started）和平台整体健康状态（healthy/degraded/unhealthy/no-runtimes）。包含 CORS 头部支持跨域监控访问。

### 变更

- 统一标志命名：`adp init -SkipProvision` 重命名为 `-NoProvision`，与 `adp up -NoProvision` 保持一致。更新了 CLI 帮助、README、文档和测试中的所有引用。不向后兼容，但提升了系统一致性。

### 修复

- 修复 `install.ps1`、`cli/commands/doctor.ps1` 和 `runtimes/vmware/vm-factory.ps1` 中 `Test-WSLCommand` 的 PowerShell 管道泄漏问题：`wsl.exe` shim 的 stdout 泄漏到函数返回值中，将布尔结果污染为 `Object[]`，导致 CI 中报 `Cannot convert value "System.Object[]" to type "System.Boolean"` 错误。修复方法是通过 `$null = &` 捕获外部命令输出，防止管道污染。
- 加固测试基础设施：`local-config-boundary.ps1`、`cli-smoke.ps1` 和 `install-smoke.ps1` 中的 `Start-Process` 现在从当前进程解析 pwsh 完整路径，而非依赖 PATH 中的裸 `pwsh` 命令，避免在某些 CI runner 实例上失败。

### 2026-05-31

### 变更

- 将 runtime profile 文案集中到共享配置 helper，并新增明确的 `topology.<runtime>.profile` 字段。agent runtime 现在会在启动和 installer 输出中显示为 `agent/high-IO` / `Agent 高 IO`，不再使用已退役的 danger/high-risk runtime 标签；snapshot-first 语义仍保留给破坏性或大范围 task 工作。
- 将 agent bootstrap marker 从已退役的 danger-mode 文案更新为 `AGENT_PROFILE.txt`，并新增回归检查，防止当前 installer、startup 和 bootstrap 路径重新引入退役的 runtime danger 标签。
- 修复 autoinstall ISO 重制阶段传递 WSL `xorriso` 参数的问题。`adp up <runtime>` 不再以可能只传入裸 `xorriso` 命令的方式调用 WSL，从而避免打印 usage 而没有创建 autoinstall ISO。
- 将 `adp up <runtime>` 使用的嵌套 VMware VM factory autoinstall monitor 一并本地化。简体中文 UI 现在会一路传递到长时间的 Ubuntu 安装等待，而不会在 VM factory 内回退成英文心跳；同时引入 PowerShell `Write-Progress` 的不确定活动指示，继续保留可复制日志，并明确不伪造安装百分比。

### 2026-05-30

### 新增

- 新增第一批运行时本地化基础能力：`platform.ui.language` 默认英文，被忽略的 `configs\local.json` 可以把本机设置为 `zh-CN`，`ADP_LANG=zh-CN` 可以在不编辑文件的情况下临时切换单次 CLI 调用。首批简体中文覆盖 `adp help`、未知命令输出和保留命令输出。
- 新增由 CI 执行的本地配置边界检查，用于证明 first-run diagnostics、preview commands、failure diagnostics 和裸 `network configure-local` 不会在没有显式 `-Apply` 的情况下修改用户拥有的 `configs\local.json`，也不会创建 local config 备份。
- 新增 `adp network configure-local [-Plan|-Apply]`，用于在创建 VM 前把被忽略的 `configs\local.json` 对齐到探测到的 host `VMnet8` NAT subnet。默认模式和 `-Plan` 都不会修改文件，会显示探测到的 host CIDR、目标 gateway/DNS、推导出的 runtime static IP，以及字段级 local config 变更。只有显式 `-Apply` 才会写入本机 override，并会把已有 `configs\local.json` 备份为 `configs\local.json.bak.<timestamp>`。`adp up` 和 `adp doctor` 现在会在 VMware NAT mismatch 阻断首次 VM 创建时给出两条修复路径：将 ADP 本机 override 对齐到 host `VMnet8`，或保留 ADP 配置的 subnet 并修改 VMware `VMnet8`。
- 新增显式的本地 `checkpoint-waived` workspace task state，让高风险 task 可以在被忽略的本地 state 中记录人类已接受缺少 VM snapshot 保护的风险。Waived checkpoint 会显示在 `workspace status`、`workspace dashboard`、`workspace project`、`workspace report`、`workspace task review`、`workspace task rollback` 和 `workspace task commit` 中；它会解除 snapshot-first gate 的阻塞，但不会伪装成已有 VM snapshot，并且在没有确认 checkpoint 时 rollback 输出不会打印 VM restore 命令。
- 在 `workspace report` 和 `workspace report -Markdown` 中新增 milestone review rollup，用于汇总每个 milestone 的 actions、release states、blockers、validation-required tasks、review-required tasks、ready-to-commit tasks、owners 和 due attention；不会运行 validation，也不会修改 runtime state。
- 在 `workspace report` 和 `workspace report -Markdown` 中新增非破坏性的 validation execution queue，用于显示每个 task 的 recorded validation state、command count、readiness、blockers、plan command、`-Execute -Plan` preview command 和显式 `-Execute` command；不会运行 validation。
- 新增 plan-only `evaluations[]` workspace hooks，并在 `workspace status`、`workspace dashboard`、`workspace report` 和 `workspace report -Markdown` 中显示 evaluation queue，让 agent-native review metrics 和声明式 evaluation commands 可以进入 release evidence，但不会执行 evaluation commands。
- 新增非破坏性的 `workspace recipes` 输出，用于汇总 manifest 中的 project recipes、task recipes、milestone checkpoints、evaluation hooks 和 evidence commands；不会 clone project、打开 SSH、启动 sync、创建快照、运行 validation、运行 evaluation commands、运行 Git 或修改文件。
- 新增 `workspace create [-Plan]`，用于 manifest 声明的本地项目目录。`-Plan` 只预览目录创建；实际执行只会创建缺失的本地目录，不会 clone project、启动 sync、启动 runtime、打开 SSH、创建快照、运行 validation、运行 evaluation commands、运行 Git 或修改已有项目文件。
- 新增非破坏性的 `adp capabilities` 输出和双语 capabilities 文档，用于区分已支持的 Windows VMware 行为，以及计划中的 Hyper-V、KVM、macOS、Linux 和 container-backed runtime 工作。
- 收紧首次 autoinstall monitor 心跳输出，使每条重复心跳都先显示 plain `[install monitor] INSTALLING Ubuntu in VM` 标题，再显示 `progress=indeterminate`、`user-action=keep-open`、`diagnostics=vmware-console-after-20min`、已用/剩余时间、下一次检查提示和 readiness signals，让日志尾部明确表现为正在 watched installation，而不是卡在 IP 或 SSH probe。

### 变更

- 修复 `install.ps1` 未使用 CLI 同一套 `platform.ui.language` / `ADP_LANG` 语言偏好的问题。Phase 1 banner 现在会在加载本地配置后打印，主要 installer 阶段、ISO 提示、依赖摘要和下一步输出已有第一批简体中文覆盖。
- 扩展全新部署主路径的简体中文 CLI 覆盖。`adp init`、`adp doctor -FirstRun`、`adp doctor -FixMutagen -Plan`、`adp up <runtime> -Plan`、主要 `adp up <runtime>` 用户提示、`adp status [runtime]` 和 `adp network configure-local [-Plan|-Apply]` 现在会本地化主要标题、非修改边界、修复选择和下一步指引，同时保持命令名和机器可读状态值稳定。
- 改进已有 Mutagen session 的 sync 诊断：`sync status` 现在会在原始 Mutagen 列表前显示 ADP runtime summary，`status` 会报告 unhealthy 或 endpoint 不匹配的 session，`doctor` 会把已创建 runtime 的不可用 session 作为 issue，`sync start <runtime>` 不再把同名 stale 或 halted session 当作成功。如果 stale session 对应的 runtime 尚未在当前 checkout 创建，ADP 现在会把它显示为 cleanup guidance，而不是当前平台健康失败。
- 改进受限网络中的 Mutagen first-run 修复：`platform.tools.mutagen` 现在支持配置 download URL、显式 local archive path、可选 SHA256 archive verification，以及可配置 download timeouts。`doctor -FixMutagen -Plan` 会在任何下载或解压前显示这些输入，offline archive 仍然只保留在被忽略的 `.tools\mutagen` 下。
- 在 autoinstall ISO remaster 阶段捕获 `xorriso` 输出，避免成功的 `adp up` 在 runtime-ready summary 之后被延迟的 ISO 工具日志污染；失败时仍会包含捕获到的工具细节。
- 改进 `adp doctor -FixMutagen` 的 first-run 修复输出，安装时会显示明确阶段、下载 source/target、连接和 hard timeout、受控终止下载进程、临时 archive 下载、复用已有 archive、archive 无效时重新下载、干净的失败输出，以及下载失败时的手动恢复指引。
- 扩充默认 frontend、backend 和 agent sync profile ignore 列表，覆盖常见依赖目录、构建输出、框架缓存、浏览器测试输出、Python virtual environments、Python caches，以及本地 ADP/Codex 工具状态，降低用户自定义 profile 前同步生成物的概率。
- 澄清 ADP-OS 的 first-run dogfooding 指南：一个最小的 POSIX shell 项目就足以端到端验证 workspace lifecycle。公开的 workspaces 文档现在会提示维护者先从一个足够小、能够被 sync、验证、review 和 commit 的项目开始，而不需要先下载浏览器或安装额外 packages。

### 2026-05-29

### 新增

- 新增更清晰的首次 autoinstall 进度输出，明确说明当前是 watched OS installation，并用 indeterminate install-monitor 心跳显示 `state=installing`、`activity=installing-ubuntu`、`status=watching`、`current-op=readiness-check`、`wait-mode=watched`、预期耗时、timeout、已用时间、剩余 timeout 时间、已观察到的 readiness signals、重复信号 `normal=yes` 含义、可见 installing 状态说明、IP/SSH probes 属于 readiness signals、下一次 readiness check、用户操作提示和预期状态转换；当 SSH 已打开但安装后系统的用户/key 尚未 ready 时明确显示 `auth-pending`。
- 新增非破坏性的 workspace sync hygiene 检查，`workspace show`、`workspace status`、`workspace dashboard` 和 `workspace report` 会在用户开始重同步工作流前，报告常见生成目录是否已被 runtime sync profile 覆盖。`workspace report` 现在会把 sync hygiene 纳入 release evidence，并在 task project 需要 `review ignore` 时阻止 release-candidate 决策。
- 新增非破坏性的 `workspace open [project-name]` 输出，可把 manifest project 解析成 local/remote path、readiness state，以及可复制的本地、编辑器、SSH、sync 和 status 命令；不会打开 shell、编辑器、SSH session、runtime、sync session 或文件。
- 新增非破坏性的 `workspace sync [project-name]` 输出，可把 manifest project 映射回 runtime-level Mutagen session，报告 sync readiness 和 sync hygiene，并打印需要显式执行的 `adp sync` 命令；不会启动或停止 sync。
- 新增非破坏性的 `workspace project [project-name]` 输出，可汇总单个 manifest project 的 operational lifecycle，包括 open、runtime、sync、validation、linked tasks、snapshot gates、recorded validation、commit readiness 和 release evidence handoff。
- 新增可选的 `milestones[]` workspace manifest planning，用于表达成组 checkpoint 意图。`workspace show`、`workspace plan`、`workspace status`、`workspace dashboard`、`workspace project` 和 `workspace report` 现在会显示 milestone checkpoint status、milestone snapshot naming、linked tasks 和 release-evidence queues；不会创建快照或修改 runtime state。
- 新增将 sync hygiene 纳入 `workspace report` 维护者 checklist 和 release-readiness 文档，确保 release evidence、release decision 和维护者 review 都把 sync hygiene 视为同一个 gate。
- 新增将 sync hygiene gate 纳入 `workspace task review` 和 `workspace task commit`，避免单 task review 或 commit guidance 在 report 会因 `review sync ignore` 阻塞时仍接受任务或打印 Git commit 命令。
- 新增非阻塞的 workspace snapshot naming convention 检查。`workspace status`、`workspace dashboard`、`workspace report`、`workspace plan` 和 `workspace task snapshot` 现在会显示 `tasks[].snapshot` 是否表达 task 或 milestone 意图，并推荐 task checkpoint 使用 `before-<task-name>`，更大的 checkpoint 使用 `milestone-<name>`。
- 新增更严格的 review acceptance 边界：`workspace task review` 只有在 review decision gate OK 时才会显示 `task mark <task> reviewed` 命令。
- 更新 `workspace dashboard` 的 task commit state，使其使用与 `workspace task commit` 相同的 sync hygiene、snapshot、validation 和 review gate。
- 新增更明确的 workspace task 执行、review handoff、rollback、commit 和本地状态边界输出，避免 `workspace task run`、`workspace task review`、`workspace task rollback`、`workspace task commit` 和 `workspace task mark` 被误解为已经执行 agent、产生 validation evidence、完成 review approval、达到 rollback readiness、达到 commit readiness，或已经完成 Git/restore 操作。
- 新增 duplicate running ADP runtime 诊断，`status` 和 `doctor` 可以在用户排查 SSH 或网络前，提示来自另一个 checkout 或 stale VM store 的同名 runtime VMX path。
- 新增 stale-networking guided remediation 输出，明确区分 rebuild、in-place guest netplan 和 administrator-only host-route workaround 路径，并且不会自动应用 host routes。
- 新增 VMware NAT host-match 诊断，`doctor` 会在可探测时比对配置的 NAT 设置和 host `VMnet8` 网络。
- 新增已有 runtime 的 seed network drift 诊断，`status` 和 `doctor` 可以报告某个 VM 是否是用比当前合并配置更旧的 autoinstall static IP 创建的。
- 新增 `tests\validate.ps1`，作为 CI 和本地贡献者共用的非破坏性仓库验证入口，并提供 `-Quick` 与定向 skip 开关用于本地迭代。
- 新增由 CI 执行的翻译文档成对检查，覆盖根目录公开文档和 `docs/zh-CN`，避免英文和简体中文文档在文件层面漂移。
- 新增由 CI 执行的 artifact hygiene 检查，覆盖被忽略的本地 assistant 设置、下载工具、日志、snapshot state、workspace state、VM artifacts、ISO files、浏览器测试 artifacts 和 Windows special files。
- 新增由 CI 执行的 issue-template 检查，确保 support routing、security links、usage questions 和公开 safety prompts 持续存在。
- 新增由 CI 执行的 Markdown anchor 验证，确保带 `#anchors` 的本地文档链接在目标 heading 缺失时会失败。
- 新增双语 release process 文档，覆盖 validation、evidence、safety checks、commit 和 publication boundaries。
- 新增双语 release readiness 文档，覆盖 release decision policy、stale-task remediation、维护者 checklist 和贡献者预期。
- 新增双语 contributor workflow templates 和 pull request readiness guidance，覆盖 workspace task shapes、维护者 review ritual 和 release decisions。
- 新增双语公开路线图，说明 workspace orchestration、agent-native development、runtime expansion、ecosystem alignment 和 release boundaries 的产品方向。
- 新增双语支持说明，定义公开帮助通道、diagnostics 预期、安全报告边界、范围限制和维护者响应预期。
- 新增双语排障文档，将常见症状映射到安全 diagnostics、preview commands、local override guidance、runtime operations 和 support escalation。
- 新增 GitHub issue routing，覆盖 support/security links、usage questions、扩展 bug diagnostics 和 feature-request safety checks。

### 变更

- 更新 `adp status` 的 SSH 状态报告，区分 `auth-pending` 与 `unreachable`，减少 Ubuntu autoinstall 和 first boot 期间的误解。
- 更新 `adp up <runtime>`，当配置的 VMware NAT CIDR 明显不匹配 host `VMnet8` 网络时，会在首次创建 VM 前阻断，避免新 VM 被安装到不可达的 static IP 上。
- 更新英文和简体中文网络、操作、排障文档，说明 NAT host matching、seed network drift，以及使用旧网络配置创建出的 VM 应如何重建或修复 guest 网络。
- 将根目录 `build.md` 调整为历史实现简报，并新增简体中文对应文件，让原始架构意图以公开文档形式呈现，而不是像旧 prompt。
- 新增 `adp workspace report -Markdown`，用于生成可复制到 pull request、release note 和维护者 handoff 的 evidence，并使用仓库相对 evidence path，仓库外路径会被脱敏。
- 新增非破坏性的 workspace dev container metadata 识别，可发现 `.devcontainer/devcontainer.json` 和 `.devcontainer.json`，并将其作为 runtime 内部项目上下文展示。
- 扩展非破坏性的 `adp workspace report` 输出，加入 governance loop queues、action decision queues、release decision policy、stale-task remediation guidance 和 task governance fields。

### 2026-05-28

### 新增

- 新增顶层 `adp status [runtime]` 输出，用于查看 runtime state、local config 状态、配置的 static IP、VMware 探测 IP、SSH 可达性、sync session 是否存在，以及具体连接命令。
- 新增由 CI 执行的文档语言上下文链接检查，确保存在翻译版本时，已选择语言的文档不会意外跳回另一种语言。
- 新增由 CI 执行的配置 schema 检查，覆盖已提交的 platform、topology、sync profile、local example 和 workspace manifest 结构。
- 新增非破坏性的 `adp workspace report` 输出，用于查看 release handoff summary、governance loop queues、action decision queues、release decision policy、stale-task remediation guidance、task governance fields、task validation result、review decision、rollback context、commit readiness、review bundle fields、source-review checklist 和 handoff commands。
- 新增 `configs/workspace.recipes.example.json`，提供可复制的 workspace recipes，覆盖低风险维护、frontend 浏览器验收、backend 验证，以及带 snapshot-first gate 的高风险 agent 工作。
- 新增显式 `adp workspace task validate <task> -Execute`，用于通过 SSH 在 task project 中运行已声明的 validation commands，并支持 `-Execute -Plan` 预览。
- 新增 executable workspace validation 的 readiness gate 输出，以及被忽略的本地 validation result 记录。
- 新增基于已记录 validation result 的 workspace review decision gate 和 rollback validation context。
- 新增基于已记录 validation、review state 和 snapshot-first gate state 的 workspace commit-readiness gate。
- 新增 workspace recipes manifest 的 CI 和 CLI smoke 覆盖。
- 在英文和简体中文 README、workspace 文档中补充 workspace recipes 说明。

### 2026-05-27

### 新增

- 新增 CLI 参数契约 CI 验证，用于检查已接收的开关是否贯通到实际执行路径。
- 新增非破坏性 CLI smoke tests，覆盖命令分发、预览输出和输入错误边界。
- 新增非破坏性 installer smoke tests，覆盖 skip 开关、ISO 诊断、临时本地状态写入和显式 ISO cache 行为。
- 新增 VMware NAT 子网前置说明，覆盖 `doctor`、网络文档和本地覆盖文档。
- 新增更强的首次使用依赖诊断，覆盖 VMware disk manager、WSL、`xorriso`、ISO remaster、Mutagen 版本和 ISO 基本形态。
- 新增显式 Mutagen 修复入口 `adp doctor -FixMutagen`，支持先用 `-Plan` 预览再下载。
- 新增 workspace manifest 示例，以及非破坏性的 `adp workspace init/show/plan` 命令。
- 新增非破坏性的 `adp workspace status` readiness 输出，覆盖 manifest 项目、运行时、同步、快照和验证命令。
- 新增非破坏性的 `adp workspace dashboard` 汇总视图，覆盖项目 readiness 和 task lifecycle state。
- 新增被忽略的本地 `adp-workspace.state.json` lifecycle state 记录，可通过 `adp workspace task mark` 写入。
- 新增面向高风险 workspace task 的 snapshot-first gate，可通过 `tasks[].risk` 和 `tasks[].requires_snapshot` 声明。
- 新增 plan-only workspace task lifecycle 命令：`prepare`、`snapshot`、`validate` 和 `review`。
- 扩展 plan-only workspace task lifecycle 边界，新增 `run`、`rollback` 和 `commit`。
- 新增 `adp doctor -FirstRun`，提供首次使用检查清单。
- 新增 `adp up`、`adp network apply` 和 `adp destroy` 的 `-Plan` 预览。
- 新增公开 `SECURITY.md` 和 `SECURITY.zh-CN.md`。
- 新增公开 `CHANGELOG.md` 和 `CHANGELOG.zh-CN.md`。
- 新增 GitHub bug report 和 feature request issue templates。
- 新增 GitHub pull request template。
- 新增 GitHub Actions CI，用于非破坏性仓库验证。
- 新增英文和简体中文双语公开文档导航。
- 新增 `docs/zh-CN` 下的简体中文文档。
- 新增 `CONTRIBUTING.zh-CN.md`。
- 新增 frontend 浏览器验收辅助命令：
  - `adp-frontend-browser-check`
  - `adp-frontend-browser-install`
- 新增浏览器测试文档。
- 新增 `configs/local.example.json` 和本地配置覆盖支持，用于本机路径、VM 规格、网络、凭据和同步 profile 调整。
- 新增目标项目 clone 和 ADP-OS dogfooding 的工作区指南。

### 变更

- 更新 `adp up` 和首次 provisioning 输出，启动后会打印连接信息，包括 SSH 命令、SSH alias、workspace path、sync 命令和 `adp status` 后续检查命令。
- 更新 autoinstall readiness checks，优先尝试合并后的 topology/local config 中配置的 static IP，再回退到 VMware 探测到的 IP，确保本机 NAT 网段覆盖配置会被一致使用。

- 修复 `adp init <runtime> -SkipProvision`，现在会传递到 `adp up -NoProvision`，不再只是跳过 bootstrap。
- 修复 `adp up <runtime> -NoProvision`，现在创建 VM 定义后会停止，不再继续进入 bootstrap readiness checks。
- 更新 `adp up <runtime> -Plan`，当不需要查询 VM 状态时，预览输出可在未安装 VMware 的环境中运行。
- 修复 CLI 子命令退出码传播，使自动化和 CI 能正确识别命令失败。
- 修复 `adp help`，现在 help 定义会在 CLI dispatch 路径调用前加载。
- 修复嵌套命令日志状态查询，避免命令调用命令时因日志级别状态查找失败。
- 修复 `adp logs`、`adp sync start` 和 `adp sync stop`，现在会在命令边界拒绝未知 runtime 名称。
- 修复 `install.ps1 -SkipDependencyCheck` 和 `install.ps1 -SkipVMValidation`，现在两个开关都会改变对应 installer 行为。
- 修复 `adp up <runtime> -IsoPath <path>`，现在传入的 ISO 路径会正确传递给 VM 创建流程，不再回退到配置的 ISO cache。
- 更新 README 语言导航。
- 更新 frontend bootstrap，使其安装轻量浏览器辅助命令，但默认不下载浏览器。
- 更新同步和 Git ignore 规则，忽略浏览器测试报告和 Playwright 产物。
- 将 agent 运行时启动提示从 `DANGER MODE` 改为 high-IO agent profile 提示。
- 更新 `adp doctor`，报告本地配置覆盖状态。
- 扩展 `adp doctor`，检查配置结构、VMware NAT 网段、运行时静态 IP 唯一性、sync profiles、运行中 VM 的 SSH 可达性、Mutagen 版本和 Mutagen sessions。

### 2026-05-26

### 新增

- ADP-OS 初始开源发布。
- Windows PowerShell 控制平面。
- VMware Workstation 运行时工厂。
- Ubuntu Server 26.04 autoinstall provisioning。
- Frontend、backend 和 agent 运行时 profiles。
- 静态 VMware NAT 网络。
- Mutagen 工作区同步。
- SSH bootstrap。
- Diagnostics、deployment pre-check、snapshot、restore、stop、logs 和 destroy 命令。
- 公开 README、架构文档、配置文档、操作文档、网络文档、贡献指南和 MIT license。
