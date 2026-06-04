# ADP-OS REST API

REST API layer for ADP-OS platform management with JWT authentication and RBAC.

## Quick Start

```bash
# Install dependencies
pip install -r cli/api/requirements.txt

# Set required env vars (optional — auto-generated if not set)
export ADP_JWT_SECRET="your-secret-at-least-32-bytes-long"
export ADP_API_KEY="your-bootstrap-api-key"

# Start the server
python cli/api/server.py
# Server runs at http://localhost:8000
# OpenAPI docs at http://localhost:8000/docs
```

## Authentication

### 1. Login with API key

```bash
curl -X POST http://localhost:8000/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "api_key": "your-bootstrap-api-key",
    "subject": "agent-1",
    "role": "user"
  }'
```

Response:
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "token_type": "bearer",
  "expires_in": 3600,
  "scopes": ["platform:read", "workspace:read", "workspace:write", "runtime:read", "runtime:write"],
  "role": "user"
}
```

### 2. Use the access token

```bash
curl http://localhost:8000/v1/platform/status \
  -H "Authorization: Bearer eyJ..."
```

### 3. Refresh when expired

```bash
curl -X POST http://localhost:8000/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "eyJ..."}'
```

## API Endpoints

### Platform
- `GET /v1/platform/status?runtime=agent` — Platform and runtime health
- `GET /v1/platform/doctor` — Run diagnostics
- `GET /v1/platform/capabilities` — Platform capabilities

### Workspaces
- `GET /v1/workspaces` — List workspace projects
- `GET /v1/workspaces/status` — Workspace readiness
- `GET /v1/workspaces/dashboard` — Dashboard with task lifecycle
- `GET /v1/workspaces/recipes` — List recipes
- `GET /v1/workspaces/report` — Markdown report
- `GET /v1/workspaces/{project}` — Single project view
- `POST /v1/workspaces/{project}/create?plan_only=true` — Create workspace dirs
- `GET /v1/workspaces/{project}/open` — Entry guidance
- `GET /v1/workspaces/{project}/sync` — Sync guidance
- `POST /v1/workspaces/{project}/close?plan_only=true` — Close workspace

### Runtimes
- `POST /v1/runtimes/{runtime}/up?plan_only=true` — Start VM
- `POST /v1/runtimes/{runtime}/down?plan_only=true&force=false` — Destroy VM
- `POST /v1/runtimes/{runtime}/stop` — Graceful stop

### Sync
- `GET /v1/sync/status` — Sync session status
- `POST /v1/sync/{runtime}/stop` — Stop sync session

### Admin (requires admin role)
- `POST /v1/admin/tokens` — Issue tokens for users
- `GET /v1/admin/tokens` — List issued tokens
- `DELETE /v1/admin/tokens/{jti}` — Revoke a token
- `DELETE /v1/admin/tokens/subject/{subject}` — Revoke all tokens for subject
- `GET /v1/admin/health` — API server health

## RBAC Roles

| Role | Default Scopes |
|------|---------------|
| `admin` | `admin:*` (all operations) |
| `user` | `platform:read`, `workspace:read`, `workspace:write`, `runtime:read`, `runtime:write` |

## Architecture

Shares the same `_run_adp()` subprocess wrapper as the MCP server (`cli/mcp/server.py`).
The REST API wraps ADP-OS PowerShell CLI commands via `pwsh -File adp.ps1`.

```
Agent / Client
    │  JWT Bearer token
    ▼
FastAPI REST Server  (cli/api/server.py)
    │  subprocess.run
    ▼
pwsh -File cli/adp.ps1  (ADP-OS PowerShell CLI)
    │
    ▼
VMware Workstation → Ubuntu Server VMs
```

## Security

- JWT HS256 with minimum 32-byte secret
- Access tokens: 1 hour expiry
- Refresh tokens: 7 day expiry, single-use (rotated on refresh)
- JTI-based revocation
- In-memory token store (cleared on restart)
- All destructive endpoints default to `plan_only=true`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ADP_JWT_SECRET` | Recommended | JWT signing secret (min 32 bytes; auto-generated if not set) |
| `ADP_API_KEY` | Required for login | Bootstrap API key for initial authentication |
| `ADP_HOME` | Auto-detected | ADP-OS installation directory |
| `ADP_HOME_WIN` | Auto-detected | ADP-OS Windows path (for pwsh.exe invocation) |
