# 生存验证

简体中文 | [English](../survival-validation.md)

本文把 ADP-OS 的生存命题转换成可重复执行的验证流程。它面向维护者、早期用户和评审者，用来在项目继续扩张前验证 ADP-OS 是否解决了真实 Windows AI coding agent 工作流问题。

## 目的

当前命题刻意收窄为：

> ADP-OS 是 Windows-first 的本地 AI coding agent 任务生命周期层，提供回滚和证据。

验证问题是：

> Windows-first 的 AI coding agent 用户是否需要一个带 checkpoint、rollback 和 evidence 的本地任务生命周期层，还是 WSL2、Docker 和 Git 已经足够？

这不是功能巡展，也不是把 ADP-OS 推成通用云开发环境、Docker 替代品、WSL 替代品、VM 管理器或多租户平台。

请把本文和 [10 分钟生存价值演示](demo-script.md) 配套使用。完整逐命令脚本目前以[英文版](../demo-script.md)为准；本文定义谁适合参与、要观察什么、要记录什么反馈，以及如何分类结果。

本文不验证生产可用性、企业治理、安全承诺或所有计划中的 runtime carrier。如果 rollback 和 evidence 路径没有在真实 Windows + VMware 环境中运行或被紧密审阅，也不能算作有效验证。

## 什么算有效信号

有效验证看行为，不看礼貌。

强信号：

- Windows AI coding agent 用户能说出一个 Git rollback 不够用的真实任务。
- 评审者能说明 ADP-OS 是 agent task lifecycle 和 evidence layer，不是 WSL2 或 Docker 替代品。
- 用户运行或紧密跟随 10 分钟 demo，并给出具体反馈。
- 用户提交 GitHub issue、写出详细反馈，或尝试接入 MCP / agent workflow。

弱信号：

- 只说“有意思”，没有后续动作。
- 只有 star，没有反馈。
- 只是对 VM、sandbox 或 MCP 技术好奇，但没有具体 workflow。

负面信号：

- 用户持续认为 WSL2、Docker 和 Git 已经足够。
- evidence export 被认为是 nice-to-have，但不值得付出 setup 成本。
- demo 技术上成功，但用户说不出什么时候会用 ADP-OS。

## 目标评审者

优先找能直接判断问题的人：

| 优先级 | 评审者 | 需要了解什么 |
| --- | --- | --- |
| P0 | 使用 Cursor、Claude Code、Codex、Cline、Hermes 或类似 coding agent 的 Windows 开发者 | 他们是否已经担心 agent 错误、生成文件、Docker state、安装包或审计轨迹 |
| P1 | MCP tool 作者和 agent framework 维护者 | ADP-OS 是否能作为 Windows 本地 sandbox backend |
| P2 | 中国 Windows AI 开发者和独立开发者 | local-first、双语、Windows-first 工具是否降低采用摩擦 |
| P3 | AI code governance、DevEx 或平台工程角色 | evidence export 是否能映射到 review 或 audit workflow |

第一轮验证不要优先面向普通开发者、Linux/macOS-first sandbox 用户或企业采购流程。

## 验证流程

1. **问题访谈**
   询问用户当前如何让 agent 修改本地代码、最担心什么、Git rollback 是否足够，以及本地或云端 sandbox 哪个更适合。

2. **Demo 彩排**
   在准备展示给用户的同一台 Windows + VMware 主机上完整运行 presenter script。记录实际耗时、命令输出偏差，以及 rollback 是否恢复预期文件。

3. **10 分钟 demo**
   使用 [10 分钟生存价值演示](demo-script.md)。demo 必须展示 task checkpoint、模拟 agent 错误、evidence recording、rollback 和 evidence export。

4. **反馈记录**
   记录用户环境、当前 workflow、是否理解与 WSL2/Docker/Git 的区别，以及用户选择的下一步动作。

5. **决策汇总**
   只有在收集到足够行为信号后，才把结果归类为 continue、pause、pivot 或 stop。

## Demo 就绪清单

展示给用户前：

