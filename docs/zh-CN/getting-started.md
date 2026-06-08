# 快速入门

简体中文 | [English](../getting-started.md)

欢迎使用 ADP-OS。本指南将带你完成首次设置——从零到运行中的开发虚拟机——大约需要 30-70 分钟，主要取决于 ISO 下载速度和首次 VM 创建耗时。

## 什么是 ADP-OS？

ADP-OS（AI Dev Platform OS）是一个本地 AI 开发运行时平台。它在你的 Windows 工作站上创建隔离的 Linux 虚拟机，将你的项目文件同步到每个 VM 中，并为你提供可回滚的快照，支持可重复的 AI 编码工作流。

```text
                        Windows 11 主机
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ADP-OS 控制平面 (PowerShell 7)                            │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│   │  setup   │  │  adpos   │  │  doctor  │                 │
│   │  .cmd    │  │ command  │  │  checks  │                 │
│   └──────────┘  └──────────┘  └──────────┘                 │
│         │              │             │                       │
│         ▼              ▼             ▼                       │
│   ┌──────────────────────────────────────────┐              │
│   │         VMware Workstation               │              │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ │              │
│   │  │ frontend │ │ backend  │ │  agent   │ │              │
│   │  │  Ubuntu  │ │  Ubuntu  │ │  Ubuntu  │ │              │
│   │  │ 26.04 VM │ │ 26.04 VM │ │ 26.04 VM │ │              │
│   │  │          │ │          │ │          │ │              │
│   │  │  Docker  │ │  Docker  │ │  Docker  │ │              │
│   │  │  Node.js │ │  Python  │ │  AI dev  │ │              │
│   │  └──────────┘ └──────────┘ └──────────┘ │              │
│   └──────────────────────────────────────────┘              │
│         ▲              ▲             ▲                       │
│         └──────────────┼─────────────┘                       │
│                        │                                     │
│              Mutagen 同步 (双向)                             │
│                        │                                     │
│         %USERPROFILE%\adp-workspaces\                        │
│         ├── frontend/  →  frontend VM:/home/adp/workspace    │
│         ├── backend/   →  backend VM :/home/adp/workspace    │
│         └── agent/     →  agent VM   :/home/adp/workspace    │
└─────────────────────────────────────────────────────────────┘
```

ADP-OS 不会替代 Docker。它提供可运行 Docker 的虚拟机，并在此基础上增加了生命周期管理、工作区同步、静态网络、按角色引导和快照回滚功能。

## 你需要准备什么

开始之前，请确认你具备以下条件：

