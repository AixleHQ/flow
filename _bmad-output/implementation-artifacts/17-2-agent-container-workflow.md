# Story 17.2: Agent Container Workflow

Status: review

## Story

As a platform engineer,
I want a dedicated agent workflow that takes only `session_id` as input,
so that activities don't manually resolve strategies and the workflow code is minimal.

## Acceptance Criteria

1. **AC1: New workflow class** — `Workflows::AgentContainerWorkflow` with input `{ session_id: }`. Registered in `WorkflowService` as `agent_container_workflow`.

2. **AC2: Pull phase** — Calls `PullAgentImageActivity(session_id:)`. Activity loads session, calls `session.strategy.pull_image`.

3. **AC3: Execute phase** — Calls `ExecuteAgentContainerActivity(session_id:)`. Activity calls `ContainerService.execute(session: session)`. Strategy resolved inside service from session.

4. **AC4: Signal wait** — After execute, checks `agent_completed` flag in result. If false (interactive session), waits for `container_finished` signal with 23h timeout. If true (non-interactive, exec already blocked), skips.

5. **AC5: Cleanup phase** — Calls `CleanupAgentContainerActivity(session_id:)`. Activity calls `ContainerService.cleanup(session: session)`. Runs `before_cleanup` (artifact collection) + `cleanup` (stop/remove container) + marks session collected.

6. **AC6: Error resilience** — If execute fails, workflow still attempts cleanup (best-effort). Session is already marked failed by strategy error handling (Story 17.8).

7. **AC7: Timeouts** — Execute: 300s for interactive (quick phases), 85800s for non-interactive. Signal: 82800s (23h). Cleanup: 120s. Pull: 600s.

## Tasks / Subtasks

- [x] Task 1: Create `Workflows::AgentContainerWorkflow` (AC: #1, #4, #7)
  - [x] 1.1 Define workflow with `session_id` input
  - [x] 1.2 Implement signal handling (reuse `container_finished` signal name)
  - [x] 1.3 Add timeout calculation based on session mode
  - [x] 1.4 Add error-resilient cleanup (begin/rescue around cleanup activity)
- [x] Task 2: Create `PullAgentImageActivity` (AC: #2)
  - [x] 2.1 Load session, delegate to `session.strategy.pull_image`
  - [x] 2.2 Error handling: wrap Docker errors with TemporalExceptions
- [x] Task 3: Create `ExecuteAgentContainerActivity` (AC: #3)
  - [x] 3.1 Load session, delegate to `ContainerService.execute(session:)`
  - [x] 3.2 Return result hash (container_id, urls, agent_completed flag)
- [x] Task 4: Create `CleanupAgentContainerActivity` (AC: #5, #6)
  - [x] 4.1 Load session, delegate to `ContainerService.cleanup(session:)`
  - [x] 4.2 Mark session collected after cleanup
  - [x] 4.3 Handle container-not-found gracefully
- [x] Task 5: Register workflow in WorkflowService (AC: #1)
- [x] Task 6: Write tests for workflow and activities

## Dev Notes

### Architecture

Current workflow passes `{strategy_type, strategy_input: {user_id, agent_type, session_id, route_token, credential_id, mode}}` — a serialization/deserialization dance. New workflow passes only `{session_id}`, everything resolved from DB.

### Key files to create

- `web/app/temporal/workflows/agent_container_workflow.rb`
- `web/app/temporal/activities/pull_agent_image_activity.rb`
- `web/app/temporal/activities/execute_agent_container_activity.rb`
- `web/app/temporal/activities/cleanup_agent_container_activity.rb`

### Key files to modify

- `web/app/services/workflow_service.rb` — register new workflow
- `web/config/temporal_activities.rb` or equivalent — register new activities

### Dependencies

- Requires Story 17.4 (strategy resolution from session) for `session.strategy`
- Requires Story 17.8 (strategy-driven state updates) for `mark_session_running` / `mark_session_failed`

### Testing

- Unit test each activity with mocked session and ContainerService
- Integration test workflow: mock activities, verify signal wait logic
- Test error paths: execute fails → cleanup still runs

### References

- [Source: web/app/temporal/workflows/unified_container_workflow.rb](web/app/temporal/workflows/unified_container_workflow.rb) — current workflow to replace
- [Source: web/app/temporal/activities/execute_container_activity.rb](web/app/temporal/activities/execute_container_activity.rb) — current activity pattern
