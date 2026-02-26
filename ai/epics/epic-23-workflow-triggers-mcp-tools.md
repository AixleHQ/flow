# Epic 23: Workflow Triggers & Board MCP Tools

> Column-workflow bindings with auto/manual triggers, cooldown mechanism, and 13 internal MCP tools for agent interaction with the board.

**Phase:** 14 (Depends on: Epic 20, Epic 21, Epic 22, Epic 11 Workflows, Epic 18/19 Internal Tools)

**PRD:** [Board & Tasks PRD](../prd/board-tasks.md)

**User Outcome:** Users bind workflows to columns with auto/manual trigger modes. Tasks entering auto-trigger columns automatically start workflows. Agents interact with the board through 13 MCP tools — reading tasks, writing comments, attaching files, and moving tasks — all with auto-resolved board context.

**FRs Covered:** FR6, FR7, FR8, FR9, FR10, FR11, FR32-FR45

---

## Problem

Board and tasks exist (Epic 20-22), but they're passive — a regular Kanban board. This epic adds the intelligence layer: column-workflow bindings that turn task movement into workflow triggers, and MCP tools that give agents full board interaction capabilities.

---

## Architecture Summary

```
User drags task to column
    │
    ├── BoardColumn has workflow binding?
    │     ├── No → nothing happens
    │     └── Yes → check trigger mode
    │           ├── auto → CooldownService.can_trigger?(task, column)
    │           │    ├── No (cooldown active) → skip
    │           │    └── Yes → TemporalService.start_workflow(workflow, board_task: task)
    │           └── manual → show "Start Workflow" button on task card
    │
    └── ColumnTransition.create!(task, from_column, to_column, actor)

Agent in workflow session
    │
    └── MCP tools available (auto-injected, workflow_only: true)
          ├── Read: list_tasks, get_task, get_comments, get_task_assets, get_board_info
          ├── Write: create_task, update_task, move_task, add_comment, attach_asset, add_tag, remove_tag
          └── Diagnostic: fail_session, request_human_help
          
    board_id resolved from: workflow_run.board_task.board_id (never passed by agent)
```

---

## Stories

### Story 23.1: Column-Workflow Binding Model

**As a** user,
**I want** to bind a workflow to a board column,
**So that** the workflow can be triggered when tasks enter that column.

**Acceptance Criteria:**
- Migration creates `column_workflow_bindings` table:
  - `id`, `board_column_id` (references, not null, unique)
  - `workflow_id` (references, not null)
  - `trigger_mode` (string, not null, default: "manual")
  - `cooldown_seconds` (integer, not null, default: 5)
  - `timestamps`
- `ColumnWorkflowBinding` model with:
  - `belongs_to :board_column`, `belongs_to :workflow`
  - `enumerize :trigger_mode, in: %i[auto manual], default: :manual`
  - Validation: workflow must be project-scoped (same project as board)
  - Validation: one binding per column (unique index on `board_column_id`)
- API: CRUD at `/board/columns/:column_id/workflow_binding` (singular)
- Pundit policy: Admin only
- `BoardColumnSerializer` includes binding info: `workflow_id`, `workflow_name`, `trigger_mode`, `cooldown_seconds`

**Technical notes:**
- One binding per column — if user wants different workflow, they replace the binding
- `cooldown_seconds` default 5 — prevents double-trigger from drag-and-drop jitter

---

### Story 23.2: Workflow Deletion Protection

**As a** system,
**I want** to prevent deletion of workflows bound to columns,
**So that** board automation doesn't break silently.

**Acceptance Criteria:**
- `Workflow` model gains `has_many :column_workflow_bindings`
- Before-destroy validation: if `column_workflow_bindings.any?`, prevent deletion with error message listing which columns use this workflow
- API returns 422 with clear error: "Cannot delete workflow 'X' — bound to column 'Y' in project 'Z'"
- User must unbind workflow from column before deleting it

**Technical notes:**
- Simple `before_destroy` callback with `:abort`
- Error message should include column and project names for clarity

---

### Story 23.3: Auto-Trigger on Task Column Entry

**As a** system,
**I want** to automatically start a workflow when a task enters a column with auto trigger,
**So that** task movement drives the AI execution pipeline.

**Acceptance Criteria:**
- After task moves to new column (Story 21.4 move endpoint):
  1. Check if target column has binding with `trigger_mode: :auto`
  2. If yes, check cooldown: `CooldownService.can_trigger?(task, column)`
  3. If cooldown allows, start workflow via `TemporalService.start_workflow`
  4. Create `WorkflowRun` with `board_task_id` reference
- `WorkflowRun` migration: add `board_task_id` (references board_tasks, nullable)
- `CooldownService`: checks if last trigger for (task_id, column_id) was within `cooldown_seconds`
  - Uses Redis: key `board_trigger:#{task_id}:#{column_id}`, TTL = cooldown_seconds
  - If key exists → cooldown active, skip trigger
  - If key absent → set key with TTL, proceed with trigger
- Workflow execution receives task context: `board_task_id` in workflow input
- ActionCable broadcast: `workflow_started` event to board channel

