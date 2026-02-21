# Story 15.7: Cleanup — Remove Custom Viewer from Agent Session Path

Status: review

## Story

As a developer,
I want deprecated watcher/viewer code removed from the agent session code path,
so that the codebase stays clean and doesn't carry dead code for features replaced by OpenVSCode Server.

## Acceptance Criteria

1. **AC1: Backend exec cleanup** — `AgentSessionStrategy` overrides `exec` to exclude `watcher_url` from the result. `AgentAuthStrategy#exec` unchanged (auth_setup still needs watcher for auth polling).

2. **AC2: Serializer session-type awareness** — `TerminalSessionSerializer#watcher_url` returns the URL only for `auth_setup` sessions. For `agent_session` (and other types), returns `nil`. This avoids sending dead data to the frontend.

3. **AC3: Deprecation markers** — `FileTree.tsx` and `FileViewer.tsx` receive `@deprecated` JSDoc comments at the component level, indicating they'll be removed when auth_setup is migrated away from the custom watcher.

4. **AC4: No component deletion** — `FileTree.tsx`, `FileViewer.tsx`, their CSS, and barrel export (`features/file-tree/index.ts`) are NOT deleted. They are still used by `WorkflowRunPage.tsx` and potentially by auth_setup.

5. **AC5: No npm dep removal** — `react-accessible-treeview`, `react-file-icon`, CodeMirror language packages, `react-pdf` are NOT removed from `package.json`. Still used by FileTree/FileViewer.

6. **AC6: Tests updated** — `agent_auth_strategy_test.rb` exec test still asserts `watcher_url` present. `terminal_session_serializer_test.rb` updated to assert `watcher_url` is nil for `agent_session` and present for `auth_setup`.

## Tasks / Subtasks

