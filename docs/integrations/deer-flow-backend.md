# ADP-OS as Deer-Flow's VM Sandbox Backend

> **Date**: 2026-06-05 | **Target audience**: Deer-flow operators, ADP-OS administrators
> **Bilingual**: English & 中文 | [简体中文版](../zh-CN/integrations/deer-flow-backend.md)
> **Source Tags**: [FILE]=Source code analysis, [LLM]=LLM reasoning

A practical guide to configuring ADP-OS as the hardware-VM sandbox backend for [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow) (70K⭐).

For the comprehensive architecture reference, gap analysis, and interface mapping, see [Deploying ADP-OS as Deer-Flow VM Sandbox Backend](deer-flow.md). For the MCP server quick-start, see [MCP Server Setup Guide](deer-flow-mcp-setup.md). For the full two-path integration reference, see [Deer-Flow Integration Guide](../deer-flow-integration.md).

---

## What This Is

Deer-flow agents run code inside sandboxes. By default those sandboxes are Docker containers. ADP-OS replaces Docker with **hardware-isolated virtual machines** — each deer-flow agent session gets its own VM with a real Linux kernel, full root access, and genuine process isolation.

```
Deer-Flow Agent
    │
    ├─ "bash: pip install requests"
    ├─ "write_file: /app/main.py"
    └─ "read_file: /app/main.py"
         │
    ┌────▼────────────────────────────────────┐
    │  ADP-OS VM Sandbox Backend              │
    │                                         │
    │  • VM runs Ubuntu 24.04                 │
    │  • Real kernel, real filesystem          │
    │  • SSH-backed command execution          │
    │  • MCP protocol or Direct Adapter        │
    └─────────────────────────────────────────┘
```

Two integration paths are available:

| Path | How it works | Best for |
|------|-------------|----------|
| **MCP Server** | Deer-flow loads ADP-OS as an MCP tool provider (26 tools exposed via stdio) | Cross-language, cross-machine, MCP-native workflows |
| **Direct Adapter** | Python `DeerFlowADPSandboxProvider` class implements deer-flow's `SandboxProvider` ABC | Python-native deer-flow deployments, minimal overhead |

Both paths provide the same 8 in-VM sandbox operations: execute commands, read/write files, list directories, glob, grep, download, and upload.

---

## Prerequisites

| Requirement | Check command | Notes |
|-------------|--------------|-------|
| ADP-OS installed | `adpos doctor` | Must return "healthy" |
| VMware Workstation | Running on Windows host | VM provisioning backend |
| At least one runtime | `adpos status` | Configured in `configs/topology.json` |
| Python 3.10+ | `python3 --version` | For MCP server and adapter |
| SSH reachable VM | `ssh adp@<vm-ip> echo OK` | Default credentials: `adp`/`adp` |

---

## Path 1: MCP Server Backend

Deer-flow connects to the ADP-OS MCP server as a tool provider. All 26 MCP tools — VM lifecycle, workspace management, and in-VM sandbox operations — become available to deer-flow agents.

### Step 1: Verify MCP Server

```bash
cd /path/to/ai-dev-platform

# Verify all 26 tools are registered
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP tools: {len(tools)}')
print(sorted(tools))
"
```

Expected: **26 tools** across Platform (3), Workspace (10), Runtime (5), and In-VM Sandbox (8).

### Step 2: Configure Deer-Flow

Create or update `extensions_config.json` in your deer-flow project root:

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/absolute/path/to/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/absolute/path/to/ai-dev-platform"
    }
  }
}
```

**WSL users** must also set `ADP_HOME_WIN` for PowerShell resolution:

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/home/user/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/home/user/ai-dev-platform",
      "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
    }
  }
}
```

> **Important**: All paths must be **absolute**. Relative paths fail in stdio MCP transport because the working directory is undetermined.

### Step 3: Restart Deer-Flow

After updating `extensions_config.json`, restart deer-flow. The 26 ADP-OS tools appear alongside deer-flow's built-in tools.

### Step 4: Validate Backend

From the deer-flow agent context:

```
# Start a VM
adp_up agent

# Check status
adp_status agent

# Run code inside the VM
adp_exec agent "python3 --version"

# Read/write files
adp_file_write agent "/tmp/hello.py" "print('Hello from ADP-OS VM!')" plan_only=False
adp_exec agent "python3 /tmp/hello.py"

# Stop the VM
adp_stop agent
```

---

## Path 2: Direct Adapter Backend

The `DeerFlowADPSandboxProvider` class implements deer-flow's `SandboxProvider` ABC directly. No MCP protocol overhead — the adapter talks to ADP-OS VMs via SSH.

### Step 1: Install Dependencies

```bash
pip install paramiko    # SSH connection management (recommended)
```

If `paramiko` is not available, the adapter falls back to subprocess `ssh` + `sshpass`.

### Step 2: Configure the Provider

In your deer-flow Python code:

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS install directory (required)
    pool_size=2,                            # Pre-warm 2 VMs (0 = disable)
    ssh_user="adp",                         # VM SSH username
    ssh_password="adp",                     # VM SSH password
)

# Pre-warm VM pool (optional, runs in background)
provider.warm_pool()
```

### Step 3: Use the Backend

```python
# Acquire a sandbox for a deer-flow thread
sandbox_id = provider.acquire(thread_id="my-thread")

# Get sandbox handle
sandbox = provider.get(sandbox_id)

# Execute commands inside the VM
output = sandbox.execute_command("pip install requests")
print(output)

# File operations
sandbox.write_file("/app/main.py", "print('Hello from ADP-OS VM!')")
content = sandbox.read_file("/app/main.py")

# Search
entries = sandbox.list_dir("/app", max_depth=1)
matches, truncated = sandbox.grep("/app", "Hello")

