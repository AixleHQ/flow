# Story 15.4: Security — Connection Token Management

Status: review

## Story

As a platform engineer,
I want VS Code Server protected by a per-session connection token,
so that only authorized users can access the editor even if someone guesses the route URL.

## Acceptance Criteria

1. **AC1: Token generation** — `build_env_vars` in `agent_auth_strategy.rb` generates a random 32-byte hex token (`SecureRandom.hex(32)`) and passes it as `VSCODE_TOKEN` env var to the container.

2. **AC2: Token file in entrypoint** — `entrypoint.sh` checks for `VSCODE_TOKEN` env var. If set, writes it to `/tmp/.vscode-connection-token` (permissions 0600) and starts OpenVSCode Server with `--connection-token-file /tmp/.vscode-connection-token` instead of `--without-connection-token`.

3. **AC3: Fallback** — When `VSCODE_TOKEN` is not set, entrypoint starts with `--without-connection-token` (backward compatibility for local testing, auth_setup sessions).

4. **AC4: Token in IDE URL** — `TerminalSessionSerializer#ide_url` appends `?tkn={token}` to the IDE URL. OpenVSCode Server accepts this query parameter for authentication. Token is stored in `TerminalSession#metadata["vscode_token"]`.

5. **AC5: Token isolation** — Each session gets a unique token. Token is ephemeral (not stored in AgentCredential, only in session metadata). Token never appears in logs.

6. **AC6: Smoke test** — IDE accessible at `http://localhost/t/{token}/ide/?tkn={vscode_token}`. Without `?tkn=` parameter, server returns 403.

## Tasks / Subtasks

