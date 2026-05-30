# 工作区

简体中文 | [English](../workspaces.md)

ADP-OS 是运行时平台。你的应用、实验项目或目标仓库通常应该放在 ADP workspace root 下的独立项目 clone 中。

## 推荐布局

将 ADP-OS 仓库和用它开发的项目分开：

```text
D:\Dev\ai-dev-platform                 ADP-OS 平台仓库
%USERPROFILE%\adp-workspaces\agent     Agent 运行时工作区 root
%USERPROFILE%\adp-workspaces\frontend  Frontend 运行时工作区 root
%USERPROFILE%\adp-workspaces\backend   Backend 运行时工作区 root
```

把目标项目 clone 到最匹配的运行时工作区：

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone <project-url> my-project
```

启动同步后：

```powershell
.\cli\adp.ps1 sync start agent
```

VM 中会看到：

```text
/home/adp/workspace/my-project
```

## 选择运行时

- 使用 `agent` 承载 AI agent 工作、大范围修改、仓库扫描、构建、验证，以及适合配合快照的任务。
- 使用 `frontend` 承载 JavaScript、UI、浏览器验收测试和 Playwright 工作流。
- 使用 `backend` 承载后端和 Python-heavy 工作。

`agent` 运行时有意配置得更大，IO 更高。执行破坏性、大范围或不确定的 agent 任务前，建议先创建快照：

```powershell
.\cli\adp.ps1 snapshot create agent before-large-agent-task
```

## 工作区 Manifest

ADP-OS 可以用一个轻量的 workspace manifest 记录目标项目。这个 manifest 会记录项目路径、期望运行时、同步意图、验证命令和任务快照名称。

从公开示例创建 manifest：

```powershell
.\cli\adp.ps1 workspace init
```

如果当前平台 checkout 中还没有 `adp-workspace.json`，该命令会创建一个。平台仓库会忽略这个生成文件，避免本地实验内容被误提交。如果你在自己的应用仓库中使用类似 manifest，是否提交应由该应用仓库自己决定。

查看 manifest：

```powershell
.\cli\adp.ps1 workspace show
```

预览建议的运行时、同步、快照和验证流程：

```powershell
.\cli\adp.ps1 workspace plan
```

`workspace plan` 有意保持非破坏性：它不会 clone 项目、启动或停止 VM、修改 Mutagen session、创建快照，也不会运行验证命令。它只会把 manifest 转换成操作计划。

检查 workspace readiness：

```powershell
.\cli\adp.ps1 workspace status
```

`workspace status` 同样保持非破坏性。它会报告 manifest 是否已加载、项目路径是否存在、配置的运行时是否已知且已创建、预期 sync session 是否存在、常见生成目录是否已被 runtime sync profile 覆盖、milestone checkpoint 是否已规划、任务快照是已存在还是建议创建，以及 validation 命令是否已声明。它不会创建目录、启动同步、修改 sync profiles、删除生成目录、创建快照，也不会运行验证命令。

对于声明了 `requires_snapshot: true`、声明了 `tasks[].milestone` 且没有显式设置 `requires_snapshot: false`，或使用高风险 `risk` 值的 task，`workspace status` 还会显示 snapshot-first gate。这个 gate 只做信息提示，不会执行操作，但在大范围 agent 工作前应被视为硬性的操作边界。

Snapshot 名称应该绑定 task 或 milestone 意图。推荐的 task checkpoint 格式是 `before-<task-name>`，例如 `before-broad-agent-refactor`。如果某个 checkpoint 保护的是更大的 milestone，而不是单个 task，则使用 `milestone-<name>`。`workspace status`、`workspace dashboard`、`workspace report` 和 `workspace task snapshot` 会把 snapshot naming 作为非阻塞约定检查显示出来：真正阻塞高风险工作的仍然是 snapshot-first gate，但 reviewer 可以看到 checkpoint 名称是否不如推荐的 task 或 milestone 格式清晰。

Milestone 是可选的 manifest-level planning record。`milestones[]` 可以把相关 task 分组，命名保护这一组任务的 runtime checkpoint，并让该 checkpoint 出现在 `workspace show`、`workspace plan`、`workspace status`、`workspace dashboard`、`workspace project` 和 `workspace report` 中。Milestone reporting 仍然是非破坏性的：ADP-OS 只打印 checkpoint status 和显式的 `adp snapshot create <runtime> <snapshot>` 命令，不会创建快照。可以从 `milestones[].tasks` 链接 task，也可以从 `tasks[].milestone` 链接 milestone；两者同时使用也可以，ADP-OS 会去重。

Evaluation 是可选的 manifest-level planning record，用于 agent-native evidence。`evaluations[]` 可以把相关 task 关联到 evaluation metrics 和 commands，并让这套计划出现在 `workspace show`、`workspace status`、`workspace dashboard`、`workspace report` 和 Markdown release evidence 中。当前 release 中 evaluation hooks 是非破坏性的：ADP-OS 会报告 evaluation readiness、metrics、linked tasks 和声明的 commands，但不会执行 evaluation commands。可以从 `evaluations[].tasks` 链接 task，也可以从 `tasks[].evaluation` 链接 evaluation；两者同时使用也可以，ADP-OS 会去重。Evaluation hooks 用于在 broad agent work 前显式表达 review criteria，不替代 validation、source review、rollback 或 commit gates。

查看 workspace dashboard：

```powershell
.\cli\adp.ps1 workspace dashboard
```

`workspace dashboard` 是非破坏性的汇总视图。它会在一个位置汇总 project readiness、milestone checkpoint status、evaluation hooks 和 task lifecycle state，包括路径、运行时、同步、sync hygiene、检查点、执行、验证、evaluation、review、回滚和提交 gate。它不会运行 Git 命令、验证命令、evaluation commands、同步命令、快照命令或运行时命令。

对于高风险 task，dashboard 会在配置的 checkpoint 存在前把 execution 标记为 blocked by snapshot gate。这样 agent 开始执行大范围、不确定或破坏性工作前，rollback readiness 会先被明确暴露出来。

创建 manifest 声明的本地项目目录：

```powershell
.\cli\adp.ps1 workspace create -Plan
.\cli\adp.ps1 workspace create
```

`workspace create -Plan` 会预览将为 `projects[]` 创建的本地目录。`workspace create` 只会创建从 `projects[].path` 解析出的缺失本地项目目录；它不会 clone repository、启动 runtime、启动或停止 sync、打开 SSH、创建快照、运行 validation、运行 evaluation commands、运行 Git，也不会修改已有项目文件。如果目标路径已经是目录，会报告为 already present。如果目标路径已经是文件，或者解析成 filesystem root，创建会在任何目录被创建前阻塞。建议先查看 `workspace plan` 或 `workspace recipes`，再使用该命令；之后用 `workspace open`、`workspace sync` 或 `workspace project` 进入下一步显式操作。

从 manifest 打开项目指南：

```powershell
.\cli\adp.ps1 workspace open app
.\cli\adp.ps1 workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace open` 是非破坏性的 open guide。它会解析一个 `projects[]` 条目，打印 local workspace path、remote runtime path、runtime readiness、sync state、sync hygiene、dev container metadata，以及可复制的本地、编辑器、SSH、sync 和 status 命令。它不会创建目录、打开编辑器、启动 shell、通过 SSH 连接、启动 sync、启动 runtime 或修改文件。如果 manifest 只有一个 project，可以省略 project name；如果有多个 project，需要传入 project name，避免 ADP 猜错。

从 manifest 查看项目 sync 指南：

```powershell
.\cli\adp.ps1 workspace sync app
.\cli\adp.ps1 workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace sync` 是非破坏性的 project-aware sync guide。它会解析一个 `projects[]` 条目，显示是否请求 sync，把 project 映射回 runtime-level Mutagen session，报告 runtime readiness、sync session status 和 sync hygiene，然后打印需要用户显式执行的 `adp sync status`、`adp sync start <runtime>` 和 `adp sync stop <runtime>` 命令。它不会启动或停止 Mutagen、创建目录、启动 runtime、通过 SSH 连接或修改文件。如果 manifest 只有一个 project，可以省略 project name；如果有多个 project，需要传入 project name。

查看单个 project 的 operational lifecycle：

```powershell
.\cli\adp.ps1 workspace project app
.\cli\adp.ps1 workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace project` 是针对一个 manifest project 的非破坏性 lifecycle view。它会把 project path、runtime readiness、sync session、sync hygiene、dev container metadata、project validation commands、linked tasks、snapshot gates、recorded validation state 和 commit readiness 汇总成一个 operating flow。它不会打开项目、启动 runtime、启动或停止 sync、创建快照、运行验证、运行 Git、通过 SSH 连接或修改文件。当你想在进入 task-specific commands 或 release evidence 前先看清某个 project 的下一步安全操作时，用这个命令。

查看 task delivery report：

```powershell
.\cli\adp.ps1 workspace report
.\cli\adp.ps1 workspace report -Markdown
```

`workspace report` 同样是非破坏性的。它会读取 manifest 和被忽略的本地 state 文件，先打印 release handoff summary、governance loop、decision queues、milestone checkpoint status、milestone review rollup、validation execution queue、evaluation queue、release decision policy 和 stale-task remediation guidance，再按 task 打印 sync hygiene、validation result、evaluation links、review decision、rollback context、commit readiness、review bundle fields、source-review checklist，以及 review、rollback、commit 和 source inspection 的 handoff commands。Summary 会统计通过、失败和缺失的 validation result，突出 sync hygiene、snapshot 或 validation blocker，列出 ready for review 或 ready to commit 的 task，打印当前 release gate，并暴露 owner、review cadence 和 due date 的 task governance 覆盖情况。Governance loop 会按 owner 分组、按 review cadence 分组，并打印 blocked、未 review、overdue 或近期到期工作的 attention queue。Decision queues 会把 task 分到 review sync ignore、create snapshot、validate now、review now、rollback or revise、ready to commit 等下一步动作，以及 validation required、review required、release blocked、release candidate 等 release-readiness 状态，还会按 milestone 分组显示 task。Milestone review rollup 会汇总每个 milestone 的 task 数量、action 组合、release state 组合、blocked tasks、validation-required tasks、review-required tasks、ready-to-commit tasks、owners 和 due attention，让维护者不用手动扫描所有 task row 就能评审一个 milestone。Validation execution queue 会汇总每个 task 的 recorded validation state、command count、readiness、blockers、plan command、`-Execute -Plan` preview command 和显式 `-Execute` command，但不会运行 validation。Evaluation queue 会汇总每个 evaluation hook 的 readiness、runtime、project、cadence、metrics、command count、linked tasks、blockers 和 evidence command，但不会运行 evaluation commands。Release decision policy 会把这些队列汇总成整体 release decision，并列出 blockers、validation work、review work、release candidates 和 governance gaps。如果 task 对应 project 的 sync hygiene 报告 `review ignore`，即使 validation 和 review 已 ready，该 task 也会被视为 release-blocked，直到 sync profile 已经 review。Stale-task remediation 会列出需要关注 task 的 owner、cadence、timing、action 和 release state。添加 `-Markdown` 可以用同一套 decision state 输出可复制到 PR 或 release 的 evidence，其中包含 `Validation Execution Queue`、`Evaluation Queue`、`Milestone Checkpoints` 和 `Milestone Review Rollup` 表。Markdown evidence 会尽量显示仓库相对的 manifest 和 state path；仓库外路径会缩减成 `outside repository: <file>` 标记，避免把本机目录复制到公开 review surface。Dashboard 用于快速扫描整体健康状态；report 用于在不重新运行 lifecycle 命令的情况下，检查已记录的 task state 是否可以进入 review、rollback 或 commit。维护者 checklist 和贡献者预期见 [Release Readiness](release-readiness.md)。

## 任务生命周期

Workspace task 是 ADP-OS 的第一个 agent-native workflow 入口。它会把 manifest 里的 task 条目转换成明确的准备、检查点、执行、验证、review、回滚和提交边界：

```powershell
.\cli\adp.ps1 workspace task prepare before-large-agent-task
.\cli\adp.ps1 workspace task snapshot before-large-agent-task
.\cli\adp.ps1 workspace task run before-large-agent-task
.\cli\adp.ps1 workspace task validate before-large-agent-task
.\cli\adp.ps1 workspace task review before-large-agent-task
.\cli\adp.ps1 workspace task rollback before-large-agent-task
.\cli\adp.ps1 workspace task commit before-large-agent-task
```

这些 task lifecycle 命令都是 plan-only。它们不会启动运行时、修改 sync session、创建快照、运行 Git 命令，也不会运行验证命令。它们只会打印人类或 agent 下一步应该显式执行的命令和 review checklist。

- `prepare`：汇总任务，并打印 readiness、运行时、同步、检查点和验证准备流程。
- `snapshot`：检查建议快照是否存在，评估 snapshot-first gate，报告 snapshot naming convention，并打印准备好之后要显式运行的快照命令。
- `run`：打印显式执行边界，覆盖 readiness、snapshot-first gate、运行时进入、手动 agent 执行、验证和 review handoff。它不会启动 agent、批准 broad agent work、记录 task state、运行 validation，也不会让 task 变成 commit-ready。
- `validate`：打印 manifest 中配置的任务验证命令。带 `-Execute` 时，它只会通过 SSH 在 task 的目标项目目录中运行这些已声明的验证命令。与 `-Execute` 一起加 `-Plan` 可只预览远端 SSH 命令，不会执行。
- `review`：打印 human review bundle，覆盖 sync hygiene、readiness、检查点、验证、源码 diff 检查，以及最终 rollback/revise/commit 决策。它还会读取被忽略的本地 validation result，并打印 decision gate：validation passed、validation failed、validation missing、blocked by sync hygiene，或 blocked by snapshot gate。只有当 review decision gate OK 时，才会打印显式的 `task mark <task> reviewed` acceptance command；否则 acceptance 会被 withheld，并显示需要先解决的 gate。当 sync hygiene 显示 `review ignore` 时不应接受该 task；要求快照的 task 在 checkpoint gate ready 前不应被接受，除非已用 `task mark <task> checkpoint-waived` 在 ADP-OS 本地 state 中显式豁免。
- `rollback`：打印最近一次记录的 validation context，以及独立的 Git 源码回滚检查，但不会执行。只有 snapshot gate ready 时才会显示 VM snapshot restore 命令。如果 checkpoint gate 已被 waived，rollback 输出会明确说明没有确认过 checkpoint，因此不会打印 VM restore 命令。手动完成 rollback 后，它会打印 `task mark <task> rollback`，用于记录本地 lifecycle state。
- `commit`：打印 commit-readiness gate、sync hygiene、validation context、review state、diff 检查和提交边界，但不会 stage 或 commit 文件。只有 sync hygiene 未阻塞、validation 已通过、snapshot gate 没有阻塞，并且本地 task state 已标记为 `reviewed` 或 `committed` 时，task 才会被视为 commit-ready。Git 暂存和提交命令只会在该 gate ready 时显示。手动创建 commit 后，它会打印 `task mark <task> committed`，用于记录本地 lifecycle state。

Validation execution 有意保持很窄：

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` 会打印 readiness gate 和将要运行的 SSH 命令。`-Execute` 会连接到 task runtime，进入 `/home/adp/workspace/<project-path>`，并按顺序运行每条 `tasks[].validation` 命令。执行前，ADP-OS 会显示 runtime、sync、snapshot gate、project path 和 SSH target readiness。ADP-OS 不会创建快照、启动同步、安装隐藏依赖、下载浏览器 binary（除非你声明的命令自己这么做）、stage 文件或 commit 文件。Review 仍然是单独的显式步骤。