# Release when done
provider.release(sandbox_id)
```

### Provider Configuration Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `adp_home` | Yes | — | ADP-OS install directory |
| `pool_size` | No | `0` | Number of pre-warmed VMs (0 = disable) |
| `ssh_user` | No | `"adp"` | VM SSH username |
| `ssh_password` | No | `"adp"` | VM SSH password |

### Thread → Runtime Mapping

Deer-flow identifies sessions by `thread_id`. ADP-OS identifies VMs by `runtime` name. The provider maps between them:

- Default: `thread_id=None` → `"agent"` runtime
- Custom mappings persist to `~/.adp-deerflow/thread_runtime_registry.json`
- Use different runtime names (`agent`, `frontend`, `backend`, `sandbox`) for multi-agent isolation

### VM Pool Pre-Warming

Cold VM creation takes 15–45 minutes (Ubuntu autoinstall). Pre-warming eliminates this latency:

```python
provider = DeerFlowADPSandboxProvider(adp_home="...", pool_size=3)
provider.warm_pool()  # Background: boots 3 VMs

# First acquire() returns instantly — VM is already warm
sandbox_id = provider.acquire()
```

Pool VMs use `deerflow-pool-N` naming. If the pool is empty, `acquire()` creates a new VM automatically.

---

## End-to-End Flow

A deer-flow agent session with ADP-OS as the VM backend:

```
1. Deer-flow agent starts a task
2. SandboxMiddleware calls provider.acquire(thread_id="task-123")
3. ADP-OS boots (or retrieves from pool) a VM named "agent"
4. Provider returns sandbox_id → Deer-flow has a VM
5. Agent executes tools inside the VM:
   - bash        → adp_exec / SSH exec
   - write_file  → adp_file_write / SSH write
   - read_file   → adp_file_read / SSH read
   - glob/grep   → adp_glob / adp_grep / SSH find+grep
6. Task completes, middleware calls provider.release(sandbox_id)
7. ADP-OS stops the VM (adp_stop) or destroys it (adp_down)
```

### Performance Characteristics

| Scenario | Latency | Notes |
|----------|---------|-------|
| Warm VM from pool | ~5s | VM already running, SSH handshake only |
| Cached VM (prior boot) | ~30s | VM powered on, Ubuntu boots |
| Cold VM (first-time) | 15–45 min | Ubuntu autoinstall from ISO |
| In-VM command exec | <1s | SSH round-trip |

---

## MCP Tool Reference (In-VM Sandbox)

The 8 SSH-backed MCP tools that map to deer-flow's `Sandbox` interface:

| MCP Tool | Sandbox Method | Description |
|----------|---------------|-------------|
| `adp_exec(runtime, command, timeout=120)` | `execute_command(command)` | Execute bash command inside VM |
| `adp_file_read(runtime, path)` | `read_file(path)` | Read file content from VM |
| `adp_file_write(runtime, path, content, append=False)` | `write_file(path, content, append)` | Write text file to VM |
| `adp_dir_list(runtime, path, max_depth=2)` | `list_dir(path, max_depth)` | List directory contents |
| `adp_glob(runtime, path, pattern)` | `glob(path, pattern)` | Find files by pattern |
| `adp_grep(runtime, path, pattern)` | `grep(path, pattern)` | Search text in files |
| `adp_file_download(runtime, path)` | `download_file(path)` | Download file (base64) |
| `adp_file_upload(runtime, path, content_base64)` | `update_file(path, content)` | Upload file (base64) |

---

## Choosing Between Paths

| Factor | MCP Server | Direct Adapter |
|--------|-----------|----------------|
| Setup complexity | Low (JSON config only) | Medium (Python import) |
| Cross-language | Yes (any MCP client) | Python only |
| Protocol overhead | MCP stdio JSON | None (direct SSH) |
| Tool discovery | Automatic (MCP `list_tools`) | Manual (documented interface) |
| VM pool pre-warming | Not available (tools only) | Yes (`pool_size` + `warm_pool()`) |
| Thread→runtime mapping | Manual (runtime parameter) | Automatic (persistent registry) |
| SSH connection caching | Per-call | Cached `SSHConnection` pool |

**Recommendation**: Start with the MCP Server path for quick integration. Switch to the Direct Adapter path when you need VM pool pre-warming, persistent SSH connections, or lower protocol overhead.

---

## Known Limitations

1. **Windows host only**: ADP-OS currently requires VMware Workstation on a Windows host.
2. **Cold start latency**: First VM creation takes 15–45 minutes. Mitigate with VM pool pre-warming (Direct Adapter path).
3. **No cross-VM filesystem isolation**: ADP-OS VMs share the same filesystem. For concurrent agents, use separate runtime names.
4. **Static SSH credentials**: Default `adp`/`adp`. Change for production deployments.
5. **Single host**: All VMs run on the same VMware host. For multi-host scaling, deploy multiple ADP-OS instances.

---

## Next Steps

- [MCP Server Setup Guide](deer-flow-mcp-setup.md) — Step-by-step MCP configuration
- [Deer-Flow Integration Guide](../deer-flow-integration.md) — Full two-path reference
- [Deploying ADP-OS as Deer-Flow VM Sandbox Backend](deer-flow.md) — Architecture and gap analysis
- [ADP-OS MCP Server Source](../../cli/mcp/server.py) — Reference implementation (26 tools)
- [Direct Adapter Source](../../extensions/deer_flow/deerflow_adp_sandbox.py) — `DeerFlowADPSandboxProvider`
- [Operations Guide](../operations.md) — Day-to-day ADP-OS runtime management

---

> **Source Tags**: [FILE]=Source code analysis, [LLM]=LLM reasoning
