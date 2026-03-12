# Epic 32: Service Layer Pyramid (TaskService / WorkflowService / SessionService)

> Move all business logic out of controllers, models, and state machine callbacks into three hierarchical services — the single entry points for operations on tasks, workflows, and sessions.

**Phase:** 18 (Depends on: Epic 8, 9, 10, 11, 17, 20–24, 29)

**User Outcome:** Controllers become thin (a single service call), models become clean (data + validations + broadcast), and business logic is concentrated in three services with a clear dependency hierarchy.

---

## Problem

Currently, business logic is spread across four layers:

1. **Controllers** directly create `WorkflowRun`, call `TemporalWorkflowRegistry`, and send Temporal signals — they know orchestration details.
2. **State machine callbacks** (`on_started`, `on_completed`, `on_cancelled`) start Temporal workflows, cancel sessions, and record activity — implicit control flow.
3. **Models** contain the methods `start_workflow!`, `request_finish!`, `cancel!`, `signal_workflow_execution_finished` — they know about Temporal directly.
4. **Temporal activities** contain business logic (step run creation, validation, session setup, container launch).

This leads to problems:
- **No single entry point** — the same operation can be launched from different places in different ways (a controller calls `TemporalWorkflowRegistry` directly, while an activity calls `session.start!`).
- **Implicit control flow** — the `on_started` callback in `TerminalSession` starts a Temporal workflow, which is not obvious when reading the controller.
- **Hard to test** — to test task creation you need to mock Temporal, ActionCable, and ActivityRecorder.
- **Duplication** — the logic for workflow auto-trigger and manual trigger is duplicated across `WorkflowAutoTriggerService`, `TasksController#trigger_workflow`, and `WorkflowRunsController#create`.

---

## Architecture

### Service pyramid (bottom to top)

```
┌─────────────────────────────────┐
│          TaskService            │  ← top level
│  create, update, destroy, move, │
│  trigger_workflow               │
├─────────────────────────────────┤
│        WorkflowService          │  ← middle level
│  start, cancel, approve_step,   │
│  retry_step, skip_step          │
├─────────────────────────────────┤
│        SessionService           │  ← bottom level
│  create_and_start, finish,      │
│  cancel, configure              │
└─────────────────────────────────┘
```

**Dependency rules:**
- `TaskService` → may use `WorkflowService`, but not the other way around
- `WorkflowService` → may use `SessionService`, but not the other way around
- `SessionService` → knows nothing about Task or Workflow (only about TerminalSession + Temporal)
- Controllers call **only** services, not models directly (except for reads)
- Temporal activities call **only** services
- Models do **not** contain business logic or side effects (except broadcast)

### Broadcast strategy

Broadcast stays in the models via `after_commit`, but is simplified:
- **No payload** — only `{ event: "board_task.updated", id: 123 }` or `{ event: "board_task.destroyed", id: 123 }`
- On receiving an event, the frontend itself refetches the needed data
- This removes the dependency on serializers in broadcast and eliminates the "which serializer to render with" problem
- For `destroyed` — the frontend removes the entity from the store without a request

---

## Stories

### Story 32.1: SessionService — session creation and launch

**As a** developer,
**I want** a single `SessionService` that encapsulates all session lifecycle operations,
**So that** neither controllers nor Temporal activities know about container orchestration details.

**Acceptance Criteria:**
- Created `app/services/session_service.rb` with class methods:
  - `create_and_start(user:, project:, session_type:, agent_type:, configured_agent: nil, params: {})` — creates a `TerminalSession`, resolves the config via `SessionConfigResolver`, attaches resources, transitions to `running`, launches the Temporal workflow
  - `finish(session:)` — sends the `container_finished` signal, handles errors
  - `cancel(session:)` — cancels the Temporal workflow, transitions to `failed`
  - `create_for_workflow_step(step_run:)` — creates a session of type `workflow_step`, binds it to step_run, resolves the config, launches. Used from `LaunchStepSessionActivity`
- The `TerminalSession` model is cleaned up:
  - Removed methods: `start_workflow!`, `request_finish!`, `cancel!`, `signal_workflow_execution_finished`, `cancel_workflow`, `signal_workflow`
  - Removed state machine callbacks: `on_started` no longer calls `start_workflow!`
  - The state machine remains for state transitions, but **without side effects** (no Temporal calls)
  - `on_started` → only `update!(started_at: Time.current)`
  - `on_finished` / `on_failed` → only `update!(finished_at: Time.current, container_id: nil)` and `sync_usage`
