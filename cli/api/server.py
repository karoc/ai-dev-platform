"""
ADP-OS REST API Server

Exposes ADP-OS platform management over REST with JWT authentication and RBAC.
Shares the same `_run_adp()` subprocess wrapper as the MCP server.

Start:
  python cli/api/server.py
  # or:
  uvicorn cli.api.server:app --host 0.0.0.0 --port 8000

Env vars:
  ADP_JWT_SECRET    — JWT signing secret (min 32 bytes; auto-generated if not set)
  ADP_API_KEY       — Bootstrap API key for initial login
  ADP_HOME / ADP_HOME_WIN — ADP-OS installation directory

OpenAPI docs:
  http://localhost:8000/docs
  http://localhost:8000/redoc
"""

import sys
import time
from pathlib import Path
from typing import Optional

# Add project root to path so we can import from cli.mcp.server
_project_root = Path(__file__).resolve().parent.parent.parent
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))

from fastapi import FastAPI, Depends, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware


# Import our modules
from .auth import (
    validate_api_key,
    create_access_token,
    create_refresh_token,
    revoke_token,
    consume_refresh_token,
    list_tokens,
    revoke_token_by_sub,
    ACCESS_TOKEN_EXPIRE_SECONDS,
    _revoked_jtis,
    _issued_tokens,
)
from .models import (
    LoginRequest,
    LoginResponse,
    RefreshRequest,
    RefreshResponse,
    RevokeResponse,
    TokenInfo,
    ErrorResponse,
    ADPResult,
    AdminTokenCreate,
    AdminTokenList,
    AdminHealthResponse,
)
from .dependencies import (
    get_current_user,
    require_scope,
    require_admin,
)

# Reuse the existing MCP server's _run_adp() and output formatters
# This is the same subprocess wrapper that the MCP server uses
from cli.mcp.server import _run_adp, _format_output, _structured_result


# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI(
    title="ADP-OS REST API",
    description=(
        "REST API for ADP-OS — a reproducible local development platform "
        "for AI-assisted software engineering. Manage VMs, workspaces, "
        "and sync sessions programmatically."
    ),
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# CORS: allow all origins for self-hosted usage
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Server start time for health check
_start_time = time.time()


# ---------------------------------------------------------------------------
# Default role scopes
# ---------------------------------------------------------------------------

DEFAULT_SCOPES = {
    "admin": ["admin:*"],
    "user": [
        "platform:read",
        "workspace:read",
        "workspace:write",
        "runtime:read",
        "runtime:write",
    ],
}


# ===========================================================================
# Authentication endpoints
# ===========================================================================

@app.post(
    "/v1/auth/login",
    response_model=LoginResponse,
    tags=["Authentication"],
    summary="Login with API key",
    description=(
        "Exchange an API key for a JWT access token + refresh token pair. "
        "The API key is configured via the ADP_API_KEY env var on server startup. "
        "Tokens include scopes based on the requested role (admin/user)."
    ),
    responses={
        401: {"model": ErrorResponse, "description": "Invalid API key"},
    },
)
async def login(body: LoginRequest):
    """Authenticate with an API key and receive JWT tokens."""
    key_info = validate_api_key(body.api_key)
    if key_info is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
        )

    role = body.role
    if role not in ("admin", "user"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid role: {role}. Must be 'admin' or 'user'.",
        )

    # Determine scopes: requested scopes are intersected with role defaults
    role_scopes = DEFAULT_SCOPES.get(role, DEFAULT_SCOPES["user"])
    if body.scopes:
        # Validate that requested scopes are a subset of role scopes
        invalid = set(body.scopes) - set(role_scopes)
        if invalid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Scopes not allowed for role '{role}': {list(invalid)}",
            )
        scopes = body.scopes
    else:
        scopes = role_scopes

    access_token = create_access_token(
        subject=body.subject,
        scopes=scopes,
        role=role,
    )
    refresh_token = create_refresh_token(
        subject=body.subject,
        scopes=scopes,
        role=role,
    )

    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=ACCESS_TOKEN_EXPIRE_SECONDS,
        scopes=scopes,
        role=role,
    )