执行 validation 后，结果会记录到被忽略的本地 state 文件：

```text
adp-workspace.state.json
```

记录内容包括 status、runtime、project、remote path、command count、commands、exit code、失败命令（如果有）、开始时间和完成时间。`workspace dashboard`、`workspace report`、`workspace task review`、`workspace task rollback` 和 `workspace task commit` 会显示最近一次记录的 validation result，便于 reviewer 决定 rollback、revise 或 commit。失败的 validation 会记录为 `validation_failed`，成功的 validation 会记录为 `validated`。Dashboard 使用与 `workspace task commit` 相同的 commit-readiness gate：sync hygiene 不能阻塞、validation 必须通过、snapshot gate 不能阻塞，并且本地 state 必须是 `reviewed` 或 `committed`。

执行 validation 时，建议设置 `tasks[].project`，让 task 明确指向某个 project。如果省略，ADP-OS 只有在 manifest 中恰好只有一个 project 使用该 task runtime 时才会推断 project。远端执行前会拒绝绝对路径，以及包含 `.` 或 `..` segment 的路径。

记录本地 lifecycle decision：

```powershell
.\cli\adp.ps1 workspace task mark before-large-agent-task prepared
```

`task mark` 只记录本地 task state。它会写入 `adp-workspace.state.json`，平台仓库默认忽略这个文件。state 文件让 `workspace status`、`workspace dashboard`、`workspace project`、`workspace report` 和 task lifecycle 命令可以显示人类或 agent 已将任务标记为 `prepared`、`checkpointed`、`checkpoint-waived`、`running`、`validated`、`reviewed`、`rollback` 或 `committed`。执行过的 validation 也会把 validation result 详情写到同一个被忽略的 state 文件。标记状态不会运行任务、创建快照、运行验证、恢复快照、stage 文件或 commit 改动。

