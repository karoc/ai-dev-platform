# Troubleshooting

[简体中文](zh-CN/troubleshooting.md) | English

This guide maps common symptoms to the safest first checks. It is intentionally non-destructive first: start with diagnostics, status, and plan previews before changing VMs, networking, sync sessions, or local configuration.

If you need to open a public issue, see [Support](../SUPPORT.md) for what diagnostics to include and what not to publish.

## First Checks

Run these before changing configuration or recreating a runtime:

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 status
.\cli\adp.ps1 sync status
.\tests\validate.ps1 -Quick
```

Useful context to capture:

- Host OS and PowerShell version.
- VMware Workstation version.
- ADP-OS commit: `git rev-parse --short HEAD`.
- Whether `configs\local.json` exists and which supported top-level sections it uses.
- The exact command that failed.
- The first error message and the command output immediately before it.

Do not publish secrets, tokens, private keys, VM disks, ISO files, downloaded archives, large logs, private local paths, or private maintainer context.

## Symptom Index

| Symptom | Start with | Likely area | Next documentation |
| --- | --- | --- | --- |
| First setup is unclear | `.\cli\adp.ps1 doctor -FirstRun` | prerequisites, ISO, local overrides | [Operations](operations.md), [Configuration](configuration.md) |
| A required tool is missing | `.\cli\adp.ps1 doctor` | VMware, WSL, xorriso, Mutagen, OpenSSH | [Operations](operations.md#health-checks) |
| Mutagen is missing or wrong version | `.\cli\adp.ps1 doctor -FixMutagen -Plan` | local Mutagen remediation | [Operations](operations.md#health-checks) |
| Runtime startup uses an unexpected ISO path | `.\cli\adp.ps1 up <runtime> -IsoPath <path> -Plan` | explicit ISO path, local config | [Operations](operations.md#start-runtimes) |
| Runtime exists but connection fails | `.\cli\adp.ps1 status <runtime>` | VM state, static IP, SSH reachability | [Operations](operations.md#runtime-status), [Networking](networking.md) |
| VMware IP differs from configured static IP | `.\cli\adp.ps1 status <runtime>` | static networking, local NAT overrides | [Networking](networking.md#prerequisites) |
| Static IP is outside the NAT subnet | `.\cli\adp.ps1 doctor` | topology and platform config | [Configuration](configuration.md#local-overrides), [Networking](networking.md) |
| Sync does not start or appears missing | `.\cli\adp.ps1 sync status` | Mutagen sessions, SSH aliases, workspace paths | [Operations](operations.md#workspace-sync) |
| Browser tests cannot run in frontend | `adp-frontend-browser-check` inside the frontend runtime | on-demand browser install | [Browser Testing](browser-testing.md) |
| Workspace task is blocked | `.\cli\adp.ps1 workspace report` | validation, review, snapshot, governance gates | [Workspaces](workspaces.md), [Release Readiness](release-readiness.md) |
| High-risk agent work is not ready | `.\cli\adp.ps1 workspace dashboard` | snapshot-first gate | [Workspaces](workspaces.md), [Release Readiness](release-readiness.md) |
| Repository validation fails | `.\tests\validate.ps1 -Quick` then targeted checks | parser, config schema, artifact hygiene, docs, issue templates, smoke tests | [Operations](operations.md#health-checks) |
| Public issue is needed | `.\cli\adp.ps1 doctor` and relevant status output | support routing | [Support](../SUPPORT.md) |

## Safe Preview Commands

Use plan or status commands before changing runtime state:

```powershell
.\cli\adp.ps1 up agent -Plan
.\cli\adp.ps1 network apply all -Plan
.\cli\adp.ps1 destroy agent -Plan
.\cli\adp.ps1 doctor -FixMutagen -Plan
.\cli\adp.ps1 workspace plan
.\cli\adp.ps1 workspace report -Markdown
```

These commands are intended to show what would happen or collect evidence. They do not create snapshots, run task validation, stage files, commit files, or destroy VMs.

## When to Change Local Configuration

Use ignored local overrides when machine-specific settings differ from committed defaults:

```powershell
Copy-Item configs\local.example.json configs\local.json
```

Use `configs\local.json` for:

- Local VMware NAT subnet differences.
- Runtime static IP changes.
- Local VM sizing changes.
- Machine-specific paths.

Run this after editing:

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 status
```

Do not paste private local paths or credentials into public issues. If an issue depends on local config, list only the supported top-level sections, for example `platform` and `topology`.

## When to Use Runtime Operations

Use runtime-changing commands only after status and plan output make the intended action clear:

- Use `network apply` after changing static networking settings.
- Use `snapshot create` before risky or broad agent work.
- Use `restore` when you intentionally want to roll a VM back to an existing snapshot.
- Use `destroy -Plan` before `destroy`.

Workspace commands keep review and commit boundaries explicit. `workspace task validate <task> -Execute` runs only declared validation commands, and review, rollback, staging, and commit remain separate actions.

## Asking for Help

Open a public issue only after removing sensitive information. Include:

- The symptom.
- The command you ran.
- The non-sensitive output from the first relevant diagnostic.
- Host and tool versions.
- ADP-OS commit.
- Whether a local override is present.

Use the Usage question template for questions, the Bug report template for reproducible failures, and the Feature request template for product or workflow improvements.
