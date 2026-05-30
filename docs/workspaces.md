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

`workspace status` is also non-destructive. It reports whether the manifest is loaded, project paths exist, configured runtimes are known and created, expected sync sessions are present, common generated directories are covered by the runtime sync profile, milestone checkpoints are planned, task snapshots already exist or are recommended, and validation commands are declared. It does not create directories, start sync, change sync profiles, delete generated directories, create snapshots, or run validation commands.

For task entries that declare `requires_snapshot: true`, declare `tasks[].milestone` without explicitly setting `requires_snapshot: false`, or use a high-risk `risk` value, `workspace status` also shows a snapshot-first gate. The gate is informational and non-destructive, but it should be treated as a hard operating boundary before broad agent work.

Snapshot names should be tied to task or milestone intent. The recommended task checkpoint format is `before-<task-name>`, for example `before-broad-agent-refactor`. If a checkpoint protects a broader milestone instead of one task, use `milestone-<name>`. `workspace status`, `workspace dashboard`, `workspace report`, and `workspace task snapshot` report snapshot naming as a non-blocking convention check: the snapshot-first gate still controls whether risky work is blocked, but reviewers can see when checkpoint names are less clear than the recommended task or milestone form.

Milestones are optional manifest-level planning records. `milestones[]` can group related tasks, name the runtime checkpoint that protects that group, and make the checkpoint visible in `workspace show`, `workspace plan`, `workspace status`, `workspace dashboard`, `workspace project`, and `workspace report`. Milestone reporting is still non-destructive: ADP-OS prints checkpoint status and explicit `adp snapshot create <runtime> <snapshot>` commands, but it does not create snapshots. Link tasks either from `milestones[].tasks` or from `tasks[].milestone`; using both is allowed and ADP-OS de-duplicates the relationship.

Evaluations are optional manifest-level planning records for agent-native evidence. `evaluations[]` can link related tasks to evaluation metrics and commands, then make that plan visible in `workspace show`, `workspace status`, `workspace dashboard`, `workspace report`, and Markdown release evidence. Evaluation hooks are non-destructive in this release: ADP-OS reports evaluation readiness, metrics, linked tasks, and declared commands, but it does not execute evaluation commands. Link tasks either from `evaluations[].tasks` or from `tasks[].evaluation`; using both is allowed and ADP-OS de-duplicates the relationship. Use evaluation hooks to make review criteria explicit before broad agent work, not as a replacement for validation, source review, rollback, or commit gates.

View the workspace dashboard:

```powershell
.\cli\adp.ps1 workspace dashboard
```

`workspace dashboard` is a non-destructive rollup. It summarizes project readiness, milestone checkpoint status, evaluation hooks, and task lifecycle state in one place, including path, runtime, sync, sync hygiene, checkpoint, execution, validation, evaluation, review, rollback, and commit gates. It does not run Git commands, validation commands, evaluation commands, sync commands, snapshot commands, or runtime commands.

For high-risk tasks, the dashboard marks execution as blocked by the snapshot gate until the configured checkpoint exists. This makes rollback readiness visible before an agent starts large, uncertain, or destructive work.

Create local project directories declared by the manifest:

```powershell
.\cli\adp.ps1 workspace create -Plan
.\cli\adp.ps1 workspace create
```

`workspace create -Plan` previews the local directories that would be created for `projects[]`. `workspace create` creates only missing local project directories resolved from `projects[].path`; it does not clone repositories, start runtimes, start or stop sync, open SSH, create snapshots, run validation, run evaluation commands, run Git, or modify existing project files. If a target path already exists as a directory, it is reported as already present. If a target path exists as a file or resolves to a filesystem root, creation is blocked before any directory is created. Use this command after reviewing `workspace plan` or `workspace recipes`, then use `workspace open`, `workspace sync`, or `workspace project` for the next explicit step.

Open a project from the manifest:

```powershell
.\cli\adp.ps1 workspace open app
.\cli\adp.ps1 workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace open` is a non-destructive open guide. It resolves one `projects[]` entry, prints the local workspace path, remote runtime path, runtime readiness, sync state, sync hygiene, dev container metadata, and copyable local, editor, SSH, sync, and status commands. It does not create directories, open an editor, start a shell, connect over SSH, start sync, start a runtime, or modify files. If the manifest has exactly one project, the project name can be omitted; if it has multiple projects, pass the project name so ADP can avoid guessing.

