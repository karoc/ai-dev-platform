# AI Dev Platform OS

[简体中文](README.zh-CN.md) | English

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)

AI Dev Platform OS, or ADP-OS, is a local AI development runtime platform for Windows, VMware Workstation, Ubuntu Server, and Mutagen.

The project provisions isolated Linux runtimes for frontend, backend, and agent workloads, keeps workspaces synchronized from Windows into each VM, and creates rollback snapshots for repeatable local AI coding workflows.

ADP-OS does not replace Docker. It provisions Docker-capable local Linux runtimes and adds VM lifecycle management, workspace synchronization, role-specific bootstrap, diagnostics, static networking, and snapshot rollback around those runtimes.

> Status: Windows MVP. macOS, Linux hosts, Hyper-V, KVM, container runtimes, and richer workspace orchestration are planned but not implemented yet.

## What It Provides

- Windows control plane implemented in PowerShell 7.
- VMware Workstation VM factory for Ubuntu Server 26.04.
- Remastered Ubuntu autoinstall ISO generation with cloud-init seed data.
- Runtime profiles for `frontend`, `backend`, and `agent`.
- Idempotent SSH bootstrap for Docker, Node.js, Python, ripgrep, fd, tmux, and profile-specific tools.
- Lightweight frontend browser acceptance helpers with on-demand Playwright browser installation.
- Mutagen-based two-way workspace synchronization.
- Static IP networking with configurable NAT subnet and per-runtime addresses.
- VMware snapshot commands for clean rollback points.
- Diagnostics and deployment pre-check scripts.

## Requirements

- Windows 11.
- PowerShell 7 or newer.
- VMware Workstation Pro with `vmrun.exe` and `vmware-vdiskmanager.exe`.
- Ubuntu Server 26.04 live server ISO.
- WSL with `xorriso` or another compatible ISO remastering path.
- OpenSSH client.
- Mutagen 0.18.x, either on `PATH` or at `.tools\mutagen\mutagen.exe`.

Install `xorriso` in WSL:

```powershell
wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"
```

## Quick Start

Clone the repository:

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
```

Place the Ubuntu ISO at:

```text
%USERPROFILE%\adp-iso\ubuntu-26.04-live-server-amd64.iso
```

Or pass it during initialization:

```powershell
.\install.ps1 -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso
```

For machine-specific paths, VM sizing, static IPs, or local bootstrap credentials, copy the ignored local override example:

```powershell
Copy-Item configs\local.example.json configs\local.json
```

See [Configuration](docs/configuration.md#local-overrides) for supported local override sections.

Initialize the platform:

```powershell
.\install.ps1
.\cli\adp.ps1 init
```

Create and start runtimes:

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

Check runtime status and connection details:

```powershell
.\cli\adp.ps1 status
.\cli\adp.ps1 status agent
```

Start workspace synchronization:

```powershell
.\cli\adp.ps1 sync start frontend
.\cli\adp.ps1 sync start backend
.\cli\adp.ps1 sync start agent
```

Prepare frontend browser acceptance testing when needed:

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

Check health:

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 doctor -FixMutagen -Plan
.\cli\adp.ps1 sync status
```

`install.ps1` and `doctor` check VMware tooling, `vmware-vdiskmanager.exe`, WSL, WSL `xorriso`, Mutagen 0.18.x, OpenSSH, ISO presence, and basic ISO shape. They print remediation commands or placement guidance, but do not download large binaries by default. To install the tested local Mutagen binary, preview first with `doctor -FixMutagen -Plan`, then run `doctor -FixMutagen`; the archive and extracted binary stay under ignored `.tools\mutagen`. If GitHub release downloads are slow or blocked, place `mutagen_windows_amd64_v0.18.1.zip` under `.tools\mutagen` or set `platform.tools.mutagen.archive_path` in `configs\local.json`; set `platform.tools.mutagen.sha256` to enforce archive hash verification.

Run non-destructive validation:

```powershell
.\tests\validate.ps1
```

For faster local iteration, run:

```powershell
.\tests\validate.ps1 -Quick
```

For targeted validation:

```powershell
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

Create clean snapshots:

```powershell
.\cli\adp.ps1 snapshot create frontend clean
.\cli\adp.ps1 snapshot create backend clean
.\cli\adp.ps1 snapshot create agent clean
```

## Default Runtimes

| Runtime | Purpose | CPU | Memory | Disk | Static IP |
| --- | --- | ---: | ---: | ---: | --- |
| `frontend` | JavaScript and frontend development | 4 | 8192 MB | 80 GB | `192.168.242.131` |
| `backend` | Python and backend development | 4 | 8192 MB | 120 GB | `192.168.242.133` |
| `agent` | AI agent runtime with higher IO tuning | 6 | 16384 MB | 160 GB | `192.168.242.135` |

Static addresses are configured in `configs\topology.json`. The VMware NAT subnet, gateway, DNS, and interface match are configured in `configs\platform.json`.

Apply configured networking to existing VMs:

```powershell
.\cli\adp.ps1 network apply all
```

## Workspace Paths

By default, Windows workspaces are created under:

```text
%USERPROFILE%\adp-workspaces
```

They are synchronized into each VM at:

```text
/home/adp/workspace
```

Keep target projects separate from the ADP-OS platform repository. Clone application or experiment repositories under the runtime workspace root, for example:

```powershell
cd $env:USERPROFILE\adp-workspaces\agent
git clone <project-url> my-project
```

Examples:

```text
%USERPROFILE%\adp-workspaces\frontend  <->  frontend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\backend   <->  backend:/home/adp/workspace
%USERPROFILE%\adp-workspaces\agent     <->  agent:/home/adp/workspace
```

See [Workspaces](docs/workspaces.md) for target-project layout and ADP-OS dogfooding guidance.
See [Capabilities](docs/capabilities.md) for the current supported runtime and adapter boundary. See [Roadmap](docs/roadmap.md) for the public product direction across workspace orchestration, agent-native development, and runtime expansion. See [Release Readiness](docs/release-readiness.md) for the release decision policy, stale-task remediation flow, and maintainer checklist. See [Release Process](docs/release-process.md) for validation, evidence, safety checks, and publication boundaries. See [Contributor Workflows](docs/contributor-workflows.md) for task templates, maintainer review ritual, and pull request expectations.

ADP-OS also includes a multi-scenario workspace recipes manifest for common agent-native workflows:

```powershell
.\cli\adp.ps1 workspace show -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace recipes -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace dashboard -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

The recipes cover low-risk maintenance, frontend browser acceptance, backend validation, and high-risk agent work with a snapshot-first gate. They also demonstrate optional `milestones[]` planning so related tasks can share a visible milestone checkpoint such as `milestone-agent-refactor-safety`, plus plan-only `evaluations[]` hooks so agent-native review criteria, metrics, and declared evaluation commands can appear in release evidence without being executed. `workspace recipes` is the discovery view for these examples: it summarizes project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, creating snapshots, running validation, running evaluation commands, starting sync, or running Git. `workspace create -Plan` previews local project directories declared by the manifest; `workspace create` creates only those local directories and still does not clone projects, start sync, start runtimes, open SSH, create snapshots, run validation, run evaluation commands, or run Git. `workspace open` prints a non-destructive open guide for one project: local path, remote path, readiness, and copyable local, editor, SSH, sync, and status commands. `workspace sync` prints a non-destructive project-aware sync guide: it maps the manifest project back to the runtime sync session, shows sync readiness and sync hygiene, and prints the runtime `adp sync` commands to run explicitly. `workspace project` prints the project operational lifecycle in one place: open, runtime, sync, validation, linked tasks, and evidence handoff. `workspace report` also prints a release handoff summary that counts validation results, lists blockers, shows tasks ready for review or commit, names the current release gate, exposes milestone checkpoint status, exposes evaluation queue status, and exposes task governance fields such as owner, review cadence, and due date. It also groups tasks into owner queues, review cadence queues, milestone queues, milestone review rollups, a validation execution queue, an evaluation queue, an attention queue for recurring review, decision queues for actions such as validate, review, revise, snapshot, or commit, a release decision policy, and stale-task remediation guidance. Add `-Markdown` to generate copyable PR or release evidence with the same decision state, including Validation Execution Queue, Evaluation Queue, Milestone Checkpoints, and Milestone Review Rollup tables. The recipes are planning examples only; the workspace commands do not install packages, download browsers, create snapshots, run validation, run evaluation commands, open editors, SSH into runtimes, start sync, stop sync, or commit files.

