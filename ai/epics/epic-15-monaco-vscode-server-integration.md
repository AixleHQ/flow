# Epic 15: Monaco Editor + VS Code Server Integration

> Replace custom file watcher (Node.js/chokidar on port 4040) and read-only file viewer (FileTree + FileViewer React components) with OpenVSCode Server, providing a full IDE editing experience inside agent session containers.

**Phase:** 8 (Depends on: Epic 9 Agent Sessions Core)

**User Outcome:** Users get a full VS Code editing experience (file tree, syntax-highlighted editor, search, multi-tab editing) directly in the browser within agent sessions, instead of a read-only file viewer.

**Research:** [ai/vscode-server-and-monaco-editor.md](../vscode-server-and-monaco-editor.md)

---

## Context & Decision

### Current State

- **File Watcher** (`docker/base/watcher/index.js`) — Node.js service (chokidar + ws + http) on port 4040. Provides:
  - `GET /tree` — directory tree JSON
  - `GET /file?path=...` — file content (text/base64)
  - `GET /auth` — auth status check for auth_setup sessions
  - WebSocket — real-time fs events (add/change/unlink)
- **FileTree.tsx** — React component using `react-accessible-treeview`, connected to watcher WebSocket
- **FileViewer.tsx** — Read-only viewer with CodeViewer (syntax highlighting via `react-syntax-highlighter`), PdfViewer, ImageViewer
- **TerminalSessionWidget.tsx** — Orchestrates FileTree + FileViewer + Terminal (ttyd iframe) in resizable panels

### Chosen Approach: OpenVSCode Server as In-Container Service

Per research, OpenVSCode Server (Gitpod) is the best fit:
- MIT license, 5.9k+ stars, active releases
- Built-in file explorer, editor, search, terminal, extensions
- WebSocket-based architecture (already proven at scale)
- `--file-watcher-polling` flag for container FS edge cases
- `--connection-token-file` for secure access
- Replaces both watcher AND viewer in one component

### What We Keep

- **ttyd** (port 7681) — still used for auth_setup sessions and as a fallback terminal
- **Auth detection** — extracted from watcher into a minimal standalone check (entrypoint-level or lightweight endpoint)
- **MITM proxy** — unchanged

---

## Story 15.1: Install OpenVSCode Server in Base Docker Image

**As a** platform engineer,
**I want** OpenVSCode Server installed in the agent container base image,
**so that** it's available as a service alongside ttyd.

**Acceptance Criteria:**

1. **Installation** — Download OpenVSCode Server release binary (linux-x64/arm64) in `docker/base/Dockerfile`. Pin to a specific release version (latest stable). Install to `/opt/openvscode-server/`.
2. **Entrypoint integration** — Update `entrypoint.sh` to start OpenVSCode Server on port 8443 with flags: `--host 0.0.0.0`, `--port 8443`, `--without-connection-token` (initial; Story 15.4 adds token), `--default-folder /workspace`.
3. **Port exposure** — Add `EXPOSE 8443` to Dockerfile. Keep existing ports (7681 ttyd, 4040 watcher — watcher removed in Story 15.6).
4. **Health check** — OpenVSCode Server responds to `GET /` with 200 when ready.
5. **Image size** — Document delta in image size. OpenVSCode Server adds ~200-300MB; acceptable for IDE-class functionality.
6. **Multi-arch** — Support both amd64 and arm64, same as ttyd installation pattern.

**Dev Notes:**
- Release URL pattern: `https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v{VERSION}/openvscode-server-v{VERSION}-linux-{x64|arm64}.tar.gz`
- Start in background: `nohup /opt/openvscode-server/bin/openvscode-server ... &`
- Consider `--disable-telemetry` flag
- Workspace directory `/workspace` already exists in current image

---

## Story 15.2: Traefik Routing for VS Code Server

**As a** platform engineer,
**I want** VS Code Server traffic routed through Traefik with WebSocket support,
**so that** the editor is accessible via the same domain as terminal without exposing raw ports.

**Acceptance Criteria:**

