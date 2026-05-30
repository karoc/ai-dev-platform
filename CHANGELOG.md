# Changelog

[简体中文](CHANGELOG.zh-CN.md) | English

All notable public changes to AI Dev Platform OS are documented here.

The project does not yet publish versioned releases. Entries are grouped by date until release tags are introduced.

## 2026-05-30

### Added

- Added `adp network configure-local [-Plan]` to align ignored `configs\local.json` with the detected host `VMnet8` NAT subnet before VM creation. The plan output shows the detected host CIDR, target gateway/DNS, and derived runtime static IPs; apply mode writes only the local ignored override file. `adp up` and `adp doctor` now point users to this command when VMware NAT mismatch blocks first-time VM creation.
- Added explicit local `checkpoint-waived` workspace task state so high-risk tasks can record human acceptance of missing VM snapshot protection in ignored local state. Waived checkpoints are visible in `workspace status`, `workspace dashboard`, `workspace project`, `workspace report`, `workspace task review`, `workspace task rollback`, and `workspace task commit`; they unblock the snapshot-first gate without pretending a VM snapshot exists, and rollback output withholds VM restore commands when no checkpoint was confirmed.
- Added milestone review rollups to `workspace report` and `workspace report -Markdown`, summarizing each milestone's actions, release states, blockers, validation-required tasks, review-required tasks, ready-to-commit tasks, owners, and due attention without running validation or changing runtime state.
- Added a non-destructive validation execution queue to `workspace report` and `workspace report -Markdown`, showing each task's recorded validation state, command count, readiness, blockers, plan command, `-Execute -Plan` preview command, and explicit `-Execute` command without running validation.
- Added plan-only `evaluations[]` workspace hooks plus evaluation queues in `workspace status`, `workspace dashboard`, `workspace report`, and `workspace report -Markdown`, so agent-native review metrics and declared evaluation commands can be included in release evidence without executing evaluation commands.
- Added non-destructive `workspace recipes` output to summarize manifest project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, starting sync, creating snapshots, running validation, running evaluation commands, running Git, or modifying files.
- Added `workspace create [-Plan]` for manifest-declared local project directories. `-Plan` previews directory creation; execution creates only missing local directories and does not clone projects, start sync, start runtimes, open SSH, create snapshots, run validation, run evaluation commands, run Git, or modify existing project files.
- Added non-destructive `adp capabilities` output plus bilingual capabilities documentation to distinguish supported Windows VMware behavior from planned Hyper-V, KVM, macOS, Linux, and container-backed runtime work.
- Tightened first-time autoinstall monitor heartbeats so each repeated line starts with a plain `[install monitor] INSTALLING Ubuntu in VM` headline, then carries `progress=indeterminate`, `user-action=keep-open`, `diagnostics=vmware-console-after-20min`, elapsed/remaining timing, next-check guidance, and readiness signals. This makes the visible log tail read as an active watched installation rather than a stuck IP or SSH probe.

### Changed

- Expanded default frontend, backend, and agent sync profile ignore lists for common dependency directories, build outputs, framework caches, browser-test output, Python virtual environments, Python caches, and local ADP/Codex tool state, reducing the chance that generated artifacts are synchronized before users customize profiles.

## 2026-05-29

### Added

