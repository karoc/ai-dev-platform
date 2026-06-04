# ADP-OS MCP Server

Exposes ADP-OS platform management as MCP (Model Context Protocol) tools for agent-native sandbox orchestration.

## Tools

| Tool | Description |
|------|-------------|
| `adp_status` | Platform and runtime health status |
| `adp_doctor` | Run platform diagnostics |
| `adp_workspace_list` | List workspace projects |
| `adp_workspace_create` | Create workspace directories |
| `adp_workspace_open` | Get workspace entry guidance |
| `adp_workspace_sync` | Get per-project sync guidance |
| `adp_workspace_status` | Workspace readiness summary |
| `adp_workspace_recipes` | List available workspace recipes |
| `adp_sync_status` | Mutagen sync session status |
| `adp_sync_stop` | Stop sync session (close workspace) |
| `adp_capabilities` | Platform capabilities and roadmap |

## Setup

### Prerequisites

- Python 3.10+
- ADP-OS installed at a known path
- PowerShell 7+ (pwsh)

### Install

```bash
cd cli/mcp
pip install -r requirements.txt
```

### Configure MCP Client

Add to your MCP client configuration (e.g., Claude Desktop `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python",
      "args": ["path/to/cli/mcp/server.py"],
      "env": {
        "ADP_HOME": "D:\\Dev\\ai-dev-platform",
        "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
      }
    }
  }
}
```

On WSL, set `ADP_HOME` to the WSL path (e.g. `/home/user/ai-dev-platform`) and `ADP_HOME_WIN` to the Windows path (e.g. `D:\Dev\ai-dev-platform`).

### Run Standalone

```bash
ADP_HOME_WIN="D:\\Dev\\ai-dev-platform" python cli/mcp/server.py
```

## Architecture

The MCP server invokes ADP-OS PowerShell CLI via `pwsh.exe` subprocess calls. Each tool maps to an `adp` CLI command and returns structured output.

All tools are non-destructive by default — they use plan/preview modes where available and do not modify VMs, sync sessions, or configuration without explicit intent.
