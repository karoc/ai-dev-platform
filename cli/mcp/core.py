"""Core helpers for the ADP-OS MCP server."""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

IS_WINDOWS = sys.platform == "win32"

# ---------------------------------------------------------------------------
# ADP-OS path resolution
# ---------------------------------------------------------------------------

def _resolve_adp_home() -> Path:
    """Resolve the ADP-OS installation directory."""
    # 1. Explicit env var
    env = os.environ.get("ADP_HOME")
    if env:
        return Path(env)

    # 2. Relative to this script: ../../ from cli/mcp/server.py -> project root
    script_dir = Path(__file__).resolve().parent  # cli/mcp/
    candidate = script_dir.parent.parent           # project root
    cli_entry = candidate / "cli" / "adp.ps1"
    if cli_entry.exists():
        return candidate

    # 3. Platform-specific fallback paths
    if IS_WINDOWS:
        # Windows native: check well-known installation paths
        for p in [
            Path("D:/Dev/ai-dev-platform"),
            Path.home() / "ai-dev-platform",
        ]:
            if (p / "cli" / "adp.ps1").exists():
                return p
    else:
        # WSL/Linux: check common WSL mount paths
        for p in [
            Path("/mnt/d/Dev/ai-dev-platform"),
            Path("/mnt/c/Users").glob("*/dev/adp-os"),
        ]:
            if isinstance(p, Path):
                check = p / "cli" / "adp.ps1"
                if check.exists():
                    return p

    raise FileNotFoundError(
        "Cannot locate ADP-OS installation. Set ADP_HOME environment variable "
        "or run this script from within an ADP-OS checkout."
    )


