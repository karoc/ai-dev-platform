# 路线图

简体中文 | [English](../roadmap.md)

这份公开路线图说明 ADP-OS 的产品方向，但不公开私有维护计划。它是方向性说明，不是 release 承诺。具体时间取决于验证质量、用户反馈、平台约束和维护能力。

ADP-OS 不是 Docker 替代品。它的长期角色是本地 AI 开发运行时的外层生命周期：provisioning、workspace synchronization、runtime bootstrap、diagnostics、snapshot rollback、validation evidence 和 human review boundaries。Docker、Docker Compose 和 dev containers 仍然是运行时内部工具，ADP 管理的环境应能识别、保留，并最终安全地编排它们。

## 产品方向

ADP-OS 正在朝本地、可复现、agent-native 的开发平台演进：

- Local-first：默认让 source code、task execution、runtime state 和 review evidence 保持在用户控制之下。
- Runtime-backed：对需要真实操作系统、Docker、package installation 和 rollback 的工作负载，使用 VM 或类似 VM 的边界。
- Workspace-aware：把 projects、runtimes、sync sessions、validation recipes、task state、snapshots 和 review gates 作为一个工作流理解。
- Evidence-driven：让 validation output、release readiness、rollback context 和 handoff notes 更容易收集和 review。
- Human-controlled：让 review、commit、publication、credentials、destructive operations 和 cost-bearing infrastructure 保持显式的人类控制边界。
- Compatible：集成 Docker、Docker Compose 和 `devcontainer.json` 等现有项目约定，而不是替代它们。

## 当前阶段

当前公开项目是 Windows VMware MVP 加 open-source hardening：

- Windows PowerShell control plane。
- VMware Workstation runtime factory。
- 面向 `frontend`、`backend` 和 `agent` 的 Ubuntu Server runtimes。
- Mutagen workspace synchronization。
- 静态 VMware NAT networking。
- 面向常用开发工具的 SSH bootstrap。
- Snapshot create、restore、stop、logs、status、diagnostics 和 plan previews。
- 通过 `tests\validate.ps1` 提供共享非破坏性 validation。
- 双语公开文档。
- Workspace manifests、task recipes、validation recording、review gates、commit readiness 和 Markdown release evidence。
- 将 dev container metadata detection 作为 runtime 内部项目上下文。

## 近期工作

近期工作会先让公开项目更安全、更容易使用，再扩大执行面：

- 提升首次使用信心和 diagnostics。
- 针对缺失工具、路径问题、ISO 放置、网络和 runtime connectivity，保持 command output 可操作。
- 扩展 CLI behavior、configuration shape、documentation links 和 workflow reports 的非破坏性 validation 覆盖。
- 改进 workspace report evidence，让 pull request、release 和 maintainer handoff 更容易 review。
- 随着 command behavior 变化，保持双语文档同步。
- 收紧 artifact hygiene，确保 local state、logs、VM disks、ISOs、downloaded tools 和 private maintainer material 不进入公开提交。

## 工作区编排

Workspace orchestration 是下一层主要产品能力。目标是让 ADP-OS 真正服务于项目，而不只是启动 runtime。

计划方向：

- Workspace creation 和 project registration commands。
- Per-project sync lifecycle views。
- Runtime、project、validation 和 task dashboards。
- 可以 preview、显式 execute、record 和 review 的 validation recipes。
- 与 task、milestone 和 rollback intent 绑定的 snapshot naming。
- 明确区分 planning、execution、review、rollback 和 commit。
- 更好支持现有项目环境 metadata，包括 `.devcontainer/devcontainer.json` 和 `.devcontainer.json`。

非目标：

- ADP-OS 不应变成 container orchestrator。
- Workspace commands 不应静默安装 packages、下载大型 toolchains、创建 snapshots、运行 validation、stage 文件或 commit changes。
- Agent workflows 不应绕过 source review、rollback checks 或 publication approval。

## Agent 原生开发

ADP-OS 面向 AI-assisted 和 agent-native development，但广泛 autonomous execution 必须受清晰安全边界约束。

计划方向：

- 让 preparation、execution、validation、review、rollback 和 commit state 显式化的 task lifecycle commands。
- 面向高风险或 destructive tasks 的 snapshot-first gates。
- 可以复制到 pull request 或 release note 的 validation evidence。
- 展示 source-review prompts、validation results、rollback context 和 commit readiness 的 review bundles。
- 清楚说明 workload 是否拥有 elevated IO、package installation、Docker access 或 broad filesystem access 的 runtime profiles。
- 只有当 preview、snapshot、validation、review 和 rollback boundaries 足够强之后，才扩展未来 task execution support。

## 运行时扩展

ADP-OS 当前面向 Windows 和 VMware Workstation。未来 runtime expansion 应在保持同一套用户可见生命周期的同时，把 host-specific behavior 放到 adapter 后面。

候选方向：

- Linux host support。
- macOS host support。
- Hyper-V adapter。
- KVM adapter。
- 在符合 safety model 的场景下支持更轻量的 VM-like 或 container-backed runtimes。

设计约束：

- 将 adapter-specific behavior 保持在 adapter boundaries 内。
- 在不同 host 上保留一致的 runtime lifecycle。
- 不用统一标签掩盖 security tradeoffs。
- 除非未来某个 runtime 明确记录了不同边界，否则 Docker 和 dev containers 仍作为内部 development-environment tools。

## 生态对齐

路线图会有意对齐当前 developer-tooling 的趋势：

- OpenAI Codex 描述了在隔离环境中处理 coding tasks，并提供 repository context、terminal/test evidence 和可 review 输出：<https://openai.com/index/introducing-codex/>。
- GitHub Copilot cloud agent 使用 ephemeral development environments、branches、pull-request workflows 和 visible logs，让 developers 可以 review 并决定工作何时 ready：<https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent>。
- Dev containers 通过 `devcontainer.json` 提供广泛使用的项目级环境格式：<https://containers.dev/>。
- Docker Sandboxes 强调面向 coding agents 的隔离 microVM environments，用于 package installation、Docker、filesystem boundaries 和 host protection：<https://docs.docker.com/ai/sandboxes/>。

这些信号支持 ADP-OS 的产品方向：local/self-managed runtimes、显式边界、Docker-capable inner environments、validation evidence、rollback 和 human review gates。

## 发布与公开

公开更新应遵循 release process：

- 运行 `.\tests\validate.ps1`。
- 当已有翻译文档时，英文和简体中文文档一起更新。
- 当 workflow、validation、release-readiness 或 task behavior 变化时，生成 `adp workspace report -Markdown` evidence。
- 检查 local artifacts、credentials、generated state、VM files、ISO files、downloaded tools 和 private maintainer material。
- 只有 validation 和 review 完成后才 commit。
- 只有 owner 授权后才 push 或 publish。

详细 release boundary 见 [Release Process](release-process.md) 和 [Release Readiness](release-readiness.md)。
