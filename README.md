# ADP-OS — The Notary for AI Development: Auditable, Reproducible, Provable

[简体中文](README.zh-CN.md) | English

[![CI](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/karoc/ai-dev-platform/actions/workflows/ci.yml)
[![MCP](https://img.shields.io/badge/MCP_SDK-26_tools-4B8BBE?logo=python)](cli/mcp/server.py)
[![Support](https://img.shields.io/badge/Support-GitHub_Issues-2ea44f?logo=github)](https://github.com/karoc/ai-dev-platform/issues/new/choose)

ADP-OS is a platform that makes AI-assisted development auditable. It produces a verifiable **evidence chain** — snapshot signatures, operation logs, and exportable evidence packages — so you can prove what was built, how it was built, and who (or what AI) wrote each piece. Every development action is recorded, every workspace state is snapshot-addressable, and every release ships with an audit trail.

ADP-OS provisions isolated, programmable Linux code execution runtimes as self-hosted AI development infrastructure for frontend, backend, and AI agent workloads, keeps workspaces synchronized from Windows into each VM, and creates rollback snapshots for repeatable AI coding workflows. It is Windows-first, running on VMware Workstation, Ubuntu Server, and Mutagen.

ADP-OS does not replace Docker. It provisions Docker-capable self-hosted Linux runtimes and adds VM lifecycle management, workspace synchronization, role-specific bootstrap, diagnostics, static networking, snapshot rollback, and agent governance — a spec-driven audit chain of workspace recipes, task state tracking, and release evidence — around those runtimes.

> Status: Windows MVP. macOS, Linux hosts, Hyper-V, KVM, container runtimes, and richer workspace orchestration are planned but not implemented yet.

## Why ADP-OS?

AI is writing more code every day. But when an AI generates a commit, how do you know what happened? Who reviewed it? What was the environment? What commands actually ran?

ADP-OS answers these questions with a verifiable **evidence chain**:

- **Snapshot signatures** — Every VM state checkpoint is hashed and timestamped, so you can prove the exact environment a piece of code was built in.
- **Operation logs** — Every `adpos up`, `adpos sync`, `adpos snapshot`, and validation run is logged with operation type, timestamp, and outcome.
- **Evidence export** — `adpos workspace evidence -Export` packages all logs, signatures, task states, and AI declarations into a single ZIP archive for compliance, review, or publication.
- **AI declarations** — `adpos workspace declare -AiAssisted` records who reviewed AI-generated code, creating a provenance trail from prompt to production.

```
以前：ADP-OS 是一个管理 AI 开发 VM 的工具。
现在：ADP-OS 是一个让 AI 开发可审计的平台。
未来：ADP-OS 是一个让 AI 开发可信的基础设施。
```

> *Before: ADP-OS was a tool for managing AI dev VMs.*
> *Now: ADP-OS is a platform that makes AI development auditable.*
> *Future: ADP-OS will be infrastructure that makes AI development trustworthy.*

## What It Provides

- **Evidence chain** — Snapshot signing (`adpos workspace evidence -Snapshot`), operation logs (`adpos workspace evidence -Log`), evidence package export (`adpos workspace evidence -Export`), and AI-assisted development declarations (`adpos workspace declare -AiAssisted`). Every build is auditable, every AI contribution is recorded.
- **Windows-first VM sandbox** — Local-first, self-hosted programmable code execution sandbox infrastructure with hardware-level isolation for AI agents and computer-use agents. Windows control plane implemented in PowerShell 7.
- VMware Workstation VM factory for Ubuntu Server 26.04.
- Remastered Ubuntu autoinstall ISO generation with cloud-init seed data.
- Runtime profiles for `frontend`, `backend`, and `agent`.
- Idempotent SSH bootstrap for Docker, Node.js, Python, ripgrep, fd, tmux, and profile-specific tools.
- Lightweight frontend browser acceptance helpers with on-demand Playwright browser installation.
- Mutagen-based two-way workspace synchronization.
- Static IP networking with configurable NAT subnet and per-runtime addresses.
- VMware snapshot commands for clean rollback points.
- Diagnostics and deployment pre-check scripts.
- Agent-native MCP server and SDK exposing 26 platform, workspace, runtime, and in-VM sandbox tools.
- Agent governance audit chain: task state tracking, milestone checkpoints, evaluation hooks, and release evidence.

## Agent-Native API (MCP)

ADP-OS ships a [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server and SDK (`cli/mcp/server.py`) that exposes the full ADP-OS control plane as 26 agent-accessible tools:

**Platform (3):** `adp_status` — runtime health and SSH reachability. `adp_doctor` — diagnostics with per-issue remediation. `adp_capabilities` — supported features and roadmap.

**Workspace (10):** `adp_workspace_list` — list all projects. `adp_workspace_status` — readiness summary. `adp_workspace_dashboard` — task lifecycle overview. `adp_workspace_project` — single project operational view. `adp_workspace_create` — create project directories. `adp_workspace_open` — workspace entry guidance. `adp_workspace_sync` — per-project sync guidance. `adp_workspace_close` — stop sync for a runtime. `adp_workspace_recipes` — available recipes. `adp_workspace_report` — Markdown release evidence.

**Runtime (5):** `adp_up` — start a VM (plan-only by default). `adp_down` — destroy a VM (plan-only by default). `adp_stop` — graceful VM shutdown. `adp_sync_status` — Mutagen sync health. `adp_sync_stop` — stop a sync session.

**In-VM Sandbox (8):** `adp_exec` — run a command over SSH. `adp_file_read` — read a file. `adp_file_write` — write a file. `adp_dir_list` — list directories. `adp_glob` — match files. `adp_grep` — search file contents. `adp_file_download` — download file contents. `adp_file_upload` — upload file contents.

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

ADP-OS is natively compatible with the [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk). Load ADP-OS as an MCP server in your Copilot SDK session to access all 26 platform, workspace, runtime, and in-VM sandbox tools. See the **[Copilot SDK Integration Guide](docs/copilot-sdk-integration.md)** for Python and TypeScript quick-start examples, environment variable configuration, and permission patterns.

### Claude Agent Support

ADP-OS is compatible with [Claude Managed Agents](https://docs.anthropic.com/en/docs/agents-and-tools/managed-agents), which support self-hosted MCP sandboxes for agent-native code execution. Connect ADP-OS as an MCP server to give Claude Agent access to all 26 platform, workspace, runtime, and in-VM sandbox tools — including VM lifecycle management, workspace synchronization, VM command execution, file operations, and the spec-driven audit chain. Configure `cli/mcp/server.py` in your Claude Agent MCP settings to enable self-hosted sandbox operations for Claude's managed agent workflows.

## Requirements

- Windows 11.
- Git for cloning the repository.
- PowerShell 7 or newer. `setup.cmd` is the stock Windows shell bootstrap entry point; if PowerShell 7 is missing, it attempts to install it with `winget` and then continues setup. If automatic installation is unavailable, it prints the manual `winget` / MSI path. The ADP-OS control plane runs on PowerShell 7.
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

**Recommended: one-click setup from a stock Windows shell — clone and run one command:**

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
.\setup.cmd
```

If you already have PowerShell 7 open, you can run the PowerShell entry point directly:

```powershell
.\setup.ps1
```

Both entries guide you through the entire setup in one pass: prerequisite scanning, ISO download (~2.6 GB), platform bootstrap, initialization, and system diagnostics. If PowerShell 7 is missing, `setup.cmd` and `setup.ps1` first try to install it with `winget`; if that cannot produce a working `pwsh.exe`, they print the manual install path and exit before running the ADP-OS control plane. If you launch `setup.ps1` from built-in Windows PowerShell 5.1 and PowerShell 7 is available or successfully installed, it restarts itself with `pwsh.exe`.

Setup also registers the global `adpos` command for your user account, so after installation you can run ADP-OS from any directory. ADP-OS exposes `adpos` as the only user-facing shell command. Open a new terminal if the current shell has not picked up the updated user `PATH` yet; from the repository root, use `.\adpos.cmd` as the local wrapper.

Multiple ADP-OS checkouts can coexist. The global `adpos` command can point to only one checkout at a time; if setup detects an existing global binding to another checkout, it asks whether to replace it. If you keep the existing binding, use `.\adpos.cmd` from the new checkout. Before running multiple VM environments side by side, configure distinct local paths and network settings such as workspace root, VM store, and static IPs.

**Options:**

```powershell
.\setup.cmd -IsoPath C:\...\ubuntu.iso   # Use a pre-downloaded ISO
.\setup.cmd -SkipIsoDownload              # Skip ISO download (already cached)
.\setup.cmd -NonInteractive               # Run without prompts (for scripts/CI)
.\setup.cmd -Force                        # Skip precheck, proceed anyway
```

**Before you start, check prerequisites:**

```powershell
.\adpos.cmd precheck
```

`adpos precheck` scans all 6 prerequisites (Windows 11, PowerShell 7+, VMware Workstation Pro, WSL+xorriso, Mutagen 0.18.x, OpenSSH) and prints a status table with specific remediation commands for each missing item. Run it before `setup.cmd` or `install.ps1` to see what you need. Use `.\adpos.cmd precheck --help-prereqs` for the full requirements list with OS-specific install commands.

**Alternatively, step-by-step:**

Clone the repository and install the platform:

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
pwsh.exe -ExecutionPolicy Bypass -File .\install.ps1
```

Check what you need before continuing:

```powershell
.\adpos.cmd precheck
```

Download the Ubuntu Server ISO:

```powershell
# Automatic download (recommended, uses BITS transfer with resume support):
adpos iso

# Download a different distro:
adpos iso almalinux
adpos iso rocky
adpos iso debian

# If you're in China, use a mirror for faster download:
adpos iso -Url "https://mirrors.aliyun.com/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adpos iso -Url "https://mirrors.ustc.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"
adpos iso -Url "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso"

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
adpos init           # or: adpos init -Quick (skip redundant dep re-checks since install.ps1 already ran)
```

> [!NOTE]
> Use `adpos` as the formal command after setup. From the repository root, `.\adpos.cmd` is available if your current shell has not refreshed `PATH`.

### Runtime Operations

Create and start runtimes:

```powershell
adpos up frontend
adpos up backend
adpos up agent
```

Check runtime status and connection details:

```powershell
adpos status
adpos status agent
```

Start workspace synchronization:

```powershell
adpos sync start frontend
adpos sync start backend
adpos sync start agent
```

Prepare frontend browser acceptance testing when needed:

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
adp-frontend-browser-install chromium
```

Check health:

```powershell
adpos doctor
adpos doctor -FirstRun
adpos doctor -FixMutagen -Plan
adpos sync status
```

`install.ps1` and `doctor` check VMware tooling, `vmware-vdiskmanager.exe`, WSL, WSL `xorriso`, Mutagen 0.18.x, OpenSSH, ISO presence, and basic ISO shape. They print remediation commands or placement guidance, but do not download large binaries by default. To install the tested local Mutagen binary, preview first with `adpos doctor -FixMutagen -Plan`, then run `adpos doctor -FixMutagen`; the archive and extracted binary stay under ignored `.tools\mutagen`. If GitHub release downloads are slow or blocked, place `mutagen_windows_amd64_v0.18.1.zip` under `.tools\mutagen` or set `platform.tools.mutagen.archive_path` in `configs\local.json`; set `platform.tools.mutagen.sha256` to enforce archive hash verification.

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
adpos snapshot create frontend clean
adpos snapshot create backend clean
adpos snapshot create agent clean
```

Sign your snapshot and export the evidence chain:

```powershell
adpos workspace evidence -Snapshot
adpos workspace evidence -Export
adpos workspace declare -AiAssisted -Reviewer "your-name"
```

Uninstall the user-level command registration in one step:

```powershell
adpos uninstall
```

This only removes the user-level `adpos` PATH shim. It does not delete VMs, workspace files, ISO cache, local tools, logs, or repository files.

If `adpos` is not available in the current shell, run the repository-root wrapper instead:

```powershell
.\uninstall.cmd
```

## Default Runtimes

| Runtime | Purpose | CPU | Memory | Disk | Static IP |
| --- | --- | ---: | ---: | ---: | --- |
| `frontend` | JavaScript and frontend development | 4 | 8192 MB | 80 GB | `192.168.242.131` |
| `backend` | Python and backend development | 4 | 8192 MB | 120 GB | `192.168.242.133` |
| `agent` | AI agent runtime with higher IO tuning | 6 | 16384 MB | 160 GB | `192.168.242.135` |
| `sandbox` | Small isolated runtime for sandbox integrations | 2 | 4096 MB | 40 GB | `192.168.242.137` |

Static addresses are configured in `configs\topology.json`. The VMware NAT subnet, gateway, DNS, and interface match are configured in `configs\platform.json`.

Apply configured networking to existing VMs:

```powershell
adpos network apply all
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
adpos workspace show -ManifestPath configs\workspace.recipes.example.json
adpos workspace plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace recipes -ManifestPath configs\workspace.recipes.example.json
adpos workspace create -Plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace open frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace sync frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace project frontend-app -ManifestPath configs\workspace.recipes.example.json
adpos workspace dashboard -ManifestPath configs\workspace.recipes.example.json
adpos workspace report -ManifestPath configs\workspace.recipes.example.json
adpos workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

The recipes cover low-risk maintenance, frontend browser acceptance, backend validation, and high-risk agent work with a snapshot-first gate. They also demonstrate optional `milestones[]` planning so related tasks can share a visible milestone checkpoint such as `milestone-agent-refactor-safety`, plus plan-only `evaluations[]` hooks so agent-native review criteria, metrics, and declared evaluation commands can appear in release evidence without being executed. `workspace recipes` is the discovery view for these examples: it summarizes project recipes, task recipes, milestone checkpoints, evaluation hooks, and evidence commands without cloning projects, opening SSH, creating snapshots, running validation, running evaluation commands, starting sync, or running Git. `workspace create -Plan` previews local project directories declared by the manifest; `workspace create` creates only those local directories and still does not clone projects, start sync, start runtimes, open SSH, create snapshots, run validation, run evaluation commands, or run Git. `workspace open` prints a non-destructive open guide for one project: local path, remote path, readiness, and copyable local, editor, SSH, sync, and status commands. `workspace sync` prints a non-destructive project-aware sync guide: it maps the manifest project back to the runtime sync session, shows sync readiness and sync hygiene, and prints the runtime `adpos sync` commands to run explicitly. `workspace project` prints the project operational lifecycle in one place: open, runtime, sync, validation, linked tasks, and evidence handoff. `workspace report` also prints a release handoff summary that counts validation results, lists blockers, shows tasks ready for review or commit, names the current release gate, exposes milestone checkpoint status, exposes evaluation queue status, and exposes task governance fields such as owner, review cadence, and due date. It also groups tasks into owner queues, review cadence queues, milestone queues, milestone review rollups, a validation execution queue, an evaluation queue, an attention queue for recurring review, decision queues for actions such as validate, review, revise, snapshot, or commit, a release decision policy, and stale-task remediation guidance. Add `-Markdown` to generate copyable PR or release evidence with the same decision state, including Validation Execution Queue, Evaluation Queue, Milestone Checkpoints, and Milestone Review Rollup tables. The recipes are planning examples only; the workspace commands do not install packages, download browsers, create snapshots, run validation, run evaluation commands, open editors, SSH into runtimes, start sync, stop sync, or commit files.

Validation can be executed explicitly from a task recipe:

```powershell
adpos workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\workspace.recipes.example.json
adpos workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\workspace.recipes.example.json
```

`-Execute -Plan` previews the readiness gate and remote SSH commands. `-Execute` runs only the declared `tasks[].validation` commands in the target project directory and records the result in ignored local workspace state. Review, rollback, and commit commands read that recorded result to show decision gates, but staging, restore, and commit execution remain separate explicit steps.

## Command Reference

The reference uses `adpos`, the formal command installed by `.\setup.cmd`. From the repository root, `.\adpos.cmd ...` is the local wrapper if your current shell has not refreshed `PATH`. MCP tool names such as `adp_status` stay unchanged protocol identifiers.

`adpos uninstall` removes only the global command registration. Runtime data, workspace data, caches, tools, logs, and repository files remain untouched.

```powershell
adpos setup [-IsoPath <path>] [-SkipIsoDownload] [-NonInteractive] [-Force]
adpos uninstall
adpos iso [ubuntu|almalinux|rocky|debian] [-Url <url>] [-Force] [-NonInteractive]
adpos quickstart [-Distro <name>] [-IsoPath <path>] [-SkipIsoDownload] [-SkipDoctor] [-Force] [-NonInteractive]
adpos init
adpos init <frontend|backend|agent|sandbox> [-IsoPath <path>] [-NoProvision] [-Quick] [-NonInteractive]
adpos up <frontend|backend|agent|sandbox> [-IsoPath <path>] [-Plan] [-NoProvision] [-NoBootstrap]
adpos status [frontend|backend|agent|sandbox]
adpos capabilities
adpos stop <frontend|backend|agent|sandbox>
adpos sync status
adpos workspace init
adpos workspace show
adpos workspace plan
adpos workspace status
adpos workspace dashboard
adpos workspace recipes
adpos workspace create [-Plan]
adpos workspace open [project-name]
adpos workspace sync [project-name]
adpos workspace project [project-name]
adpos workspace report
adpos workspace report [-Markdown]
adpos workspace evidence -Snapshot [-Json]                        Sign current snapshot metadata (SHA-256 chain)
adpos workspace evidence -Log -Operation <op> [-Details <text>] [-Json]  Record operation log entry
adpos workspace evidence -Export [-Path <path>]                   Export all evidence as ZIP
adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes "..."] [-Json]  Declare AI-assisted development
adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>
adpos workspace task validate <task-name> [-Execute] [-Plan]
adpos workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed>
adpos sync start <frontend|backend|agent|sandbox>
adpos sync stop <frontend|backend|agent|sandbox>
adpos network apply <frontend|backend|agent|sandbox|all> [-Plan]
adpos snapshot create <runtime> <name>
adpos restore <runtime> <name>
adpos logs <runtime>
adpos doctor [-FirstRun] [-FixMutagen] [-Plan]
adpos destroy <runtime> [-Plan]
adpos workspace evidence -Snapshot [-ManifestPath <path>]
adpos workspace evidence -Log -Operation <op> [-Details <text>] [-ManifestPath <path>]
adpos workspace evidence -Export [-Path <path>] [-ManifestPath <path>]
adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes "..."] [-ManifestPath <path>]
```

## What Success Looks Like

A healthy ADP-OS installation produces output like the following.

### `adpos status` — all runtimes running

```text
RUNTIME   STATE     IP               SSH
frontend  running   192.168.242.131  adp-os-adp-frontend
backend   running   192.168.242.133  adp-os-adp-backend
agent     running   192.168.242.135  adp-os-adp-agent
```

### `adpos doctor` — all checks passing

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

### `adpos sync status` — workspaces syncing

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
- [Evidence Chain](docs/evidence.md)
- [Survival Validation](docs/survival-validation.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Networking](docs/networking.md)
- [Browser Testing](docs/browser-testing.md)
- [Historical Implementation Brief](build.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Community

- **[GitHub Issues](https://github.com/karoc/ai-dev-platform/issues/new/choose)** — Use the templates for installation help, usage questions, reproducible bugs, and feature requests.
- **[Contributing](CONTRIBUTING.md)** — Development environment setup, coding guidelines, and PR process.
- **[Demo](docs/demo.cast)** — Quick terminal orientation: clone → doctor → plan → status → MCP (30s, play with `asciinema play`). [10-minute presenter script →](docs/demo-script.md)
- **[Survival Validation](docs/survival-validation.md)** — First-users validation process for the 10-minute demo, rollback result, evidence export, and feedback capture.
- **[Discord setup plan](docs/discord-setup.md)** — Planned community chat setup. It is not an active support channel until an invite link is published.

## Security

ADP-OS follows a **local-development security model** designed for single-user, trusted-workstation environments. Default provisioning uses a local `adp:adp` credential for automated sudo — these runtimes are **not** intended for exposed, shared, production, or multi-tenant environments. See [SECURITY.md](SECURITY.md) for the full policy, including credential rotation, network hardening, and vulnerability reporting.

Runtime secrets, VM disks, ISO images, logs, local tool binaries, and local assistant settings are excluded from version control.

## License

MIT. See [LICENSE](LICENSE).
