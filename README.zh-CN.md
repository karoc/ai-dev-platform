# AI Dev Platform OS —— 安全、Spec 驱动的 Windows 原生代码执行 AI Agent 与 Computer-Use Agent 开发沙箱

简体中文 | [English](README.md)

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)
[![MCP](https://img.shields.io/badge/MCP_SDK-18_tools-4B8BBE?logo=python)](cli/mcp/server.py)

AI Dev Platform OS，简称 ADP-OS，是一个安全、企业级、Spec 驱动的本地代码执行沙箱，面向 Windows、VMware Workstation、Ubuntu Server 和 Mutagen，提供硬件级隔离的 AI Agent 和 Computer-Use Agent 开发环境。ADP-OS 采用 Spec 驱动方式：workspace recipe 预先声明项目、任务、验证命令、里程碑和评估钩子，平台按照声明执行，产出可审计的任务状态追踪和发布证据。

本项目会为前端、后端和 AI Agent 工作负载创建隔离的 Linux 代码执行运行时，将 Windows 工作区同步到各个 VM 中，并提供回滚快照，以支持可复现的本地 AI 编码工作流。

ADP-OS 不替代 Docker。它创建可运行 Docker 的本地 Linux 运行时，并在其外层提供 VM 生命周期管理、工作区同步、角色化 bootstrap、诊断、静态网络、快照回滚，以及 Agent 治理（Spec 驱动的工作区配方、任务状态追踪和发布证据审计链）。

> 状态：Windows MVP。macOS、Linux 主机、Hyper-V、KVM、容器运行时以及更完整的工作区编排仍在计划中，尚未实现。

## 提供能力

- 使用 PowerShell 7 实现的 Windows 控制平面。
- 面向 AI Agent 和 Computer-Use Agent 的硬件级隔离代码执行沙箱。
- 面向 Ubuntu Server 26.04 的 VMware Workstation VM 工厂。
- 基于 cloud-init seed data 的 Ubuntu autoinstall ISO 重制。
- `frontend`、`backend` 和 `agent` 运行时 profile。
- 幂等 SSH bootstrap，安装 Docker、Node.js、Python、ripgrep、fd、tmux 以及 profile 专属工具。
- 轻量 frontend 浏览器验收辅助命令，按需安装 Playwright 浏览器。
- 基于 Mutagen 的双向工作区同步。
- 静态 IP 网络，支持配置 NAT 子网和各运行时地址。
- VMware 快照命令，用于创建可回滚的干净检查点。
- 诊断脚本和部署预检查脚本。
- Agent-native MCP 服务器和 SDK，暴露 18 个平台、工作区和运行时工具。
- Agent 治理审计链：任务状态追踪、里程碑检查点、评估钩子和发布证据。

## Agent-Native API（MCP）

ADP-OS 内置了一个 [Model Context Protocol (MCP)](https://modelcontextprotocol.io) 服务器和 SDK（`cli/mcp/server.py`），将完整的 ADP-OS 控制平面暴露为 18 个 agent 可访问的工具：

**平台工具（3 个）：** `adp_status` — 运行时健康状态和 SSH 可达性。`adp_doctor` — 诊断和逐项修复指引。`adp_capabilities` — 已支持功能和路线图。

**工作区工具（10 个）：** `adp_workspace_list` — 列出所有项目。`adp_workspace_status` — 就绪状态汇总。`adp_workspace_dashboard` — 任务生命周期总览。`adp_workspace_project` — 单个项目操作视图。`adp_workspace_create` — 创建项目目录。`adp_workspace_open` — 工作区入口指引。`adp_workspace_sync` — 按项目同步指引。`adp_workspace_close` — 停止运行时同步。`adp_workspace_recipes` — 可用 recipes。`adp_workspace_report` — Markdown 发布证据。

**运行时工具（5 个）：** `adp_up` — 启动 VM（默认仅预览）。`adp_down` — 销毁 VM（默认仅预览）。`adp_stop` — 优雅关闭 VM。`adp_sync_status` — Mutagen 同步健康状态。`adp_sync_stop` — 停止同步会话。

所有破坏性操作默认以 plan-only 模式运行，确保安全。将任何 MCP 兼容的 Agent（Claude Desktop、Hermes、Cursor 等）连接到 `cli/mcp/server.py`：

```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python3",
      "args": ["cli/mcp/server.py"],
      "env": { "ADP_HOME": "/path/to/ai-dev-platform" }
    }
  }
}
```

### GitHub Copilot Agent SDK

ADP-OS 与 [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk) 原生兼容。在 Copilot SDK session 中加载 ADP-OS 作为 MCP 服务器，即可访问全部 18 个平台、工作区和运行时工具。参见 **[Copilot SDK 集成指南](docs/zh-CN/copilot-sdk-integration.md)**，了解 Python 和 TypeScript 快速开始示例、环境变量配置和权限模式。

## 环境要求

- Windows 11。
- PowerShell 7 或更高版本。
- VMware Workstation Pro，包含 `vmrun.exe` 和 `vmware-vdiskmanager.exe`。
- Ubuntu Server 26.04 live server ISO。
- WSL，以及 `xorriso` 或其他兼容的 ISO 重制路径。
- OpenSSH client。
- Mutagen 0.18.x，可位于 `PATH`，也可放在 `.tools\mutagen\mutagen.exe`。

在 WSL 中安装 `xorriso`：

```powershell
wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"
```

## 快速开始

克隆仓库并安装平台：

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
.\\install.ps1
```

下载 Ubuntu Server ISO（使用 BITS 传输，支持断点续传）：

```powershell
adp iso
```

> [!TIP]
> 运行 `install.ps1` 后，`adp.cmd` 包装器即已可用 — 后续所有命令均可使用裸 `adp` 代替 `.\\cli\\adp.ps1`。

如果您在中国，使用镜像下载更快：

```powershell
adp iso -Url "https://mirrors.aliyun.com/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adp iso -Url "https://mirrors.ustc.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
```

如需设置本机路径、VM 规格、静态 IP 或本地 bootstrap 凭据，可以复制已被忽略的本地覆盖示例：

```powershell
Copy-Item configs\\local.example.json configs\\local.json
```

支持的本地覆盖字段见[配置说明](docs/zh-CN/configuration.md#本地覆盖)。

初始化运行时：

```powershell
adp init
```

创建并启动运行时：

```powershell
adp up frontend
adp up backend
adp up agent
```

查看运行时状态和连接信息：

```powershell
adp status
adp status agent
```

启动工作区同步：

```powershell
adp sync start frontend
adp sync start backend
adp sync start agent
```

需要时准备 frontend 浏览器验收测试：

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

检查健康状态：

```powershell
adp doctor
adp doctor -FirstRun
adp doctor -FixMutagen -Plan
adp sync status
```

`install.ps1` 和 `doctor` 会检查 VMware 工具、`vmware-vdiskmanager.exe`、WSL、WSL `xorriso`、Mutagen 0.18.x、OpenSSH、ISO 是否存在以及 ISO 基本形态。它们会输出修复命令或放置路径提示，但默认不会下载大型二进制文件。如需安装经过测试的本地 Mutagen binary，先运行 `doctor -FixMutagen -Plan` 预览，再运行 `doctor -FixMutagen`；archive 和解压后的 binary 会保留在已忽略的 `.tools\mutagen` 下。如果 GitHub release 下载很慢或不可达，可以把 `mutagen_windows_amd64_v0.18.1.zip` 放到 `.tools\mutagen`，或在 `configs\local.json` 中设置 `platform.tools.mutagen.archive_path`；设置 `platform.tools.mutagen.sha256` 后会强制校验 archive hash。

运行非破坏性验证：

```powershell
.\tests\validate.ps1
```

本地快速迭代时可运行：

```powershell
.\tests\validate.ps1 -Quick
```

如需运行单项验证：

```powershell
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

创建干净快照：

```powershell
adp snapshot create frontend clean
adp snapshot create backend clean
adp snapshot create agent clean
```

## 默认运行时

| 运行时 | 用途 | CPU | 内存 | 磁盘 | 静态 IP |
| --- | --- | ---: | ---: | ---: | --- |
| `frontend` | JavaScript 和前端开发 | 4 | 8192 MB | 80 GB | `192.168.242.131` |
| `backend` | Python 和后端开发 | 4 | 8192 MB | 120 GB | `192.168.242.133` |
| `agent` | 面向 AI Agent 的高 IO 调优运行时 | 6 | 16384 MB | 160 GB | `192.168.242.135` |

静态地址配置在 `configs\topology.json`。VMware NAT 子网、网关、DNS 和网卡匹配规则配置在 `configs\platform.json`。

对已有 VM 应用配置的网络：

```powershell
adp network apply all
```

## 工作区路径

默认情况下，Windows 工作区创建在：

```text
%USERPROFILE%\adp-workspaces
```

它们会同步到各 VM 中的：

```text
/home/adp/workspace
```

目标项目应和 ADP-OS 平台仓库分开。将应用或实验项目 clone 到对应运行时的 workspace root 下，例如：

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone <project-url> my-project
```

示例：

```text
%USERPROFILE%\adp-workspaces\frontend  <->  frontend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\backend   <->  backend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\agent     <->  agent:/home/adp/workspace
```

目标项目布局和 ADP-OS dogfooding 指南见[工作区](docs/zh-CN/workspaces.md)。当前支持的 runtime 和 adapter 边界见[能力边界](docs/zh-CN/capabilities.md)。Workspace orchestration、agent-native development 和 runtime expansion 的公开产品方向见[路线图](docs/zh-CN/roadmap.md)。Release decision policy、stale-task remediation flow 和维护者 checklist 见[发布就绪](docs/zh-CN/release-readiness.md)。Validation、evidence、safety checks 和 publication boundaries 见[发布流程](docs/zh-CN/release-process.md)。Task templates、维护者 review ritual 和 pull request expectations 见[贡献者工作流](docs/zh-CN/contributor-workflows.md)。

ADP-OS 还提供一个多场景、Spec 驱动的 workspace recipes manifest，用于常见 agent-native workflow。把 manifest 当作 Spec：声明要构建什么、如何验证、哪些里程碑把关进度，然后由平台执行并产出可审计的发布证据：

```powershell
adp workspace show -ManifestPath configs\workspace.recipes.example.json
adp workspace plan -ManifestPath configs\workspace.recipes.example.json
adp workspace recipes -ManifestPath configs\workspace.recipes.example.json
adp workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
adp workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace dashboard -ManifestPath configs\workspace.recipes.example.json
adp workspace report -ManifestPath configs\workspace.recipes.example.json
adp workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

这些 recipes 覆盖低风险维护、frontend 浏览器验收、backend 验证，以及带 snapshot-first gate 的高风险 agent 工作。它们也演示了可选的 `milestones[]` planning，让相关 task 可以共享一个可见的 milestone checkpoint，例如 `milestone-agent-refactor-safety`；还演示了 plan-only `evaluations[]` hooks，让 agent-native review criteria、metrics 和声明式 evaluation commands 可以进入 release evidence，但不会被执行。`workspace recipes` 是这些示例的 discovery view：它会汇总 project recipes、task recipes、milestone checkpoints、evaluation hooks 和 evidence commands，但不会 clone project、打开 SSH、创建快照、运行 validation、运行 evaluation commands、启动 sync 或运行 Git。`workspace create -Plan` 会预览 manifest 声明的本地项目目录；`workspace create` 只会创建这些本地目录，仍然不会 clone project、启动 sync、启动 runtime、打开 SSH、创建快照、运行 validation、运行 evaluation commands 或运行 Git。`workspace open` 会为单个项目打印非破坏性的 open guide：local path、remote path、readiness，以及可复制的本地、编辑器、SSH、sync 和 status 命令。`workspace sync` 会打印非破坏性的 project-aware sync guide：它会把 manifest project 映射回 runtime sync session，显示 sync readiness 和 sync hygiene，并打印需要显式执行的 runtime `adp sync` 命令。`workspace project` 会在一个位置打印 project operational lifecycle：open、runtime、sync、validation、linked tasks 和 evidence handoff。`workspace report` 还会打印 release handoff summary，用于统计 validation result、列出 blockers、显示 ready for review 或 ready to commit 的 task、标明当前 release gate，暴露 milestone checkpoint status、evaluation queue status，并暴露 owner、review cadence、due date 等 task governance 字段。它还会按 owner queue、review cadence queue、milestone queue、milestone review rollup、validation execution queue、evaluation queue、attention queue 和 decision queues 聚合 task，用于周期性 review，并给出 validate、review、revise、snapshot 或 commit 等下一步动作分类，同时输出 release decision policy 和 stale-task remediation guidance。添加 `-Markdown` 可以生成可复制到 PR 或 release 的 evidence，并保持同一套 decision state，其中包含 Validation Execution Queue、Evaluation Queue、Milestone Checkpoints 和 Milestone Review Rollup tables。这些 recipes 只是 planning examples；workspace 命令不会安装 packages、下载浏览器、创建快照、运行验证、运行 evaluation commands、打开编辑器、SSH 进入 runtime、启动 sync、停止 sync 或 commit 文件。

Validation 可以从 task recipe 中显式执行：

```powershell
adp workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
adp workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` 会预览 readiness gate 和远端 SSH 命令。`-Execute` 只会在目标项目目录中运行已声明的 `tasks[].validation` 命令，并把结果记录到已忽略的本地 workspace state。Review、rollback 和 commit 命令会读取这个记录并显示 decision gate，但 stage、restore 和真正执行 commit 仍然是独立的显式步骤。

## 命令参考

```powershell
adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]
adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive]
adp init
adp init <frontend|backend|agent> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]
adp up <frontend|backend|agent> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
adp status [frontend|backend|agent]
adp capabilities
adp stop <frontend|backend|agent>
adp sync status
adp workspace init
adp workspace show
adp workspace plan
adp workspace status
adp workspace dashboard
adp workspace recipes
adp workspace create [-Plan]
adp workspace open [project-name]
adp workspace sync [project-name]
adp workspace project [project-name]
adp workspace report
adp workspace report [-Markdown]
adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
adp workspace task validate <task-name> [-Execute] [-Plan]
adp workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed>
adp sync start <frontend|backend|agent>
adp sync stop <frontend|backend|agent>
adp network apply <frontend|backend|agent|all> [-Plan]
adp snapshot create <runtime> <name>
adp restore <runtime> <name>
adp logs <runtime>
adp doctor [-FirstRun] [-FixMutagen] [-Plan]
adp destroy <runtime> [-Plan]
```

## 文档

- [文档首页](docs/zh-CN/README.md)
- **[Copilot SDK 集成指南](docs/zh-CN/copilot-sdk-integration.md)** — 在 GitHub Copilot Agent SDK 中加载 ADP-OS 工具。
- [ADP-OS 与 Docker](docs/zh-CN/positioning.md)
- [架构说明](docs/zh-CN/architecture.md)
- [配置说明](docs/zh-CN/configuration.md)
- [工作区](docs/zh-CN/workspaces.md)
- [能力边界](docs/zh-CN/capabilities.md)
- [路线图](docs/zh-CN/roadmap.md)
- [发布就绪](docs/zh-CN/release-readiness.md)
- [发布流程](docs/zh-CN/release-process.md)
- [贡献者工作流](docs/zh-CN/contributor-workflows.md)
- [操作指南](docs/zh-CN/operations.md)
- [排障](docs/zh-CN/troubleshooting.md)
- [网络说明](docs/zh-CN/networking.md)
- [浏览器测试](docs/zh-CN/browser-testing.md)
- [历史实现简报](build.zh-CN.md)
- [贡献指南](CONTRIBUTING.zh-CN.md)
- [支持说明](SUPPORT.zh-CN.md)
- [安全策略](SECURITY.zh-CN.md)
- [变更日志](CHANGELOG.zh-CN.md)

## 安全

ADP-OS 采用**本地开发安全模型**，专为单用户、可信工作站环境设计。默认配置使用本地 `adp:adp` 凭据进行自动化 sudo —— 这些运行时**不**适用于公开、共享、生产或多租户环境。完整策略包括凭据轮换、网络加固和漏洞报告，请参见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md)。

运行时 secrets、VM 磁盘、ISO 镜像、日志、本地工具二进制和本地 assistant 设置均已从版本控制中排除。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
