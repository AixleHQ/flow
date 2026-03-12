# Story 32.1: SessionService — Create and Start Sessions

Status: review

## Story

As a developer,
I want a single `SessionService` that encapsulates all session lifecycle operations,
so that neither controllers nor Temporal activities know about container orchestration details.

## Acceptance Criteria

1. `SessionService.create_and_start(user:, project:, session_type:, agent_type:, configured_agent: nil, params: {})` creates a `TerminalSession`, resolves config via `SessionConfigResolver`, attaches resources, transitions to `running`, and starts the Temporal workflow
2. `SessionService.finish(session:)` sends `container_finished` signal via `TemporalService` and handles errors gracefully
3. `SessionService.cancel(session:)` cancels the Temporal workflow and transitions session to `failed`
4. `SessionService.create_for_workflow_step(step_run:)` creates a `workflow_step` session, binds to step_run, resolves config, attaches resources, and starts — single entry point for `LaunchStepSessionActivity`
5. `TerminalSession` model no longer references `TemporalService` or `TemporalWorkflowRegistry` directly
6. `TerminalSession#start_workflow!`, `request_finish!`, `cancel!`, `signal_workflow`, `signal_workflow_execution_finished`, `cancel_workflow` methods are removed from the model
7. State machine callback `on_started` only calls `update!(started_at: Time.current)` — no Temporal workflow launch
8. State machine callbacks `on_finished` / `on_failed` only call `sync_usage` + `update!(finished_at:, container_id: nil)` — no `signal_workflow_execution_finished`
9. `TerminalSessionsController#create` delegates to `SessionService.create_and_start`
10. `TerminalSessionsController#finish` delegates to `SessionService.finish`
11. `LaunchStepSessionActivity#execute` delegates to `SessionService.create_for_workflow_step` (single call replaces all manual setup)
12. All existing tests pass; new unit tests cover `SessionService` methods

## Tasks / Subtasks

- [x] Task 1: Create `SessionService` (AC: 1, 2, 3, 4)
  - [x] Create `app/services/session_service.rb` with class methods
  - [x] `create_and_start`: build session, save, resolve config, attach resources, `session.start!`, start Temporal workflow
  - [x] `finish`: validate state, send `container_finished` signal, handle `workflow_step` session signaling to workflow execution
  - [x] `cancel`: cancel Temporal workflow via `TemporalService.cancel_workflow`, `session.fail!`
  - [x] `create_for_workflow_step`: extract logic from current `LaunchStepSessionActivity#execute`
- [x] Task 2: Clean `TerminalSession` model (AC: 5, 6, 7, 8)
  - [x] Remove `start_workflow!` method
  - [x] Remove `request_finish!` method
  - [x] Remove `cancel!` override method
  - [x] Remove private methods: `signal_workflow`, `signal_workflow_execution_finished`, `cancel_workflow`
  - [x] Simplify `on_started` callback — only `update!(started_at: Time.current)`
  - [x] Simplify `on_finished` — only `sync_usage` + timestamp/container_id update
  - [x] Simplify `on_failed` — same as `on_finished`
  - [x] Keep: `strategy`, `available_tools`, `workflow_id`, `active?`, `config_files`, `env_vars`
- [x] Task 3: Update `TerminalSessionsController` (AC: 9, 10)
  - [x] `create` → `SessionService.create_and_start(user: current_user, project:, session_type:, ...)`
  - [x] `finish` → `SessionService.finish(session: @session)`
- [x] Task 4: Update `LaunchStepSessionActivity` (AC: 11)
  - [x] Replace all manual session creation logic with `SessionService.create_for_workflow_step(step_run:)`
  - [x] Remove `attach_resolved_resources!` private method
- [x] Task 5: Tests (AC: 12)
  - [x] Unit tests for `SessionService` (mock `TemporalService`, `SessionConfigResolver`)
  - [x] Update `TerminalSessionsController` tests
  - [x] Update `LaunchStepSessionActivity` tests
  - [x] Verify `TerminalSession` model tests still pass without removed methods

## Dev Notes

### Architecture

