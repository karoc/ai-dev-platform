"""
FastAPI dependency injection for JWT authentication and RBAC enforcement.

Provides:
  - get_current_user: Extracts and validates JWT from Authorization header
  - require_scopes: Factory that returns a dependency checking token scopes
  - require_admin: Shortcut for admin-only endpoints
"""

from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt

from .auth import decode_token

# ---------------------------------------------------------------------------
# Security scheme
# ---------------------------------------------------------------------------

security = HTTPBearer(
    scheme_name="JWT",
    description="Enter your JWT access token (Bearer <token>)",
    auto_error=False,  # We handle missing token ourselves for better error messages
)


# ---------------------------------------------------------------------------
# Dependency: get_current_user
# ---------------------------------------------------------------------------

def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> dict:
    """Extract and validate the current user from the JWT Bearer token.

    Returns:
        Decoded token payload (dict with sub, role, scopes, jti, etc.)

    Raises:
        HTTPException 401: Missing, invalid, or expired token
    """
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization header. Use: Bearer <token>",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = credentials.credentials
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Empty token in Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        payload = decode_token(token)
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.InvalidTokenError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {e}",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Ensure it's an access token, not a refresh token
    if payload.get("tt") == "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token cannot be used for API access. Use an access token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return payload


# ---------------------------------------------------------------------------
# Dependency: require_scopes
# ---------------------------------------------------------------------------

def require_scope(*required_scopes: str):
    """Factory: create a dependency that checks the token has the required scopes.

    Usage:
        @app.get("/workspaces")
        async def list_workspaces(user: dict = Depends(require_scope("workspace:read"))):
            ...

    Wildcard 'admin:*' grants all scopes.
    Partial wildcard 'workspace:*' grants all 'workspace:' family scopes.

    Args:
        *required_scopes: Scope strings required for this endpoint

    Returns:
        Callable dependency that returns the user payload if authorized
    """
    async def _check_scopes(
        user: dict = Depends(get_current_user),
    ) -> dict:
        user_scopes = set(user.get("scopes", []))

        # Admin wildcard grants everything
        if "admin:*" in user_scopes:
            return user

        for required in required_scopes:
            if required in user_scopes:
                continue
            # Check wildcard: if user has "workspace:*", it covers "workspace:read"
            if ":" in required:
                prefix = required.rsplit(":", 1)[0] + ":*"
                if prefix in user_scopes:
                    continue
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required scope: {required}",
            )
        return user

    return _check_scopes


# ---------------------------------------------------------------------------
# Dependency: require_admin
# ---------------------------------------------------------------------------

async def require_admin(
    user: dict = Depends(get_current_user),
) -> dict:
    """Require admin role. Admin role has 'admin:*' scope."""
    role = user.get("role", "")
    scopes = user.get("scopes", [])

    if role != "admin" and "admin:*" not in scopes:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required for this endpoint",
        )
    return user
