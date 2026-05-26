# AI Dev Platform OS

简体中文 | [English](README.md)

AI Dev Platform OS，简称 ADP-OS，是一个面向 Windows、VMware Workstation、Ubuntu Server 和 Mutagen 的本地 AI 开发运行时平台。

本项目会为前端、后端和 Agent 工作负载创建隔离的 Linux 运行时，将 Windows 工作区同步到各个 VM 中，并提供回滚快照，以支持可复现的本地 AI 编码工作流。

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
.\cli\adp.ps1 sync status
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

示例：

```text
%USERPROFILE%\adp-workspaces\frontend  <->  frontend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\backend   <->  backend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\agent     <->  agent:/home/adp/workspace
```

## 命令参考

```powershell
.\cli\adp.ps1 init
.\cli\adp.ps1 up <frontend|backend|agent>
.\cli\adp.ps1 stop <frontend|backend|agent>
.\cli\adp.ps1 sync status
.\cli\adp.ps1 sync start <frontend|backend|agent>
.\cli\adp.ps1 sync stop <frontend|backend|agent>
.\cli\adp.ps1 network apply <frontend|backend|agent|all>
.\cli\adp.ps1 snapshot create <runtime> <name>
.\cli\adp.ps1 restore <runtime> <name>
.\cli\adp.ps1 logs <runtime>
.\cli\adp.ps1 doctor
.\cli\adp.ps1 destroy <runtime>
```

## 文档

- [Architecture](docs/architecture.md)
- [Configuration](docs/configuration.md)
- [Operations](docs/operations.md)
- [Networking](docs/networking.md)
- [Browser Testing](docs/browser-testing.md)
- [Contributing](CONTRIBUTING.md)

## 安全说明

这个 MVP 面向本地单用户开发场景。它使用默认运行时用户 `adp` 和默认 bootstrap 密码 `adp` 来自动执行 sudo provisioning。不要在未修改凭据并审查 SSH 访问方式之前，将这些 VM 直接暴露给不可信网络。

运行时 secrets、VM 磁盘、ISO 镜像、日志、本地工具二进制和本地 assistant 设置均已从版本控制中排除。

## 许可证

MIT。参见 [LICENSE](LICENSE)。
