# Epic 9: Agent Sessions Core (Phase 4+)

Users can start sessions with AI agents and interact with them.

**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9

**Phase:** 4+ (Depends on: Epic 8 Session Context)

**Status:** IN PROGRESS (Stories 9.1, 9.2 ready-for-dev)

**User Outcome:** Complete agent session workflow with cost tracking.

## Story 9.1: Start Agent Session

As a user,
I want to start a new agent session with selected agent type,
So that I can work with an AI agent on my project.

**Status:** ready-for-dev

**Acceptance Criteria:**
- Can select agent type (Claude Code, Codex, Gemini CLI, Cursor CLI)
- Can select mode (Interactive / Non-interactive)
- Docker container created with session context
- Session status tracks lifecycle

## Story 9.2: Web Terminal Interface

As a user,
I want to interact with agent through web terminal in Interactive mode,
So that I can communicate in real-time.

**Status:** ready-for-dev

**Acceptance Criteria:**
- Web terminal via xterm.js + WebSocket
- Real-time input/output
- Standard terminal features (cursor, scrolling, copy/paste)
- State preserved on navigation

## Story 9.3: Real-time File Tree

As a user,
I want to view file tree of session workspace in real-time,
So that I can see what agent is working on.

**Acceptance Criteria:**
- File tree panel shows workspace structure
- Updates in real-time via WebSocket
- Can expand/collapse directories
- Click file to view in viewer

## Story 9.4: File Viewer & Browser

As a user,
I want to view and browse files in session workspace,
So that I can see agent's work.

**Acceptance Criteria:**
- Syntax highlighting for code
- View images, PDFs, text files
- Read-only viewing
- Navigate via file tree

## Story 9.5: Stop Active Session

As a user,
I want to stop an active session,
So that I can terminate agent's work.

**Acceptance Criteria:**
- Stop button with confirmation
- Container terminated
- Session status → stopped
- Files preserved in workspace

## Story 9.6: MITM Proxy Token Tracking

As a system,
I want to track token usage via MITM proxy,
So that billing is accurate.

**Acceptance Criteria:**
- All LLM API calls intercepted
- Input/output tokens tracked
- Works for all 4 agents
- Accuracy ≥ 95%

## Story 9.7: Session Cost Display

As a user,
I want to see session cost after completion,
So that I understand the expense.

**Acceptance Criteria:**
- Shows total tokens (input/output)
- Shows cost in USD
- Optional cost breakdown by API call

## Story 9.8: Session History View

As a user,
I want to view session history with status and outcomes,
So that I can review past work.

**Acceptance Criteria:**
- List of all project sessions
- Shows agent type, mode, status, duration, cost
- Can filter by type, status, date
- Click to view details

---