1. **Route pattern** — VS Code Server accessible at `/t/{route_token}/ide/` (parallel to existing `/t/{route_token}/tty/` for ttyd and `/t/{route_token}/fs/` for watcher).
2. **Traefik labels** — Add router + service labels in `agent_auth_strategy.rb` and `agent_session_strategy.rb` `build_labels` method. Router: `PathPrefix('/t/{route_token}/ide/')`, service: port 8443.
3. **WebSocket upgrade** — Ensure Traefik middleware allows WebSocket upgrade for VS Code Server routes (VS Code uses WebSockets extensively).
4. **Strip prefix** — Configure middleware to strip `/t/{route_token}/ide` prefix before forwarding to OpenVSCode Server, or use `--server-base-path` flag on VS Code Server.
5. **Timeout** — Set appropriate timeout for long-lived WebSocket connections (at least 3600s, matching current ttyd config).

**Dev Notes:**
- OpenVSCode Server flag `--server-base-path /t/{route_token}/ide` may be cleaner than strip-prefix middleware — test both approaches
- Current ttyd routing uses `PathPrefix` + `StripPrefix` pattern — follow the same
- WebSocket compression: OpenVSCode Server supports `--enable-websocket-compression` flag — consider enabling for bandwidth savings

---

## Story 15.3: Backend — Update Container Strategies

**As a** backend developer,
**I want** container strategies to expose VS Code Server URL and check its readiness,
**so that** the frontend can connect to the editor.

**Acceptance Criteria:**

1. **Exposed ports** — Add `8443/tcp` to `build_exposed_ports` in both `AgentAuthStrategy` and `AgentSessionStrategy`.
2. **IDE URL in exec result** — `exec(context)` returns `ide_url` alongside existing `websocket_url` and `watcher_url`. Format: `https://{host}/t/{route_token}/ide/`.
3. **Service readiness** — Add port 8443 to `services_ports` array in `AgentSessionStrategy` (currently `[7681, 4040]` → `[7681, 4040, 8443]`, then `[7681, 8443]` after watcher removal in Story 15.6).
4. **TerminalSession model** — Add `ide_url` field to session metadata or expose via serializer (same pattern as `websocket_url` and `watcher_url`).
5. **ActionCable broadcast** — Include `ide_url` in session state updates so frontend receives it via existing `useTerminalSessionChannel` hook.

**Dev Notes:**
- Follow existing pattern in `agent_auth_strategy.rb` lines 127-143 for URL construction
- `ide_url` format: `"#{traefik_ws_base}/t/#{route_token}/ide/"`
- Frontend `ITerminalSession` type needs `ideUrl?: string` field

---

## Story 15.4: Security — Connection Token Management

**As a** platform engineer,
**I want** VS Code Server protected by a per-session connection token,
**so that** only authorized users can access the editor.

**Acceptance Criteria:**

1. **Token generation** — Generate a random connection token (SecureRandom.hex(32)) per session in container strategy.
2. **Token file** — Write token to `/tmp/.vscode-connection-token` inside container (permissions 0600). Use `--connection-token-file /tmp/.vscode-connection-token` flag instead of `--connection-token` (avoids token leaking via `ps`).
3. **Token passing to frontend** — Include token in `ide_url` as query parameter: `?tkn={token}`. OpenVSCode Server accepts this for authentication.
4. **Token isolation** — Each session gets a unique token. Token is not stored in database — it's ephemeral, lives only in container and in the session's IDE URL.
5. **Fallback** — If token file creation fails, log warning and start with `--without-connection-token` (degraded security, acceptable for dev/staging).

**Dev Notes:**
- Token file must be created in `before_exec` lifecycle hook (before VS Code Server starts reading it)
- Research doc warns: store token file in directory with `chmod 0700`
- Consider timing: entrypoint reads token file → starts VS Code Server. Token file must exist before server starts.
- Pattern: generate token in strategy → pass as env var `VSCODE_TOKEN` → entrypoint writes to file → starts server with `--connection-token-file`

---

## Story 15.5: Frontend — Embed VS Code Editor in Session Widget

**As a** user,
**I want** a full VS Code editor embedded in my agent session view,
**so that** I can browse, read, and edit files with IDE-level UX.

**Acceptance Criteria:**

