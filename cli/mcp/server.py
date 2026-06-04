#!/usr/bin/env python3
"""
ADP-OS MCP Server

Exposes ADP-OS platform management as MCP tools for agent-native sandbox orchestration.

Platform tools:
  - adp_status: Platform and runtime health status
  - adp_doctor: Run platform diagnostics
  - adp_capabilities: Platform capabilities and roadmap

Workspace tools:
  - adp_workspace_list: List workspace projects
  - adp_workspace_status: Workspace readiness summary
  - adp_workspace_dashboard: Workspace dashboard with task lifecycle
  - adp_workspace_project: Single project operational lifecycle view
  - adp_workspace_create: Create workspace project directories
  - adp_workspace_open: Get workspace entry guidance
  - adp_workspace_sync: Get per-project sync guidance
  - adp_workspace_close: Close a workspace (stop sync for its runtime)
  - adp_workspace_recipes: List available workspace recipes
  - adp_workspace_report: Generate Markdown release evidence

Runtime tools:
  - adp_up: Start a runtime VM (plan-only by default)
  - adp_down: Destroy a runtime VM (plan-only by default)
  - adp_stop: Gracefully stop a runtime VM
  - adp_sync_status: Get Mutagen sync session status
  - adp_sync_stop: Stop a Mutagen sync session

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


def _resolve_adp_home_win() -> str:
    """Resolve ADP-OS home as a Windows path for pwsh.exe invocation."""
    adp_home_win = os.environ.get("ADP_HOME_WIN")
    if adp_home_win:
        return adp_home_win

    adp_home = _resolve_adp_home()
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
# ADP CLI invocation
# ---------------------------------------------------------------------------

def _find_pwsh() -> str:
    """Find PowerShell 7+ executable."""
    pwsh = shutil.which("pwsh.exe") or shutil.which("pwsh")
    if pwsh:
        return pwsh
    raise FileNotFoundError("PowerShell 7+ (pwsh) not found in PATH")


def _run_adp(args: list[str], timeout: int = 120) -> dict:
    """Execute an ADP CLI command and return structured result.

    Returns:
        dict with keys: stdout, stderr, exit_code, success
    """
    adp_home_win = _resolve_adp_home_win()
    cli_path_win = adp_home_win.replace("/", "\\") + "\\cli\\adp.ps1"
    pwsh = _find_pwsh()
    adp_home = _resolve_adp_home()

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


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

mcp = FastMCP("ADP-OS")


# ===========================================================================
# Platform tools
# ===========================================================================

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


@mcp.tool()
def adp_capabilities() -> str:
    """Show ADP-OS platform capabilities and roadmap.

    Lists supported runtime carriers, host adapters, and planned expansions.
    """
    result = _run_adp(["capabilities"])
    return _format_output(result)


# ===========================================================================
# Workspace tools
# ===========================================================================

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
def adp_workspace_dashboard() -> str:
    """Get workspace dashboard with task lifecycle overview.

    Summarizes project readiness, milestone checkpoints, evaluation hooks,
    and per-task lifecycle state across path, runtime, sync, checkpoint,
    execution, validation, review, rollback, and commit gates.
    """
    result = _run_adp(["workspace", "dashboard"])
    return _format_output(result)


@mcp.tool()
def adp_workspace_project(project_name: str) -> str:
    """Get a single project's full operational lifecycle view.

    Combines path, runtime, sync, sync hygiene, devcontainer metadata,
    project validation commands, linked tasks, snapshot gates, recorded
    validation state, commit readiness, and evidence handoff into one view.
    Non-destructive: does not start runtimes, sync, SSH, or modify files.

    Args:
        project_name: Project name from manifest to inspect
    """
    result = _run_adp(["workspace", "project", project_name])
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
def adp_workspace_close(project_name: str, plan_only: bool = True) -> str:
    """Close a workspace by stopping file sync for its runtime.

    First shows the project's current sync status, then stops the Mutagen
    sync session for the associated runtime. The VM keeps running —
    use adp_stop or adp_down to manage the VM itself.

    When plan_only=True (default), only shows what would happen without
    actually stopping sync.

    Args:
        project_name: Project name from manifest to close
        plan_only: If true (default), preview only without stopping sync
    """
    runtime = _find_runtime_for_project(project_name)
    if not runtime:
        # Fall back to workspace sync for guidance
        guidance = _run_adp(["workspace", "sync", project_name])
        return (
            f"[workspace close] Could not resolve runtime for project '{project_name}'.\n"
            f"Please use adp_sync_stop with the runtime name directly.\n\n"
            f"Project sync guidance:\n{_format_output(guidance)}"
        )

    lines = [f"[workspace close] Project '{project_name}' → runtime '{runtime}'"]

    # Show current sync status
    sync_result = _run_adp(["sync", "status"])
    lines.append(f"\nCurrent sync status:\n{_format_output(sync_result)}")

    if plan_only:
        lines.append(
            f"\n[PLAN ONLY] Would stop sync for runtime '{runtime}'.\n"
            f"To execute: adp_workspace_close(project_name='{project_name}', plan_only=False)\n"
            f"Or directly: adp_sync_stop(runtime='{runtime}')"
        )
        return "\n".join(lines)

    # Actually stop sync
    stop_result = _run_adp(["sync", "stop", runtime])
    lines.append(f"\nSync stop result:\n{_format_output(stop_result)}")
    return "\n".join(lines)


@mcp.tool()
def adp_workspace_recipes() -> str:
    """List available workspace recipes.

    Shows project recipes, task recipes, milestone checkpoints,
    evaluation hooks, and evidence commands from the manifest.
    """
    result = _run_adp(["workspace", "recipes"])
    return _format_output(result)


@mcp.tool()
def adp_workspace_report() -> str:
    """Generate workspace release evidence in Markdown format.

    Produces a comprehensive report covering governance loop, action
    decision queues, milestone review rollup, validation execution queue,
    evaluation queue, release decision policy, stale-task remediation,
    task-by-task validation, review decisions, rollback context, commit
    readiness, source-review checklist, and handoff commands.

    The Markdown output is suitable for PR descriptions, release notes,
    or maintainer handoff evidence.
    """
    result = _run_adp(["workspace", "report", "-Markdown"])
    return _format_output(result)


# ===========================================================================
# Runtime tools
# ===========================================================================

@mcp.tool()
def adp_up(
    runtime: str,
    plan_only: bool = True,
    iso_path: Optional[str] = None,
) -> str:
    """Start a runtime VM (creates it from ISO if first time).

    Defaults to plan-only mode for safety — shows what would happen
    without actually creating or starting a VM. Set plan_only=False
    to actually start the runtime.

    VM creation from ISO is a long-running operation (15-45 minutes
    for first-time Ubuntu autoinstall). The command monitors installation
    progress and reports readiness signals.

    Args:
        runtime: Runtime name to start (frontend, backend, agent)
        plan_only: If true (default), preview only without starting
        iso_path: Optional path to Ubuntu Server ISO for first-time VM creation
    """
    args = ["up", runtime]
    if plan_only:
        args.append("-Plan")
    if iso_path:
        args.append("-IsoPath")
        args.append(iso_path)
    timeout = 300 if not plan_only else 120
    result = _run_adp(args, timeout=timeout)
    return _format_output(result)


@mcp.tool()
def adp_down(
    runtime: str,
    plan_only: bool = True,
    force: bool = False,
) -> str:
    """Destroy a runtime VM completely.

    Defaults to plan-only mode for safety — shows what would be destroyed
    without actually removing anything. Set plan_only=False to actually
    destroy the VM. This is irreversible.

    Args:
        runtime: Runtime name to destroy (frontend, backend, agent)
        plan_only: If true (default), preview only without destroying
        force: Skip confirmation prompts (only applies when plan_only=False)
    """
    args = ["destroy", runtime]
    if plan_only:
        args.append("-Plan")
    if force:
        args.append("-Force")
    result = _run_adp(args)
    return _format_output(result)


@mcp.tool()
def adp_stop(runtime: str) -> str:
    """Gracefully stop a runtime VM.

    Shuts down the VM gracefully without destroying it. The VM can be
    restarted later with adp_up. Sync sessions remain intact.

    Args:
        runtime: Runtime name to stop (frontend, backend, agent)
    """
    result = _run_adp(["stop", runtime])
    return _format_output(result)


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


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run()
