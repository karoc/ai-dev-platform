"""Thread-runtime registry and VM pool helpers for the deer-flow adapter."""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .cli import ADPCLI


logger = logging.getLogger("deerflow.adp.sandbox")


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



# Default pool size. Set to 0 to disable pooling.
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
