# Story 8.2: Tool Execution Strategy Migration

Status: done

## Story

As a system,
I want to migrate tool execution to use the unified container framework,
So that tools benefit from standardized lifecycle hooks, timeouts, and artifact collection.

## Architecture Decision

**Approach:** Implement `ToolExecutionStrategy` inheriting from `BaseStrategy`, migrate existing `ToolExecutionService` logic.

**Key Changes:**
- Move tool-specific logic from `ToolExecutionService` → `ToolExecutionStrategy`
- Leverage lifecycle hooks for file injection, execution, cleanup
- Add artifact collection in `before_cleanup` phase
- Keep `ExecuteToolActivity` but simplify to use new service

```
Before:
ExecuteToolActivity → ToolExecutionService (monolithic)

After:
ExecuteToolActivity → ContainerExecutionService.execute(
  strategy: ToolExecutionStrategy.new(tool:, parameters:, project:)
)
```

## Acceptance Criteria

1. ✅ `ToolExecutionStrategy` implements all lifecycle phases
2. ✅ Config item resolution works (API keys, env vars)
3. ✅ File injection in `before_exec` phase
4. ✅ Command execution with timeout enforcement (5-30 min)
5. ✅ Output truncation (1MB limit) to prevent memory issues
6. ✅ Artifact collection from tool output paths
7. ✅ Resource limits enforced (CPU 50%, Memory 512MB)
8. ✅ Backward compatibility: existing tool executions work
9. ✅ Tests updated and passing

## Tasks

### Task 1: Create ToolExecutionStrategy (AC: 1, 2)

- [x] Create `app/services/container_strategies/tool_execution_strategy.rb`
- [x] Inherit from `BaseStrategy`
- [x] Implement `resolve_image`
- [x] Implement `build_env_vars` with config item resolution
- [x] Add `WorkingDir: /workspace` to container config

**Acceptance:** Strategy resolves image and config items correctly ✅

---

### Task 2: Implement File Injection (AC: 3)

- [x] Implement `before_exec` phase with file injection via base64

**Acceptance:** Tool files injected into container before execution ✅

---

### Task 3: Implement Command Execution with Timeout (AC: 4, 5)

- [x] Override `timeout_for` method (default 5min, max 30min)
- [x] Implement `exec` phase with timeout protection
- [x] Implement `build_command` with {{param}} substitution
- [x] Implement `truncate_output` (1MB limit)
- [x] Implement timeout handler with container kill

**Acceptance:** Tool executes with proper timeout and output limits ✅

---

### Task 4: Implement Artifact Collection (AC: 6)

- [x] Implement `before_cleanup` phase using `read_file_from_container`
- [x] Uses exec cat instead of tar (faster, from BaseStrategy)

**Acceptance:** Output files extracted from container before cleanup ✅

---

### Task 5: Add Resource Limits (AC: 7)

- [x] Override `build_host_config` to use `build_host_config_with_limits`
- [x] Memory 512MB, CPU 50%, PIDs 100

**Acceptance:** Container has strict resource limits ✅

---

### Task 6: Update ExecuteToolActivity (AC: 8)

- [x] Simplify to use ContainerExecutionService + ToolExecutionStrategy
- [x] Keep existing activity interface for backward compatibility

**Acceptance:** Activity uses new framework, backward compatible ✅

---

### Task 7: Deprecate ToolExecutionService (AC: 8)

- [x] Add deprecation warning to service
- [x] Document migration path in comments

**Acceptance:** Old service marked deprecated but still works ✅

---

### Task 8: Write Tests (AC: 9)

- [x] Test `ToolExecutionStrategy` (24 tests):
  - Image resolution
  - Config item resolution
  - Env var building
  - File injection
  - Command building with parameter substitution
  - Execution with success
  - Execution with timeout
  - Output truncation
- [x] Full test suite passes (368 tests, 1000 assertions)

**Acceptance:** All tests pass ✅

---

## Implementation Notes

### Config Item Resolution Logic

```ruby
# Priority: Project → Company → nil
def find_config_item(name, project, company)
  if project
    ConfigItem.find_by(name: name, scope: project) ||
      ConfigItem.find_by(name: name, scope: company)
  else
    ConfigItem.find_by(name: name, scope: company)
  end
end
```

### Command Execution

```ruby
def execute_command_in_container(container, command)
  stdout_lines, stderr_lines, exit_code = container.exec(
    ["/bin/sh", "-c", command],
    stdout: true,
    stderr: true
  )

  {
    exit_code: exit_code,
    stdout: stdout_lines.join,
    stderr: stderr_lines.join
  }
end
```

### Backward Compatibility

All existing code calling `ToolExecutionService.execute` continues to work. Only `ExecuteToolActivity` is updated to use new framework (activities are internal, not public API).

---

## File List

### New Files
- `app/services/container_strategies/tool_execution_strategy.rb`
- `test/services/container_strategies/tool_execution_strategy_test.rb`

### Modified Files
- `app/temporal/activities/execute_tool_activity.rb` (simplified)
- `app/services/tool_execution_service.rb` (add deprecation warning)
- `test/temporal/activities/execute_tool_activity_test.rb` (updated)

### Future Removal (Story 8.5)
- `app/services/tool_execution_service.rb` (will be deleted)

---

## Dependencies

- Story 8.1 completed (ContainerExecutionService, BaseStrategy)
- Tool model with `docker_image`, `command`, `required_config_items`, `tool_files`
- ConfigItem model for env var resolution

---

## Next Stories

- Story 8.3: Agent Migration (implement AgentAuthStrategy, AgentSessionStrategy)
- Story 8.4: Workflow Unification (UnifiedContainerWorkflow)

---

## Dev Agent Record

**Agent Model:** Claude Sonnet 4

**Completion Notes:**
- Created `ToolExecutionStrategy` with all 8 lifecycle phases implemented
- Migrated logic from `ToolExecutionService` to new strategy
- Config item resolution: Project level > Company level priority
- File injection via base64 encoding for binary safety
- Command execution with parameter substitution ({{param}} placeholders)
- Timeout enforcement: default 5min, max 30min, exit code 124 on timeout
- Output truncation at 1MB to prevent memory issues
- Resource limits: 512MB memory, 50% CPU, 100 PIDs
- Updated `ExecuteToolActivity` to use new framework
- Added deprecation warning to `ToolExecutionService`
- Fixed recursion bug in `build_host_config_with_limits` by introducing `base_host_config`
- All 368 tests pass with 1000 assertions

**Implementation Date:** 2026-02-04
