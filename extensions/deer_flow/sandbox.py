"""SSH-backed deer-flow Sandbox implementation for ADP-OS VMs."""

from __future__ import annotations

import base64
from shlex import quote as shlex_quote

from .base import GrepMatch, Sandbox
from .ssh import SSHConnection


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
