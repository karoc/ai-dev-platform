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

From a stock Windows shell, prefer the wrapper form such as `.\adp.cmd doctor`. If `pwsh.exe` is not installed, run `.\setup.cmd`; built-in Windows PowerShell 5.1 is only a bootstrap path and does not run the ADP-OS control plane.

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
| Only Windows PowerShell 5.1 is available | `.\setup.cmd` | PowerShell 7 bootstrap | [README](../README.md#requirements) |
| A required tool is missing | `.\cli\adp.ps1 doctor` | VMware, WSL, xorriso, Mutagen, OpenSSH | [Operations](operations.md#health-checks) |
| Mutagen is missing or wrong version | `.\cli\adp.ps1 doctor -FixMutagen -Plan` | local Mutagen remediation, offline archive, optional SHA256 | [Operations](operations.md#health-checks) |
| Runtime startup uses an unexpected ISO path | `.\cli\adp.ps1 up <runtime> -IsoPath <path> -Plan` | explicit ISO path, local config | [Operations](operations.md#start-runtimes) |
| Runtime exists but connection fails | `.\cli\adp.ps1 status <runtime>` | VM state, static IP, SSH reachability | [Operations](operations.md#runtime-status), [Networking](networking.md) |
| Runtime creation looks stuck | keep `adp up <runtime>` running while `[install monitor] INSTALLING Ubuntu in VM` heartbeats continue; if the VM was already pre-provisioned, switch to `status`, `doctor`, and network drift checks | Ubuntu autoinstall, first boot, readiness signals from IP/SSH/provision marker, stale VM networking | [Operations](operations.md#start-runtimes) |
| `status` reports `auth-pending` | wait, then rerun `.\\cli\\adp.ps1 status <runtime>` | SSH port is open but ADP key/user is not ready | [Operations](operations.md#runtime-status) |
| `status` reports `ssh-timeout` | wait briefly, rerun `.\\cli\\adp.ps1 status <runtime>`, and use `.\\cli\\adp.ps1 up <runtime> -NoBootstrap` if restore left the VM stopped | post-restore readiness, guest SSH/control-plane settling | [Operations](operations.md#runtime-status) |
| SSH connection fails with `Permission denied` | `.\\cli\\adp.ps1 status <runtime>` | SSH key mismatch, VM was created with a different key | [Operations](operations.md#troubleshooting-ssh-keys) |
| Direct `ssh` reports `REMOTE HOST IDENTIFICATION HAS CHANGED` | refresh only the ADP runtime alias/IP entry in OpenSSH known_hosts, then rerun `.\\cli\\adp.ps1 status <runtime>` | stale direct OpenSSH host-key entry after restore or VM recreation | [Operations](operations.md#ssh-access) |
| `status` reports `key-missing` | run any `adp up` or SSH operation | SSH key pair not yet created | [Operations](operations.md#troubleshooting-ssh-keys) |
| SSH key was accidentally deleted | regenerate by running any SSH operation | `%USERPROFILE%\\.ssh\\adp-os\\` key pair missing | [Operations](operations.md#troubleshooting-ssh-keys) |
| `up` stops with VMware NAT mismatch | `.\cli\adp.ps1 network configure-local -Plan` | host VMnet8 versus local config | [Networking](networking.md#prerequisites), [Configuration](configuration.md#local-overrides) |
| `status` reports `duplicate VM` | `.\cli\adp.ps1 doctor` | same runtime name running from another checkout or stale VM store | [Operations](operations.md#runtime-status) |
| `status` reports network drift | `.\cli\adp.ps1 doctor` and `.\cli\adp.ps1 network apply <runtime> -Plan` | existing VM seed network versus current config; rebuild, guest netplan fix, or host-route workaround | [Operations](operations.md#runtime-status), [Networking](networking.md#static-networking-for-new-vms) |
| VMware IP differs from configured static IP | `.\cli\adp.ps1 status <runtime>` | static networking, local NAT overrides | [Networking](networking.md#prerequisites) |
| Static IP is outside the NAT subnet | `.\cli\adp.ps1 doctor` | topology and platform config | [Configuration](configuration.md#local-overrides), [Networking](networking.md) |
| Sync does not start or appears missing | `.\cli\adp.ps1 sync status` | Mutagen sessions, stale endpoints, SSH aliases, workspace paths | [Operations](operations.md#workspace-sync) |
| Browser tests cannot run in frontend | `adp-frontend-browser-check` inside the frontend runtime | on-demand browser install | [Browser Testing](browser-testing.md) |
| Workspace task is blocked | `.\cli\adp.ps1 workspace report` | validation, review, snapshot, governance gates | [Workspaces](workspaces.md), [Release Readiness](release-readiness.md) |
| High-risk agent work is not ready | `.\cli\adp.ps1 workspace dashboard` | snapshot-first gate | [Workspaces](workspaces.md), [Release Readiness](release-readiness.md) |
| `snapshot create` appears stuck | check whether the snapshot exists before rerunning or continuing a demo | VMware snapshot command return, rollback checkpoint | [Survival Validation](survival-validation.md#demo-readiness-checklist) |
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

## Pre-Provisioned Runtime Still Looks Installing

During first creation, repeated `[install monitor] INSTALLING Ubuntu in VM` heartbeats can be normal. Do not interrupt a real first install only because SSH or IP probes repeat.

That rule changes when the runtime was supposed to be pre-provisioned. If an existing `agent` VM keeps being described as installing during a survival rehearsal, run diagnostics instead of waiting indefinitely:

```powershell
.\adp.cmd status agent
.\adp.cmd doctor
.\adp.cmd network apply agent -Plan
.\adp.cmd sync status
```

If VMware reports a guest IP outside the configured ADP NAT subnet, or `status` / `doctor` reports `network drift` or `seed network drift`, treat the VM as stale networking. Older VMs may have been created before static network seed injection, so the guest can be fully provisioned while booting on an old VMware NAT address that ADP-OS no longer targets.

Use one of the explicit remediation paths:

- Rebuild the runtime if the VM can be recreated.
- Use `network apply agent -Plan` when the old guest address is reachable over SSH.
- Use an administrator-only temporary host-route workaround only to regain SSH to the old guest address. ADP will not add, change, or remove host routes automatically.

Do not count this as a valid 10-minute demo run. It is a product-readiness or local-stale-state issue that must be resolved before showing rollback and evidence value.

## Snapshot Command Appears Stuck

`adp snapshot create <runtime> <name>` is on the rollback-critical path. If it appears stuck, do not proceed with high-risk agent work or a survival demo until the checkpoint is confirmed.

First check whether the snapshot was created:

```powershell
vmrun.exe listSnapshots <path-to-runtime.vmx>
.\adp.cmd snapshot create agent <name>
```

If the target snapshot exists, rerunning `adp snapshot create` should report that it already exists. If VMware created the snapshot but ADP-OS did not return promptly, record that as a product failure for the rehearsal. A rollback checkpoint that cannot be confirmed cleanly is not acceptable demo evidence, even if the VM snapshot exists.

## Mutagen Download Problems

If `doctor -FixMutagen` times out or cannot reach GitHub releases, keep the remediation local and explicit:

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
New-Item -ItemType Directory -Path .tools\mutagen -Force
# Place mutagen_windows_amd64_v0.18.1.zip under .tools\mutagen, then:
.\cli\adp.ps1 doctor -FixMutagen
```

For an archive stored elsewhere, set `platform.tools.mutagen.archive_path` in ignored `configs\local.json`. For a mirror, set `platform.tools.mutagen.download_url`. For strict archive verification, set `platform.tools.mutagen.sha256` to the expected 64-character SHA256 hash. ADP never commits the archive or `mutagen.exe`; `.tools` remains ignored.

## Sync Session Problems

If `sync status`, `status`, or `doctor` reports `wrong-local`, `wrong-remote`, or `unhealthy`, the Mutagen session exists but does not match the current checkout/runtime or is not usable. This can happen after moving workspaces, switching clones, recreating VMs, or reusing a same-name `adp-<runtime>` session from another setup.

Use the explicit reset path:

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
.\\cli\\adp.ps1 sync status
```

If the runtime has not been created in this checkout, `sync status`, `status`, and `doctor` may report the same stale session as `stale-session` or cleanup guidance. That is not a VM health failure yet. Stop the stale session, create the runtime, then start sync.

`sync start <runtime>` does not silently replace an unusable same-name session. It asks for the explicit stop/start sequence so users can see that an existing sync relationship is being terminated and recreated.

All three commands (`status`, `doctor`, and `sync status`) now detect the specific recovery scenario and provide diagnostic output with exact remediation steps. Starting a new sync session does not delete workspace files. Stopping a stale session only removes the Mutagen session definition — workspace files on both sides remain untouched.

## One-Sided Root Emptying

If Mutagen stops with one-sided root emptying protection, it means the synced root was emptied on one side or on both sides and Mutagen refused to keep mirroring the delete. This is expected safety behavior, not a platform crash. It usually shows up after cleaning probe files or experimenting with both sides of the same workspace.

`doctor` and `status` now detect this specific condition and label it explicitly rather than reporting a generic `unhealthy` sync state. The diagnostic output includes:

- What happened: which session hit root-emptying protection
- Why it happened: Mutagen's safe-guard against mirroring unintended deletes
- Recovery steps: repopulation, stop, restart, verify

Recover by repopulating one side from the source of truth, or by recreating the project tree if you intentionally started over. Then restart the session explicitly:

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
.\\cli\\adp.ps1 sync status
```

If the project should be recreated from scratch, do that deliberately instead of expecting Mutagen to recover an empty pair of roots automatically.

Detect root-emptying without syncing:

```powershell
.\\cli\\adp.ps1 doctor            # Shows [SYNC] with recovery scenario title and steps
.\\cli\\adp.ps1 status agent      # Shows sync recovery: with detail and steps
.\\cli\\adp.ps1 sync status       # Shows session health classification
```

## Stale Sessions Across Clones

If you maintain multiple local clones of the ai-dev-platform repository (common for dogfooding ADP-OS while developing it), Mutagen sessions created in one clone are visible globally. A session named `adp-agent` created in `D:\\ai-dev-platform` will show up in `D:\\other-clone` as well, even though the workspace paths differ.

This causes `status` and `doctor` to report `wrong-local` or `wrong-remote` because the session's stored local path (from the clone that created it) does not match the workspace path in the current checkout.

`status`, `doctor`, and `sync status` now detect this crossover and label it explicitly:

```
sync recovery: Sync session local endpoint mismatch
sync detail:   The Mutagen session 'adp-agent' points to a local path
               from a different checkout or clone.
sync step:     This session was likely created from a different clone.
sync step:     If the other clone is still active, consider which
               checkout should own the session.
sync step:     To reclaim for the current checkout: adp sync stop agent,
               then adp sync start agent
sync safety:   Stopping the stale session does not delete workspace
               files on either side.
```

Before stopping, check whether the session is still in active use:

```powershell
.\\cli\\adp.ps1 sync list          # Shows all sessions with their endpoints
.\\cli\\adp.ps1 status agent       # Shows which checkout path is expected
```

If the other clone still needs the session, leave it alone. If not, stop and recreate from the current checkout:

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
```

This is safe: `sync stop` only terminates the Mutagen session definition. No workspace files on either side are deleted.

## Pre-Runtime Stale Session Cleanup

After deleting a VM (or switching to a fresh clone), a Mutagen session for that runtime may still exist globally. `sync status`, `status`, and `doctor` report this as `stale-session` or `sync recovery: Stale sync session before runtime creation`.

This is not a blocking failure — `doctor` treats it as an info-level observation rather than an issue. The VM is gone, but the Mutagen session definition remains. Cleanup is safe and straightforward:

```powershell
.\\cli\\adp.ps1 sync stop agent     # Stop the stale session
.\\cli\\adp.ps1 up agent            # Create the runtime
.\\cli\\adp.ps1 sync start agent    # Start a fresh sync session
```

The diagnostic output includes a safety note: stopping the stale session does not delete workspace files on either side. Only the Mutagen session metadata is removed.

Detect stale sessions before runtime creation:

```powershell
.\\cli\\adp.ps1 doctor              # Lists stale sessions as info-level entries
.\\cli\\adp.ps1 sync status         # Shows stale-session with cleanup guidance
.\\cli\\adp.ps1 status agent        # Shows sync recovery: with detail and steps
```

If you plan to keep the other clone active and the session belongs to it, simply ignore the stale-session report in the current checkout.

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

Do this before creating VMs. If a VM already exists, changing `configs\local.json` changes ADP's target address but does not rewrite the guest network installed from the old autoinstall seed. If `status` reports `network drift`, choose a remediation path explicitly:

- Rebuild the runtime when it can be recreated.
- Use `network apply <runtime> -Plan` when the seed-era guest address is reachable and you want an in-place guest netplan fix.
- Use an administrator-only temporary host-route workaround only to regain SSH to the seed-era address. ADP will not apply host routes automatically.

If `status` or `doctor` reports a duplicate running ADP runtime, handle that before changing local networking. A same-name VM from another checkout can make detected IP and SSH diagnostics point at the wrong VM.

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