**Technical notes:**
- Trigger happens in `TaskMoveService` (extract from controller) — single place for move logic
- `TaskMoveService#execute`: move task → create transition → check binding → trigger workflow
- Redis-based cooldown is simple and fast — no DB queries
- `board_task_id` on `WorkflowRun` enables: indicator on card (Epic 22), MCP tool context resolution

---

### Story 23.4: Manual Trigger Button

**As a** user,
**I want** to manually start a bound workflow for a task,
**So that** I control when the workflow runs on manual-trigger columns.

**Acceptance Criteria:**
- Task card and task detail sidebar show "Start Workflow" button when:
  - Task is in a column with `trigger_mode: :manual` binding
  - No active workflow run for this task
- Button click → API: `POST /tasks/:task_id/trigger_workflow`
- Endpoint: validates column has manual binding, starts workflow, returns workflow_run
- Same workflow execution as auto-trigger but initiated by user action
- Button disabled while workflow is running (indicator shown instead)

**Technical notes:**
- Reuses same `TaskMoveService` trigger logic, just called directly instead of after move
- Frontend: button visibility controlled by column binding data from board API

---

### Story 23.5: Column Transition History

**As a** system,
**I want** to record every task movement between columns,
**So that** we have audit trail and data for future analytics.

**Acceptance Criteria:**
- Migration creates `column_transitions` table:
  - `id`, `board_task_id` (references, not null)
  - `from_column_id` (references board_columns, nullable — null for initial placement)
  - `to_column_id` (references board_columns, not null)
  - `actor_id` (references users, not null)
  - `actor_type` (string, not null) — `human`, `agent`, `auto_trigger`
  - `workflow_run_id` (references, nullable) — if move triggered a workflow
  - `created_at` (timestamp, not null)
- `ColumnTransition` model — append-only, no updates or deletes
- Created in `TaskMoveService` on every task column change
- `actor_type: :agent` when MCP `move_task` tool is used
- `actor_type: :auto_trigger` when system moves task (future: webhook triggers)
- API: `GET /tasks/:task_id/transitions` — task movement history

**Technical notes:**
- No `updated_at` — transitions are immutable events
- Foundation for future analytics (time per column, bottleneck detection)
- `actor_id` for agent actions = task assignee (per PRD decision)

---

### Story 23.6: Board MCP Read Tools (5 tools)

**As an** agent in a workflow session,
**I want** to read board data through MCP tools,
**So that** I can understand task context and board structure.

**Acceptance Criteria:**
- 5 internal tools registered with `kind: :internal`, `execution_mode: :app`, `workflow_only: true`:

**`list_tasks`:**
- Parameters: `column_name` (optional), `tag` (optional), `task_type` (optional), `assignee_id` (optional)
- Returns: array of task summaries (id, title, type, priority, assignee, column, tags)
- board_id auto-resolved from session context

**`get_task`:**
- Parameters: `task_id` (required)
- Returns: full task details including description, comments count, assets count, parent/children info

**`get_comments`:**
- Parameters: `task_id` (required), `tag` (optional), `author_type` (optional)
- Returns: filtered comments with body, tags, author_type, created_at

**`get_task_assets`:**
- Parameters: `task_id` (required), `tag` (optional)
- Returns: asset metadata with presigned download URLs

**`get_board_info`:**
- Parameters: none
- Returns: board structure — columns with names, positions, purposes, workflow bindings

**Technical notes:**
- All tools inherit from `InternalTools::Base` (existing pattern)
- board_id resolution: `session.workflow_run&.board_task&.board_id` or `session.project.board.id`
- Tools validate that requested task belongs to session's board (security)
- `get_board_info` is the key tool — agent reads `purpose` to understand what to do

---

### Story 23.7: Board MCP Write Tools (6 tools)

**As an** agent in a workflow session,
**I want** to modify board data through MCP tools,
**So that** I can create tasks, add comments, attach files, and move tasks.

**Acceptance Criteria:**
- 6 internal tools registered with `kind: :internal`, `execution_mode: :app`, `workflow_only: true`:

**`create_task`:**
- Parameters: `title` (required), `description`, `task_type`, `column_name`, `tags`
- Creates task in specified column (or first column if not specified)
- `author_type: :agent` set on creation

**`update_task`:**
- Parameters: `task_id` (required), `title`, `description`, `priority`, `tags`, `task_type`
- Updates specified fields only

**`move_task`:**
- Parameters: `task_id` (required), `column_name` (required)
- Moves task to named column — triggers same `TaskMoveService` logic
- Can trigger cascade: agent moves task → auto-trigger → new workflow (if target column has auto binding)

**`add_comment`:**
- Parameters: `task_id` (required), `body` (required), `tags` (optional array)
- `author_type` auto-set to `:agent`
- `author_id` = task assignee (per PRD decision)

**`attach_asset`:**
- Parameters: `task_id` (required), `file_content` (required, base64), `name` (required), `tags` (optional)
- Creates TaskAsset from base64-encoded content
- `author_type` auto-set to `:agent`

