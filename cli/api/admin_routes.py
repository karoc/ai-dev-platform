"""Admin route registration for the ADP-OS REST API."""

import time
from typing import List, Mapping

from fastapi import Depends, FastAPI, HTTPException, status

from .auth import (
    ACCESS_TOKEN_EXPIRE_SECONDS,
    _issued_tokens,
    _revoked_jtis,
    create_access_token,
    create_refresh_token,
    list_tokens,
    revoke_token,
    revoke_token_by_sub,
)
from .dependencies import require_admin
from .models import (
    AdminHealthResponse,
    AdminTokenCreate,
    AdminTokenList,
    LoginResponse,
    RevokeResponse,
)


def register_admin_routes(
    app: FastAPI,
    start_time: float,
    default_scopes: Mapping[str, List[str]],
) -> None:
    """Register admin-only routes on the provided FastAPI app."""

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

        role_scopes = default_scopes.get(role, default_scopes["user"])
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
            uptime_seconds=time.time() - start_time,
            revoked_tokens=len(_revoked_jtis),
            issued_tokens=len(_issued_tokens),
        )
