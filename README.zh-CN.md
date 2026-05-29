# AI Dev Platform OS

简体中文 | [English](README.md)

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)

AI Dev Platform OS，简称 ADP-OS，是一个面向 Windows、VMware Workstation、Ubuntu Server 和 Mutagen 的本地 AI 开发运行时平台。

本项目会为前端、后端和 Agent 工作负载创建隔离的 Linux 运行时，将 Windows 工作区同步到各个 VM 中，并提供回滚快照，以支持可复现的本地 AI 编码工作流。

ADP-OS 不替代 Docker。它创建可运行 Docker 的本地 Linux 运行时，并在其外层提供 VM 生命周期管理、工作区同步、角色化 bootstrap、诊断、静态网络和快照回滚。

> 状态：Windows MVP。macOS、Linux 主机、Hyper-V、KVM、容器运行时以及更完整的工作区编排仍在计划中，尚未实现。

## 提供能力

- 使用 PowerShell 7 实现的 Windows 控制平面。
- 面向 Ubuntu Server 26.04 的 VMware Workstation VM 工厂。
- 基于 cloud-init seed data 的 Ubuntu autoinstall ISO 重制。
- `frontend`、`backend` 和 `agent` 运行时 profile。
- 幂等 SSH bootstrap，安装 Docker、Node.js、Python、ripgrep、fd、tmux 以及 profile 专属工具。
- 轻量 frontend 浏览器验收辅助命令，按需安装 Playwright 浏览器。
- 基于 Mutagen 的双向工作区同步。
- 静态 IP 网络，支持配置 NAT 子网和各运行时地址。
- VMware 快照命令，用于创建可回滚的干净检查点。
- 诊断脚本和部署预检查脚本。

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

克隆仓库：

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
```

将 Ubuntu ISO 放到：

```text
%USERPROFILE%\adp-iso\ubuntu-26.04-live-server-amd64.iso
```

或者在初始化时传入 ISO 路径：

```powershell
.\install.ps1 -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso
```

如需设置本机路径、VM 规格、静态 IP 或本地 bootstrap 凭据，可以复制已被忽略的本地覆盖示例：

```powershell
Copy-Item configs\local.example.json configs\local.json
```

支持的本地覆盖字段见[配置说明](docs/zh-CN/configuration.md#本地覆盖)。

初始化平台：

```powershell
.\install.ps1
.\cli\adp.ps1 init
```

创建并启动运行时：

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

查看运行时状态和连接信息：

```powershell
.\cli\adp.ps1 status
.\cli\adp.ps1 status agent
```

启动工作区同步：

```powershell
.\cli\adp.ps1 sync start frontend
.\cli\adp.ps1 sync start backend
.\cli\adp.ps1 sync start agent
```

需要时准备 frontend 浏览器验收测试：

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

检查健康状态：

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 doctor -FixMutagen -Plan
.\cli\adp.ps1 sync status
```

`install.ps1` 和 `doctor` 会检查 VMware 工具、`vmware-vdiskmanager.exe`、WSL、WSL `xorriso`、Mutagen 0.18.x、OpenSSH、ISO 是否存在以及 ISO 基本形态。它们会输出修复命令或放置路径提示，但默认不会下载大型二进制文件。如需安装经过测试的本地 Mutagen binary，先运行 `doctor -FixMutagen -Plan` 预览，再运行 `doctor -FixMutagen`；下载的 archive 和解压后的 binary 会保留在已忽略的 `.tools\mutagen` 下。

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
.\cli\adp.ps1 snapshot create frontend clean
.\cli\adp.ps1 snapshot create backend clean
.\cli\adp.ps1 snapshot create agent clean
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
.\cli\adp.ps1 network apply all
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

目标项目布局和 ADP-OS dogfooding 指南见[工作区](docs/zh-CN/workspaces.md)。Workspace orchestration、agent-native development 和 runtime expansion 的公开产品方向见[路线图](docs/zh-CN/roadmap.md)。Release decision policy、stale-task remediation flow 和维护者 checklist 见[发布就绪](docs/zh-CN/release-readiness.md)。Validation、evidence、safety checks 和 publication boundaries 见[发布流程](docs/zh-CN/release-process.md)。Task templates、维护者 review ritual 和 pull request expectations 见[贡献者工作流](docs/zh-CN/contributor-workflows.md)。

