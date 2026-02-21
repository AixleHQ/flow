# Story 17.3: Tool Execution Workflow

Status: review

## Story

As a platform engineer,
I want tool execution managed by a separate, simpler workflow,
so that tool-specific logic isn't tangled with agent session state management.

## Acceptance Criteria

1. **AC1: New workflow class** — `Workflows::ToolExecutionWorkflow` with input `{ tool_id:, parameters:, project_id:, timeout: }`. Registered in `WorkflowService` as `tool_execution_workflow`.

2. **AC2: Pull phase** — Calls `PullToolImageActivity(tool_id:)`. Activity loads tool, calls `strategy.pull_image` where strategy is `ToolExecutionStrategy.new(tool: tool)`.

3. **AC3: Execute phase** — Calls `ExecuteToolContainerActivity(tool_id:, parameters:, project_id:, timeout:)`. Activity builds `ToolExecutionStrategy` directly, calls `ContainerService.execute(strategy: strategy, input: strategy.input)`. Returns execution result (stdout, stderr, exit_code, container_id).

4. **AC4: Cleanup phase** — Calls `CleanupToolContainerActivity(container_id:)`. Direct container stop + remove via runtime. No session state, no before_cleanup artifacts.

5. **AC5: No signal wait** — Tool containers run to completion in the execute phase. Workflow proceeds directly to cleanup.

6. **AC6: Timeout** — Execute timeout: `min(timeout, 1800) + 300` overhead. Pull: 600s. Cleanup: 60s. Workflow execution timeout: 3600s.

## Tasks / Subtasks

- [x] Task 1: Create `Workflows::ToolExecutionWorkflow` (AC: #1, #5, #6)
  - [x] 1.1 Define workflow with tool-specific input
  - [x] 1.2 Linear flow: pull → execute → cleanup (no signal)
  - [x] 1.3 Error handling: attempt cleanup even if execute fails
- [x] Task 2: Create `PullToolImageActivity` (AC: #2)
  - [x] 2.1 Load tool, build strategy, pull image
- [x] Task 3: Create `ExecuteToolContainerActivity` (AC: #3)
  - [x] 3.1 Build ToolExecutionStrategy from input
  - [x] 3.2 Call ContainerService.execute, return result
- [x] Task 4: Create `CleanupToolContainerActivity` (AC: #4)
  - [x] 4.1 Direct runtime.stop_container + runtime.remove_container
- [x] Task 5: Register workflow and activities
- [x] Task 6: Write tests

## Dev Notes

### Architecture

Tools are fundamentally simpler than agent sessions:
- No session model or state machine
- No signal wait (synchronous execution)
- No credential injection or context assembly
- No artifact collection in cleanup
- Strategy is built directly from tool model, not from session

### Key files to create

- `web/app/temporal/workflows/tool_execution_workflow.rb`
- `web/app/temporal/activities/pull_tool_image_activity.rb`
- `web/app/temporal/activities/execute_tool_container_activity.rb`
- `web/app/temporal/activities/cleanup_tool_container_activity.rb`

### Key files to modify

- `web/app/services/workflow_service.rb` — register new workflow

### Current tool execution path

Currently `ContainerWorkflowService.execute_tool` sends `{strategy_type: "tool_execution", strategy_input: {tool_id:, parameters:, project_id:, timeout:}}` through UnifiedContainerWorkflow. The new workflow takes the same fields directly (minus `strategy_type`).

### Can be developed in parallel with 17.2

No dependency on session.strategy resolution (17.4) — tools build strategy directly.

### Testing

- Unit test each activity with mocked tool and ContainerService
- Test execute timeout enforcement
- Test cleanup after failed execution

### References

- [Source: web/app/services/container_strategies/tool_execution_strategy.rb](web/app/services/container_strategies/tool_execution_strategy.rb)
- [Source: web/app/services/container_workflow_service.rb](web/app/services/container_workflow_service.rb) — `start_tool_execution`, `execute_tool`