- Added clearer first-time autoinstall progress output with an explicit watched OS-installation phase notice, indeterminate install-monitor heartbeats, `state=installing`, `activity=installing-ubuntu`, `status=watching`, `current-op=readiness-check`, and `wait-mode=watched` status, expected duration and timeout fields, elapsed and remaining timeout time, observed readiness signals, repeated-signal `normal=yes` meaning, visible installing-state framing, readiness-signal wording for IP/SSH probes, next readiness-check guidance, user-action guidance, expected transition guidance, and explicit `auth-pending` wording when SSH is open but the installed-system user/key is not ready.
- Added non-destructive workspace sync hygiene checks so `workspace show`, `workspace status`, `workspace dashboard`, and `workspace report` report whether common generated directories are covered by the runtime sync profile before users start sync-heavy workflows. `workspace report` now includes sync hygiene in release evidence and blocks release-candidate decisions when a task project needs `review ignore`.
- Added non-destructive `workspace open [project-name]` output that resolves a manifest project into local and remote paths, readiness state, and copyable local, editor, SSH, sync, and status commands without opening shells, editors, SSH sessions, runtimes, sync sessions, or files.
- Added non-destructive `workspace sync [project-name]` output that maps a manifest project back to its runtime-level Mutagen session, reports sync readiness and sync hygiene, and prints explicit `adp sync` commands without starting or stopping sync.
- Added non-destructive `workspace project [project-name]` output that summarizes one manifest project's operational lifecycle across open, runtime, sync, validation, linked tasks, snapshot gates, recorded validation, commit readiness, and release evidence handoff.
- Added optional `milestones[]` workspace manifest planning for grouped checkpoint intent. `workspace show`, `workspace plan`, `workspace status`, `workspace dashboard`, `workspace project`, and `workspace report` now surface milestone checkpoint status, milestone snapshot naming, linked tasks, and release-evidence queues without creating snapshots or changing runtime state.
- Added sync hygiene to `workspace report` maintainer checklists and release-readiness documentation so release evidence, release decisions, and maintainer review all treat sync hygiene as the same gate.
- Added sync hygiene gates to `workspace task review` and `workspace task commit`, so single-task review or commit guidance cannot accept or print Git commit commands while the report would block the task with `review sync ignore`.
- Added a non-blocking workspace snapshot naming convention check. `workspace status`, `workspace dashboard`, `workspace report`, `workspace plan`, and `workspace task snapshot` now surface whether `tasks[].snapshot` follows task or milestone intent, recommending `before-<task-name>` for task checkpoints and `milestone-<name>` for broader checkpoints.
- Added stricter review acceptance boundaries so `workspace task review` withholds the `task mark <task> reviewed` command until the review decision gate is OK.
- Updated `workspace dashboard` task commit state to use the same sync hygiene, snapshot, validation, and review gate as `workspace task commit`.
- Added stronger workspace task execution, review handoff, rollback, commit, and local-state boundary output so `workspace task run`, `workspace task review`, `workspace task rollback`, `workspace task commit`, and `workspace task mark` cannot be mistaken for agent execution, validation evidence, review approval, rollback readiness, commit readiness, or completed Git/restore operations.
- Added duplicate running ADP runtime diagnostics so `status` and `doctor` can flag same-name runtime VMX paths from another checkout or stale VM store before users diagnose SSH or networking.
- Added guided stale-networking remediation output that separates rebuild, in-place guest netplan, and administrator-only host-route workaround paths without applying host routes automatically.
- Added VMware NAT host-match diagnostics so `doctor` compares configured NAT settings with the host `VMnet8` network when detectable.
- Added existing-runtime seed network drift diagnostics so `status` and `doctor` can report when a VM was created with an older autoinstall static IP than the current merged configuration.
- Added `tests\validate.ps1` as the shared non-destructive repository validation entry used by CI and local contributors, with `-Quick` and targeted skip switches for local iteration.
- Added CI-backed translated-document pair checks for root public docs and `docs/zh-CN` so English and Simplified Chinese docs do not drift by file presence.
- Added CI-backed artifact hygiene checks for ignored local assistant settings, downloaded tools, logs, snapshot state, workspace state, VM artifacts, ISO files, browser test artifacts, and Windows special files.
- Added CI-backed issue-template checks so support routing, security links, usage questions, and public safety prompts remain present.
- Added CI-backed Markdown anchor validation so local documentation links with `#anchors` fail validation when the target heading is missing.
- Added bilingual release process documentation for validation, evidence, safety checks, commit, and publication boundaries.
- Added bilingual release readiness documentation for release decision policy, stale-task remediation, maintainer checklist, and contributor expectations.
- Added bilingual contributor workflow templates and pull request readiness guidance for workspace task shapes, maintainer review ritual, and release decisions.
- Added a bilingual public roadmap that explains the product direction across workspace orchestration, agent-native development, runtime expansion, ecosystem alignment, and release boundaries.
- Added bilingual support documentation that defines public help channels, diagnostic expectations, security-report boundaries, scope limits, and maintainer response expectations.
- Added bilingual troubleshooting documentation that maps common symptoms to safe diagnostics, preview commands, local override guidance, runtime operations, and support escalation.
- Added GitHub issue routing for support and security links, usage questions, expanded bug diagnostics, and feature-request safety checks.

