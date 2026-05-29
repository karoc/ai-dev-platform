# Operations

[简体中文](zh-CN/operations.md) | English

This guide covers day-to-day operation of ADP-OS.

## Health Checks

Run:

```powershell
.\cli\adp.ps1 doctor
```

Expected result:

```text
All checks passed. Platform is healthy.
```

For first-run guidance, include the checklist:

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

`doctor` checks platform prerequisites, configuration shape, local override status, VMware tooling, VMware NAT host match when detectable, Mutagen version, ISO cache, runtime topology, static IP uniqueness, static IP ranges, existing-runtime seed network drift, VM status, SSH reachability for running VMs, and Mutagen sessions.

Preview local Mutagen remediation:

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
```

Install the tested local Mutagen binary only after reviewing the plan:

```powershell
.\cli\adp.ps1 doctor -FixMutagen
```

`-FixMutagen` downloads the official Mutagen 0.18.x Windows AMD64 archive, extracts `mutagen.exe` to `.tools\mutagen\mutagen.exe`, and verifies the installed version. The `.tools` directory is ignored by Git, so downloaded archives and local binaries are not committed.

Run integration checks:

```powershell
.\tests\validate.ps1
```

For targeted checks:

```powershell
.\tests\validate.ps1 -Quick
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

`validate.ps1` is the local version of the CI repository validation. It runs PowerShell parsing, JSON parsing, CLI parameter contracts, config schema checks, artifact hygiene checks, CLI smoke tests, installer smoke tests, bootstrap shell syntax checks, Markdown local link checks, and documentation language-link checks. The documentation language check also enforces translated file pairs for root public docs and `docs/zh-CN`. Use `-Quick` for local iteration; it keeps parser, schema, contract, artifact hygiene, shell, Markdown, and documentation checks, but skips the slower CLI and installer smoke tests. Use `-SkipCliSmoke`, `-SkipInstallerSmoke`, or `-SkipShellSyntax` for narrower troubleshooting.

`cli-smoke.ps1` checks command dispatch, non-destructive previews, and input error boundaries. It does not create, start, stop, sync, or destroy VMs.

`install-smoke.ps1` checks installer diagnostics and local-state writes with a temporary `USERPROFILE`. It does not use the real user profile, download dependencies, validate VMware, create VMs, or require a real ISO.

Installer troubleshooting switches:

```powershell
.\install.ps1 -SkipDependencyCheck
.\install.ps1 -SkipVMValidation
```

These switches are intended for controlled troubleshooting and CI-like validation paths. Normal first-run setup should not use them.

`install.ps1` and `doctor` check the host prerequisites needed for first runtime creation:

- VMware `vmrun.exe`.
- VMware `vmware-vdiskmanager.exe`.
- WSL and WSL `xorriso`.
- An ISO remaster tool.
- Mutagen 0.18.x.
- OpenSSH Client.
- ISO presence and basic shape.

The checks print remediation guidance. They do not download VMware, Mutagen, browsers, ISO images, or other large binaries by default. Mutagen installation is explicit through `doctor -FixMutagen`.

## Start Runtimes

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

If a VM exists and is already running, ADP reports the current IP and skips creation.

After startup, ADP prints the configured connection target, SSH command, SSH alias, workspace path, sync command, and status command. The connection target comes from the merged configuration, including `configs\local.json` when present.

The `agent` runtime may print a high-IO profile notice. This is not an error; it means the runtime is sized for AI agent workloads and snapshots are recommended before destructive or large-scale tasks.

First-time VM creation includes a long Ubuntu autoinstall phase. ADP reports this as `Autoinstall in progress` and shows elapsed and remaining timeout time. During this phase, SSH port 22 may become reachable before the installed system has accepted the ADP key or written `/home/adp/.adp-provisioned`; that intermediate state is reported as `auth-pending`, not as a finished runtime.

Preview startup without creating, starting, provisioning, or bootstrapping a VM:

```powershell
.\cli\adp.ps1 up agent -Plan
```

Create the VM definition without starting OS provisioning or bootstrap:

```powershell
.\cli\adp.ps1 up agent -NoProvision
```

Initialize platform state and create a runtime VM definition without starting OS provisioning:

```powershell
.\cli\adp.ps1 init agent -SkipProvision
```

