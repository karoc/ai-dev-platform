# Workspaces

[简体中文](zh-CN/workspaces.md) | English

ADP-OS is the runtime platform. Your application or experiment should usually live in a separate project clone under the ADP workspace root.

## Recommended Layout

Keep the ADP-OS repository separate from the projects you build with it:

```text
D:\Dev\ai-dev-platform              ADP-OS platform repository
%USERPROFILE%\adp-workspaces\agent  Agent runtime workspace root
%USERPROFILE%\adp-workspaces\frontend  Frontend runtime workspace root
%USERPROFILE%\adp-workspaces\backend   Backend runtime workspace root
```

Clone target projects into the runtime workspace that best matches the work:

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone <project-url> my-project
```

After starting sync:

```powershell
.\cli\adp.ps1 sync start agent
```

the project is available in the VM at:

```text
/home/adp/workspace/my-project
```

## Choosing a Runtime

- Use `agent` for AI agent work, large edits, repository scans, builds, validation, and tasks that benefit from snapshots.
- Use `frontend` for JavaScript, UI, browser acceptance testing, and Playwright-based workflows.
- Use `backend` for backend and Python-heavy work.

The `agent` runtime is intentionally larger and higher-IO than the other profiles. Create a snapshot before destructive, broad, or uncertain agent tasks:

```powershell
.\cli\adp.ps1 snapshot create agent before-large-agent-task
```

## Dogfooding ADP-OS

When using ADP-OS to develop ADP-OS itself, prefer a separate workspace clone instead of the maintainer checkout:

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone git@github.com:karoc/ai-dev-platform.git ai-dev-platform-dogfood
```

Use the dogfood clone for runtime workflow experiments. Keep the main platform checkout for release-quality maintenance:

```text
D:\Dev\ai-dev-platform
```

This keeps platform maintenance, user projects, and agent-generated artifacts from mixing in one working tree.