- 在真实 Windows 10/11 主机上运行，且 VMware Workstation 可用并可访问。
- 控制面使用 PowerShell 7。从 stock Windows shell 运行时使用 `.\adp.cmd`；如果机器只有内置 Windows PowerShell 5.1，先运行 `.\setup.cmd`，让用户得到 PowerShell 7 安装路径，而不是直接得到失败的 ADP 命令。
- 使用包含公开文档和 recipes 的 ADP-OS checkout。
- 预先创建好 `agent` runtime；首次 VM 创建不计入 10 分钟窗口。
- 确认 `adp doctor` 在 demo 前报告 0 issues。
- 确认 `adp status agent` 显示 runtime 正在运行且 SSH 可达。
- 确认 `adp sync status` 在 demo 前显示 `agent` session healthy 或 watching。开始用户可见运行前，先停止并重建 stale `adp-agent` session。
- 确认 presenter script 在 VM mutation 和 rollback 前设置 sync fence：破坏性任务前停止 `agent` sync，restore 期间保持 stopped，只在选定 host 或 VM workspace 作为 source of truth 并完成 reconcile 后重启。
- 确认 restore 后 readiness 能通过公开 ADP 命令观察：restore 后 `adp status agent` 必须返回有界状态；如果 runtime stopped，`adp up agent -NoBootstrap` 必须返回，随后 `adp status agent` 必须达到 running + SSH reachable，才能继续直接 SSH 文件检查。
- 创建或确认 demo script 中指定的 snapshot。
- 确认 evidence export 前已经在 manifest workspace root 中生成 `workspace-report.md`。使用公开 recipe manifest 时，该路径是 `configs\workspace-report.md`。
- 用 `adp workspace evidence -Export` 导出真实 evidence ZIP，并验证其中包含 `README.txt`、`snapshot-hashes.json`、`operation-log.json`、`workspace-report.md` 和 `adp-workspace.json`。
- 验证 rollback 会恢复 `README.md`、移除 `generated/output.json`，并回退 `src/main.ts` 的 demo mutation。如果 restore 后 runtime 处于 stopped，先运行 `adp up agent -NoBootstrap` 和 `adp status agent`，再做 SSH 文件检查。
- 记录真实的 restore、`up`、`status` 和 SSH verification 耗时。如果运行需要未写入公开文档的 VMware 手工介入、私有清理，或超过公开排障路径的 host-key 手工处理，这只能算 rehearsal evidence，不能算有效 10 分钟 demo evidence。
- 保留真实耗时，不要把 snapshot 或 restore 的慢操作美化掉。

如果预先创建好的 `agent` VM 仍被显示为 installing，不要继续把这次运行当作正常首次安装。运行 `adp status agent`、`adp doctor` 和 `adp network apply agent -Plan`。一种常见 stale-VM 故障是：旧 guest 已经 provisioned，但它是在静态网络 seed 注入之前创建的，因此会启动到旧 VMware NAT 地址，而 ADP-OS 目标是当前 static IP。这是 network drift / product-readiness 问题，不是有效的 10 分钟 demo 证据。

如果 `adp snapshot create agent <name>` 看起来卡住，不要继续对用户演示，直到 snapshot 被确认。使用 `vmrun listSnapshots` 检查，或等命令返回后重新运行 `adp snapshot create`。如果 snapshot 已存在但 CLI 挂住，应把该彩排记录为产品失败，因为 rollback 和 evidence 是 survival path 的核心。

硬性规则：如果 VMware 不可用，不要运行 survival demo。不要伪造 VMware、snapshot、restore、SSH、evidence chain 或 evidence export 输出。

## 观察清单

demo 过程中记录：

- 环境 precheck 是否通过。
- VMware 是否真实可访问。
- 用户可见运行前 `doctor` 是否报告 0 issues。
- `agent` runtime 是否已经运行。
- `agent` sync session 是否在 demo 前 healthy，并且在 VM mutation 和 restore 期间被 fenced/stopped。
- 是否真实创建或复用了 snapshot。
- agent-style task 前后是否记录了 evidence。
- 任务是否改变了 Git 不能完整清理的内容。
- rollback 是否恢复预期的 runtime 和 workspace 状态；如果 restore 后 runtime stopped，是否先用 `adp up agent -NoBootstrap` 重启后再做 SSH 验证。
- restore 后 readiness 是否通过已记录的 ADP 命令完成，是否出现 `ssh-timeout`、`auth-pending`、`unreachable` 或 recovery 状态，并且这些状态是否被记录而不是隐藏。
- 是否导出了 evidence ZIP，且其中包含预期 5 个条目。
- 参与者是否能解释它和 Git reset、Docker、WSL2、Dev Containers 的区别。
- 是否有命令输出与 presenter script 不一致。

## 参与者问题

优先记录具体回答，不把礼貌性称赞当成验证：

1. 你现在使用什么 AI coding agent？
2. 你当前的操作系统和本地开发环境是什么？
3. 你允许 agent 修改项目前会做什么保护？
4. 你最担心 agent 做错什么？
5. 什么时候 `git reset` 对你已经足够？
6. 什么时候 `git reset` 不够？
7. rollback demo 是否解决了你的真实问题？
8. evidence report 是否解决了你的真实问题？
9. 你能否想到一个真实 workflow 使用 ADP-OS？
10. 什么会阻止你尝试它？

## 反馈记录

每次 session 使用一条记录。如果记录能识别到具体个人，应保存在公开仓库之外。

