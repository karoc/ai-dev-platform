# Changelog

[简体中文](CHANGELOG.zh-CN.md) | English

All notable public changes to AI Dev Platform OS are documented here.

The project does not yet publish versioned releases. Entries are grouped by date until release tags are introduced.

## 2026-05-28

### Added

- Added top-level `adp status [runtime]` output for runtime state, local config status, configured static IPs, VMware-detected IPs, SSH reachability, sync session presence, and exact connection commands.
- Added CI-backed documentation language-context link checks so translated docs stay in the selected language when translated equivalents exist.
- Added CI-backed configuration schema checks for committed platform, topology, sync profile, local example, and workspace manifest shapes.
- Added non-destructive `adp workspace report` output for release handoff summaries, task validation results, review decisions, rollback context, commit readiness, review bundle fields, a source-review checklist, and handoff commands.
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