Lifecycle state 本身不是证据。`checkpoint-waived` 记录人类已经显式接受缺少 VM snapshot 保护的风险；它不会创建快照、证明 rollback safety，也不会恢复 rollback capability。如果后续真实 snapshot 已创建，checkpoint gate 会优先显示 snapshot ready；标记 `checkpointed` 会清除本地 waiver marker。`running` 表示手动执行已经开始或尝试过；不代表 ADP-OS 启动了 agent 或批准了这项工作。`validated` 只是本地 lifecycle note，除非已经通过 `workspace task validate <task> -Execute` 记录了 executable validation evidence。`reviewed` 只应在人类 source review 接受 diff、rollback path、snapshot context 和已记录 validation evidence 后使用。`rollback` 和 `committed` 也只是本地 note；ADP-OS 不会 restore snapshot、修改源码、stage 文件或运行 `git commit`。

公开示例位于：

```text
configs/workspace.example.json
```

如果需要一组更完整、可复制的 workflow，可以使用 recipes manifest：

```text
configs/workspace.recipes.example.json
```

它包含四类常见 task：

- `docs-copy-edit`：低风险文档或小型维护任务。
- `frontend-browser-acceptance`：带 Playwright 浏览器验收验证的前端任务。
- `backend-validation-pass`：带依赖同步、测试和 lint 验证的后端任务。
- `broad-agent-refactor`：高风险 agent 任务，执行前必须先通过 snapshot-first gate。