### Changed

- Updated `adp status` SSH reporting to distinguish `auth-pending` from `unreachable`, reducing confusion during Ubuntu autoinstall and first boot.
- Updated `adp up <runtime>` to block first-time VM creation when the configured VMware NAT CIDR clearly does not match the host `VMnet8` network, preventing new VMs from being installed with unreachable static IPs.
- Updated networking, operations, and troubleshooting documentation in English and Simplified Chinese to explain NAT host matching, seed network drift, and the rebuild or guest-network remediation path for VMs created with stale network settings.
- Reframed the root `build.md` file as a historical implementation brief and added a Simplified Chinese counterpart so the original architecture intent is public-facing instead of prompt-like.
- Added `adp workspace report -Markdown` for copyable pull request, release note, and maintainer handoff evidence, with repository-relative evidence paths and redaction for paths outside the repository.
- Added non-destructive workspace detection for `.devcontainer/devcontainer.json` and `.devcontainer.json` so dev container metadata is visible as runtime-internal project context.
- Expanded non-destructive `adp workspace report` output with governance loop queues, action decision queues, release decision policy, stale-task remediation guidance, and task governance fields.

## 2026-05-28

### Added

- Added top-level `adp status [runtime]` output for runtime state, local config status, configured static IPs, VMware-detected IPs, SSH reachability, sync session presence, and exact connection commands.
- Added CI-backed documentation language-context link checks so translated docs stay in the selected language when translated equivalents exist.
- Added CI-backed configuration schema checks for committed platform, topology, sync profile, local example, and workspace manifest shapes.
- Added non-destructive `adp workspace report` output for release handoff summaries, governance loop queues, action decision queues, release decision policy, stale-task remediation guidance, task governance fields, task validation results, review decisions, rollback context, commit readiness, review bundle fields, a source-review checklist, and handoff commands.
- Added `configs/workspace.recipes.example.json` with copyable workspace recipes for low-risk maintenance, frontend browser acceptance, backend validation, and high-risk agent work with a snapshot-first gate.
- Added explicit `adp workspace task validate <task> -Execute` support for running declared validation commands in the task project over SSH, with `-Execute -Plan` preview.
- Added validation readiness gate output and ignored local validation result recording for executable workspace validation.
- Added workspace review decision gates and rollback validation context based on recorded validation results.
- Added workspace commit-readiness gates based on recorded validation, review state, and snapshot-first gate state.
- Added CI and CLI smoke coverage for the workspace recipes manifest.
- Documented the workspace recipes in English and Simplified Chinese README and workspace docs.

## 2026-05-27

### Added