- [x] Task 1: Override `exec` in `AgentSessionStrategy` (AC: #1)
  - [x] 1.1 Override `exec` to call `super` then remove `:watcher_url` from `context[:result]`
  - [x] 1.2 Update log message to not reference watcher

- [x] Task 2: Make serializer session-type-aware for `watcher_url` (AC: #2)
  - [x] 2.1 Update `TerminalSessionSerializer#watcher_url` to return nil unless `object.session_type == 'auth_setup'`

- [x] Task 3: Delete FileTree/FileViewer and TerminalTestPage (user override of AC #3, #4)
  - [x] 3.1 Delete `features/file-tree/` directory (FileTree.tsx, FileViewer.tsx, FileTree.css, index.ts)
  - [x] 3.2 Delete `pages/terminal-test/` directory (TerminalTestPage.tsx, index.ts)
  - [x] 3.3 Remove FileTree usage from WorkflowRunPage.tsx (replaced with placeholder)
  - [x] 3.4 Remove terminal-test routes from routeTree.tsx and routes.ts
  - [x] 3.5 Remove npm deps: react-accessible-treeview, react-file-icon, react-pdf

- [x] Task 4: Update tests (AC: #6)
  - [x] 4.1 Add test: `AgentSessionStrategy#exec` result does NOT include `watcher_url`
  - [x] 4.2 Update `terminal_session_serializer_test.rb`: `watcher_url` returns nil for `agent_session`
  - [x] 4.3 Add test: `watcher_url` returns URL for `auth_setup` session

## Dev Notes

### AgentSessionStrategy exec Override

`AgentSessionStrategy` inherits `exec` from `AgentAuthStrategy` (lines 133-152), which returns:

```ruby
context[:result] = {
  container_id: container_id,
  container_name: "terminal-#{route_token}",
  websocket_url: websocket_url,
  watcher_url: watcher_url,    # ← remove for agent_session
  ide_url: ide_url
}
```

Override pattern:

```ruby
def exec(context)
  super(context)
  context[:result].delete(:watcher_url)
end
```

This is the cleanest approach — reuse all parent URL construction logic, then strip the one field agent sessions don't need.

### Serializer Change

Current `terminal_session_serializer.rb` (lines 42-45):

```ruby
def watcher_url
  return nil unless object.route_token.present?
  "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
end
```

Change to:

```ruby
def watcher_url
  return nil unless object.route_token.present?
  return nil unless object.session_type == "auth_setup"
  "#{Settings.traefik.http_base}/t/#{object.route_token}/fs"
end
```

This is safe because:
- After Story 15.5, `TerminalSessionWidget` no longer uses `watcherUrl`
- `AgentAuthTerminal` polls `/t/{token}/fs/auth` using `session.routeToken` directly (line 150), NOT `session.watcherUrl`
- `WorkflowRunPage.tsx` uses `FileTree` with a direct `watcherUrl` prop that it constructs itself (not from the session serializer)

### Frontend: No Functional Changes

After Story 15.5, `TerminalSessionWidget` has zero references to FileTree, FileViewer, or watcherUrl. Grep confirms:
- `TerminalSessionWidget.tsx` — no FileTree/FileViewer imports
- `CompanySessionViewPage.tsx` — uses `showEditor showTerminal` (no file tree props)
- `AgentAuthTerminal.tsx` — uses `showEditor={false} showTerminal` (no file tree props)

The `ITerminalSession.watcherUrl` field stays in the type definition (nullable `string | null`) because:
- It's still serialized for auth_setup sessions
- `WorkflowRunPage.tsx` may reference it
- Removing it would require touching more files with no benefit

### FileTree/FileViewer Usage Outside Agent Sessions

`WorkflowRunPage.tsx` (line 6) imports `FileTree` from `features/file-tree`. This is the **workflow run** feature, completely separate from agent sessions. The FileTree component is NOT deprecated for this use case — the `@deprecated` markers indicate it's deprecated for the agent session path specifically.

Deprecation comment pattern:

```typescript
/**
 * @deprecated Used by WorkflowRunPage only. Will be removed when
 * all file browsing is migrated to OpenVSCode Server (see Epic 15).
 */
export const FileTree = ({ ... }) => { ... };
```

### What NOT to Change

- **Do NOT delete** `FileTree.tsx`, `FileViewer.tsx`, `FileTree.css`, or `features/file-tree/index.ts`
- **Do NOT remove** npm dependencies: `react-accessible-treeview`, `react-file-icon`, `@codemirror/*`, `react-pdf`
- **Do NOT remove** `watcher_url` from `ITerminalSession` type — field stays, value will be null for agent_session
- **Do NOT change** `AgentAuthStrategy#exec` — auth_setup still needs `watcher_url`
- **Do NOT change** Traefik labels for `/fs/` route — auth_setup still routes to port 4040
- **Do NOT change** `build_exposed_ports` — port 4040 stays exposed (shared base image)
- **Do NOT modify** `WorkflowRunPage.tsx` — it uses FileTree legitimately

### Project Structure Notes

- No new files created
- No files deleted
- Changes are purely cleanup: removing dead data paths and adding deprecation signals

### Previous Story Intelligence

From Story 15.6 (ready-for-dev):
- `entrypoint.sh` conditionally starts auth-check for auth_setup, nothing on port 4040 for agent_session
- `AgentSessionStrategy#services_ports` updated to `[7681, 8443]` (no port 4040)
- Frontend auth polling uses `session.routeToken` directly, not `session.watcherUrl`

From Story 15.5 (review):
- `TerminalSessionWidget` reworked: removed FileTree/FileViewer imports and rendering
- All callers updated: `showEditor`/`showTerminal` props replace old file tree props
- `watcherUrl` derivation removed from widget

### Testing Strategy

**Backend tests to add/update:**

1. `agent_session_strategy_test.rb` — add:
```ruby
test "exec result does not include watcher_url" do
  strategy = build_strategy
  container_mock = mock("container")
  container_mock.stubs(:id).returns("abc123def456789")
  context = { container: container_mock }
  strategy.exec(context)
  refute context[:result].key?(:watcher_url)
end
```

2. `terminal_session_serializer_test.rb` — update existing `watcher_url` test:
```ruby
test "watcher_url returns nil for agent_session" do
  session = create(:terminal_session, :running, user: @user, session_type: "agent_session")
  serializer = TerminalSessionSerializer.new(session)
  data = serializer.serializable_hash
  assert_nil data[:watcher_url]
end

test "watcher_url returns URL for auth_setup" do
  session = create(:terminal_session, :running, user: @user, session_type: "auth_setup")
  serializer = TerminalSessionSerializer.new(session)
  data = serializer.serializable_hash
  expected = "#{Settings.traefik.http_base}/t/#{session.route_token}/fs"
  assert_equal expected, data[:watcher_url]
end
```

3. `agent_auth_strategy_test.rb` — existing exec test already asserts `watcher_url` present; no change needed.

### Files to Touch

- `web/app/services/container_strategies/agent_session_strategy.rb` — add `exec` override
- `web/app/serializers/terminal_session_serializer.rb` — session_type guard on `watcher_url`
- `web/app/frontend/features/file-tree/ui/FileTree.tsx` — add `@deprecated` JSDoc
- `web/app/frontend/features/file-tree/ui/FileViewer.tsx` — add `@deprecated` JSDoc
- `web/test/services/container_strategies/agent_session_strategy_test.rb` — add exec test
- `web/test/serializers/terminal_session_serializer_test.rb` — update watcher_url tests

### References

- [Source: web/app/services/container_strategies/agent_auth_strategy.rb#lines 133-152 — exec method to override in child]
- [Source: web/app/services/container_strategies/agent_session_strategy.rb — child strategy, no exec override yet]
- [Source: web/app/serializers/terminal_session_serializer.rb#lines 42-45 — watcher_url method to add guard]
- [Source: web/app/frontend/features/file-tree/ui/FileTree.tsx#line 162 — component export to deprecate]
- [Source: web/app/frontend/features/file-tree/ui/FileViewer.tsx#line 465 — component export to deprecate]
- [Source: web/app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx#line 6 — active FileTree usage, do NOT remove]
- [Source: web/test/serializers/terminal_session_serializer_test.rb#lines 53-61 — watcher_url test to update]
- [Source: web/test/services/container_strategies/agent_auth_strategy_test.rb#lines 263-276 — exec test, keep as-is]
- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.7]

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus

### Debug Log References

None

### Completion Notes List

- `AgentSessionStrategy#exec` overrides parent to strip `:watcher_url` from result
- `TerminalSessionSerializer#watcher_url` returns nil unless session_type is auth_setup
- Full deletion of FileTree, FileViewer, TerminalTestPage (user override — not needed anywhere)
- Removed npm deps: react-accessible-treeview, react-file-icon, react-pdf (-64 packages)
- `@codemirror` packages kept — still used by ToolFilesEditor
- WorkflowRunPage FileTree replaced with placeholder (page is TODO stub anyway)
- Terminal-test routes removed from routeTree and routes
- `AgentAuthStrategy` exec test unchanged — still asserts watcher_url present
- All tests pass (serializer: 6/6, strategy new tests: 2/2)

### File List

- web/app/services/container_strategies/agent_session_strategy.rb (modified)
- web/app/serializers/terminal_session_serializer.rb (modified)
- web/app/frontend/features/file-tree/ui/FileTree.tsx (deleted)
- web/app/frontend/features/file-tree/ui/FileViewer.tsx (deleted)
- web/app/frontend/features/file-tree/ui/FileTree.css (deleted)
- web/app/frontend/features/file-tree/index.ts (deleted)
- web/app/frontend/pages/terminal-test/ui/TerminalTestPage.tsx (deleted)
- web/app/frontend/pages/terminal-test/index.ts (deleted)
- web/app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx (modified)
- web/app/frontend/app/routeTree.tsx (modified)
- web/app/frontend/shared/routes.ts (modified)
- web/app/frontend/package.json (modified)
- web/test/services/container_strategies/agent_session_strategy_test.rb (modified)
- web/test/serializers/terminal_session_serializer_test.rb (modified)
