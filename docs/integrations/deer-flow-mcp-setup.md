# ADP-OS MCP Server Setup for Deer-Flow

> **Date**: 2026-06-05 | **Target audience**: Deer-flow integrators, ADP-OS operators
> **Bilingual**: English & 中文 | [简体中文版](../zh-CN/integrations/deer-flow-mcp-setup.md)

Step-by-step, copy-paste runnable guide to connect [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow) (70K⭐) to ADP-OS VMs via the **MCP protocol**. Each command is tested and self-contained.

For the comprehensive integration reference covering both MCP and Direct Adapter paths, see [Deer-Flow Integration Guide](../deer-flow-integration.md) ([简体中文](../zh-CN/deer-flow-integration.md)). For architecture and gap analysis, see [Deploying ADP-OS as Deer-Flow VM Sandbox Backend](deer-flow.md).

---

## What You Get

After completing this guide, deer-flow agents can:

- **Start/stop ADP-OS VMs** on demand (VM lifecycle via MCP tools)
- **Execute commands inside VMs** (shell, Python, any tool)
- **Read/write files** in the sandbox filesystem
- **Search content** with glob and grep patterns
- **Download/upload files** between agent context and VM

26 MCP tools across 4 categories: Platform (3), Workspace (10), Runtime (5), In-VM Sandbox (8).

---

## Prerequisites

| Requirement | How to verify | Notes |
|-------------|--------------|-------|
| ADP-OS installed | `adpos doctor` | VMware Workstation on Windows host |
| SSH reachable VM | `adpos status` | At least one runtime configured |
| Python 3.10+ | `python3 --version` | Required by MCP server |
| deer-flow installed | Project root has `extensions_config.json` | deer-flow MCP extension support |
| (Optional) `paramiko` | `pip install paramiko` | Better SSH performance |

```bash
# Quick prerequisite check
adpos doctor   # Should return "healthy"
python3 --version                # Should be ≥3.10
```

---

## Step 1: Verify ADP-OS MCP Server

The MCP server exposes ADP-OS as an MCP tool provider.

```bash
cd /path/to/ai-dev-platform

# Verify the MCP server module loads and all 26 tools are registered
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP tools registered: {len(tools)}')
print(f'Tool names: {sorted(tools)}')
"
```

Expected output: **26 tools** across these categories:

| Category | Tools | Count |
|----------|-------|-------|
| **Platform** | `adp_status`, `adp_doctor`, `adp_capabilities` | 3 |
| **Workspace** | `adp_workspace_list`, `adp_workspace_status`, `adp_workspace_dashboard`, `adp_workspace_project`, `adp_workspace_create`, `adp_workspace_open`, `adp_workspace_sync`, `adp_workspace_close`, `adp_workspace_recipes`, `adp_workspace_report` | 10 |
| **Runtime** | `adp_up`, `adp_down`, `adp_stop`, `adp_sync_status`, `adp_sync_stop` | 5 |
| **In-VM Sandbox** | `adp_exec`, `adp_file_read`, `adp_file_write`, `adp_dir_list`, `adp_glob`, `adp_grep`, `adp_file_download`, `adp_file_upload` | 8 |

Verify the server starts correctly:

```bash
# Test MCP server starts and responds (Ctrl+C after output appears)
ADP_HOME=$(pwd) python3 cli/mcp/server.py
```

---

## Step 2: Configure Deer-Flow MCP Extension

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

### Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `ADP_HOME` | **Yes** | ADP-OS install directory (WSL/Linux path) | `/home/user/ai-dev-platform` |
| `ADP_HOME_WIN` | WSL only | ADP-OS Windows path for `pwsh.exe` | `D:\\Dev\\ai-dev-platform` |
| `ADP_SSH_USER` | No | VM SSH username (default: `adp`) | `adp` |
| `ADP_SSH_PASSWORD` | No | VM SSH password (default: `adp`) | `adp` |

### Configuration Examples

**WSL (Windows Subsystem for Linux)**

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

**Native Linux**

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/opt/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/opt/ai-dev-platform"
    }
  }
}
```

**macOS (requires pwsh + VMware Fusion or UTM as VM backend)**

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/Users/me/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/Users/me/ai-dev-platform"
    }
  }
}
```

> **Important**: Paths in `command` and `args` must be **absolute**. Relative paths fail in stdio MCP transport because the working directory is undetermined.

---

## Step 3: Restart Deer-Flow

After updating `extensions_config.json`, restart deer-flow to load the ADP-OS MCP extension. The 26 ADP-OS tools appear alongside deer-flow's built-in sandbox tools.

Deer-flow agent should now have access to these sandbox tools. These `adp_*` names are MCP tool names, not local shell commands:

```
adp_up, adp_down, adp_stop, adp_status,
adp_exec, adp_file_read, adp_file_write,
adp_dir_list, adp_glob, adp_grep,
adp_file_download, adp_file_upload,
adp_workspace_*, adp_sync_*, adp_doctor, adp_capabilities
```

---

## Step 4: Validate the Integration

### VM Lifecycle Test

In the deer-flow agent context, exercise the VM lifecycle. These are MCP tool invocations; for a local terminal, use `adpos up agent`, `adpos status agent`, and `adpos stop agent`.

```
# Start an ADP-OS VM
adp_up agent

# Check VM status
adp_status agent

# Run a command inside the VM
adp_exec agent "python3 --version"

# Graceful shutdown
adp_stop agent
```

**Expected behavior**:
- `adp_up agent`: Creates or boots the `agent` runtime VM. First-time: 15-45 min (Ubuntu autoinstall). Warm: ~30s.
- `adp_status agent`: Shows VM running with SSH reachable.
- `adp_exec`: Returns command stdout from inside the VM.
- `adp_stop agent`: Gracefully shuts down the VM.

### In-VM File Operations Test

```
# Write a file inside the VM
adp_file_write agent "/tmp/test.py" "print('Hello from ADP-OS!')" plan_only=False

# Read it back
adp_file_read agent "/tmp/test.py"

# List the directory
adp_dir_list agent "/tmp" max_depth=1

# Execute the file
adp_exec agent "python3 /tmp/test.py"

# Search with glob
adp_glob agent "/tmp" "*.py"

# Search file contents
adp_grep agent "/tmp" "Hello"
```

**Expected behavior**:
- File written and read successfully.
- `adp_dir_list` returns directory entries.
- `adp_exec` runs Python and prints "Hello from ADP-OS!".
- `adp_glob` finds `test.py`.
- `adp_grep` finds "Hello" in the file.

### Diagnostics Test

```
# Platform health check
adp_doctor

# Platform capabilities
adp_capabilities
```

---

## MCP Tool → Sandbox Method Mapping

The 8 in-VM MCP tools map 1:1 to deer-flow's `Sandbox` abstract interface:

| MCP Tool | Sandbox Method | Signature Match | Notes |
|----------|---------------|-----------------|-------|
| `adp_exec(runtime, command, timeout)` | `execute_command(command)` | ✅ Compatible | `runtime` is session-scoped (MCP extra) |
| `adp_file_read(runtime, path)` | `read_file(path)` | ✅ Compatible | |
| `adp_file_write(runtime, path, content, append)` | `write_file(path, content, append)` | ✅ Exact match | `plan_only=True` default — adapter overrides |
| `adp_dir_list(runtime, path, max_depth)` | `list_dir(path, max_depth)` | ✅ Exact match | |
| `adp_glob(runtime, path, pattern, include_dirs, max_results)` | `glob(path, pattern, include_dirs, max_results)` | ✅ Exact match | |
| `adp_grep(runtime, path, pattern, glob_filter, literal, case_sensitive, max_results)` | `grep(path, pattern, glob, literal, case_sensitive, max_results)` | ✅ Compatible | `glob_filter` vs `glob` naming (maps cleanly) |
| `adp_file_download(runtime, path)` | `download_file(path)` | ✅ Compatible | |
| `adp_file_upload(runtime, path, content_base64, plan_only)` | `update_file(path, content)` | ✅ Compatible | base64 (MCP-safe) vs bytes (Sandbox native) |

### Bridgeable Differences

| Difference | Type | Impact | Resolution |
|------------|------|--------|------------|
| `runtime` parameter on every tool | Session isolation | MCP tools scope operations to a specific VM; deer-flow scopes to a `Sandbox` instance | Adapter layer threads `runtime` for each acquire cycle |
| `content_base64` (str) vs `bytes` | Content encoding | MCP protocol uses JSON-safe base64; deer-flow natively uses bytes | Adapter base64-encodes/decodes at protocol boundary |
| `plan_only=True` default | Safety design | MCP tools preview by default to prevent accidental VM mutations | Adapter passes `plan_only=False` on production calls |
| `glob_filter` vs `glob` naming | Cosmetic | `adp_grep` names the file filter `glob_filter`; deer-flow `Sandbox.grep()` names it `glob` | Parameter mapping in adapter |

All differences are **bridgeable at the adapter level** and do not require MCP server changes.

---

## Troubleshooting

### MCP server doesn't start

**Symptoms**: Deer-flow can't connect to MCP server. Logs show "failed to start MCP extension."

**Checks**:
1. Python 3.10+ installed: `python3 --version`
2. ADP-OS repository exists: `ls /path/to/ai-dev-platform/cli/mcp/server.py`
3. Absolute paths in `extensions_config.json` (relative paths fail in stdio mode)
4. `fastmcp` installed: `python3 -c "from mcp.server.fastmcp import FastMCP; print('OK')"`
5. Environment variables set and correct

