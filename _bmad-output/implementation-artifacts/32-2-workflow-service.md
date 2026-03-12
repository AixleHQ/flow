# Story 32.2: WorkflowService — Start and Manage Workflows

Status: review

## Story

As a developer,
I want a single `WorkflowService` that manages the full lifecycle of workflow runs,
so that Temporal details are hidden from controllers and workflow orchestration has a single entry point.

## Acceptance Criteria

1. `WorkflowService.start(workflow:, project:, user:, task: nil, mode: :interactive, overrides: {}, input_asset_ids: [], repository_ids: [])` creates `WorkflowRun`, creates `StepRun` per step, validates mode compatibility, starts Temporal via `TemporalWorkflowRegistry`
2. `WorkflowService.cancel(run:)` sends `workflow_cancelled` signal, cancels active step_runs and their sessions via `SessionService.cancel`, transitions run to `cancelled`
3. `WorkflowService.approve_step(step_run:)` calls `mark_completed!` and sends `step_completed` signal
4. `WorkflowService.retry_step(step_run:)` calls `mark_failed!` and sends `step_retried` signal
5. `WorkflowService.skip_step(step_run:, reason: nil)` calls `mark_skipped!` and sends `step_skipped` signal
6. `WorkflowService.notify_container_finished(step_run:)` sends `container_finished` signal to workflow execution workflow
7. `WorkflowRunsController` delegates all actions to `WorkflowService` — no direct Temporal calls
8. `WorkflowRunsController` private methods `start_temporal_workflow`, `send_workflow_signal`, `validate_mode!` are removed
9. `WorkflowRunStateMachine#on_cancelled` no longer calls `cancel_active_step_runs!` or `cancel_session` — only timestamp + broadcast
10. Mode validation logic moves from controller to `WorkflowService.start`
11. All existing tests pass; new unit tests cover `WorkflowService`

## Tasks / Subtasks

- [x] Task 1: Create `WorkflowService` (AC: 1-6)
  - [x] Create `app/services/workflow_service.rb` with class methods
  - [x] `start`: create WorkflowRun, create StepRuns, validate mode, call `TemporalWorkflowRegistry.start_workflow_execution`
  - [x] `cancel`: send signal, iterate active step_runs → `SessionService.cancel` for each session, `run.cancel!`
  - [x] `approve_step`: `step_run.mark_completed!` + `send_signal("step_completed")`
  - [x] `retry_step`: `step_run.mark_failed!("Retried by user")` + `send_signal("step_retried")`
  - [x] `skip_step`: `step_run.mark_skipped!(reason)` + `send_signal("step_skipped")`
  - [x] `notify_container_finished`: send `container_finished` signal to `"workflow-execution-#{step_run.workflow_run_id}"`
  - [x] Private: `workflow_execution_id(run)` → `"workflow-execution-#{run.id}"`, `send_signal(run, signal_name)`
- [x] Task 2: Simplify `WorkflowRunsController` (AC: 7, 8, 10)
  - [x] `create` → `WorkflowService.start(...)`; respond with run
  - [x] `approve_step` → `WorkflowService.approve_step(step_run:)`
  - [x] `retry_step` → `WorkflowService.retry_step(step_run:)`
  - [x] `skip_step` → `WorkflowService.skip_step(step_run:, reason:)`
  - [x] `cancel` → `WorkflowService.cancel(run:)`
  - [x] Remove `start_temporal_workflow`, `send_workflow_signal`, `validate_mode!`
- [x] Task 3: Clean `WorkflowRunStateMachine` (AC: 9)
  - [x] Remove `cancel_active_step_runs!` method
  - [x] Remove `cancel_session` helper
  - [x] `on_cancelled` → only `update_column(:completed_at, Time.current)` + `broadcast_run_update!`
  - [x] Keep `record_workflow_activity!` — notification concern, stays in callback
- [x] Task 4: Update `SessionService.finish` to call `notify_container_finished` (AC: 6)
  - [x] When finishing a `workflow_step` session, call `WorkflowService.notify_container_finished(step_run:)`
  - [x] This replaces the removed `signal_workflow_execution_finished` from story 32.1
- [x] Task 5: Tests (AC: 11)
  - [x] Unit tests for all `WorkflowService` public methods
  - [x] Update `WorkflowRunsController` tests
  - [x] Update `WorkflowRunStateMachine` tests (verify no session cancellation in callback)

## Dev Notes

### Architecture

- `WorkflowService` is the **middle layer** — uses `SessionService.cancel` downward, used by `TaskService` upward
- Encapsulates `workflow_execution_id` string format — no other code builds this string
- Mode validation (interactive vs non_interactive) is a business rule, belongs in service not controller

### Key Files to Modify

| File | Action |
|------|--------|
| `app/services/workflow_service.rb` | **CREATE** — new service |
| `app/controllers/api/v1/company/projects/workflow_runs_controller.rb` | **MODIFY** — delegate to WorkflowService |
| `app/state_machines/workflow_run_state_machine.rb` | **MODIFY** — remove cancel_active_step_runs!, cancel_session |
| `app/services/session_service.rb` | **MODIFY** — add notify_container_finished call in finish |
| `test/services/workflow_service_test.rb` | **CREATE** — new tests |

### Current Controller Logic to Extract

**`WorkflowRunsController#create`** (lines 20-37):
```
workflow = accessible_workflows.find(...)
run = current_project.workflow_runs.new(...)
validate_mode!(run, workflow)
run.save
workflow.steps.each { |step| run.step_runs.find_or_create_by!(step:) }
start_temporal_workflow(run)
```
→ `WorkflowService.start(workflow:, project:, user:, mode:, overrides:, ...)`

**`WorkflowRunsController#cancel`** (lines 72-77):
```
send_workflow_signal(run, "workflow_cancelled")
run.cancel! if run.may_cancel?
```
→ `WorkflowService.cancel(run:)` (which also cancels active sessions)

### Mode Validation Migration

Current `validate_mode!` in controller checks `step.allow_non_interactive` and `step_overrides`. This moves into `WorkflowService.start` — raise or add errors to run object before save.

### Dependency: Story 32.1

- `SessionService` must exist before `WorkflowService.cancel` can call `SessionService.cancel`
- `SessionService.finish` must be updated to call `WorkflowService.notify_container_finished`

### References

- [Source: app/controllers/api/v1/company/projects/workflow_runs_controller.rb] — current controller
- [Source: app/state_machines/workflow_run_state_machine.rb] — cancel_active_step_runs!, cancel_session
- [Source: app/services/temporal_workflow_registry.rb#start_workflow_execution] — Temporal entry point
- [Source: app/services/temporal_service.rb] — send_signal, cancel_workflow
- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-322] — epic definition

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- Created `WorkflowService` with 6 public class methods
- Controller reduced to thin delegation — no Temporal calls, no mode validation
- State machine `on_cancelled` simplified — no longer cancels sessions (service handles this)
- `SessionService.finish` now calls `WorkflowService.notify_container_finished` for workflow_step sessions
- 8 unit tests, 21 assertions, 0 failures; 6 controller tests pass

### File List

- app/services/workflow_service.rb (CREATED)
- app/controllers/api/v1/company/projects/workflow_runs_controller.rb (MODIFIED)
- app/state_machines/workflow_run_state_machine.rb (MODIFIED)
- app/services/session_service.rb (MODIFIED — uses WorkflowService.notify_container_finished)
- test/services/workflow_service_test.rb (CREATED)
