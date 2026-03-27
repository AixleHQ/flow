# Story 4.2: Web Terminal Interface

Epic: 4 - Agent Session & Workspace
Story ID: 4.2
Story Key: `4-2-web-terminal-interface`
Status: ready-for-dev

## User Story

As a user,
I want to interact with the agent through a web terminal in Interactive mode,
So that I can communicate with the agent in real-time.

## Acceptance Criteria

1. **AC1**: Web terminal interface visible when session is active (Interactive mode)
2. **AC2**: Terminal embedded via ttyd iframe
3. **AC3**: Real-time input/output streaming
4. **AC4**: Standard terminal features (cursor, scrolling, copy/paste)
5. **AC5**: Keyboard shortcuts work (Ctrl+C, etc.)
6. **AC6**: Terminal state preserved on navigation away/return
7. **AC7**: Terminal connects via WebSocket to container

## Pre-Implementation Analysis

### Already Implemented (in terminal-test page)
- **`TerminalSessionWidget`** — complete terminal widget with:
  - ttyd iframe integration
  - Connection status (connecting, running, error states)
  - FileTree panel
  - FileViewer panel
  - Resizable panels
- **`useTerminalSessionChannel`** — ActionCable hook for real-time updates
- ttyd running in Docker containers
- `route_token` for terminal access
- WebSocket proxy configuration

### Needs Implementation
- Integrate existing `TerminalSessionWidget` into project session view
- Most functionality already works!

## Tasks/Subtasks

### Task 1: Integrate TerminalSessionWidget (AC: 1, 2, 3, 4, 5, 6, 7)
- [ ] Use `TerminalSessionWidget` in project session view
- [ ] All terminal features already implemented

### Task 2: Session View Page (if not done in 4-1)
- [ ] Create route for project session
- [ ] Embed TerminalSessionWidget

## Dev Notes

### ttyd URL Format
```
wss://{host}/ttyd/{route_token}/
```

### Terminal Iframe
```tsx
<iframe
  src={`/ttyd/${session.route_token}/`}
  style={{ width: '100%', height: '100%', border: 'none' }}
  title="Terminal"
/>
```

### Session States for Terminal
- `starting` - Show "Connecting..." message
- `running` - Show terminal iframe
- `stopped` / `collected` - Show "Session ended" message

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
