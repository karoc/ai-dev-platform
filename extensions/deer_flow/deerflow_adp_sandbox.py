"""
Deer-Flow ADP-OS SandboxProvider Adapter

Implements deer-flow's SandboxProvider and Sandbox abstract interfaces using
ADP-OS VMs as the sandbox backend.  VM lifecycle is managed via the ADP-OS CLI;
in-VM operations use direct SSH.

Architecture:

    Deer-Flow Agent
        │
    DeerFlowADPSandboxProvider      ← this module
        ├── acquire(thread_id) → sandbox_id   (adp.ps1 up + status)
        ├── get(sandbox_id)   → ADPSSHSandbox (SSH to VM)
        └── release(sandbox_id)                (adp.ps1 stop/down)

    ADPSSHSandbox                   ← SSH-backed Sandbox
        ├── execute_command()       ssh <vm> <cmd>
        ├── read_file / write_file  ssh cat / tee
        ├── list_dir / glob / grep  ssh ls / find / grep
        └── download / update_file  ssh base64 + scp

Dependencies:
    - paramiko (SSH) or subprocess ssh fallback
    - ADP-OS CLI installed (adp.ps1 + PowerShell 7+)
    - ADP-OS VMs accessible via SSH (port 22 on VMware NAT subnet)

Thread→Runtime Mapping:
    Maps deer-flow thread_id strings to ADP-OS runtime names (agent/frontend/
    backend/sandbox).  Stored persistently in a JSON file so mappings survive
    restarts.  Default mapping when thread_id is None: "agent" runtime.

VM Pool:
    Pre-warms N VMs to eliminate cold-start latency.  When acquire() is called,
    checks pool first before creating a new VM.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Logger
# ---------------------------------------------------------------------------

logger = logging.getLogger("deerflow.adp.sandbox")

# ---------------------------------------------------------------------------
# GrepMatch — matches deer-flow deerflow.sandbox.search.GrepMatch
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class GrepMatch:
    """A single grep match result, compatible with deer-flow's type."""

    path: str
    line_number: int
    line: str

    def __repr__(self) -> str:
        return f"GrepMatch({self.path}:{self.line_number})"


# ---------------------------------------------------------------------------
# Abstract base classes — mirror deer-flow's Sandbox / SandboxProvider ABCs
# ---------------------------------------------------------------------------


class Sandbox(ABC):
    """Abstract sandbox (mirrors deer-flow's Sandbox ABC).

    The eight abstract methods below match deer-flow's interface exactly so
    that ADPSSHSandbox can be used as a drop-in replacement.
    """

    _id: str

    def __init__(self, sandbox_id: str) -> None:
        self._id = sandbox_id

    @property
    def id(self) -> str:
        return self._id

    @abstractmethod
    def execute_command(self, command: str) -> str:
        """Execute a bash command inside the sandbox and return stdout/stderr."""
        ...

    @abstractmethod
    def read_file(self, path: str) -> str:
        """Read the content of a file inside the sandbox."""
        ...

    @abstractmethod
    def download_file(self, path: str) -> bytes:
        """Download the binary content of a file."""
        ...

    @abstractmethod
    def list_dir(self, path: str, max_depth: int = 2) -> list[str]:
        """List directory contents up to *max_depth*."""
        ...

    @abstractmethod
    def write_file(self, path: str, content: str, append: bool = False) -> None:
        """Write (or append) text content to a file."""
        ...

    @abstractmethod
    def glob(
        self,
        path: str,
        pattern: str,
        *,
        include_dirs: bool = False,
        max_results: int = 200,
    ) -> tuple[list[str], bool]:
        """Glob for paths matching *pattern* under *path*."""
        ...

    @abstractmethod
    def grep(
        self,
        path: str,
        pattern: str,
        *,
        glob: str | None = None,
        literal: bool = False,
        case_sensitive: bool = False,
        max_results: int = 100,
    ) -> tuple[list[GrepMatch], bool]:
        """Search for *pattern* inside text files under *path*."""
        ...

    @abstractmethod
    def update_file(self, path: str, content: bytes) -> None:
        """Overwrite a file with binary content."""
        ...