用非破坏性的方式查看 recipes，不会修改运行时、sync session、快照、文件或验证状态：

```powershell
.\cli\adp.ps1 workspace show -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace recipes -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

`workspace recipes` 是 manifest discovery view。它会汇总 project recipes、task recipes、milestone checkpoints、evaluation hooks 和 evidence commands，但不会 clone project、打开 SSH、启动 sync、创建快照、运行 validation、运行 evaluation commands、运行 Git 或修改文件。当你想先看清 manifest 里有哪些 workflow recipes，再选择 project-specific 或 task-specific command 时，使用这个命令。

使用 task-specific planning commands，让操作边界更明确：

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task run broad-agent-refactor -ManifestPath configs\workspace.recipes.example.json
```

这些 recipes 只是示例。默认情况下，ADP-OS 会从 manifest 打印验证命令，但 workspace planning commands 不会安装 packages、下载浏览器 binary、运行 Playwright、运行 Python 工具、创建快照、恢复快照、stage 文件或 commit 改动。只有显式调用 `workspace task validate -Execute` 时，validation 才会执行。

初始 manifest schema 有意保持精简：

- `name`：workspace 名称。
- `version`：manifest 格式版本。
- `description`：可选的人类可读说明。
- `projects`：映射到 ADP 运行时的目标项目。
- `projects[].path`：相对于 workspace root 的项目路径。
- `projects[].runtime`：`frontend`、`backend` 或 `agent`。
- `projects[].sync`：该项目是否预期使用 ADP sync。
- `projects[].devcontainer`：可选 hint，用于标记使用 dev container metadata 的项目。ADP-OS 会在本地项目路径中识别 `.devcontainer/devcontainer.json` 或 `.devcontainer.json`，并把它报告为 runtime 内部的项目 metadata；它不会 build、start 或 install dev container。
- `projects[].validation`：人类或 agent 应为项目运行的验证命令。
- `milestones`：可选的 milestone checkpoint plans。每一项可以把相关 task 名称分组，并为这一组声明 runtime-level snapshot。
- `milestones[].name`：milestone 名称。推荐 checkpoint 名称是 `milestone-<name>`。
- `milestones[].description`：可选的人类可读 milestone summary。
- `milestones[].runtime`：可选的 `frontend`、`backend` 或 `agent` runtime。如果省略且所有 linked tasks 使用同一个 runtime，ADP-OS 可以在 milestone reporting 中推断该 runtime。
- `milestones[].snapshot`：可选 checkpoint 名称。如果省略，ADP-OS 会推荐 `milestone-<name>`。
- `milestones[].tasks`：可选 task 名称，来自 `tasks[].name`。未知 task 名称会导致配置验证失败。
- `evaluations`：可选的 plan-only evaluation hooks。每一项可以为 review evidence 声明 metrics、commands、runtime/project context、cadence 和 linked tasks。
- `evaluations[].name`：evaluation 名称。
- `evaluations[].description`：可选的人类可读 evaluation summary。
- `evaluations[].project`：可选 project 名称，来自 `projects[].name`。
- `evaluations[].runtime`：可选的 `frontend`、`backend` 或 `agent` runtime。
- `evaluations[].cadence`：可选 review cadence，例如 `per-change`、`per-task` 或 `weekly`。
- `evaluations[].metrics`：非空 evaluation criteria 或 metric names 列表。
- `evaluations[].commands`：非空的声明式 evaluation commands 列表。当前 release 中 ADP-OS 只报告这些 commands，不会执行。
- `evaluations[].tasks`：可选 task 名称，来自 `tasks[].name`。未知 task 名称会导致配置验证失败。
- `tasks`：可选的具名任务计划。
- `tasks[].milestone`：可选 milestone 名称，来自 `milestones[].name`。如果未设置 `requires_snapshot`，带有 `tasks[].milestone` 的 task 默认触发 snapshot-first gate；只有当 milestone 只是用于分组/evidence 且该 task 不应要求 checkpoint 时，才设置 `requires_snapshot: false`。
- `tasks[].evaluation`：可选 evaluation 名称，来自 `evaluations[].name`。
- `tasks[].project`：可选的 project 名称，来自 `projects[].name`；执行 validation 时建议设置。
- `tasks[].owner`：可选的 owner 或 review role，用于 release handoff 和 source review。
- `tasks[].review_cadence`：可选的 review rhythm，例如 `per-change`、`per-task` 或 `weekly`。
- `tasks[].due`：可选 due date，`workspace report` 会用它标记 overdue 或近期需要关注的 task。
- `tasks[].risk`：可选的任务风险标记。`high`、`broad`、`destructive` 和 `uncertain` 默认触发 snapshot-first gate，除非显式覆盖。
- `tasks[].requires_snapshot`：可选 boolean，用于显式要求执行前通过 snapshot-first gate。
- `tasks[].snapshot`：任务开始前建议创建的快照名称。task checkpoint 优先使用 `before-<task-name>`，更大的 milestone checkpoint 使用 `milestone-<name>`。
- `tasks[].validation`：进入 review 或 commit 前预期运行的验证命令。

