"""
Tests for ADP-OS REST API — server endpoints.

Verifies:
  - Login flow (API key → access + refresh tokens)
  - Token refresh (rotating refresh tokens)
  - Token revocation
  - RBAC scope enforcement (403 on missing scopes)
  - Admin-only endpoint protection
  - Token info endpoint

Uses FastAPI TestClient — no actual pwsh.exe or ADP-OS needed.
Run: python tests/test-api-server.py
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestAPIServer:
    """Integration tests for the REST API server."""

    @classmethod
    def setup_class(cls):
        """Set up TestClient and register a bootstrap API key."""
        from cli.api import auth
        # Reset state
        auth._revoked_jtis.clear()
        auth._consumed_refresh_jtis.clear()
        auth._api_keys.clear()
        auth._issued_tokens.clear()
        auth.JWT_SECRET = "supertestsecretkey-" * 4  # 88 bytes
        # Register a test API key
        auth.register_api_key("test-api-key-bootstrap", owner="test-admin")

        from cli.api.server import app
        from fastapi.testclient import TestClient
        cls.client = TestClient(app)

    # -------------------------------------------------------------------
    # Login flow
    # -------------------------------------------------------------------

    def test_login_success(self):
        """Login with valid API key returns access + refresh tokens."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert data["role"] == "user"
        assert len(data["scopes"]) > 0
        assert data["expires_in"] == 3600

    def test_login_invalid_api_key(self):
        """Login with invalid API key returns 401."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "wrong-key",
            "subject": "agent-1",
            "role": "user",
        })
        assert resp.status_code == 401

    def test_login_invalid_role(self):
        """Login with invalid role returns 400."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "superadmin",
        })
        assert resp.status_code == 400

    def test_login_admin_role(self):
        """Login as admin returns admin:* scopes."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "admin-1",
            "role": "admin",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["role"] == "admin"
        assert "admin:*" in data["scopes"]

    def test_login_scoped(self):
        """Login with explicit scope subset."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "limited-agent",
            "role": "user",
            "scopes": ["workspace:read"],
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["scopes"] == ["workspace:read"]

    def test_login_scopes_outside_role(self):
        """Login requesting admin scope as user returns 400."""
        resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "hacker",
            "role": "user",
            "scopes": ["admin:*"],
        })
        assert resp.status_code == 400

    # -------------------------------------------------------------------
    # Token info
    # -------------------------------------------------------------------

    def test_me_endpoint(self):
        """GET /v1/auth/me returns token info."""
        # First login
        login_resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        token = login_resp.json()["access_token"]

        # Then check /me
        resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["sub"] == "agent-1"
        assert data["role"] == "user"
        assert data["tt"] == "access"

    # -------------------------------------------------------------------
    # Token refresh
    # -------------------------------------------------------------------

    def test_refresh_success(self):
        """Refresh flow: old tokens invalidated, new tokens issued."""
        # Login
        login_resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        old_data = login_resp.json()
        old_refresh = old_data["refresh_token"]

        # Refresh
        refresh_resp = self.client.post("/v1/auth/refresh", json={
            "refresh_token": old_refresh,
        })
        assert refresh_resp.status_code == 200, refresh_resp.text
        new_data = refresh_resp.json()
        assert "access_token" in new_data
        assert "refresh_token" in new_data
        assert new_data["access_token"] != old_data["access_token"]
        assert new_data["refresh_token"] != old_refresh

        # Old refresh token should be consumed (single-use)
        retry_resp = self.client.post("/v1/auth/refresh", json={
            "refresh_token": old_refresh,
        })
        assert retry_resp.status_code == 401

    def test_refresh_with_access_token_fails(self):
        """Access tokens cannot be used for refresh."""
        login_resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        access = login_resp.json()["access_token"]

        resp = self.client.post("/v1/auth/refresh", json={
            "refresh_token": access,
        })
        assert resp.status_code == 401

    def test_refresh_invalid_token(self):
        """Invalid refresh token returns 401."""
        resp = self.client.post("/v1/auth/refresh", json={
            "refresh_token": "not.a.token",
        })
        assert resp.status_code == 401

    # -------------------------------------------------------------------
    # Token revocation
    # -------------------------------------------------------------------

    def test_revoke_token(self):
        """Revoked access token is rejected on next request."""
        login_resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        token = login_resp.json()["access_token"]

        # Revoke
        revoke_resp = self.client.post(
            "/v1/auth/revoke",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert revoke_resp.status_code == 200
        assert revoke_resp.json()["revoked"] is True

        # Token should now be rejected
        me_resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert me_resp.status_code == 401

    # -------------------------------------------------------------------
    # RBAC scope enforcement
    # -------------------------------------------------------------------

    def _get_token(self, subject="agent-1", role="user",
                   scopes=None):
        """Helper: get an access token."""
        body = {
            "api_key": "test-api-key-bootstrap",
            "subject": subject,
            "role": role,
        }
        if scopes:
            body["scopes"] = scopes
        resp = self.client.post("/v1/auth/login", json=body)
        assert resp.status_code == 200, resp.text
        return resp.json()["access_token"]

    def test_platform_endpoint_with_valid_scope(self):
        """User with platform:read can access platform endpoints."""
        token = self._get_token()
        resp = self.client.get(
            "/v1/platform/status",
            headers={"Authorization": f"Bearer {token}"},
        )
        # Will fail at _run_adp level (no pwsh), but auth should pass
        # 500 = auth OK, but _run_adp failed (expected in test)
        assert resp.status_code != 401
        assert resp.status_code != 403

    def test_runtime_endpoint_requires_write_scope(self):
        """POST runtime up without runtime:write scope returns 403."""
        token = self._get_token(scopes=["workspace:read"])
        resp = self.client.post(
            "/v1/runtimes/agent/up?plan_only=true",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403

    def test_admin_endpoint_as_user_returns_403(self):
        """User cannot access admin endpoints."""
        token = self._get_token(role="user")
        resp = self.client.get(
            "/v1/admin/health",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 403

    def test_admin_endpoint_as_admin_succeeds(self):
        """Admin can access admin endpoints."""
        token = self._get_token(role="admin")
        resp = self.client.get(
            "/v1/admin/health",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "healthy"

    def test_admin_list_tokens(self):
        """Admin can list issued tokens."""
        # Create some tokens first
        self._get_token("agent-1", "user")
        self._get_token("agent-2", "user")

        token = self._get_token("admin-1", "admin")
        resp = self.client.get(
            "/v1/admin/tokens",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] >= 2

    def test_admin_create_token(self):
        """Admin can create tokens for any subject."""
        token = self._get_token("admin-1", "admin")
        resp = self.client.post(
            "/v1/admin/tokens",
            headers={"Authorization": f"Bearer {token}"},
            json={"subject": "new-agent", "role": "user"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["role"] == "user"

    def test_admin_revoke_token(self):
        """Admin can revoke a token by JTI."""
        admin_token = self._get_token("admin-1", "admin")
        user_token = self._get_token("agent-1", "user")

        # Get JTI from /me
        me_resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {user_token}"},
        )
        jti = me_resp.json()["jti"]

        # Revoke it
        revoke_resp = self.client.delete(
            f"/v1/admin/tokens/{jti}",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        assert revoke_resp.status_code == 200

        # User token should now be invalid
        me_after = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {user_token}"},
        )
        assert me_after.status_code == 401

    def test_admin_revoke_by_subject(self):
        """Admin can revoke all tokens for a subject."""
        admin_token = self._get_token("admin-1", "admin")
        t1 = self._get_token("victim-1", "user")
        t2 = self._get_token("victim-2", "user")

        resp = self.client.delete(
            "/v1/admin/tokens/subject/victim-1",
            headers={"Authorization": f"Bearer {admin_token}"},
        )
        assert resp.status_code == 200

        # victim-1 token should be revoked
        me1 = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {t1}"},
        )
        assert me1.status_code == 401

        # victim-2 should still work
        me2 = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {t2}"},
        )
        assert me2.status_code == 200

    # -------------------------------------------------------------------
    # Missing/auth errors
    # -------------------------------------------------------------------

    def test_no_auth_header(self):
        """Request without Authorization header returns 401."""
        resp = self.client.get("/v1/auth/me")
        assert resp.status_code == 401

    def test_empty_token(self):
        """Request with empty token returns 401."""
        resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": "Bearer "},
        )
        assert resp.status_code == 401

    def test_invalid_token(self):
        """Request with invalid token returns 401."""
        resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": "Bearer invalid.token.here"},
        )
        assert resp.status_code == 401

    def test_refresh_token_as_access_token(self):
        """Using refresh token for API access returns 401."""
        login_resp = self.client.post("/v1/auth/login", json={
            "api_key": "test-api-key-bootstrap",
            "subject": "agent-1",
            "role": "user",
        })
        refresh = login_resp.json()["refresh_token"]

        resp = self.client.get(
            "/v1/auth/me",
            headers={"Authorization": f"Bearer {refresh}"},
        )
        assert resp.status_code == 401


if __name__ == "__main__":
    import traceback

    TestAPIServer.setup_class()

    test = TestAPIServer()
    passed = 0
    failed = 0

    for name in sorted(dir(test)):
        if name.startswith("test_"):
            try:
                getattr(test, name)()
                print(f"  PASS: {name}")
                passed += 1
            except Exception as e:
                print(f"  FAIL: {name}")
                traceback.print_exc()
                failed += 1

    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