```bash
# Verify MCP server starts standalone
cd /absolute/path/to/ai-dev-platform
ADP_HOME=$(pwd) python3 cli/mcp/server.py 2>&1 &
# Should start without errors; kill after verifying
kill %1
```

### VM doesn't start (timeout)

**Symptoms**: `adp_up agent` returns timeout or "VM not ready" after several minutes.

**Checks**:
1. VMware Workstation is running on the Windows host
2. `adpos status` shows VM state
3. First-time Ubuntu autoinstall can take 15-45 minutes — wait longer
4. ISO exists at the configured path in `configs/topology.json`

### "adp_exec" returns "Connection refused"

**Symptoms**: In-VM tools fail with "Connection refused" or SSH errors.

**Checks**:
1. VM is running: `adp_status agent`
2. SSH credentials match `configs/topology.json`
3. VMware NAT network is properly configured
4. Integration host can reach the VM's IP address

```bash
# Direct SSH test (replace IP with actual VM IP)
ssh -o StrictHostKeyChecking=no adp@<vm-ip> "echo 'SSH OK'"
```

### "pwsh.exe not found" (WSL)

**Symptoms**: ADP-OS commands fail with "pwsh not found" when running from WSL.

**Solution**: Set `ADP_HOME_WIN` in `extensions_config.json` env section. The MCP server uses this to resolve `pwsh.exe` from WSL context.

### "plan_only" blocks actual writes

**Symptoms**: `adp_file_write` or `adp_file_upload` doesn't actually write to the VM.

**Explanation**: MCP tools default to `plan_only=True` for safety. The agent must explicitly pass `plan_only=False`:

```
adp_file_write agent "/tmp/config.json" '{"key": "value"}' plan_only=False
adp_file_upload agent "/tmp/data.bin" "SGVsbG8=" plan_only=False
```

---

## Known Limitations

1. **Cold start latency**: First-time VM creation requires 15-45 minutes for Ubuntu autoinstall. Subsequent boots: ~30 seconds. Consider pre-warming VMs by invoking the MCP tool `adp_up` before agent sessions begin.

2. **Windows host only**: ADP-OS currently requires VMware Workstation on a Windows host. Linux/macOS hosts not supported for VM provisioning.

3. **No cross-VM filesystem isolation**: deer-flow's native Docker sandbox creates isolated filesystems per session. ADP-OS VMs share the same filesystem — concurrent agents on the same runtime may interfere.

4. **SSH credential management**: VM SSH passwords are currently static (`adp`/`adp`). Production deployments should change default passwords and use SSH keys.

5. **Single runtime per session**: MCP tools bind to a single `runtime` parameter. For multi-agent scenarios, acquire separate VMs via different runtime names (agent, frontend, backend, sandbox).

---

## Verification Checklist

Items using `adpos` are local CLI checks. Items using `adp_*` are MCP tool checks from the deer-flow agent context.

- [ ] ADP-OS CLI healthy: `adpos doctor`
- [ ] At least one VM runtime configured: `adpos status`
- [ ] MCP server module loads: `python3 -c "from cli.mcp.server import mcp; print(len(mcp._tool_manager._tools))"` → `26`
- [ ] MCP server tests pass: `python3 -m pytest tests/test-mcp-server.py tests/test-mcp-vm-tools.py -q` → `46 passed`
- [ ] Deer-flow adapter tests pass: `python3 -m pytest tests/test_deerflow_adp_sandbox.py -q` → `46 passed`
- [ ] `extensions_config.json` configured with absolute paths and correct env vars
- [ ] Deer-flow restarted and 26 ADP-OS tools visible to the agent
- [ ] `adp_up agent` succeeds (creates or boots the VM)
- [ ] `adp_exec agent "python3 --version"` returns Python version from inside the VM
- [ ] `adp_file_read` / `adp_file_write` work correctly on the VM

---

## References

- [Deer-Flow Sandbox Architecture](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner)
- [Deer-Flow Sandbox ABC](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/sandbox.py)
- [ADP-OS MCP Server Source](../../cli/mcp/server.py) — 26-tool entrypoint with package helpers
- [ADP-OS Deer-Flow Adapter](../../extensions/deer_flow/deerflow_adp_sandbox.py) — Python-native integration path
- [Deer-Flow Integration Guide](../deer-flow-integration.md) — Comprehensive both-path reference
- [Deer-Flow Gap Analysis](deer-flow.md) — Architecture and gap tracking

---

> **Source Tags**: [FILE]=Source code analysis, [LLM]=LLM reasoning

---

**Next step** after completing this guide: Deploy the Python-native `DeerFlowADPSandboxProvider` adapter for production use (VM pool pre-warming, thread→runtime registry, SSH connection caching). See [Deer-Flow Integration Guide - Path 2](../deer-flow-integration.md#path-2-direct-adapter-python-native).