当 `projects[].sync` 为 `true` 时，`workspace show`、`workspace status` 和 `workspace dashboard` 还会运行非破坏性的 sync hygiene 检查。该检查只查看项目顶层的常见生成目录，例如 `node_modules`、`.venv`、`dist`、`build`、`.next`、`coverage`、`.turbo`、`.cache`、`.pytest_cache`、`.ruff_cache`、测试报告和 Python cache，然后与 runtime 配置的 `sync_profile.ignore` 比对。默认 frontend、backend 和 agent sync profiles 已经覆盖常见依赖目录、构建输出、框架缓存、浏览器测试输出、Python virtual environments、Python caches，以及适用的本地 ADP/Codex 工具状态。当检测到的生成目录已被忽略时会报告 `covered`，没有发现常见生成目录时会报告 `clean`，如果某个生成目录没有被该 runtime 的 sync profile 覆盖，则会报告 `review ignore`。`review ignore` 是在开始重同步工作前检查 runtime sync profile 的提示；ADP 不会编辑 sync profile，也不会删除项目文件。

## 用 ADP-OS 自举开发

使用 ADP-OS 开发 ADP-OS 自身时，建议使用单独的 workspace clone，而不是直接使用维护用 checkout：

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone git@github.com:karoc/ai-dev-platform.git ai-dev-platform-dogfood
```

dogfood clone 用于运行时工作流实验。主平台 checkout 继续用于发布质量的维护：

```text
D:\Dev\ai-dev-platform
```

这样可以避免平台维护、用户项目和 agent 生成产物混在同一个 working tree 中。

对于 first-run dogfood，一个最小的 POSIX shell 项目就足以验证 ADP workspace lifecycle 的整条链路。先从一个足够小但真实的项目开始，确保它的文件可以被 sync、验证、review 和 commit，而不需要下载浏览器或安装额外 packages。只要它有明确的 validation command 和有意义的 diff，shell-only 项目就已经足够。目标是先验证工作流路径，而不是把项目复杂度拉满。
