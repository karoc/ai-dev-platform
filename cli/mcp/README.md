# ADP-OS MCP Server

Exposes ADP-OS platform management as MCP (Model Context Protocol) tools for agent-native sandbox orchestration.

## Tools (18 total)

### Platform

| Tool | Description |
|------|-------------|
| `adp_status` | Platform and runtime health status |
| `adp_doctor` | Run platform diagnostics |
| `adp_capabilities` | Platform capabilities and roadmap |

### Workspace

| Tool | Description |
|------|-------------|
| `adp_workspace_list` | List workspace projects |
| `adp_workspace_status` | Workspace readiness summary |
| `adp_workspace_dashboard` | Workspace dashboard with task lifecycle |
| `adp_workspace_project` | Single project operational lifecycle view |
| `adp_workspace_create` | Create workspace directories |
| `adp_workspace_open` | Get workspace entry guidance |
| `adp_workspace_sync` | Get per-project sync guidance |
| `adp_workspace_close` | Close workspace (stop sync for its runtime) |
| `adp_workspace_recipes` | List available workspace recipes |
| `adp_workspace_report` | Generate Markdown release evidence |

### Runtime

| Tool | Description |
|------|-------------|
| `adp_up` | Start a runtime VM (plan-only by default) |
| `adp_down` | Destroy a runtime VM (plan-only by default) |
| `adp_stop` | Gracefully stop a runtime VM |
| `adp_sync_status` | Mutagen sync session status |
| `adp_sync_stop` | Stop sync session for a runtime |

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

#### Windows (Native)

```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python",
      "args": ["D:\\Dev\\ai-dev-platform\\cli\\mcp\\server.py"],
      "env": {
        "ADP_HOME": "D:\\Dev\\ai-dev-platform"
      }
    }
  }
}
```

On Windows, only `ADP_HOME` is needed. The server auto-detects the platform and treats paths as native Windows paths.

#### WSL

```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python",
      "args": ["path/to/cli/mcp/server.py"],
      "env": {
        "ADP_HOME": "/home/user/ai-dev-platform",
        "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
      }
    }
  }
}
```

On WSL, set `ADP_HOME` to the WSL path (e.g. `/home/user/ai-dev-platform`) and `ADP_HOME_WIN` to the Windows path (e.g. `D:\\Dev\\ai-dev-platform`). The server converts between WSL and Windows paths automatically via `wslpath`.

### Claude Desktop Setup

1. Install the MCP server dependencies:
   ```bash
   cd /path/to/ai-dev-platform/cli/mcp
   pip install -r requirements.txt
   ```

2. Locate your Claude Desktop config file:
   - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
   - **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

3. Add the ADP-OS server entry:

   **Windows native**:
   ```json
   {
     "mcpServers": {
       "adp-os": {
         "command": "python",
         "args": ["D:\\Dev\\ai-dev-platform\\cli\\mcp\\server.py"],
         "env": {
           "ADP_HOME": "D:\\Dev\\ai-dev-platform"
         }
       }
     }
   }
   ```

   **WSL** (Python in WSL, pwsh.exe on Windows host):
   ```json
   {
     "mcpServers": {
       "adp-os": {
         "command": "wsl",
         "args": ["python3", "/home/user/ai-dev-platform/cli/mcp/server.py"],
         "env": {
           "ADP_HOME": "/home/user/ai-dev-platform",
           "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
         }
       }
     }
   }
   ```

4. Restart Claude Desktop. You should see a hammer icon indicating MCP tools are available.

5. Verify by asking Claude: "Show me ADP-OS platform status"

### Troubleshooting Claude Desktop

- **Tools not appearing**: Check Claude Desktop logs at `%APPDATA%\Claude\logs\`
- **pwsh.exe not found**: Install PowerShell 7+ from https://github.com/PowerShell/PowerShell
- **ADP_HOME path issues**: On Windows, use double backslashes in JSON (e.g. `D:\\Dev\\ai-dev-platform`). On WSL, set both `ADP_HOME` (WSL path) and `ADP_HOME_WIN` (Windows path).
- **Script execution blocked**: The server uses `-ExecutionPolicy Bypass` — ensure your PowerShell execution policy allows it or run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

### Run Standalone

```bash
ADP_HOME_WIN="D:\\Dev\\ai-dev-platform" python cli/mcp/server.py
```

## Safety Design

All tools default to non-destructive behavior:

- `adp_up` and `adp_down` default to `plan_only=True` — they preview what would happen without making changes
- `adp_workspace_close` defaults to `plan_only=True` — shows what sync would be stopped without actually stopping it
- `adp_workspace_create` defaults to `plan_only=True` — previews directories without creating them
- All workspace inspection tools (`list`, `status`, `dashboard`, `project`, `open`, `sync`, `recipes`, `report`) are entirely non-destructive

To execute destructive operations, explicitly set `plan_only=False`.

## Architecture

The MCP server invokes ADP-OS PowerShell CLI via `pwsh.exe` subprocess calls. Each tool maps to an `adp` CLI command and returns structured output.

All 18 tools return **JSON structured dicts** with the following base fields:

| Field | Type | Description |
|-------|------|-------------|
| `_text` | string | Human-readable formatted CLI output |
| `_exit_code` | integer | Process exit code (0 = success) |
| `_success` | boolean | Whether the command succeeded |

**Command-specific parsed fields** (included when applicable):

- `adp_status` → `runtimes[]`, `runtime_count`, `running_count`
- `adp_doctor` → `ok_count`, `issue_count`, `info_count`, `issues[]`, `healthy`
- `adp_capabilities` → `supported[]`, `planned[]`, `exploratory[]`
- `adp_workspace_list` → `projects[]`, `project_count`
- `adp_sync_status` → `sessions[]`, `session_count`, `healthy_count`
- `adp_workspace_close` → `action`, `project`, `runtime`, `plan_only`
- `adp_up`/`adp_down`/`adp_stop`/`adp_sync_stop` → `runtime` (+ `plan_only`/`force` where applicable)

Example response from `adp_status`:
```json
{
  "_text": "agent       running      192.168.242.135  reachable  healthy",
  "_exit_code": 0,
  "_success": true,
  "runtimes": [{"name": "agent", "status": "running", "ip": "192.168.242.135", "ssh": "reachable", "sync": "healthy"}],
  "runtime_count": 1,
  "running_count": 1
}
```

Path resolution:
1. `ADP_HOME` / `ADP_HOME_WIN` environment variables (explicit)
2. Relative to the server script location (`../../` from `cli/mcp/server.py`)
3. Common WSL mount paths (`/mnt/d/Dev/ai-dev-platform`)

## Testing

```bash
cd /path/to/ai-dev-platform
python -m pytest tests/test-mcp-server.py -v
```

Or run without pytest:

```bash
python tests/test-mcp-server.py
```
