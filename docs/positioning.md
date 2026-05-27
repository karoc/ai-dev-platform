# ADP-OS and Docker

[简体中文](zh-CN/positioning.md) | English

ADP-OS is not a Docker replacement.

Docker is a container runtime and application packaging system. ADP-OS provisions and operates local Linux development runtimes that can run Docker, while adding host isolation, workspace synchronization, role-specific bootstrap, diagnostics, static networking, and VM-level snapshot rollback.

In short:

```text
Docker packages and runs applications.
ADP-OS provisions and operates AI-ready development runtimes.
```

## Different Layers

Docker's core units are:

```text
container
image
volume
network
```

ADP-OS's core units are:

```text
runtime
workspace
sync session
bootstrap profile
snapshot
role
```

ADP-OS can install and use Docker inside each runtime. The platform boundary sits outside Docker:

```text
Windows host
  -> ADP-OS control plane
      -> VMware Ubuntu runtime
          -> Docker, Node.js, Python, browsers, project tools
```

## Why Use ADP-OS Instead of Only Docker?

### Stronger Host Boundary

Docker containers share the host kernel. ADP-OS uses full Linux VMs in the current Windows MVP, giving each runtime a clearer machine boundary:

- Real Ubuntu Server environment.
- Real SSH, systemd, apt, Docker daemon, netplan, and Linux tooling.
- System-level changes remain inside the VM.
- AI agent experimentation can be rolled back with a VM snapshot.

This is especially useful when an AI agent may install packages, modify configuration, run Docker, start services, or run broad diagnostics.

### Better Windows-to-Linux Workspace Behavior

Docker bind mounts on Windows can expose file watching, path, performance, and permission differences.

ADP-OS uses Mutagen synchronization instead:

```text
%USERPROFILE%\adp-workspaces\frontend
  <-> /home/adp/workspace
```

The guest runtime sees a native Linux filesystem, while the host keeps a normal Windows workspace. This is useful for frontend watchers, Python environments, `node_modules`, and AI tools that scan many files.

### VM-Level Snapshot and Restore

Docker can rebuild containers and images, but AI development environments often include state outside a single container:

- apt packages.
- Docker daemon state.
- systemd services.
- SSH and shell configuration.
- language runtime caches.
- browser dependencies.
- network configuration.

ADP-OS exposes VM-level rollback:

```powershell
.\cli\adp.ps1 snapshot create agent clean
.\cli\adp.ps1 restore agent clean
```

That restores the runtime as a machine, not just one process or one container.

### Role-Specific Runtimes

Docker does not define product-level roles such as `frontend`, `backend`, and `agent`. ADP-OS makes those roles first-class:

```text
frontend: JavaScript, frontend tooling, browser acceptance helpers
backend: Python and backend development
agent: higher resource profile, IO tuning, agent sandbox preparation
```

The same ADP commands manage each runtime:

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 sync start frontend
.\cli\adp.ps1 snapshot create frontend clean
.\cli\adp.ps1 doctor
```

### Agent-Native Development

AI agents often need to operate like a developer inside a machine:

- Install dependencies.
- Run tests.
- Start multiple services.
- Use browsers for acceptance checks.
- Inspect source trees.
- Run Docker commands.
- Modify local configuration.
- Produce review artifacts.

Putting an agent inside a container can require privileged mode, Docker socket mounting, nested containers, extra systemd handling, and careful host volume access.

ADP-OS gives the agent a Linux runtime boundary that is easier to reason about and easier to roll back.

## When Docker Is the Better Tool

Use Docker directly when you primarily need:

- Application packaging.
- `docker compose up` for a service stack.
- CI/CD image builds.
- Production-like container deployment.
- Lightweight local services.
- Existing mature Docker Compose or devcontainer workflows.

ADP-OS should not replace those workflows.

## When ADP-OS Is the Better Fit

Use ADP-OS when you need:

- A reproducible local Linux workstation boundary on Windows.
- Full VM isolation for agent experiments.
- VM-level snapshot and restore.
- Native Linux filesystem behavior with host synchronization.
- Multiple role-specific development runtimes.
- A Docker-capable runtime with SSH, systemd, Node.js, Python, and diagnostics already prepared.
- A platform layer around local AI-assisted development workflows.

## Design Principle

ADP-OS should not become another container orchestrator.

Docker remains the container layer inside a runtime. ADP-OS provides the outer development runtime lifecycle:

```text
provision
bootstrap
sync
diagnose
snapshot
restore
operate
```

The goal is to give AI agents and developers a reproducible local Linux workstation boundary, not just a container runtime.