Inspect project sync guidance from the manifest:

```powershell
.\cli\adp.ps1 workspace sync app
.\cli\adp.ps1 workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace sync` is a non-destructive project-aware sync guide. It resolves one `projects[]` entry, shows whether sync is requested, maps the project back to the runtime-level Mutagen session, reports runtime readiness, sync session status, and sync hygiene, then prints the explicit `adp sync status`, `adp sync start <runtime>`, and `adp sync stop <runtime>` commands to run when you choose. It does not start or stop Mutagen, create directories, start runtimes, connect over SSH, or modify files. If the manifest has exactly one project, the project name can be omitted; if it has multiple projects, pass the project name.

Inspect one project's operational lifecycle:

```powershell
.\cli\adp.ps1 workspace project app
.\cli\adp.ps1 workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
```

`workspace project` is a non-destructive lifecycle view for one manifest project. It combines the project path, runtime readiness, sync session, sync hygiene, dev container metadata, project validation commands, linked tasks, snapshot gates, recorded validation state, and commit readiness into one operating flow. It does not open the project, start a runtime, start or stop sync, create snapshots, run validation, run Git, connect over SSH, or modify files. Use it when you want to see the next safe steps for a project before moving into task-specific commands or release evidence.

View a task delivery report:

```powershell
.\cli\adp.ps1 workspace report
.\cli\adp.ps1 workspace report -Markdown
```

`workspace report` is also non-destructive. It reads the manifest and ignored local state file, then prints a release handoff summary, governance loop, decision queues, milestone checkpoint status, milestone review rollup, validation execution queue, evaluation queue, release decision policy, and stale-task remediation guidance before task-by-task sync hygiene, validation results, evaluation links, review decisions, rollback context, commit readiness, review bundle fields, a source-review checklist, and handoff commands for review, rollback, commit, and source inspection. The summary counts passed, failed, and missing validation results; highlights sync hygiene, snapshot, or validation blockers; lists tasks ready for review or commit; prints the current release gate; and exposes task governance coverage for owner, review cadence, and due date. The governance loop groups tasks by owner, groups tasks by review cadence, and prints an attention queue for blocked, unreviewed, overdue, or near-term work. Decision queues classify tasks into next actions such as review sync ignore, create snapshot, validate now, review now, rollback or revise, and ready to commit, plus release-readiness states such as validation required, review required, release blocked, and release candidate, and milestone queues for grouped task review. The milestone review rollup summarizes each milestone's task count, action mix, release state mix, blocked tasks, validation-required tasks, review-required tasks, ready-to-commit tasks, owners, and due attention so a maintainer can review a milestone without manually scanning every task row. The validation execution queue summarizes each task's recorded validation state, command count, readiness, blockers, plan command, `-Execute -Plan` preview command, and explicit `-Execute` command without running validation. The evaluation queue summarizes each evaluation hook's readiness, runtime, project, cadence, metrics, command count, linked tasks, blockers, and evidence command without running evaluation commands. The release decision policy turns those queues into an overall release decision and names blockers, validation work, review work, release candidates, and governance gaps. A task whose project reports `review ignore` for sync hygiene is treated as release-blocked until the sync profile is reviewed, even if validation and review are otherwise ready. Stale-task remediation lists the owner, cadence, timing, action, and release state for tasks that need attention. Add `-Markdown` to print the same decision state as copyable PR or release evidence, including `Validation Execution Queue`, `Evaluation Queue`, `Milestone Checkpoints`, and `Milestone Review Rollup` tables. Markdown evidence shows repository-relative manifest and state paths when possible; paths outside the repository are reduced to an `outside repository: <file>` marker so local machine directories are not copied into public review surfaces. Use the dashboard to scan overall health; use the report to inspect whether recorded task state is ready for review, rollback, or commit without re-running lifecycle commands. See [Release Readiness](release-readiness.md) for the maintainer checklist and contributor expectations.

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
- `snapshot`: checks whether the recommended snapshot exists, evaluates the snapshot-first gate, reports the snapshot naming convention, and prints the explicit snapshot command to run when ready.
- `run`: prints the explicit execution boundary for readiness, snapshot-first gating, runtime entry, manual agent execution, validation, and review handoff. It does not start an agent, approve broad agent work, record task state, run validation, or make the task commit-ready.
- `validate`: prints the task validation commands from the manifest. With `-Execute`, it runs only those declared validation commands over SSH in the task's target project directory. Add `-Plan` with `-Execute` to preview the remote SSH commands without running them.
- `review`: prints a human review bundle for sync hygiene, readiness, checkpoint, validation, source diff inspection, and final rollback/revise/commit decision. It also reads the ignored local validation result and prints a decision gate: validation passed, validation failed, validation missing, blocked by sync hygiene, or blocked by the snapshot gate. It prints the explicit `task mark <task> reviewed` acceptance command only when the review decision gate is OK; otherwise acceptance is withheld and the output names the gate to resolve first. Tasks should not be accepted while sync hygiene says `review ignore`; tasks that require snapshots should not be accepted until the checkpoint gate is ready or explicitly waived in local ADP-OS state with `task mark <task> checkpoint-waived`.
- `rollback`: prints the latest recorded validation context and separate Git source rollback checks without running them. VM snapshot restore commands are shown only when the snapshot gate is ready. If the checkpoint gate is waived, rollback output states that no VM restore command is printed because no checkpoint was confirmed. After rollback is completed manually, it prints `task mark <task> rollback` so the local lifecycle state can be recorded.
- `commit`: prints a commit-readiness gate, sync hygiene, validation context, review state, diff inspection, and commit boundary without staging or committing files. A task is commit-ready only when sync hygiene is not blocking, validation passed, the snapshot gate is not blocking, and local task state is marked `reviewed` or `committed`. Git staging and commit commands are shown only when that gate is ready. After a commit is created manually, it prints `task mark <task> committed` so the local lifecycle state can be recorded.

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