ADP-OS 还提供一个多场景 workspace recipes manifest，用于常见 agent-native workflow：

```powershell
.\cli\adp.ps1 workspace show -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

这些 recipes 覆盖低风险维护、frontend 浏览器验收、backend 验证，以及带 snapshot-first gate 的高风险 agent 工作。`workspace report` 还会打印 release handoff summary，用于统计 validation result、列出 blockers、显示 ready for review 或 ready to commit 的 task、标明当前 release gate，并暴露 owner、review cadence、due date 等 task governance 字段。它还会按 owner queue、review cadence queue、attention queue 和 decision queues 聚合 task，用于周期性 review，并给出 validate、review、revise、snapshot 或 commit 等下一步动作分类，同时输出 release decision policy 和 stale-task remediation guidance。添加 `-Markdown` 可以生成可复制到 PR 或 release 的 evidence，并保持同一套 decision state。这些 recipes 只是 planning examples；workspace 命令不会安装 packages、下载浏览器、创建快照、运行验证或 commit 文件。

Validation 可以从 task recipe 中显式执行：

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` 会预览 readiness gate 和远端 SSH 命令。`-Execute` 只会在目标项目目录中运行已声明的 `tasks[].validation` 命令，并把结果记录到已忽略的本地 workspace state。Review、rollback 和 commit 命令会读取这个记录并显示 decision gate，但 stage、restore 和真正执行 commit 仍然是独立的显式步骤。

## 命令参考

```powershell
.\cli\adp.ps1 init
.\cli\adp.ps1 init <frontend|backend|agent> [-IsoPath <path>] [-SkipProvision]
.\cli\adp.ps1 up <frontend|backend|agent> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
.\cli\adp.ps1 status [frontend|backend|agent]
.\cli\adp.ps1 stop <frontend|backend|agent>
.\cli\adp.ps1 sync status
.\cli\adp.ps1 workspace init
.\cli\adp.ps1 workspace show
.\cli\adp.ps1 workspace plan
.\cli\adp.ps1 workspace status
.\cli\adp.ps1 workspace dashboard
.\cli\adp.ps1 workspace report
.\cli\adp.ps1 workspace report [-Markdown]
.\cli\adp.ps1 workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
.\cli\adp.ps1 workspace task validate <task-name> [-Execute] [-Plan]
.\cli\adp.ps1 workspace task mark <task-name> <prepared|checkpointed|running|validated|reviewed|rollback|committed>
.\cli\adp.ps1 sync start <frontend|backend|agent>
.\cli\adp.ps1 sync stop <frontend|backend|agent>
.\cli\adp.ps1 network apply <frontend|backend|agent|all> [-Plan]
.\cli\adp.ps1 snapshot create <runtime> <name>
.\cli\adp.ps1 restore <runtime> <name>
.\cli\adp.ps1 logs <runtime>
.\cli\adp.ps1 doctor [-FirstRun] [-FixMutagen] [-Plan]
.\cli\adp.ps1 destroy <runtime> [-Plan]
```

## 文档

- [文档首页](docs/zh-CN/README.md)
- [ADP-OS 与 Docker](docs/zh-CN/positioning.md)
- [架构说明](docs/zh-CN/architecture.md)
- [配置说明](docs/zh-CN/configuration.md)
- [工作区](docs/zh-CN/workspaces.md)
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

## 安全说明

这个 MVP 面向本地单用户开发场景。它使用默认运行时用户 `adp` 和默认 bootstrap 密码 `adp` 来自动执行 sudo provisioning。不要在未修改凭据并审查 SSH 访问方式之前，将这些 VM 直接暴露给不可信网络。

运行时 secrets、VM 磁盘、ISO 镜像、日志、本地工具二进制和本地 assistant 设置均已从版本控制中排除。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
