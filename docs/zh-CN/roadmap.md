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
- Workspace manifests、recipes、本地目录创建、project open/sync/project views、task lifecycle commands、milestone planning、evaluation planning、sync hygiene checks、validation recording、review gates、commit readiness 和 Markdown release evidence。
- 将 dev container metadata detection 作为 runtime 内部项目上下文。
- 通过 `adp capabilities` 提供公开 capability boundary。

## 近期工作

近期工作会先让公开项目更安全、更容易使用，再扩大执行面：

- 提升首次使用信心和 diagnostics。
- 针对缺失工具、路径问题、ISO 放置、网络和 runtime connectivity，保持 command output 可操作。
- 扩展 CLI behavior、configuration shape、documentation links 和 workflow reports 的非破坏性 validation 覆盖。
- 改进 workspace report evidence，让 pull request、release 和 maintainer handoff 更容易 review。
- 随着 command behavior 变化，保持双语文档同步。
- 收紧 artifact hygiene，确保 local state、logs、VM disks、ISOs、downloaded tools 和 private maintainer material 不进入公开提交。

## 工作区编排

Workspace orchestration 是当前主要产品能力。目标是让 ADP-OS 真正服务于项目，而不只是启动 runtime。

当前公开能力：

- Workspace manifests 可以声明 projects、tasks、milestones、evaluations、validation commands、review metadata 和 snapshot intent。
- `workspace create [-Plan]` 用于 manifest 声明的本地项目目录。实际执行只会创建缺失的本地目录；不会 clone repository、启动 runtime、启动 sync、打开 SSH、创建 snapshot、运行 validation、运行 evaluation commands 或运行 Git。
- `workspace open`、`workspace sync` 和 `workspace project` views 会把单个 project entry 转换成本地、runtime、sync、validation 和 evidence handoff 的显式步骤，但不会代替用户执行这些步骤。
- `workspace status`、`workspace dashboard` 和 `workspace report` views 覆盖 runtime、project、sync hygiene、validation、evaluation、milestone、task、review、rollback 和 commit readiness。
- `workspace report -Markdown` 可以生成可复制到 pull request、release 或 maintainer handoff 的 evidence。
- Validation recipes 可以 preview，可以通过 `workspace task validate <task> -Execute` 显式执行，并把结果记录到被忽略的本地 state，供后续 review。
- Snapshot naming 通过非阻塞约定检查绑定 task、milestone 和 rollback intent。
- `.devcontainer/devcontainer.json` 和 `.devcontainer.json` 会作为 runtime 内部项目上下文被检测。

剩余方向：

- 将 project registration 从本地目录创建演进到更安全的 clone/import guidance，但不隐藏 Git 操作。
- 根据真实项目暴露的问题，继续提升 workspace evidence 在 validation、review、rollback 和 sync workflows 中的质量。
- 继续收紧常见技术栈的 generated-artifact sync defaults 和 review ergonomics。
- 探索更强的项目环境集成，同时保持 Docker、Docker Compose 和 dev containers 作为内层工具。

非目标：

- ADP-OS 不应变成 container orchestrator。
- Workspace commands 不应静默安装 packages、下载大型 toolchains、创建 snapshots、运行 validation、stage 文件或 commit changes。
- Agent workflows 不应绕过 source review、rollback checks 或 publication approval。

## Agent 原生开发

ADP-OS 面向 AI-assisted 和 agent-native development，但广泛 autonomous execution 必须受清晰安全边界约束。

当前公开能力：

- Task lifecycle commands 覆盖 prepare、snapshot、run guidance、validate、review、rollback guidance、commit guidance 和 local state marking。
- 面向高风险或 destructive tasks 的 snapshot-first gates；当人类 reviewer 接受缺少 VM snapshot 保护时，可以用显式本地 `checkpoint-waived` state 记录。
- Validation evidence 可以通过显式 task validation execution 记录，并进入 report 或 Markdown release evidence。
- Review bundles 会显示 source-review prompts、sync hygiene、validation results、evaluation links、rollback context 和 commit readiness。
- Milestone 和 evaluation planning surfaces 可以让更广的 agent-native review criteria 可见，但不会执行 evaluation commands。
- Runtime profile 语言会明确 agent elevated IO 和 snapshot 建议。

剩余方向：

- 在 preview、snapshot、validation、review、rollback 和 commit boundaries 经过更多真实项目验证前，继续让 broad task execution 保持 plan-only。
- 在增加 evaluation execution 之前，先用更多项目形态 dogfood evaluation hooks 和 report evidence。
- 基于真实维护者和贡献者 workflow，改进 human review bundles 和 release evidence。
- 只有当 security 和 rollback boundaries 能被解释并测试时，才探索更丰富的 runtime profiles。

## 运行时扩展

ADP-OS 当前面向 Windows 和 VMware Workstation。未来 runtime expansion 应在保持同一套用户可见生命周期的同时，把 host-specific behavior 放到 adapter 后面。

当前已支持和计划中的能力边界，请运行 `.\cli\adp.ps1 capabilities` 或查看[能力边界](capabilities.md)。该边界用于说明今天实际可用的能力；本路线图仍然是方向性说明。

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
