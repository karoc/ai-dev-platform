# AI Dev Platform OS — Self-Hosted, Secure, Programmable Spec-Driven Windows-First Code Execution Sandbox for AI Agent & Computer-Use Agent Development

[简体中文](README.zh-CN.md) | English

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)
[![MCP](https://img.shields.io/badge/MCP_SDK-18_tools-4B8BBE?logo=python)](cli/mcp/server.py)

AI Dev Platform OS, or ADP-OS, is a secure, enterprise-grade, spec-driven self-hosted programmable code execution sandbox infrastructure with hardware-level isolation for AI agent and computer-use agent development on Windows, VMware Workstation, Ubuntu Server, and Mutagen. ADP-OS takes a spec-driven approach: workspace recipes declare projects, tasks, validation commands, milestones, and evaluation hooks upfront, then the platform executes them in an auditable lifecycle with task state tracking and release evidence.

The project provisions isolated, programmable Linux code execution runtimes as self-hosted AI development infrastructure for frontend, backend, and AI agent workloads, keeps workspaces synchronized from Windows into each VM, and creates rollback snapshots for repeatable self-hosted AI coding workflows.

ADP-OS does not replace Docker. It provisions Docker-capable self-hosted Linux runtimes and adds VM lifecycle management, workspace synchronization, role-specific bootstrap, diagnostics, static networking, snapshot rollback, and agent governance — a spec-driven audit chain of workspace recipes, task state tracking, and release evidence — around those runtimes.

> Status: Windows MVP. macOS, Linux hosts, Hyper-V, KVM, container runtimes, and richer workspace orchestration are planned but not implemented yet.

## What It Provides

- Windows control plane implemented in PowerShell 7.
- Self-hosted programmable code execution sandbox infrastructure with hardware-level isolation for AI agents and computer-use agents.
- VMware Workstation VM factory for Ubuntu Server 26.04.
- Remastered Ubuntu autoinstall ISO generation with cloud-init seed data.
- Runtime profiles for `frontend`, `backend`, and `agent`.
- Idempotent SSH bootstrap for Docker, Node.js, Python, ripgrep, fd, tmux, and profile-specific tools.
- Lightweight frontend browser acceptance helpers with on-demand Playwright browser installation.
- Mutagen-based two-way workspace synchronization.
- Static IP networking with configurable NAT subnet and per-runtime addresses.
- VMware snapshot commands for clean rollback points.
- Diagnostics and deployment pre-check scripts.
- Agent-native MCP server and SDK exposing 18 platform, workspace, and runtime tools.
- Agent governance audit chain: task state tracking, milestone checkpoints, evaluation hooks, and release evidence.

## Agent-Native API (MCP)

ADP-OS ships a [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server and SDK (`cli/mcp/server.py`) that exposes the full ADP-OS control plane as 18 agent-accessible tools:

**Platform (3):** `adp_status` — runtime health and SSH reachability. `adp_doctor` — diagnostics with per-issue remediation. `adp_capabilities` — supported features and roadmap.

**Workspace (10):** `adp_workspace_list` — list all projects. `adp_workspace_status` — readiness summary. `adp_workspace_dashboard` — task lifecycle overview. `adp_workspace_project` — single project operational view. `adp_workspace_create` — create project directories. `adp_workspace_open` — workspace entry guidance. `adp_workspace_sync` — per-project sync guidance. `adp_workspace_close` — stop sync for a runtime. `adp_workspace_recipes` — available recipes. `adp_workspace_report` — Markdown release evidence.

**Runtime (5):** `adp_up` — start a VM (plan-only by default). `adp_down` — destroy a VM (plan-only by default). `adp_stop` — graceful VM shutdown. `adp_sync_status` — Mutagen sync health. `adp_sync_stop` — stop a sync session.

All destructive operations default to plan-only mode for safety. Connect any MCP-compatible agent (Claude Desktop, Claude Agent, Hermes, Cursor, etc.) to `cli/mcp/server.py`:

```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python3",
      "args": ["cli/mcp/server.py"],
      "env": { "ADP_HOME": "/path/to/ai-dev-platform" }
    }
  }
}
```

### GitHub Copilot Agent SDK

ADP-OS is natively compatible with the [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk). Load ADP-OS as an MCP server in your Copilot SDK session to access all 18 platform, workspace, and runtime tools. See the **[Copilot SDK Integration Guide](docs/copilot-sdk-integration.md)** for Python and TypeScript quick-start examples, environment variable configuration, and permission patterns.

### Claude Agent Support

ADP-OS is compatible with [Claude Managed Agents](https://docs.anthropic.com/en/docs/agents-and-tools/managed-agents), which support self-hosted MCP sandboxes for agent-native code execution. Connect ADP-OS as an MCP server to give Claude Agent access to all 18 platform, workspace, and runtime tools — including VM lifecycle management, workspace synchronization, and the spec-driven audit chain. Configure `cli/mcp/server.py` in your Claude Agent MCP settings to enable self-hosted sandbox operations for Claude's managed agent workflows.

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

> [!TIP]
> New to ADP-OS? Start with the **[Getting Started](docs/getting-started.md)** guide ([简体中文](docs/zh-CN/getting-started.md)) — a step-by-step tutorial with architecture diagram, prerequisites checklist, expected timeline, and common mistakes.

> [!WARNING]
> ADP-OS provisions local VMs with a default `adp:adp` user and password for automated sudo provisioning. These VMs are designed for local, single-user development on a trusted workstation. Do not expose them to untrusted networks without changing credentials and reviewing SSH access. See [Security](SECURITY.md) for the full local-development security model.

A complete first run consists of prerequisites (VMware, WSL, Mutagen), one-time setup (ISO, clone, install, init), runtime provisioning (up), workspace sync, and health check. See the sections below for each phase.

### One-Time Setup

**Recommended: One-command guided setup:**

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
.\cli\adp.ps1 quickstart
```

`adp quickstart` automatically scans prerequisites first, guides you through ISO download, platform bootstrap (`install.ps1`), initialization (`adp init -Quick`), and diagnostics (`adp doctor`) in a single guided flow. If prerequisites are missing, it shows exactly what to install and exits — fix them, then re-run.

**Before you start, check prerequisites:**

```powershell
.\cli\adp.ps1 precheck
```

`adp precheck` scans all 6 prerequisites (Windows 11, PowerShell 7+, VMware Workstation Pro, WSL+xorriso, Mutagen 0.18.x, OpenSSH) and prints a status table with specific remediation commands for each missing item. Run it before `quickstart` or `install.ps1` to see what you need. Use `adp precheck --help-prereqs` for the full requirements list with OS-specific install commands.

**Alternatively, step-by-step:**

Clone the repository and install the platform:

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
.\\install.ps1
```

Check what you need before continuing:

```powershell
adp precheck
```

Download the Ubuntu Server ISO:

```powershell
# Automatic download (recommended, uses BITS transfer with resume support):
adp iso

# Download a different distro:
adp iso almalinux
adp iso rocky
adp iso debian

# If you're in China, use a mirror for faster download:
adp iso -Url "https://mirrors.aliyun.com/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adp iso -Url "https://mirrors.ustc.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adp iso -Url "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"

# Or download manually:
# PowerShell: Invoke-WebRequest -Uri "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso" -OutFile "$env:USERPROFILE\adp-iso\ubuntu-26.04-live-server-amd64.iso"
# WSL:        wget -P /mnt/c/Users/$env:USERNAME/adp-iso/ https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso
```

For machine-specific paths, VM sizing, static IPs, or local bootstrap credentials, copy the ignored local override example:

```powershell
Copy-Item configs\\local.example.json configs\\local.json
```

See [Configuration](docs/configuration.md#local-overrides) for supported local override sections.

Initialize your first runtime:

```powershell
adp init           # or: adp init -Quick (skip redundant dep re-checks since install.ps1 already ran)
```

> [!NOTE]
> After running `install.ps1`, the `adp.cmd` wrapper is available — use bare `adp` instead of `.\\cli\\adp.ps1` for all subsequent commands.

### Runtime Operations

Create and start runtimes:

```powershell
adp up frontend
adp up backend
adp up agent
```

Check runtime status and connection details:

```powershell
adp status
adp status agent
```

Start workspace synchronization:

```powershell
adp sync start frontend
adp sync start backend
adp sync start agent
```

Prepare frontend browser acceptance testing when needed:

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

Check health:

```powershell
adp doctor
adp doctor -FirstRun
adp doctor -FixMutagen -Plan
adp sync status
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
adp snapshot create frontend clean
adp snapshot create backend clean
adp snapshot create agent clean
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
adp network apply all
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

ADP-OS also includes a multi-scenario, spec-driven workspace recipes manifest for common agent-native workflows. Treat the manifest as a spec: declare what to build, how to validate, and which milestones gate progress, then let the platform execute and produce auditable release evidence:

```powershell
adp workspace show -ManifestPath configs\workspace.recipes.example.json
adp workspace plan -ManifestPath configs\workspace.recipes.example.json
adp workspace recipes -ManifestPath configs\workspace.recipes.example.json
adp workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
adp workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
adp workspace dashboard -ManifestPath configs\workspace.recipes.example.json
adp workspace report -ManifestPath configs\workspace.recipes.example.json
adp workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

The recipes cover low-risk maintenance, frontend browser acceptance, backend validation, and high-risk agent work with a snapshot-first gate. They also demonstrate optional `milestones[]` planning so related tasks can share a visible milestone checkpoint such as `milestone-agent-refactor-safety`, plus plan-only `evaluations[]` hooks so agent-native review criteria, metrics, and declared evaluation commands can appear in release evidence without being executed. `workspace recipes` is the discovery view for these examples: it summarizes project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, creating snapshots, running validation, running evaluation commands, starting sync, or running Git. `workspace create -Plan` previews local project directories declared by the manifest; `workspace create` creates only those local directories and still does not clone projects, start sync, start runtimes, open SSH, create snapshots, run validation, run evaluation commands, or run Git. `workspace open` prints a non-destructive open guide for one project: local path, remote path, readiness, and copyable local, editor, SSH, sync, and status commands. `workspace sync` prints a non-destructive project-aware sync guide: it maps the manifest project back to the runtime sync session, shows sync readiness and sync hygiene, and prints the runtime `adp sync` commands to run explicitly. `workspace project` prints the project operational lifecycle in one place: open, runtime, sync, validation, linked tasks, and evidence handoff. `workspace report` also prints a release handoff summary that counts validation results, lists blockers, shows tasks ready for review or commit, names the current release gate, exposes milestone checkpoint status, exposes evaluation queue status, and exposes task governance fields such as owner, review cadence, and due date. It also groups tasks into owner queues, review cadence queues, milestone queues, milestone review rollups, a validation execution queue, an evaluation queue, an attention queue for recurring review, decision queues for actions such as validate, review, revise, snapshot, or commit, a release decision policy, and stale-task remediation guidance. Add `-Markdown` to generate copyable PR or release evidence with the same decision state, including Validation Execution Queue, Evaluation Queue, Milestone Checkpoints, and Milestone Review Rollup tables. The recipes are planning examples only; the workspace commands do not install packages, download browsers, create snapshots, run validation, run evaluation commands, open editors, SSH into runtimes, start sync, stop sync, or commit files.

Validation can be executed explicitly from a task recipe:

```powershell
adp workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
adp workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` previews the readiness gate and remote SSH commands. `-Execute` runs only the declared `tasks[].validation` commands in the target project directory and records the result in ignored local workspace state. Review, rollback, and commit commands read that recorded result to show decision gates, but staging, restore, and commit execution remain separate explicit steps.

## Command Reference

```powershell
adp iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]
adp quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive]
adp init
adp init <frontend|backend|agent> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]
adp up <frontend|backend|agent> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
adp status [frontend|backend|agent]
adp capabilities
adp stop <frontend|backend|agent>
adp sync status
adp workspace init
adp workspace show
adp workspace plan
adp workspace status
adp workspace dashboard
adp workspace recipes
adp workspace create [-Plan]
adp workspace open [project-name]
adp workspace sync [project-name]
adp workspace project [project-name]
adp workspace report
adp workspace report [-Markdown]
adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
adp workspace task validate <task-name> [-Execute] [-Plan]
adp workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed>
adp sync start <frontend|backend|agent>
adp sync stop <frontend|backend|agent>
adp network apply <frontend|backend|agent|all> [-Plan]
adp snapshot create <runtime> <name>
adp restore <runtime> <name>
adp logs <runtime>
adp doctor [-FirstRun] [-FixMutagen] [-Plan]
adp destroy <runtime> [-Plan]
```

## What Success Looks Like

A healthy ADP-OS installation produces output like the following.

### `adp status` — all runtimes running

```text
RUNTIME   STATE     IP               SSH
frontend  running   192.168.242.131  adp-os-adp-frontend
backend   running   192.168.242.133  adp-os-adp-backend
agent     running   192.168.242.135  adp-os-adp-agent
```

### `adp doctor` — all checks passing

```text
[PASS] VMware Workstation      (vmrun.exe found)
[PASS] VMware Disk Manager     (vmware-vdiskmanager.exe found)
[PASS] WSL                     (WSL detected)
[PASS] WSL xorriso             (xorriso 1.5.6 available)
[PASS] Mutagen                 (0.18.1)
[PASS] OpenSSH                 (OpenSSH_for_Windows_9.5p1)
[PASS] Ubuntu ISO              (ubuntu-26.04-live-server-amd64.iso present)

Doctor complete: 7/7 checks passed.
```

### `adp sync status` — workspaces syncing

```text
RUNTIME   STATUS    SOURCE                              DEST
frontend  watching  %USERPROFILE%\adp-workspaces\fron... /home/adp/workspace
backend   watching  %USERPROFILE%\adp-workspaces\back... /home/adp/workspace
agent     watching  %USERPROFILE%\adp-workspaces\agent   /home/adp/workspace
```

## Documentation

- **[Getting Started](docs/getting-started.md)** ([简体中文](docs/zh-CN/getting-started.md)) — first-time setup tutorial.
- **[Copilot SDK Integration](docs/copilot-sdk-integration.md)** ([简体中文](docs/zh-CN/copilot-sdk-integration.md)) — load ADP-OS tools into the GitHub Copilot Agent SDK.
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

## Security

ADP-OS follows a **local-development security model** designed for single-user, trusted-workstation environments. Default provisioning uses a local `adp:adp` credential for automated sudo — these runtimes are **not** intended for exposed, shared, production, or multi-tenant environments. See [SECURITY.md](SECURITY.md) for the full policy, including credential rotation, network hardening, and vulnerability reporting.

Runtime secrets, VM disks, ISO images, logs, local tool binaries, and local assistant settings are excluded from version control.

## License

MIT. See [LICENSE](LICENSE).
