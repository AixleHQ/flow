# Story 15.3: Backend — Update Container Strategies

Status: review

## Story

As a backend developer,
I want container strategies to expose the VS Code Server URL and check its readiness,
so that the frontend can connect to the editor and display it alongside the terminal.

## Acceptance Criteria

1. **AC1: IDE URL in exec result** — `exec(context)` in `agent_auth_strategy.rb` returns `ide_url` alongside existing `websocket_url` and `watcher_url`. Format: `"#{traefik_ws_base}/t/#{route_token}/ide/"`.

2. **AC2: Service readiness** — `services_ports` in `agent_session_strategy.rb` includes port 8443 alongside 7681 and 4040: `[7681, 4040, 8443]`. This ensures the container is not marked "ready" until OpenVSCode Server is listening.

3. **AC3: Serializer update** — `TerminalSessionSerializer` includes `ide_url` attribute computed as `"#{Settings.traefik.http_base}/t/#{route_token}/ide/"` (same pattern as `websocket_url` and `watcher_url`).

4. **AC4: Frontend type update** — `ITerminalSession` interface in `entities/terminal-session/model/types.ts` includes `ideUrl: string | null`.

5. **AC5: ActionCable broadcast** — `ide_url` is included in session state updates via `TerminalSessionChannel.broadcast_update` (automatic — serializer already used by channel).

## Tasks / Subtasks

