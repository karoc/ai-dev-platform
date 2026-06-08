# GitHub Copilot Agent SDK Integration

[简体中文](zh-CN/copilot-sdk-integration.md) | English

ADP-OS ships a standard [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that is natively compatible with the [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk). No extra adapters, no code changes — configure it once and all 26 ADP-OS tools are available to your Copilot SDK agents.

## Quick Start

Install the Copilot SDK for your language, then load ADP-OS as an MCP server.

### Python

```python
import asyncio
from copilot import CopilotClient
from copilot.session import PermissionHandler

async def main():
    client = CopilotClient()
    await client.start()

    session = await client.create_session(
        on_permission_request=PermissionHandler.approve_all,
        model="gpt-5",
        mcp_servers={
            "adp-os": {
                "type": "local",
                "command": "python",
                "args": ["cli/mcp/server.py"],
                "cwd": "/path/to/ai-dev-platform",
                "tools": ["*"],
            },
        },
    )

    response = await session.send_and_wait(
        "Check the ADP-OS platform status and list all workspace projects."
    )
    print(response.data.content)

    await session.disconnect()
    await client.stop()

asyncio.run(main())
```

### TypeScript (Node.js)

```typescript
import { CopilotClient } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    const session = await client.createSession({
        model: "gpt-5",
        mcpServers: {
            "adp-os": {
                type: "local",
                command: "python",
                args: ["cli/mcp/server.py"],
                cwd: "/path/to/ai-dev-platform",
                tools: ["*"],
            },
        },
    });

    const result = await session.sendAndWait({
        prompt: "Check the ADP-OS platform status and list all workspace projects.",
    });

    console.log(result?.data?.content);
    await session.disconnect();
    await client.stop();
}

main();
```

### Using Environment Variables

Instead of hardcoding paths, use `env` to pass `ADP_HOME` and optionally `ADP_HOME_WIN`:

```python
# Python
mcp_servers={
    "adp-os": {
        "type": "local",
        "command": "python",
        "args": ["cli/mcp/server.py"],
        "cwd": "/path/to/ai-dev-platform",
        "env": {
            "ADP_HOME": "/path/to/ai-dev-platform",
            # Only needed when ADP-OS is on a different Windows path:
            # "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform",
        },
        "tools": ["*"],
    },
},
```

```typescript
// TypeScript
mcpServers: {
    "adp-os": {
        type: "local",
        command: "python",
        args: ["cli/mcp/server.py"],
        cwd: "/path/to/ai-dev-platform",
        env: {
            ADP_HOME: "/path/to/ai-dev-platform",
        },
        tools: ["*"],
    },
},
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADP_HOME` | **Yes** | Path to the ADP-OS installation directory. Accepts both Windows (`D:\\Dev\\ai-dev-platform`) and WSL/Linux (`/mnt/d/Dev/ai-dev-platform`) paths. |
| `ADP_HOME_WIN` | No | Explicit Windows path override. Only needed when running the MCP server on WSL but ADP-OS is on a Windows drive reachable via a different path than what `wslpath -w` would resolve. If set, it takes precedence over the auto-resolved Windows path. |

The MCP server resolves `ADP_HOME` with a three-tier fallback:

1. `ADP_HOME` environment variable (explicit)
2. Auto-detection: walks up from `cli/mcp/server.py` to find the project root that contains the internal CLI implementation (`cli/adp.ps1`). User-facing shell commands should still use `adpos`.
3. Platform-specific well-known paths (`D:/Dev/ai-dev-platform`, `~/ai-dev-platform`, `/mnt/d/Dev/ai-dev-platform`)

If you get `FileNotFoundError: Cannot locate ADP-OS installation`, set `ADP_HOME` explicitly.

## ADP-OS MCP Tools

All 26 tools are exposed through the MCP server. Four categories:

### Platform Tools (3)

| Tool | Description |
|------|-------------|
| `adp_status` | Platform and runtime health status. Shows running VMs, SSH reachability, sync health. |
| `adp_doctor` | Run platform diagnostics. Reports OK count, issue count, and per-issue remediation. |
| `adp_capabilities` | Platform capabilities and roadmap. Lists supported/planned/exploratory features. |

### Workspace Tools (10)

| Tool | Description |
|------|-------------|
| `adp_workspace_list` | List all workspace projects defined in the manifest. |
| `adp_workspace_status` | Detailed workspace readiness: manifest state, paths, runtime status, sync sessions. |
| `adp_workspace_dashboard` | Dashboard with task lifecycle overview, milestone checkpoints, evaluation hooks. |
| `adp_workspace_project` | Single project's full operational lifecycle view (path, runtime, sync, validation, evidence). |
| `adp_workspace_create` | Create workspace project directories (plan-only by default). |
| `adp_workspace_open` | Workspace entry guidance: local/remote paths, runtime readiness, sync status. |
| `adp_workspace_sync` | Per-project file sync guidance with explicit sync commands. |
| `adp_workspace_close` | Close a workspace by stopping sync for its runtime (plan-only by default). |
| `adp_workspace_recipes` | List available workspace recipes, milestones, and evaluation hooks. |
| `adp_workspace_report` | Generate Markdown release evidence for maintainer handoff. |

### Runtime Tools (5)

| Tool | Description |
|------|-------------|
| `adp_up` | Start a runtime VM (plan-only by default). Creates from ISO on first run. |
| `adp_down` | Destroy a runtime VM completely (plan-only by default). Irreversible. |
| `adp_stop` | Gracefully stop a runtime VM without destroying it. |
| `adp_sync_status` | Get Mutagen sync session status for all runtimes. |
| `adp_sync_stop` | Stop a Mutagen sync session for a specific runtime. |

### In-VM Sandbox Tools (8)

These tools execute operations directly inside a running VM via SSH:

| Tool | Description |
|------|-------------|
| `adp_exec` | Execute a shell command inside a running VM via SSH. |
| `adp_file_read` | Read the contents of a file inside a running VM. |
| `adp_file_write` | Write/append content to a file inside a VM (plan-only by default). |
| `adp_dir_list` | List directory contents inside a VM with configurable depth. |
| `adp_glob` | Find files matching a glob pattern inside a VM. |
| `adp_grep` | Search for text patterns in files inside a VM with regex/literal support. |
| `adp_file_download` | Download a binary file from a VM as base64-encoded content. |
| `adp_file_upload` | Upload binary content to a file inside a VM (plan-only by default). |

## Safety: Plan-Only Defaults

**All destructive operations default to plan-only mode.** `adp_up`, `adp_down`, `adp_workspace_create`, `adp_workspace_close`, `adp_file_write`, and `adp_file_upload` all require explicitly setting `plan_only=False` to take effect. In plan-only mode, the tool shows what *would* happen without making changes.

This means you can safely let an agent explore the platform without fear of accidental VM destruction. When you're ready to execute, pass `plan_only=False`:

```python
# Agent: "Let me check what starting the agent runtime would do."
response = await session.send_and_wait(
    "Preview starting the agent runtime."
)
# → adp_up(runtime="agent") is called → plan-only output shown, no VM created

# Agent: "Now actually start it."
response = await session.send_and_wait(
    "Start the agent runtime for real."
)
# → adp_up(runtime="agent", plan_only=False) → VM provisions
```

## Permission Notes

### Tool Access Control

The `tools` field in Copilot SDK MCP configuration controls which tools are available. Options:

- `["*"]` — all 26 tools enabled (recommended for full ADP-OS access)
- `["adp_status", "adp_doctor", "adp_workspace_list"]` — read-only tools only
- `[]` — no tools (effectively disables the server)

For production or CI use, you may want to restrict to read-only tools and only enable mutating tools for specific sessions.

### Copilot SDK Permission Handler

The Copilot SDK's `PermissionHandler` controls tool-level approval. You can:

- **Approve all** (`PermissionHandler.approve_all`): Suitable for trusted local development.
- **Prompt for approval** (`PermissionHandler.prompt`): The SDK asks you before each tool execution.
- **Custom handler**: Implement your own approval logic — allow reads, prompt for writes, deny destroys.

```python
# Custom: auto-approve reads, prompt for everything else
class ReadOnlyHandler(PermissionHandler):
    READ_TOOLS = {"adp_status", "adp_doctor", "adp_capabilities",
                  "adp_workspace_list", "adp_workspace_status",
                  "adp_workspace_dashboard", "adp_workspace_project",
                  "adp_workspace_open", "adp_workspace_sync",
                  "adp_workspace_recipes", "adp_workspace_report",
                  "adp_sync_status",
                  "adp_exec", "adp_file_read", "adp_dir_list",
                  "adp_glob", "adp_grep", "adp_file_download"}

    def on_permission_request(self, request):
        if request.tool_name in self.READ_TOOLS:
            return True   # auto-approve reads
        return super().on_permission_request(request)  # prompt for writes
```

### Local Security Model

ADP-OS is designed for **single-user, trusted-workstation** environments. The MCP server inherits this model:

- VMs run locally with a default `adp:adp` credential for automated sudo provisioning.
- The MCP server executes ADP-OS CLI commands — it has the same access as running `adpos` from that installation.
- Do not expose the MCP server to untrusted networks or multi-tenant environments without credential rotation and SSH hardening (see [Security](../SECURITY.md)).

## See Also

- [GitHub Copilot SDK — MCP Documentation](https://github.com/github/copilot-sdk/blob/main/docs/features/mcp.md)
- [ADP-OS Agent-Native API (MCP) Overview](../README.md#agent-native-api-mcp)
- [ADP-OS Security Model](../SECURITY.md)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
