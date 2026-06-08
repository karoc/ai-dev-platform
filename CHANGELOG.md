# Changelog

[简体中文](CHANGELOG.zh-CN.md) | English

All notable public changes to AI Dev Platform OS are documented here.

Versions follow [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`). Entries are grouped by release version, then by date within the version. The latest release is at the top.

## [v1.0.0] — 2026-06-04

Initial public release.

### 2026-06-08

### Added

- Added `adpos` as the only user-facing shell command. `setup.cmd` / `setup.ps1` now register a user-level `adpos` shim by default under `%LOCALAPPDATA%\ADP-OS\bin` and add only that bin directory to the user `PATH`.
- Added one-click safe uninstall through `adpos uninstall` and the repository-root `uninstall.cmd` wrapper. The default uninstall removes only the global `adpos` command registration and does not delete VMs, workspaces, ISO cache, local tools, logs, or repository files.
- Improved one-click bootstrap behavior for stock Windows shells. `setup.cmd`, `setup.ps1`, and `install.ps1` now attempt to install PowerShell 7 with `winget` when `pwsh.exe` is missing, then continue setup with PowerShell 7. `uninstall.cmd` can remove the command registration through Windows PowerShell 5.1 when PowerShell 7 is unavailable.
- Added `adpos isolate -Plan [-Namespace <name>]` to preview multi-checkout local isolation overrides without changing `configs\local.json`, VMs, SSH aliases, sync sessions, `PATH`, or the global `adpos` binding.
- Added `adpos isolate -Apply [-Namespace <name>]` to safely write the previewed checkout isolation overrides to the current checkout's ignored `configs\local.json`, preserving unrelated local fields and backing up an existing file first.

### Changed

- Removed the repo-root `adp.cmd` compatibility wrapper and stopped advertising `adp` / `adp.cmd` shell completions. Public docs, PR templates, deploy guidance, and extension docs now use `adpos` or repo-local `.\adpos.cmd`.
- Setup now detects an existing global `adpos` binding through `ADPOS_HOME`, the user/system `PATH`, and the generated shim. Interactive setup asks before replacing a binding to another checkout; non-interactive setup keeps the existing binding unless `-Force` is used, and prints `.\adpos.cmd` guidance for the current checkout, including the local isolation settings and validation commands needed before running VMs from that checkout.

### Fixed

- Aligned first-user support and feedback entry points with the current public state. README badges and Community sections now point users to GitHub Issues, issue templates use the formal `adpos` command, Discord is documented as a setup plan rather than an active support channel, and GitHub Discussions are not advertised until they are enabled.

- Hardened post-restore runtime readiness checks for the survival demo path. ADP-managed SSH probes now use a bounded process timeout, classify `ssh-timeout` separately from `auth-pending` and `unreachable`, avoid stale direct OpenSSH known-hosts state for readiness checks, and keep VMware control operations bounded so `status`, `up -NoBootstrap`, and `stop` do not appear to wait indefinitely on half-ready restored VMs.

- Fixed `adp workspace evidence -Snapshot` and `adp workspace evidence -Export -Path <zip>` when `-ManifestPath` points to an existing manifest. The workspace evidence code now explicitly calls PowerShell's built-in `Resolve-Path` for filesystem paths, uses provider filesystem paths for ZIP input/output, and binds the documented `-Path` alias for exports, preventing survival demo evidence recording from failing with path resolver or provider-qualified path errors.

### 2026-06-05

### Added

- Added Discord community badge to README (English and 简体中文) with setup guide link, and updated Discord setup guides with a quick-reference server creation checklist. The badge and invite infrastructure are ready — the Discord server link is a placeholder pending server creation.

- Added sync recovery diagnostics for three edge cases exposed by dogfooding: Mutagen one-sided root emptying protection, stale global same-name sessions across clones, and pre-runtime stale session cleanup. `Get-SyncSessionRecoveryInfo` in `adapters/windows/mutagen/mutagen.ps1` classifies sync recovery scenarios with structured recovery steps. `adp status`, `adp doctor`, and `adp sync status` now detect and label specific recovery scenarios (root-emptying, stale-before-creation, wrong-local-endpoint, wrong-remote-endpoint, unhealthy-session) with bilingual diagnostic output including scenario titles, detail descriptions, numbered recovery steps, and explicit safe-cleanup notes. Bilingual troubleshooting docs (`docs/troubleshooting.md`, `docs/zh-CN/troubleshooting.md`) expanded with dedicated recovery sections: "Stale Sessions Across Clones" and "Pre-Runtime Stale Session Cleanup" with diagnostic commands and recovery paths. Root-emptying detection now identifies the condition explicitly instead of reporting generic `unhealthy`.

- Added community infrastructure: installation help issue template (`.github/ISSUE_TEMPLATE/install_help.yml`), enhanced CONTRIBUTING.md with step-by-step development environment setup and PR process, Discord community setup guide (`docs/discord-setup.md`, `docs/zh-CN/discord-setup.md`) with channel structure and community guidelines, and demo video script with storyboard (`docs/demo-script.md`). Added Community section to README and bilingual docs index.

- Added `setup.ps1` — a root-level one-click bootstrap script that chains prerequisite scanning, ISO download, platform install, init, and doctor into a single command. After cloning, users run `.\setup.ps1` (instead of `.\cli\adp.ps1 quickstart`) for a simpler first-run experience. Supports `-IsoPath`, `-SkipIsoDownload`, `-NonInteractive`, and `-Force` flags. Updated README (English and 简体中文), getting-started guides, and CLI smoke tests.

### 2026-06-04

### Added

- Added Copilot SDK integration guide (`docs/copilot-sdk-integration.md` in English and Simplified Chinese). Documents how to load ADP-OS as an MCP server in GitHub Copilot Agent SDK sessions. Includes Python and TypeScript quick-start examples, environment variable reference, 18-tool catalog, plan-only safety defaults, and permission handler patterns. (Copilot SDK is natively compatible — no ADP-OS code changes required.)
- Added circuit breaker module (`core/utility/circuit-breaker.ps1`) with `New-CircuitBreaker`, `Test-CircuitBreaker`, `Reset-CircuitBreaker`, and `Get-CircuitBreakerSummary` functions. Tracks consecutive identical error keys and opens the circuit when the same error repeats MaxConsecutiveErrors times — prevents infinite retry loops in long-running operations.
- Added circuit breaker integration to `Wait-AutoinstallComplete` in `runtimes/vmware/vm-factory.ps1`. Monitors readiness signal categories (`no-guest-ip`, `auth-pending`, `ssh-not-ready`, `provision-not-ready`, etc.) during Ubuntu autoinstall. When the same error category persists beyond the configurable threshold (`-AutoinstallCircuitBreakerMinutes`, default 20min), the circuit opens: retries stop, a bilingual warning is emitted, and the function returns to allow operator investigation. Prevents agents from looping indefinitely on a stuck VM install.
- Added SSH key lifecycle documentation to operations and troubleshooting guides in English and Simplified Chinese. The new docs cover key location (`%USERPROFILE%\\.ssh\\adp-os\\`), key format (ed25519, no passphrase), automatic first-time creation, regeneration with backup and VM-impact warnings, key security, direct SSH/scp usage, and troubleshooting for `key-missing`, `auth-pending`, `Permission denied`, `bad permissions`, deleted keys, and multi-user setups. (Phase 2 roadmap item.)
- Added `adp validate` command as a standalone CLI entry point for the shared repository validation suite. Supports `-Quick`, `-SkipCliSmoke`, `-SkipInstallerSmoke`, and `-SkipShellSyntax` flags with bilingual output. (Phase 2 roadmap item.)
- Localized remaining user-facing diagnostic output in `adp doctor`: network drift remediation options, VMware/xorriso guidance, Mutagen remediation plan and installation details, duplicate VM warnings, stale session cleanup guidance, and issue listing. English and Simplified Chinese text is now consistent across all `adp doctor` output paths.
- Localized `adp workspace report`, `adp workspace recipes`, and all workspace report sub-sections (release handoff summary, governance loop, decision queues, milestone checkpoints, milestone review rollup, validation execution queue, evaluation queue, release decision policy, stale-task remediation, and per-task report bundles) with bilingual output using Write-UIHost. Section headers, field labels, boundary statements, checklist items, and handoff commands now respond to `ADP_LANG=zh-CN`.
- Localized remaining user-facing data labels in `adp status` (ssh, running VMX, sync, VMX, connect, alias) and `adp up` connection summary (IP, SSH, Alias, Workspace, Sync, Status, Doctor, CPU/RAM/Disk, VMX, ISO). All CLI output labels now respect the configured UI language preference.
- Localized remaining user-facing output in `adp network`: seed-network drift detection messages, in-place netplan fix guidance, rebuild/host-route workaround options, plan-preview operation steps (verify SSH, upload, install, wait, update Mutagen alias), and the static-IP activation success message. English and Simplified Chinese text is now consistent across the `network apply` plan-only output and `network configure-local` paths.
- Began bilingual localization of `adp workspace` entry commands. The dispatch section and five entry-command surfaces now use `Write-UIHost` for consistent language selection: `workspace show`/`plan` (Write-WorkspaceSummary), `workspace create` (Write-WorkspaceCreate), `workspace open` (Write-WorkspaceOpen), and `workspace sync` (Write-WorkspaceSyncGuide). The shared `Write-WorkspaceCheck` helper now also supports bilingual output with optional `-ChineseName` and `-ChineseDetail` parameters.
- Continued bilingual localization of `adp workspace` with `workspace status` (Write-WorkspaceStatus), covering manifest information, project readiness, milestones, evaluations, and task lifecycle fields. All user-facing labels, section headers, and check names in `workspace status` now respond to the configured UI language. Remaining workspace surfaces (dashboard, report, recipes, project, task lifecycle) will follow.
- Continued bilingual localization of `adp workspace` with `workspace dashboard` (Write-WorkspaceDashboard), covering section headers (Overview, Project readiness, Milestone checkpoints, Evaluation hooks, Task lifecycle), check names (manifest, state, projects, milestones, evaluations, tasks), empty-state messages, and task lifecycle command hints (prepare, run, review). All dashboard output now responds to the configured UI language preference. Remaining workspace surfaces (report, recipes, project, task lifecycle) will follow.
- Completed bilingual localization of all remaining Write-Host calls in `workspace.ps1`: usage/help examples (Show-WorkspaceUsage), review/commit decision next-step lines (Write-WorkspaceReviewDecision, Write-WorkspaceCommitDecision), validation detail lines (Write-WorkspaceValidationDetailLines), checkpoint header (Write-WorkspaceTaskSnapshot), and all task mark boundary messages and state display (Write-WorkspaceTaskMark). All `adp workspace` user-facing output now uses `Write-UIHost` with English and Simplified Chinese support (521 Write-UIHost calls, zero Write-Host).
- Added MCP (Model Context Protocol) server for ADP-OS at `cli/mcp/server.py`. Exposes 11 tools for agent-native sandbox orchestration: `adp_status`, `adp_doctor`, `adp_workspace_list`, `adp_workspace_create`, `adp_workspace_open`, `adp_workspace_sync`, `adp_workspace_status`, `adp_workspace_recipes`, `adp_sync_status`, `adp_sync_stop`, and `adp_capabilities`. The server invokes ADP-OS PowerShell CLI via `pwsh.exe` subprocess calls and communicates over stdio using FastMCP. Includes `README.md` with setup and configuration guidance for MCP clients such as Claude Desktop.
- Extended MCP server from 11 to 18 tools with runtime management, workspace lifecycle, and close support. New tools: `adp_up` (start VM, plan-only default), `adp_down` (destroy VM, plan-only default), `adp_stop` (graceful shutdown), `adp_workspace_close` (stop sync for a project's runtime, plan-only default), `adp_workspace_project` (single-project lifecycle view), `adp_workspace_dashboard` (task lifecycle overview), and `adp_workspace_report` (Markdown release evidence). Updated `README.md` with Claude Desktop setup instructions and troubleshooting.
- Added MCP server test suite at `tests/test-mcp-server.py` with 14 tests covering module import, tool registration (18 tools verified), output formatting (success, stderr, failure, empty, timeout), manifest loading, project-to-runtime resolution, path resolution, pwsh detection, and tool signature defaults.
- Added JSON structured output to MCP server. All 18 tools now return structured dicts (with `_text`, `_exit_code`, `_success` metadata fields) instead of plain text strings. Platform tools (`adp_status`, `adp_doctor`, `adp_capabilities`) and workspace/runtime tools (`adp_workspace_list`, `adp_sync_status`) include command-specific parsed fields for programmatic consumption by agents. Added 9 new tests for structured output and parsing (23 total). Updated `cli/mcp/README.md` to document structured response format.
- Added `--help` long option support to all subcommands. `adp --help`, `adp help`, and `adp <command> --help` now all work (also `-Help` and `-?` short forms).
- Added `adp version` command and `--version` global flag. Reports version from `VERSION` file or falls back to `git describe` for dev builds.
- Added `adp.cmd` wrapper at project root so users can type `adp <command>` instead of `.\\cli\\adp.ps1 <command>`.
- Added `adp run <runtime>` command for one-command runtime creation. Combines `init` → `up` → `sync start` → `status` into a single command like `docker run` or `daytona create`. Supports `-IsoPath`, `-Plan`, `-NoBootstrap`, `-NoProvision`, and `-NoSync` flags with bilingual output.
- Added `adp completion <powershell|bash>` command to generate shell tab completion scripts. PowerShell output uses `Register-ArgumentCompleter`; bash output uses `complete -F _adp_completion adp`. Bilingual usage messaging.
- Added `-Json` flag to `adp status` for machine-readable JSON output. When active, status returns structured JSON with local config, network, SSH key path, and per-runtime objects (status, IPs, SSH, sync, workspace, VMX, connection command, alias, port, network drift, duplicate VM detection). Suppresses all human-readable formatting. The flag can be set globally via `adp -Json <cmd>` or locally via `adp status -Json`.
- Documented `local` alias for `adp network configure-local` in CLI help text. The alias already existed in `network.ps1` (line 13) but was undocumented in `adp help` output.
- Added `adp serve` health check HTTP server (`cli/commands/serve.ps1`). Starts a lightweight HTTP server using .NET HttpListener, exposing `GET /health` with JSON runtime status and sync health. Supports `-Port` (default 9080), `-Public` (all interfaces), and `-Json` (one-shot health report without starting server). Health endpoint reports VM states (running/stopped/not-created), sync session health (healthy/present/unhealthy/not-started), and overall platform health (healthy/degraded/unhealthy/no-runtimes). Includes CORS headers for cross-origin monitoring access.

### Changed

- Unified flag naming: `adp init -SkipProvision` renamed to `-NoProvision` to match `adp up -NoProvision`. Updated all references in CLI help, README, docs, and tests. Backward incompatible but improves consistency.

### Fixed

- Fixed `Test-WSLCommand` PowerShell pipeline leak in `install.ps1`, `cli/commands/doctor.ps1`, and `runtimes/vmware/vm-factory.ps1` where `wsl.exe` shim stdout leaked into function return values, corrupting the boolean result into `Object[]` and causing `Cannot convert value "System.Object[]" to type "System.Boolean"` errors in CI. External command output is now captured with `$null = &` to prevent pipeline pollution.
- Hardened test infrastructure so `Start-Process -FilePath "pwsh"` in `local-config-boundary.ps1`, `cli-smoke.ps1`, and `install-smoke.ps1` resolves the full pwsh path from the current process rather than relying on bare `pwsh` being in PATH, which fails on some CI runner instances.

### 2026-05-31

### Changed

- Centralized runtime profile wording in shared configuration helpers and added an explicit `topology.<runtime>.profile` field. The agent runtime now renders as `agent/high-IO` / `Agent 高 IO` in startup and installer output instead of the retired danger/high-risk runtime labels, while snapshot-first language remains reserved for destructive or broad task work.
- Updated the agent bootstrap marker from the retired danger-mode wording to `AGENT_PROFILE.txt`, and added regression checks so current installer, startup, and bootstrap paths do not reintroduce the retired runtime danger labels.
- Fixed WSL `xorriso` argument passing during autoinstall ISO remastering. `adp up <runtime>` no longer invokes WSL in a way that can pass only the bare `xorriso` command and trigger usage output instead of creating the autoinstall ISO.
- Localized the nested VMware VM factory autoinstall monitor used by `adp up <runtime>`, so Simplified Chinese UI settings now carry through the long Ubuntu installation wait instead of falling back to English heartbeat text. The monitor now also uses PowerShell `Write-Progress` as an indeterminate activity indicator while keeping copyable heartbeat logs and avoiding fake install percentages.

### 2026-05-30

### Added

- Added the first runtime localization foundation: `platform.ui.language` defaults to English, ignored `configs\local.json` can set `zh-CN` for a machine, and `ADP_LANG=zh-CN` can switch a single CLI invocation without editing files. The initial Simplified Chinese coverage includes `adp help`, unknown-command output, and reserved-command output.
- Added CI-backed local configuration boundary checks to prove that first-run diagnostics, preview commands, failure diagnostics, and bare `network configure-local` do not mutate user-owned `configs\local.json` or create local config backups without explicit `-Apply`.
- Added `adp network configure-local [-Plan|-Apply]` to align ignored `configs\local.json` with the detected host `VMnet8` NAT subnet before VM creation. The default and `-Plan` modes are non-mutating, show the detected host CIDR, target gateway/DNS, derived runtime static IPs, and field-level local config changes. `-Apply` is required to write the local override and backs up an existing `configs\local.json` as `configs\local.json.bak.<timestamp>`. `adp up` and `adp doctor` now present both remediation paths when VMware NAT mismatch blocks first-time VM creation: align ADP local overrides to host `VMnet8`, or keep ADP's configured subnet and change VMware `VMnet8`.
- Added explicit local `checkpoint-waived` workspace task state so high-risk tasks can record human acceptance of missing VM snapshot protection in ignored local state. Waived checkpoints are visible in `workspace status`, `workspace dashboard`, `workspace project`, `workspace report`, `workspace task review`, `workspace task rollback`, and `workspace task commit`; they unblock the snapshot-first gate without pretending a VM snapshot exists, and rollback output withholds VM restore commands when no checkpoint was confirmed.
- Added milestone review rollups to `workspace report` and `workspace report -Markdown`, summarizing each milestone's actions, release states, blockers, validation-required tasks, review-required tasks, ready-to-commit tasks, owners, and due attention without running validation or changing runtime state.
- Added a non-destructive validation execution queue to `workspace report` and `workspace report -Markdown`, showing each task's recorded validation state, command count, readiness, blockers, plan command, `-Execute -Plan` preview command, and explicit `-Execute` command without running validation.
- Added plan-only `evaluations[]` workspace hooks plus evaluation queues in `workspace status`, `workspace dashboard`, `workspace report`, and `workspace report -Markdown`, so agent-native review metrics and declared evaluation commands can be included in release evidence without executing evaluation commands.
- Added non-destructive `workspace recipes` output to summarize manifest project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, starting sync, creating snapshots, running validation, running evaluation commands, running Git, or modifying files.
- Added `workspace create [-Plan]` for manifest-declared local project directories. `-Plan` previews directory creation; execution creates only missing local directories and does not clone projects, start sync, start runtimes, open SSH, create snapshots, run validation, run evaluation commands, run Git, or modify existing project files.
- Added non-destructive `adp capabilities` output plus bilingual capabilities documentation to distinguish supported Windows VMware behavior from planned Hyper-V, KVM, macOS, Linux, and container-backed runtime work.
- Tightened first-time autoinstall monitor heartbeats so each repeated line starts with a plain `[install monitor] INSTALLING Ubuntu in VM` headline, then carries `progress=indeterminate`, `user-action=keep-open`, `diagnostics=vmware-console-after-20min`, elapsed/remaining timing, next-check guidance, and readiness signals. This makes the visible log tail read as an active watched installation rather than a stuck IP or SSH probe.

### Changed

- Fixed `install.ps1` so installer output uses the same `platform.ui.language` / `ADP_LANG` preference as the CLI. The Phase 1 banner is now printed after local config is loaded, and the main installer phases, ISO guidance, dependency summaries, and next-step output have initial Simplified Chinese coverage.
- Expanded Simplified Chinese CLI coverage across the fresh deployment path. `adp init`, `adp doctor -FirstRun`, `adp doctor -FixMutagen -Plan`, `adp up <runtime> -Plan`, the main `adp up <runtime>` guidance, `adp status [runtime]`, and `adp network configure-local [-Plan|-Apply]` now localize primary headers, non-mutating boundaries, remediation choices, and next-step guidance while keeping command names and machine-readable state values stable.
- Improved sync diagnostics for existing Mutagen sessions: `sync status` now prints an ADP runtime summary before the raw Mutagen list, `status` reports unhealthy or endpoint-mismatched sessions, `doctor` treats unusable sessions as issues for created runtimes, and `sync start <runtime>` no longer treats a same-name stale or halted session as success. If a stale session belongs to a runtime that has not been created in the current checkout, ADP now reports it as cleanup guidance instead of a current platform-health failure.
- Improved Mutagen first-run remediation for restricted networks: `platform.tools.mutagen` now supports configurable download URL, explicit local archive path, optional SHA256 archive verification, and configurable download timeouts. `doctor -FixMutagen -Plan` shows these inputs before any download or extraction, and offline archives still remain under ignored `.tools\mutagen`.
- Captured `xorriso` output during autoinstall ISO remastering so successful `adp up` output is not polluted by delayed ISO-tool logs after the runtime-ready summary, while failures still include captured tool details.
- Improved `adp doctor -FixMutagen` first-run remediation output with explicit install phases, download source/target, connection and hard timeout guidance, controlled download-process termination, temporary archive downloads, reuse of existing archives, invalid-archive retry, clean failure output, and manual recovery guidance if the download fails.
- Expanded default frontend, backend, and agent sync profile ignore lists for common dependency directories, build outputs, framework caches, browser-test output, Python virtual environments, Python caches, and local ADP/Codex tool state, reducing the chance that generated artifacts are synchronized before users customize profiles.
- Clarified the ADP-OS dogfooding guidance for first-run usage: a minimal POSIX shell project is enough to validate the workspace lifecycle end to end. The public workspaces docs now tell maintainers to start with a tiny syncable project that can be validated, reviewed, and committed without browser downloads or package installation.

### 2026-05-29

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

### 2026-05-28

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

### 2026-05-27

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

### 2026-05-26

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
