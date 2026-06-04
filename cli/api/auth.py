"""
JWT authentication module for ADP-OS REST API.

Inspired by Containarium's JWT architecture (iss/aud/jti/scopes).
Uses HS256 symmetric key — simple, self-contained, no external IdP needed.

Token types:
  - access_token: 1 hour expiry, used for API authentication
  - refresh_token: 7 day expiry, used to obtain new access tokens
  - api_key: no expiry, used for bootstrap/admin (rotatable)

Revocation: in-memory JTI blacklist. Lost on restart — acceptable for MVP.
"""

import os
import uuid
import time
import secrets
from typing import Optional

import jwt


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

def _get_jwt_secret() -> str:
    """Get JWT secret from env or generate a random one on first access.

    The secret is cached in the module for the process lifetime.
    Minimum 32 bytes enforced (matching Containarium requirement).

    Returns:
        JWT secret string
    """
    secret = os.environ.get("ADP_JWT_SECRET", "")
    if secret:
        if len(secret.encode()) < 32:
            raise ValueError(
                "ADP_JWT_SECRET must be at least 32 bytes. "
                f"Got {len(secret.encode())} bytes."
            )
        return secret

    # Generate a random secret if not set — this means tokens won't survive
    # a server restart, which is acceptable for single-instance self-hosted MVP.
    import warnings
    warnings.warn(
        "ADP_JWT_SECRET not set — generated a random secret. "
        "Tokens will be invalidated on server restart. "
        "Set ADP_JWT_SECRET env var for persistent tokens."
    )
    return secrets.token_hex(32)


JWT_SECRET = _get_jwt_secret()
JWT_ALGORITHM = "HS256"

ACCESS_TOKEN_EXPIRE_SECONDS = 3600       # 1 hour
REFRESH_TOKEN_EXPIRE_SECONDS = 604800    # 7 days

# Issuer and audience — stable identifiers
TOKEN_ISSUER = "adp-os-api"
TOKEN_AUDIENCE = "adp-os"


# ---------------------------------------------------------------------------
# Token store (in-memory)
# ---------------------------------------------------------------------------

# Set of revoked JTIs. A token is revoked if its jti is in this set OR
# if the jti was a refresh token's jti AND the refresh was consumed (single-use).
_revoked_jtis: set[str] = set()

# Set of consumed refresh token JTIs. A refresh token can only be used once.
_consumed_refresh_jtis: set[str] = set()

# Registered API keys (for bootstrap — maps api_key -> owner name)
_api_keys: dict[str, dict] = {}

# List of issued tokens (for admin listing)
_issued_tokens: list[dict] = []


def register_api_key(api_key: str, owner: str = "admin", scopes: Optional[list[str]] = None):
    """Register a bootstrap API key.

    API keys have no expiry and are used to obtain initial access tokens.

    Args:
        api_key: The API key string (should be a long random string)
        owner: Owner name for audit logs
        scopes: Optional scope override (defaults to admin:*)
    """
    _api_keys[api_key] = {
        "owner": owner,
        "scopes": scopes or ["admin:*"],
        "created_at": int(time.time()),
    }


# Auto-register API key from env if set
_apikey_env = os.environ.get("ADP_API_KEY", "").strip()
if _apikey_env:
    register_api_key(_apikey_env, owner="bootstrap")


# ---------------------------------------------------------------------------
# Token creation
# ---------------------------------------------------------------------------

def _make_jti() -> str:
    """Generate a unique token ID."""
    return uuid.uuid4().hex


