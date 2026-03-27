# Story 15.2: Traefik Routing for VS Code Server

Status: review

## Story

As a platform engineer,
I want VS Code Server traffic routed through Traefik with WebSocket support,
so that the editor is accessible via the same domain as terminal without exposing raw ports.

## Acceptance Criteria

1. **AC1: Traefik labels** — `traefik_labels` method in `agent_auth_strategy.rb` includes IDE router+service labels. Route: `PathPrefix('/t/{route_token}/ide')`, service port: 8443. No `StripPrefix` middleware (server handles path via `--server-base-path`).

2. **AC2: server-base-path** — Entrypoint starts OpenVSCode Server with `--server-base-path /t/{ROUTE_TOKEN}/ide` when `ROUTE_TOKEN` env var is set. Falls back to no base path when `ROUTE_TOKEN` is unset (local testing).

3. **AC3: ROUTE_TOKEN env var** — `build_env_vars` in `agent_auth_strategy.rb` passes `ROUTE_TOKEN={route_token}` to the container so entrypoint can use it.

4. **AC4: WebSocket support** — Traefik correctly proxies WebSocket upgrade requests for the IDE route. No additional middleware needed (Traefik v3 handles WebSocket upgrade natively for HTTP routers).

5. **AC5: Exposed ports** — `build_exposed_ports` in `agent_auth_strategy.rb` includes `"8443/tcp" => {}` alongside existing 7681 and 4040.

6. **AC6: Smoke test** — OpenVSCode Server accessible via Traefik at `http://localhost/t/{token}/ide/` in a running session. Editor loads, WebSocket connects, file tree visible.

## Tasks / Subtasks

