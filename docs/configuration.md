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
    "ignore": ["node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", "playwright-report", "test-results"]
  }
}
```

Default sync profiles ignore common dependency directories, build outputs, framework caches, test reports, Python virtual environments, Python caches, and local ADP/Codex tool state that should not be copied through Mutagen. They are intentionally conservative: source files, lockfiles, manifests, and project configuration remain syncable. Use `workspace status`, `workspace dashboard`, or `workspace report` to see whether a synced project still has generated directories that need profile review.

Supported sync modes depend on the installed Mutagen version. The project has been tested with Mutagen `0.18.x`.

## Local Overrides

`configs\local.json` is an ignored, machine-local override file. Use it for host paths, the ISO filename used inside the ISO cache, local VM sizing, static IPs, credentials for local bootstrap, and sync ignore changes that should not be committed.

Start from the example:

```powershell
Copy-Item configs\local.example.json configs\local.json
```

Example:

```json
{
  "platform": {
    "paths": {
      "workspace_root": "D:\\ADP\\workspaces",
      "iso_cache": "D:\\ADP\\iso",
      "vm_store": "D:\\ADP\\vms"
    },
    "defaults": {
      "iso_path": "ubuntu-26.04-live-server-amd64.iso",
      "admin_user": "adp",
      "admin_password": "change-this-local-password"
    },
    "network": {
      "vmware_nat": {
        "cidr": "192.168.242.0/24",
        "gateway": "192.168.242.2"
      }
    }
  },
  "topology": {
    "frontend": {
      "memory": 12288,
      "static_ip": "192.168.242.131"
    },
    "agent": {
      "memory": 24576,
      "disk": 240
    }
  },
  "sync_profiles": {
    "frontend": {
      "ignore": ["node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", "playwright-report", "test-results", "blob-report", ".playwright"]
    }
  }
}
```

Supported top-level sections:

- `platform`: merged into `configs\platform.json`.
- `topology`: merged into `configs\topology.json`.
- `sync_profiles`: merged into `configs\sync-profiles.json`.

Merging is recursive for JSON objects. Arrays and scalar values replace the default value, so local `sync_profiles.<name>.ignore` overrides should include every ignored path you still want to keep from the default profile. Empty `configs\local.json` files are ignored.

`platform.defaults.iso_path` is resolved inside `platform.paths.iso_cache`. To import an ISO from any location, run `.\install.ps1 -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso`; the installer copies it into the configured ISO cache.

For VMware NAT differences between machines, prefer:

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local
```

The command detects host `VMnet8`, previews the target `platform.network.vmware_nat` and `topology.<runtime>.static_ip` values, and writes only the ignored `configs\local.json` override when run without `-Plan`. Manual editing is still supported when host detection is unavailable. Confirm the actual VMware NAT subnet in VMware Workstation's Virtual Network Editor if needed; see [Networking](networking.md#prerequisites).

Do not commit `configs\local.json`; commit shared defaults to the main config files instead.

Run `.\cli\adp.ps1 doctor` to see whether `configs\local.json` is missing, empty, applied, present without supported sections, or using unsupported top-level sections.

`configs\secrets.json` is also ignored and reserved for future secret-specific support. It is not read by the current MVP.
