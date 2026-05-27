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

## Workspace Manifest

ADP-OS can keep a lightweight workspace manifest for target projects. The manifest records project paths, the intended runtime, sync intent, validation commands, and task snapshot names.

Create one from the public example:

```powershell
.\cli\adp.ps1 workspace init
```

This creates `adp-workspace.json` in the current platform checkout if it does not already exist. The platform repository ignores that generated file so local experiments do not get committed by accident. If you use a similar manifest inside your own application repository, decide there whether it should be committed.

Inspect the manifest:

```powershell
.\cli\adp.ps1 workspace show
```

Preview the suggested runtime, sync, snapshot, and validation flow:

```powershell
.\cli\adp.ps1 workspace plan
```

`workspace plan` is intentionally non-destructive: it does not clone projects, start or stop VMs, change Mutagen sessions, create snapshots, or run validation commands. It only turns the manifest into an operating plan.

Check workspace readiness:

```powershell
.\cli\adp.ps1 workspace status
```

`workspace status` is also non-destructive. It reports whether the manifest is loaded, project paths exist, configured runtimes are known and created, expected sync sessions are present, task snapshots already exist or are recommended, and validation commands are declared. It does not create directories, start sync, create snapshots, or run validation commands.

## Task Lifecycle

Workspace tasks are the first agent-native workflow surface in ADP-OS. They turn a task entry from the manifest into explicit preparation, checkpoint, validation, and review steps:

```powershell
.\cli\adp.ps1 workspace task prepare before-large-agent-task
.\cli\adp.ps1 workspace task snapshot before-large-agent-task
.\cli\adp.ps1 workspace task validate before-large-agent-task
.\cli\adp.ps1 workspace task review before-large-agent-task
```

The task lifecycle commands are plan-only. They do not start runtimes, change sync sessions, create snapshots, run Git commands, or run validation commands. They print the exact commands and review checklist a human or agent should use next.

- `prepare`: summarizes the task and prints the readiness, runtime, sync, checkpoint, and validation preparation flow.
- `snapshot`: checks whether the recommended snapshot exists and prints the explicit snapshot command to run when ready.
- `validate`: prints the task validation commands from the manifest.
- `review`: prints a human review bundle for readiness, checkpoint, validation, source diff inspection, and final rollback/revise/commit decision.

The public example lives at:

```text
configs/workspace.example.json
```

The initial manifest schema is intentionally small:

- `name`: workspace name.
- `version`: manifest format version.
- `description`: optional human-readable summary.
- `projects`: target projects mapped to ADP runtimes.
- `projects[].path`: project path relative to the workspace root.
- `projects[].runtime`: `frontend`, `backend`, or `agent`.
- `projects[].sync`: whether the project is expected to use ADP sync.
- `projects[].validation`: commands a human or agent should run for the project.
- `tasks`: optional named task plans.
- `tasks[].snapshot`: recommended snapshot name before starting the task.
- `tasks[].validation`: commands expected before review or commit.

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
