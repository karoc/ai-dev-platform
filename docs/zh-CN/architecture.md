# 架构

简体中文 | [English](../architecture.md)

ADP-OS 由本地控制平面和运行时 fabric 组成。

```text
Host OS
  -> ADP-OS control plane
  -> Runtime fabric
  -> Workspace fabric
  -> AI coding agents and developer tools
```

当前 MVP 目标：

- 主机：Windows 11。
- 运行时载体：VMware Workstation。
- Guest OS：Ubuntu Server 26.04。
- 工作区同步：Mutagen。
- 自动化：PowerShell 7、OpenSSH、cloud-init、netplan。

## 目录结构

```text
adp-os/
  install.ps1
  cli/
    adp.ps1
    commands/
  core/
    bootstrap/
    config/
    logging/
    runtime/
  adapters/
    windows/
      filesystem/
      mutagen/
      ssh/
      vmware/
    linux/
    mac/
  runtimes/
    vmware/
  bootstrap/
    base/
    frontend/
    backend/
    agent/
  configs/
  docs/
  templates/
```

## 控制平面

CLI 入口是 `cli\adp.ps1`。它加载：

- `core\config\config.ps1`
- `core\logging\logger.ps1`
- Windows filesystem 和 VMware adapters

随后它会分发到 `cli\commands` 下的命令文件。

Core 模块尽量避免直接包含运行时专属行为。主机相关操作放在 `adapters` 下。

## 运行时 Fabric

VMware 集成由 `adapters\windows\vmware\vmware.ps1` 实现。它封装 `vmrun.exe` 并提供：

- VM 启动、停止、挂起和重置。
- VM 状态检测。
- 通过 VMware Tools 和 DHCP lease fallback 获取 guest IP。
- Guest 命令执行和文件复制辅助函数。
- 快照创建、列出、恢复和删除。

VM 创建由 `runtimes\vmware\vm-factory.ps1` 处理：

- 生成 cloud-init user data。
- 生成 seed ISO。
- 重制 Ubuntu 安装 ISO，使启动菜单默认进入 autoinstall。
- 创建 VMDK 和 VMX 文件。
- 启动 VM provisioning 并等待 provisioning marker。

## 引导流程

Bootstrap 编排由 `core\bootstrap\bootstrap.ps1` 实现。

Base bootstrap 安装共享工具：

- Git、curl、wget、jq、tmux、fzf。
- Docker。
- Node.js 和 npm/pnpm。
- Python 3、pip、venv、uv。
- ripgrep 和 fd。

运行时专属 bootstrap 脚本扩展 base runtime：

- `bootstrap\frontend\setup-frontend.sh`
- `bootstrap\backend\setup-backend.sh`
- `bootstrap\agent\setup-agent.sh`

Frontend profile 还会从 `bootstrap\frontend\browser-tools.sh` 安装轻量浏览器验收辅助命令：

```text
adp-frontend-browser-check
adp-frontend-browser-install
```

这些辅助命令只是脚本。浏览器引擎和 Playwright 缓存会按需下载到 VM 内，不会 vendored 到 ADP-OS 仓库。

Bootstrap 脚本是幂等的，并使用 `/home/adp` 下的 marker 文件记录状态。

## 工作区 Fabric

Mutagen 集成由 `adapters\windows\mutagen\mutagen.ps1` 实现。

ADP 为每个运行时创建一个同步 session：

```text
adp-frontend
adp-backend
adp-agent
```

每个 session 同步：

```text
%USERPROFILE%\adp-workspaces\<runtime>
  <-> /home/adp/workspace
```

Mutagen SSH endpoints 使用 ADP 在用户 SSH config 中管理的 Host aliases。

## 快照模型

快照是运行时范围内的 VMware snapshots。CLI 当前暴露：

```powershell
.\cli\adp.ps1 snapshot create <runtime> <name>
.\cli\adp.ps1 restore <runtime> <name>
```

快照创建是防御性的：如果 `vmrun` 超时但之后能看到快照，ADP 会把操作视为成功。
