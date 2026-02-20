# Story 17.5: Thin Activities

Status: review

## Story

As a platform engineer,
I want activities to be 5-line delegators with no routing or strategy resolution,
so that business logic lives exclusively in strategies and services.

## Acceptance Criteria

1. **AC1: Agent activities are minimal** — Each agent activity (`PullAgentImageActivity`, `ExecuteAgentContainerActivity`, `CleanupAgentContainerActivity`) loads session, calls one service method, returns result. No `STRATEGY_MAP`, no `prepare_strategy_input`, no `build_strategy_from_*`.

2. **AC2: Tool activities are minimal** — Each tool activity (`PullToolImageActivity`, `ExecuteToolContainerActivity`, `CleanupToolContainerActivity`) loads tool, builds strategy directly, calls service method.

3. **AC3: No shared base for routing** — `ContainerActivityBase` either removed or reduced to a utility mixin (logger, error wrapping). No strategy routing code.

4. **AC4: Error wrapping** — Activities wrap exceptions into `TemporalExceptions::NonRetryableError` for infrastructure failures and `TemporalExceptions::RetryableError` for transient issues (Docker daemon unreachable, network timeouts).

5. **AC5: Logging** — Each activity logs start/end with `session_id` or `tool_id` tag. Uses `Rails.logger.tagged`.

6. **AC6: Registration** — All 6 new activities registered in `temporal_activities.rb` and old activities deregistered.

## Tasks / Subtasks

- [x] Task 1: Implement 3 agent activities (AC: #1, #4, #5)
  - [x] 1.1 `PullAgentImageActivity` — session.strategy.pull_image
  - [x] 1.2 `ExecuteAgentContainerActivity` — ContainerService.execute(session:)
  - [x] 1.3 `CleanupAgentContainerActivity` — ContainerService.cleanup(session:)
- [x] Task 2: Implement 3 tool activities (AC: #2, #4, #5)
  - [x] 2.1 `PullToolImageActivity` — strategy = ToolExecutionStrategy.new(tool:); strategy.pull_image
  - [x] 2.2 `ExecuteToolContainerActivity` — ContainerService.execute(strategy:, input:)
  - [x] 2.3 `CleanupToolContainerActivity` — runtime.stop + runtime.remove
- [x] Task 3: Refactor or remove ContainerActivityBase (AC: #3)
  - [x] 3.1 Audit remaining shared utility methods
  - [x] 3.2 Extract useful helpers (error wrapping) into concern
  - [x] 3.3 Remove strategy routing code
- [x] Task 4: Register activities (AC: #6)
- [x] Task 5: Write tests for all 6 activities

## Dev Notes

### Current activity structure (~120 lines in base + ~45 lines in execute)

```
ContainerActivityBase
├── STRATEGY_MAP (4 entries)
├── build_strategy_from_input → resolves class
├── prepare_strategy_input → case statement (4 branches)
├── mark_session_failed → updates AASM
└── mark_session_running (removed already)

ExecuteContainerActivity < ContainerActivityBase
├── execute → ~25 lines with rescue blocks
├── handle_result → signal workflow if interactive
└── build_strategy_from_session → fallback resolution
```

### Target activity structure (~5-10 lines each)

```ruby
class ExecuteAgentContainerActivity < Temporal::Activity
  def execute(session_id:)
    session = TerminalSession.find(session_id)
    ContainerService.execute(session: session)
  rescue ActiveRecord::RecordNotFound => e
    raise TemporalExceptions::NonRetryableError, e.message
  end
end
```

### Dependencies

- Requires 17.2 (agent workflow) and 17.3 (tool workflow) for activity structure
- Requires 17.4 (session.strategy) for agent activities
- Can be developed alongside or after 17.2–17.4

### Key files to create/modify

- Create: `web/app/temporal/activities/pull_agent_image_activity.rb`
- Create: `web/app/temporal/activities/execute_agent_container_activity.rb` (new, not modifying old)
- Create: `web/app/temporal/activities/cleanup_agent_container_activity.rb`
- Create: `web/app/temporal/activities/pull_tool_image_activity.rb`
- Create: `web/app/temporal/activities/execute_tool_container_activity.rb` (new)
- Create: `web/app/temporal/activities/cleanup_tool_container_activity.rb`
- Modify: `web/app/temporal/activities/container_activity_base.rb` — strip or remove
- Modify: `web/config/temporal_activities.rb` — register new, deregister old

### Testing

- Each activity unit tested with mocked session/tool and service
- Test error wrapping (ActiveRecord::NotFound → NonRetryable, Docker errors → appropriate type)

### References

- [Source: web/app/temporal/activities/container_activity_base.rb](web/app/temporal/activities/container_activity_base.rb) — current base being replaced
- [Source: web/app/temporal/activities/execute_container_activity.rb](web/app/temporal/activities/execute_container_activity.rb) — current activity
