"""
Deer-Flow ADP-OS SandboxProvider Adapter

Implements deer-flow's SandboxProvider and Sandbox abstract interfaces using
ADP-OS VMs as the sandbox backend. VM lifecycle is managed via the ADP-OS CLI;
in-VM operations use direct SSH.

This module remains the public compatibility entrypoint. Helper classes live in
adjacent modules and are re-exported here so existing imports and test patch
paths continue to work.
"""

from __future__ import annotations

import logging
import re
import threading
import time
from pathlib import Path
from shlex import quote as shlex_quote

from .base import GrepMatch, Sandbox, SandboxProvider
from .cli import ADPCLI
from .registry import DEFAULT_POOL_SIZE, ThreadRuntimeRegistry, VMPool, _PoolEntry
from .sandbox import ADPSSHSandbox
from .ssh import SSHConnection


logger = logging.getLogger("deerflow.adp.sandbox")


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
                # Try to get IP from adpos status
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
        """Poll adpos status until the VM reports reachable SSH."""
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
        """Extract IP address from adpos status output for *runtime*."""
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



__all__ = [
    "ADPCLI",
    "ADPSSHSandbox",
    "DEFAULT_POOL_SIZE",
    "DeerFlowADPSandboxProvider",
    "GrepMatch",
    "Sandbox",
    "SandboxProvider",
    "SSHConnection",
    "ThreadRuntimeRegistry",
    "VMPool",
    "_PoolEntry",
    "shlex_quote",
]
