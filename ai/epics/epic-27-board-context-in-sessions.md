# Epic 27: Board Task Context in Agent Sessions

> Agents triggered from the board receive proactive board task context (board, task, column, comments) in their session context, eliminating the need to call board MCP tools for basic awareness.

**Phase:** 16 (Depends on: Epic 25 Unified Context Constructor, Epic 20-21 Board & Tasks)

**Design Document:** [Session Context Constructor — §5.4 BoardContext Builder](../session-context-constructor.md)

**User Outcome:** Board-triggered agents immediately understand their task context — what board task they're working on, what column it's in, what priority it has, and what recent discussion happened. This reduces first-action latency and improves task relevance compared to agents that start blind and must call MCP tools for context.

**FRs Covered:** FR-SCC5

---

## Problem

Currently `BoardContextResolver` resolves board→project mapping only for board MCP tools. The agent doesn't know about its task, column, or recent comments until it explicitly calls `board_get_task` and `board_get_comments` tools. This means the first several agent actions are always "discovery" calls instead of productive work.

This epic injects board context proactively into the session context file, so the agent starts with full awareness of its task.

---

## Stories

### Story 27.1: BoardContext Builder

**As a** system,
**I want** a BoardContext builder that injects board task details into the session context,
**So that** agents immediately know what task they're working on without calling MCP tools.

**Acceptance Criteria:**

**Given** a workflow session triggered from a board task (workflow_run.board_task present)
**When** `ContextBuilders::BoardContext` builds
**Then** output includes a section with tag `board-context`, priority `:important`, position_hint `:top`, containing:
  - Board name
  - Task title and ID
  - Column name
  - Task priority (if present)
  - Task description (truncated to 500 chars, if present)
  - Task tags (if present)
  - Instruction to use board MCP tools for further interaction

**Given** a standalone session (no board_task)
**When** `applicable?` is called
**Then** returns `false` — no board-context section produced

**Given** a workflow session not triggered from board (workflow_run.board_task is nil)
**When** `applicable?` is called
**Then** returns `false`

**Technical notes:**
- Board task resolved via: `session.step_run&.workflow_run&.board_task`
- Builder accesses: `board_task.board`, `board_task.board_column`
- File: `app/services/context_builders/board_context.rb`

---

### Story 27.2: Recent Comments in Board Context

**As a** system,
**I want** the BoardContext builder to include recent task comments,
**So that** agents can see the latest discussion and any instructions from humans or previous agent runs.

**Acceptance Criteria:**

**Given** a board task with 8 comments, 3 of which are from the last 24 hours
**When** BoardContext builder builds
**Then** the board-context section includes a "Recent Comments" subsection with up to 5 most recent comments
**And** each comment shows: author_name, body (truncated to 200 chars)

**Given** a board task with no comments
**When** BoardContext builder builds
**Then** no "Recent Comments" subsection appears

**Technical notes:**
- Comments query: `task.task_comments.recent.limit(5)` (assumes `recent` scope exists on TaskComment — order by created_at desc)
- Comment truncation: body to 200 chars to prevent context bloat
- If `recent` scope doesn't exist, add `scope :recent, -> { order(created_at: :desc) }` to TaskComment model

---

## Dependency Graph

```
Story 27.1 (BoardContext builder — task details)
    │
    └──→ Story 27.2 (Recent comments)
```

---

## Implementation Notes

- BoardContext builder is relatively simple — 2 stories covering the full design doc spec
- Position hint `:top` puts board context near the beginning, right after critical-rules and agent-role — the agent sees "what I'm working on" early
- `board-context` uses priority `:important` — not critical (agent can still function without it), but important enough to be near the top
- Security note: BoardContext only reads data from the session's own board_task — no cross-project data exposure
- Register builder in `SessionContextConstructor::BUILDERS` after `WorkflowContext` and before `Tools`
