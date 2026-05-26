# Configuration

[简体中文](zh-CN/configuration.md) | English

ADP-OS is configured through JSON files in `configs`.

## `platform.json`

`configs\platform.json` defines host-level paths, defaults, features, and networking.

Important paths:

```json
{
  "paths": {
    "workspace_root": "${env:USERPROFILE}\\adp-workspaces",
    "iso_cache": "${env:USERPROFILE}\\adp-iso",
    "vm_store": "${env:USERPROFILE}\\adp-vms",
    "logs": "${project:root}\\logs"
  }
}
```

Path placeholders:

- `${env:NAME}` resolves from the host environment.
- `${project:root}` resolves to the repository root.

Default runtime user:

```json
{
  "defaults": {
    "admin_user": "adp",
    "admin_password": "adp"
  }
}
```

The default password is used for local automated sudo during bootstrap. Change it before using ADP on shared or untrusted networks.

## `topology.json`

`configs\topology.json` defines runtime sizing and profiles.

Example:

```json
{
  "frontend": {
    "runtime": "vmware",
    "os": "ubuntu-26.04",
    "cpu": 4,
    "memory": 8192,
    "disk": 80,
    "workspace": "frontend",
    "sync_profile": "frontend",
    "bootstrap_profile": "frontend",
    "static_ip": "192.168.242.131",
    "ssh_port": 22
  }
}
```

Fields:

- `runtime`: runtime carrier, currently `vmware`.
- `os`: OS profile name from `runtimes\vmware\os-profiles.ps1`.
- `cpu`, `memory`, `disk`: VM sizing.
- `workspace`: local workspace subdirectory.
- `sync_profile`: profile in `sync-profiles.json`.
- `bootstrap_profile`: bootstrap folder under `bootstrap`.
- `static_ip`: configured guest IP used by provisioning, CLI, SSH, and sync.
- `ssh_port`: guest SSH port.

## `sync-profiles.json`

Sync profiles configure Mutagen behavior and ignore lists.

```json
{
  "frontend": {
    "mode": "two-way-resolved",
    "ignore": ["node_modules", ".next", "dist", "build"]
  }
}
```

Supported sync modes depend on the installed Mutagen version. The project has been tested with Mutagen `0.18.x`.

## Local Overrides

The following files are ignored and reserved for local secrets or future local override support:

```text
configs/local.json
configs/secrets.json
```

The current MVP reads the main config files directly. Local override merging is not implemented yet.
