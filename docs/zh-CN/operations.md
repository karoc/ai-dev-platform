# 操作指南

简体中文 | [English](../operations.md)

本文档覆盖 ADP-OS 的日常操作。

## 健康检查

运行：

```powershell
.\cli\adp.ps1 doctor
```

期望结果：

```text
All checks passed. Platform is healthy.
```

首次使用时可以附加检查清单：

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

`doctor` 会检查平台前置条件、配置结构、本地覆盖状态、VMware 工具、Mutagen 版本、ISO cache、运行时拓扑、静态 IP 唯一性、静态 IP 网段、VM 状态、运行中 VM 的 SSH 可达性，以及 Mutagen sessions。

预览本地 Mutagen 修复：

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
```

确认计划后，再安装经过测试的本地 Mutagen binary：

```powershell
.\cli\adp.ps1 doctor -FixMutagen
```

`-FixMutagen` 会下载官方 Mutagen 0.18.x Windows AMD64 archive，将 `mutagen.exe` 解压到 `.tools\mutagen\mutagen.exe`，并验证安装后的版本。`.tools` 目录已被 Git 忽略，因此下载的 archive 和本地 binary 不会被提交。

运行集成检查：

```powershell
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

`cli-smoke.ps1` 会检查命令分发、非破坏性预览和输入错误边界。它不会创建、启动、停止、同步或销毁 VM。

`install-smoke.ps1` 使用临时 `USERPROFILE` 检查 installer 诊断和本地状态写入。它不会使用真实用户 profile，不会下载依赖，不会验证 VMware，不会创建 VM，也不要求真实 ISO。

Installer 排障开关：

```powershell
.\install.ps1 -SkipDependencyCheck
.\install.ps1 -SkipVMValidation
```

这些开关主要用于受控排障和类似 CI 的验证路径。正常首次安装不建议使用。

`install.ps1` 和 `doctor` 会检查首次创建运行时所需的主机前置条件：

- VMware `vmrun.exe`。
- VMware `vmware-vdiskmanager.exe`。
- WSL 和 WSL `xorriso`。
- ISO remaster 工具。
- Mutagen 0.18.x。
- OpenSSH Client。
- ISO 是否存在以及基本形态。

这些检查会输出修复建议。默认不会下载 VMware、Mutagen、浏览器、ISO 镜像或其他大型二进制文件。Mutagen 安装必须通过 `doctor -FixMutagen` 显式触发。

## 启动运行时

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

如果 VM 已存在且正在运行，ADP 会报告当前 IP 并跳过创建。

启动后，ADP 会打印配置中的连接目标、SSH 命令、SSH alias、workspace path、sync 命令和 status 命令。连接目标来自合并后的配置；如果存在 `configs\local.json`，也会包含其中的覆盖值。

`agent` 运行时可能会打印 high-IO profile 提示。这不是错误；它表示该运行时面向 AI agent 工作负载配置，执行破坏性或大范围任务前建议先创建快照。

不创建、不启动、不 provisioning、不 bootstrap VM，只预览启动计划：

```powershell
.\cli\adp.ps1 up agent -Plan
```

只创建 VM 定义，不启动 OS provisioning 或 bootstrap：

```powershell
.\cli\adp.ps1 up agent -NoProvision
```

初始化平台状态，并创建运行时 VM 定义，但不启动 OS provisioning：

```powershell
.\cli\adp.ps1 init agent -SkipProvision
```

首次创建运行时时，可以从任意位置传入 ISO：

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\Share\ubuntu-26.04-live-server-amd64.iso
```

`-IsoPath` 会直接用于 VM 创建，不需要位于配置的 ISO cache 中。

## 停止运行时

```powershell
.\cli\adp.ps1 stop frontend
```

该命令会先尝试 soft stop，必要时再 hard stop。

## 运行时状态

查看所有运行时状态和连接信息：

```powershell
.\cli\adp.ps1 status
```

查看单个运行时：

```powershell
.\cli\adp.ps1 status frontend
```

`status` 是非破坏性的。它不会创建、启动、停止、同步、创建快照，也不会编辑 guest 文件。它会报告：

- `configs\local.json` 是不存在、为空、已应用，还是使用了不支持的字段。
- 配置的 VMware NAT CIDR 和 gateway。
- 每个运行时的 VM 状态。
- 合并后的 topology 中配置的 static IP。
- VMware 可探测到的 IP（如果可用）。
- 运行中 VM 的 SSH 可达性。
- Mutagen sync session 是否存在。
- 具体 SSH 命令、SSH alias、workspace path 和下一步命令。

如果 VMware 探测到的 IP 与配置的 static IP 不同，ADP 仍会把配置的 static IP 显示为连接目标。这是静态网络的预期行为，也能让你在编辑 `configs\local.json` 修改本机 NAT 网段后直接看到实际使用的地址。

## SSH 访问

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

默认地址见[网络说明](networking.md)。如果你用 `configs\local.json` 覆盖了 `topology.<runtime>.static_ip`，启动后运行 `.\cli\adp.ps1 status <runtime>`，然后连接输出中显示的地址。

## 工作区同步

启动同步前，将目标项目 clone 到匹配的 Windows workspace root 下。推荐布局和 dogfooding 指南见[工作区](workspaces.md)。

启动同步：

```powershell
.\cli\adp.ps1 sync start frontend
```

检查同步：

```powershell
.\cli\adp.ps1 sync status
```

停止同步：

```powershell
.\cli\adp.ps1 sync stop frontend
```

Mutagen sessions 名称：

```text
adp-frontend
adp-backend
adp-agent
```

## Frontend 浏览器测试

Frontend 运行时包含轻量浏览器验收辅助命令。它们不会在 bootstrap 时安装浏览器二进制。

检查就绪状态：

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
```

按需安装 Chromium 支持：

```bash
adp-frontend-browser-install chromium
```

然后从同步工作区运行项目测试：

```bash
cd /home/adp/workspace
pnpm install
pnpm exec playwright test
```

浏览器下载保留在 VM 用户缓存中。`playwright-report`、`test-results` 和 `blob-report` 等生成报告会被 frontend 同步 profile 忽略。

## 快照和恢复

创建 baseline 快照：

```powershell
.\cli\adp.ps1 snapshot create frontend clean
```

恢复：

```powershell
.\cli\adp.ps1 restore frontend clean
```

快照是 VMware snapshots，在运行中的 VM 上可能需要几分钟。ADP 会在超时后验证快照是否存在，以避免误报失败。

## 销毁运行时

```powershell
.\cli\adp.ps1 destroy frontend
```

销毁运行时会删除该运行时的 VM 文件。`%USERPROFILE%\adp-workspaces` 下的工作区数据是独立的。

先预览删除计划：

```powershell
.\cli\adp.ps1 destroy frontend -Plan
```

## 重新应用网络

```powershell
.\cli\adp.ps1 network apply all
```

编辑 `configs\platform.json`、`configs\topology.json`，或 `configs\local.json` 中受支持的 `platform`/`topology` 字段后使用此命令。

可以先预览 guest 网络改动：

```powershell
.\cli\adp.ps1 network apply all -Plan
```
