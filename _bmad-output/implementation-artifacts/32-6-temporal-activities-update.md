# Story 32.6: Update Temporal Activities to Use Services

Status: review

## Story

As a developer,
I want Temporal activities to delegate business logic to services,
so that activities are thin wrappers and all logic has a single source of truth.

## Acceptance Criteria

1. `LaunchStepSessionActivity#execute` calls `SessionService.create_for_workflow_step(step_run:)` — single line replacing all manual setup
2. `LaunchStepSessionActivity` no longer contains `attach_resolved_resources!` private method
3. `UpdateWorkflowRunStatusActivity` is verified clean — only calls AASM transitions (`run.start!`, `run.complete!`, `run.fail!`) which now have no orchestration side effects
4. `CompleteStepActivity` is verified — delegates to service if side effects needed beyond `mark_completed!`
5. `PrepareStepActivity` is verified — `mark_running!`, `create_sub_step_runs!` are data operations, acceptable
6. `ContainerPhaseActivity` and `ContainerService` are NOT modified — already encapsulated behind strategy pattern
7. All activity tests pass; updated to test service delegation

## Tasks / Subtasks

- [x] Task 1: Simplify `LaunchStepSessionActivity` (AC: 1, 2)
  - [x] Replace entire `execute` body with `SessionService.create_for_workflow_step(step_run:)` (done in 32.1)
  - [x] Return `{ "terminal_session_id" => session.id, "step_run_id" => step_run.id }` from service result
  - [x] Delete `attach_resolved_resources!` method (done in 32.1)
- [x] Task 2: Audit `UpdateWorkflowRunStatusActivity` (AC: 3)
  - [x] Read current implementation — only AASM transitions
  - [x] Verify it only calls AASM transitions on WorkflowRun ✓
  - [x] Confirm callbacks are clean (from story 32.5) — no service calls in transitions ✓
- [x] Task 3: Audit `CompleteStepActivity` (AC: 4)
  - [x] Read current implementation — only mark_completed!/mark_failed! + output validation
  - [x] Verify only calls data operations ✓
- [x] Task 4: Audit `PrepareStepActivity` (AC: 5)
  - [x] Read current implementation — mark_running!, create_sub_step_runs!, workspace prep
  - [x] Verify pure data ops ✓
  - [x] Confirm no Temporal or service calls ✓
- [x] Task 5: Verify non-touched activities (AC: 6)
  - [x] Confirm ContainerPhaseActivity untouched ✓
  - [x] Confirm ContainerService untouched ✓
- [x] Task 6: Tests (AC: 7)
  - [x] LaunchStepSessionActivity tests covered by SessionService tests (32.1)
  - [x] Other activity tests verified passing

## Dev Notes

### Architecture

- Activities remain Temporal entry points — they don't disappear
- Pattern becomes: `Activity → Service → Model` instead of `Activity → Model (with callbacks → Temporal)`
- This is mostly a verification story — `LaunchStepSessionActivity` is the main change

### Key Files to Modify

| File | Action |
|------|--------|
| `app/temporal/activities/workflow/launch_step_session_activity.rb` | **MODIFY** — delegate to SessionService |
| `app/temporal/activities/workflow/update_workflow_run_status_activity.rb` | **AUDIT** — verify clean |
| `app/temporal/activities/workflow/complete_step_activity.rb` | **AUDIT** — verify clean |
| `app/temporal/activities/workflow/prepare_step_activity.rb` | **AUDIT** — verify clean |

### Current `LaunchStepSessionActivity#execute` (69 lines → ~5 lines)

```ruby
# BEFORE
def execute(input)
  step_run = StepRun.find(input["step_run_id"])
  workflow_run = step_run.workflow_run
  step = step_run.step
  prompt = step.instructions.presence || "Execute step: #{step.name}"
  default_runtime = step.required_agent_runtime.presence || ...
  session = TerminalSession.create!(user:, project:, session_type: "workflow_step", ...)
  step_run.update!(terminal_session: session)
  config = SessionConfigResolver.resolve(session)
  session.update!(agent_type: config[:agent_runtime], mode: config[:mode])
  attach_resolved_resources!(session, config)
  step_run.broadcast_update!
  session.start! if session.may_start?
  { "terminal_session_id" => session.id, "step_run_id" => step_run.id }
end

# AFTER
def execute(input)
  step_run = StepRun.find(input["step_run_id"])
  result = SessionService.create_for_workflow_step(step_run: step_run)
  { "terminal_session_id" => result.id, "step_run_id" => step_run.id }
end
```

### References

- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb] — main target
- [Source: app/temporal/activities/workflow/update_workflow_run_status_activity.rb] — audit
- [Source: app/temporal/activities/workflow/complete_step_activity.rb] — audit
- [Source: app/temporal/activities/workflow/prepare_step_activity.rb] — audit
- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-326] — epic definition

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- LaunchStepSessionActivity already simplified in 32.1 to single SessionService call
- UpdateWorkflowRunStatusActivity: clean — only AASM transitions, callbacks have no side effects
- CompleteStepActivity: clean — only mark_completed!/mark_failed! + output validation
- PrepareStepActivity: clean — only mark_running!, create_sub_step_runs!, workspace prep
- All activities follow Activity → Service → Model pattern

### File List

- app/temporal/activities/workflow/launch_step_session_activity.rb (VERIFIED — modified in 32.1)
- app/temporal/activities/workflow/update_workflow_run_status_activity.rb (VERIFIED — clean)
- app/temporal/activities/workflow/complete_step_activity.rb (VERIFIED — clean)
- app/temporal/activities/workflow/prepare_step_activity.rb (VERIFIED — clean)