@app.post(
    "/v1/auth/refresh",
    response_model=RefreshResponse,
    tags=["Authentication"],
    summary="Refresh access token",
    description=(
        "Exchange a refresh token for a new access token. "
        "Refresh tokens are single-use — they are consumed and a new "
        "refresh token is issued (token rotation)."
    ),
    responses={
        401: {"model": ErrorResponse, "description": "Invalid or expired refresh token"},
    },
)
async def refresh(body: RefreshRequest):
    """Rotate tokens: consume old refresh, issue new pair."""
    import jwt as _jwt
    from .auth import decode_token

    try:
        payload = decode_token(body.refresh_token)
    except _jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has expired",
        )
    except _jwt.InvalidTokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid refresh token: {e}",
        )

    if payload.get("tt") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not a refresh token. Use an access token for API calls.",
        )

    jti = payload.get("jti", "")
    sub = payload.get("sub", "")
    scopes = payload.get("scopes", [])
    role = payload.get("role", "user")

    # Consume the old refresh token (single-use)
    consume_refresh_token(jti)

    # Issue new tokens
    access_token = create_access_token(subject=sub, scopes=scopes, role=role)
    new_refresh = create_refresh_token(subject=sub, scopes=scopes, role=role)

    return RefreshResponse(
        access_token=access_token,
        refresh_token=new_refresh,
        token_type="bearer",
        expires_in=ACCESS_TOKEN_EXPIRE_SECONDS,
        scopes=scopes,
        role=role,
    )


@app.post(
    "/v1/auth/revoke",
    response_model=RevokeResponse,
    tags=["Authentication"],
    summary="Revoke current token",
    description="Revoke the current access token by its JTI.",
    responses={
        401: {"model": ErrorResponse, "description": "Invalid token"},
    },
)
async def revoke(user: dict = Depends(get_current_user)):
    """Revoke the current token."""
    jti = user.get("jti", "")
    revoke_token(jti)
    return RevokeResponse(revoked=True, jti=jti)


@app.get(
    "/v1/auth/me",
    response_model=TokenInfo,
    tags=["Authentication"],
    summary="Get current token info",
    description="Return information about the current authenticated token.",
)
async def me(user: dict = Depends(get_current_user)):
    """Return current token metadata."""
    return TokenInfo(
        sub=user.get("sub", ""),
        role=user.get("role", ""),
        scopes=user.get("scopes", []),
        jti=user.get("jti", ""),
        iat=user.get("iat", 0),
        exp=user.get("exp", 0),
        tt=user.get("tt", "access"),
    )


# ===========================================================================
# Platform endpoints
# ===========================================================================

@app.get(
    "/v1/platform/status",
    response_model=ADPResult,
    tags=["Platform"],
    summary="Get platform status",
    description="Get ADP-OS platform and runtime health status.",
)
async def platform_status(
    runtime: Optional[str] = Query(None, description="Runtime name for detailed status"),
    user: dict = Depends(require_scope("platform:read")),
):
    """Get platform/runtime status."""
    args = ["status"]
    if runtime:
        args.append(runtime)
    result = _run_adp(args)
    return _structured_result(result)


@app.get(
    "/v1/platform/doctor",
    response_model=ADPResult,
    tags=["Platform"],
    summary="Run diagnostics",
    description="Run ADP-OS platform diagnostics (doctor).",
)
async def platform_doctor(
    user: dict = Depends(require_scope("platform:read")),
):
    """Run platform diagnostics."""
    result = _run_adp(["doctor"])
    from cli.mcp.server import _parse_doctor
    return _structured_result(result, _parse_doctor(result["stdout"]))