def _resolve_adp_home_win() -> str:
    """Resolve ADP-OS home as a Windows path for pwsh.exe invocation."""
    adp_home_win = os.environ.get("ADP_HOME_WIN")
    if adp_home_win:
        return adp_home_win

    adp_home = _resolve_adp_home()

    # On Windows, ADP_HOME is already a native Windows path — no conversion needed
    if IS_WINDOWS:
        return str(adp_home)

    # On WSL/Linux, convert WSL path to Windows path via wslpath
    try:
        result = subprocess.run(
            ["wslpath", "-w", str(adp_home)],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass

    raise RuntimeError(
        f"Cannot resolve Windows path for {adp_home}. "
        "Set ADP_HOME_WIN environment variable."
    )


# ---------------------------------------------------------------------------
# Path normalization and conversion
# ---------------------------------------------------------------------------

def _normalize_windows_path(path: Optional[str], must_exist: bool = False) -> Optional[str]:
    """Normalize a path for use with Windows pwsh.exe, converting from WSL if needed.

    Handles:
      - Windows native paths: C:\\..., D:/... (both slash styles) → returned as-is
      - WSL paths: /mnt/c/... → C:\\... (via wslpath)
      - Linux paths: /home/... → kept as-is on native Linux, converted on WSL

    When running on WSL (not IS_WINDOWS), WSL-style paths are converted to their
    Windows equivalent so pwsh.exe can access them. On native Windows, paths
    pass through unchanged.

    Args:
        path: Any path string (Windows, WSL, or Linux style)
        must_exist: If True, raises FileNotFoundError when path doesn't exist

    Returns:
        Normalized path string suitable for pwsh.exe invocation
    """
    if not path:
        return path

    normalized = path.replace("\\", "/")

    # On native Windows, paths are already in Windows format — just validate
    if IS_WINDOWS:
        if must_exist and not Path(normalized).exists():
            raise FileNotFoundError(f"Path does not exist: {path}")
        return normalized

    # On WSL/Linux: convert WSL paths to Windows paths for pwsh.exe
    # WSL mount paths (/mnt/c/...) need conversion; regular Linux paths may too
    if normalized.startswith("/mnt/"):
        # WSL mount path → Windows path via wslpath
        try:
            result = subprocess.run(
                ["wslpath", "-w", normalized],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0:
                win_path = result.stdout.strip()
                if must_exist:
                    # Validate the Windows path exists via wslpath -u round-trip check
                    check = subprocess.run(
                        ["wslpath", "-u", win_path],
                        capture_output=True, text=True, timeout=5,
                    )
                    if check.returncode != 0:
                        raise FileNotFoundError(
                            f"Path does not exist (wslpath round-trip failed): {path}"
                        )
                return win_path
        except FileNotFoundError:
            raise
        except Exception:
            pass
        # Fall through: return as-is if conversion fails
        return normalized

    # Non-mount path on WSL (e.g., /home/...)
    if must_exist and not Path(normalized).exists():
        raise FileNotFoundError(f"Path does not exist: {path}")

    return normalized


def _wsl_to_win(path: str) -> str:
    """Convert a WSL path to Windows path via wslpath.

    Shortcut for _normalize_windows_path when you know it's a WSL path.
    On native Windows, returns the path unchanged.
    """
    if IS_WINDOWS:
        return path.replace("\\", "/")

    try:
        result = subprocess.run(
            ["wslpath", "-w", path],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return path


def _win_to_wsl(path: str) -> str:
    """Convert a Windows path to WSL path via wslpath.

    On native Windows, returns the path unchanged.
    """
    if IS_WINDOWS:
        return path.replace("\\", "/")

    try:
        result = subprocess.run(
            ["wslpath", "-u", path],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return path

# ---------------------------------------------------------------------------
# SSH execution infrastructure
# ---------------------------------------------------------------------------

# Well-known SSH options shared across all in-VM operations
_SSH_BASE_OPTS = [
    "ssh",
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=10",
    "-o", "BatchMode=yes",
    "-o", "LogLevel=ERROR",
    "-o", "ServerAliveInterval=30",
]


def _get_runtime_ip(runtime: str) -> str:
    """Resolve a runtime name to its VM IP address via adpos status.

    Returns the IP address string, or raises RuntimeError if the runtime
    is not found or not running.
    """
    result = _run_adp(["status", runtime])
    if not result["success"]:
        raise RuntimeError(
            f"Cannot resolve runtime '{runtime}': "
            f"adpos status failed (exit {result['exit_code']}): {result['stderr']}"
        )

    parsed = _parse_status(result["stdout"])
    runtimes = parsed.get("runtimes", [])

    for rt in runtimes:
        if rt.get("name") == runtime and rt.get("status", "").lower() == "running":
            ip = rt.get("ip")
            if ip and ip != "--":
                return ip
            raise RuntimeError(
                f"Runtime '{runtime}' is running but has no IP address. "
                f"Check VM network configuration."
            )

    # Runtime not found or not running
    if runtimes:
        names = [r.get("name", "?") for r in runtimes]
        raise RuntimeError(
            f"Runtime '{runtime}' is not running. "
            f"Found runtimes: {', '.join(names)}. "
            f"Start it with adp_up(runtime='{runtime}', plan_only=False)."
        )
    raise RuntimeError(
        f"Runtime '{runtime}' not found. Available runtimes: frontend, backend, agent."
    )


def _sanitize_path(path: str) -> str:
    """Validate a path for safe use in SSH commands.

    Rejects paths containing '..' segments (path traversal) and null bytes.
    Returns the path unchanged if safe.
    """
    if not path:
        raise ValueError("Path must not be empty")
    if "\x00" in path:
        raise ValueError("Path contains null byte")
    # Split on both / and \ to catch Windows-style traversal too
    segments = path.replace("\\", "/").split("/")
    for seg in segments:
        if seg == "..":
            raise ValueError(
                f"Path traversal detected in '{path}': '..' segments are not allowed. "
                f"Use absolute paths inside the VM."
            )
    return path


def _ssh_exec(runtime: str, command: str, timeout: int = 120) -> dict:
    """Execute a command inside a VM via SSH.

    Args:
        runtime: Runtime name (frontend, backend, agent)
        command: Shell command to execute
        timeout: Command timeout in seconds

    Returns:
        dict with keys: stdout, stderr, exit_code, success
    """
    ip = _get_runtime_ip(runtime)
    ssh_cmd = _SSH_BASE_OPTS + [f"adp@{ip}", command]

    try:
        proc = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
        return {
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "exit_code": proc.returncode,
            "success": proc.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {
            "stdout": "",
            "stderr": f"SSH command timed out after {timeout}s",
            "exit_code": -1,
            "success": False,
        }
    except Exception as e:
        return {
            "stdout": "",
            "stderr": f"SSH error: {e}",
            "exit_code": -1,
            "success": False,
        }


def _ssh_result(runtime: str, result: dict, parsed: Optional[dict] = None) -> dict:
    """Build a structured result for in-VM operations."""
    base: dict[str, Any] = {
        "_text": _format_output(result),
        "_exit_code": result["exit_code"],
        "_success": result["success"],
        "runtime": runtime,
    }
    if parsed:
        base.update(parsed)
    return base

# ---------------------------------------------------------------------------
# ADP-OS command invocation
# ---------------------------------------------------------------------------

def _find_pwsh() -> str:
    """Find PowerShell 7+ executable."""
    pwsh = shutil.which("pwsh.exe") or shutil.which("pwsh")
    if pwsh:
        return pwsh

    # Platform-specific fallback locations
    if IS_WINDOWS:
        for loc in [
            Path("C:/Program Files/PowerShell/7/pwsh.exe"),
            Path.home() / "AppData/Local/Programs/PowerShell/7/pwsh.exe",
            Path.home() / "AppData/Local/Microsoft/WindowsApps/pwsh.exe",
        ]:
            if loc.exists():
                return str(loc)

    raise FileNotFoundError("PowerShell 7+ (pwsh) not found in PATH")


def _run_adp(
    args: list[str],
    timeout: int = 120,
    *,
    resolve_adp_home_win: Any = None,
    find_pwsh: Any = None,
    resolve_adp_home: Any = None,
) -> dict:
    """Execute an ADP-OS command and return structured result.

    Returns:
        dict with keys: stdout, stderr, exit_code, success
    """
    resolve_adp_home_win = resolve_adp_home_win or _resolve_adp_home_win
    find_pwsh = find_pwsh or _find_pwsh
    resolve_adp_home = resolve_adp_home or _resolve_adp_home

    adp_home_win = resolve_adp_home_win()
    cli_path_win = adp_home_win.replace("/", "\\") + "\\cli\\adp.ps1"
    pwsh = find_pwsh()
    adp_home = resolve_adp_home()

    cmd = [
        pwsh, "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", cli_path_win
    ] + args

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(adp_home),
            encoding="utf-8",
            errors="replace",
        )
        return {
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "exit_code": result.returncode,
            "success": result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {
            "stdout": "",
            "stderr": f"Command timed out after {timeout}s",
            "exit_code": -1,
            "success": False,
        }
    except Exception as e:
        return {
            "stdout": "",
            "stderr": str(e),
            "exit_code": -1,
            "success": False,
        }


def _format_output(result: dict) -> str:
    """Format ADP-OS command output for MCP response."""
    parts = []
    if result["stdout"]:
        parts.append(result["stdout"])
    if result["stderr"]:
        parts.append(f"[stderr]\n{result['stderr']}")
    if not result["success"]:
        parts.append(f"[exit code: {result['exit_code']}]")
    return "\n".join(parts) if parts else "(no output)"


# ---------------------------------------------------------------------------
# Structured output parsing
# ---------------------------------------------------------------------------

def _structured_result(result: dict, parsed: Optional[dict] = None) -> dict:
    """Build a structured result dict from raw CLI output.

    Always includes:
      - _text: formatted human-readable output
      - _exit_code: process exit code
      - _success: whether the command succeeded

    Additional parsed fields from command-specific parsers are merged in.
    """
    base: dict[str, Any] = {
        "_text": _format_output(result),
        "_exit_code": result["exit_code"],
        "_success": result["success"],
    }
    if parsed:
        base.update(parsed)
    return base


def _parse_status(stdout: str) -> dict:
    """Parse 'adpos status' output into structured fields."""
    runtimes: list[dict] = []
    # Match runtime entries like: "agent      running      192.168.242.135  reachable  healthy"
    # The status output format varies; try common patterns
    for line in stdout.split("\n"):
        line = line.strip()
        if not line or line.startswith("===") or line.startswith("---"):
            continue
        # Match lines that start with a known runtime name
        for rt_name in ["frontend", "backend", "agent"]:
            if line.lower().startswith(rt_name):
                parts = line.split()
                rt = {"name": rt_name}
                if len(parts) > 1:
                    rt["status"] = parts[1]
                if len(parts) > 2:
                    rt["ip"] = parts[2]
                if len(parts) > 3:
                    rt["ssh"] = parts[3]
                if len(parts) > 4:
                    rt["sync"] = parts[4]
                runtimes.append(rt)
                break

    # Count running/stopped
    running_count = sum(1 for r in runtimes if r.get("status", "").lower() == "running")
    parsed: dict[str, Any] = {
        "runtimes": runtimes,
        "runtime_count": len(runtimes),
        "running_count": running_count,
    }
    return parsed


def _parse_doctor(stdout: str) -> dict:
    """Parse 'adpos doctor' output into structured fields."""
    # Extract OK count and issue count
    ok_match = re.search(r"(\d+)\s*OK", stdout)
    issue_match = re.search(r"(\d+)\s*(?:issue|问题)", stdout, re.IGNORECASE)
    info_match = re.search(r"(\d+)\s*info", stdout, re.IGNORECASE)

    issues: list[dict] = []
    # Parse issue lines — they typically follow a pattern like:
    #   [ISSUE] description or ! description
    for line in stdout.split("\n"):
        stripped = line.strip()
        if re.match(r"^[!⚠].+", stripped) or "[ISSUE]" in stripped:
            # Clean up the issue text
            text = re.sub(r"^[!⚠]\s*", "", stripped)
            text = re.sub(r"\[ISSUE\]\s*", "", text)
            if text:
                issues.append({"description": text})

    parsed: dict[str, Any] = {
        "ok_count": int(ok_match.group(1)) if ok_match else 0,
        "issue_count": int(issue_match.group(1)) if issue_match else 0,
        "info_count": int(info_match.group(1)) if info_match else 0,
        "issues": issues,
        "healthy": not issues,
    }
    return parsed


def _parse_workspace_show(stdout: str) -> dict:
    """Parse 'adpos workspace show' output into structured fields."""
    projects: list[dict] = []
    current_project: Optional[dict] = None

    for line in stdout.split("\n"):
        stripped = line.strip()
        # Try: "- project-name (runtime: runtime-name)"
        proj_match = re.match(r"^[-*]\s*(\S+)\s*\(runtime:\s*(.+?)\)", stripped)
        # Try: "- project-name: runtime-name"
        if not proj_match:
            proj_match = re.match(r"^[-*]\s*(\S+)\s*:\s*(.+?)$", stripped)
        if proj_match:
            if current_project:
                projects.append(current_project)
            current_project = {"name": proj_match.group(1), "runtime": proj_match.group(2).strip()}
            continue
        # Detect runtime mapping on separate line
        rt_match = re.match(r"(?:runtime|运行时)[:\s]+(\S+)", stripped, re.IGNORECASE)
        if rt_match and current_project and "runtime" not in current_project:
            current_project["runtime"] = rt_match.group(1)

    if current_project:
        projects.append(current_project)

    parsed: dict[str, Any] = {
        "projects": projects,
        "project_count": len(projects),
    }
    return parsed


def _parse_sync_status(stdout: str) -> dict:
    """Parse 'adpos sync status' output into structured fields."""
    sessions: list[dict] = []

    for line in stdout.split("\n"):
        stripped = line.strip()
        for rt_name in ["frontend", "backend", "agent"]:
            if rt_name in stripped.lower():
                # Extract status keywords
                status = "unknown"
                for kw in ["healthy", "halted", "connecting", "stale", "paused",
                           "watching", "waiting", "disconnected"]:
                    if kw in stripped.lower():
                        status = kw
                        break
                sessions.append({
                    "runtime": rt_name,
                    "status": status,
                })
                break

    healthy_count = sum(1 for s in sessions if s["status"] == "healthy")
    parsed: dict[str, Any] = {
        "sessions": sessions,
        "session_count": len(sessions),
        "healthy_count": healthy_count,
    }
    return parsed


def _parse_capabilities(stdout: str) -> dict:
    """Parse 'adpos capabilities' output into structured fields."""
    supported: list[str] = []
    planned: list[str] = []
    exploratory: list[str] = []
    current_section = ""

    for line in stdout.split("\n"):
        stripped = line.strip()
        if "supported" in stripped.lower() or "支持" in stripped:
            current_section = "supported"
            continue
        if "planned" in stripped.lower() or "计划" in stripped or "规划" in stripped:
            current_section = "planned"
            continue
        if "explor" in stripped.lower() or "探索" in stripped:
            current_section = "exploratory"
            continue
        # Capture capability names (indented items or bullet points)
        cap_match = re.match(r"^\s*[-•*]\s*(.+)$", stripped)
        if cap_match and current_section:
            name = cap_match.group(1).strip()
            if current_section == "supported":
                supported.append(name)
            elif current_section == "planned":
                planned.append(name)
            elif current_section == "exploratory":
                exploratory.append(name)

    parsed: dict[str, Any] = {
        "supported": supported,
        "planned": planned,
        "exploratory": exploratory,
    }
    return parsed


def _load_manifest() -> dict:
    """Load the workspace manifest JSON. Tries adp-workspace.json, then
    configs/workspace.example.json, then configs/workspace.recipes.example.json.
    """
    adp_home = _resolve_adp_home()
    candidates = [
        adp_home / "adp-workspace.json",
        adp_home / "configs" / "workspace.example.json",
        adp_home / "configs" / "workspace.recipes.example.json",
    ]
    for path in candidates:
        if path.exists():
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
    return {}


def _find_runtime_for_project(project_name: str) -> Optional[str]:
    """Resolve a project name to its runtime name from the manifest."""
    manifest = _load_manifest()
    projects = manifest.get("projects", [])
    for proj in projects:
        if proj.get("name") == project_name:
            return proj.get("runtime")
    return None