class SandboxProvider(ABC):
    """Abstract sandbox provider (mirrors deer-flow's SandboxProvider ABC)."""

    @abstractmethod
    def acquire(self, thread_id: str | None = None) -> str:
        """Acquire a sandbox, returning its id."""
        ...

    @abstractmethod
    def get(self, sandbox_id: str) -> Sandbox | None:
        """Return a Sandbox handle for *sandbox_id*."""
        ...

    @abstractmethod
    def release(self, sandbox_id: str) -> None:
        """Release (stop/destroy) a sandbox."""
        ...


# ---------------------------------------------------------------------------
# SSH backend — wraps paramiko with subprocess-ssh fallback
# ---------------------------------------------------------------------------


class SSHConnection:
    """Lightweight SSH connection wrapper.

    Prefers paramiko when available; falls back to subprocess ssh otherwise.
    """

    def __init__(
        self,
        host: str,
        port: int = 22,
        username: str = "adp",
        password: str = "adp",
        key_filename: str | None = None,
        timeout: float = 30.0,
    ) -> None:
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.key_filename = key_filename
        self.timeout = timeout
        self._client: object | None = None  # paramiko.SSHClient when available

    # -- paramiko path -------------------------------------------------------

    def _ensure_paramiko(self) -> object:
        """Lazy-import paramiko and create a connected client."""
        if self._client is not None:
            return self._client
        try:
            import paramiko  # type: ignore[import-untyped]
        except ImportError:
            raise RuntimeError(
                "paramiko is not installed. "
                "Install with: pip install paramiko"
            )
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        connect_kwargs: dict = {
            "hostname": self.host,
            "port": self.port,
            "username": self.username,
            "timeout": self.timeout,
        }
        if self.key_filename:
            connect_kwargs["key_filename"] = self.key_filename
        else:
            connect_kwargs["password"] = self.password
        client.connect(**connect_kwargs)
        self._client = client
        return client

    def _paramiko_exec(self, command: str, timeout: float = 120.0) -> tuple[str, str, int]:
        """Execute command via paramiko, returning (stdout, stderr, exit_code)."""
        client = self._ensure_paramiko()
        import paramiko  # type: ignore[import-untyped]
        chan: paramiko.Channel = client.get_transport().open_session()  # type: ignore[union-attr]
        chan.exec_command(command)
        chan.settimeout(timeout)
        stdout_raw = chan.makefile("r", -1).read()
        stderr_raw = chan.makefile_stderr("r", -1).read()
        exit_code = chan.recv_exit_status()
        # paramiko may return bytes or str depending on mode
        stdout = stdout_raw.decode("utf-8", errors="replace") if isinstance(stdout_raw, bytes) else stdout_raw
        stderr = stderr_raw.decode("utf-8", errors="replace") if isinstance(stderr_raw, bytes) else stderr_raw
        return stdout, stderr, exit_code

    # -- subprocess-ssh fallback ---------------------------------------------

    def _subprocess_exec(self, command: str, timeout: float = 120.0) -> tuple[str, str, int]:
        """Execute command via subprocess ssh, returning (stdout, stderr, exit_code)."""
        ssh_bin = shutil.which("ssh")
        if not ssh_bin:
            raise RuntimeError("ssh binary not found in PATH")
        dest = f"{self.username}@{self.host}"
        ssh_args = [
            ssh_bin,
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", f"ConnectTimeout={int(self.timeout)}",
            "-p", str(self.port),
            dest,
            command,
        ]
        # Prefer key-based auth if available
        if self.key_filename:
            ssh_args[2:2] = ["-i", self.key_filename]
        else:
            # Use sshpass for password auth; fall back to interactive if unavailable
            sshpass = shutil.which("sshpass")
            if sshpass:
                ssh_args = [
                    sshpass, "-p", self.password,
                ] + ssh_args
        try:
            result = subprocess.run(
                ssh_args,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            return result.stdout, result.stderr, result.returncode
        except subprocess.TimeoutExpired:
            return "", f"SSH command timed out after {timeout}s", -1

    # -- public API ----------------------------------------------------------

    def exec_command(self, command: str, timeout: float = 120.0) -> tuple[str, str, int]:
        """Execute *command* on the remote host.

        Returns:
            (stdout, stderr, exit_code)
        """
        try:
            return self._paramiko_exec(command, timeout)
        except Exception as exc:
            logger.debug("paramiko exec failed (%s), falling back to subprocess ssh", exc)
            return self._subprocess_exec(command, timeout)

    def exec_command_output(self, command: str, timeout: float = 120.0) -> str:
        """Execute *command* and return combined stdout+stderr."""
        stdout, stderr, _exit = self.exec_command(command, timeout)
        parts: list[str] = []
        if stdout:
            parts.append(stdout.rstrip())
        if stderr:
            parts.append(stderr.rstrip())
        return "\n".join(parts)

    def close(self) -> None:
        """Close the underlying SSH connection."""
        if self._client is not None:
            try:
                self._client.close()  # type: ignore[union-attr]
            except Exception:
                pass
            self._client = None


# ---------------------------------------------------------------------------
# ADP-OS CLI wrapper (subprocess → adp.ps1 via pwsh)
# ---------------------------------------------------------------------------


class ADPCLI:
    """Minimal wrapper around the ADP-OS PowerShell CLI.

    Uses subprocess to invoke ``pwsh.exe -File adp.ps1 <args...>``, the same
    mechanism as the ADP-OS MCP server.
    """

    def __init__(self, adp_home: str | Path, ssh_user: str = "adp", ssh_password: str = "adp") -> None:
        self.adp_home = Path(adp_home).resolve()
        self.ssh_user = ssh_user
        self.ssh_password = ssh_password
        self._pwsh: str | None = None
        self._topology: dict = {}
        self._load_topology()

    def _load_topology(self) -> None:
        """Load topology from disk."""
        topo_path = self.adp_home / "configs" / "topology.json"
        if topo_path.exists():
            raw = json.loads(topo_path.read_text(encoding="utf-8"))
            self._topology = raw if isinstance(raw, dict) else {}
        else:
            self._topology = {}

    def load_topology(self) -> dict:
        """Load runtime topology (static IPs, ports, etc.)."""
        if not self._topology:
            self._load_topology()
        return self._topology

    # -- pwsh resolution -----------------------------------------------------

    @property
    def pwsh(self) -> str:
        if self._pwsh is None:
            self._pwsh = shutil.which("pwsh.exe") or shutil.which("pwsh") or "pwsh"
        return self._pwsh

    # -- topology ------------------------------------------------------------

    def get_runtime_ssh_info(self, runtime: str) -> dict:
        """Return SSH connection info for *runtime*."""
        topo = self.load_topology()
        rt = topo.get(runtime, {})
        return {
            "ip": rt.get("static_ip", ""),
            "port": rt.get("ssh_port", 22),
            "user": self.ssh_user,
            "password": self.ssh_password,
        }

    # -- command execution ---------------------------------------------------

    def _run(self, args: list[str], timeout: int = 300) -> dict:
        """Run ``adp.ps1 <args>`` and return {stdout, stderr, exit_code, success}."""
        adp_script = self.adp_home / "cli" / "adp.ps1"
        cmd = [
            self.pwsh, "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(adp_script),
        ] + args
        try:
            result = subprocess.run(
                cmd,
                capture_output=True, text=True, timeout=timeout,
                cwd=str(self.adp_home),
            )
            return {
                "stdout": result.stdout.strip(),
                "stderr": result.stderr.strip(),
                "exit_code": result.returncode,
                "success": result.returncode == 0,
            }
        except subprocess.TimeoutExpired:
            return {"stdout": "", "stderr": f"Command timed out after {timeout}s", "exit_code": -1, "success": False}
        except FileNotFoundError:
            return {"stdout": "", "stderr": f"pwsh not found: {self.pwsh}", "exit_code": -1, "success": False}

    def status(self, runtime: str | None = None) -> dict:
        """Run ``adp status [runtime]`` and parse output."""
        args = ["status"]
        if runtime:
            args.append(runtime)
        return self._run(args, timeout=60)

    def up(self, runtime: str, plan_only: bool = False, iso_path: str | None = None) -> dict:
        """Run ``adp up <runtime>``."""
        args = ["up", runtime]
        if plan_only:
            args.append("-Plan")
        if iso_path:
            args.append("-IsoPath")
            args.append(iso_path)
        return self._run(args, timeout=1800)  # 30 min — first boot can be long

    def stop(self, runtime: str) -> dict:
        """Run ``adp stop <runtime>``."""
        return self._run(["stop", runtime], timeout=120)

    def down(self, runtime: str, plan_only: bool = False, force: bool = False) -> dict:
        """Run ``adp destroy <runtime>``."""
        args = ["destroy", runtime]
        if plan_only:
            args.append("-Plan")
        if force:
            args.append("-Force")
        return self._run(args, timeout=300)

    def doctor(self) -> dict:
        """Run ``adp doctor``."""
        return self._run(["doctor"], timeout=120)


# ---------------------------------------------------------------------------
# Thread → Runtime Registry
# ---------------------------------------------------------------------------


class ThreadRuntimeRegistry:
    """Persistent mapping of deer-flow thread_id → ADP-OS runtime name.

    Stored as a JSON file so mappings survive process restarts.
    Built-in defaults:
        - thread_id None  → "agent"
        - thread_id "agent" → "agent"
        - thread_id "sandbox" → "sandbox"
    """

    DEFAULT_MAP: dict[str | None, str] = {
        None: "agent",
        "": "agent",
    }

    def __init__(self, registry_path: str | Path | None = None) -> None:
        self.registry_path = Path(registry_path) if registry_path else (
            Path.home() / ".adp-deerflow" / "thread_runtime_registry.json"
        )
        self._lock = threading.RLock()
        self._map: dict[str, str] = {}

    def _ensure_dir(self) -> None:
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)

    def load(self) -> None:
        """Load the registry from disk (idempotent)."""
        with self._lock:
            if self.registry_path.exists():
                try:
                    self._map = json.loads(self.registry_path.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    self._map = {}
            else:
                self._map = {}

    def save(self) -> None:
        """Persist the registry to disk."""
        with self._lock:
            self._ensure_dir()
            self.registry_path.write_text(
                json.dumps(self._map, indent=2, sort_keys=True),
                encoding="utf-8",
            )

    def get(self, thread_id: str | None) -> str:
        """Resolve *thread_id* to an ADP-OS runtime name.

        Resolution order:
            1. Explicit mapping in registry
            2. DEFAULT_MAP (None → "agent")
            3. thread_id itself (fallback)
        """
        key = thread_id or ""
        with self._lock:
            self.load()
            # Check explicit mapping
            if key in self._map:
                return self._map[key]
            # Check defaults
            if key in self.DEFAULT_MAP:
                return self.DEFAULT_MAP[key]
            if thread_id and thread_id in self.DEFAULT_MAP:
                return self.DEFAULT_MAP[thread_id]
            # Fallback: treat thread_id as the runtime name
            return thread_id or "agent"

    def set(self, thread_id: str, runtime: str) -> None:
        """Record a thread → runtime mapping."""
        with self._lock:
            self.load()
            self._map[thread_id] = runtime
            self.save()

    def remove(self, thread_id: str) -> None:
        """Remove a thread mapping."""
        with self._lock:
            self.load()
            self._map.pop(thread_id, None)
            self.save()

    def list_runtimes(self) -> list[str]:
        """Return all runtime names currently mapped."""
        with self._lock:
            self.load()
            return list(self._map.values())


# ---------------------------------------------------------------------------
# VM Pool — pre-warmed VMs for cold-start mitigation
# ---------------------------------------------------------------------------

# Default pool size.  Set to 0 to disable pooling.
DEFAULT_POOL_SIZE = 2


@dataclass
class _PoolEntry:
    runtime_name: str
    ssh_info: dict
    created_at: float = field(default_factory=time.time)


class VMPool:
    """Maintain a pool of pre-warmed ADP-OS VMs.

    When acquire() is called, the pool is checked first.  If a VM is available,
    it is returned immediately (no cold-start wait).  Otherwise, a new VM is
    created on demand.

    Pool VMs use runtime names like ``deerflow-pool-0``, ``deerflow-pool-1``,
    etc. to avoid colliding with user-named runtimes.
    """

    def __init__(
        self,
        cli: ADPCLI,
        registry: ThreadRuntimeRegistry,
        pool_size: int = DEFAULT_POOL_SIZE,
    ) -> None:
        self.cli = cli
        self.registry = registry
        self.pool_size = pool_size
        self._lock = threading.Lock()
        self._pool: list[_PoolEntry] = []
        self._warm_lock = threading.Lock()

    def _pool_runtime_name(self, index: int) -> str:
        return f"deerflow-pool-{index}"

    def warm(self) -> None:
        """Pre-warm the pool (non-blocking).

        Creates pool VMs in the background.  Safe to call multiple times.
        """
        if self.pool_size <= 0:
            return
        acquired = self._warm_lock.acquire(blocking=False)
        if not acquired:
            return  # already warming
        try:
            for i in range(self.pool_size):
                rt_name = self._pool_runtime_name(i)
                logger.info("Warming pool VM %d/%d: %s", i + 1, self.pool_size, rt_name)
                result = self.cli.up(rt_name)
                if result["success"]:
                    ssh_info = self.cli.get_runtime_ssh_info(rt_name)
                    if ssh_info["ip"]:
                        with self._lock:
                            self._pool.append(_PoolEntry(rt_name, ssh_info))
                        logger.info("Pool VM %s ready at %s", rt_name, ssh_info["ip"])
                    else:
                        logger.warning("Pool VM %s started but no IP found", rt_name)
                else:
                    logger.warning("Pool VM %s failed to start: %s", rt_name, result["stderr"])
        finally:
            self._warm_lock.release()

    def acquire(self) -> _PoolEntry | None:
        """Try to acquire a VM from the pool (non-blocking).

        Returns a _PoolEntry if one is available, or None if the pool is empty.
        """
        with self._lock:
            if self._pool:
                entry = self._pool.pop(0)
                # Verify VM is still running
                status = self.cli.status(entry.runtime_name)
                if not status["success"] or "running" not in status.get("stdout", ""):
                    logger.warning("Pool VM %s is not running, discarding", entry.runtime_name)
                    return None
                return entry
        return None

    @property
    def available(self) -> int:
        """Number of VMs currently in the pool."""
        with self._lock:
            return len(self._pool)


# ---------------------------------------------------------------------------
# ADPSSHSandbox — implements all 8 Sandbox ABC methods via SSH
# ---------------------------------------------------------------------------


class ADPSSHSandbox(Sandbox):
    """Deer-flow Sandbox backed by an ADP-OS VM via SSH.

    All eight abstract methods are implemented using SSH commands executed
    inside the VM.  This gives deer-flow agents full in-VM code execution,
    file I/O, and search capabilities.
    """

    def __init__(
        self,
        sandbox_id: str,
        ssh_conn: SSHConnection,
        runtime_name: str = "",
    ) -> None:
        super().__init__(sandbox_id)
        self.ssh = ssh_conn
        self.runtime_name = runtime_name or sandbox_id

    # ------------------------------------------------------------------
    # execute_command
    # ------------------------------------------------------------------

    def execute_command(self, command: str) -> str:
        """Execute a bash command inside the sandbox VM.

        Returns combined stdout + stderr.
        """
        return self.ssh.exec_command_output(command)

    # ------------------------------------------------------------------
    # read_file
    # ------------------------------------------------------------------

    def read_file(self, path: str) -> str:
        """Read a text file from the sandbox VM."""
        # Use cat with stderr redirect so errors don't get mixed with content
        escaped = shlex_quote(path)
        stdout, stderr, exit_code = self.ssh.exec_command(f"cat -- {escaped} 2>&1")
        if exit_code != 0 and not stdout:
            raise OSError(f"Cannot read file {path}: {stderr}")
        return stdout

    # ------------------------------------------------------------------
    # download_file
    # ------------------------------------------------------------------

    def download_file(self, path: str) -> bytes:
        """Download a file's binary content via base64 over SSH."""
        escaped = shlex_quote(path)
        stdout, stderr, exit_code = self.ssh.exec_command(
            f"base64 -- {escaped} 2>/dev/null"
        )
        if exit_code != 0:
            raise OSError(f"Cannot download file {path}: {stderr}")
        # Strip whitespace (newlines from base64 output)
        b64_text = stdout.replace("\n", "").replace("\r", "").strip()
        if not b64_text:
            return b""
        try:
            return base64.b64decode(b64_text)
        except Exception as exc:
            raise OSError(f"Failed to decode base64 for {path}: {exc}") from exc

    # ------------------------------------------------------------------
    # list_dir
    # ------------------------------------------------------------------

    def list_dir(self, path: str, max_depth: int = 2) -> list[str]:
        """List directory contents using ``find``.

        Uses a depth-limited ``find -maxdepth`` for efficient traversal.
        Falls back to ``ls -R`` if find isn't available.
        """
        escaped = shlex_quote(path)
        # Use find for depth-limited listing
        cmd = (
            f"find {escaped} -maxdepth {max_depth} "
            f"-not -path '*/\\.*' 2>/dev/null | sort"
        )
        stdout, stderr, exit_code = self.ssh.exec_command(cmd)
        if exit_code != 0 and not stdout:
            # Fallback: ls -R
            cmd2 = f"ls -R {escaped} 2>/dev/null"
            stdout, stderr, exit_code = self.ssh.exec_command(cmd2)
        lines = [ln.strip() for ln in stdout.split("\n") if ln.strip()]
        return lines

    # ------------------------------------------------------------------
    # write_file
    # ------------------------------------------------------------------

    def write_file(self, path: str, content: str, append: bool = False) -> None:
        """Write (or append) text content to a file in the sandbox VM.

        Uses base64-encoded content piped to base64 -d > file to handle
        special characters safely.
        """
        encoded = base64.b64encode(content.encode("utf-8")).decode("ascii")
        escaped = shlex_quote(path)
        redirect = ">>" if append else ">"
        cmd = f"echo {shlex_quote(encoded)} | base64 -d {redirect} {escaped}"
        stdout, stderr, exit_code = self.ssh.exec_command(cmd)
        if exit_code != 0:
            raise OSError(f"Cannot write file {path}: {stderr}")

    # ------------------------------------------------------------------
    # glob
    # ------------------------------------------------------------------

    def glob(
        self,
        path: str,
        pattern: str,
        *,
        include_dirs: bool = False,
        max_results: int = 200,
    ) -> tuple[list[str], bool]:
        """Find paths matching *pattern* under *path* using ``find -path``.

        Returns:
            (matches, truncated) — truncated=True when *max_results* is exceeded.
        """
        escaped = shlex_quote(path)
        # Convert glob pattern to find -path pattern
        find_pattern = pattern
        if not pattern.startswith("*"):
            find_pattern = f"*/{pattern}"
        type_flag = "" if include_dirs else "-type f"
        cmd = (
            f"find {escaped} -path '*/{shlex_quote(find_pattern)}' "
            f"{type_flag} 2>/dev/null | head -n {max_results + 1}"
        )
        stdout, _stderr, _exit = self.ssh.exec_command(cmd)
        lines = [ln.strip() for ln in stdout.split("\n") if ln.strip()]
        truncated = len(lines) > max_results
        return lines[:max_results], truncated

    # ------------------------------------------------------------------
    # grep
    # ------------------------------------------------------------------

    def grep(
        self,
        path: str,
        pattern: str,
        *,
        glob: str | None = None,
        literal: bool = False,
        case_sensitive: bool = False,
        max_results: int = 100,
    ) -> tuple[list[GrepMatch], bool]:
        """Search for *pattern* inside text files under *path*.

        Uses ``grep -rn`` with appropriate flags.  When *literal* is True,
        passes ``-F`` for fixed-string matching.
        """
        escaped = shlex_quote(path)
        grep_args = ["-rn"]  # recursive + line numbers
        if not case_sensitive:
            grep_args.append("-i")
        if literal:
            grep_args.append("-F")
        pattern_esc = shlex_quote(pattern)
        glob_clause = ""
        if glob:
            glob_esc = shlex_quote(glob)
            glob_clause = f"--include='{glob_esc}'"

        cmd = (
            f"grep {' '.join(grep_args)} {glob_clause} "
            f"-m {max_results + 1} -e {pattern_esc} {escaped} 2>/dev/null"
        )
        stdout, _stderr, _exit = self.ssh.exec_command(cmd)
        lines = [ln.strip() for ln in stdout.split("\n") if ln.strip()]

        matches: list[GrepMatch] = []
        for line in lines[:max_results]:
            # grep -rn output: "filepath:lineno:content"
            parts = line.split(":", 2)
            if len(parts) >= 3:
                matches.append(GrepMatch(
                    path=parts[0],
                    line_number=int(parts[1]),
                    line=parts[2],
                ))
            elif len(parts) == 2:
                # Line with colon in content
                try:
                    lineno = int(parts[1])
                    matches.append(GrepMatch(path=parts[0], line_number=lineno, line=""))
                except ValueError:
                    matches.append(GrepMatch(path=parts[0], line_number=0, line=parts[1] if len(parts) > 1 else ""))

        truncated = len(lines) > max_results
        return matches, truncated

    # ------------------------------------------------------------------
    # update_file
    # ------------------------------------------------------------------

    def update_file(self, path: str, content: bytes) -> None:
        """Overwrite a file with binary content via base64."""
        encoded = base64.b64encode(content).decode("ascii")
        escaped = shlex_quote(path)
        cmd = f"echo {shlex_quote(encoded)} | base64 -d > {escaped}"
        stdout, stderr, exit_code = self.ssh.exec_command(cmd)
        if exit_code != 0:
            raise OSError(f"Cannot update file {path}: {stderr}")

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def close(self) -> None:
        """Close the SSH connection."""
        self.ssh.close()

    def __repr__(self) -> str:
        return f"ADPSSHSandbox({self.runtime_name} @ {self.ssh.host})"


# ---------------------------------------------------------------------------
# DeerFlowADPSandboxProvider — the main adapter class
# ---------------------------------------------------------------------------


class DeerFlowADPSandboxProvider(SandboxProvider):
    """Deer-flow SandboxProvider backed by ADP-OS VMs.

    Lifecycle:
        - acquire(thread_id) → starts (or pools) a VM → returns sandbox_id
        - get(sandbox_id)    → returns an ADPSSHSandbox handle
        - release(sandbox_id) → stops or destroys the VM

    Setup::

        provider = DeerFlowADPSandboxProvider(
            adp_home="/path/to/ai-dev-platform",
            pool_size=2,                    # pre-warm 2 VMs
            ssh_user="adp",
            ssh_password="adp",
        )
        provider.warm_pool()                # optional: pre-warm in background
    """

    # Default VM configuration for sandbox runtimes
    DEFAULT_VM_CONFIG: dict = {
        "cpu": 2,
        "memory": 4096,   # 4 GiB
        "disk": 40,        # 40 GiB
        "os": "ubuntu-26.04",
    }

    def __init__(
        self,
        adp_home: str | Path,
        *,
        pool_size: int = DEFAULT_POOL_SIZE,
        ssh_user: str = "adp",
        ssh_password: str = "adp",
        ssh_key: str | None = None,
        registry_path: str | Path | None = None,
        warm_on_init: bool = False,
    ) -> None:
        """
        Args:
            adp_home: Path to ADP-OS installation root.
            pool_size: Number of VMs to pre-warm (0 = disabled).
            ssh_user: SSH username for ADP-OS VMs.
            ssh_password: SSH password for ADP-OS VMs.
            ssh_key: Path to SSH private key (optional; uses password auth if None).
            registry_path: Path to thread→runtime registry JSON file.
            warm_on_init: If True, start warming the pool immediately.
        """
        self.adp_home = Path(adp_home).resolve()
        self.cli = ADPCLI(self.adp_home, ssh_user=ssh_user, ssh_password=ssh_password)
        self.registry = ThreadRuntimeRegistry(registry_path)
        self.pool = VMPool(self.cli, self.registry, pool_size=pool_size)
        self.ssh_user = ssh_user
        self.ssh_password = ssh_password
        self.ssh_key = ssh_key
        self._sandboxes: dict[str, ADPSSHSandbox] = {}
        self._lock = threading.Lock()

        if warm_on_init:
            self.warm_pool()

    # ------------------------------------------------------------------
    # Pooling
    # ------------------------------------------------------------------

    def warm_pool(self) -> None:
        """Start pre-warming the VM pool in a background thread."""
        t = threading.Thread(target=self.pool.warm, daemon=True, name="adp-pool-warm")
        t.start()

    @property
    def pool_available(self) -> int:
        """Number of VMs currently available in the pool."""
        return self.pool.available

    # ------------------------------------------------------------------
    # SandboxProvider interface
    # ------------------------------------------------------------------

    def acquire(self, thread_id: str | None = None) -> str:
        """Acquire an ADP-OS VM sandbox for *thread_id*.

        1. Check VM pool for a pre-warmed VM
        2. If pool empty: map thread_id → runtime, start the VM
        3. Wait for SSH to become available
        4. Record mapping in registry
        5. Return sandbox_id (the runtime name)

        The returned sandbox_id can be passed to get() and release().
        """
        with self._lock:
            # 1. Try pool first
            entry = self.pool.acquire()
            if entry is not None:
                runtime = entry.runtime_name
                sandbox_id = runtime
                logger.info("Acquired pooled VM: %s", sandbox_id)
                # Record mapping for this thread
                if thread_id:
                    self.registry.set(thread_id, runtime)
                return sandbox_id

            # 2. Map thread_id → runtime
            runtime = self.registry.get(thread_id)
            sandbox_id = runtime

            # 3. Check if runtime is already running
            status = self.cli.status(runtime)
            if not status["success"]:
                # 4. Start the VM
                logger.info("Starting VM: %s (thread_id=%s)", runtime, thread_id)
                result = self.cli.up(runtime)
                if not result["success"]:
                    raise RuntimeError(
                        f"Failed to start VM '{runtime}': {result['stderr']}"
                    )

            # 5. Record mapping
            if thread_id:
                self.registry.set(thread_id, runtime)

            # 6. Wait for SSH availability (up to 60s for warm boot, more for cold)
            self._wait_for_ssh(runtime, timeout=120)

            logger.info("Sandbox acquired: %s (thread_id=%s)", sandbox_id, thread_id)
            return sandbox_id

    def get(self, sandbox_id: str) -> Sandbox | None:
        """Return an ADPSSHSandbox handle for *sandbox_id*.

        Creates the SSH connection on first call and caches it.  Returns the
        same handle on subsequent calls.
        """
        with self._lock:
            if sandbox_id in self._sandboxes:
                return self._sandboxes[sandbox_id]

            # Get SSH info
            ssh_info = self.cli.get_runtime_ssh_info(sandbox_id)
            ip = ssh_info.get("ip")
            if not ip:
                # Try to get IP from adp status
                status = self.cli.status(sandbox_id)
                if status["success"]:
                    ip = self._extract_ip(status["stdout"], sandbox_id)
            if not ip:
                raise RuntimeError(
                    f"Cannot determine IP for runtime '{sandbox_id}'. "
                    f"Is the VM running?"
                )

            # Create SSH connection
            ssh_conn = SSHConnection(
                host=ip,
                port=ssh_info.get("port", 22),
                username=ssh_info.get("user", self.ssh_user),
                password=ssh_info.get("password", self.ssh_password),
                key_filename=self.ssh_key,
            )

            sandbox = ADPSSHSandbox(sandbox_id, ssh_conn, runtime_name=sandbox_id)
            self._sandboxes[sandbox_id] = sandbox
            return sandbox

    def release(self, sandbox_id: str) -> None:
        """Release (stop) a sandbox VM.

        Closes the SSH connection and stops the VM.  Does NOT destroy the VM
        by default — use ``force_destroy=True`` variant if needed.
        """
        with self._lock:
            # Close SSH handle
            sb = self._sandboxes.pop(sandbox_id, None)
            if sb is not None:
                sb.close()

            # Stop the VM
            logger.info("Stopping VM: %s", sandbox_id)
            self.cli.stop(sandbox_id)

            # Clean up registry entries pointing to this runtime
            self.registry.load()
            to_remove = [
                tid for tid, rt in self.registry._map.items()
                if rt == sandbox_id
            ]
            for tid in to_remove:
                self.registry.remove(tid)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _wait_for_ssh(self, runtime: str, timeout: float = 120.0) -> None:
        """Poll adp status until the VM reports reachable SSH."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            result = self.cli.status(runtime)
            if result["success"] and "reachable" in result.get("stdout", ""):
                return
            time.sleep(2)
        raise TimeoutError(
            f"VM '{runtime}' did not become SSH-reachable within {timeout}s"
        )

    @staticmethod
    def _extract_ip(status_output: str, runtime: str) -> str | None:
        """Extract IP address from adp status output for *runtime*."""
        for line in status_output.split("\n"):
            if runtime.lower() in line.lower():
                # Match IPv4 pattern
                m = re.search(r"\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b", line)
                if m:
                    return m.group(1)
        return None

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def shutdown(self) -> None:
        """Release all sandboxes and clean up."""
        with self._lock:
            for sid in list(self._sandboxes.keys()):
                try:
                    self.release(sid)
                except Exception as exc:
                    logger.warning("Error releasing %s: %s", sid, exc)

    def __repr__(self) -> str:
        return (
            f"DeerFlowADPSandboxProvider("
            f"adp_home={self.adp_home}, "
            f"pool_available={self.pool_available})"
        )


# ---------------------------------------------------------------------------
# shlex_quote shim (Python stdlib, re-exported for clarity)
# ---------------------------------------------------------------------------

from shlex import quote as shlex_quote  # noqa: E402
