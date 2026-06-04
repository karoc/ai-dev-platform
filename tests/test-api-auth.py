"""
Tests for ADP-OS REST API — authentication module.

Verifies:
  - JWT token lifecycle: create, decode, refresh, revoke
  - API key registration and validation
  - RBAC scope enforcement logic
  - Token expiry handling
  - Single-use refresh token enforcement

Does NOT require pwsh.exe or an actual ADP-OS installation.
Run: python tests/test-api-auth.py
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestAuth:
    """Test the JWT authentication module."""

    def setup_method(self):
        """Reset state before each test."""
        from cli.api import auth
        auth._revoked_jtis.clear()
        auth._consumed_refresh_jtis.clear()
        auth._api_keys.clear()
        auth._issued_tokens.clear()
        # Set a deterministic secret for tests
        auth.JWT_SECRET = "test-secret-" * 4  # 48 bytes

    def test_register_api_key(self):
        """API key can be registered and validated."""
        from cli.api.auth import register_api_key, validate_api_key

        register_api_key("sk-test123", owner="test-user")
        info = validate_api_key("sk-test123")
        assert info is not None
        assert info["owner"] == "test-user"
        assert "admin:*" in info["scopes"]

    def test_register_api_key_custom_scopes(self):
        """API key with custom scopes."""
        from cli.api.auth import register_api_key, validate_api_key

        register_api_key("sk-scoped", owner="agent-1", scopes=["workspace:read"])
        info = validate_api_key("sk-scoped")
        assert info["scopes"] == ["workspace:read"]

    def test_validate_invalid_api_key(self):
        """Invalid API key returns None."""
        from cli.api.auth import validate_api_key
        assert validate_api_key("nonexistent") is None

    def test_create_access_token(self):
        """Access token has correct structure."""
        from cli.api.auth import create_access_token, decode_token

        token = create_access_token(
            subject="agent-1",
            scopes=["workspace:read", "runtime:write"],
            role="user",
        )
        payload = decode_token(token)

        assert payload["iss"] == "adp-os-api"
        assert payload["sub"] == "agent-1"
        assert payload["aud"] == "adp-os"
        assert payload["role"] == "user"
        assert payload["tt"] == "access"
        assert "workspace:read" in payload["scopes"]
        assert "runtime:write" in payload["scopes"]
        assert "jti" in payload
        assert "iat" in payload
        assert "exp" in payload
        # Token should not expire immediately
        assert payload["exp"] > payload["iat"]

    def test_create_refresh_token(self):
        """Refresh token has correct type and longer expiry."""
        from cli.api.auth import create_refresh_token, decode_token

        token = create_refresh_token(
            subject="agent-1",
            scopes=["workspace:read"],
            role="user",
        )
        payload = decode_token(token)

        assert payload["tt"] == "refresh"
        assert payload["sub"] == "agent-1"
        # Refresh token should expire after access token
        assert payload["exp"] - payload["iat"] > 3600  # More than 1 hour

    def test_admin_token_has_admin_scopes(self):
        """Admin token gets admin:* scope."""
        from cli.api.auth import create_access_token, decode_token

        token = create_access_token(
            subject="admin-1",
            scopes=["admin:*"],
            role="admin",
        )
        payload = decode_token(token)
        assert payload["role"] == "admin"
        assert "admin:*" in payload["scopes"]

    def test_revoke_token(self):
        """Revoked tokens cannot be decoded."""
        from cli.api.auth import create_access_token, decode_token, revoke_token
        import jwt

        token = create_access_token("agent-1", ["workspace:read"], "user")
        payload = decode_token(token)
        revoke_token(payload["jti"])

        try:
            decode_token(token)
            assert False, "Should have raised InvalidTokenError"
        except jwt.InvalidTokenError as e:
            assert "revoked" in str(e).lower()

    def test_single_use_refresh_token(self):
        """Refresh tokens can only be used once."""
        from cli.api.auth import (
            create_refresh_token, decode_token, consume_refresh_token
        )
        import jwt

        token = create_refresh_token("agent-1", ["workspace:read"], "user")
        payload = decode_token(token)
        consume_refresh_token(payload["jti"])

        try:
            decode_token(token)
            assert False, "Should have raised"
        except jwt.InvalidTokenError as e:
            assert "already been used" in str(e).lower()

    def test_decode_invalid_token(self):
        """Garbage token raises InvalidTokenError."""
        from cli.api.auth import decode_token
        import jwt

        try:
            decode_token("not.a.valid.token")
            assert False, "Should have raised"
        except jwt.InvalidTokenError:
            pass

    def test_decode_expired_token(self):
        """Expired token raises ExpiredSignatureError."""
        from cli.api import auth
        import jwt as _jwt

        # Create a token that expired 10 seconds ago
        import time
        now = int(time.time())
        payload = {
            "iss": auth.TOKEN_ISSUER,
            "sub": "agent-1",
            "aud": auth.TOKEN_AUDIENCE,
            "jti": "test-jti-expired",
            "iat": now - 7200,
            "exp": now - 10,
            "scopes": ["workspace:read"],
            "role": "user",
            "tt": "access",
        }
        token = _jwt.encode(payload, auth.JWT_SECRET, algorithm="HS256")

        try:
            auth.decode_token(token)
            assert False, "Should have raised ExpiredSignatureError"
        except _jwt.ExpiredSignatureError:
            pass

    def test_revoke_by_subject(self):
        """Revoke all tokens for a subject."""
        from cli.api.auth import (
            create_access_token, revoke_token_by_sub, decode_token
        )
        import jwt

        t1 = create_access_token("agent-1", ["workspace:read"], "user")
        t2 = create_access_token("agent-1", ["workspace:read"], "user")
        t3 = create_access_token("agent-2", ["workspace:read"], "user")

        count = revoke_token_by_sub("agent-1")
        assert count == 2

        # agent-1 tokens revoked
        try:
            decode_token(t1)
            assert False
        except jwt.InvalidTokenError:
            pass
        try:
            decode_token(t2)
            assert False
        except jwt.InvalidTokenError:
            pass

        # agent-2 token still works
        decode_token(t3)

    def test_list_tokens(self):
        """List issued tokens."""
        from cli.api.auth import create_access_token, list_tokens

        create_access_token("agent-1", ["workspace:read"], "user")
        create_access_token("agent-2", ["workspace:read"], "user")

        tokens = list_tokens()
        assert len(tokens) >= 2
        subjects = {t["sub"] for t in tokens}
        assert "agent-1" in subjects
        assert "agent-2" in subjects

    def test_jti_is_unique(self):
        """Each token has a unique JTI."""
        from cli.api.auth import create_access_token, decode_token

        t1 = create_access_token("agent-1", ["workspace:read"], "user")
        t2 = create_access_token("agent-1", ["workspace:read"], "user")

        jti1 = decode_token(t1)["jti"]
        jti2 = decode_token(t2)["jti"]
        assert jti1 != jti2

    def test_token_type_enforcement(self):
        """API should reject refresh tokens for API access."""
        # This is tested at the dependency level later, but verify the
        # token payload correctly identifies refresh tokens
        from cli.api.auth import create_refresh_token, decode_token

        token = create_refresh_token("agent-1", ["workspace:read"], "user")
        payload = decode_token(token)
        assert payload["tt"] == "refresh"


if __name__ == "__main__":
    import traceback

    test = TestAuth()
    passed = 0
    failed = 0

    for name in sorted(dir(test)):
        if name.startswith("test_"):
            try:
                test.setup_method()
                getattr(test, name)()
                print(f"  PASS: {name}")
                passed += 1
            except Exception as e:
                print(f"  FAIL: {name}")
                traceback.print_exc()
                failed += 1

    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
