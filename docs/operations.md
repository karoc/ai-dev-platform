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

`doctor` checks platform prerequisites, configuration shape, local override status, VMware tooling, Mutagen version, ISO cache, runtime topology, static IP uniqueness, static IP ranges, VM status, SSH reachability for running VMs, and Mutagen sessions.

Run integration checks:

```powershell
.\tests\cli-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

`cli-smoke.ps1` checks command dispatch, non-destructive previews, and input error boundaries. It does not create, start, stop, sync, or destroy VMs.

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

The checks print remediation guidance. They do not download VMware, Mutagen, browsers, ISO images, or other large binaries by default.

## Start Runtimes

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

If a VM exists and is already running, ADP reports the current IP and skips creation.

The `agent` runtime may print a high-IO profile notice. This is not an error; it means the runtime is sized for AI agent workloads and snapshots are recommended before destructive or large-scale tasks.

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

## Stop Runtimes

```powershell
.\cli\adp.ps1 stop frontend
```

The command tries a soft stop first, then a hard stop if needed.

## SSH Access

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

Default addresses are documented in `docs\networking.md`.

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

Use this after editing `configs\platform.json` or `configs\topology.json`.

Preview the guest networking changes first:

```powershell
.\cli\adp.ps1 network apply all -Plan
```
