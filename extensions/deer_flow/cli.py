"""ADP-OS CLI wrapper for the deer-flow sandbox adapter."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


class ADPCLI:
    """Minimal wrapper around the ADP-OS PowerShell CLI.

    Uses subprocess to invoke the ADP-OS PowerShell control plane with
    adpos-style arguments, the same mechanism as the ADP-OS MCP server.
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
        """Run adpos-style CLI arguments and return stdout/stderr/exit status."""
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
        """Run ``adpos status [runtime]`` and parse output."""
        args = ["status"]
        if runtime:
            args.append(runtime)
        return self._run(args, timeout=60)

    def up(self, runtime: str, plan_only: bool = False, iso_path: str | None = None) -> dict:
        """Run ``adpos up <runtime>``."""
        args = ["up", runtime]
        if plan_only:
            args.append("-Plan")
        if iso_path:
            args.append("-IsoPath")
            args.append(iso_path)
        return self._run(args, timeout=1800)  # 30 min — first boot can be long

    def stop(self, runtime: str) -> dict:
        """Run ``adpos stop <runtime>``."""
        return self._run(["stop", runtime], timeout=120)

    def down(self, runtime: str, plan_only: bool = False, force: bool = False) -> dict:
        """Run ``adpos destroy <runtime>``."""
        args = ["destroy", runtime]
        if plan_only:
            args.append("-Plan")
        if force:
            args.append("-Force")
        return self._run(args, timeout=300)

    def doctor(self) -> dict:
        """Run ``adpos doctor``."""
        return self._run(["doctor"], timeout=120)
