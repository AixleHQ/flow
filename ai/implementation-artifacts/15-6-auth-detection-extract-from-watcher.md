# Story 15.6: Auth Detection — Extract from Watcher

Status: review

## Story

As a platform engineer,
I want auth detection logic preserved as a standalone lightweight service after removing the full watcher from agent sessions,
so that auth_setup sessions still detect when agent authentication is complete without carrying unnecessary watcher dependencies.

## Acceptance Criteria

1. **AC1: Standalone auth endpoint** — A minimal `docker/base/auth-check/index.js` script (~50 lines, pure Node.js `http` module, zero npm dependencies) provides `GET /auth` returning `{ "authenticated": true/false }` and `GET /health` returning `{ "status": "ok" }`. Runs on port 4040.

2. **AC2: Entrypoint conditional start** — `entrypoint.sh` starts auth-check service ONLY when `SESSION_TYPE=auth_setup`. For `SESSION_TYPE=agent_session`, nothing runs on port 4040 (OpenVSCode Server handles file browsing).

3. **AC3: Same contract** — `GET /auth` returns `{ "authenticated": true/false }` — identical to current watcher `/auth` endpoint. Frontend `AgentAuthTerminal` polling unchanged.

4. **AC4: Dockerfile update** — Auth-check script copied to `/opt/auth-check/` in base image. No new npm dependencies.

5. **AC5: Backend services_ports update** — `AgentSessionStrategy#services_ports` updated from `[7681, 4040, 8443]` to `[7681, 8443]` because port 4040 is no longer running in agent_session containers. `AgentAuthStrategy#services_ports` unchanged (`[7681, 4040]`).

6. **AC6: Cleanup handler update** — `entrypoint.sh` cleanup function handles auth-check PID for auth_setup, and does NOT reference watcher PID for agent_session.

## Tasks / Subtasks

