"""In-VM tool implementations for the ADP-OS MCP server."""

import base64
import shlex
from typing import Callable, Optional


def adp_exec_impl(
    runtime: str,
    command: str,
    timeout: int,
    *,
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    ssh_raw = ssh_exec(runtime, command, timeout=timeout)
    return ssh_result(runtime, ssh_raw)


def adp_file_read_impl(
    runtime: str,
    path: str,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    ssh_raw = ssh_exec(
        runtime,
        f"test -f {shlex.quote(safe_path)} && base64 {shlex.quote(safe_path)} || "
        f"(echo 'ERROR: File not found: {safe_path}' >&2 && exit 1)",
        timeout=30,
    )

    if ssh_raw["success"] and ssh_raw["stdout"]:
        try:
            content = base64.b64decode(ssh_raw["stdout"]).decode("utf-8", errors="replace")
        except Exception:
            content = ssh_raw["stdout"]
    else:
        content = ""

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "content": content,
    })


def adp_file_write_impl(
    runtime: str,
    path: str,
    content: str,
    append: bool,
    plan_only: bool,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    content_b64 = base64.b64encode(content.encode("utf-8")).decode("ascii")

    if plan_only:
        redirect = ">>" if append else ">"
        return {
            "_text": (
                f"[plan] Would write {len(content)} bytes to {path} on runtime '{runtime}'\n"
                f"  Command: echo '<base64>' | base64 -d {redirect} {safe_path}\n"
                f"  Execute: adp_file_write(runtime='{runtime}', path='{path}', "
                f"content=..., append={append}, plan_only=False)"
            ),
            "_exit_code": 0,
            "_success": True,
            "runtime": runtime,
            "path": path,
            "plan_only": True,
            "bytes_planned": len(content),
        }

    redirect = ">>" if append else ">"
    ssh_raw = ssh_exec(
        runtime,
        f"echo {shlex.quote(content_b64)} | base64 -d {redirect} {shlex.quote(safe_path)}",
        timeout=30,
    )

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "bytes_written": len(content) if ssh_raw["success"] else 0,
        "append": append,
        "plan_only": False,
    })


def adp_dir_list_impl(
    runtime: str,
    path: str,
    max_depth: int,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    ssh_raw = ssh_exec(
        runtime,
        f"find {shlex.quote(safe_path)} -maxdepth {max_depth} "
        f"-not -path '*/\\.*' 2>/dev/null | sort",
        timeout=30,
    )

    entries = []
    if ssh_raw["success"] and ssh_raw["stdout"]:
        entries = [e for e in ssh_raw["stdout"].split("\n") if e.strip()]

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "max_depth": max_depth,
        "entries": entries,
        "entry_count": len(entries),
    })


def adp_glob_impl(
    runtime: str,
    path: str,
    pattern: str,
    include_dirs: bool,
    max_results: int,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    safe_pattern = shlex.quote(pattern)

    type_filter = "" if include_dirs else "-type f"
    ssh_raw = ssh_exec(
        runtime,
        f"find {shlex.quote(safe_path)} {type_filter} "
        f"-name {safe_pattern} -not -path '*/\\.*' 2>/dev/null "
        f"| head -n {max_results + 1} | sort",
        timeout=30,
    )

    matches = []
    truncated = False
    if ssh_raw["success"] and ssh_raw["stdout"]:
        lines = [line for line in ssh_raw["stdout"].split("\n") if line.strip()]
        if len(lines) > max_results:
            truncated = True
            matches = lines[:max_results]
        else:
            matches = lines

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "pattern": pattern,
        "matches": matches,
        "match_count": len(matches),
        "truncated": truncated,
    })


def adp_grep_impl(
    runtime: str,
    path: str,
    pattern: str,
    glob_filter: Optional[str],
    literal: bool,
    case_sensitive: bool,
    max_results: int,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    safe_pattern = shlex.quote(pattern)

    grep_opts = ["-r", "-n", "-I"]
    if literal:
        grep_opts.append("-F")
    if not case_sensitive:
        grep_opts.append("-i")

    include = ""
    if glob_filter:
        safe_glob = shlex.quote(glob_filter)
        include = f"--include={safe_glob}"

    ssh_raw = ssh_exec(
        runtime,
        f"grep {' '.join(grep_opts)} {include} "
        f"{safe_pattern} {shlex.quote(safe_path)} 2>/dev/null "
        f"| head -n {max_results + 1}",
        timeout=30,
    )

    matches = []
    truncated = False
    if ssh_raw["success"] or ssh_raw["exit_code"] == 1:
        if ssh_raw["stdout"]:
            lines = [line for line in ssh_raw["stdout"].split("\n") if line.strip()]
            if len(lines) > max_results:
                truncated = True
                matches = lines[:max_results]
            else:
                matches = lines
        if ssh_raw["exit_code"] == 1 and not ssh_raw["stdout"]:
            ssh_raw["success"] = True
            ssh_raw["exit_code"] = 0

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "pattern": pattern,
        "matches": matches,
        "match_count": len(matches),
        "truncated": truncated,
    })


def adp_file_download_impl(
    runtime: str,
    path: str,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)
    ssh_raw = ssh_exec(
        runtime,
        f"test -f {shlex.quote(safe_path)} && base64 {shlex.quote(safe_path)} || "
        f"(echo 'ERROR: File not found: {safe_path}' >&2 && exit 1)",
        timeout=30,
    )

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "content_base64": ssh_raw["stdout"] if ssh_raw["success"] else "",
    })


def adp_file_upload_impl(
    runtime: str,
    path: str,
    content_base64: str,
    plan_only: bool,
    *,
    sanitize_path: Callable[[str], str],
    ssh_exec: Callable[..., dict],
    ssh_result: Callable[..., dict],
) -> dict:
    safe_path = sanitize_path(path)

    try:
        decoded = base64.b64decode(content_base64, validate=True)
        byte_count = len(decoded)
    except Exception as exc:
        return {
            "_text": f"Invalid base64 content: {exc}",
            "_exit_code": -1,
            "_success": False,
            "runtime": runtime,
            "path": path,
            "error": str(exc),
        }

    if plan_only:
        return {
            "_text": (
                f"[plan] Would upload {byte_count} bytes to {path} on runtime '{runtime}'\n"
                f"  Command: mkdir -p $(dirname {safe_path}) && "
                f"echo '<base64>' | base64 -d > {safe_path}\n"
                f"  Execute: adp_file_upload(runtime='{runtime}', path='{path}', "
                f"content_base64=..., plan_only=False)"
            ),
            "_exit_code": 0,
            "_success": True,
            "runtime": runtime,
            "path": path,
            "plan_only": True,
            "bytes_planned": byte_count,
        }

    ssh_raw = ssh_exec(
        runtime,
        f"mkdir -p $(dirname {shlex.quote(safe_path)}) && "
        f"echo {shlex.quote(content_base64)} | base64 -d > {shlex.quote(safe_path)}",
        timeout=30,
    )

    return ssh_result(runtime, ssh_raw, {
        "path": path,
        "bytes_written": byte_count if ssh_raw["success"] else 0,
        "plan_only": False,
    })
