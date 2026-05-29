# Historical Implementation Brief

[简体中文](build.zh-CN.md) | English

This file is a historical implementation brief for AI Dev Platform OS. It records the original product and architecture intent that guided the first public MVP.

It is not the current installation guide, operations guide, release process, or roadmap. For current user-facing instructions, start with:

- [README](README.md)
- [Documentation Home](docs/README.md)
- [Roadmap](docs/roadmap.md)
- [Operations](docs/operations.md)
- [Workspaces](docs/workspaces.md)
- [Release Process](docs/release-process.md)

## Original Product Intent

AI Dev Platform OS, or ADP-OS, was conceived as a local AI coding runtime platform:

- Local-first.
- Runtime-oriented.
- Workspace-centric.
- Sandbox-first.
- Multi-agent-ready.
- Designed for AI-assisted and agent-native software development.

The original intent was not to build a small VM management script. The goal was to build a local development platform that can provision isolated runtimes, synchronize workspaces, optimize for AI coding workloads, and provide snapshot rollback for risky work.

## Original Architecture Direction

The early architecture direction centered on layered responsibilities:

```text
Host OS
  -> ADP-OS control plane
  -> Runtime fabric
  -> Workspace fabric
  -> AI agents
```

The design expected host-specific behavior to live behind adapter boundaries, with future room for Windows, macOS, Linux, VMware, Hyper-V, KVM, Docker-capable runtimes, and other sandbox carriers.

## Original MVP Scope

The first MVP focused on:

- Windows 11.
- PowerShell 7.
- VMware Workstation.
- Ubuntu Server runtimes.
- Mutagen workspace synchronization.
- Runtime profiles for frontend, backend, and agent workloads.
- SSH bootstrap.
- Static networking.
- Snapshot and rollback workflows.
- Diagnostics.

The current public implementation has evolved from this brief. Treat the committed source, README, and docs as authoritative for present behavior.

## Non-Goals Captured by the Brief

The brief explicitly framed ADP-OS as more than:

- A VM management script.
- An Ubuntu installer.
- A Docker wrapper.
- A one-off development environment setup script.

That remains true for public positioning: Docker and dev containers are runtime-internal project tools; ADP-OS is the outer runtime lifecycle, synchronization, validation, evidence, and rollback layer.

## Current Planning Boundary

Use these current documents instead of this historical brief for active planning and usage:

- [Roadmap](docs/roadmap.md): public product direction.
- [Release Readiness](docs/release-readiness.md): review and release decision policy.
- [Release Process](docs/release-process.md): validation, evidence, safety, commit, and publication boundary.
- [Contributor Workflows](docs/contributor-workflows.md): task templates and review expectations.

