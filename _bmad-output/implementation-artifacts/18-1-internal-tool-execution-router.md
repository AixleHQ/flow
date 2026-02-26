# Story 18.1: Internal Tool Execution Router

Status: review

## Story

As a system,
I want to route internal tool calls to Ruby handler classes instead of Docker containers,
so that platform-provided tools execute efficiently without containerization overhead.

## Acceptance Criteria

1. `Tool#execute` checks `kind` and routes accordingly:
   - `custom` → existing `ToolExecutionStrategy` path (no changes)
   - `internal` → `InternalToolExecutor.execute(tool, params, session)`
2. `InternalToolExecutor` resolves handler class by naming convention: `InternalTools::{tool.name.classify}`
3. Handler receives `params` (Hash) and `session` (TerminalSession), returns `{ exit_code:, stdout:, stderr: }`
4. Input validated against `tool.input_schema` before handler call
5. Errors caught and returned as `{ exit_code: 1, stdout: "", stderr: error_message }`
6. `InternalTools::Base` base class provides shared helpers
7. Existing custom tool execution path unchanged — no regression

## Tasks / Subtasks

- [x] Task 1: Create `InternalTools::Base` class (AC: #6)
  - [x] Create `app/services/internal_tools/base.rb`
  - [x] Define `initialize(params:, session:)` and abstract `execute`
  - [x] Add helpers: `project`, `step_run`, `workflow_run`, `success(text)`, `error(text)`
- [x] Task 2: Create `InternalToolExecutor` service (AC: #2, #3, #4, #5)
  - [x] Create `app/services/internal_tool_executor.rb`
  - [x] Implement `self.execute(tool, params, session)` — resolve class, validate, run
  - [x] Handler resolution: `"InternalTools::#{tool.name.classify}".constantize`
  - [x] Validate params against `tool.input_schema` (JSON Schema validation)
  - [x] Rescue `StandardError` → return `{ exit_code: 1, stderr: msg }`
- [x] Task 3: Update `Tool#execute` routing (AC: #1, #7)
  - [x] Add `session:` keyword arg (optional, default: nil)
  - [x] If `internal?` → `InternalToolExecutor.execute(self, parameters, session)`
  - [x] If `custom?` → existing `ToolExecutionStrategy` path (unchanged)
- [x] Task 4: Update MCP dynamic tools patch (AC: #1)
  - [x] In `action_mcp_dynamic_tools.rb`, pass `session` to `tool.execute`
  - [x] `execute_tool_via_temporal` → rename to `execute_tool`, handle both kinds
- [x] Task 5: Tests (AC: all)
  - [x] Unit test `InternalTools::Base` helpers
  - [x] Unit test `InternalToolExecutor` — resolution, validation, error handling
  - [x] Unit test `Tool#execute` routing for internal vs custom
  - [x] Test MCP integration — internal tool call flow

## Dev Notes

### Key Files to Modify

- `app/models/tool.rb` — add `session:` param to `execute`, routing logic
- `config/initializers/action_mcp_dynamic_tools.rb` — pass session to execute
- New: `app/services/internal_tool_executor.rb`
- New: `app/services/internal_tools/base.rb`

### Architecture Compliance

- `ToolExecutionStrategy` has guard: `raise ArgumentError, "Tool must be custom"` — this is expected, internal tools bypass it
- `Tool#execute` currently takes `parameters:, project:, timeout:` — add `session:` as optional kwarg
- MCP patch `execute_tool_via_temporal` method needs renaming since internal tools don't use Temporal
- Follow existing pattern: `ContainerStrategies::` for container, `InternalTools::` for Ruby handlers

### JSON Schema Validation

- Use `json_schemer` gem if available, or simple manual validation
- Check required fields, type matching — don't need full JSON Schema spec
- If `input_schema` is empty/nil, skip validation

### Project Structure Notes

```
app/services/
├── internal_tools/
│   └── base.rb                    # NEW
├── internal_tool_executor.rb      # NEW
├── container_strategies/
│   ├── base_strategy.rb           # existing
│   └── tool_execution_strategy.rb # existing, unchanged
```

### References

- [Source: app/models/tool.rb] — Tool model with kind routing
- [Source: config/initializers/action_mcp_dynamic_tools.rb] — MCP tools/call handler
- [Source: app/services/container_strategies/tool_execution_strategy.rb] — existing Docker execution
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.1]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Created InternalTools::Base with session/params init, helpers (project, step_run, workflow_run, success, error), require_workflow_context!
- Created InternalToolExecutor with handler resolution by naming convention, input_schema validation (required fields), error wrapping
- Updated Tool#execute to route internal→InternalToolExecutor, custom→Temporal (extracted to execute_custom private method)
- Renamed execute_tool_via_temporal→execute_tool in MCP initializer, now passes session to tool.execute
- 17 tests: 8 for Base, 6 for Executor, 3 for Tool routing — all pass

### File List
- app/services/internal_tools/base.rb (new)
- app/services/internal_tool_executor.rb (new)
- app/models/tool.rb (modified)
- config/initializers/action_mcp_dynamic_tools.rb (modified)
- test/services/internal_tools/base_test.rb (new)
- test/services/internal_tool_executor_test.rb (new)
- test/models/tool_execute_routing_test.rb (new)
