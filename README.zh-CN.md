# ADP-OS —— AI 开发的公证人：可审计、可复现、可证明

简体中文 | [English](README.md)

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)
[![MCP](https://img.shields.io/badge/MCP_SDK-26_tools-4B8BBE?logo=python)](cli/mcp/server.py)
[![Support](https://img.shields.io/badge/Support-GitHub_Issues-2ea44f?logo=github)](https://github.com/karoc/ai-dev-platform/issues/new/choose)

ADP-OS 是一个让 AI 辅助开发变得可审计的平台。它生成可验证的**证据链** —— 快照签名、操作日志和可导出的证据包 —— 让你能够证明：构建了什么、如何构建、由谁（或哪个 AI）编写了每一段代码。每一次开发操作都有记录，每个工作区状态都可以通过快照寻址，每个发布都附带完整的审计轨迹。

ADP-OS 会为前端、后端和 AI Agent 工作负载创建隔离的、可编程的 Linux 代码执行运行时作为自托管 AI 开发基础设施，将 Windows 工作区同步到各个 VM 中，并提供回滚快照，以支持可复现的 AI 编码工作流。它是 Windows 优先的，基于 VMware Workstation、Ubuntu Server 和 Mutagen。

ADP-OS 不替代 Docker。它创建可运行 Docker 的本地 Linux 运行时，并在其外层提供 VM 生命周期管理、工作区同步、角色化 bootstrap、诊断、静态网络、快照回滚，以及 Agent 治理（Spec 驱动的工作区配方、任务状态追踪和发布证据审计链）。

> 状态：Windows MVP。macOS、Linux 主机、Hyper-V、KVM、容器运行时以及更完整的工作区编排仍在计划中，尚未实现。

## 为什么选择 ADP-OS？

AI 每天在写越来越多的代码。但当 AI 生成一个 commit 时，你怎么知道发生了什么？谁审查了它？运行环境是什么？实际执行了哪些命令？

ADP-OS 用一条可验证的**证据链**来回答这些问题：

- **快照签名** — 每个 VM 状态检查点都会被哈希并加盖时间戳，你可以证明代码是在哪个确切环境中构建的。
- **操作日志** — 每次 `adpos up`、`adpos sync`、`adpos snapshot` 和验证运行都会记录操作类型、时间戳和结果。
- **证据导出** — `adpos workspace evidence -Export` 将所有日志、签名、任务状态和 AI 声明打包为一个 ZIP 归档，用于合规、审查或发布。
- **AI 开发声明** — `adpos workspace declare -AiAssisted` 记录谁审查了 AI 生成的代码，创建从 prompt 到生产的溯源轨迹。

```
以前：ADP-OS 是一个管理 AI 开发 VM 的工具。
现在：ADP-OS 是一个让 AI 开发可审计的平台。
未来：ADP-OS 是一个让 AI 开发可信的基础设施。
```

## 提供能力

- **证据链 / Evidence chain** — 快照签名 (`adpos workspace evidence -Snapshot`)、操作日志 (`adpos workspace evidence -Log`)、证据包导出 (`adpos workspace evidence -Export`)、AI 辅助开发声明 (`adpos workspace declare -AiAssisted`)。每次构建都可审计，每次 AI 贡献都有记录。
- **Windows 优先的 VM 沙箱** — 本地优先的面向 AI Agent 和 Computer-Use Agent 的硬件级隔离可编程代码执行沙箱基础设施。使用 PowerShell 7 实现的 Windows 控制平面。
- 面向 Ubuntu Server 26.04 的 VMware Workstation VM 工厂。
- 基于 cloud-init seed data 的 Ubuntu autoinstall ISO 重制。
- `frontend`、`backend` 和 `agent` 运行时 profile。
- 幂等 SSH bootstrap，安装 Docker、Node.js、Python、ripgrep、fd、tmux 以及 profile 专属工具。
- 轻量 frontend 浏览器验收辅助命令，按需安装 Playwright 浏览器。
- 基于 Mutagen 的双向工作区同步。
- 静态 IP 网络，支持配置 NAT 子网和各运行时地址。
- VMware 快照命令，用于创建可回滚的干净检查点。
- 诊断脚本和部署预检查脚本。
- Agent-native MCP 服务器和 SDK，暴露 26 个平台、工作区、运行时和 VM 内沙箱工具。
- Agent 治理审计链：任务状态追踪、里程碑检查点、评估钩子和发布证据。

## Agent-Native API（MCP）

ADP-OS 内置了一个 [Model Context Protocol (MCP)](https://modelcontextprotocol.io) 服务器和 SDK（`cli/mcp/server.py`），将完整的 ADP-OS 控制平面暴露为 26 个 agent 可访问的工具：

**平台工具（3 个）：** `adp_status` — 运行时健康状态和 SSH 可达性。`adp_doctor` — 诊断和逐项修复指引。`adp_capabilities` — 已支持功能和路线图。

**工作区工具（10 个）：** `adp_workspace_list` — 列出所有项目。`adp_workspace_status` — 就绪状态汇总。`adp_workspace_dashboard` — 任务生命周期总览。`adp_workspace_project` — 单个项目操作视图。`adp_workspace_create` — 创建项目目录。`adp_workspace_open` — 工作区入口指引。`adp_workspace_sync` — 按项目同步指引。`adp_workspace_close` — 停止运行时同步。`adp_workspace_recipes` — 可用 recipes。`adp_workspace_report` — Markdown 发布证据。

**运行时工具（5 个）：** `adp_up` — 启动 VM（默认仅预览）。`adp_down` — 销毁 VM（默认仅预览）。`adp_stop` — 优雅关闭 VM。`adp_sync_status` — Mutagen 同步健康状态。`adp_sync_stop` — 停止同步会话。

**VM 内沙箱工具（8 个）：** `adp_exec` — 通过 SSH 执行命令。`adp_file_read` — 读取文件。`adp_file_write` — 写入文件。`adp_dir_list` — 列出目录。`adp_glob` — 匹配文件。`adp_grep` — 搜索文件内容。`adp_file_download` — 下载文件内容。`adp_file_upload` — 上传文件内容。

所有破坏性操作默认以 plan-only 模式运行，确保安全。将任何 MCP 兼容的 Agent（Claude Desktop、Claude Agent、Hermes、Cursor 等）连接到 `cli/mcp/server.py`：

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

ADP-OS 与 [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk) 原生兼容。在 Copilot SDK session 中加载 ADP-OS 作为 MCP 服务器，即可访问全部 26 个平台、工作区、运行时和 VM 内沙箱工具。参见 **[Copilot SDK 集成指南](docs/zh-CN/copilot-sdk-integration.md)**，了解 Python 和 TypeScript 快速开始示例、环境变量配置和权限模式。

### Claude Agent 支持

ADP-OS 兼容 [Claude Managed Agents](https://docs.anthropic.com/en/docs/agents-and-tools/managed-agents)，该平台支持自托管 MCP 沙箱的 Agent 原生代码执行。将 ADP-OS 作为 MCP 服务器连接，即可让 Claude Agent 访问全部 26 个平台、工作区、运行时和 VM 内沙箱工具 —— 包括 VM 生命周期管理、工作区同步、VM 内命令执行、文件操作和 Spec 驱动的审计链。在 Claude Agent 的 MCP 设置中配置 `cli/mcp/server.py` 即可启用自托管沙箱操作，支持 Claude 的 managed agent 工作流。

## 环境要求

- Windows 11。
- Git，用于克隆仓库。
- PowerShell 7 或更高版本。`setup.cmd` 是面向普通 Windows shell 的引导入口；如果缺少 PowerShell 7，它会先尝试用 `winget` 自动安装并继续 setup。若自动安装不可用，才会打印手动 `winget` / MSI 安装路径。ADP-OS 控制平面运行在 PowerShell 7 上。
- VMware Workstation Pro，包含 `vmrun.exe` 和 `vmware-vdiskmanager.exe`。
- Ubuntu Server 26.04 live server ISO。
- WSL，以及 `xorriso` 或其他兼容的 ISO 重制路径。
- OpenSSH client。
- Mutagen 0.18.x，可位于 `PATH`，也可放在 `.tools\mutagen\mutagen.exe`。运行 `.\setup.cmd` 时，如果 Mutagen 是唯一缺失的前提条件，ADP-OS 会把测试过的本地 binary 安装到已忽略的 `.tools\mutagen` 下，然后重新运行 precheck。

在 WSL 中安装 `xorriso`：

```powershell
wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"
```

## 快速开始

> [!TIP]
> 新手？请从 **[入门指南](docs/zh-CN/getting-started.md)** 开始 — 包含架构图、前提条件清单、预计时间和常见错误的分步教程。

> [!WARNING]
> ADP-OS 使用默认 `adp:adp` 用户和密码来配置本地 VM，以进行自动化 sudo 配置。这些 VM 专为可信工作站上的本地单用户开发而设计。请勿在未更改凭据和审查 SSH 访问权限的情况下将其暴露给不受信任的网络。有关完整的本地开发安全模型，请参阅 [安全](SECURITY.zh-CN.md)。

**推荐：从普通 Windows shell 一键设置 — 克隆后只需运行一条命令：**

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
.\setup.cmd
```

`.\setup.cmd` 是克隆后面向普通 Windows shell 的推荐入口。它将引导您一次性完成全部设置：前提条件扫描、ISO 下载（~2.6 GB）、平台引导、初始化和系统诊断。如果缺少 PowerShell 7，`setup.cmd` / `setup.ps1` 会先尝试用 `winget` 自动安装；如果仍无法获得可用的 `pwsh.exe`，才会打印手动安装路径并退出，不会让 Windows PowerShell 5.1 误跑 ADP-OS 控制平面。如果 Mutagen 是唯一缺失的前提条件，setup 会把测试过的本地 Mutagen binary 安装到已忽略的 `.tools\mutagen` 下，并重新运行 precheck 后继续。已经打开 PowerShell 7 时，也可以直接运行 `.\setup.ps1`。

设置流程还会为当前用户注册全局 `adpos` 命令。安装完成后，可以在任意目录运行 `adpos` 操作 ADP-OS；ADP-OS 对外只暴露 `adpos` 这一个用户 shell 命令。如果当前 shell 还没有刷新用户 `PATH`，请打开一个新终端；在仓库根目录下使用 `.\adpos.cmd` 作为本地 wrapper。

多个 ADP-OS checkout 可以共存，但全局 `adpos` 同一时间只能指向其中一个。setup 如果检测到已有全局绑定指向其他 checkout，会询问是否替换；如果保留现有绑定，请在新 checkout 根目录使用 `.\adpos.cmd`。使用第二个 checkout 前，先在该 checkout 中预览本地隔离计划：

```powershell
.\adpos.cmd isolate -Plan -Namespace v2
```

确认预览后，可以复制或调整输出的 `configs\local.json` 片段，也可以让 ADP-OS 只写入这个被忽略的本机文件并自动备份：

```powershell
.\adpos.cmd isolate -Apply -Namespace v2
```

隔离后的 checkout 应使用不同的本机路径和网络设置：至少包括 `platform.runtime_namespace`、`platform.paths.workspace_root`、`platform.paths.vm_store`、`platform.provider.config.vm_store`，以及每个会同时运行的 `topology.<runtime>.static_ip`。设置 `platform.runtime_namespace` 为 `v2` 后，`adpos up agent` 首次创建会指向资源 `v2-agent` 和 VM `adp-v2-agent`，而不是旧的 `adp-agent`。然后在新 checkout 本地检查：

```powershell
.\adpos.cmd doctor
.\adpos.cmd status agent
.\adpos.cmd sync status
.\adpos.cmd up agent -Plan
```

如果已有另一个相同 runtime resource name 的 VM 正在运行，ADP-OS 会报告 `duplicate VM`；在停止 stale VM，或用独立 namespace、VM store、workspace root 和 static IP 隔离 checkout 前，`up` 和 `sync start` 会在修改 runtime state 前停止。

**选项：**

```powershell
.\setup.cmd -IsoPath C:\...\ubuntu.iso   # 使用已下载的 ISO
.\setup.cmd -Distro ubuntu                # 选择支持的发行版配置
.\setup.cmd -SkipIsoDownload              # 跳过 ISO 下载（已缓存）
.\setup.cmd -SkipDoctor                   # 跳过安装后的 doctor 检查
.\setup.cmd -Plan                         # 预览 setup，不执行变更
.\setup.cmd -NonInteractive               # 无交互运行（脚本/CI 使用）
.\setup.cmd -Force                        # 跳过前提条件检查
.\setup.cmd -NoRegisterCommand            # 不注册全局 adpos 命令
```

**可选：如果已安装 PowerShell 7，可先预览前提条件：**

```powershell
.\adpos.cmd precheck
```

如果还没有 PowerShell 7，请直接从 `.\setup.cmd` 开始；它会先引导获得 `pwsh.exe`，然后执行同一套 precheck。`adpos precheck` 会扫描全部 6 项前提条件（Windows 11、PowerShell 7+、VMware Workstation Pro、WSL+xorriso、Mutagen 0.18.x、OpenSSH），以状态表格显示每项的修复命令。使用 `.\adpos.cmd precheck --help-prereqs` 查看带安装命令的完整需求列表。

**setup 后常用的后续命令：**

下载 Ubuntu Server ISO（使用 BITS 传输，支持断点续传）：

```powershell
adpos iso
```

> [!TIP]
> 安装后请使用正式入口 `adpos`。如果当前 shell 尚未刷新 `PATH`，可在仓库根目录使用 `.\adpos.cmd`。

如果您在中国，使用镜像下载更快：

```powershell
adpos iso -Url "https://mirrors.aliyun.com/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adpos iso -Url "https://mirrors.ustc.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
```

如需设置本机路径、VM 规格、静态 IP 或本地 bootstrap 凭据，可以复制已被忽略的本地覆盖示例：

```powershell
Copy-Item configs\\local.example.json configs\\local.json
```

支持的本地覆盖字段见[配置说明](docs/zh-CN/configuration.md#本地覆盖)。

初始化运行时：

```powershell
adpos init
```

创建并启动运行时：

```powershell
adpos up frontend
adpos up backend
adpos up agent
```

查看运行时状态和连接信息：

```powershell
adpos status
adpos status agent
```

启动工作区同步：

```powershell
adpos sync start frontend
adpos sync start backend
adpos sync start agent
```

需要时准备 frontend 浏览器验收测试：

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

检查健康状态：

```powershell
adpos doctor
adpos doctor -FirstRun
adpos doctor -FixMutagen -Plan
adpos sync status
```

`setup`、`precheck` 和 `doctor` 会检查 VMware 工具、`vmware-vdiskmanager.exe`、WSL、WSL `xorriso`、Mutagen 0.18.x、OpenSSH、ISO 是否存在以及 ISO 基本形态。它们会输出修复命令或放置路径提示。如需安装经过测试的本地 Mutagen binary，先运行 `doctor -FixMutagen -Plan` 预览，再运行 `doctor -FixMutagen`；archive 和解压后的 binary 会保留在已忽略的 `.tools\mutagen` 下。如果 GitHub release 下载很慢或不可达，可以把 `mutagen_windows_amd64_v0.18.1.zip` 放到 `.tools\mutagen`，或在 `configs\local.json` 中设置 `platform.tools.mutagen.archive_path`；设置 `platform.tools.mutagen.sha256` 后会强制校验 archive hash。

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
adpos snapshot create frontend clean
adpos snapshot create backend clean
adpos snapshot create agent clean
```

签署快照并导出证据链：

```powershell
adpos workspace evidence -Snapshot
adpos workspace evidence -Export
adpos workspace declare -AiAssisted -Reviewer "your-name"
```

一键卸载当前用户的命令注册：

```powershell
adpos uninstall
```

这只会移除当前用户级别的 `adpos` PATH shim，不会删除 VM、workspace 文件、ISO cache、本地工具、日志或仓库文件。

如果当前 shell 中还无法使用 `adpos`，也可以在仓库根目录运行：

```powershell
.\uninstall.cmd
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
adpos network apply all
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
adpos workspace show -ManifestPath configs\workspace.recipes.example.json
adpos workspace plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace recipes -ManifestPath configs\workspace.recipes.example.json
adpos workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace dashboard -ManifestPath configs\workspace.recipes.example.json
adpos workspace report -ManifestPath configs\workspace.recipes.example.json
adpos workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

这些 recipes 覆盖低风险维护、frontend 浏览器验收、backend 验证，以及带 snapshot-first gate 的高风险 agent 工作。它们也演示了可选的 `milestones[]` planning，让相关 task 可以共享一个可见的 milestone checkpoint，例如 `milestone-agent-refactor-safety`；还演示了 plan-only `evaluations[]` hooks，让 agent-native review criteria、metrics 和声明式 evaluation commands 可以进入 release evidence，但不会被执行。`workspace recipes` 是这些示例的 discovery view：它会汇总 project recipes、task recipes、milestone checkpoints、evaluation hooks 和 evidence commands，但不会 clone project、打开 SSH、创建快照、运行 validation、运行 evaluation commands、启动 sync 或运行 Git。`workspace create -Plan` 会预览 manifest 声明的本地项目目录；`workspace create` 只会创建这些本地目录，仍然不会 clone project、启动 sync、启动 runtime、打开 SSH、创建快照、运行 validation、运行 evaluation commands 或运行 Git。`workspace open` 会为单个项目打印非破坏性的 open guide：local path、remote path、readiness，以及可复制的本地、编辑器、SSH、sync 和 status 命令。`workspace sync` 会打印非破坏性的 project-aware sync guide：它会把 manifest project 映射回 runtime sync session，显示 sync readiness 和 sync hygiene，并打印需要显式执行的 runtime `adpos sync` 命令。`workspace project` 会在一个位置打印 project operational lifecycle：open、runtime、sync、validation、linked tasks 和 evidence handoff。`workspace report` 还会打印 release handoff summary，用于统计 validation result、列出 blockers、显示 ready for review 或 ready to commit 的 task、标明当前 release gate，暴露 milestone checkpoint status、evaluation queue status，并暴露 owner、review cadence、due date 等 task governance 字段。它还会按 owner queue、review cadence queue、milestone queue、milestone review rollup、validation execution queue、evaluation queue、attention queue 和 decision queues 聚合 task，用于周期性 review，并给出 validate、review、revise、snapshot 或 commit 等下一步动作分类，同时输出 release decision policy 和 stale-task remediation guidance。添加 `-Markdown` 可以生成可复制到 PR 或 release 的 evidence，并保持同一套 decision state，其中包含 Validation Execution Queue、Evaluation Queue、Milestone Checkpoints 和 Milestone Review Rollup tables。这些 recipes 只是 planning examples；workspace 命令不会安装 packages、下载浏览器、创建快照、运行验证、运行 evaluation commands、打开编辑器、SSH 进入 runtime、启动 sync、停止 sync 或 commit 文件。

Validation 可以从 task recipe 中显式执行：

```powershell
adpos workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` 会预览 readiness gate 和远端 SSH 命令。`-Execute` 只会在目标项目目录中运行已声明的 `tasks[].validation` 命令，并把结果记录到已忽略的本地 workspace state。Review、rollback 和 commit 命令会读取这个记录并显示 decision gate，但 stage、restore 和真正执行 commit 仍然是独立的显式步骤。

## 命令参考

本节使用 `adpos`，也就是 `.\setup.cmd` 安装后注册的正式命令。若当前 shell 尚未刷新 `PATH`，可在仓库根目录使用 `.\adpos.cmd ...`。MCP 工具名（例如 `adp_status`）是稳定协议标识，保持不变。

`adpos uninstall` 只移除属于当前 checkout 的全局命令注册。Runtime 数据、workspace 数据、缓存、工具、日志和仓库文件都会保留。如果全局 `adpos` 属于另一个 checkout，默认会拒绝卸载；请到所属 checkout 中执行卸载，或在确认要移除该全局绑定时使用 `-Force`。

```powershell
adpos setup [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [-Plan]
adpos uninstall [-NonInteractive] [-Force]
adpos help [command]
adpos version
adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]
adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive] [-NoRegisterCommand] [-Plan] [--help-prereqs]
adpos precheck [--help-prereqs]
adpos init
adpos init <frontend|backend|agent|sandbox> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]
adpos up <frontend|backend|agent|sandbox> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
adpos run <frontend|backend|agent|sandbox> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap] [-NoSync]
adpos status [frontend|backend|agent|sandbox] [-Json]
adpos capabilities
adpos stop <frontend|backend|agent|sandbox>
adpos validate [-Quick] [-SkipCliSmoke] [-SkipInstallerSmoke] [-SkipShellSyntax]
adpos completion <powershell|bash>
adpos sandbox <command...> [-Distro <name>] [-IsoPath <path>]
adpos serve [-Port <port>] [-Public] [-Json]
adpos isolate [-Plan|-Apply] [-Namespace <name>]
adpos sync status
adpos sync list
adpos workspace init
adpos workspace show
adpos workspace plan
adpos workspace status
adpos workspace dashboard
adpos workspace recipes
adpos workspace create [-Plan]
adpos workspace open [project-name]
adpos workspace sync [project-name]
adpos workspace project [project-name]
adpos workspace report
adpos workspace report [-Markdown]
adpos workspace evidence -Snapshot [-Json]                        签署当前快照元数据 (SHA-256 链)
adpos workspace evidence -Log -Operation <op> [-Details <text>] [-Json]  记录操作日志条目
adpos workspace evidence -Export [-Path <path>]                   导出所有证据为 ZIP
adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes "..."] [-Json]  声明 AI 辅助开发
adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
adpos workspace task validate <task-name> [-Execute] [-Plan]
adpos workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|validation_failed|reviewed|rollback|committed>
adpos sync start <frontend|backend|agent|sandbox>
adpos sync stop <frontend|backend|agent|sandbox>
adpos network apply <frontend|backend|agent|sandbox|all> [-Plan]
adpos network configure-local [-Plan|-Apply]
adpos snapshot create <runtime> <name>
adpos restore <runtime> <name> [-Plan] [-Force]
adpos logs <runtime>
adpos doctor [-FirstRun] [-Json]
adpos doctor -FixMutagen [-Plan] [-Json]
adpos destroy <runtime> [-Plan] [-Force]
adpos workspace evidence -Snapshot [-ManifestPath <path>]
adpos workspace evidence -Log -Operation <op> [-Details <text>] [-ManifestPath <path>]
adpos workspace evidence -Export [-Path <path>] [-ManifestPath <path>]
adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes "..."] [-ManifestPath <path>]
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
- [证据链](docs/zh-CN/evidence.md)
- [生存验证](docs/zh-CN/survival-validation.md)
- [10 分钟生存价值演示 / 录制前核对](docs/zh-CN/demo-script.md)
- [排障](docs/zh-CN/troubleshooting.md)
- [网络说明](docs/zh-CN/networking.md)
- [浏览器测试](docs/zh-CN/browser-testing.md)
- [历史实现简报](build.zh-CN.md)
- [贡献指南](CONTRIBUTING.zh-CN.md)
- [支持说明](SUPPORT.zh-CN.md)
- [安全策略](SECURITY.zh-CN.md)
- [变更日志](CHANGELOG.zh-CN.md)

## 社区

- **[GitHub Issues](https://github.com/karoc/ai-dev-platform/issues/new/choose)** — 使用模板提交安装帮助、使用问题、可复现 bug 和功能请求。
- **[贡献指南](CONTRIBUTING.zh-CN.md)** — 开发环境搭建、编码规范和 PR 流程。
- **[演示](docs/demo.cast)** — 快速终端导览：clone → doctor → plan → status → MCP（30 秒，用 `asciinema play` 播放）。[10 分钟演示脚本 →](docs/zh-CN/demo-script.md)
- **[生存验证](docs/zh-CN/survival-validation.md)** — 面向首批用户的验证流程，记录 10 分钟 demo、rollback 结果、evidence export 和反馈。
- **[Discord 搭建计划](docs/zh-CN/discord-setup.md)** — 计划中的社区聊天入口。发布真实邀请链接前，它不是当前可用的支持渠道。

## 安全

ADP-OS 采用**本地开发安全模型**，专为单用户、可信工作站环境设计。默认配置使用本地 `adp:adp` 凭据进行自动化 sudo —— 这些运行时**不**适用于公开、共享、生产或多租户环境。完整策略包括凭据轮换、网络加固和漏洞报告，请参见 [SECURITY.zh-CN.md](SECURITY.zh-CN.md)。

运行时 secrets、VM 磁盘、ISO 镜像、日志、本地工具二进制和本地 assistant 设置均已从版本控制中排除。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