1. **Three layout modes** — `TerminalSessionWidget` supports three modes determined by props and session state:
   - **`editor+terminal`** — VS Code Editor (left) + Terminal iframe (right). Default for `agent_session` when `ideUrl` is present. Resizable panels via `react-resizable-panels`.
   - **`terminal-only`** — Terminal iframe fills the entire widget. Used by `AgentAuthTerminal` (`showEditor=false, showTerminal=true`), and as fallback when `ideUrl` is not available.
   - **`editor-only`** — VS Code Editor fills the entire widget (future use; VS Code has built-in terminal, so this is viable). Activated via `showEditor=true, showTerminal=false`.
2. **VS Code iframe** — Embed OpenVSCode Server via iframe pointing to `session.ideUrl`. Same pattern as current ttyd iframe embedding.
3. **Loading state** — Show loading spinner while VS Code iframe loads (same UX as current terminal loading).
4. **Session type awareness** — Widget does NOT hardcode session type logic. Callers decide the layout:
   - `AgentAuthTerminal` passes `showEditor=false, showTerminal=true` → terminal-only (unchanged behavior)
   - `CompanySessionViewPage` / `CompanySessionNewPage` pass `showEditor=true, showTerminal=true` → editor+terminal
   - `TerminalTestPage` — same as session pages
5. **Panel toggle** — User can collapse editor panel to terminal-only mode (and vice versa) at runtime. Toggle button in panel header.
6. **Responsive** — In editor+terminal mode: editor takes 60% width by default, minimum 30%. Terminal takes remaining space, minimum 20%.
7. **Props update** — `TerminalSessionWidget` props:
   - Remove: `showFileTree`, `showFileViewer`, `fileTreeWidth`, `fileViewerWidth`
   - Add: `showEditor` (boolean, default true), `editorWidth` (number, default 60)
   - Keep: `showTerminal` (boolean, default true), `onSessionUpdate`, `onAuthComplete`
8. **Model update** — `ITerminalSession` type gets `ideUrl?: string` field. Widget derives `canShowEditor` from `showEditor && isSessionRunning && session.ideUrl`.

**Dev Notes:**
- VS Code Server iframe URL: `{ideUrl}` (includes connection token as query param from Story 15.4)
- Panel library `react-resizable-panels` is already used — same `<Group>` / `<Panel>` / `<Separator>` approach
- Current callers to update:
  - `AgentAuthTerminal` (line 306): `showEditor={false} showTerminal={true}` — **terminal-only, no change in behavior**
  - `CompanySessionViewPage` (line 194): `showEditor showTerminal` — **editor+terminal**
  - `CompanySessionNewPage` (line 42): `showEditor showTerminal` — **editor+terminal**
  - `TerminalTestPage` (line 257): `showEditor showTerminal` — **editor+terminal**
  - `SessionLaunchWidget` render prop — callers control layout via props
- `FileTree` + `FileViewer` imports removed from agent session rendering; components themselves kept (auth_setup still uses watcher-based file tree if needed in the future)

---

## Story 15.6: Auth Detection — Extract from Watcher

**As a** platform engineer,
**I want** auth detection logic preserved after watcher removal,
**so that** auth_setup sessions still detect when agent authentication is complete.

**Acceptance Criteria:**

1. **Standalone auth endpoint** — Extract `/auth` endpoint from `watcher/index.js` into a minimal standalone script (`docker/base/auth-check/index.js` or shell script). Runs on port 4040 ONLY for `auth_setup` sessions.
2. **Entrypoint logic** — `entrypoint.sh` starts auth-check service only when `SESSION_TYPE=auth_setup`. For `agent_session`, port 4040 is not used.
3. **Same contract** — `GET /auth` returns `{ "authenticated": true/false }` — no change for frontend.
4. **Lightweight** — Auth check is a ~50-line script (no chokidar, no tree, no file serving). Just periodic file check + HTTP endpoint.
5. **FileTree for auth sessions** — Auth setup sessions still use FileTree + watcher for file tree (minimal watcher kept for this flow only), OR we skip file tree entirely for auth sessions (simpler).

**Dev Notes:**
- Auth setup is a short-lived flow (user authenticates agent, ~30 seconds). Full file tree is not critical here.
- Simplest approach: keep watcher as-is for auth_setup sessions, only remove it from agent_session path. Cleanup of auth_setup flow is out of scope for this epic.
- Alternative: move auth polling to Rails backend (check file via `docker exec`) — eliminates need for any in-container HTTP service for auth. Consider for future simplification.

---

## Story 15.7: Cleanup — Remove Custom Viewer from Agent Session Path