| # | 前置条件 | 获取方式 |
|---|---------|---------|
| 1 | **Windows 11** | 通过 设置 → 系统 → 关于 查看。不支持 Windows 10。 |
| 2 | **PowerShell 7+** | 如果缺少 PowerShell 7，`.\setup.cmd` 会尝试用 `winget` 自动安装。手动 fallback：`winget install --id Microsoft.PowerShell --source winget`，或从 GitHub 下载。系统内置 PowerShell 5.1 可以启动引导 wrapper，但不能运行 ADP-OS 控制平面。 |
| 3 | **VMware Workstation Pro** | [下载](https://www.vmware.com/products/workstation-pro.html)（个人免费使用，或付费许可）。验证 `vmrun.exe` 是否在 PATH 中。 |
| 4 | **WSL**（Windows Subsystem for Linux） | 在管理员 PowerShell 中运行 `wsl --install`。ISO 重制需要此项。 |
| 5 | **OpenSSH 客户端** | Windows 11 已内置。运行 `ssh -V` 验证。 |
| 6 | **Mutagen 0.18.x** | 安装后 ADP-OS 可以通过 `adpos doctor -FixMutagen` 帮你安装；如果当前 shell 尚未刷新 `PATH`，可在仓库根目录用 `.\adpos.cmd doctor -FixMutagen`。如果 GitHub 速度慢，也可以[手动下载](https://github.com/mutagen-io/mutagen/releases)。 |
| 7 | **约 10 GB 可用磁盘空间** | 用于 ISO、VM 磁盘和工具二进制文件。 |

**注意：** 第 1–5 项是你需要自己安装的前置条件。第 6 项（Mutagen）可由 ADP-OS 内置的 doctor 安装。第 7 项只是空间。

## 预计时间线

| 步骤 | 耗时 | 内容 |
|------|------|------|
| 克隆仓库 | < 1 分钟 | `git clone` — 几 MB 大小 |
| 下载 Ubuntu ISO | 5–15 分钟 | ~2.6 GB 下载。速度取决于你的网络和 [Ubuntu 镜像](https://releases.ubuntu.com/26.04/) 的可达性 |
| `setup.cmd`（安装 + 初始化） | 5–10 分钟 | 安装平台、注册全局 `adpos` 命令、重制 ISO、创建 VM 模板 |
| `adpos up frontend`（首次 VM） | 15–45 分钟 | 创建并启动你的第一个 VM，运行引导脚本 |
| 之后 warm start | 约 30 秒 | 启动已经完成 provisioning 的既有 VM |
| 用 `adpos status` 验证 | < 1 分钟 | 确认一切正常运行 |
| **合计** | **约 30–70 分钟** | 从零到可用的开发虚拟机 |

以上时间假设使用典型宽带连接和配置较好的机器。ISO 下载通常是最慢的步骤。

## 逐步操作指南

### 第 1 步：克隆仓库

打开 Windows Terminal、PowerShell 或 cmd.exe，运行：

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
```

> [!TIP]
> 安装完成后，你可以在任意目录直接使用 `adpos`。如果当前 shell 尚未刷新用户 `PATH`，请打开新终端，或在仓库根目录使用 `.\adpos.cmd`。ADP-OS 对外只暴露 `adpos` 这一个用户 shell 命令。

#### 使用第二个 Checkout

如果这是同一 Windows 用户账户下的第二个本地 checkout，或另一个 ADP-OS 版本，setup 可能会检测到全局 `adpos` 已经指向另一个 checkout。你可以替换该绑定，也可以保留它，并在当前 checkout 中使用 `.\adpos.cmd`。

在第二个 checkout 中创建、启动或同步 runtime 前，请先预览本机隔离计划：

```powershell
.\adpos.cmd isolate -Plan -Namespace v2
```

复制或调整输出的 `configs\local.json` 片段，让当前 checkout 完成隔离：

- 使用不同的 `platform.runtime_namespace`。
- 使用不同的 `platform.paths.workspace_root`。
- 使用不同的 `platform.paths.vm_store`。
- 使用匹配的 `platform.provider.config.vm_store`。
- 为可能从不同 checkout 激活的 runtime 使用不同的 `topology.<runtime>.static_ip`。

如果希望 ADP-OS 只写入被忽略的本机覆盖文件并自动备份，运行：

```powershell
.\adpos.cmd isolate -Apply -Namespace v2
```

创建或同步 VM 前，先在当前 checkout 本地检查：

```powershell
.\adpos.cmd doctor
.\adpos.cmd status agent
.\adpos.cmd sync status
.\adpos.cmd up agent -Plan
```

runtime gate 会阻止相同 runtime resource name 的重复运行 VM。如果 `status` 报告 `duplicate VM`，请先从其所属 checkout 或 VMware UI 停止 stale VM，再从当前 checkout 运行 `up` 或 `sync start`。Namespaced runtime resource names 已支持首次 VM 创建：当 `platform.runtime_namespace` 设置为 `v2` 时，`adpos up agent` 会指向资源 `v2-agent` 和 VM `adp-v2-agent`。这不会自动隔离 IP 或路径，因此仍要保留上面独立的 `workspace_root`、`vm_store` 和 `static_ip` 配置。

### 第 2 步：运行引导式设置

**一键设置：** 在仓库根目录运行 `.\setup.cmd`：

```powershell
.\setup.cmd
```

这一条命令即可完成前提条件扫描、ISO 下载、平台安装、初始化和诊断：

1. **前提条件扫描** — 检查全部 6 项前提条件，显示每项的修复步骤。
2. **ISO 下载** — 下载 Ubuntu Server 26.04（约 2.6 GB）。显示百分比和速度。
3. **安装** — 运行 `install.ps1`，设置目录、注册 `adpos`、生成 seed ISO 并创建 VM 模板。
4. **初始化** — setup 链路会运行 `adpos init -Quick` 完成平台配置。
5. **诊断** — setup 链路会运行 `adpos doctor` 验证所有前置条件是否就绪。

每个阶段完成时，你会看到 `[1/6]`、`[2/6]` 等进度指示。

> [!TIP]
> 如果已有 Ubuntu ISO：`.\setup.cmd -IsoPath C:\path\to\ubuntu.iso`
> 非交互/脚本化使用：`.\setup.cmd -NonInteractive`

> [!NOTE]
> 如果你已经有 Ubuntu ISO 文件，可以跳过下载：
> ```powershell
> .\setup.cmd -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso
> ```

### 第 3 步：启动你的第一个 Runtime

创建并启动 frontend 虚拟机：

```powershell
adpos up frontend
```

这条命令会：

1. 创建 VM 磁盘和 VMX 配置
2. 使用重制后的 ISO 启动 VM
3. 等待 cloud-init 完成 provisioning
4. 运行 SSH 引导脚本（Docker、Node.js 等）
5. 确认 VM 就绪

每个阶段完成时都会显示输出。首次 VM 创建通常需要 15–45 分钟，因为 Ubuntu autoinstall 和 bootstrap 都会首次运行。已经完成 provisioning 的既有 VM 之后 warm start 通常约 30 秒。

> [!TIP]
> 想预览 `up` 会做什么而不实际执行？使用 `-Plan`：
> ```powershell
> adpos up frontend -Plan
> ```

### 第 4 步：检查一切是否正常

#### 检查 Runtime 状态

```powershell
adpos status
```

正常的输出如下：

```text
RUNTIME   STATE     IP               SSH
frontend  running   192.168.242.131  adp-os-adp-frontend
```

`STATE` 应显示 `running`。如果显示 `poweredOff`，说明 VM 没有启动——请跳到下方的[常见错误](#常见首次错误)。

#### 运行诊断

```powershell
adpos doctor
```

正常的输出如下：

```text
[PASS] VMware Workstation      (vmrun.exe found)
[PASS] VMware Disk Manager     (vmware-vdiskmanager.exe found)
[PASS] WSL                     (WSL detected)
[PASS] WSL xorriso             (xorriso 1.5.6 available)
[PASS] Mutagen                 (0.18.1)
[PASS] OpenSSH                 (OpenSSH_for_Windows_9.5p1)
[PASS] Ubuntu ISO              (ubuntu-26.04-live-server-amd64.iso present)

Doctor complete: 7/7 checks passed.
```

所有 7 项检查都应显示 `[PASS]`。如果有任何一项显示 `[FAIL]`，输出中会包含修复说明——按说明操作后重新运行 `adpos doctor`。

### 第 5 步：启动工作区同步（可选但推荐）

将你的本地项目文件同步到 VM 中：

```powershell
adpos sync start frontend
```

检查同步状态：

```powershell
adpos sync status
```

预期输出：

```text
RUNTIME   STATUS    SOURCE                              DEST
frontend  watching  %USERPROFILE%\adp-workspaces\fron... /home/adp/workspace
```

现在你放入 `%USERPROFILE%\adp-workspaces\frontend\` 的任何文件都会立即出现在 VM 的 `/home/adp/workspace/` 中。

### 第 6 步：SSH 进入你的 VM

```powershell
ssh adp-os-adp-frontend
```

现在你已经进入了开发 VM。试试：

```bash
docker --version
node --version
python3 --version
```

这三条命令都应该输出版本号——这些都是在 bootstrap 过程中安装的。

> [!WARNING]
> VM 使用默认的 `adp:adp` 用户和密码进行自动 sudo 配置。这对于在可信工作站上进行本地单用户开发是安全的。请勿在未修改凭据的情况下将这些 VM 暴露给不受信任的网络。详见[安全策略](../../SECURITY.zh-CN.md)。

## 常见首次错误

### "vmrun.exe not found"

**症状：** `adpos doctor` 显示 `[FAIL] VMware Workstation`。

**修复：** 安装 VMware Workstation Pro。安装后，打开一个新的 PowerShell 窗口以使 PATH 更新。验证：

```powershell
vmrun.exe list
```

### ISO 下载失败或速度很慢

**症状：** `quickstart` 在 ISO 下载阶段卡住，或 `Invoke-WebRequest` 超时。

**修复：** 通过浏览器手动下载 ISO（浏览器可能更好地处理断点续传），然后传入路径：

```powershell
.\setup.cmd -IsoPath C:\Users\你的用户名\Downloads\ubuntu-26.04-live-server-amd64.iso
```

ISO 下载到 `%USERPROFILE%\adp-iso\`。手动下载地址：https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso

### "WSL not detected" 或 "xorriso not found"

**症状：** `adpos doctor` 显示 `[FAIL] WSL` 或 `[FAIL] WSL xorriso`。

**修复：** 安装 WSL 和 xorriso：

```powershell
# 安装 WSL（在管理员 PowerShell 中运行）
wsl --install

# 安装 xorriso（在 WSL 中运行）
wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"
```

### VM 启动了但 "provisioning timed out"

**症状：** `adpos up frontend` 运行一段时间后显示 cloud-init provisioning 超时错误。

**修复：** 这通常意味着 VMware 网络配置不正确。检查：

1. 打开 VMware Workstation，进入 编辑 → 虚拟网络编辑器
2. 确认 NAT 网络（默认 `vmnet8`）已启用
3. 检查子网是否与 `configs\platform.json` 匹配
4. 运行 `adpos doctor` — 它可以检测 NAT 主机匹配情况

### 运行 .ps1 文件时提示 "Permission denied"

**症状：** PowerShell 显示红色的执行策略错误。

**修复：** ADP-OS 脚本不需要修改系统执行策略。通过将脚本路径传给 PowerShell 7 的 `pwsh.exe` 来运行：

```powershell
pwsh.exe -ExecutionPolicy Bypass -File .\install.ps1
```

如果缺少 `pwsh.exe`，正常路径是运行 `.\setup.cmd`；它会尝试自动安装 PowerShell 7。手动 fallback：

```powershell
winget install --id Microsoft.PowerShell --source winget
```

或者使用 `.cmd` 封装脚本；它们也会在运行 ADP-OS 前检查 PowerShell 7：

```powershell
.\setup.cmd
.\adpos.cmd quickstart
```

### "Mutagen 0.18.x not found"

**症状：** `adpos doctor` 显示 `[FAIL] Mutagen`。

**修复：** 让 ADP-OS 帮你安装：

```powershell
adpos doctor -FixMutagen
```

这会将 Mutagen 下载并安装到 `.tools\mutagen\mutagen.exe`。如果 GitHub 速度慢，请参阅[操作指南](operations.md)了解离线安装方式。

## 下一步

你的第一个 runtime 已经在运行了。接下来可以：

- **[操作指南](operations.md)** — 日常命令：启动/停止 VM、管理同步、创建快照、运行验证。
- **[排障指南](troubleshooting.md)** — 按症状查找命令的诊断指南。遇到问题时从这里开始。
- **[配置说明](configuration.md)** — 自定义 VM 大小、静态 IP、引导行为和本地覆盖配置。
- **[架构说明](architecture.md)** — 控制平面、runtime fabric 和 workspace fabric 如何协同工作。
- **[工作区](workspaces.md)** — 项目放置位置和如何安全地 dogfood ADP-OS。
- **[安全策略](../../SECURITY.zh-CN.md)** — 了解本地开发安全模型。

想启动全部三个 runtime？在 `frontend` 运行后：

```powershell
adpos up backend
adpos up agent
```

之后如果需要移除全局命令注册，运行：

```powershell
adpos uninstall
```

这只会移除当前用户级别的 `adpos` PATH shim，不会删除 VM、workspace 文件、ISO cache、本地工具、日志或仓库文件。

如果全局 `adpos` 属于另一个 checkout，默认会拒绝卸载。请到所属 checkout 中执行卸载，或在确认要移除该全局绑定时使用 `-Force`。

如果当前 shell 中无法使用 `adpos`，可以在仓库根目录使用 wrapper：

```powershell
.\uninstall.cmd
```
