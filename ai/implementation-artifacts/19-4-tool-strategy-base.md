# Story 19.4: ToolStrategy Base Class

Status: ready-for-dev

## Story

As a developer,
I want a shared base strategy for all tool container execution,
so that lifecycle phases (start, exec, timeout, persist, cleanup) are implemented once.

## Acceptance Criteria

1. `ContainerStrategies::ToolStrategy < BaseStrategy` created
2. `phase_config`: exec timeout from `input[:timeout]`, cleanup always runs (60s), other phases 120s
3. `before_create_container`: returns hash with image, cmd, working_dir, env_vars, labels, host_config (delegates to subclass template methods)
4. `start_container`: starts without health check (tools run to completion, no `wait_for_ready`)
5. `exec`: waits for container, collects logs, calls `persist_result`, returns `{ tool_result_id:, exit_code:, status: }`
6. `persist_result`: finds ToolResult by `input[:tool_result_id]`, calls `complete!`
7. `handle_timeout`: kills container, collects partial logs, persists with error message
8. Timeout capped at `MAX_TIMEOUT = 1800`
9. Temporal activity result payload < 500 bytes

## Tasks / Subtasks

- [ ] Task 1: ToolStrategy class (AC: #1-#8)
  - [ ] Create `app/services/container_strategies/tool_strategy.rb`
  - [ ] Constants: `DEFAULT_TIMEOUT = 300`, `MAX_TIMEOUT = 1800`, `TIMEOUT_EXIT_CODE = 124`
  - [ ] `phase_config(phase)` method
  - [ ] `before_create_container` delegating to template methods
  - [ ] `start_container` — start only, no health check
  - [ ] `exec` — Timeout.timeout → wait_container → logs → persist_result → tiny return hash
  - [ ] `persist_result` — ToolResult.find + complete!
  - [ ] `handle_timeout` — kill, collect logs, persist with error
  - [ ] Private `exec_timeout`, `ms_since` helpers
- [ ] Task 2: Tests (AC: #1-#9)
  - [ ] Test phase_config returns correct timeouts
  - [ ] Test exec persists result to ToolResult on success
  - [ ] Test exec persists result to ToolResult on failure (nonzero exit)
  - [ ] Test timeout handling — kills container, persists error
  - [ ] Test return payload is small (only tool_result_id, exit_code, status)

## Dev Notes

- `ToolStrategy` does NOT implement `resolve_image`, `build_cmd`, etc. — those are abstract, subclasses must override
- `ToolStrategy` does NOT collect files — `InternalToolStrategy` does that in `before_cleanup`
- The `exec` phase is where the container runs its main process and we wait for it. No `docker exec` — the command runs as PID 1

### Project Structure Notes

- `app/services/container_strategies/tool_strategy.rb` — new file

### References

- [Source: ai/tool-execution-framework.md#2.1] — ToolStrategy code
- [Source: app/services/container_strategies/base_strategy.rb] — BaseStrategy to inherit from
- [Source: app/services/container_strategies/tool_execution_strategy.rb] — existing code to extract shared logic from
