"""SSH execution backend for the ADP-OS deer-flow sandbox adapter."""

from __future__ import annotations

import logging
import shutil
import subprocess


logger = logging.getLogger("deerflow.adp.sandbox")


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
