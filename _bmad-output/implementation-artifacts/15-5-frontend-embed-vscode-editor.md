# Story 15.5: Frontend — Embed VS Code Editor in Session Widget

Status: review

## Story

As a user,
I want a full VS Code editor embedded in my agent session view,
so that I can browse, read, and edit files with IDE-level UX directly in the browser.

## Acceptance Criteria

1. **AC1: Three layout modes** — `TerminalSessionWidget` supports three modes:
   - **`editor+terminal`** — VS Code editor iframe (left/top) + Terminal iframe (right/bottom). Default for `agent_session` when `ideUrl` is present. Resizable panels via existing `react-resizable-panels`.
   - **`terminal-only`** — Terminal iframe fills entire widget. Used by `AgentAuthTerminal` and as fallback when `ideUrl` is not available.
   - **`editor-only`** — VS Code editor fills entire widget. Activated via `showEditor=true, showTerminal=false`.

2. **AC2: VS Code iframe** — Embed OpenVSCode Server via `<iframe src={session.ideUrl}>`. Same pattern as current ttyd iframe embedding (loading spinner, onLoad handler).

3. **AC3: New props** — `TerminalSessionWidget` props updated:
   - Remove: `showFileTree`, `showFileViewer`, `fileTreeWidth`, `fileViewerWidth`
   - Add: `showEditor` (boolean, default true), `editorWidth` (number, default 60 — percent)
   - Keep: `showTerminal` (boolean, default true), `sessionId`, `session`, `onSessionUpdate`, `onAuthComplete`

4. **AC4: All callers updated** —
   - `AgentAuthTerminal` (line 306): `showEditor={false} showTerminal` — terminal-only, unchanged behavior
   - `CompanySessionViewPage` (line 194): `showEditor showTerminal` — editor+terminal
   - `CompanySessionNewPage` via `renderTerminal`: `showEditor showTerminal` — editor+terminal
   - `TerminalTestPage` (line 257): `showEditor showTerminal` — editor+terminal

5. **AC5: Panel toggle** — User can collapse/expand editor panel at runtime via a toggle button in the separator area. Collapsed state remembered for the session duration (not persisted).

6. **AC6: Responsive sizing** — Editor panel takes 60% width by default, minimum 30%. Terminal takes remaining space, minimum 20%.

7. **AC7: Loading state** — Both iframes show loading spinner while loading (same UX as current terminal loading).

## Tasks / Subtasks