- Added CI validation for CLI parameter contracts so accepted switches are checked against their execution paths.
- Added non-destructive CLI smoke tests for command dispatch, preview output, and input error boundaries.
- Added non-destructive installer smoke tests for skip switches, ISO diagnostics, temporary local-state writes, and explicit ISO cache behavior.
- Added VMware NAT subnet prerequisite guidance in `doctor`, networking docs, and local override documentation.
- Added stronger first-run dependency diagnostics for VMware disk management, WSL, `xorriso`, ISO remastering, Mutagen version, and ISO shape.
- Added explicit Mutagen remediation through `adp doctor -FixMutagen`, with `-Plan` preview before downloading.
- Added an example workspace manifest and non-destructive `adp workspace init/show/plan` commands.
- Added non-destructive `adp workspace status` readiness output for manifest projects, runtimes, sync, snapshots, and validation commands.
- Added non-destructive `adp workspace dashboard` rollups for project readiness and task lifecycle state.
- Added ignored local `adp-workspace.state.json` lifecycle state recording through `adp workspace task mark`.
- Added snapshot-first task gating for high-risk workspace tasks through `tasks[].risk` and `tasks[].requires_snapshot`.
- Added plan-only workspace task lifecycle commands: `prepare`, `snapshot`, `validate`, and `review`.
- Extended plan-only workspace task lifecycle boundaries with `run`, `rollback`, and `commit`.
- Added `adp doctor -FirstRun` for first-run checklist guidance.
- Added `-Plan` previews for `adp up`, `adp network apply`, and `adp destroy`.
- Added public `SECURITY.md` and `SECURITY.zh-CN.md`.
- Added public `CHANGELOG.md` and `CHANGELOG.zh-CN.md`.
- Added GitHub issue templates for bug reports and feature requests.
- Added a GitHub pull request template.
- Added GitHub Actions CI for non-destructive repository validation.
- Added bilingual public documentation navigation with English and Simplified Chinese docs.
- Added Simplified Chinese documentation under `docs/zh-CN`.
- Added `CONTRIBUTING.zh-CN.md`.
- Added frontend browser acceptance helper commands:
  - `adp-frontend-browser-check`
  - `adp-frontend-browser-install`
- Added browser testing documentation.
- Added `configs/local.example.json` and local config override support for machine-specific paths, VM sizing, networking, credentials, and sync profile changes.
- Added workspace guidance for target project clones and ADP-OS dogfooding.

### Changed

- Updated `adp up` and first-provisioning output to print connection details, including SSH command, SSH alias, workspace path, sync command, and `adp status` follow-up.
- Updated autoinstall readiness checks to try the configured static IP from merged topology/local config before falling back to VMware-detected IPs, so local NAT subnet overrides are used consistently.

- Fixed `adp init <runtime> -SkipProvision` so it now propagates to `adp up -NoProvision` instead of only skipping bootstrap.
- Fixed `adp up <runtime> -NoProvision` so it stops after VM definition creation instead of continuing into bootstrap readiness checks.
- Updated `adp up <runtime> -Plan` so preview output can run without VMware installed when no VM status lookup is needed.
- Fixed CLI process exit code propagation from subcommands so automation and CI can detect command failures.
- Fixed `adp help` so help is defined before the CLI dispatch path calls it.
- Fixed nested command logging so command-to-command execution does not fail when log level state is looked up.
- Fixed `adp logs`, `adp sync start`, and `adp sync stop` to reject unknown runtime names at the command boundary.
- Fixed `install.ps1 -SkipDependencyCheck` and `install.ps1 -SkipVMValidation` so both switches now change the corresponding installer behavior.
- Fixed `adp up <runtime> -IsoPath <path>` so the supplied ISO path is passed through to VM creation instead of falling back to the configured ISO cache.
- Updated README language navigation.
- Updated frontend bootstrap to install lightweight browser helper commands without downloading browsers by default.
- Updated sync and Git ignore rules for browser test reports and Playwright artifacts.
- Reworded the agent runtime startup warning from `DANGER MODE` to a high-IO agent profile notice.
- Updated `adp doctor` to report local config override status.
- Expanded `adp doctor` checks for configuration shape, VMware NAT range, runtime static IP uniqueness, sync profiles, running-runtime SSH reachability, Mutagen version, and Mutagen sessions.

## 2026-05-26

### Added

- Initial open-source release of ADP-OS.
- Windows PowerShell control plane.
- VMware Workstation runtime factory.
- Ubuntu Server 26.04 autoinstall provisioning.
- Frontend, backend, and agent runtime profiles.
- Static VMware NAT networking.
- Mutagen workspace synchronization.
- SSH bootstrap.
- Diagnostics, deployment pre-check, snapshot, restore, stop, logs, and destroy commands.
- Public README, architecture docs, configuration docs, operations docs, networking docs, contributing guide, and MIT license.
