# Deploying ADP-OS as Deer-Flow VM Sandbox Backend

> **Date**: 2026-06-05 | **Source Tags**: [GH]=GitHub API, [FILE]=Source code analysis, [LLM]=LLM reasoning
> **Bilingual**: English & 中文 | **Target audience**: ADP-OS maintainers, deer-flow integrators

---

## Executive Summary

[LLM] [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow) (70K⭐) is a SuperAgent harness with Docker-based sandbox execution. Its `SandboxProvider` / `Sandbox` abstraction supports pluggable backends — ADP-OS can serve as a **hardware-VM sandbox backend** via the MCP protocol, offering stronger isolation than Docker containers.

**Key finding**: ADP-OS MCP server covers VM lifecycle management (create, start, stop, destroy) but **does NOT expose in-VM operations** (exec command, read/write file, list directory). Deer-flow agents need those for code execution. Integration requires two layers:

1. **Layer 1 (covered)**: VM lifecycle — `adp_up` / `adp_down` / `adp_stop` / `adp_status` via MCP
2. **Layer 2 (P0 gap)**: In-VM operations — requires SSH exec/file tools added to MCP server

---

## Deer-Flow Sandbox Architecture

### Sandbox Abstraction Stack

```
┌──────────────────────────────────────────────┐
│  Deer-flow Agent                              │
│  Uses: bash, ls, glob, grep, read_file,      │
│        write_file, str_replace                │
├──────────────────────────────────────────────┤
│  SandboxMiddleware                            │
│  Lifecycle: acquire → use → release           │
├──────────────────────────────────────────────┤
│  SandboxProvider                              │
│  Pluggable: AioSandbox | LocalSandbox | ???   │
├──────────────────────────────────────────────┤
│  Sandbox (ABC)                                │
│  Methods: execute_command, read_file,         │
│  write_file, list_dir, glob, grep,            │
│  download_file, update_file                   │
├──────────────────────────────────────────────┤
│  Backend: Docker containers (default)         │
│  OR Kubernetes pods via provisioner           │
└──────────────────────────────────────────────┘
```

### SandboxProvider Interface [FILE]

```python
class SandboxProvider(ABC):
    def acquire(self, thread_id: str | None = None) -> str: ...
    def get(self, sandbox_id: str) -> Sandbox | None: ...
    def release(self, sandbox_id: str) -> None: ...
```

### Sandbox Interface [FILE]

```python
class Sandbox(ABC):
    def execute_command(self, command: str) -> str: ...
    def read_file(self, path: str) -> str: ...
    def write_file(self, path: str, content: str, append: bool = False) -> None: ...
    def list_dir(self, path: str, max_depth: int = 2) -> list[str]: ...
    def glob(self, path: str, pattern: str, ...) -> tuple[list[str], bool]: ...
    def grep(self, path: str, pattern: str, ...) -> tuple[list[GrepMatch], bool]: ...
    def download_file(self, path: str) -> bytes: ...
    def update_file(self, path: str, content: bytes) -> None: ...
```

### Agent-Level Sandbox Tools [FILE]

| Tool | What it does |
|------|-------------|
| `bash` | Execute bash command in sandbox |
| `ls` | List directory contents |
| `glob` | Find files by pattern |
| `grep` | Search text inside files |
| `read_file` | Read file content |
| `write_file` | Write content to file |
| `str_replace` | String replacement in files |

---

## ADP-OS MCP Server: Tool Reference

18 MCP tools in 3 categories:

### Platform Tools (3)

| Tool | Function | Returns |
|------|----------|---------|
| `adp_status` | Health status of all/specific runtime | `{runtimes, runtime_count, running_count}` |
| `adp_doctor` | Platform diagnostics (47+ checks) | `{ok_count, issue_count, issues, healthy}` |
| `adp_capabilities` | Platform capabilities & roadmap | `{supported, planned, exploratory}` |

### Workspace Tools (10)

| Tool | Function | Key params |
|------|----------|------------|
| `adp_workspace_list` | List manifest projects | — |
| `adp_workspace_status` | Workspace readiness summary | — |
| `adp_workspace_dashboard` | Task lifecycle overview | — |
| `adp_workspace_project` | Single project lifecycle | `project_name` |
| `adp_workspace_create` | Create project directories | `project_name`, `plan_only` |
| `adp_workspace_open` | Entry guidance (paths, sync, SSH) | `project_name` |
| `adp_workspace_sync` | Per-project sync guidance | `project_name` |
| `adp_workspace_close` | Close workspace (stop sync) | `project_name`, `plan_only` |
| `adp_workspace_recipes` | List workspace recipes | — |
| `adp_workspace_report` | Markdown release evidence | — |