- `TerminalSessionsController#create` calls `SessionService.create_and_start(...)` instead of `session.save` + `session.start!`
- `TerminalSessionsController#finish` calls `SessionService.finish(session:)` instead of `session.request_finish!`
- `LaunchStepSessionActivity` calls `SessionService.create_for_workflow_step(step_run:)` instead of manually creating and configuring the session
- All calls to `TemporalService` from the `TerminalSession` model are moved to `SessionService`
- Existing tests updated, new unit tests for `SessionService`

**Technical notes:**
- `SessionService` internally uses `TemporalService`, `TemporalWorkflowRegistry`, `SessionConfigResolver` — these are infrastructure dependencies, not business ones
- The `strategy` method stays in the model — it is a pure factory with no side effects
- `available_tools` stays in the model — it is a query method
- `sync_usage` stays in the state machine callback — it is data sync, not a business operation
- `signal_workflow_execution_finished` moves to `SessionService` or `WorkflowService` (story 32.2 will decide)

---

### Story 32.2: WorkflowService — starting and managing workflows

**As a** developer,
**I want** a single `WorkflowService` that manages the full lifecycle of workflow runs,
**So that** Temporal details are hidden from controllers and the workflow orchestration has a single entry point.

**Acceptance Criteria:**
- Created `app/services/workflow_service.rb` with class methods:
  - `start(workflow:, project:, user:, task: nil, mode: :interactive, overrides: {}, input_asset_ids: [], repository_ids: [])` — creates a `WorkflowRun`, creates a `StepRun` for each step, validates mode compatibility, starts Temporal via `TemporalWorkflowRegistry.start_workflow_execution`
  - `cancel(run:)` — sends the `workflow_cancelled` signal, transitions the run to `cancelled`
  - `approve_step(step_run:)` — `mark_completed!` + sends the `step_completed` signal
  - `retry_step(step_run:)` — `mark_failed!` + sends the `step_retried` signal
  - `skip_step(step_run:, reason: nil)` — `mark_skipped!` + sends the `step_skipped` signal
  - `notify_container_finished(step_run:)` — sends the `container_finished` signal to the workflow execution. Called from `SessionService` or a state machine callback when a workflow_step session finishes
- `WorkflowRunsController` is simplified:
  - `create` → `WorkflowService.start(...)`
  - `approve_step` → `WorkflowService.approve_step(...)`
  - `retry_step` → `WorkflowService.retry_step(...)`
  - `skip_step` → `WorkflowService.skip_step(...)`
  - `cancel` → `WorkflowService.cancel(...)`
  - Removed the private methods `start_temporal_workflow` and `send_workflow_signal`
  - Removed `validate_mode!` — moved to `WorkflowService.start`
- `WorkflowRunStateMachine` cleaned up:
  - `on_cancelled` no longer cancels step_runs and sessions directly — `WorkflowService.cancel` does that
  - `record_workflow_activity!` stays — it is a notification concern, similar to broadcast
  - The `cancel_session` helper is removed — `WorkflowService` calls `SessionService.cancel`
- Temporal activities (`UpdateWorkflowRunStatusActivity`) may call `WorkflowService` for state transitions if side effects are needed
- Existing tests updated, new unit tests for `WorkflowService`

**Technical notes:**
- `WorkflowService` knows about `TemporalService`, `TemporalWorkflowRegistry` — infrastructure dependencies
- `WorkflowService` can use `SessionService.cancel(...)` to cancel active sessions when cancelling a workflow
- Mode validation (interactive vs non_interactive) moves from the controller to the service — it is a business rule
- Building the `workflow_id` string `"workflow-execution-#{run.id}"` is encapsulated in the service

---

### Story 32.3: TaskService — task management

**As a** developer,
**I want** a single `TaskService` for all task operations,
**So that** activity recording, workflow auto-triggering, and validation happen consistently regardless of entry point.

**Acceptance Criteria:**
- Created `app/services/task_service.rb` with class methods:
  - `create(board:, params:, actor:)` — creates a task, records the `task_created` activity, checks the auto-trigger (column binding), and calls `WorkflowService.start(...)` if needed
  - `update(task:, params:, actor:)` — updates the task, records the `task_updated` activity with changes
  - `destroy(task:, actor:)` — deletes the task, records the `task_deleted` activity
  - `move(task:, to_column:, position: nil, actor:, actor_type: :human)` — moves the task (logic from `TaskMoveService`), creates a `ColumnTransition`, checks the auto-trigger, and calls `WorkflowService.start(...)` if needed
  - `trigger_workflow(task:, binding:, actor:)` — manual trigger: validates the manual binding, checks that there are no active runs, calls `WorkflowService.start(..., task: task)`
