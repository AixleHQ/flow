# Story 27.1: BoardContext Builder

Status: review

## Story

As a system,
I want a BoardContext builder that injects board task details into the session context,
So that agents immediately know what task they're working on without calling MCP tools.

## Acceptance Criteria

1. **BoardContext applicable for board-triggered sessions** — Given a workflow session triggered from a board task (workflow_run.board_task present), when `ContextBuilders::BoardContext#applicable?` is called, then it returns `true`

2. **Not applicable for standalone sessions** — Given a standalone session (no board_task), when `applicable?` is called, then it returns `false`

3. **Not applicable for workflow without board task** — Given a workflow session not triggered from board (workflow_run.board_task is nil), when `applicable?` is called, then it returns `false`

4. **Produces board-context section with task details** — Given a board-triggered session, when `BoardContext#build` runs, then output includes a section with tag `board-context`, priority `:important`, position_hint `:top`, containing:
   - Board name
   - Task title and ID
   - Column name
   - Task priority (if present)
   - Task description (truncated to 500 chars, if present)
   - Task tags (if present)
   - Instruction to use board MCP tools for further interaction

5. **Builder registered in BUILDERS** — Given `SessionContextConstructor::BUILDERS`, when inspected, then `ContextBuilders::BoardContext` is present after `WorkflowContext` and before `Tools`

## Tasks / Subtasks

- [x] Task 1: Create BoardContext builder (AC: #1, #2, #3, #4)
  - [x] Create `app/services/context_builders/board_context.rb`
  - [x] Implement `applicable?` → `board_task.present?` (via Base#board_task helper)
  - [x] Implement `build` → returns array with single `board-context` section
  - [x] Build content: board name, task title+ID, column name, priority, description (truncated 500), tags
  - [x] Include instruction to use board MCP tools
- [x] Task 2: Register in SessionContextConstructor (AC: #5)
  - [x] Add `ContextBuilders::BoardContext` to BUILDERS after `WorkflowContext` and before `Tools`
- [x] Task 3: Write tests (AC: #1-#5)
  - [x] Create `test/services/context_builders/board_context_test.rb`
  - [x] Test `applicable?` returns true when board_task present
  - [x] Test `applicable?` returns false for standalone session
  - [x] Test `applicable?` returns false for workflow without board_task
  - [x] Test board-context section has correct tag, priority, position
  - [x] Test content includes board name, task title, column, priority, description, tags
  - [x] Test description truncation to 500 chars
  - [x] Test BUILDERS registration position

## Dev Notes

### Architecture Patterns

- **Builder pattern:** Extends `ContextBuilders::Base` from Story 25.2. Same interface: `applicable?`, `build`, `name`.
- **Navigation:** `board_task` helper already exists in Base class: `workflow_run&.board_task`
- **Single section builder:** Returns exactly 1 section (unlike WorkflowContext which returns up to 5).

### Implementation Details

- `board_task` resolved via: `session.step_run&.workflow_run&.board_task` — already implemented in `ContextBuilders::Base`
- `BoardTask` model: has `title`, `description`, `priority` (enumerize: low/medium/high/critical), `tags` (array), `task_type`, `position`
- `BoardTask` belongs_to: `board`, `board_column`, `assignee` (optional), `parent_task` (optional)
- `Board` model: has `name`
- `BoardColumn` model: has `name`
- Section: tag `board-context`, priority `:important`, position_hint `:top`
- Description truncation: `task.description.truncate(500)` — Ruby built-in String method
- Tags: `task.tags` is an array field — join with `', '`

### Existing Code Context

- `BoardContextResolver` exists for board MCP tools (resolves board_id → project) — NOT the same as this builder
- Board MCP tools (Epic 23): `board_get_task`, `board_add_comment`, `board_move_task`, etc.
- `ContextBuilders::Base#board_task` helper returns `workflow_run&.board_task`

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Factories:** Need `board`, `board_column`, `board_task`, `workflow_run` factories
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/board_context_test.rb`

### Project Structure Notes

- New file: `app/services/context_builders/board_context.rb`
- Modified: `app/services/session_context_constructor.rb` (add to BUILDERS)
- Test file: `test/services/context_builders/board_context_test.rb`

### References

- [Source: ai/session-context-constructor.md#5.4 BoardContext Builder] — Design specification with code
- [Source: ai/epics/epic-27-board-context-in-sessions.md#Story 27.1] — Acceptance criteria
- [Source: app/models/board_task.rb] — BoardTask model: title, description, priority, tags, board, board_column
- [Source: app/services/context_builders/base.rb#board_task] — Base helper

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — all tests passed on first run.

### Completion Notes List
- Created `ContextBuilders::BoardContext` extending Base, returning a single `board-context` section with tag, priority `:important`, position_hint `:top`
- Content includes board name, task title+ID, column, priority (if set), description (truncated 500), tags (joined), and MCP tools instruction
- Registered in `SessionContextConstructor::BUILDERS` after `WorkflowContext` and before `Tools`
- 11 tests, 35 assertions — all passing

### File List
- app/services/context_builders/board_context.rb (new)
- app/services/session_context_constructor.rb (modified — BUILDERS registration)
- test/services/context_builders/board_context_test.rb (new)
