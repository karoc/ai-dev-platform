# 变更日志

简体中文 | [English](CHANGELOG.md)

这里记录 AI Dev Platform OS 的重要公开变更。

项目尚未发布版本化 release。在引入 release tags 前，变更按日期分组。

## 2026-05-29

### 新增

- 新增 VMware NAT host-match 诊断，`doctor` 会在可探测时比对配置的 NAT 设置和 host `VMnet8` 网络。
- 新增已有 runtime 的 seed network drift 诊断，`status` 和 `doctor` 可以报告某个 VM 是否是用比当前合并配置更旧的 autoinstall static IP 创建的。
- 新增 `tests\validate.ps1`，作为 CI 和本地贡献者共用的非破坏性仓库验证入口，并提供 `-Quick` 与定向 skip 开关用于本地迭代。
- 新增由 CI 执行的翻译文档成对检查，覆盖根目录公开文档和 `docs/zh-CN`，避免英文和简体中文文档在文件层面漂移。
- 新增由 CI 执行的 artifact hygiene 检查，覆盖被忽略的本地 assistant 设置、下载工具、日志、snapshot state、workspace state、VM artifacts、ISO files、浏览器测试 artifacts 和 Windows special files。
- 新增由 CI 执行的 issue-template 检查，确保 support routing、security links、usage questions 和公开 safety prompts 持续存在。
- 新增由 CI 执行的 Markdown anchor 验证，确保带 `#anchors` 的本地文档链接在目标 heading 缺失时会失败。
- 新增双语 release process 文档，覆盖 validation、evidence、safety checks、commit 和 publication boundaries。
- 新增双语 release readiness 文档，覆盖 release decision policy、stale-task remediation、维护者 checklist 和贡献者预期。
- 新增双语 contributor workflow templates 和 pull request readiness guidance，覆盖 workspace task shapes、维护者 review ritual 和 release decisions。
- 新增双语公开路线图，说明 workspace orchestration、agent-native development、runtime expansion、ecosystem alignment 和 release boundaries 的产品方向。
- 新增双语支持说明，定义公开帮助通道、diagnostics 预期、安全报告边界、范围限制和维护者响应预期。
- 新增双语排障文档，将常见症状映射到安全 diagnostics、preview commands、local override guidance、runtime operations 和 support escalation。
- 新增 GitHub issue routing，覆盖 support/security links、usage questions、扩展 bug diagnostics 和 feature-request safety checks。

### 变更

- 更新 `adp up <runtime>`，当配置的 VMware NAT CIDR 明显不匹配 host `VMnet8` 网络时，会在首次创建 VM 前阻断，避免新 VM 被安装到不可达的 static IP 上。
- 更新英文和简体中文网络、操作、排障文档，说明 NAT host matching、seed network drift，以及使用旧网络配置创建出的 VM 应如何重建或修复 guest 网络。
- 将根目录 `build.md` 调整为历史实现简报，并新增简体中文对应文件，让原始架构意图以公开文档形式呈现，而不是像旧 prompt。
- 新增 `adp workspace report -Markdown`，用于生成可复制到 pull request、release note 和维护者 handoff 的 evidence，并使用仓库相对 evidence path，仓库外路径会被脱敏。
- 新增非破坏性的 workspace dev container metadata 识别，可发现 `.devcontainer/devcontainer.json` 和 `.devcontainer.json`，并将其作为 runtime 内部项目上下文展示。
- 扩展非破坏性的 `adp workspace report` 输出，加入 governance loop queues、action decision queues、release decision policy、stale-task remediation guidance 和 task governance fields。

## 2026-05-28

### 新增

- 新增顶层 `adp status [runtime]` 输出，用于查看 runtime state、local config 状态、配置的 static IP、VMware 探测 IP、SSH 可达性、sync session 是否存在，以及具体连接命令。
- 新增由 CI 执行的文档语言上下文链接检查，确保存在翻译版本时，已选择语言的文档不会意外跳回另一种语言。
- 新增由 CI 执行的配置 schema 检查，覆盖已提交的 platform、topology、sync profile、local example 和 workspace manifest 结构。
- 新增非破坏性的 `adp workspace report` 输出，用于查看 release handoff summary、governance loop queues、action decision queues、release decision policy、stale-task remediation guidance、task governance fields、task validation result、review decision、rollback context、commit readiness、review bundle fields、source-review checklist 和 handoff commands。
- 新增 `configs/workspace.recipes.example.json`，提供可复制的 workspace recipes，覆盖低风险维护、frontend 浏览器验收、backend 验证，以及带 snapshot-first gate 的高风险 agent 工作。
- 新增显式 `adp workspace task validate <task> -Execute`，用于通过 SSH 在 task project 中运行已声明的 validation commands，并支持 `-Execute -Plan` 预览。
- 新增 executable workspace validation 的 readiness gate 输出，以及被忽略的本地 validation result 记录。
- 新增基于已记录 validation result 的 workspace review decision gate 和 rollback validation context。
- 新增基于已记录 validation、review state 和 snapshot-first gate state 的 workspace commit-readiness gate。
- 新增 workspace recipes manifest 的 CI 和 CLI smoke 覆盖。
- 在英文和简体中文 README、workspace 文档中补充 workspace recipes 说明。

## 2026-05-27

### 新增