- `TasksController` is simplified:
  - `create` → `TaskService.create(board:, params:, actor:)`
  - `update` → `TaskService.update(task:, params:, actor:)`
  - `destroy` → `TaskService.destroy(task:, actor:)`
  - `move` → `TaskService.move(task:, to_column:, ...)`
  - `trigger_workflow` → `TaskService.trigger_workflow(task:, binding:, actor:)`
  - Removed all direct calls to `ActivityRecorder`, `WorkflowAutoTriggerService`, `TemporalWorkflowRegistry`
- `TaskMoveService` is removed — the logic is merged into `TaskService.move`
- `WorkflowAutoTriggerService` is removed — the auto-trigger logic is inline in `TaskService.move` and `TaskService.create`
- Existing tests updated, new unit tests for `TaskService`

**Technical notes:**
- `TaskService` uses `WorkflowService.start(...)` to start workflows — it does not know about Temporal
- `TaskService` uses `ActivityRecorder` to record activity — this remains a separate infrastructure service
- The reorder logic (insert_at_position, reorder_within_column) from `TaskMoveService` moves into private methods of `TaskService`
- Auto-trigger check: `column.column_workflow_binding&.auto? → WorkflowService.start(...)`

---

### Story 32.4: Simplifying broadcasts in models

**As a** developer,
**I want** model broadcasts to send minimal events without payload,
**So that** frontend refetches data using existing API endpoints and we don't depend on serializers in broadcasts.

**Acceptance Criteria:**
- `BoardTask#broadcast_change` simplified:
  - Format: `{ event: "board_task.<action>", id: <id> }` where action = `created` | `updated` | `destroyed`
  - Removed `BoardTaskSerializer` from the broadcast — no payload with task data
  - Channel: `board_<board_id>` (unchanged)
- `WorkflowRun` broadcast simplified similarly:
  - `{ event: "workflow_run.updated", id: <id> }` — instead of the full object
- `TerminalSession#broadcast_update` simplified:
  - `{ event: "terminal_session.updated", id: <id> }` — the frontend does a refetch
- `StepRun#broadcast_update!` simplified:
  - Instead of `touch` + `WorkflowRunChannel.broadcast_update(wr.reload)` — sends `{ event: "step_run.updated", id: <id>, workflow_run_id: <wr_id> }`
- Frontend updated:
  - WebSocket subscriptions handle the new event format
  - On receiving an event — invalidate/refetch the corresponding queries (React Query / RTK Query / Zustand)
  - For `destroyed` — remove from the store without a request
- Broadcast tests updated for the new format

**Technical notes:**
- `BoardChannel.broadcast_event` may need refactoring or replacement with a direct `ActionCable.server.broadcast`
- If the frontend uses React Query — invalidation by keys on receiving an event
- This is a breaking change for the frontend — coordination with frontend subscriptions is mandatory
- `ActivityRecorder` no longer broadcasts via `BoardChannel.broadcast_event` — the activity feed gets its own separate event `{ event: "board_activity.created", id: <id> }`

---

### Story 32.5: Clearing business logic out of state machine callbacks

**As a** developer,
**I want** state machine callbacks to only handle data updates and broadcasts (no external service calls),
**So that** the control flow is explicit and all orchestration goes through services.

**Acceptance Criteria:**
- `TerminalSessionStateMachine`:
  - `on_started` → only `update!(started_at: Time.current)`. Starting the Temporal workflow is removed (moved to `SessionService`)
  - `on_finished` → `sync_usage` + `update!(finished_at: Time.current, container_id: nil)`. `signal_workflow_execution_finished` removed (moved to `SessionService` / `WorkflowService`)
  - `on_failed` → same as `on_finished`
  - `on_ready` → `update!(ready_at: Time.current)` (unchanged)
- `WorkflowRunStateMachine`:
  - `on_started` → `update_column(:started_at, Time.current)` + broadcast (unchanged)
  - `on_completed` → `update_column(:completed_at, Time.current)` + broadcast (unchanged)
  - `on_cancelled` → `update_column(:completed_at, Time.current)` + broadcast. **Removed**: `cancel_active_step_runs!`, `cancel_session` — cancelling step_runs and sessions is moved to `WorkflowService.cancel`
  - `record_workflow_activity!` stays in the callback — it records activity, analogous to broadcast
- All state transitions are still invoked through AASM (`run.start!`, `session.finish!`), but now they are **only** transitions + data updates, without orchestration side effects
- Make sure the `after_commit` callbacks for broadcast are **not** removed — they remain