@app.get(
    "/v1/platform/capabilities",
    response_model=ADPResult,
    tags=["Platform"],
    summary="Platform capabilities",
    description="Show ADP-OS platform capabilities and roadmap.",
)
async def platform_capabilities(
    user: dict = Depends(require_scope("platform:read")),
):
    """Show platform capabilities."""
    result = _run_adp(["capabilities"])
    from cli.mcp.server import _parse_capabilities
    return _structured_result(result, _parse_capabilities(result["stdout"]))


# ===========================================================================
# Workspace endpoints
# ===========================================================================

@app.get(
    "/v1/workspaces",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="List workspace projects",
    description="List all workspace projects defined in the manifest.",
)
async def workspace_list(
    user: dict = Depends(require_scope("workspace:read")),
):
    """List workspace projects."""
    result = _run_adp(["workspace", "show"])
    from cli.mcp.server import _parse_workspace_show
    return _structured_result(result, _parse_workspace_show(result["stdout"]))


@app.get(
    "/v1/workspaces/status",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Workspace readiness",
    description="Get detailed workspace readiness status.",
)
async def workspace_status(
    user: dict = Depends(require_scope("workspace:read")),
):
    """Get workspace status."""
    result = _run_adp(["workspace", "status"])
    return _structured_result(result)


@app.get(
    "/v1/workspaces/dashboard",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Workspace dashboard",
    description="Get workspace dashboard with task lifecycle overview.",
)
async def workspace_dashboard(
    user: dict = Depends(require_scope("workspace:read")),
):
    """Get workspace dashboard."""
    result = _run_adp(["workspace", "dashboard"])
    return _structured_result(result)


@app.get(
    "/v1/workspaces/recipes",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="List recipes",
    description="List available workspace recipes.",
)
async def workspace_recipes(
    user: dict = Depends(require_scope("workspace:read")),
):
    """List workspace recipes."""
    result = _run_adp(["workspace", "recipes"])
    return _structured_result(result)


@app.get(
    "/v1/workspaces/report",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Generate report",
    description="Generate workspace release evidence in Markdown format.",
)
async def workspace_report(
    user: dict = Depends(require_scope("workspace:read")),
):
    """Generate workspace report."""
    result = _run_adp(["workspace", "report", "-Markdown"])
    return _structured_result(result)


@app.get(
    "/v1/workspaces/{project}",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Get project details",
    description="Get a single project's full operational lifecycle view.",
)
async def workspace_project(
    project: str,
    user: dict = Depends(require_scope("workspace:read")),
):
    """Get project details."""
    result = _run_adp(["workspace", "project", project])
    return _structured_result(result)


@app.post(
    "/v1/workspaces/{project}/create",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Create workspace directories",
    description=(
        "Create workspace project directories. "
        "Default plan_only=true shows what would happen without creating."
    ),
)
async def workspace_create(
    project: str,
    plan_only: bool = Query(True, description="Preview only, no actual creation"),
    user: dict = Depends(require_scope("workspace:write")),
):
    """Create workspace project directories."""
    args = ["workspace", "create", project]
    if plan_only:
        args.append("-Plan")
    result = _run_adp(args)
    return _structured_result(result)


@app.get(
    "/v1/workspaces/{project}/open",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Get entry guidance",
    description="Get guidance for entering a workspace project.",
)
async def workspace_open(
    project: str,
    user: dict = Depends(require_scope("workspace:read")),
):
    """Get workspace entry guidance."""
    result = _run_adp(["workspace", "open", project])
    return _structured_result(result)


@app.get(
    "/v1/workspaces/{project}/sync",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Get sync guidance",
    description="Get per-project file sync guidance.",
)
async def workspace_sync(
    project: str,
    user: dict = Depends(require_scope("workspace:read")),
):
    """Get sync guidance."""
    result = _run_adp(["workspace", "sync", project])
    return _structured_result(result)