Validation can be executed explicitly from a task recipe:

```powershell
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` previews the readiness gate and remote SSH commands. `-Execute` runs only the declared `tasks[].validation` commands in the target project directory and records the result in ignored local workspace state. Review, rollback, and commit commands read that recorded result to show decision gates, but staging, restore, and commit execution remain separate explicit steps.

## Command Reference

```powershell
.\cli\adp.ps1 init
.\cli\adp.ps1 init <frontend|backend|agent> [-IsoPath <path>] [-SkipProvision]
.\cli\adp.ps1 up <frontend|backend|agent> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
.\cli\adp.ps1 status [frontend|backend|agent]
.\cli\adp.ps1 capabilities
.\cli\adp.ps1 stop <frontend|backend|agent>
.\cli\adp.ps1 sync status
.\cli\adp.ps1 workspace init
.\cli\adp.ps1 workspace show
.\cli\adp.ps1 workspace plan
.\cli\adp.ps1 workspace status
.\cli\adp.ps1 workspace dashboard
.\cli\adp.ps1 workspace recipes
.\cli\adp.ps1 workspace create [-Plan]
.\cli\adp.ps1 workspace open [project-name]
.\cli\adp.ps1 workspace sync [project-name]
.\cli\adp.ps1 workspace project [project-name]
.\cli\adp.ps1 workspace report
.\cli\adp.ps1 workspace report [-Markdown]
.\cli\adp.ps1 workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
.\cli\adp.ps1 workspace task validate <task-name> [-Execute] [-Plan]
.\cli\adp.ps1 workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed>
.\cli\adp.ps1 sync start <frontend|backend|agent>
.\cli\adp.ps1 sync stop <frontend|backend|agent>
.\cli\adp.ps1 network apply <frontend|backend|agent|all> [-Plan]
.\cli\adp.ps1 snapshot create <runtime> <name>
.\cli\adp.ps1 restore <runtime> <name>
.\cli\adp.ps1 logs <runtime>
.\cli\adp.ps1 doctor [-FirstRun] [-FixMutagen] [-Plan]
.\cli\adp.ps1 destroy <runtime> [-Plan]
```

## Documentation

- [Documentation Home](docs/README.md)
- [ADP-OS and Docker](docs/positioning.md)
- [Architecture](docs/architecture.md)
- [Configuration](docs/configuration.md)
- [Workspaces](docs/workspaces.md)
- [Capabilities](docs/capabilities.md)
- [Roadmap](docs/roadmap.md)
- [Release Readiness](docs/release-readiness.md)
- [Release Process](docs/release-process.md)
- [Contributor Workflows](docs/contributor-workflows.md)
- [Operations](docs/operations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Networking](docs/networking.md)
- [Browser Testing](docs/browser-testing.md)
- [Historical Implementation Brief](build.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Security Notes

This MVP is designed for local, single-user development. It uses a default runtime user named `adp` and a default bootstrap password of `adp` to automate sudo during provisioning. Do not expose these VMs directly to untrusted networks without changing credentials and reviewing SSH access.

Runtime secrets, VM disks, ISO images, logs, local tool binaries, and local assistant settings are excluded from version control.

## License

MIT. See [LICENSE](LICENSE).
