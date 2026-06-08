# Deer-Flow ADP-OS Integration Guide

> **Date**: 2026-06-05 | **Target audience**: Deer-flow integrators, ADP-OS operators
> **Bilingual**: English & 中文 | [简体中文版](zh-CN/deer-flow-integration.md)

Practical, copy-paste runnable guide to wire up [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow) (70K⭐) with ADP-OS VMs as a hardware-VM sandbox backend.

For architectural analysis and gap tracking, see [Deploying ADP-OS as Deer-Flow VM Sandbox Backend](integrations/deer-flow.md).

---

## Overview

ADP-OS provides **two integration paths** for deer-flow:

| Path | How | When to use |
|------|-----|-------------|
| **MCP Server** (recommended) | Deer-flow connects to ADP-OS MCP server as an MCP tool provider. All 26 tools exposed via stdio MCP transport. | Deer-flow agents use MCP protocol. Cross-language, cross-machine. |
| **Direct Adapter** | `DeerFlowADPSandboxProvider` Python class imported directly. Implements deer-flow `SandboxProvider` ABC. | Python-native deer-flow integration, minimal protocol overhead. |

Both paths provide the same sandbox capabilities: VM lifecycle (acquire/release) + 8 in-VM operations (exec, file read/write, dir list, glob, grep, download, upload).

---

## Prerequisites

- **ADP-OS installed** on a Windows host with VMware Workstation
  - Verified: `adpos doctor` returns healthy
- **At least one VM runtime** configured in `configs/topology.json`
  - Test with: `adpos up agent`
- **SSH access to VMs** (port 22 on VMware NAT subnet)
  - Default credentials: `adp` / `adp` (set during Ubuntu autoinstall)
- **Python 3.10+** and **PowerShell 7+** on the integration host
- (Optional) `paramiko` for better SSH connection management: `pip install paramiko`

---

## Path 1: MCP Server Integration (Recommended)

Deer-flow connects to ADP-OS MCP server as an MCP tool provider via stdio transport. All 26 tools are available to deer-flow agents.

### Step 1: Verify ADP-OS MCP Server

```bash
cd /path/to/ai-dev-platform

# Verify MCP server module loads and all 26 tools are registered
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP tools registered: {len(tools)}')
print(f'Tool names: {sorted(tools)}')
"
```

Expected output: 26 tools in 4 categories (Platform, Workspace, Runtime, In-VM Sandbox).

### Step 2: Configure Deer-Flow MCP Extension

Create or update `extensions_config.json` in your deer-flow project root:

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python",
    "args": [
      "/absolute/path/to/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/absolute/path/to/ai-dev-platform",
      "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
    }
  }
}
```

**Environment variables**:

| Variable | Required | Description |
|----------|----------|-------------|
| `ADP_HOME` | Yes | ADP-OS install directory (Linux/WSL path) |
| `ADP_HOME_WIN` | WSL only | ADP-OS Windows path for PowerShell invocation |
| `ADP_SSH_USER` | No | VM SSH user (default: `adp`) |
| `ADP_SSH_PASSWORD` | No | VM SSH password (default: `adp`) |

### Step 3: Restart Deer-Flow

Restart deer-flow to load the MCP extension. The ADP-OS tools appear in deer-flow agent's tool list.

### Step 4: Verify Integration

In deer-flow, verify the tools are registered:

```
# Agent should see these MCP tool names:
adp_status, adp_up, adp_down, adp_stop, adp_exec,
adp_file_read, adp_file_write, adp_dir_list, adp_glob, adp_grep,
adp_file_download, adp_file_upload, ...
```

Test with a simple VM lifecycle. The following lines are MCP/deer-flow tool invocations, not terminal commands; for local shell verification, use `adpos up agent`, `adpos status agent`, and `adpos stop agent`.

```
adp_up agent                    # Start VM (first time: 15-45 min, warm: ~30s)
adp_status agent                # Verify VM is running
adp_exec agent "python --version"  # Execute command in VM
adp_stop agent                  # Graceful shutdown
```

### MCP Tools Reference

26 tools in 4 categories:

| Category | Tools | Count |
|----------|-------|-------|
| **Platform** | `adp_status`, `adp_doctor`, `adp_capabilities` | 3 |
| **Workspace** | `adp_workspace_list`, `adp_workspace_status`, `adp_workspace_dashboard`, `adp_workspace_project`, `adp_workspace_create`, `adp_workspace_open`, `adp_workspace_sync`, `adp_workspace_close`, `adp_workspace_recipes`, `adp_workspace_report` | 10 |
| **Runtime** | `adp_up`, `adp_down`, `adp_stop`, `adp_sync_status`, `adp_sync_stop` | 5 |
| **In-VM Sandbox** | `adp_exec`, `adp_file_read`, `adp_file_write`, `adp_dir_list`, `adp_glob`, `adp_grep`, `adp_file_download`, `adp_file_upload` | 8 |

---

## Path 2: Direct Adapter (Python-Native)

Import `DeerFlowADPSandboxProvider` directly in Python. Best for embedded deer-flow deployments where Python interop is available.

### Step 1: Install Dependencies

```bash
cd /path/to/ai-dev-platform
pip install paramiko   # Recommended SSH backend
```

### Step 2: Import and Initialize

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS install directory (required)
    pool_size=2,                            # Pre-warm VM pool size (0 = disabled)
    ssh_user="adp",                         # VM SSH user
    ssh_password="adp",                     # VM SSH password
)
```

