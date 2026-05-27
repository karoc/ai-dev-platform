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
