# Story 4.1: Start Agent Session

Epic: 4 - Agent Session & Workspace
Story ID: 4.1
Story Key: `4-1-start-agent-session`
Status: ready-for-dev

## User Story

As a user,
I want to start a new agent session with a selected agent type,
So that I can work with an AI agent on my project.

## Acceptance Criteria

1. **AC1**: Project collaborator can see "Start Session" button in Sessions tab
2. **AC2**: Configuration modal shows agent type selector (Claude Code, Codex, Gemini CLI, Cursor CLI)
3. **AC3**: Configuration modal shows mode selector (Interactive / Non-interactive)
4. **AC4**: Agent must be configured in user profile (validation)
5. **AC5**: Session record created in database with project association
6. **AC6**: User redirected to Session View after starting
7. **AC7**: Session status starts as "starting", changes to "active" when ready
8. **AC8**: Error message with link to settings if agent not configured

## Pre-Implementation Analysis

### Already Implemented (in terminal-test page)
- `TerminalSession` model with state machine, `project_id` field
- `TerminalSessionsController` with CRUD actions
- Agent types: `claude_code`, `cursor_cli`, `codex`, `gemini_cli`
- Session types: `auth_setup`, `agent_session`, `tool_setup`, `workflow_step`
- User `selected_agents` field for configured agents
- Docker container management via `ContainerManager`
- **`TerminalTestPage`** — full session management UI
- **`TerminalSessionWidget`** — terminal + file tree + file viewer widget
- **`useTerminalSessionChannel`** — ActionCable hook for real-time updates
- **`terminalSessionApi`** — RTK Query endpoints

### Needs Implementation
- Project-scoped sessions API (use existing controller with project_id)
- Reuse `TerminalSessionWidget` in ProjectPage Sessions tab
- Add `mode` field (interactive/non-interactive) if needed
- Sessions list in project

## Tasks/Subtasks

### Task 1: Create Project Sessions API (AC: 1, 5)
- [ ] Create `Api::V1::Company::Projects::SessionsController`
- [ ] Implement `index` - list project sessions
- [ ] Implement `create` - start new session with project_id
- [ ] Add policy for project collaborator access

### Task 2: Add Sessions Tab to ProjectPage (AC: 1, 2, 3)
- [ ] Add "Sessions" tab to ProjectPage
- [ ] Show sessions list (reuse patterns from terminal-test)
- [ ] Add "Start Session" button

### Task 3: Create Start Session Dialog (AC: 2, 3, 4, 8)
- [ ] Reuse agent selector from TerminalTestPage
- [ ] Filter by user's configured agents
- [ ] Show error if no agents configured

### Task 4: Session View Integration (AC: 6, 7)
- [ ] Navigate to session view after creation
- [ ] Reuse `TerminalSessionWidget` for session display

## Dev Notes

### API Contract
```
POST /api/v1/company/projects/:project_id/sessions
Body: { session: { agent_type: "claude_code", mode: "interactive" } }
Response: { data: { id, state, agent_type, mode, ... } }
```

### Frontend Routes
```typescript
// New route
/company/projects/:projectId/sessions/:sessionId -> SessionPage
```

### Agent Types
- claude_code
- cursor_cli
- codex
- gemini_cli

### Session Modes
- interactive (with terminal)
- non_interactive (batch mode)

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
