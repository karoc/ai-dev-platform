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

公开示例位于：

```text
configs/workspace.example.json
```

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