### Step 3: Pre-Warm VM Pool (Optional)

```python
# Start background VMs to eliminate cold start (15-45 min → instant)
provider.warm_pool()
```

Pool VMs use `deerflow-pool-N` runtime names — they don't conflict with user runtimes.

### Step 4: Use the Sandbox

```python
# Acquire a sandbox (maps thread_id to ADP-OS runtime)
sandbox_id = provider.acquire(thread_id="my-agent-thread")
print(f"Sandbox acquired: {sandbox_id}")

# Get the Sandbox handle
sandbox = provider.get(sandbox_id)

# Execute commands inside the VM
output = sandbox.execute_command("python --version")
print(output)

# Read and write files
sandbox.write_file("/tmp/hello.py", "print('Hello from ADP-OS!')")
content = sandbox.read_file("/tmp/hello.py")
print(content)

# List directories
entries = sandbox.list_dir("/tmp", max_depth=1)
for entry in entries:
    print(entry)

# Search files with glob
matches, truncated = sandbox.glob("/tmp", "*.py")
print(f"Found {len(matches)} Python files")

# Search file contents with grep
matches, truncated = sandbox.grep("/tmp", "Hello")
for m in matches:
    print(f"{m.path}:{m.line_number}: {m.line}")

# Download / upload binary files
data = sandbox.download_file("/path/to/binary")
sandbox.update_file("/path/to/dest", data)

# Release the sandbox when done
provider.release(sandbox_id)
```

### Full Sandbox Interface Reference

| Method | Signature | Returns |
|--------|-----------|---------|
| `execute_command` | `(command: str)` | `str` (stdout) |
| `read_file` | `(path: str)` | `str` (file content) |
| `write_file` | `(path: str, content: str, append: bool = False)` | `None` |
| `list_dir` | `(path: str, max_depth: int = 2)` | `list[str]` |
| `glob` | `(path: str, pattern: str)` | `tuple[list[str], bool]` |
| `grep` | `(path: str, pattern: str, max_matches: int = 100, ...)` | `tuple[list[GrepMatch], bool]` |
| `download_file` | `(path: str)` | `bytes` |
| `update_file` | `(path: str, content: bytes)` | `None` |

### Thread → Runtime Mapping

The adapter maintains a persistent thread-runtime registry at `~/.adp-deerflow/thread_runtime_registry.json`:

```json
{
  "thread-abc123": "agent",
  "thread-def456": "sandbox"
}
```

Default mapping when `thread_id=None`: `"agent"` runtime.

---

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `ADP_HOME` | Yes | ADP-OS install directory (Linux/WSL path) |
| `ADP_HOME_WIN` | WSL only | ADP-OS Windows path for `pwsh.exe` invocation |
| `ADP_SSH_USER` | No | VM SSH username (default: `adp`) |
| `ADP_SSH_PASSWORD` | No | VM SSH password (default: `adp`) |

---

## Verification Checklist

- [ ] ADP-OS CLI healthy: `adpos doctor`
- [ ] At least one VM runtime configured: `adpos status`
- [ ] MCP server lists 26 tools: `python cli/mcp/server.py --list-tools`
- [ ] MCP server tests pass: `python -m pytest tests/test-mcp-server.py -v`
- [ ] Deer-flow adapter tests pass: `python -m pytest tests/test_deerflow_adp_sandbox.py -v`
- [ ] (Optional) Integration test: deer-flow agent executes code in ADP-OS VM

---

## Troubleshooting

### VM doesn't start (timeout)

**Symptoms**: `adp_up` returns timeout or "VM not ready" after several minutes.

**Checks**:
1. VMware Workstation is running
2. ISO exists at the configured path
3. First-time Ubuntu autoinstall can take 15-45 minutes — wait longer, or use `VMPool` pre-warming

### SSH connection refused

**Symptoms**: `adp_exec` or adapter methods return "Connection refused".

**Checks**:
1. VM is running: `adpos status agent`
2. SSH port is reachable from integration host
3. SSH credentials match `configs/topology.json` settings
4. VMware NAT network is properly configured

### MCP server doesn't start

**Symptoms**: Deer-flow can't connect to MCP server.

**Checks**:
1. Python 3.10+: `python --version`
2. ADP-OS installed: `ls cli/mcp/server.py`
3. Environment variables set in `extensions_config.json`
4. Absolute paths used in configuration (relative paths may fail in stdio mode)

### paramiko not found

**Solution**: Install it, or the adapter falls back to `subprocess ssh` + `sshpass`:

```bash
pip install paramiko

# Or install sshpass for fallback:
# Ubuntu: sudo apt install sshpass
# macOS: brew install hudochenkov/sshpass/sshpass
```

### WSL-specific: pwsh.exe not found

**Symptoms**: `adpos` commands fail with "pwsh not found".

**Solution**: Set `ADP_HOME_WIN` to the Windows-style path for the ADP-OS directory so PowerShell scripts run via `pwsh.exe` from WSL.

---

## References

- [Deer-Flow Sandbox Architecture](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner)
- [ADP-OS MCP Server Source](../cli/mcp/server.py)
- [Deer-Flow Gap Analysis](integrations/deer-flow.md)
- [Deer-Flow VM Backend Guide](integrations/deer-flow-backend.md)
- [Adapter Module Source](../extensions/deer_flow/deerflow_adp_sandbox.py)
- [Adapter README](../extensions/deer_flow/README.md)