```yaml
session_id: "YYYYMMDD-NN"
date: "2026-MM-DD"
persona: "P0|P1|P2|P3"
channel: "github|discord|v2ex|call|referral|other"
os: "Windows 10|Windows 11|Other"
agent_tool: "Cursor|Claude Code|Codex|Cline|Hermes|Other|None"
current_sandbox: "none|wsl2|docker|manual-vm-snapshot|manual-backup|cloud-sandbox|other"

pain_agent_mistakes: "high|medium|low|none"
git_enough: "yes|no|sometimes"
wsl2_docker_enough: "yes|no|conditional"
needs_evidence: "high|medium|low|none"

demo_ran: true
demo_duration_minutes: 10
understood_difference: "yes|partial|no"
own_use_case: "specific use case or empty"
top_friction: "setup|vmware|concept|docs|missing integration|not needed|other"

action_star: false
action_issue: false
action_integration_attempt: false
action_detailed_feedback: false
action_requested_followup: false

signal: "strong|moderate|weak|negative"
notes: "Short summary. Avoid secrets, tokens, private code, and personal data."
```

## 决策门槛

把这些门槛当作维护者决策输入。只有证据支持时，才继续进入下一轮：

- 至少 10 个相关目标用户已识别并联系，或已排入联系队列。
- 至少 3 个真实用户运行或紧密查看了 10 分钟 demo。
- 至少 2 个外部 feedback artifact 存在，例如 GitHub issue、详细评论或具体的私下反馈记录。
- 至少 1 个第三方 MCP、agent 或 workflow 集成尝试被识别或启动。
- 至少 3 个用户能复述：ADP-OS 是 agent task lifecycle + rollback + evidence layer，不是 WSL2 或 Docker 替代品。

出现以下情况时，应考虑停止、收缩或转向：

- 找不到 10 个愿意看这个问题的相关用户。
- 多数评审者在看完 rollback 和 evidence 场景后仍认为 WSL2、Docker 和 Git 足够。
- 没有人愿意运行或紧密查看 demo。
- 即使在准备好的机器上，demo 也无法足够快地展示价值。
- evidence report 被持续认为是可有可无的文书工作，而不是 workflow 需求。

## 失败分类

| 失败类型 | 示例 | 解读 |
| --- | --- | --- |
| 环境失败 | VMware 缺失、ISO 缺失、Mutagen 不可用、SSH key 问题、NAT mismatch | setup 摩擦是真实问题。它本身不证明产品命题错误。 |
| 产品失败 | ADP 命令失败、evidence hash chain 断裂、VMware 健康但 restore 失败、restore 后 `status` 无法分类 readiness，或 `stop`/`status`/`up` 没有有界输出 | 修复产品后，才能把该运行作为验证证据。 |
| 定位失败 | 功能可以运行，但参与者不理解为什么有价值 | 先改进 demo、文档或产品表述，不要扩张范围。 |
| 工作流失败 | 参与者理解价值，但即使 ADP 已返回有界状态和公开恢复路径，流程仍太慢或太笨重 | 先降低现有 Windows + VMware 路径摩擦，不要急着新增平台。 |
| 用户匹配失败 | 参与者只需要 Linux shell、普通 Git rollback 或托管云 sandbox | 不把这类结果计为目标用户群的命题失败。 |
| 价值失败 | 用户说“这不就是 VM snapshot 吗”、无法解释 Git 与 ADP rollback 的差异，或拒绝 evidence 价值 | 产品命题或定位失败。这是最严重的信号。 |

## 触达规则

- 只在相关上下文中手动联系。
- 不爬取私人联系方式。
- 不使用 bot 或自动评论。
- 不要求用户提供 token、密码、API key、私钥或私有仓库访问权限。
- 不在验证 session 中收集 telemetry 或 phone home。
- 不伪造 star、issue、testimonial、review 或用户身份。
- 未经明确许可，不公开参与者姓名。
- 诚实说明 ADP-OS 仍处于早期验证阶段。
- 请通过 GitHub Discussions，或维护者在本次验证中提供的反馈渠道提交反馈。Discord server 创建前，不要把 Discord 当成已经上线的官方渠道。

## 范围护栏

生存验证期间，不要把 ADP-OS 扩张成：

- 通用 CDE。
- Docker、Dev Containers 或 WSL2 替代品。
- 泛 VM 管理器。
- Web UI 或多租户企业平台。
- 云 sandbox API 克隆。
- 广泛 runtime provider abstraction，除非用户证据明确要求。

先使用现有 demo 和 evidence surface。产品扩张应跟随证据，而不是先于证据。

## 相关文档

- [10 分钟生存价值演示](demo-script.md)
- [证据链](evidence.md)
- [能力边界](capabilities.md)
- [ADP-OS 与 Docker](positioning.md)
- [工作区](workspaces.md)
- [操作指南](operations.md)
- [排障](troubleshooting.md)
- [发布就绪](release-readiness.md)
