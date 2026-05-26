# Architecture

ADP-OS is structured as a local control plane plus runtime fabric.

```text
Host OS
  -> ADP-OS control plane
  -> Runtime fabric
  -> Workspace fabric
  -> AI coding agents and developer tools
```

The current MVP targets:

- Host: Windows 11.
- Runtime carrier: VMware Workstation.
- Guest OS: Ubuntu Server 26.04.
- Workspace sync: Mutagen.
- Automation: PowerShell 7, OpenSSH, cloud-init, netplan.

## Directory Layout

```text
adp-os/
  install.ps1
  cli/
    adp.ps1
    commands/
  core/
    bootstrap/
    config/
    logging/
    runtime/
  adapters/
    windows/
      filesystem/
      mutagen/
      ssh/
      vmware/
    linux/
    mac/
  runtimes/
    vmware/
  bootstrap/
    base/
    frontend/
    backend/
    agent/
  configs/
  docs/
  templates/
```

## Control Plane

The CLI entry point is `cli\adp.ps1`. It loads:

- `core\config\config.ps1`
- `core\logging\logger.ps1`
- Windows adapters for filesystem and VMware

It then dispatches to command files under `cli\commands`.

Core modules avoid direct runtime-specific behavior where possible. Host-specific operations live under `adapters`.

## Runtime Fabric

VMware integration is implemented in `adapters\windows\vmware\vmware.ps1`. It wraps `vmrun.exe` and exposes:

- VM start, stop, suspend, reset.
- VM status detection.
- Guest IP lookup with VMware Tools and DHCP lease fallback.
- Guest command and file copy helpers.
- Snapshot create, list, restore, delete.

VM creation is handled by `runtimes\vmware\vm-factory.ps1`:

- Generates cloud-init user data.
- Generates seed ISO.
- Remasters Ubuntu install ISO so the boot menu defaults to autoinstall.
- Creates VMDK and VMX files.
- Starts VM provisioning and waits for the provisioning marker.

## Bootstrap

Bootstrap orchestration is implemented in `core\bootstrap\bootstrap.ps1`.

The base bootstrap installs shared tooling:

- Git, curl, wget, jq, tmux, fzf.
- Docker.
- Node.js and npm/pnpm.
- Python 3, pip, venv, uv.
- ripgrep and fd.

Runtime-specific bootstrap scripts extend the base runtime:

- `bootstrap\frontend\setup-frontend.sh`
- `bootstrap\backend\setup-backend.sh`
- `bootstrap\agent\setup-agent.sh`

The frontend profile also installs lightweight browser acceptance helper commands from `bootstrap\frontend\browser-tools.sh`:

```text
adp-frontend-browser-check
adp-frontend-browser-install
```

These helpers are scripts only. Browser engines and Playwright caches are downloaded on demand inside the VM and are not vendored into the ADP-OS repository.

Bootstrap scripts are idempotent and use marker files in `/home/adp`.

## Workspace Fabric

Mutagen integration is implemented in `adapters\windows\mutagen\mutagen.ps1`.

ADP creates one sync session per runtime:

```text
adp-frontend
adp-backend
adp-agent
```

Each session syncs:

```text
%USERPROFILE%\adp-workspaces\<runtime>
  <-> /home/adp/workspace
```

Mutagen SSH endpoints use ADP-managed Host aliases in the user's SSH config.

## Snapshot Model

Snapshots are runtime-scoped VMware snapshots. The CLI currently exposes:

```powershell
.\cli\adp.ps1 snapshot create <runtime> <name>
.\cli\adp.ps1 restore <runtime> <name>
```

Snapshot creation is defensive: if `vmrun` times out but the snapshot appears afterward, ADP treats the operation as successful.