@app.post(
    "/v1/workspaces/{project}/close",
    response_model=ADPResult,
    tags=["Workspaces"],
    summary="Close workspace",
    description=(
        "Close a workspace by stopping file sync for its runtime. "
        "Default plan_only=true previews without stopping sync."
    ),
)
async def workspace_close(
    project: str,
    plan_only: bool = Query(True, description="Preview only, no actual close"),
    user: dict = Depends(require_scope("workspace:write")),
):
    """Close a workspace."""
    from cli.mcp.server import _find_runtime_for_project

    runtime = _find_runtime_for_project(project)
    if not runtime:
        guidance = _run_adp(["workspace", "sync", project])
        return _structured_result(guidance, {
            "action": "close_failed",
            "reason": f"Could not resolve runtime for project '{project}'",
        })

    sync_result = _run_adp(["sync", "status"])

    if plan_only:
        return _structured_result(sync_result, {
            "action": "close_plan",
            "project": project,
            "runtime": runtime,
            "plan_only": True,
        })

    stop_result = _run_adp(["sync", "stop", runtime])
    return _structured_result(stop_result, {
        "action": "close_executed",
        "project": project,
        "runtime": runtime,
    })


# ===========================================================================
# Runtime endpoints
# ===========================================================================

@app.post(
    "/v1/runtimes/{runtime}/up",
    response_model=ADPResult,
    tags=["Runtimes"],
    summary="Start a runtime VM",
    description=(
        "Start a runtime VM (creates from ISO if first time). "
        "Default plan_only=true shows what would happen without starting. "
        "VM creation from ISO may take 15-45 minutes on first run."
    ),
)
async def runtime_up(
    runtime: str,
    plan_only: bool = Query(True, description="Preview only, no actual start"),
    iso_path: Optional[str] = Query(None, description="Path to Ubuntu Server ISO"),
    user: dict = Depends(require_scope("runtime:write")),
):
    """Start a runtime VM."""
    args = ["up", runtime]
    if plan_only:
        args.append("-Plan")
    if iso_path:
        from cli.mcp.server import _normalize_windows_path
        normalized = _normalize_windows_path(iso_path)
        if normalized:
            args.append("-IsoPath")
            args.append(normalized)
    timeout = 300 if not plan_only else 120
    result = _run_adp(args, timeout=timeout)
    return _structured_result(result, {
        "runtime": runtime,
        "plan_only": plan_only,
    })


@app.post(
    "/v1/runtimes/{runtime}/down",
    response_model=ADPResult,
    tags=["Runtimes"],
    summary="Destroy a runtime VM",
    description=(
        "Destroy a runtime VM completely. IRREVERSIBLE when plan_only=false. "
        "Default plan_only=true previews without destroying."
    ),
)
async def runtime_down(
    runtime: str,
    plan_only: bool = Query(True, description="Preview only, no actual destruction"),
    force: bool = Query(False, description="Skip confirmation prompts"),
    user: dict = Depends(require_scope("runtime:write")),
):
    """Destroy a runtime VM."""
    args = ["destroy", runtime]
    if plan_only:
        args.append("-Plan")
    if force:
        args.append("-Force")
    result = _run_adp(args)
    return _structured_result(result, {
        "runtime": runtime,
        "plan_only": plan_only,
        "force": force,
    })


@app.post(
    "/v1/runtimes/{runtime}/stop",
    response_model=ADPResult,
    tags=["Runtimes"],
    summary="Stop a runtime VM",
    description="Gracefully stop a runtime VM without destroying it.",
)
async def runtime_stop(
    runtime: str,
    user: dict = Depends(require_scope("runtime:write")),
):
    """Stop a runtime VM gracefully."""
    result = _run_adp(["stop", runtime])
    return _structured_result(result, {"runtime": runtime})


# ===========================================================================
# Sync endpoints
# ===========================================================================

