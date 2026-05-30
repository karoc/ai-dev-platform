# Capabilities

[简体中文](zh-CN/capabilities.md) | English

This page describes the current ADP-OS capability boundary. It is deliberately explicit about what is supported, what is planned, and what is only a stub so users do not mistake roadmap direction for available runtime support.

Use this command to see the same boundary from the CLI:

```powershell
.\cli\adp.ps1 capabilities
```

The command is non-destructive. It does not create, start, stop, inspect, or destroy VMs; it does not change sync sessions, snapshots, guest files, workspace files, downloads, or host networking.

## Current Support

ADP-OS currently supports:

- Windows PowerShell as the host control plane.
- VMware Workstation as the runtime carrier.
- Ubuntu Server 26.04 guest runtimes.
- `frontend`, `backend`, and `agent` runtime profiles.
- Mutagen workspace synchronization over SSH.
- Runtime lifecycle commands: `up`, `status`, `stop`, `logs`, `destroy`, and `network apply`.
- Rollback lifecycle commands: `snapshot create` and `restore`.
- Workspace evidence commands: `workspace dashboard`, `workspace report`, `workspace report -Markdown`, and explicit task validation recording.

## Runtime Carrier Matrix

| Carrier | Status | Boundary |
| --- | --- | --- |
| VMware Workstation | Supported on Windows | Full VM runtime with static NAT, SSH bootstrap, Docker-capable guest, and VMware snapshots. |
| Hyper-V | Planned | Not implemented. No Hyper-V VM creation or lifecycle command is available. |
| KVM/libvirt | Planned | Not implemented. The Linux adapter is currently a stub. |
| macOS VM carrier | Planned | Not implemented. The macOS adapter is currently a stub. |
| Container-backed runtime | Exploratory | Not implemented as an ADP outer runtime carrier. Docker and dev containers are runtime-internal project tools today. |

## Host Adapter Matrix

| Host adapter | Status | Notes |
| --- | --- | --- |
| Windows | Supported | Filesystem, VMware, SSH, and Mutagen adapters are active. |
| Linux | Planned | `adapters/linux/linux.ps1` exists as a stub and reports unavailable. |
| macOS | Planned | `adapters/mac/mac.ps1` exists as a stub and reports unavailable. |

## Inner Environment Integrations

Docker, Docker Compose, and dev containers are not ADP-OS replacements. They are inner development-environment tools that can run or be detected inside ADP-managed runtimes.

- Docker is installed inside bootstrapped Ubuntu runtimes so project tooling can use containers inside the VM boundary.
- Dev container metadata is detected non-destructively by workspace views as project context.
- Workspace planning commands do not execute dev containers, install packages, download browser binaries, create snapshots, stage files, or commit changes.

## Expansion Rules

New runtime carriers should not be marked supported until they preserve the same user-facing lifecycle and safety expectations:

- Keep host-specific behavior behind adapter boundaries.
- Preserve runtime creation, startup, status, stop, diagnostics, sync, and rollback semantics.
- Document the security boundary and tradeoffs clearly.
- Keep Docker and dev containers as inner tools unless a future runtime explicitly documents a different boundary.
- Add tests and bilingual documentation before presenting a carrier as supported.