### Runtime Tools (5)

| Tool | Function | Key params |
|------|----------|------------|
| `adp_up` | Start VM (create from ISO if first time) | `runtime`, `plan_only`, `iso_path` |
| `adp_down` | Destroy VM completely | `runtime`, `plan_only`, `force` |
| `adp_stop` | Graceful VM shutdown | `runtime` |
| `adp_sync_status` | Mutagen sync session health | — |
| `adp_sync_stop` | Stop Mutagen sync session | `runtime` |

---

## Interface Mapping

### Lifecycle Mapping (Layer 1 — ✅ Covered)

| Deer-Flow SandboxProvider | ADP-OS MCP Tool | Status | Notes |
|---------------------------|-----------------|--------|-------|
| `acquire(thread_id)` → `sandbox_id` | `adp_up(runtime, plan_only=False)` + VM readiness check | ✅ Mapped | Thread→runtime mapping needed. ADP-OS: 15-45 min first-time ISO install. |
| `get(sandbox_id)` → `Sandbox` | `adp_status(runtime)` | ⚠️ Partial | Returns health info, not a Sandbox handle. Need SSH connection wrapper. |
| `release(sandbox_id)` | `adp_down(runtime, plan_only=False)` or `adp_stop(runtime)` | ✅ Mapped | `adp_stop` for graceful, `adp_down` for destroy |

### In-VM Operations (Layer 2 — ❌ P0 Gap)

| Deer-Flow Sandbox Method | ADP-OS MCP Tool | Status | Remediation |
|--------------------------|-----------------|--------|-------------|
| `execute_command(command)` | ❌ None | **P0 GAP** | Add `adp_exec(runtime, command)` → SSH exec |
| `read_file(path)` | ❌ None | **P0 GAP** | Add `adp_file_read(runtime, path)` → SSH cat/read |
| `write_file(path, content)` | ❌ None | **P0 GAP** | Add `adp_file_write(runtime, path, content)` → SSH tee/write |
| `list_dir(path, max_depth)` | ❌ None | **P0 GAP** | Add `adp_dir_list(runtime, path, max_depth)` → SSH find/ls |
| `glob(path, pattern)` | ❌ None | **P0 GAP** | Add `adp_glob(runtime, path, pattern)` → SSH find |
| `grep(path, pattern)` | ❌ None | **P0 GAP** | Add `adp_grep(runtime, path, pattern)` → SSH grep |
| `download_file(path)` | ❌ None | **P0 GAP** | Add `adp_file_download(runtime, path)` → SSH base64/scp |
| `update_file(path, content)` | ❌ None | **P0 GAP** | Add `adp_file_upload(runtime, path, content)` → SSH base64/scp |

### ADP-OS-Only Capabilities (No Deer-Flow Equivalent)

| ADP-OS MCP Tool | Value for deer-flow |
|-----------------|-------------------|
| `adp_doctor` | VM-level health diagnostics before agent runs |
| `adp_capabilities` | Platform capability discovery |
| `adp_workspace_dashboard` | Task lifecycle visibility across threads |
| `adp_workspace_report` | Evidence generation for release processes |
| `adp_sync_status` | File sync health (Mutagen) |
| `adp_workspace_recipes` | Workflow templates |

---

## Gap Analysis Summary

### P0 (Blocking — must be resolved before integration)

| ID | Gap | Impact |
|----|-----|--------|
| P0-1 | No in-VM `execute_command()` | Deer-flow agents cannot run code in ADP-OS VMs |
| P0-2 | No in-VM `read_file()` | Agents cannot inspect outputs |
| P0-3 | No in-VM `write_file()` | Agents cannot create/modify source files |
| P0-4 | No in-VM `list_dir()` | Agents cannot navigate VM filesystem |
| P0-5 | No in-VM `glob()` / `grep()` | Agents cannot search for files/patterns |
| P0-6 | No `get(sandbox_id)`→Sandbox pattern | No handle to bind in-VM ops to a specific VM |

**Root cause**: ADP-OS MCP server currently wraps the PowerShell `adp.ps1` CLI — which manages VMs from the HOST side. Deer-flow needs a sandbox provider that runs operations INSIDE the VM.

### P1 (Important — address in v2)

| ID | Gap | Impact |
|----|-----|--------|
| P1-1 | No deer-flow `SandboxProvider` adapter class | Requires manual mapping of lifecycle calls |
| P1-2 | No thread→runtime name mapping | Deer-flow uses `thread_id`, ADP-OS uses `runtime` (agent/frontend/backend) |
| P1-3 | First-time VM startup: 15-45 min | Deer-flow expects sub-second sandbox acquisition |
| P1-4 | Windows-first platform vs deer-flow's Linux containers | Mismatch in default OS target |

