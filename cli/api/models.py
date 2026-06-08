"""
Pydantic models for ADP-OS REST API request/response schemas.

Used by FastAPI for automatic validation, serialization, and OpenAPI docs.
"""

from typing import Optional, Any
from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Authentication models
# ---------------------------------------------------------------------------

class LoginRequest(BaseModel):
    """Login with an API key to obtain access + refresh tokens."""
    api_key: str = Field(..., description="Bootstrap API key")
    subject: str = Field(..., description="Token owner identifier (e.g., 'agent-1')")
    scopes: Optional[list[str]] = Field(
        default=None,
        description="Requested scopes subset. If omitted, inherits full role scopes."
    )
    role: str = Field(default="user", description="Role: 'admin' or 'user'")


class LoginResponse(BaseModel):
    """Access token + refresh token pair."""
    access_token: str = Field(..., description="JWT access token (1 hour)")
    refresh_token: str = Field(..., description="JWT refresh token (7 days, single-use)")
    token_type: str = Field(default="bearer", description="Token type")
    expires_in: int = Field(..., description="Access token lifetime in seconds")
    scopes: list[str] = Field(..., description="Granted scopes")
    role: str = Field(..., description="Assigned role")


class RefreshRequest(BaseModel):
    """Exchange a refresh token for a new access token."""
    refresh_token: str = Field(..., description="Valid refresh token")


class RefreshResponse(BaseModel):
    """New access token after refresh."""
    access_token: str = Field(..., description="New JWT access token")
    refresh_token: str = Field(..., description="New JWT refresh token (rotated)")
    token_type: str = Field(default="bearer", description="Token type")
    expires_in: int = Field(..., description="Access token lifetime in seconds")
    scopes: list[str] = Field(..., description="Granted scopes")
    role: str = Field(..., description="Assigned role")


class RevokeResponse(BaseModel):
    """Confirmation of token revocation."""
    revoked: bool = Field(default=True, description="Whether revocation succeeded")
    jti: str = Field(..., description="Revoked token JTI")


class TokenInfo(BaseModel):
    """Current token information (GET /auth/me)."""
    sub: str = Field(..., description="Token subject")
    role: str = Field(..., description="Role")
    scopes: list[str] = Field(..., description="Granted scopes")
    jti: str = Field(..., description="Token JTI")
    iat: int = Field(..., description="Issued at (unix timestamp)")
    exp: int = Field(..., description="Expires at (unix timestamp)")
    tt: str = Field(..., description="Token type (access/refresh)")


class ErrorResponse(BaseModel):
    """Standard error response."""
    error: str = Field(..., description="Error code")
    detail: str = Field(..., description="Human-readable error message")


# ---------------------------------------------------------------------------
# Platform / CLI execution models
# ---------------------------------------------------------------------------

class ADPResult(BaseModel):
    """Structured result from an ADP-OS command execution."""
    text: str = Field(..., alias="_text", description="Formatted human-readable output")
    exit_code: int = Field(..., alias="_exit_code", description="Command exit code")
    success: bool = Field(..., alias="_success", description="Whether the command succeeded")
    model_config = {"extra": "allow", "populate_by_name": True}  # Allow command-specific parsed fields


class StatusResponse(ADPResult):
    """Platform status with parsed runtime info."""
    runtimes: Optional[list[dict]] = Field(default=None, description="Runtime list")
    runtime_count: Optional[int] = Field(default=None, description="Total runtimes")
    running_count: Optional[int] = Field(default=None, description="Running runtimes")


class DoctorResponse(ADPResult):
    """Doctor diagnostics with parsed counts."""
    ok_count: Optional[int] = Field(default=None, description="OK checks")
    issue_count: Optional[int] = Field(default=None, description="Issues found")
    info_count: Optional[int] = Field(default=None, description="Info items")
    issues: Optional[list[dict]] = Field(default=None, description="Issue details")
    healthy: Optional[bool] = Field(default=None, description="Overall health")


class CapabilitiesResponse(ADPResult):
    """Capabilities with parsed matrix."""
    supported: Optional[list[str]] = Field(default=None, description="Supported features")
    planned: Optional[list[str]] = Field(default=None, description="Planned features")
    exploratory: Optional[list[str]] = Field(default=None, description="Exploratory features")


class WorkspaceListResponse(ADPResult):
    """Workspace list with parsed projects."""
    projects: Optional[list[dict]] = Field(default=None, description="Project list")
    project_count: Optional[int] = Field(default=None, description="Project count")


class SyncStatusResponse(ADPResult):
    """Sync status with parsed sessions."""
    sessions: Optional[list[dict]] = Field(default=None, description="Sync sessions")
    session_count: Optional[int] = Field(default=None, description="Session count")
    healthy_count: Optional[int] = Field(default=None, description="Healthy sessions")


# ---------------------------------------------------------------------------
# Admin models
# ---------------------------------------------------------------------------

class AdminTokenCreate(BaseModel):
    """Admin request to issue tokens for a user."""
    subject: str = Field(..., description="Token owner identifier")
    role: str = Field(default="user", description="Role: 'admin' or 'user'")
    scopes: Optional[list[str]] = Field(
        default=None,
        description="Explicit scopes (defaults to role defaults)"
    )


class AdminTokenList(BaseModel):
    """List of issued tokens."""
    tokens: list[dict] = Field(..., description="Issued tokens")
    count: int = Field(..., description="Token count")


class AdminHealthResponse(BaseModel):
    """API server health check."""
    status: str = Field(default="healthy", description="Server status")
    version: str = Field(default="0.1.0", description="API version")
    uptime_seconds: float = Field(default=0, description="Server uptime")
    revoked_tokens: int = Field(default=0, description="Revoked token count")
    issued_tokens: int = Field(default=0, description="Issued token count")