- 新增 CLI 参数契约 CI 验证，用于检查已接收的开关是否贯通到实际执行路径。
- 新增非破坏性 CLI smoke tests，覆盖命令分发、预览输出和输入错误边界。
- 新增非破坏性 installer smoke tests，覆盖 skip 开关、ISO 诊断、临时本地状态写入和显式 ISO cache 行为。
- 新增 VMware NAT 子网前置说明，覆盖 `doctor`、网络文档和本地覆盖文档。
- 新增更强的首次使用依赖诊断，覆盖 VMware disk manager、WSL、`xorriso`、ISO remaster、Mutagen 版本和 ISO 基本形态。
- 新增显式 Mutagen 修复入口 `adp doctor -FixMutagen`，支持先用 `-Plan` 预览再下载。
- 新增 workspace manifest 示例，以及非破坏性的 `adp workspace init/show/plan` 命令。
- 新增非破坏性的 `adp workspace status` readiness 输出，覆盖 manifest 项目、运行时、同步、快照和验证命令。
- 新增非破坏性的 `adp workspace dashboard` 汇总视图，覆盖项目 readiness 和 task lifecycle state。
- 新增被忽略的本地 `adp-workspace.state.json` lifecycle state 记录，可通过 `adp workspace task mark` 写入。
- 新增面向高风险 workspace task 的 snapshot-first gate，可通过 `tasks[].risk` 和 `tasks[].requires_snapshot` 声明。
- 新增 plan-only workspace task lifecycle 命令：`prepare`、`snapshot`、`validate` 和 `review`。
- 扩展 plan-only workspace task lifecycle 边界，新增 `run`、`rollback` 和 `commit`。
- 新增 `adp doctor -FirstRun`，提供首次使用检查清单。
- 新增 `adp up`、`adp network apply` 和 `adp destroy` 的 `-Plan` 预览。
- 新增公开 `SECURITY.md` 和 `SECURITY.zh-CN.md`。
- 新增公开 `CHANGELOG.md` 和 `CHANGELOG.zh-CN.md`。
- 新增 GitHub bug report 和 feature request issue templates。
- 新增 GitHub pull request template。
- 新增 GitHub Actions CI，用于非破坏性仓库验证。
- 新增英文和简体中文双语公开文档导航。
- 新增 `docs/zh-CN` 下的简体中文文档。
- 新增 `CONTRIBUTING.zh-CN.md`。
- 新增 frontend 浏览器验收辅助命令：
  - `adp-frontend-browser-check`
  - `adp-frontend-browser-install`
- 新增浏览器测试文档。
- 新增 `configs/local.example.json` 和本地配置覆盖支持，用于本机路径、VM 规格、网络、凭据和同步 profile 调整。
- 新增目标项目 clone 和 ADP-OS dogfooding 的工作区指南。

### 变更

- 更新 `adp up` 和首次 provisioning 输出，启动后会打印连接信息，包括 SSH 命令、SSH alias、workspace path、sync 命令和 `adp status` 后续检查命令。
- 更新 autoinstall readiness checks，优先尝试合并后的 topology/local config 中配置的 static IP，再回退到 VMware 探测到的 IP，确保本机 NAT 网段覆盖配置会被一致使用。

- 修复 `adp init <runtime> -SkipProvision`，现在会传递到 `adp up -NoProvision`，不再只是跳过 bootstrap。
- 修复 `adp up <runtime> -NoProvision`，现在创建 VM 定义后会停止，不再继续进入 bootstrap readiness checks。
- 更新 `adp up <runtime> -Plan`，当不需要查询 VM 状态时，预览输出可在未安装 VMware 的环境中运行。
- 修复 CLI 子命令退出码传播，使自动化和 CI 能正确识别命令失败。
- 修复 `adp help`，现在 help 定义会在 CLI dispatch 路径调用前加载。
- 修复嵌套命令日志状态查询，避免命令调用命令时因日志级别状态查找失败。
- 修复 `adp logs`、`adp sync start` 和 `adp sync stop`，现在会在命令边界拒绝未知 runtime 名称。
- 修复 `install.ps1 -SkipDependencyCheck` 和 `install.ps1 -SkipVMValidation`，现在两个开关都会改变对应 installer 行为。
- 修复 `adp up <runtime> -IsoPath <path>`，现在传入的 ISO 路径会正确传递给 VM 创建流程，不再回退到配置的 ISO cache。
- 更新 README 语言导航。
- 更新 frontend bootstrap，使其安装轻量浏览器辅助命令，但默认不下载浏览器。
- 更新同步和 Git ignore 规则，忽略浏览器测试报告和 Playwright 产物。
- 将 agent 运行时启动提示从 `DANGER MODE` 改为 high-IO agent profile 提示。
- 更新 `adp doctor`，报告本地配置覆盖状态。
- 扩展 `adp doctor`，检查配置结构、VMware NAT 网段、运行时静态 IP 唯一性、sync profiles、运行中 VM 的 SSH 可达性、Mutagen 版本和 Mutagen sessions。

## 2026-05-26

### 新增

- ADP-OS 初始开源发布。
- Windows PowerShell 控制平面。
- VMware Workstation 运行时工厂。
- Ubuntu Server 26.04 autoinstall provisioning。
- Frontend、backend 和 agent 运行时 profiles。
- 静态 VMware NAT 网络。
- Mutagen 工作区同步。
- SSH bootstrap。
- Diagnostics、deployment pre-check、snapshot、restore、stop、logs 和 destroy 命令。
- 公开 README、架构文档、配置文档、操作文档、网络文档、贡献指南和 MIT license。