- [x] Task 1: Generate VSCODE_TOKEN and pass to container (AC: #1, #5)
  - [x] 1.1 Generate `SecureRandom.hex(32)` in `build_env_vars`
  - [x] 1.2 Add `"VSCODE_TOKEN" => vscode_token` to env vars hash
  - [x] 1.3 Store token in session metadata: `session.update_column(:metadata, metadata.merge("vscode_token" => vscode_token))`
  - [x] 1.4 Ensure token is NOT logged
- [x] Task 2: Update entrypoint.sh for connection token file (AC: #2, #3)
  - [x] 2.1 Check `VSCODE_TOKEN` env var before OpenVSCode Server startup
  - [x] 2.2 If set: write to `/tmp/.vscode-connection-token`, chmod 0600, use `--connection-token-file`
  - [x] 2.3 If not set: use `--without-connection-token` (existing behavior)
- [x] Task 3: Update serializer to include token in IDE URL (AC: #4)
  - [x] 3.1 Read `vscode_token` from `object.metadata["vscode_token"]`
  - [x] 3.2 Append `?tkn=#{token}` to `ide_url` when token present
- [x] Task 4: Write tests (AC: #1, #2, #4, #5)
  - [x] 4.1 Test `build_env_vars` includes `VSCODE_TOKEN` with 64-char hex value
  - [x] 4.2 Test token is stored in session metadata
  - [x] 4.3 Test serializer `ide_url` includes `?tkn=` when metadata has token
  - [x] 4.4 Test serializer `ide_url` has no `?tkn=` when metadata lacks token

## Dev Notes

### Token Generation — Where and How

Generate token in `build_env_vars` because this is the earliest point where we know the session and can persist metadata. The token must be available both in the container (env var) and in the serializer (metadata).

```ruby
def build_env_vars
  session = TerminalSession.find(input[:session_id])
  agent_service = AgentCredentialsService.for(input[:agent_type])

  # Generate VS Code connection token
  vscode_token = SecureRandom.hex(32)
  persist_vscode_token(session, vscode_token)

  env_vars = {
    # ... existing vars ...
    "VSCODE_TOKEN" => vscode_token,
    # ...
  }
  # ... rest of method
end

private

def persist_vscode_token(session, token)
  meta = session.metadata || {}
  meta["vscode_token"] = token
  session.update_column(:metadata, meta)
end
```

**Important:** `update_column` bypasses callbacks — this is intentional to avoid triggering ActionCable broadcast before the container is ready.

### AgentSessionStrategy Override

`AgentSessionStrategy#build_env_vars` calls `super` and then modifies the result. The `VSCODE_TOKEN` env var from parent will be included automatically. But `persist_vscode_token` is called in the parent, so both auth and session flows get tokens.

Consider: for `auth_setup` sessions, the token is less critical (short-lived, user is actively authenticating). But for consistency, generate token for all session types.

### Entrypoint Changes (docker/base/entrypoint.sh)

Current OpenVSCode Server startup (after Story 15.2):

```bash
OPENVSCODE_ARGS="--host 0.0.0.0 --port $OPENVSCODE_PORT --without-connection-token --default-folder $WORKSPACE --disable-telemetry"
if [ -n "$ROUTE_TOKEN" ]; then
    OPENVSCODE_ARGS="$OPENVSCODE_ARGS --server-base-path /t/$ROUTE_TOKEN/ide"
fi
```

Updated:

```bash
OPENVSCODE_ARGS="--host 0.0.0.0 --port $OPENVSCODE_PORT --default-folder $WORKSPACE --disable-telemetry"

if [ -n "$VSCODE_TOKEN" ]; then
    echo -n "$VSCODE_TOKEN" > /tmp/.vscode-connection-token
    chmod 600 /tmp/.vscode-connection-token
    OPENVSCODE_ARGS="$OPENVSCODE_ARGS --connection-token-file /tmp/.vscode-connection-token"
else
    OPENVSCODE_ARGS="$OPENVSCODE_ARGS --without-connection-token"
fi

if [ -n "$ROUTE_TOKEN" ]; then
    OPENVSCODE_ARGS="$OPENVSCODE_ARGS --server-base-path /t/$ROUTE_TOKEN/ide"
fi
```

Key points:
- `--without-connection-token` removed from base args, added conditionally
- Token file written with `echo -n` (no trailing newline)
- `chmod 600` — only container user can read
- `--connection-token-file` is preferred over `--connection-token` (avoids `ps` leaking secret)

### Serializer Update (terminal_session_serializer.rb)

After Story 15.3 adds `ide_url`, update it to include token:

```ruby
def ide_url
  return nil unless object.route_token.present?

  base_url = "#{Settings.traefik.http_base}/t/#{object.route_token}/ide/"
  token = object.metadata&.dig("vscode_token")
  token.present? ? "#{base_url}?tkn=#{token}" : base_url
end
```

### Security Considerations

1. **Token in URL** — OpenVSCode Server expects `?tkn=` as the auth mechanism. This is standard for VS Code Server. The URL is only sent to the authenticated user via ActionCable/API.
2. **No logging** — Token must NOT appear in Rails logs. `build_env_vars` returns `"KEY=VALUE"` strings which get logged by Docker — but `VSCODE_TOKEN` will be in env vars list which is not typically logged by our code. Add explicit exclusion if needed.
3. **Metadata storage** — Token in session metadata is acceptable: metadata is only accessible to the session owner (Pundit policy) and admin. It's not exposed in list views.
4. **Ephemeral** — Token dies with the container. No persistent secret management needed.

### Dependency on Story 15.3

This story depends on Story 15.3 adding `ide_url` to the serializer. If implementing before 15.3, the serializer `ide_url` method must be created from scratch (not just modified).

Tasks can be implemented independently:
- Tasks 1-2 (token generation + entrypoint) work without 15.3
- Task 3 (serializer token in URL) requires 15.3's `ide_url` method to exist

### What NOT To Change

- Do NOT modify Traefik labels or middleware — ForwardAuth handles route-level auth, connection token is IDE-level auth
- Do NOT store token in `AgentCredential` — it's per-session, not per-agent
- Do NOT modify frontend components — frontend just opens the `ideUrl` as-is (token embedded in URL)
- Do NOT add token rotation or refresh — sessions are short-lived

### Files to Touch

- `web/app/services/container_strategies/agent_auth_strategy.rb` — generate token, pass as env var, persist to metadata
- `docker/base/entrypoint.sh` — write token file, conditional `--connection-token-file` flag
- `web/app/serializers/terminal_session_serializer.rb` — append `?tkn=` to `ide_url`
- `web/test/services/container_strategies/agent_auth_strategy_test.rb` — test token env var and metadata persistence

### Previous Story Intelligence

From Story 15.2:
- `ROUTE_TOKEN` env var pattern already established — follow same approach for `VSCODE_TOKEN`
- Entrypoint already uses conditional `OPENVSCODE_ARGS` building
- `--without-connection-token` flag currently hardcoded — needs to become conditional

From Story 15.1:
- OpenVSCode Server `--help` confirmed `--connection-token-file` flag available
- Server uses file-based token (recommended over `--connection-token` CLI arg)

### References

- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.4]
- [Source: ai/vscode-server-and-monaco-editor.md#Security considerations — connection-token-file recommendation]
- [Source: web/app/services/container_strategies/agent_auth_strategy.rb — build_env_vars lines 71-97]
- [Source: docker/base/entrypoint.sh — OpenVSCode Server startup lines 83-98]
- [Source: web/app/serializers/terminal_session_serializer.rb — websocket_url/watcher_url pattern lines 37-47]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — metadata field line 42]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Debug Log References
- 39 targeted tests pass (0 failures, 0 errors)

### Completion Notes List
- AC1: `SecureRandom.hex(32)` generates 64-char hex token, passed as `VSCODE_TOKEN` env var
- AC2: `entrypoint.sh` writes token to `/tmp/.vscode-connection-token` (chmod 600), uses `--connection-token-file`
- AC3: Fallback — `--without-connection-token` when `VSCODE_TOKEN` not set
- AC4: Serializer appends `?tkn={token}` to `ide_url` when `metadata["vscode_token"]` present
- AC5: Each session gets unique token via `SecureRandom.hex(32)`, stored in `session.metadata` only (not AgentCredential), never logged
- AC6: Smoke test requires Docker image rebuild + new session — `?tkn=` required for access, 403 without it
- Token persisted via `update_column` to bypass ActionCable broadcast before container ready

### Change Log
- `agent_auth_strategy.rb`: Generate `vscode_token`, add `VSCODE_TOKEN` to env vars, `persist_vscode_token` private method
- `entrypoint.sh`: Conditional `--connection-token-file` vs `--without-connection-token`
- `terminal_session_serializer.rb`: `ide_url` appends `?tkn=` from `metadata["vscode_token"]`
- `agent_auth_strategy_test.rb`: 2 new tests — VSCODE_TOKEN env var format, metadata persistence
- `terminal_session_serializer_test.rb`: Updated ide_url tests — with/without token in metadata

### File List
- web/app/services/container_strategies/agent_auth_strategy.rb
- docker/base/entrypoint.sh
- web/app/serializers/terminal_session_serializer.rb
- web/test/services/container_strategies/agent_auth_strategy_test.rb
- web/test/serializers/terminal_session_serializer_test.rb
