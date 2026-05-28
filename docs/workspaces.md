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

For task entries that declare `requires_snapshot: true` or a high-risk `risk` value, `workspace status` also shows a snapshot-first gate. The gate is informational and non-destructive, but it should be treated as a hard operating boundary before broad agent work.

View the workspace dashboard:

```powershell
.\cli\adp.ps1 workspace dashboard
```

`workspace dashboard` is a non-destructive rollup. It summarizes project readiness and task lifecycle state in one place, including path, runtime, sync, checkpoint, execution, validation, review, rollback, and commit gates. It does not run Git commands, validation commands, sync commands, snapshot commands, or runtime commands.

For high-risk tasks, the dashboard marks execution as blocked by the snapshot gate until the configured checkpoint exists. This makes rollback readiness visible before an agent starts large, uncertain, or destructive work.

## Task Lifecycle

Workspace tasks are the first agent-native workflow surface in ADP-OS. They turn a task entry from the manifest into explicit preparation, checkpoint, execution, validation, review, rollback, and commit boundaries:

```powershell
.\cli\adp.ps1 workspace task prepare before-large-agent-task
.\cli\adp.ps1 workspace task snapshot before-large-agent-task
.\cli\adp.ps1 workspace task run before-large-agent-task
.\cli\adp.ps1 workspace task validate before-large-agent-task
.\cli\adp.ps1 workspace task review before-large-agent-task
.\cli\adp.ps1 workspace task rollback before-large-agent-task
.\cli\adp.ps1 workspace task commit before-large-agent-task
```

The task lifecycle commands are plan-only. They do not start runtimes, change sync sessions, create snapshots, run Git commands, or run validation commands. They print the exact commands and review checklist a human or agent should use next.

- `prepare`: summarizes the task and prints the readiness, runtime, sync, checkpoint, and validation preparation flow.
- `snapshot`: checks whether the recommended snapshot exists, evaluates the snapshot-first gate, and prints the explicit snapshot command to run when ready.
- `run`: prints the explicit execution boundary for readiness, snapshot-first gating, runtime entry, manual agent execution, validation, and review handoff.
- `validate`: prints the task validation commands from the manifest. With `-Execute`, it runs only those declared validation commands over SSH in the task's target project directory. Add `-Plan` with `-Execute` to preview the remote SSH commands without running them.
- `review`: prints a human review bundle for readiness, checkpoint, validation, source diff inspection, and final rollback/revise/commit decision. It also reads the ignored local validation result and prints a decision gate: validation passed, validation failed, validation missing, or blocked by the snapshot gate. Tasks that require snapshots should not be accepted until the checkpoint gate is ready or explicitly waived outside ADP-OS.
- `rollback`: prints the VM snapshot restore command, the latest recorded validation context, and separate Git source rollback checks without running them.
- `commit`: prints the review, validation, diff inspection, staging, and commit boundary without staging or committing files.

Validation execution is intentionally narrow:

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` prints the readiness gate and SSH commands that would run. `-Execute` connects to the task runtime, changes into `/home/adp/workspace/<project-path>`, and runs each `tasks[].validation` command in order. Before execution, ADP-OS displays runtime, sync, snapshot gate, project path, and SSH target readiness. ADP-OS does not create snapshots, start sync, install hidden dependencies, download browser binaries beyond what the declared command itself does, stage files, or commit files. Review remains an explicit separate step.

When validation is executed, the result is recorded in the ignored local state file:

```text
adp-workspace.state.json
```

The recorded result includes status, runtime, project, remote path, command count, commands, exit code, failed command when present, start time, and completion time. `workspace dashboard`, `workspace task review`, and `workspace task rollback` show the latest recorded validation result so a reviewer can decide whether to rollback, revise, or commit. Failed validation is recorded as `validation_failed`; successful validation is recorded as `validated`. The dashboard marks commit as `review ready` after a passed validation result and `blocked by validation` after a failed one.

For validation execution, set `tasks[].project` when a task should target a specific project. If omitted, ADP-OS will only infer the project when exactly one manifest project uses the task runtime. Absolute paths and `.` or `..` path segments are rejected before remote execution.

Record a local lifecycle decision:

```powershell
.\cli\adp.ps1 workspace task mark before-large-agent-task prepared
```

`task mark` records local task state only. It writes `adp-workspace.state.json`, which the platform repository ignores by default. The state file lets `workspace dashboard` show that a human or agent has marked a task as `prepared`, `checkpointed`, `running`, `validated`, `reviewed`, `rollback`, or `committed`. Executed validation also writes validation result details to the same ignored state file. Marking state does not run the task, create snapshots, run validation, restore snapshots, stage files, or commit changes.

The public example lives at:

```text
configs/workspace.example.json
```

For a fuller set of copyable workflows, use the recipes manifest:

```text
configs/workspace.recipes.example.json
```

It includes four common task shapes:

- `docs-copy-edit`: a low-risk documentation or small maintenance task.
- `frontend-browser-acceptance`: a frontend task with Playwright browser acceptance validation.
- `backend-validation-pass`: a backend task with dependency sync, test, and lint validation.
- `broad-agent-refactor`: a high-risk agent task that requires a snapshot-first gate before execution.

Inspect the recipes without changing runtimes, sync sessions, snapshots, files, or validation state:

```powershell
.\cli\adp.ps1 workspace show -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
```

Use task-specific planning commands to make the operating boundary explicit:

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task run broad-agent-refactor -ManifestPath configs\workspace.recipes.example.json
```

These recipes are examples only. By default, ADP-OS prints validation commands from the manifest but does not install packages, download browser binaries, run Playwright, run Python tools, create snapshots, restore snapshots, stage files, or commit changes through workspace planning commands. Validation execution only happens when `workspace task validate` is called with `-Execute`.

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
- `tasks[].project`: optional project name from `projects[].name`; recommended for validation execution.
- `tasks[].risk`: optional task risk marker. `high`, `broad`, `destructive`, and `uncertain` imply snapshot-first gating unless overridden.
- `tasks[].requires_snapshot`: optional boolean that explicitly requires a snapshot-first gate before execution.
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