- [x] Task 1: Add IDE Traefik labels to agent_auth_strategy.rb (AC: #1)
  - [x] 1.1 Add IDE router label: `PathPrefix('/t/{route_token}/ide')`
  - [x] 1.2 Add IDE service label: port 8443
  - [x] 1.3 Add `terminal-auth` middleware to IDE router (same auth as tty/fs)
  - [x] 1.4 Do NOT add StripPrefix — server handles path via `--server-base-path`
- [x] Task 2: Pass ROUTE_TOKEN env var to container (AC: #3)
  - [x] 2.1 Add `"ROUTE_TOKEN" => input[:route_token]` to `build_env_vars` hash
- [x] Task 3: Add 8443 to exposed ports (AC: #5)
  - [x] 3.1 Add `"8443/tcp" => {}` to `build_exposed_ports` hash
- [x] Task 4: Update entrypoint.sh to use --server-base-path (AC: #2)
  - [x] 4.1 Read `ROUTE_TOKEN` env var in OpenVSCode Server startup section
  - [x] 4.2 If `ROUTE_TOKEN` is set, add `--server-base-path "/t/$ROUTE_TOKEN/ide"` flag
  - [x] 4.3 If `ROUTE_TOKEN` is unset, start without `--server-base-path` (local/test mode)
- [ ] Task 5: Verify routing works end-to-end (AC: #4, #6)
  - [ ] 5.1 Start a session via the app, note the route_token
  - [ ] 5.2 Access `http://localhost/t/{token}/ide/` in browser
  - [ ] 5.3 Verify VS Code editor loads, WebSocket connects
  - [ ] 5.4 Verify ttyd terminal still works at `/t/{token}/tty/`
  - [ ] 5.5 Verify watcher still works at `/t/{token}/fs/`

## Dev Notes

### Architecture Decision: --server-base-path over StripPrefix

OpenVSCode Server is a complex SPA with WebSocket connections, internal routing, and static assets that reference paths relative to the server base. Using Traefik `StripPrefix` middleware would break internal links because the server wouldn't know its URL prefix.

`--server-base-path` is the native VS Code Server solution: the server generates all URLs (HTML, JS, CSS, WebSocket endpoints) with the correct base path prefix. This means:
- Traefik routes the PathPrefix to the container — **no strip needed**
- The server itself serves content under `/t/{token}/ide/...`
- WebSocket upgrade requests go to `/t/{token}/ide/...` and work correctly
- All static assets load from the correct prefixed URLs

### Traefik Labels Pattern

Current TTY and FS routes in `traefik_labels` method (lines 265-283 of `agent_auth_strategy.rb`):

```ruby
# TTY router (ttyd terminal)
"traefik.http.routers.#{router_name}-tty.rule" => "PathPrefix(`/t/#{route_token}/tty`)",
"traefik.http.routers.#{router_name}-tty.middlewares" => "terminal-auth,#{router_name}-tty-strip",
"traefik.http.middlewares.#{router_name}-tty-strip.stripprefix.prefixes" => "/t/#{route_token}/tty",
"traefik.http.routers.#{router_name}-tty.service" => "#{router_name}-tty",
"traefik.http.services.#{router_name}-tty.loadbalancer.server.port" => "7681",
```

New IDE route follows same pattern but **without StripPrefix**:

```ruby
# IDE router (OpenVSCode Server)
"traefik.http.routers.#{router_name}-ide.rule" => "PathPrefix(`/t/#{route_token}/ide`)",
"traefik.http.routers.#{router_name}-ide.middlewares" => "terminal-auth",
"traefik.http.routers.#{router_name}-ide.service" => "#{router_name}-ide",
"traefik.http.services.#{router_name}-ide.loadbalancer.server.port" => "8443",
```

No CORS middleware needed for IDE (unlike FS which uses `terminal-cors`) — the IDE is served as an iframe from the same domain.

### Entrypoint Change

Update the OpenVSCode Server section in `docker/base/entrypoint.sh`. The `ROUTE_TOKEN` env var is set by the strategy. When present, it configures the server to serve under that path:

```bash
OPENVSCODE_PORT="${OPENVSCODE_PORT:-8443}"

OPENVSCODE_ARGS="--host 0.0.0.0 --port $OPENVSCODE_PORT --without-connection-token --default-folder $WORKSPACE --disable-telemetry"
if [ -n "$ROUTE_TOKEN" ]; then
    OPENVSCODE_ARGS="$OPENVSCODE_ARGS --server-base-path /t/$ROUTE_TOKEN/ide"
fi

/opt/openvscode-server/bin/openvscode-server $OPENVSCODE_ARGS > /dev/null 2>&1 &
OPENVSCODE_PID=$!
```

### build_env_vars Change

In `agent_auth_strategy.rb`, add `ROUTE_TOKEN` to the env vars hash (line ~76 area):

```ruby
"ROUTE_TOKEN" => input[:route_token]
```

This is already used for Traefik label generation, so it's always present.

### build_exposed_ports Change

In `agent_auth_strategy.rb`, add 8443:

```ruby
def build_exposed_ports
  {
    "7681/tcp" => {},  # ttyd
    "4040/tcp" => {},  # watcher
    "8443/tcp" => {}   # OpenVSCode Server
  }
end
```

### AgentSessionStrategy Inheritance

`AgentSessionStrategy` inherits from `AgentAuthStrategy` and calls `super` in `build_env_vars` and `build_labels`. It does NOT override `build_exposed_ports` or `traefik_labels`. This means:
- Traefik labels: inherited automatically (no changes to session strategy)
- Env vars: inherited via `super` (no changes to session strategy)
- Exposed ports: inherited (no changes to session strategy)

### Traefik Middleware Reference

From `docker-compose.yml` (lines 150-156):
- `terminal-auth` — ForwardAuth to `http://web:4000/api/v1/internal/ws_auth` — verifies session cookie
- `terminal-cors` — CORS headers for direct API calls (not needed for iframe-embedded IDE)

### WebSocket Handling

Traefik v3 handles WebSocket upgrade natively — no special middleware needed. When a client sends `Upgrade: websocket` header, Traefik automatically establishes a WebSocket tunnel. This is how ttyd already works through Traefik without any WebSocket-specific configuration.

### What NOT To Change

- Do NOT modify `agent_session_strategy.rb` — it inherits everything from `agent_auth_strategy.rb`
- Do NOT add StripPrefix middleware for IDE route
- Do NOT modify Traefik config in `docker-compose.yml`
- Do NOT add connection token logic — that's Story 15.4
- Do NOT add `ide_url` to exec result — that's Story 15.3

### Files to Touch

- `web/app/services/container_strategies/agent_auth_strategy.rb` — Traefik labels, env var, exposed ports
- `docker/base/entrypoint.sh` — `--server-base-path` flag

### Previous Story Intelligence

From Story 15.1:
- OpenVSCode Server installed at `/opt/openvscode-server/`, runs on port 8443
- Entrypoint starts it with `--host 0.0.0.0 --port 8443 --without-connection-token --default-folder /workspace --disable-telemetry`
- Server confirmed responding HTTP 200 at `localhost:8443`
- `--server-base-path` flag is available (confirmed via `--help` output)

### References

- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.2]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — traefik_labels lines 265-283]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — build_env_vars lines 71-97]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — build_exposed_ports lines 117-122]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — inherits, build_labels line 64-66]
- [Source: docker/base/entrypoint.sh — OpenVSCode Server startup lines 80-98]
- [Source: docker-compose.yml — Traefik middleware definitions lines 147-156]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus (via Cursor)

### Debug Log References

None — clean implementation, all tests passed on first run.

### Completion Notes List

- Added IDE Traefik labels to `traefik_labels` method: PathPrefix router, terminal-auth middleware (no StripPrefix), service port 8443
- Added `ROUTE_TOKEN` env var to `build_env_vars` so entrypoint can configure `--server-base-path`
- Added `8443/tcp` to `build_exposed_ports` for OpenVSCode Server
- Updated entrypoint.sh to conditionally pass `--server-base-path /t/$ROUTE_TOKEN/ide` when ROUTE_TOKEN is set; falls back to no base path for local/test mode
- Added 6 unit tests: IDE Traefik labels (PathPrefix, middleware, service port, no StripPrefix), ROUTE_TOKEN env var, exposed port 8443
- All 31 auth strategy tests pass (64 assertions), 0 regressions
- Pre-existing failures in agent_session_strategy_test.rb (3 tests) confirmed unrelated to this story
- Task 5 (manual smoke test) left unchecked — requires running session and browser verification

### Change Log

- 2026-02-20: Implemented Traefik routing for VS Code Server (Tasks 1-4), added unit tests

### File List

- web/app/services/container_strategies/agent_auth_strategy.rb (modified)
- docker/base/entrypoint.sh (modified)
- web/test/services/container_strategies/agent_auth_strategy_test.rb (modified)