- [x] Task 1: Rework `TerminalSessionWidget` component (AC: #1, #2, #3, #6, #7)
  - [x] 1.1 Remove `showFileTree`, `showFileViewer`, `fileTreeWidth`, `fileViewerWidth` props
  - [x] 1.2 Add `showEditor` (default true), `editorWidth` (default 60) props
  - [x] 1.3 Remove `FileTree` and `FileViewer` imports and rendering logic
  - [x] 1.4 Remove `selectedFile`, `onFileSelect`, `handleFileSelect`, `handleCloseFileViewer` state/callbacks
  - [x] 1.5 Add `ideUrl` derivation from `session.ideUrl` (already comes from serializer via ActionCable)
  - [x] 1.6 Implement editor+terminal layout with `react-resizable-panels` `<Group>/<Panel>/<Separator>`
  - [x] 1.7 Implement terminal-only layout (when `!showEditor` or `!ideUrl`)
  - [x] 1.8 Implement editor-only layout (when `showEditor && !showTerminal`)
  - [x] 1.9 Add loading spinner for editor iframe (same pattern as terminal iframe)
- [x] Task 2: Add panel collapse toggle (AC: #5)
  - [x] 2.1 Add state: `editorCollapsed` (boolean, default false)
  - [x] 2.2 Add toggle button on separator + double-click on separator to toggle
  - [x] 2.3 When collapsed, terminal takes full width with expand button; when expanded, restore dual layout
- [x] Task 3: Update `CompanySessionViewPage` caller (AC: #4)
  - [x] 3.1 Replace `showFileTree showFileViewer showTerminal` with `showEditor showTerminal`
- [x] Task 4: Update `CompanySessionNewPage` / `renderTerminal` caller (AC: #4)
  - [x] 4.1 Replace `showFileTree showFileViewer showTerminal` with `showEditor showTerminal`
- [x] Task 5: Update `AgentAuthTerminal` caller (AC: #4)
  - [x] 5.1 Replace `showFileTree={false} showFileViewer={false} showTerminal={true}` with `showEditor={false} showTerminal`
- [x] Task 6: Update `TerminalTestPage` caller (AC: #4)
  - [x] 6.1 Replace `showFileTree={true} showFileViewer={true} showTerminal={true}` with `showEditor showTerminal`
- [x] Task 7: Remove unused `onFileSelect` prop from interface (AC: #3)
  - [x] 7.1 Remove `onFileSelect` from `TerminalSessionWidgetProps`
  - [x] 7.2 Ensure no callers pass it — verified via grep

## Dev Notes

### Current TerminalSessionWidget Architecture (323 lines)

The widget currently orchestrates three panels:
1. **FileTree** (left) — connected to watcher WebSocket, shows file directory tree
2. **FileViewer** (center) — shows file content with syntax highlighting when file selected
3. **Terminal** (right) — ttyd iframe

After this story, it becomes:
1. **VS Code Editor** (left) — iframe to OpenVSCode Server at `session.ideUrl`
2. **Terminal** (right) — ttyd iframe (unchanged)

This is a **simplification** — we remove FileTree + FileViewer complexity and replace with a single iframe.

### ideUrl Derivation

After Story 15.3, `ideUrl` comes directly from the session object via ActionCable/API:

```typescript
const ideUrl = session?.ideUrl ?? null;
const canShowEditor = showEditor && isSessionRunning && ideUrl;
```

No URL manipulation needed (unlike current `watcherUrl` which is derived from `websocketUrl`). After Story 15.4, `ideUrl` already includes the `?tkn=` parameter.

### Layout Implementation

Use existing `react-resizable-panels` (already imported):

```tsx
// editor+terminal mode
<Group orientation="horizontal" style={{ width: '100%', height: '100%' }}>
  <Panel defaultSize={editorWidth} minSize={30}>
    {/* VS Code iframe */}
    <iframe src={ideUrl} style={styles.iframe} title="VS Code Editor" onLoad={handleEditorLoad} />
  </Panel>
  <Separator />
  <Panel minSize={20}>
    {/* Terminal iframe */}
    <iframe src={ttydUrl} style={styles.iframe} title="Terminal" onLoad={handleTerminalLoad} />
  </Panel>
</Group>
```

### Panel Collapse

Add a small toggle button to the separator. When editor is collapsed, set `editorCollapsed=true` and render terminal-only layout. Use state, not CSS — so the panel sizes reset properly.

Simple approach: `<Separator>` from react-resizable-panels supports `onDoubleClick` — double-click to collapse/expand is a natural UX pattern.

### Callers to Update

1. **CompanySessionViewPage.tsx** (line 194):
   ```tsx
   // Before:
   <TerminalSessionWidget sessionId={id} session={session} showFileTree showFileViewer showTerminal />
   // After:
   <TerminalSessionWidget sessionId={id} session={session} showEditor showTerminal />
   ```

2. **CompanySessionNewPage.tsx** — via `renderTerminal` callback (line 42-45):
   ```tsx
   // Before:
   <TerminalSessionWidget sessionId={sid} session={session} showFileTree showFileViewer showTerminal />
   // After:
   <TerminalSessionWidget sessionId={sid} session={session} showEditor showTerminal />
   ```

3. **AgentAuthTerminal.tsx** (line 306):
   ```tsx
   // Before:
   <TerminalSessionWidget sessionId={sessionId} showFileTree={false} showFileViewer={false} showTerminal={true} ... />
   // After:
   <TerminalSessionWidget sessionId={sessionId} showEditor={false} showTerminal ... />
   ```

4. **TerminalTestPage.tsx** (line 257):
   ```tsx
   // Before:
   <TerminalSessionWidget sessionId={sessionId} showFileTree={true} showFileViewer={true} showTerminal={true} ... />
   // After:
   <TerminalSessionWidget sessionId={sessionId} showEditor showTerminal ... />
   ```

### What to Remove from TerminalSessionWidget

- `FileTree` import from `features/file-tree`
- `FileViewer` import from `features/file-tree`
- `selectedFile` state
- `handleFileSelect` callback
- `handleCloseFileViewer` callback
- `watcherUrl` derivation logic (keep it if still used by `onAuthComplete` polling, or remove if not)
- `onFileSelect` prop
- `showFileTree`, `showFileViewer`, `fileTreeWidth`, `fileViewerWidth` props
- All FileTree/FileViewer panel rendering

### What to Keep

- `FileTree` and `FileViewer` component files themselves (still used by auth_setup potentially, removed in Story 15.7)
- `useTerminalSessionChannel` hook import (still used)
- Loading/error/empty states
- `ttydUrl` derivation (terminal still uses ttyd)
- `iframeRef`, `iframeLoaded` state for terminal
- `onSessionUpdate`, `onAuthComplete` props

### watcherUrl in AgentAuthTerminal

`AgentAuthTerminal` polls `/t/{token}/fs/auth` for auth detection (line 153-166). This uses `session.routeToken` directly, not `watcherUrl`. So removing `watcherUrl` from the widget doesn't break auth polling.

### Dependencies

- **Story 15.3** must be complete (adds `ideUrl` to serializer and `ITerminalSession` type)
- **Story 15.4** should be complete (adds `?tkn=` to `ideUrl`) — but not strictly required; IDE works without token in dev

### TypeScript Strict Mode

The project uses strict TypeScript. Ensure:
- No unused imports after removing FileTree/FileViewer
- `ideUrl` properly typed as `string | null` (from ITerminalSession)
- Props interface updated to match new shape

### What NOT To Change

- Do NOT delete `FileTree.tsx` or `FileViewer.tsx` — that's Story 15.7
- Do NOT remove `watcher_url` from backend — that's Story 15.7
- Do NOT modify ActionCable channel or serializer — that's Stories 15.3/15.4
- Do NOT add VS Code extension management — out of scope

### Files to Touch

- `web/app/frontend/widgets/terminal-session/ui/TerminalSessionWidget.tsx` — major rework (remove file tree/viewer, add editor iframe)
- `web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx` — update props
- `web/app/frontend/pages/company-sessions/ui/CompanySessionNewPage.tsx` — update renderTerminal props
- `web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx` — update props
- `web/app/frontend/pages/terminal-test/ui/TerminalTestPage.tsx` — update props

### Previous Story Intelligence

From Story 15.2:
- IDE accessible at `/t/{token}/ide/` via Traefik — confirmed working in smoke test
- Editor loads in browser, file tree visible, WebSocket connects
- `terminal-auth` ForwardAuth protects the route (same as ttyd)

From Story 15.1:
- OpenVSCode Server provides built-in file tree, editor, terminal, search
- Default settings configured in `vscode-settings.json` (dark theme, no telemetry, workspace trust disabled)

### References

- [Source: ai/epics/epic-15-monaco-vscode-server-integration.md#Story 15.5]
- [Source: web/app/frontend/widgets/terminal-session/ui/TerminalSessionWidget.tsx — full component 323 lines]
- [Source: web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx — line 194 TerminalSessionWidget usage]
- [Source: web/app/frontend/pages/company-sessions/ui/CompanySessionNewPage.tsx — line 42 renderTerminal]
- [Source: web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx — line 306 TerminalSessionWidget usage]
- [Source: web/app/frontend/pages/terminal-test/ui/TerminalTestPage.tsx — line 257 TerminalSessionWidget usage]
- [Source: web/app/frontend/entities/terminal-session/model/types.ts — ITerminalSession interface]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus

### Debug Log References
- No linter errors in any modified files
- Grep confirms zero remaining references to removed props (showFileTree, showFileViewer, fileTreeWidth, fileViewerWidth, onFileSelect)

### Completion Notes List
- AC1: Three layout modes implemented — editor+terminal (dual panel), terminal-only, editor-only
- AC2: VS Code iframe embeds `session.ideUrl` (includes `?tkn=` from Story 15.4)
- AC3: Old props removed (showFileTree, showFileViewer, fileTreeWidth, fileViewerWidth, onFileSelect); new props added (showEditor default true, editorWidth default 60)
- AC4: All 4 callers updated — AgentAuthTerminal (showEditor=false), CompanySessionViewPage, CompanySessionNewPage, TerminalTestPage
- AC5: Panel collapse via toggle button on separator + double-click; collapsed state shows expand chevron; resets per session
- AC6: Editor panel 60% default, minSize 30%; terminal minSize 20%
- AC7: Both iframes show loading spinner with CircularProgress while loading
- Removed ~100 lines of FileTree/FileViewer logic, replaced with ~80 lines of cleaner editor+terminal layout
- watcherUrl derivation removed from widget (not needed after FileTree removal)

### Change Log
- `TerminalSessionWidget.tsx`: Complete rewrite — removed FileTree/FileViewer, added editor iframe with 3 layout modes, collapse toggle
- `CompanySessionViewPage.tsx`: Props updated to showEditor showTerminal
- `CompanySessionNewPage.tsx`: renderTerminal props updated
- `AgentAuthTerminal.tsx`: Props updated to showEditor={false} showTerminal
- `TerminalTestPage.tsx`: Props updated, description text updated

### File List
- web/app/frontend/widgets/terminal-session/ui/TerminalSessionWidget.tsx
- web/app/frontend/pages/company-sessions/ui/CompanySessionViewPage.tsx
- web/app/frontend/pages/company-sessions/ui/CompanySessionNewPage.tsx
- web/app/frontend/features/agent-auth/ui/AgentAuthTerminal.tsx
- web/app/frontend/pages/terminal-test/ui/TerminalTestPage.tsx
