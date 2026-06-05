# Deer-Flow Integration Guide

[简体中文](zh-CN/deer-flow-integration.md) | English

ADP-OS ships a standard [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that can be loaded as an MCP server in [ByteDance/deer-flow](https://github.com/bytedance/deer-flow) (70K⭐). Configure it once and all 18 ADP-OS platform, workspace, and runtime tools are available to deer-flow agents.

> **Scope**: This guide covers configuring the ADP-OS MCP server in deer-flow for VM lifecycle management. For full sandbox replacement (in-VM code execution), see [Gap Analysis](integrations/deer-flow.md).

## Quick Start

### 1. Install MCP server dependencies

```bash
cd /path/to/ai-dev-platform/cli/mcp
pip install -r requirements.txt
```

### 2. Configure deer-flow

Copy the example extensions config if you haven't already:

```bash
cd /path/to/deer-flow
cp extensions_config.example.json extensions_config.json
```

Add the ADP-OS MCP server entry to `extensions_config.json`:

#### Windows (Native)

```json
{
  "mcpServers": {
    "adp-os": {
      "enabled": true,
      "type": "stdio",
      "command": "python",
      "args": ["D:\\Dev\\ai-dev-platform\\cli\\mcp\\server.py"],
      "env": {
        "ADP_HOME": "D:\\Dev\\ai-dev-platform"
      },
      "description": "ADP-OS VM sandbox backend — 18 tools for platform, workspace, and runtime management"
    }
  }
}
```

On Windows, only `ADP_HOME` is needed. The server auto-detects the platform and treats paths as native Windows paths.

#### WSL (Python in WSL, pwsh.exe on Windows host)

```json
{
  "mcpServers": {
    "adp-os": {
      "enabled": true,
      "type": "stdio",
      "command": "python3",
      "args": ["/home/user/ai-dev-platform/cli/mcp/server.py"],
      "env": {
        "ADP_HOME": "/home/user/ai-dev-platform",
        "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
      },
      "description": "ADP-OS VM sandbox backend — 18 tools for platform, workspace, and runtime management"
    }
  }
}
```

On WSL, set both `ADP_HOME` (WSL path) and `ADP_HOME_WIN` (Windows host path). The server converts between WSL and Windows paths automatically via `wslpath`.

### 3. Restart deer-flow

Restart the deer-flow services. The ADP-OS tools will be discovered and registered at startup.

### 4. Verify

Ask a deer-flow agent: "Show me ADP-OS platform status"

The agent should call `adp_status` and report runtime health.

## Available Tools

All 18 tools are available once configured:

### Platform Tools

| Tool | What it does |
|------|-------------|
| `adp_status` | Health status of all runtimes (VM status, SSH, sync) |
| `adp_doctor` | Platform diagnostics (47+ checks, issue remediation) |
| `adp_capabilities` | Platform capabilities and roadmap |

### Workspace Tools

| Tool | What it does |
|------|-------------|
| `adp_workspace_list` | List manifest projects and runtime mappings |
| `adp_workspace_status` | Workspace readiness (paths, runtimes, sync, snapshots) |
| `adp_workspace_dashboard` | Task lifecycle overview with governance queues |
| `adp_workspace_project` | Single project operational lifecycle view |
| `adp_workspace_create` | Create workspace directories (plan-only default) |
| `adp_workspace_open` | Entry guidance (paths, SSH, sync commands) |
| `adp_workspace_sync` | Per-project sync guidance |
| `adp_workspace_close` | Close workspace (stop sync, plan-only default) |
| `adp_workspace_recipes` | List available workspace recipes |
| `adp_workspace_report` | Markdown release evidence |

### Runtime Tools

| Tool | What it does |
|------|-------------|
| `adp_up` | Start VM (create from ISO if first time, plan-only default) |
| `adp_down` | Destroy VM (plan-only default) |
| `adp_stop` | Graceful VM shutdown |
| `adp_sync_status` | Mutagen sync session health |
| `adp_sync_stop` | Stop Mutagen sync session |

## Safety Design

All destructive operations default to plan-only mode:

- `adp_up` and `adp_down` default to `plan_only=True` — preview only
- `adp_workspace_create` defaults to `plan_only=True` — preview only
- `adp_workspace_close` defaults to `plan_only=True` — preview only

To execute, explicitly set `plan_only=False`. All inspection tools are entirely non-destructive.

## What You Can Do Today

With the current 18 tools, a deer-flow agent can:

| Task | Tools to use | Description |
|------|-------------|-------------|
| **Check platform health** | `adp_status`, `adp_doctor` | Verify all VMs running, SSH reachable, sync healthy |
| **Manage VM lifecycle** | `adp_up`, `adp_stop`, `adp_down` | Start, stop, destroy VMs |
| **Set up workspaces** | `adp_workspace_create`, `adp_workspace_open` | Create project directories, get entry guidance |
| **Monitor sync** | `adp_sync_status`, `adp_sync_stop` | Check and manage file synchronization |
| **Inspect workspaces** | `adp_workspace_list`, `adp_workspace_status`, `adp_workspace_dashboard`, `adp_workspace_project` | Full workspace visibility |
| **Generate evidence** | `adp_workspace_report` | Markdown release evidence for PR descriptions |
| **Discover capabilities** | `adp_capabilities`, `adp_workspace_recipes` | Platform and workflow discovery |

## Workflow Example: VM Management via Deer-Flow

A typical deer-flow agent session managing ADP-OS VMs:

```
User: "Set up an ADP-OS agent workspace and check it's healthy"

Agent calls:
  1. adp_status()                    → "agent: stopped"
  2. adp_up("agent", plan_only=False) → VM boots (30s warm, 20min first install)
  3. adp_status("agent")             → "agent: running, reachable, healthy"
  4. adp_doctor()                    → "47 OK, 0 issues"
  5. adp_workspace_list()            → Projects and runtime mappings
  6. adp_workspace_status()          → Readiness summary
  7. adp_sync_status()               → "agent: healthy"
```

## Current Limitations

The MCP server currently provides **VM-side operations** (management from the host). It does **not** provide **in-VM operations** (code execution inside the VM). This means:

| Capability | Status | Workaround |
|-----------|--------|------------|
| Start/stop/destroy VMs | ✅ Available | Use `adp_up`/`adp_stop`/`adp_down` |
| Check VM health | ✅ Available | Use `adp_status`/`adp_doctor` |
| Manage workspaces and sync | ✅ Available | Use workspace and sync tools |
| **Run code inside VM** | ❌ Not available | SSH exec tools needed (P0 gap) |
| **Read/write files in VM** | ❌ Not available | File transfer tools needed (P0 gap) |
| **List directories in VM** | ❌ Not available | Dir listing tools needed (P0 gap) |

The P0 gaps are documented in [Integrations: Deer-Flow Gap Analysis](integrations/deer-flow.md). Once the 8 SSH-backed in-VM tools are implemented, ADP-OS can serve as a full deer-flow sandbox backend.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADP_HOME` | Yes | Path to ADP-OS installation (WSL path or Windows path) |
| `ADP_HOME_WIN` | WSL only | Windows host path to ADP-OS installation (e.g., `D:\\Dev\\ai-dev-platform`) |

Path resolution order:
1. `ADP_HOME` / `ADP_HOME_WIN` environment variables (explicit)
2. Relative to the server script location (`../../` from `cli/mcp/server.py`)
3. Common paths (`D:/Dev/ai-dev-platform`, `/mnt/d/Dev/ai-dev-platform`)

## Troubleshooting

### Tools not appearing in deer-flow

1. Check `extensions_config.json` — verify `"enabled": true` and paths are correct
2. Check deer-flow logs for MCP server startup errors
3. Verify MCP server works standalone:
   ```bash
   cd /path/to/ai-dev-platform
   ADP_HOME_WIN="D:\\Dev\\ai-dev-platform" python cli/mcp/server.py
   ```
   (The server starts via stdio — it expects an MCP client to connect. No output on stdout is expected.)

### pwsh.exe not found

Install PowerShell 7+ from https://github.com/PowerShell/PowerShell

### Path issues

- On Windows: use double backslashes in JSON (`D:\\Dev\\ai-dev-platform`)
- On WSL: set both `ADP_HOME` (WSL path) and `ADP_HOME_WIN` (Windows path)
- The server automatically converts between WSL and Windows paths via `wslpath`

### ADP-OS not installed or not configured

The MCP server wraps the ADP-OS PowerShell CLI. You need:
1. ADP-OS installed at the configured path
2. VMware Workstation Pro installed
3. An ADP-OS runtime created (`adp up agent`)

Use `adp_doctor` via MCP to verify platform health after configuration.

## References

- [Deer-Flow MCP Server Guide](https://github.com/bytedance/deer-flow/blob/main/backend/docs/MCP_SERVER.md) — deer-flow MCP configuration
- [Deer-Flow Sandbox Configuration](https://github.com/bytedance/deer-flow/blob/main/backend/docs/CONFIGURATION.md#sandbox) — sandbox modes
- [ADP-OS MCP Server README](../cli/mcp/README.md) — full tool reference and architecture
- [Deer-Flow Gap Analysis](integrations/deer-flow.md) — P0/P1/P2 gaps and integration path
- [Copilot SDK Integration](copilot-sdk-integration.md) — alternative agent SDK integration
