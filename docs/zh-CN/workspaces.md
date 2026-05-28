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

## Workspace Manifest

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

`workspace status` 同样保持非破坏性。它会报告 manifest 是否已加载、项目路径是否存在、配置的运行时是否已知且已创建、预期 sync session 是否存在、任务快照是已存在还是建议创建，以及 validation 命令是否已声明。它不会创建目录、启动同步、创建快照，也不会运行验证命令。

对于声明了 `requires_snapshot: true` 或高风险 `risk` 值的 task，`workspace status` 还会显示 snapshot-first gate。这个 gate 只做信息提示，不会执行操作，但在大范围 agent 工作前应被视为硬性的操作边界。

查看 workspace dashboard：

```powershell
.\cli\adp.ps1 workspace dashboard
```

`workspace dashboard` 是非破坏性的汇总视图。它会在一个位置汇总 project readiness 和 task lifecycle state，包括路径、运行时、同步、检查点、执行、验证、review、回滚和提交 gate。它不会运行 Git 命令、验证命令、同步命令、快照命令或运行时命令。

对于高风险 task，dashboard 会在配置的 checkpoint 存在前把 execution 标记为 blocked by snapshot gate。这样 agent 开始执行大范围、不确定或破坏性工作前，rollback readiness 会先被明确暴露出来。

## Task Lifecycle

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
- `snapshot`：检查建议快照是否存在，评估 snapshot-first gate，并打印准备好之后要显式运行的快照命令。
- `run`：打印显式执行边界，覆盖 readiness、snapshot-first gate、运行时进入、手动 agent 执行、验证和 review handoff。
- `validate`：打印 manifest 中配置的任务验证命令。带 `-Execute` 时，它只会通过 SSH 在 task 的目标项目目录中运行这些已声明的验证命令。与 `-Execute` 一起加 `-Plan` 可只预览远端 SSH 命令，不会执行。
- `review`：打印 human review bundle，覆盖 readiness、检查点、验证、源码 diff 检查，以及最终 rollback/revise/commit 决策。它还会读取被忽略的本地 validation result，并打印 decision gate：validation passed、validation failed、validation missing，或 blocked by snapshot gate。要求快照的 task 在 checkpoint gate ready 前不应被接受，除非在 ADP-OS 外部显式豁免。
- `rollback`：打印 VM snapshot restore 命令、最近一次记录的 validation context，以及独立的 Git 源码回滚检查，但不会执行。
- `commit`：打印 review、验证、diff 检查、暂存和提交边界，但不会 stage 或 commit 文件。

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

记录内容包括 status、runtime、project、remote path、command count、commands、exit code、失败命令（如果有）、开始时间和完成时间。`workspace dashboard`、`workspace task review` 和 `workspace task rollback` 会显示最近一次记录的 validation result，便于 reviewer 决定 rollback、revise 或 commit。失败的 validation 会记录为 `validation_failed`，成功的 validation 会记录为 `validated`。Dashboard 会在验证通过后把 commit 标记为 `review ready`，在验证失败后标记为 `blocked by validation`。

执行 validation 时，建议设置 `tasks[].project`，让 task 明确指向某个 project。如果省略，ADP-OS 只有在 manifest 中恰好只有一个 project 使用该 task runtime 时才会推断 project。远端执行前会拒绝绝对路径，以及包含 `.` 或 `..` segment 的路径。

记录本地 lifecycle decision：

```powershell
.\cli\adp.ps1 workspace task mark before-large-agent-task prepared
```

`task mark` 只记录本地 task state。它会写入 `adp-workspace.state.json`，平台仓库默认忽略这个文件。state 文件让 `workspace dashboard` 可以显示人类或 agent 已将任务标记为 `prepared`、`checkpointed`、`running`、`validated`、`reviewed`、`rollback` 或 `committed`。执行过的 validation 也会把 validation result 详情写到同一个被忽略的 state 文件。标记状态不会运行任务、创建快照、运行验证、恢复快照、stage 文件或 commit 改动。

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
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
```

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
- `projects[].validation`：人类或 agent 应为项目运行的验证命令。
- `tasks`：可选的具名任务计划。
- `tasks[].project`：可选的 project 名称，来自 `projects[].name`；执行 validation 时建议设置。
- `tasks[].risk`：可选的任务风险标记。`high`、`broad`、`destructive` 和 `uncertain` 默认触发 snapshot-first gate，除非显式覆盖。
- `tasks[].requires_snapshot`：可选 boolean，用于显式要求执行前通过 snapshot-first gate。
- `tasks[].snapshot`：任务开始前建议创建的快照名称。
- `tasks[].validation`：进入 review 或 commit 前预期运行的验证命令。

## Dogfooding ADP-OS

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