- [x] Task 1: Create standalone auth-check script (AC: #1)
  - [x] 1.1 Create `docker/base/auth-check/index.js` with minimal HTTP server
  - [x] 1.2 Implement `GET /auth` handler using same env vars: `SESSION_TYPE`, `AUTH_WATCH_PATH`, `AUTH_REQUIRED_KEYS`
  - [x] 1.3 Implement `checkAuthComplete()` logic (copy from watcher, ~25 lines)
  - [x] 1.4 Implement `GET /health` handler
  - [x] 1.5 Add CORS headers (same as watcher: `Access-Control-Allow-Origin: *`)

- [x] Task 2: Update `entrypoint.sh` for conditional service start (AC: #2, #6)
  - [x] 2.1 Replace unconditional watcher start with `SESSION_TYPE` conditional
  - [x] 2.2 `auth_setup` → start auth-check script on port 4040
  - [x] 2.3 `agent_session` → skip port 4040 entirely (comment explains why)
  - [x] 2.4 Update `cleanup()` function to kill correct PID based on session type
  - [x] 2.5 Update `wait -n` at bottom to use correct PIDs
  - [x] 2.6 OpenVSCode Server conditional — starts only for agent_session, not auth_setup (user requirement)

- [x] Task 3: Update Dockerfile (AC: #4)
  - [x] 3.1 Copy `auth-check/index.js` to `/opt/auth-check/`
  - [x] 3.2 Keep watcher section unchanged (still needed for auth_setup until full deprecation)

- [x] Task 4: Update `AgentSessionStrategy` services_ports (AC: #5)
  - [x] 4.1 Change `services_ports` from `[7681, 4040, 8443]` to `[7681, 8443]`

- [x] Task 5: Update tests (AC: #5)
  - [x] 5.1 Update `agent_session_strategy_test.rb` — services_ports test to expect `[7681, 8443]` (no 4040)

## Dev Notes

### Auth Detection Logic (Extract Target)

The auth detection logic lives in `docker/base/watcher/index.js` in two places:

**1. `GET /auth` handler** (lines 319-338):
```javascript
case '/auth':
  let authenticated = false;
  if (SESSION_TYPE === 'auth_setup' && AUTH_WATCH_PATH) {
    try {
      if (fs.existsSync(AUTH_WATCH_PATH)) {
        const content = fs.readFileSync(AUTH_WATCH_PATH, 'utf-8');
        authenticated = checkAuthComplete(content);
      }
    } catch (e) { /* ... */ }
  }
  res.end(JSON.stringify({ authenticated }));
```

**2. `checkAuthComplete()` function** (lines 350-376):
```javascript
function checkAuthComplete(configContent) {
  if (AUTH_REQUIRED_KEYS.length === 0) return false;
  try {
    const config = JSON.parse(configContent);
    const foundKey = AUTH_REQUIRED_KEYS.find(key => {
      const value = key.split('.').reduce((obj, k) => obj?.[k], config);
      return value !== undefined && value !== null && value !== '';
    });
    return !!foundKey;
  } catch (e) { return false; }
}
```

### Environment Variables Used by Auth Check

All set in `AgentAuthStrategy#build_env_vars`:
- `SESSION_TYPE` — "auth_setup" or "agent_session"
- `AUTH_WATCH_PATH` — agent-specific config file path to monitor (e.g., `/home/coder/.config/claude/settings.json`)
- `AUTH_REQUIRED_KEYS` — comma-separated keys to check (e.g., `"oauthAccount,primaryApiKey"`)

### Frontend Auth Polling (NO CHANGES)

`AgentAuthTerminal.tsx` (lines 142-167) polls auth endpoint:
```typescript
const url = `${baseUrl}/t/${session.routeToken}/fs/auth`;
const response = await fetch(url, { credentials: 'include' });
const data: AuthStatusResponse = await response.json();
if (data.authenticated) { /* ... */ }
```

Route `/t/{token}/fs/auth` goes through Traefik → port 4040. Since auth-check listens on the same port with the same response format, NO frontend changes needed.

### Entrypoint Conditional Logic

Current entrypoint starts watcher unconditionally (lines 68-78):
```bash
cd /opt/watcher
WATCH_DIR="$WORKSPACE" WATCHER_PORT="$WATCHER_PORT" node index.js > /dev/null 2>&1 &
WATCHER_PID=$!
```

Replace with:
```bash
if [ "$SESSION_TYPE" = "auth_setup" ]; then
    WATCH_DIR="$WORKSPACE" WATCHER_PORT="$WATCHER_PORT" node /opt/auth-check/index.js > /dev/null 2>&1 &
    AUTH_CHECK_PID=$!
    sleep 1
    if kill -0 $AUTH_CHECK_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Auth check service ready${NC}"
    else
        echo -e "${YELLOW}⚠️  Auth check service failed${NC}"
    fi
fi
```

For agent_session: nothing starts on port 4040. OpenVSCode Server (port 8443) provides file browsing.

### Cleanup Handler Update

Current cleanup (lines 165-172) kills `$WATCHER_PID`. Update to:
```bash
cleanup() {
    echo -e "${YELLOW}Shutting down...${NC}"
    kill $MITM_PID 2>/dev/null || true
    [ -n "$AUTH_CHECK_PID" ] && kill $AUTH_CHECK_PID 2>/dev/null || true
    kill $OPENVSCODE_PID 2>/dev/null || true
    kill $TTYD_PID 2>/dev/null || true
    exit 0
}
```

### `wait -n` Update

Current: `wait -n $WATCHER_PID $OPENVSCODE_PID $TTYD_PID`

For auth_setup: `wait -n $AUTH_CHECK_PID $OPENVSCODE_PID $TTYD_PID`
For agent_session: `wait -n $OPENVSCODE_PID $TTYD_PID`

Build the PID list dynamically:
```bash
WAIT_PIDS="$OPENVSCODE_PID $TTYD_PID"
[ -n "$AUTH_CHECK_PID" ] && WAIT_PIDS="$AUTH_CHECK_PID $WAIT_PIDS"
wait -n $WAIT_PIDS 2>/dev/null || true
```

### Backend: services_ports Critical Change

`agent_session_strategy.rb` line 149-151:
```ruby
def services_ports
  [ 7681, 4040, 8443 ] # ttyd, file watcher, OpenVSCode Server
end
```

Must change to `[7681, 8443]`. Without this, container readiness checks will fail because port 4040 is no longer open in agent_session containers.

`agent_auth_strategy.rb` line 182-184 stays `[7681, 4040]` — auth_setup still runs auth-check on port 4040.

### Test Update Required

`agent_session_strategy_test.rb` line 148-156:
```ruby
test "services_ports returns ttyd, file watcher, and OpenVSCode Server ports" do
  strategy = build_strategy
  ports = strategy.send(:services_ports)
  assert_includes ports, 7681 # ttyd
  assert_includes ports, 4040 # file watcher    ← REMOVE
  assert_includes ports, 8443 # OpenVSCode Server
end
```

Change to assert only `[7681, 8443]` and add `refute_includes ports, 4040`.

### What NOT to Change

- **Do NOT modify `watcher/index.js`** — it's still the watcher source for auth_setup (used if we want file tree in auth flow; Story 15.7 decides whether to deprecate)
- **Do NOT remove `watcher_url` from serializer** — that's Story 15.7
- **Do NOT modify `AgentAuthTerminal.tsx`** — polling route and contract unchanged
- **Do NOT remove watcher npm deps from Dockerfile** — watcher package still in image for potential auth_setup file tree use
- **Do NOT change Traefik labels** — `/t/{token}/fs/` route still maps to port 4040 in both strategies
- **Do NOT change `agent_auth_strategy.rb` services_ports** — auth_setup still checks port 4040

### Project Structure Notes

- Auth-check script goes to `docker/base/auth-check/index.js` (parallel to existing `docker/base/watcher/index.js`)
- No package.json needed for auth-check (zero npm dependencies, pure Node.js http + fs modules)
- Follows existing pattern: services in `/opt/{service}/` inside container

### Previous Story Intelligence

From Story 15.5:
- `TerminalSessionWidget` already reworked to editor+terminal (no FileTree/FileViewer)
- `watcherUrl` derivation removed from widget
- Auth sessions use `showEditor={false}` → terminal-only mode
- `AgentAuthTerminal` polls `/t/{token}/fs/auth` using `session.routeToken` directly

From Story 15.4:
- `VSCODE_TOKEN` env var pattern: strategy generates → entrypoint writes file → server reads
- Same pattern can inform auth-check: reads env vars set by strategy

From Story 15.3:
- `ide_url` added to exec result, serializer, ActionCable broadcast
- Port 8443 added to services_ports in both strategies

### References

- [Source: docker/base/watcher/index.js#lines 319-376 — auth detection logic to extract]
- [Source: docker/base/entrypoint.sh#lines 68-78 — watcher start section to replace]
- [Source: docker/base/entrypoint.sh#lines 165-172 — cleanup handler to update]
- [Source: docker/base/Dockerfile#lines 72-78 — watcher copy section (add auth-check parallel)]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb#line 149-151 — services_ports to update]
- [Source: web/test/services/container_strategies/agent_session_strategy_test.rb#line 148-156 — test to update]
- [Source: web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx#lines 142-167 — auth polling (no change)]
- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.6]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus

### Debug Log References

None

### Completion Notes List

- Created standalone `auth-check/index.js` (~80 lines, pure Node.js http+fs, zero npm deps)
- `entrypoint.sh` conditionally starts auth-check only for `SESSION_TYPE=auth_setup`
- OpenVSCode Server only starts for `agent_session` (saves ~200MB RAM for auth sessions)
- `AgentSessionStrategy#services_ports` updated: `[7681, 8443]` — no 4040
- Cleanup handler and `wait -n` use dynamic PID lists
- All new/modified tests pass

### File List

- docker/base/auth-check/index.js (new)
- docker/base/entrypoint.sh (modified)
- docker/base/Dockerfile (modified)
- web/app/services/container_strategies/agent_session_strategy.rb (modified)
- web/test/services/container_strategies/agent_session_strategy_test.rb (modified)