**Technical notes:**
- This is a glue story that anchors the result of stories 32.1 and 32.2 in the context of state machines
- Can be done in parallel with 32.1 and 32.2, but is finalized after them
- Key rule: a state machine callback may call `update!`, `update_column`, broadcast — but **not** `TemporalService`, `SessionService`, `WorkflowService`

---

### Story 32.6: Update Temporal activities to use services

**As a** developer,
**I want** Temporal activities to delegate business logic to services,
**So that** activities are thin wrappers and all logic has a single source of truth.

**Acceptance Criteria:**
- `LaunchStepSessionActivity` simplified:
  - Instead of manual `TerminalSession.create!` + `SessionConfigResolver.resolve` + `attach_resolved_resources!` + `session.start!`
  - Calls `SessionService.create_for_workflow_step(step_run:)` — a single call
  - The private method `attach_resolved_resources!` removed from the activity
- `UpdateWorkflowRunStatusActivity` reviewed:
  - If the activity calls `run.start!` / `run.complete!` / `run.fail!` — this is OK as long as the callbacks are clean (story 32.5)
  - If the activity needs side effects (canceling sessions on fail) — it delegates to `WorkflowService`
- `CompleteStepActivity` reviewed:
  - If logic beyond `mark_completed!` is needed — it delegates to `WorkflowService`
- `PrepareStepActivity` reviewed:
  - `mark_running!`, `create_sub_step_runs!` — acceptable, these are data operations
  - If side effects are added — delegate to a service
- All modified activities are covered by tests

**Technical notes:**
- Activities remain the entry point for Temporal — they don't disappear, but become thin
- Pattern: `Activity → Service → Model` instead of `Activity → Model (with callbacks → Temporal)`
- `ContainerPhaseActivity` and `ContainerService` are not affected — they are already encapsulated behind the strategy pattern

---

### Story 32.7: Remove deprecated services and cleanup

**As a** developer,
**I want** to remove obsolete services and methods,
**So that** there's a single way to perform each operation.

**Acceptance Criteria:**
- Removed `app/services/task_move_service.rb` — logic moved into `TaskService`
- Removed `app/services/workflow_auto_trigger_service.rb` — logic moved into `TaskService`
- Removed from `TerminalSession`:
  - `start_workflow!`
  - `request_finish!` (public method — replaced by `SessionService.finish`)
  - `cancel!` (override — replaced by `SessionService.cancel`)
  - `signal_workflow`, `signal_workflow_execution_finished`, `cancel_workflow` (private)
- Removed from `WorkflowRunStateMachine`:
  - `cancel_active_step_runs!`
  - `cancel_session`
- Removed from `WorkflowRunsController`:
  - `start_temporal_workflow`
  - `send_workflow_signal`
  - `validate_mode!`
- Check: `grep -r "WorkflowAutoTriggerService\|TaskMoveService" --include="*.rb"` — 0 results
- Check: `grep -r "start_workflow!\|request_finish!\|signal_workflow_execution_finished" app/models/` — 0 results (except comments)
- All tests pass, no broken references

**Technical notes:**
- This is the final cleanup story — done after all the previous ones
- Includes updating `app/temporal/activities/workflow/launch_step_session_activity.rb` tests, if not updated in 32.6
- Verify there are no orphaned routes or controller actions

---

## Dependency Graph

```
Story 32.1 (SessionService)
    │
    └──→ Story 32.2 (WorkflowService)
             │
             ├──→ Story 32.3 (TaskService)
             │
             └──→ Story 32.5 (State machine cleanup)
                      │
                      └──→ Story 32.6 (Temporal activities update)
                               │
                               └──→ Story 32.7 (Cleanup & removal)

Story 32.4 (Broadcast simplification) — independent, can be done in parallel
```

---

## Implementation Notes

- **Implementation order**: bottom-up along the pyramid — 32.1 (Session) → 32.2 (Workflow) → 32.3 (Task)
- **Story 32.4** (broadcast) can go in parallel, since it is an orthogonal concern
- **Story 32.5** — formal anchoring: after 32.1 and 32.2 the callbacks will already be clean, this story explicitly verifies and finalizes it
- **Testing**: each service is tested in isolation. For integration tests — the full flow from the controller through the services
- **API backward compatibility**: the external API (routes, request/response format) does not change — this is a purely internal refactor (except the broadcast format in 32.4)
- **DB migrations**: not required — this is a refactor of code, not the schema
- **ActivityRecorder** remains a separate infrastructure service — it is not part of the pyramid, but a utility used by `TaskService` and state machine callbacks
- **SessionConfigResolver** remains — used inside `SessionService`
- **ContainerService** and the strategies are not affected — they sit behind Temporal activities
