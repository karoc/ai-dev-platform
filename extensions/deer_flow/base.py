"""Shared deer-flow sandbox interface types for the ADP-OS adapter."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class GrepMatch:
    """A single grep match result, compatible with deer-flow's type."""

    path: str
    line_number: int
    line: str

    def __repr__(self) -> str:
        return f"GrepMatch({self.path}:{self.line_number})"


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
