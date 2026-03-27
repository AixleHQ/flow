# Story 19.8: read_tool_result Internal Tool

Status: ready-for-dev

## Story

As an agent,
I want to retrieve the status and download URLs for a tool execution result,
so that I can download and process tool outputs after async execution completes.

## Acceptance Criteria

1. `InternalTools::ReadToolResult < Base` created (execution_mode: `:app`)
2. Required parameter: `tool_result_id` (string)
3. Returns serialized ToolResult via `ToolResultSerializer` as JSON string
4. If state is `processing`: returns metadata with `state: "processing"` (no URLs yet)
5. If state is `completed` or `failed`: returns metadata with presigned URLs for all non-nil attachments
6. If not found: returns error message
7. Tool seed created with `kind: :internal`, `execution_mode: :app`, NOT `workflow_only`

## Tasks / Subtasks

- [ ] Task 1: InternalTools::ReadToolResult handler (AC: #1-#6)
  - [ ] Create `app/services/internal_tools/read_tool_result.rb`
  - [ ] Inherit from `InternalTools::Base`
  - [ ] `execute` method: find ToolResult by execution_id
  - [ ] Not found → `error("Tool result not found")`
  - [ ] Found → `success(ToolResultSerializer.new(tr).to_json)`
- [ ] Task 2: Tool seed (AC: #7)
  - [ ] Add seed to `db/seeds.rb` (or `db/seeds/code_report.rb`, whichever is appropriate for internal tools)
  - [ ] Name: `read_tool_result`
  - [ ] Display name: `Read Tool Result`
  - [ ] Kind: `:internal`
  - [ ] Execution mode: `:app`
  - [ ] NOT `workflow_only` — available in all sessions
  - [ ] Description: explains that it returns presigned URLs for async tool results
  - [ ] Input schema: `{ tool_result_id: { type: "string" } }`, required: `["tool_result_id"]`
- [ ] Task 3: Tests
  - [ ] Test with existing completed ToolResult → returns serialized JSON with URLs
  - [ ] Test with processing ToolResult → returns JSON with state: processing, nil URLs
  - [ ] Test with nonexistent tool_result_id → error response
  - [ ] Test with failed ToolResult → returns JSON with error field and partial URLs

## Dev Notes

- No poll/wait mechanism — agent decides when and how often to call this tool
- Agent workflow: call container tool → receive `tr-xxx` → wait → `read_tool_result(tr-xxx)` → curl download → process locally
- `read_tool_result` must NOT be `workflow_only` because container tools can run outside workflow context
- Presigned URLs expire in 1 hour — agent can call again for fresh URLs

### Project Structure Notes

- `app/services/internal_tools/read_tool_result.rb` — new file
- `db/seeds.rb` or `db/seeds/code_report.rb` — add seed

### References

- [Source: ai/tool-execution-framework.md#5.3] — read_tool_result code
- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.8] — acceptance criteria and seed example
- [Source: app/services/internal_tools/base.rb] — Base class pattern