@app.get(
    "/v1/sync/status",
    response_model=ADPResult,
    tags=["Sync"],
    summary="Sync session status",
    description="Get Mutagen sync session status for all runtimes.",
)
async def sync_status(
    user: dict = Depends(require_scope("runtime:read")),
):
    """Get sync session status."""
    from cli.mcp.server import _parse_sync_status
    result = _run_adp(["sync", "status"])
    return _structured_result(result, _parse_sync_status(result["stdout"]))


@app.post(
    "/v1/sync/{runtime}/stop",
    response_model=ADPResult,
    tags=["Sync"],
    summary="Stop sync session",
    description="Stop a Mutagen sync session for a runtime.",
)
async def sync_stop(
    runtime: str,
    user: dict = Depends(require_scope("runtime:write")),
):
    """Stop a sync session."""
    result = _run_adp(["sync", "stop", runtime])
    return _structured_result(result, {"runtime": runtime})


# ===========================================================================
# Admin endpoints
# ===========================================================================

@app.post(
    "/v1/admin/tokens",
    response_model=LoginResponse,
    tags=["Admin"],
    summary="Issue tokens for a user",
    description="Admin-only: issue JWT tokens for any subject.",
)
async def admin_create_token(
    body: AdminTokenCreate,
    user: dict = Depends(require_admin),
):
    """Issue tokens for a user (admin only)."""
    role = body.role
    if role not in ("admin", "user"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid role: {role}",
        )

    role_scopes = DEFAULT_SCOPES.get(role, DEFAULT_SCOPES["user"])
    if body.scopes:
        invalid = set(body.scopes) - set(role_scopes)
        if invalid:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Scopes not allowed for role '{role}': {list(invalid)}",
            )
        scopes = body.scopes
    else:
        scopes = role_scopes

    access_token = create_access_token(subject=body.subject, scopes=scopes, role=role)
    refresh_token = create_refresh_token(subject=body.subject, scopes=scopes, role=role)

    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=ACCESS_TOKEN_EXPIRE_SECONDS,
        scopes=scopes,
        role=role,
    )


@app.get(
    "/v1/admin/tokens",
    response_model=AdminTokenList,
    tags=["Admin"],
    summary="List issued tokens",
    description="Admin-only: list all issued tokens.",
)
async def admin_list_tokens(
    user: dict = Depends(require_admin),
):
    """List all issued tokens."""
    tokens = list_tokens()
    return AdminTokenList(tokens=tokens, count=len(tokens))


@app.delete(
    "/v1/admin/tokens/{jti}",
    response_model=RevokeResponse,
    tags=["Admin"],
    summary="Revoke a token",
    description="Admin-only: revoke a token by its JTI.",
)
async def admin_revoke_token(
    jti: str,
    user: dict = Depends(require_admin),
):
    """Revoke a token by JTI."""
    revoke_token(jti)
    return RevokeResponse(revoked=True, jti=jti)


@app.delete(
    "/v1/admin/tokens/subject/{subject}",
    response_model=dict,
    tags=["Admin"],
    summary="Revoke all tokens for a subject",
    description="Admin-only: revoke all tokens for a given subject.",
)
async def admin_revoke_subject(
    subject: str,
    user: dict = Depends(require_admin),
):
    """Revoke all tokens for a subject."""
    count = revoke_token_by_sub(subject)
    return {"subject": subject, "revoked_count": count}


@app.get(
    "/v1/admin/health",
    response_model=AdminHealthResponse,
    tags=["Admin"],
    summary="API server health",
    description="Admin-only: API server health check with metrics.",
)
async def admin_health(
    user: dict = Depends(require_admin),
):
    """API server health check."""
    return AdminHealthResponse(
        status="healthy",
        version="0.1.0",
        uptime_seconds=time.time() - _start_time,
        revoked_tokens=len(_revoked_jtis),
        issued_tokens=len(_issued_tokens),
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "cli.api.server:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info",
    )