def create_access_token(
    subject: str,
    scopes: list[str],
    role: str = "user",
    expires_in: int = ACCESS_TOKEN_EXPIRE_SECONDS,
) -> str:
    """Create a new JWT access token.

    Args:
        subject: Token owner identifier (e.g., 'agent-1', 'user-alice')
        scopes: List of scope strings (e.g., ['workspace:read', 'runtime:write'])
        role: Role name for RBAC ('admin' or 'user')
        expires_in: Token lifetime in seconds

    Returns:
        Encoded JWT string
    """
    now = int(time.time())
    jti = _make_jti()
    payload = {
        "iss": TOKEN_ISSUER,
        "sub": subject,
        "aud": TOKEN_AUDIENCE,
        "jti": jti,
        "iat": now,
        "exp": now + expires_in,
        "scopes": scopes,
        "role": role,
        "tt": "access",       # token type
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    _issued_tokens.append({
        "jti": jti,
        "sub": subject,
        "role": role,
        "scopes": scopes,
        "tt": "access",
        "iat": now,
        "exp": now + expires_in,
    })

    return token


def create_refresh_token(
    subject: str,
    scopes: list[str],
    role: str = "user",
    expires_in: int = REFRESH_TOKEN_EXPIRE_SECONDS,
    parent_jti: Optional[str] = None,
) -> str:
    """Create a new JWT refresh token (single-use).

    Args:
        subject: Token owner identifier
        scopes: Scope list (same as access token)
        role: Role name
        expires_in: Token lifetime in seconds (default 7 days)
        parent_jti: JTI of the access token this refresh was issued alongside

    Returns:
        Encoded JWT string
    """
    now = int(time.time())
    jti = _make_jti()
    payload = {
        "iss": TOKEN_ISSUER,
        "sub": subject,
        "aud": TOKEN_AUDIENCE,
        "jti": jti,
        "iat": now,
        "exp": now + expires_in,
        "scopes": scopes,
        "role": role,
        "tt": "refresh",
    }
    if parent_jti:
        payload["parent_jti"] = parent_jti

    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    _issued_tokens.append({
        "jti": jti,
        "sub": subject,
        "role": role,
        "scopes": scopes,
        "tt": "refresh",
        "iat": now,
        "exp": now + expires_in,
    })

    return token


# ---------------------------------------------------------------------------
# Token validation and revocation
# ---------------------------------------------------------------------------

def decode_token(token: str) -> dict:
    """Decode and validate a JWT token.

    Checks: signature, expiration, issuer, audience, revocation, and
    single-use (refresh token consumed).

    Args:
        token: Encoded JWT string

    Returns:
        Decoded token payload as dict

    Raises:
        jwt.ExpiredSignatureError: Token has expired
        jwt.InvalidTokenError: Token is invalid or revoked
    """
    payload = jwt.decode(
        token,
        JWT_SECRET,
        algorithms=[JWT_ALGORITHM],
        issuer=TOKEN_ISSUER,
        audience=TOKEN_AUDIENCE,
    )

    jti = payload.get("jti", "")

    # Check revocation
    if jti in _revoked_jtis:
        raise jwt.InvalidTokenError("Token has been revoked")

    # Check single-use for refresh tokens
    if payload.get("tt") == "refresh" and jti in _consumed_refresh_jtis:
        raise jwt.InvalidTokenError("Refresh token has already been used")

    return payload


def revoke_token(jti: str):
    """Revoke a token by its JTI.

    Args:
        jti: Token ID to revoke
    """
    _revoked_jtis.add(jti)
    # Also mark as consumed if it was a refresh token
    for t in _issued_tokens:
        if t["jti"] == jti and t["tt"] == "refresh":
            _consumed_refresh_jtis.add(jti)
            break


def consume_refresh_token(jti: str):
    """Mark a refresh token as consumed (single-use enforcement).

    Args:
        jti: Refresh token JTI that was just used
    """
    _consumed_refresh_jtis.add(jti)


# ---------------------------------------------------------------------------
# API key validation
# ---------------------------------------------------------------------------

def validate_api_key(api_key: str) -> Optional[dict]:
    """Validate an API key and return its metadata.

    Args:
        api_key: API key string

    Returns:
        dict with owner, scopes, created_at, or None if invalid
    """
    return _api_keys.get(api_key)


# ---------------------------------------------------------------------------
# Token listing (admin)
# ---------------------------------------------------------------------------

def list_tokens() -> list[dict]:
    """List all issued tokens (for admin dashboard)."""
    return list(_issued_tokens)


def revoke_token_by_sub(subject: str) -> int:
    """Revoke all tokens for a subject.

    Args:
        subject: Subject identifier

    Returns:
        Number of tokens revoked
    """
    count = 0
    for t in list(_issued_tokens):
        if t["sub"] == subject:
            if t["jti"] not in _revoked_jtis:
                _revoked_jtis.add(t["jti"])
                count += 1
            if t["tt"] == "refresh":
                _consumed_refresh_jtis.add(t["jti"])
    return count
