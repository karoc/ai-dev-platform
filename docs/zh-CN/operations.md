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

运行集成检查：

```powershell
.\test-integration.ps1
.\deploy-check.ps1
```

## 启动运行时

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

如果 VM 已存在且正在运行，ADP 会报告当前 IP 并跳过创建。

## 停止运行时

```powershell
.\cli\adp.ps1 stop frontend
```

该命令会先尝试 soft stop，必要时再 hard stop。

## SSH 访问

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

默认地址见 [网络说明](networking.md)。

## 工作区同步

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

## 重新应用网络

```powershell
.\cli\adp.ps1 network apply all
```

编辑 `configs\platform.json` 或 `configs\topology.json` 后使用此命令。