The recorded result includes status, runtime, project, remote path, command count, commands, exit code, failed command when present, start time, and completion time. `workspace dashboard`, `workspace report`, `workspace task review`, `workspace task rollback`, and `workspace task commit` show the latest recorded validation result so a reviewer can decide whether to rollback, revise, or commit. Failed validation is recorded as `validation_failed`; successful validation is recorded as `validated`. The dashboard uses the same commit-readiness gate as `workspace task commit`: sync hygiene must not be blocking, validation must pass, the snapshot gate must not be blocking, and local state must be `reviewed` or `committed`.

For validation execution, set `tasks[].project` when a task should target a specific project. If omitted, ADP-OS will only infer the project when exactly one manifest project uses the task runtime. Absolute paths and `.` or `..` path segments are rejected before remote execution.

Record a local lifecycle decision:

```powershell
.\cli\adp.ps1 workspace task mark before-large-agent-task prepared
```

`task mark` records local task state only. It writes `adp-workspace.state.json`, which the platform repository ignores by default. The state file lets `workspace status`, `workspace dashboard`, `workspace project`, `workspace report`, and task lifecycle commands show that a human or agent has marked a task as `prepared`, `checkpointed`, `checkpoint-waived`, `running`, `validated`, `reviewed`, `rollback`, or `committed`. Executed validation also writes validation result details to the same ignored state file. Marking state does not run the task, create snapshots, run validation, restore snapshots, stage files, or commit changes.

Lifecycle state is not evidence by itself. `checkpoint-waived` records explicit human acceptance of missing VM snapshot protection; it does not create a snapshot, prove rollback safety, or restore rollback capability. If a real snapshot is later created, the checkpoint gate reports the snapshot as ready; marking `checkpointed` clears the local waiver marker. `running` means manual execution began or was attempted; it does not mean ADP-OS started the agent or approved the work. `validated` is only a local lifecycle note unless executable validation evidence was recorded with `workspace task validate <task> -Execute`. `reviewed` should be used only after human source review accepts the diff, rollback path, snapshot context, and recorded validation evidence. `rollback` and `committed` are also local notes; ADP-OS does not restore snapshots, modify source files, stage files, or run `git commit`.

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
.\cli\adp.ps1 workspace recipes -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