**As a** developer,
**I want** deprecated viewer code removed from the agent session code path,
**so that** the codebase stays clean and doesn't carry dead code.

**Acceptance Criteria:**

1. **Frontend cleanup** — Remove `FileTree` and `FileViewer` usage from agent session rendering in `TerminalSessionWidget`. Components themselves are NOT deleted yet (still used by auth_setup).
2. **Backend cleanup** — Remove `watcher_url` from `AgentSessionStrategy#exec` result (keep in `AgentAuthStrategy`).
3. **Port cleanup** — Remove port 4040 from `services_ports` in `AgentSessionStrategy` (was `[7681, 4040, 8443]` → `[7681, 8443]`).
4. **Dockerfile** — For agent_session containers: watcher is not started (entrypoint conditional). Watcher deps remain in image for now (shared base with auth_setup).
5. **Deprecation markers** — Add `@deprecated` comments to `FileTree.tsx` and `FileViewer.tsx` indicating they'll be removed when auth_setup is migrated.
6. **npm deps** — Do NOT remove `react-accessible-treeview`, `react-file-icon`, `react-syntax-highlighter` yet (still used by auth_setup and potentially other pages).

**Dev Notes:**
- This is a conservative cleanup — full removal happens in a future epic when auth_setup is also migrated
- Test: agent_session should work with VS Code editor + terminal, no watcher
- Test: auth_setup should still work with ttyd + watcher (unchanged)

---

## Story 15.8: VS Code Server — File Watching Tuning

**As a** platform engineer,
**I want** VS Code Server file watching optimized for container environment,
**so that** file changes by agents are reflected immediately in the editor.

**Acceptance Criteria:**

1. **Polling mode** — Enable `--file-watcher-polling` flag by default for container environments (inotify may not work reliably across all volume types).
2. **inotify limits** — Set `fs.inotify.max_user_watches=524288` in container (via sysctl or entrypoint `echo` to `/proc/sys/fs/inotify/max_user_watches` if privileged, otherwise document as host requirement).
3. **Excluded patterns** — Configure VS Code settings to exclude watching: `node_modules`, `.git`, `__pycache__`, `venv`, `tmp`, `cache` — same patterns as current watcher's IGNORE_PATTERNS.
4. **Testing** — Verify: agent writes file → VS Code explorer updates within 2 seconds. Test with repo clone (Story 14.3 creates `/workspace/repos/` structure).
5. **Resource limits** — Document memory overhead of VS Code Server with polling enabled. Set recommendations for container memory limits.

**Dev Notes:**
- VS Code settings file: `/workspace/.vscode/settings.json` or user-level settings in VS Code Server data dir
- `files.watcherExclude` setting controls watch exclusions
- Polling interval is configurable via VS Code settings
- Research doc warns: inotify limits are a known issue at scale, polling is the safe fallback

---

## Effort Estimate

| Story | Effort | Risk |
|-------|--------|------|
| 15.1 Install OpenVSCode Server | Low | Image size, multi-arch builds |
| 15.2 Traefik routing | Low | WebSocket + base path config |
| 15.3 Backend strategies | Low-Medium | URL plumbing, readiness checks |
| 15.4 Connection token | Medium | Timing of token file creation |
| 15.5 Frontend embed | Medium | Layout rework, iframe comms |
| 15.6 Auth detection extract | Low | Scope contained to auth_setup |
| 15.7 Cleanup | Low | Careful not to break auth_setup |
| 15.8 File watching tuning | Medium | FS behavior varies by runtime |

**Total: Medium** — primary risk is infrastructure (Docker image + Traefik routing), frontend change is mostly simplification.

---

## Dependencies

- **Epic 9 (Agent Sessions Core)** — session model, container lifecycle, ActionCable
- **Epic 14.3 (Repo Clone)** — VS Code Server should open `/workspace` which includes cloned repos
- **Container Runtime** — works with both Docker and Kubernetes runtimes

## Out of Scope

- Collaborative editing / multi-user presence (VS Code Live Share — future epic)
- VS Code extensions marketplace / pre-installed extensions (future enhancement)
- Replacing ttyd terminal entirely with VS Code integrated terminal (evaluate after adoption)
- Migrating auth_setup flow away from watcher (separate cleanup epic)
