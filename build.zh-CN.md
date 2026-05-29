# 历史实现简报

简体中文 | [English](build.md)

本文是 AI Dev Platform OS 的历史实现简报，记录最初公开 MVP 的产品和架构意图。

它不是当前安装指南、操作指南、release process 或 roadmap。当前用户应优先阅读：

- [README](README.zh-CN.md)
- [文档首页](docs/zh-CN/README.md)
- [路线图](docs/zh-CN/roadmap.md)
- [操作指南](docs/zh-CN/operations.md)
- [工作区](docs/zh-CN/workspaces.md)
- [发布流程](docs/zh-CN/release-process.md)

## 原始产品意图

AI Dev Platform OS，简称 ADP-OS，最初被设计为本地 AI coding runtime platform：

- Local-first。
- Runtime-oriented。
- Workspace-centric。
- Sandbox-first。
- Multi-agent-ready。
- 面向 AI-assisted 和 agent-native software development。

原始目标不是构建一个小型 VM 管理脚本，而是构建一个本地开发平台：它可以创建隔离 runtime、同步 workspace、针对 AI coding workload 优化，并为高风险工作提供 snapshot rollback。

## 原始架构方向

早期架构方向围绕分层职责展开：

```text
Host OS
  -> ADP-OS control plane
  -> Runtime fabric
  -> Workspace fabric
  -> AI agents
```

设计上，host-specific 行为应放在 adapter boundary 后面，并为 Windows、macOS、Linux、VMware、Hyper-V、KVM、Docker-capable runtimes 和其他 sandbox carriers 预留空间。

## 原始 MVP 范围

第一个 MVP 聚焦：

- Windows 11。
- PowerShell 7。
- VMware Workstation。
- Ubuntu Server runtimes。
- Mutagen workspace synchronization。
- 面向 frontend、backend 和 agent workloads 的 runtime profiles。
- SSH bootstrap。
- Static networking。
- Snapshot 和 rollback workflows。
- Diagnostics。

当前公开实现已经从这份简报继续演进。现有行为以已提交 source、README 和 docs 为准。

## 简报中的非目标

原始简报明确说明 ADP-OS 不只是：

- VM management script。
- Ubuntu installer。
- Docker wrapper。
- 一次性的 development environment setup script。

这仍然是当前公开定位的一部分：Docker 和 dev containers 是 runtime 内部的项目工具；ADP-OS 是外层 runtime lifecycle、synchronization、validation、evidence 和 rollback layer。

## 当前规划边界

主动规划和日常使用应以这些当前文档为准，而不是这份历史简报：

- [路线图](docs/zh-CN/roadmap.md)：公开产品方向。
- [发布就绪](docs/zh-CN/release-readiness.md)：review 和 release decision policy。
- [发布流程](docs/zh-CN/release-process.md)：validation、evidence、safety、commit 和 publication boundary。
- [贡献者工作流](docs/zh-CN/contributor-workflows.md)：task templates 和 review expectations。