**`add_tag` / `remove_tag`:**
- Parameters: `entity_type` (task/comment), `entity_id` (required), `tag` (required)
- Adds/removes tag from entity's tags array

**Technical notes:**
- Write tools need careful authorization: agent acts as task assignee
- `move_task` calling `TaskMoveService` means agent-initiated moves also trigger bindings and record transitions
- `attach_asset` uses base64 because agents can't upload multipart — they read file, encode, and send via MCP
- Broadcast events via ActionCable after each write operation

---

### Story 23.8: Agent Self-Diagnostic Tools (2 tools)

**As an** agent in a workflow session,
**I want** to signal when I'm stuck or need human help,
**So that** the system can handle failures gracefully.

**Acceptance Criteria:**
- 2 internal tools registered with `kind: :internal`, `execution_mode: :app`, `workflow_only: true`:

**`fail_session`:**
- Parameters: `reason` (required string)
- Terminates the workflow session with error
- Sets workflow_run status to `failed` with reason
- Adds system comment on task: "Agent terminated session: {reason}" with tag `system`
- ActionCable broadcast: `workflow_failed` event

**`request_human_help`:**
- Parameters: `question` (required string)
- Pauses the workflow session
- Sets workflow_run status to `awaiting_input`
- Adds system comment on task: "Agent requests help: {question}" with tag `human_help`
- ActionCable broadcast: `human_help_requested` event
- UI shows notification on task card

**Technical notes:**
- These tools interact with the Temporal workflow execution — may need signal mechanism
- `fail_session`: could raise exception caught by workflow, or send Temporal signal
- `request_human_help`: needs a way to pause and resume — Temporal signal + wait pattern
- Implementation depends on existing workflow execution pattern in `WorkflowExecutionWorkflow`

---

### Story 23.9: Board Context Auto-Resolution (FR45)

**As a** system,
**I want** board_id to be automatically resolved from session context,
**So that** agents never need to pass board_id and cannot access other projects' boards.

**Acceptance Criteria:**
- All board MCP tools resolve board_id from session context chain:
  1. `session.workflow_run.board_task.board_id` (if workflow was triggered from board)
  2. `session.project.board.id` (fallback for workflow sessions not triggered from board)
- `board_id` is NOT a parameter in any MCP tool
- All task operations validate: `task.board_id == resolved_board_id`
- Security test: agent cannot read/write tasks from different board

**Technical notes:**
- Create `BoardContextResolver` service: given a `TerminalSession`, returns `Board`
- All board MCP tools call resolver in `before_execute` or via shared concern
- If no board found → return error "No board available in current context"

---

### Story 23.10: Board MCP Tools Seed & Registration

**As a** developer,
**I want** all 13 board MCP tools seeded and registered,
**So that** they're available in workflow sessions after deploy.

**Acceptance Criteria:**
- Seeds create 13 Tool records:
  - 5 read tools: `board_list_tasks`, `board_get_task`, `board_get_comments`, `board_get_task_assets`, `board_get_board_info`
  - 6 write tools: `board_create_task`, `board_update_task`, `board_move_task`, `board_add_comment`, `board_attach_asset`, `board_manage_tags`
  - 2 diagnostic tools: `board_fail_session`, `board_request_human_help`
- All tools: `kind: :internal`, `execution_mode: :app`, `workflow_only: true`
- All tools: `scope: nil` (internal, available system-wide)
- Each tool has proper `input_schema` (JSON Schema) and `description`
- Tool names prefixed with `board_` to avoid naming conflicts with existing tools
- Seeds are idempotent: `find_or_create_by!(name: ...)`

**Technical notes:**
- `workflow_only: true` means these tools auto-inject into `workflow_step` sessions only
- Prefix `board_` distinguishes from potential future tools (e.g. `list_tasks` for Linear integration)
- Seeds file: add to existing `db/seeds.rb` or create `db/seeds/board_tools.rb`

---

## Dependency Graph

```
Story 23.1 (Binding model)
    │
    ├──→ Story 23.2 (Deletion protection)
    │
    ├──→ Story 23.3 (Auto-trigger) ← also depends on 21.4 (move task)
    │
    └──→ Story 23.4 (Manual trigger button)

Story 23.5 (Transition history) ← depends on 21.4 (move task)

Story 23.9 (Context resolution) ← independent foundation
    │
    ├──→ Story 23.6 (Read tools)
    │
    ├──→ Story 23.7 (Write tools)
    │
    └──→ Story 23.8 (Diagnostic tools)

Story 23.10 (Seeds) ← after 23.6, 23.7, 23.8
```

---

## Implementation Notes

- `TaskMoveService` is the central orchestrator: move task → record transition → check binding → trigger workflow → broadcast events
- Redis cooldown is stateless and fast — no need for database records for trigger throttling
- MCP tools follow existing `InternalTools::Base` pattern from Epic 18
- `board_` prefix on tool names is important for namespace isolation
- `fail_session` and `request_human_help` are the most complex tools — they need to interact with Temporal workflow execution state