When creating a runtime for the first time, you can pass an ISO from any location:

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\Share\ubuntu-26.04-live-server-amd64.iso
```

`-IsoPath` is used directly for VM creation. It does not need to be inside the configured ISO cache.

Before creating a new VM, `adp up <runtime>` compares the configured VMware NAT CIDR with the host `VMnet8` network when the host exposes it. If they do not match, ADP exits before creating the VM and asks you to update `configs\local.json`. This prevents a new VM from being installed with a static IP that the host cannot reach.

## Stop Runtimes

```powershell
.\cli\adp.ps1 stop frontend
```

The command tries a soft stop first, then a hard stop if needed.

## Runtime Status

Show all runtime states and connection details:

```powershell
.\cli\adp.ps1 status
```

Show one runtime:

```powershell
.\cli\adp.ps1 status frontend
```

`status` is non-destructive. It does not create, start, stop, sync, snapshot, or edit guest files. It reports:

- Whether `configs\local.json` is missing, empty, applied, or unsupported.
- The configured VMware NAT CIDR and gateway.
- Each runtime's VM status.
- The configured static IP from the merged topology.
- The VMware-detected IP when available.
- Network drift when an existing autoinstall seed still contains an older static IP than the current merged configuration.
- SSH state for running VMs: `reachable`, `auth-pending`, `unreachable`, or a local prerequisite state such as `key-missing`.
- Mutagen sync session presence.
- The exact SSH command, SSH alias, workspace path, and next commands.

If the VMware-detected IP differs from the configured static IP, ADP still shows the configured static IP as the connection target. This is intentional for static networking and makes local NAT subnet overrides visible after editing `configs\local.json`.

If `status` reports `network drift`, the VM was created with an older seed network than the current configuration. Editing `configs\local.json` after VM creation does not rewrite guest networking. Rebuild the runtime, or reach the guest through the seed-era address and apply the desired netplan change.

If `status` reports `auth-pending`, the SSH port is open but the ADP key is not accepted yet. During first-time autoinstall this usually means the installer or first boot is still preparing the target user. Keep waiting until the timeout, or inspect the VMware console if the state does not change.

## SSH Access

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

Default addresses are documented in `docs\networking.md`. If you use `configs\local.json` to override `topology.<runtime>.static_ip`, use `.\cli\adp.ps1 status <runtime>` after startup and connect to the address shown there.

## Workspace Sync

Place target project clones under the matching Windows workspace root before starting sync. See [Workspaces](workspaces.md) for recommended layouts and dogfooding guidance.

Start sync:

```powershell
.\cli\adp.ps1 sync start frontend
```

Check sync:

```powershell
.\cli\adp.ps1 sync status
```

Stop sync:

```powershell
.\cli\adp.ps1 sync stop frontend
```

Mutagen sessions are named:

```text
adp-frontend
adp-backend
adp-agent
```

## Frontend Browser Tests

The frontend runtime includes lightweight browser acceptance helpers. They do not install browser binaries during bootstrap.

Check readiness:

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
```

Install Chromium support on demand:

```bash
adp-frontend-browser-install chromium
```

Then run project tests from the synced workspace:

```bash
cd /home/adp/workspace
pnpm install
pnpm exec playwright test
```

Browser downloads stay inside the VM user cache. Generated reports such as `playwright-report`, `test-results`, and `blob-report` are ignored by the frontend sync profile.

## Snapshots and Restore

Create a baseline snapshot:

```powershell
.\cli\adp.ps1 snapshot create frontend clean
```

Restore:

```powershell
.\cli\adp.ps1 restore frontend clean
```

Snapshots are VMware snapshots and may take several minutes on running VMs. ADP verifies snapshot existence after timeout to avoid false failures.

## Destroy a Runtime

```powershell
.\cli\adp.ps1 destroy frontend
```

Destroying a runtime removes the VM files for that runtime. Workspace data under `%USERPROFILE%\adp-workspaces` is separate.

Preview the deletion first:

```powershell
.\cli\adp.ps1 destroy frontend -Plan
```

## Re-apply Networking

```powershell
.\cli\adp.ps1 network apply all
```

Use this after editing `configs\platform.json`, `configs\topology.json`, or the supported `platform`/`topology` sections in `configs\local.json`.

Preview the guest networking changes first:

```powershell
.\cli\adp.ps1 network apply all -Plan
```
