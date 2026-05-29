# 支持说明

简体中文 | [English](SUPPORT.md)

AI Dev Platform OS 当前是早期本地开发 MVP。支持以 best-effort 为主，重点是让公开项目容易理解、可复现，并且安全地试用。

## 从哪里开始

创建 issue 前，先运行与问题相关的非破坏性检查：

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 status
.\cli\adp.ps1 sync status
.\tests\validate.ps1 -Quick
```

可从这些文档入口开始：

- [快速开始](README.zh-CN.md#快速开始)：首次设置和 runtime startup。
- [操作指南](docs/zh-CN/operations.md)：日常命令和 troubleshooting。
- [配置说明](docs/zh-CN/configuration.md)：platform、topology、sync profiles 和 local overrides。
- [网络说明](docs/zh-CN/networking.md)：VMware NAT、static IP 和连接排障。
- [工作区](docs/zh-CN/workspaces.md)：目标项目布局和 workspace task flow。
- [排障](docs/zh-CN/troubleshooting.md)：创建 issue 前按症状查命令。
- [路线图](docs/zh-CN/roadmap.md)：产品方向和计划边界。

## 创建公开 Issue

可通过 GitHub Issues 报告可复现的公开问题：

- Bug reports：commands、diagnostics、VM lifecycle、networking、sync、bootstrap、browser testing、docs 或 workspace behavior。
- Feature requests：描述 user problem 和期望 workflow。
- Usage questions：可以沉淀为可复用公开知识的问题。
- Documentation gaps：说明 setup、operation、validation 或 release readiness 哪里不清楚。

请包含：

- Host OS、PowerShell version、VMware Workstation version 和 ADP-OS commit。
- 你运行的完整命令。
- 最小复现步骤。
- 来自 `doctor`、`status`、`sync status` 或 `tests\validate.ps1` 的相关非敏感输出。
- 是否使用了 `configs\local.json`，以及其中有哪些受支持 section，但不要包含 private paths 或 secrets。

不要包含：

- Secrets、tokens、private SSH keys、cloud credentials 或 customer data。
- VM disks、snapshots、ISO images、downloaded tool archives、browser caches 或大型 logs。
- 不应公开的 private local paths。
- Private maintainer context 或 local assistant state。

## 安全报告

不要在公开 issue 中包含 exploit details、secrets、tokens 或 private keys。

漏洞报告和安全修复处理请遵循[安全策略](SECURITY.zh-CN.md)。

## 使用问题

如果使用问题能沉淀为可复用的公开知识，欢迎提出。建议包含：

- 你想完成什么。
- 涉及哪个 runtime：`frontend`、`backend` 或 `agent`。
- 问题属于 setup、operation、workspace planning、validation、rollback 还是 release readiness。
- 让你产生问题的命令输出，并移除敏感信息。

如果问题来自私有目标项目，请将它缩减为可以公开讨论的 ADP-OS command、manifest shape、runtime state 或 diagnostic behavior。

这类问题请使用 GitHub Usage question template。只有当你有可复现的 ADP-OS failure 时，才使用 Bug report template。

## 范围边界

当前公开支持范围：

- Windows 11 host。
- PowerShell 7。
- VMware Workstation Pro。
- Ubuntu Server 26.04 runtime provisioning。
- Mutagen 0.18.x synchronization。
- ADP-OS CLI、configuration、docs、validation 和 workspace planning behavior。

当前公开范围之外：

- Production 或 multi-tenant deployment。
- 将默认 ADP-OS runtimes 暴露给不可信网络。
- Hosted service operations。
- 响应时间保证。
- 无法缩减为 ADP-OS 行为的私有项目调试。
- Legal、licensing、credential、account 或 cost-bearing infrastructure decisions。

## 维护者预期

维护者应让支持响应保持在项目边界内：

- 优先要求非破坏性 diagnostics。
- 优先使用可复现命令序列，而不是截图。
- 将漏洞问题转到 security process。
- 当支持回答暴露文档缺口时，同时更新英文和简体中文文档。
- 将重复出现的支持摩擦转化为 diagnostics、docs、validation 或 roadmap items。
