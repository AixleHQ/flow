# Story 19.9: MCP Handler Update

Status: ready-for-dev

## Story

As a system,
I want the MCP `tools/call` handler to create ToolResult and return execution_id for container tools,
so that container tools execute asynchronously and results are delivered via read_tool_result.

## Acceptance Criteria

1. `execute_tool` in `action_mcp_dynamic_tools.rb` updated to branch on `tool.execution_mode`
2. If `tool.execution_mode_app?` → sync execution, return result directly (no change from current behavior)
3. If `tool.execution_mode_container?` → create `ToolResult(state: processing)`, call `tool.execute(tool_result_id:)`, return `{ exit_code: 0, stdout: execution_id }`
4. `build_response_content` unchanged — works for both sync results and execution_id strings
5. All container tools are always async — no sync/async switch based on timeout

## Tasks / Subtasks

- [ ] Task 1: Update execute_tool (AC: #1-#3)
  - [ ] Add execution_mode check in `execute_tool`
  - [ ] App mode: call `tool.execute(parameters:, project:, session:)` directly
  - [ ] Container mode:
    - [ ] Create ToolResult with generate_id, state: processing, tool, terminal_session, step_run
    - [ ] Call `tool.execute(parameters:, project:, session:, tool_result_id:)`
    - [ ] Return `{ exit_code: 0, stdout: tool_result.execution_id }`
  - [ ] Remove any existing sync container execution path
- [ ] Task 2: Verify response format (AC: #4)
  - [ ] Confirm `build_response_content` handles both hash results and execution_id strings
  - [ ] No changes needed to `build_response_content` if it already handles `{ exit_code:, stdout: }` format
- [ ] Task 3: Tests
  - [ ] Test app tool execution returns direct result
  - [ ] Test container tool execution creates ToolResult in processing state
  - [ ] Test container tool execution returns execution_id string
  - [ ] Test ToolResult is associated with correct tool, session, step_run

## Dev Notes

- ToolResult creation happens in MCP handler (not in Tool#execute) because only MCP needs the execution_id return pattern
- Direct `Tool#execute` callers (tests, future API) create ToolResult themselves if needed
- The handler must find `terminal_session` and `step_run` from the ActionMCP session context
- No timeout concern at MCP level — the call returns immediately with execution_id

### Project Structure Notes

- `config/initializers/action_mcp_dynamic_tools.rb` — modify existing file

### References

- [Source: ai/tool-execution-framework.md#5.1] — MCP handler code
- [Source: config/initializers/action_mcp_dynamic_tools.rb] — current handler to modify
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.9] — acceptance criteria