- [x] Task 1: Add `ide_url` to `exec` method result (AC: #1)
  - [x] 1.1 In `agent_auth_strategy.rb` `exec` method, compute `ide_url` from `traefik_ws_base` and `route_token`
  - [x] 1.2 Add `ide_url` to `context[:result]` hash
  - [x] 1.3 Update log line to include IDE URL
- [x] Task 2: Add 8443 to `services_ports` in `agent_session_strategy.rb` (AC: #2)
  - [x] 2.1 Update `services_ports` from `[7681, 4040]` to `[7681, 4040, 8443]`
- [x] Task 3: Add `ide_url` to `TerminalSessionSerializer` (AC: #3)
  - [x] 3.1 Add `ide_url` to `attributes` list
  - [x] 3.2 Add `ide_url` method: `"#{Settings.traefik.http_base}/t/#{object.route_token}/ide/"` (return nil when `route_token` blank)
- [x] Task 4: Update frontend `ITerminalSession` type (AC: #4)
  - [x] 4.1 Add `ideUrl: string | null;` to `ITerminalSession` interface in `entities/terminal-session/model/types.ts`
- [x] Task 5: Write tests (AC: #1, #2, #3, #5)
  - [x] 5.1 Test `exec` method returns `ide_url` in `agent_auth_strategy_test.rb`
  - [x] 5.2 Test `services_ports` includes 8443 in `agent_session_strategy_test.rb`
  - [x] 5.3 Test serializer returns `ide_url` for session with `route_token`
  - [x] 5.4 Test serializer returns `nil` for session without `route_token`

## Dev Notes

### exec Method — Current State (lines 127-143 of agent_auth_strategy.rb)

```ruby
def exec(context)
  route_token = input[:route_token]
  container_ref = context[:container] || context[:container_id]
  container_id = runtime.container_identifier(container_ref)
  raise "Container not ready for exec" if container_id.blank?

  websocket_url = "#{traefik_ws_base}/t/#{route_token}/tty/ws"
  watcher_url = "#{traefik_ws_base}/t/#{route_token}/fs"

  context[:result] = {
    container_id: container_id,
    container_name: "terminal-#{route_token}",
    websocket_url: websocket_url,
    watcher_url: watcher_url
  }
end
```

Add `ide_url` following the same pattern:

```ruby
ide_url = "#{traefik_ws_base}/t/#{route_token}/ide/"
```

Note the trailing slash — OpenVSCode Server requires it for proper URL resolution.

### services_ports — Current State (line 149-151 of agent_session_strategy.rb)

```ruby
def services_ports
  [ 7681, 4040 ] # ttyd and file watcher
end
```

Update to include 8443. This method is called by `BaseStrategy#wait_for_services` which polls `localhost:{port}` inside the container until all respond.

**Important:** `agent_auth_strategy.rb` also has `services_ports` (line 174-176) returning `[7681, 4040]`. For auth_setup sessions, OpenVSCode Server readiness is less critical (short-lived auth flow), but for consistency add 8443 there too.

### Serializer — Current State (terminal_session_serializer.rb)

The serializer already computes `websocket_url` and `watcher_url` dynamically from `route_token`:

```ruby
def websocket_url
  return nil unless object.route_token.present?
  "#{Settings.traefik.ws_base}/t/#{object.route_token}/tty/ws"
end

def watcher_url
  return nil unless object.route_token.present?
  "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
end
```

Add `ide_url` following the exact same pattern:

```ruby
def ide_url
  return nil unless object.route_token.present?
  "#{Settings.traefik.http_base}/t/#{object.route_token}/ide/"
end
```

Use `http_base` (not `ws_base`) because the IDE is loaded as an iframe via HTTP, not a raw WebSocket. The IDE internally manages its own WebSocket connections.

### ActionCable — Automatic

`TerminalSessionChannel.broadcast_update` calls `TerminalSessionSerializer.new(session).serializable_hash` — so adding `ide_url` to the serializer automatically includes it in ActionCable broadcasts. No changes needed in the channel.

### Frontend Type — ITerminalSession (entities/terminal-session/model/types.ts)

Add after `watcherUrl`:

```typescript
ideUrl: string | null;
```

The `useTerminalSessionChannel` hook receives data from ActionCable, passes through `keysToCamelCase` which converts `ide_url` → `ideUrl`. No hook changes needed.

### AgentSessionStrategy Does NOT Override exec

`AgentSessionStrategy` inherits `exec` from `AgentAuthStrategy` — the `ide_url` addition in parent applies to both auth and session flows automatically.

### What NOT To Change

- Do NOT modify `TerminalSessionWidget.tsx` — that's Story 15.5
- Do NOT add connection token to IDE URL — that's Story 15.4
- Do NOT remove `watcher_url` — that's Story 15.7
- Do NOT modify `docker-compose.yml` or Traefik config
- Do NOT modify `entrypoint.sh` — that was completed in Story 15.2

### Files to Touch

- `web/app/services/container_strategies/agent_auth_strategy.rb` — `exec` method: add `ide_url` to result
- `web/app/services/container_strategies/agent_session_strategy.rb` — `services_ports`: add 8443
- `web/app/serializers/terminal_session_serializer.rb` — add `ide_url` attribute + method
- `web/app/frontend/entities/terminal-session/model/types.ts` — add `ideUrl` field
- `web/test/services/container_strategies/agent_auth_strategy_test.rb` — test `ide_url` in exec result
- `web/test/services/container_strategies/agent_session_strategy_test.rb` — test `services_ports` includes 8443

### Previous Story Intelligence

From Story 15.2:
- Traefik IDE labels already set: `PathPrefix('/t/{token}/ide')`, service port 8443, `terminal-auth` middleware
- `ROUTE_TOKEN` env var passed to container
- `8443/tcp` already in `build_exposed_ports`
- `--server-base-path /t/$ROUTE_TOKEN/ide` configured in entrypoint
- Smoke test confirmed: container responds HTTP 200 at `localhost:8443/t/{token}/ide/`
- IDE accessible through Traefik with 401 (ForwardAuth) — correct behavior

From Story 15.1:
- OpenVSCode Server installed at `/opt/openvscode-server/`, port 8443
- Server startup takes ~1s, `kill -0` health check pattern used

### Testing Patterns

Tests use Minitest with factory_bot and mocha mocks. See existing patterns in:
- `agent_auth_strategy_test.rb` — `build_strategy` helper, mock container with `stubs(:id)`
- `agent_session_strategy_test.rb` — same pattern, tests `services_ports` via `send(:services_ports)`

For serializer test, follow existing test patterns in `test/serializers/` if they exist, or create inline test.

### References

- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.3]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — exec lines 127-143]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — services_ports lines 149-151]
- [Source: web/app/serializers/terminal_session_serializer.rb — websocket_url/watcher_url pattern lines 37-47]
- [Source: web/app/channels/terminal_session_channel.rb — broadcast_update uses serializer lines 65-73]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — ITerminalSession lines 30-62]
- [Source: web/app/frontend/shared/lib/hooks/useTerminalSessionChannel.ts — keysToCamelCase conversion line 96]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Debug Log References
- All 37 targeted tests pass (0 failures, 0 errors)
- Pre-existing `before_cleanup` failures in agent_session_strategy_test excluded (not related to this story)

### Completion Notes List
- AC1: `ide_url` added to `exec` result in `agent_auth_strategy.rb` — format `#{traefik_ws_base}/t/#{route_token}/ide/` with trailing slash
- AC2: Port 8443 added to `services_ports` in `agent_session_strategy.rb` — container readiness now waits for OpenVSCode Server
- AC3: `ide_url` attribute + method added to `TerminalSessionSerializer` using `http_base` (not `ws_base`)
- AC4: `ideUrl: string | null` added to `ITerminalSession` TypeScript interface
- AC5: ActionCable broadcast automatic — serializer used by `TerminalSessionChannel.broadcast_update`

### Change Log
- `agent_auth_strategy.rb`: Added `ide_url` computation + added to `context[:result]`, updated log line
- `agent_session_strategy.rb`: `services_ports` updated from `[7681, 4040]` to `[7681, 4040, 8443]`
- `terminal_session_serializer.rb`: Added `ide_url` to attributes list + `ide_url` method (nil-safe)
- `entities/terminal-session/model/types.ts`: Added `ideUrl: string | null` field
- `agent_auth_strategy_test.rb`: Added test for `ide_url` in exec result
- `agent_session_strategy_test.rb`: Updated test to verify 8443 in services_ports
- Created `test/serializers/terminal_session_serializer_test.rb` with 4 tests (ide_url with/without token, websocket_url, watcher_url)

### File List
- web/app/services/container_strategies/agent_auth_strategy.rb
- web/app/services/container_strategies/agent_session_strategy.rb
- web/app/serializers/terminal_session_serializer.rb
- web/app/frontend/entities/terminal-session/model/types.ts
- web/test/services/container_strategies/agent_auth_strategy_test.rb
- web/test/services/container_strategies/agent_session_strategy_test.rb
- web/test/serializers/terminal_session_serializer_test.rb (new)