### P2 (Nice-to-have — post-launch)

| ID | Gap | Impact |
|----|-----|--------|
| P2-1 | No workspace→thread isolation | ADP-OS workspaces are project-level, not thread-level |
| P2-2 | No snapshot/rollback tool exposed | ADP-OS has snapshots but MCP doesn't expose them |
| P2-3 | Skills mount path mismatch | Deer-flow expects `/mnt/skills/`, ADP-OS uses different workspace layout |

---

## Integration Path

### Phase 1: SSH-Backed Sandbox Provider (Resolves P0)

Add 8 new MCP tools to `cli/mcp/server.py` that execute inside running VMs via SSH:

```
adp_exec(runtime, command) → {stdout, stderr, exit_code}
adp_file_read(runtime, path) → {content, path}
adp_file_write(runtime, path, content, append=False) → {path, written}
adp_dir_list(runtime, path, max_depth=2) → {entries}
adp_glob(runtime, path, pattern) → {matches, truncated}
adp_grep(runtime, path, pattern, ...) → {matches, truncated}
adp_file_download(runtime, path) → {content_base64}
adp_file_upload(runtime, path, content_base64) → {path}
```

This brings the MCP server from 18 → 26 tools.

### Phase 2: Deer-Flow Adapter Class (Resolves P1)

Write `DeerFlowADPSandboxProvider` that implements `SandboxProvider` using the MCP client:

```python
class DeerFlowADPSandboxProvider(SandboxProvider):
    def acquire(self, thread_id=None) -> str:
        runtime = self._thread_to_runtime(thread_id)
        self._mcp.adp_up(runtime, plan_only=False)
        return runtime  # runtime name IS sandbox_id

    def get(self, sandbox_id) -> Sandbox:
        return ADPSSHSandbox(sandbox_id, self._ssh_config)

    def release(self, sandbox_id):
        self._mcp.adp_down(sandbox_id, plan_only=False)
```

### Phase 3: Production Hardening (Resolves P1-3, P1-4)

- **VM pool pre-warming**: Keep N VMs ready to eliminate 15-45 min cold start
- **Linux guest support**: Ubuntu autoinstall already works; document deer-flow-specific VM template
- **Thread→runtime registry**: Map deer-flow `thread_id` → ADP-OS `runtime` name
- **Resource limits**: Match ADP-OS VM resources to deer-flow sandbox specs (100m-1000m CPU, 256Mi-1Gi RAM)

---

## Code-Level Example

### Current: Deer-Flow + Docker Sandbox

```python
# deer-flow agent calls bash tool
# → SandboxMiddleware acquires Docker container
# → bash_tool calls sandbox.execute_command("pip install requests")
# → Docker exec runs command, returns stdout
```

### Target: Deer-Flow + ADP-OS VM Sandbox

```python
# deer-flow agent calls bash tool
# → SandboxMiddleware acquires ADP-OS VM
# → ADP-OS MCP: adp_up("agent", plan_only=False)
#   → VMware boots Ubuntu VM (~30s for cached, ~20min for first install)
# → ADPSandbox.execute_command("pip install requests")
#   → MCP tool adp_exec("agent", "pip install requests")
#   → SSH into VM, run command, return stdout
# → Cleanup: adp_down("agent") or adp_stop("agent")
```

---

## Verification Checklist

- [ ] 8 new SSH-backed MCP tools implemented in `cli/mcp/server.py` (26 total)
- [ ] Test suite updated (`tests/test-mcp-server.py`) covering new tools
- [ ] Deer-flow `SandboxProvider` adapter class implemented
- [ ] Integration test: deer-flow agent → ADP-OS VM → code execution
- [ ] Startup time documented (cold start vs warm VM)
- [ ] Thread→runtime mapping registry documented

---

## References

- [Deer-flow Sandbox Provisioner](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner) — K8s-based sandbox Pod manager
- [Deer-flow Sandbox ABC](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/sandbox.py) — Abstract sandbox interface
- [Deer-flow Sandbox Tools](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/tools.py) — Agent-facing sandbox operations
- [ADP-OS MCP Server](cli/mcp/server.py) — Reference implementation (18 tools)
- [ADP-OS MCP Tests](tests/test-mcp-server.py) — Test suite

---

> **Source Tags**: [GH]=GitHub API, [FILE]=Source code analysis, [LLM]=LLM reasoning
