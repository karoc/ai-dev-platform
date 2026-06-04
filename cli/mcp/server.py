#!/usr/bin/env python3
"""
ADP-OS MCP Server

Exposes ADP-OS platform management as MCP tools for agent-native sandbox orchestration.

Tools:
  - adp_status: Platform and runtime health status
  - adp_doctor: Run platform diagnostics
  - adp_workspace_list: List workspace projects
  - adp_workspace_create: Create workspace directories
  - adp_workspace_open: Get workspace entry guidance
  - adp_workspace_sync: Get per-project sync guidance
  - adp_workspace_status: Workspace readiness summary

Usage:
  python cli/mcp/server.py
  # or with explicit ADP-OS path:
  ADP_HOME=D:\\Dev\\ai-dev-platform python cli/mcp/server.py
"""

import os
import sys
import subprocess
import json
import shutil
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

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

    # 3. Common WSL mount paths
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


# ---------------------------------------------------------------------------
# ADP CLI invocation
# ---------------------------------------------------------------------------

def _find_pwsh() -> str:
    """Find PowerShell 7+ executable."""
    # In WSL, use pwsh.exe
    pwsh = shutil.which("pwsh.exe") or shutil.which("pwsh")
    if pwsh:
        return pwsh
    raise FileNotFoundError("PowerShell 7+ (pwsh) not found in PATH")


def _run_adp(args: list[str], timeout: int = 60) -> dict:
    """Execute an ADP CLI command and return structured result.

    Returns:
        dict with keys: stdout, stderr, exit_code, success
    """
    adp_home = _resolve_adp_home()

    # Convert WSL path to Windows path for pwsh.exe invocation.
    # When pwsh.exe receives a WSL path, PowerShell treats it as a UNC
    # (\\wsl.localhost\...) and blocks script execution.
    # Use wslpath to convert, or resolve from the env var / known mounts.
    adp_home_win = os.environ.get("ADP_HOME_WIN")
    if not adp_home_win:
        # Try wslpath conversion
        try:
            result = subprocess.run(
                ["wslpath", "-w", str(adp_home)],
                capture_output=True, text=True, timeout=5,
            )
            if result.returncode == 0:
                adp_home_win = result.stdout.strip()
        except Exception:
            pass

    if not adp_home_win:
        raise RuntimeError(
            f"Cannot resolve Windows path for {adp_home}. "
            "Set ADP_HOME_WIN environment variable."
        )

    cli_path_win = adp_home_win.replace("/", "\\") + "\\cli\\adp.ps1"
    pwsh = _find_pwsh()

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
    """Format ADP CLI output for MCP response."""
    parts = []
    if result["stdout"]:
        parts.append(result["stdout"])
    if result["stderr"]:
        parts.append(f"[stderr]\n{result['stderr']}")
    if not result["success"]:
        parts.append(f"[exit code: {result['exit_code']}]")
    return "\n".join(parts) if parts else "(no output)"


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

mcp = FastMCP("ADP-OS")


# -- Platform tools --

@mcp.tool()
def adp_status(runtime: Optional[str] = None) -> str:
    """Get ADP-OS platform and runtime health status.

    Shows running VMs, SSH reachability, sync session health, and connection guidance.
    Without arguments, shows all runtimes. With a runtime name (e.g. 'agent'),
    shows detailed status for that runtime.

    Args:
        runtime: Optional runtime name (frontend, backend, agent) for detailed status
    """
    args = ["status"]
    if runtime:
        args.append(runtime)
    result = _run_adp(args)
    return _format_output(result)


@mcp.tool()
def adp_doctor() -> str:
    """Run ADP-OS platform diagnostics.

    Checks: configuration shape, VMware NAT, static IP, sync profiles,
    duplicate VMs, VM status, SSH reachability, Mutagen version, and sessions.
    Reports OK count, issue count, and per-issue remediation guidance.
    """
    result = _run_adp(["doctor"])
    return _format_output(result)


# -- Workspace tools --

@mcp.tool()
def adp_workspace_list() -> str:
    """List all workspace projects defined in the manifest.

    Shows project names, runtime mappings, and basic readiness.
    """
    result = _run_adp(["workspace", "show"])
    return _format_output(result)


@mcp.tool()
def adp_workspace_status() -> str:
    """Get detailed workspace readiness status.

    Reports manifest state, project paths, runtime status, sync sessions,
    snapshot recommendations, and validation command declarations.
    """
    result = _run_adp(["workspace", "status"])
    return _format_output(result)


@mcp.tool()
def adp_workspace_create(project_name: str, plan_only: bool = True) -> str:
    """Create workspace project directories.

    Creates only missing local project directories declared in the manifest.
    Does NOT clone git repos, start runtimes, start sync, open SSH,
    create snapshots, run validation, or modify existing files.

    Args:
        project_name: Project name from manifest to create directories for
        plan_only: If true (default), preview only without creating directories
    """
    args = ["workspace", "create", project_name]
    if plan_only:
        args.append("-Plan")
    result = _run_adp(args)
    return _format_output(result)


@mcp.tool()
def adp_workspace_open(project_name: str) -> str:
    """Get guidance for entering a workspace project.

    Resolves local/remote project paths, reports runtime readiness,
    sync status, sync hygiene, and devcontainer context.
    Prints copyable local/editor/SSH/sync/status commands.
    Does NOT open shells, start runtimes, start sync, or connect over SSH.

    Args:
        project_name: Project name from manifest to open
    """
    result = _run_adp(["workspace", "open", project_name])
    return _format_output(result)


@mcp.tool()
def adp_workspace_sync(project_name: str) -> str:
    """Get per-project file sync guidance.

    Maps a manifest project to its runtime-level Mutagen session,
    reports runtime readiness, sync session status, and sync hygiene.
    Prints explicit sync start/stop/status commands.
    Does NOT start or stop Mutagen, start runtimes, or connect over SSH.

    Args:
        project_name: Project name from manifest for sync guidance
    """
    result = _run_adp(["workspace", "sync", project_name])
    return _format_output(result)


@mcp.tool()
def adp_workspace_recipes() -> str:
    """List available workspace recipes.

    Shows project recipes, task recipes, milestone checkpoints,
    evaluation hooks, and evidence commands from the manifest.
    """
    result = _run_adp(["workspace", "recipes"])
    return _format_output(result)


# -- Runtime tools --

@mcp.tool()
def adp_sync_status() -> str:
    """Get Mutagen sync session status for all runtimes.

    Shows session health, endpoint connectivity, and per-runtime sync state.
    """
    result = _run_adp(["sync", "status"])
    return _format_output(result)


@mcp.tool()
def adp_sync_stop(runtime: str) -> str:
    """Stop a Mutagen sync session for a runtime.

    This is the equivalent of "closing" a workspace — it stops bidirectional
    file synchronization. The VM itself keeps running.

    Args:
        runtime: Runtime name (frontend, backend, agent)
    """
    result = _run_adp(["sync", "stop", runtime])
    return _format_output(result)


@mcp.tool()
def adp_capabilities() -> str:
    """Show ADP-OS platform capabilities and roadmap.

    Lists supported runtime carriers, host adapters, and planned expansions.
    """
    result = _run_adp(["capabilities"])
    return _format_output(result)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
