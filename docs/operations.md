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

Run integration checks:

```powershell
.\test-integration.ps1
.\deploy-check.ps1
```

## Start Runtimes

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

If a VM exists and is already running, ADP reports the current IP and skips creation.

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

## Re-apply Networking

```powershell
.\cli\adp.ps1 network apply all
```

Use this after editing `configs\platform.json` or `configs\topology.json`.