`workspace recipes` is the manifest discovery view. It summarizes project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, starting sync, creating snapshots, running validation, running evaluation commands, running Git, or modifying files. Use it when you want to see the available workflow recipes before choosing a project-specific or task-specific command.

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
- `projects[].devcontainer`: optional hint for projects that use dev container metadata. ADP-OS detects `.devcontainer/devcontainer.json` or `.devcontainer.json` in local project paths and reports it as runtime-internal project metadata; it does not build, start, or install dev containers.
- `projects[].validation`: commands a human or agent should run for the project.
- `milestones`: optional milestone checkpoint plans. Each item groups related task names and can declare a runtime-level snapshot for the group.
- `milestones[].name`: milestone name. The recommended checkpoint name is `milestone-<name>`.
- `milestones[].description`: optional human-readable milestone summary.
- `milestones[].runtime`: optional `frontend`, `backend`, or `agent` runtime. If omitted and all linked tasks use the same runtime, ADP-OS can infer that runtime for milestone reporting.
- `milestones[].snapshot`: optional checkpoint name. If omitted, ADP-OS recommends `milestone-<name>`.
- `milestones[].tasks`: optional task names from `tasks[].name`. Unknown task names fail configuration validation.
- `evaluations`: optional plan-only evaluation hooks. Each item can declare metrics, commands, runtime/project context, cadence, and linked tasks for review evidence.
- `evaluations[].name`: evaluation name.
- `evaluations[].description`: optional human-readable evaluation summary.
- `evaluations[].project`: optional project name from `projects[].name`.
- `evaluations[].runtime`: optional `frontend`, `backend`, or `agent` runtime.
- `evaluations[].cadence`: optional review cadence such as `per-change`, `per-task`, or `weekly`.
- `evaluations[].metrics`: non-empty list of evaluation criteria or metric names.
- `evaluations[].commands`: non-empty list of declared evaluation commands. ADP-OS reports these commands but does not execute them in this release.
- `evaluations[].tasks`: optional task names from `tasks[].name`. Unknown task names fail configuration validation.
- `tasks`: optional named task plans.
- `tasks[].milestone`: optional milestone name from `milestones[].name`. If `requires_snapshot` is not set, a task with `tasks[].milestone` defaults to snapshot-first gating; set `requires_snapshot: false` only when the milestone is for grouping/evidence but the task should not require a checkpoint.
- `tasks[].evaluation`: optional evaluation name from `evaluations[].name`.
- `tasks[].project`: optional project name from `projects[].name`; recommended for validation execution.
- `tasks[].owner`: optional owner or review role for release handoff and source review.
- `tasks[].review_cadence`: optional review rhythm, such as `per-change`, `per-task`, or `weekly`.
- `tasks[].due`: optional due date used by `workspace report` to flag overdue or near-term attention.
- `tasks[].risk`: optional task risk marker. `high`, `broad`, `destructive`, and `uncertain` imply snapshot-first gating unless overridden.
- `tasks[].requires_snapshot`: optional boolean that explicitly requires a snapshot-first gate before execution.
- `tasks[].snapshot`: recommended snapshot name before starting the task. Prefer `before-<task-name>` for task checkpoints or `milestone-<name>` for broader milestone checkpoints.
- `tasks[].validation`: commands expected before review or commit.

When `projects[].sync` is `true`, `workspace show`, `workspace status`, and `workspace dashboard` also run a non-destructive sync hygiene check. The check looks only at the project top level for common generated directories such as `node_modules`, `.venv`, `dist`, `build`, `.next`, `coverage`, `.turbo`, `.cache`, `.pytest_cache`, `.ruff_cache`, test reports, and Python caches, then compares what it finds with the runtime's configured `sync_profile.ignore`. The default frontend, backend, and agent sync profiles already ignore common dependency directories, build outputs, framework caches, browser-test output, Python virtual environments, Python caches, and local ADP/Codex tool state where appropriate. The check reports `covered` when the detected generated directories are already ignored, `clean` when none are present, or `review ignore` when a detected generated directory is not covered by that runtime's sync profile. `review ignore` is a prompt to inspect the runtime sync profile before starting heavy sync work; ADP does not edit sync profiles and never deletes project files.

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

For first-run dogfooding, a minimal POSIX shell project is enough to prove the ADP workspace lifecycle end to end. Start with a tiny project that can be synced, validated, reviewed, and committed without browser downloads or package installation. The goal is to verify the workflow path first, not to maximize project complexity.
