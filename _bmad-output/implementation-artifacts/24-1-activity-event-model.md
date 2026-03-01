# Story 24.1: Activity Event Model

**Epic:** 24 — Activity Feed & Filtered Views
**Status:** ready-for-dev
**Priority:** P1 (Post-MVP)

## User Story

**As a** system,
**I want** to record board activity events,
**So that** users and PMs can track what's happening on the board.

## Acceptance Criteria

- [x] Migration creates `board_activities` table with columns: `id`, `board_id` (not null), `board_task_id` (nullable), `event_type` (string, not null), `actor_id` (references users, not null), `actor_type` (string, not null), `metadata` (jsonb, default: {}), `created_at` (timestamp, not null)
- [x] `BoardActivity` model — append-only (no `updated_at`)
- [x] `event_type` enumerized: `task_created`, `task_updated`, `task_moved`, `comment_added`, `asset_attached`, `workflow_started`, `workflow_completed`, `workflow_failed`, `human_help_requested`
- [x] `actor_type` enumerized: `human`, `agent`, `system`
- [x] Activities created automatically from:
  - `TasksController#create`, `#update`, `#destroy`
  - `TaskMoveService` (on move)
  - `Task::CommentsController#create`
  - `Task::AssetsController#create`
  - `WorkflowRunStateMachine` callbacks (start, complete, fail)
  - `board_request_human_help` internal tool
- [x] `metadata` stores event-specific context (see examples below)
- [x] Board-level index on `[board_id, created_at]` for feed queries
- [x] Task-level index on `[board_task_id, created_at]`
- [x] Unit tests for model validations and scopes
- [x] Activity creation is non-blocking — wrapped in rescue to not fail parent operation

## Tasks / Subtasks

### 1. Migration
- Create `board_activities` table
- Indexes: `[board_id, created_at DESC]`, `[board_task_id, created_at DESC]`, `event_type`
- No `updated_at` column

### 2. Model
- `BoardActivity` with associations, enumerize, validations
- `self.timestamp_attributes_for_update = []`
- Scope: `for_board(board)`, `for_task(task)`, `by_event_type(type)`, `since(timestamp)`

### 3. ActivityRecorder service
- `ActivityRecorder.record(board:, event_type:, actor:, actor_type:, task: nil, metadata: {})`
- Non-blocking: wrapped in `rescue StandardError`
- Broadcasts `activity_created` event to BoardChannel

### 4. Integration points
- Add `ActivityRecorder.record(...)` calls to:
  - `Board::TasksController` (create, update, destroy)
  - `TaskMoveService#execute` (after transition)
  - `Board::Task::CommentsController#create`
  - `Board::Task::AssetsController#create`
  - `WorkflowRunStateMachine#broadcast_board_event!`
  - `InternalTools::BoardRequestHumanHelp#execute`
  - `InternalTools::BoardFailSession#execute`

### 5. Tests
- Model validations and scopes
- ActivityRecorder unit tests
- Verify non-blocking behavior (parent operation succeeds even if activity recording fails)

## Dev Notes

### Metadata Examples

```ruby
# task_moved
{ from_column: "Backlog", to_column: "Tech Design", trigger: "auto" }

# comment_added
{ tag: "tech_design", preview: "First 100 chars of comment body..." }

# workflow_started
{ workflow_name: "Create Tech Design", workflow_run_id: 123 }

# workflow_completed / workflow_failed
{ workflow_name: "Create Tech Design", workflow_run_id: 123, duration_seconds: 300 }

# human_help_requested
{ question: "Ambiguous requirement: should payment retry be synchronous?", workflow_run_id: 123 }

# asset_attached
{ name: "architecture.png", content_type: "image/png" }

# task_created
{ title: "Login API", task_type: "story" }

# task_updated
{ changes: { "priority" => ["low", "high"] } }
```

### Architectural Patterns

- Follow `ColumnTransition` immutable pattern — no `updated_at`, `self.timestamp_attributes_for_update = []`
- Use `enumerize` gem (not `ActiveRecord::Enum`) — project convention
- `metadata` is jsonb for flexibility — no schema validation on the field itself
- ActivityRecorder is a plain Ruby service class (not an ActiveJob) — synchronous but non-blocking via rescue
- Broadcast new activities via `BoardChannel.broadcast_event(board, "activity_created", ...)` — frontend will prepend to feed

### Non-blocking Pattern

```ruby
class ActivityRecorder
  def self.record(board:, event_type:, actor:, actor_type:, task: nil, metadata: {})
    BoardActivity.create!(
      board: board, board_task: task,
      event_type: event_type, actor: actor,
      actor_type: actor_type, metadata: metadata
    )
    BoardChannel.broadcast_event(board, "activity_created", { event_type: event_type, task_id: task&.id })
  rescue StandardError => e
    Rails.logger.warn("[ActivityRecorder] Failed: #{e.message}")
  end
end
```

### Dependencies
- Epic 20-23 must be complete (Board, Tasks, TaskMoveService, BoardChannel, MCP tools)
- No new gems required
- No frontend changes in this story (API + UI in 24.2)