- `SessionService` is the **bottom layer** of the service pyramid — it knows nothing about Tasks or Workflows
- Uses `TemporalService`, `TemporalWorkflowRegistry`, `SessionConfigResolver` as infrastructure dependencies
- `strategy` method stays on model — pure factory, no side effects
- `available_tools` stays on model — query method
- `sync_usage` stays in state machine callback — data sync, not business operation

### Key Files to Modify

| File | Action |
|------|--------|
| `app/services/session_service.rb` | **CREATE** — new service |
| `app/models/terminal_session.rb` | **MODIFY** — remove Temporal methods, simplify callbacks |
| `app/state_machines/terminal_session_state_machine.rb` | **MODIFY** — callbacks simplified (no Temporal calls) |
| `app/controllers/api/v1/terminal_sessions_controller.rb` | **MODIFY** — delegate to SessionService |
| `app/temporal/activities/workflow/launch_step_session_activity.rb` | **MODIFY** — delegate to SessionService |
| `test/services/session_service_test.rb` | **CREATE** — new tests |

### Current `TerminalSession` Methods to Migrate

```
start_workflow!          → SessionService.create_and_start (called after session.start!)
request_finish!          → SessionService.finish
cancel!                  → SessionService.cancel
signal_workflow          → SessionService (private: send_signal)
signal_workflow_execution_finished → SessionService.finish or WorkflowService.notify_container_finished
cancel_workflow          → SessionService.cancel (private: TemporalService.cancel_workflow)
```

### Current `LaunchStepSessionActivity#execute` Logic to Extract

Current flow (69 lines):
1. Find step_run, workflow_run, step
2. Build prompt, resolve runtime
3. `TerminalSession.create!` with all params
4. `step_run.update!(terminal_session: session)`
5. `SessionConfigResolver.resolve(session)`
6. `session.update!(agent_type:, mode:)`
7. `attach_resolved_resources!` (tools, skills, mcp_servers, repositories, input_assets)
8. `session.start!`

New flow (1 line): `SessionService.create_for_workflow_step(step_run:)`

### `signal_workflow_execution_finished` Decision

This method currently signals the parent `WorkflowExecutionWorkflow` when a `workflow_step` session finishes. Two options:
- **Option A**: Keep in `SessionService.finish` — session service knows about step_run association
- **Option B**: Move to `WorkflowService.notify_container_finished(step_run:)` — cleaner separation

**Decision**: Option A for now — `SessionService.finish` checks if session is `workflow_step` type and sends signal. This keeps `finish` atomic. Story 32.2 can refine if needed.

### Testing Approach

- Mock `TemporalService` and `TemporalWorkflowRegistry` in `SessionService` tests
- Test each public method independently
- Integration: controller test → service → mocked Temporal

### References

- [Source: app/models/terminal_session.rb] — current model with Temporal methods (lines 88-108, 158-184)
- [Source: app/state_machines/terminal_session_state_machine.rb] — current callbacks
- [Source: app/controllers/api/v1/terminal_sessions_controller.rb] — current controller
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb] — current activity
- [Source: app/services/session_config_resolver.rb] — used by SessionService internally
- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-321] — epic definition

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- Created `SessionService` with 4 public class methods encapsulating all session lifecycle operations
- Removed 6 Temporal-related methods from `TerminalSession` model (start_workflow!, request_finish!, cancel!, signal_workflow, signal_workflow_execution_finished, cancel_workflow)
- Simplified 3 state machine callbacks to only handle data updates (no Temporal calls)
- Controller delegates create/finish to SessionService
- LaunchStepSessionActivity reduced from 69 lines to 5 lines
- 9 new unit tests, 24 assertions, 0 failures
- All 18 controller tests pass, all 29 model tests pass

### File List

- app/services/session_service.rb (CREATED)
- app/models/terminal_session.rb (MODIFIED — removed Temporal methods, simplified callbacks)
- app/controllers/api/v1/terminal_sessions_controller.rb (MODIFIED — delegate to SessionService)
- app/temporal/activities/workflow/launch_step_session_activity.rb (MODIFIED — delegate to SessionService)
- test/services/session_service_test.rb (CREATED)
