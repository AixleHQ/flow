# Story 19.12: Agent Context — Container Tool Usage Instructions

Status: ready-for-dev

## Story

As an agent in a container,
I want clear instructions in my context file explaining how to work with container tools and tool results,
so that I know to expect an execution ID, poll with `read_tool_result`, and download via `curl`.

## Acceptance Criteria

1. `SessionContextService#build_tool_descriptions` updated to group tools by execution mode
2. Context file includes a **"Tool Execution Modes"** section before individual tool descriptions
3. Section explains two modes: instant (app) and container (async)
4. Container tools section includes full workflow: call → receive ID → poll read_tool_result → curl download → process locally
5. Each tool in the list shows execution mode marker: `⚡ app` or `⏳ container`
6. Container tools show "Returns: execution ID → use read_tool_result to get results"
7. App tools show "Returns: direct result"
8. `read_tool_result` description includes concise reminder of its purpose and parameters
9. "Tool Execution Modes" section only shown if at least one container-mode tool is available in the session

## Tasks / Subtasks

- [ ] Task 1: "Tool Execution Modes" section (AC: #2, #3, #4, #9)
  - [ ] Add static markdown block to `build_tool_descriptions`
  - [ ] Explain instant vs container mode
  - [ ] Include numbered workflow for container tools:
    1. Call the tool → receive execution ID
    2. Check status via `read_tool_result` → poll until not processing
    3. Download results via `curl -o file <url>`
    4. Process locally
  - [ ] Include "Important" notes: never expect direct output, URL expiry, prefer result_data_url
  - [ ] Only inject section if session has at least one container-mode tool
- [ ] Task 2: Update per-tool descriptions (AC: #5, #6, #7, #8)
  - [ ] Add `⚡ app` / `⏳ container` markers to each tool heading
  - [ ] Container tools: add "Returns: execution ID → use read_tool_result to get results"
  - [ ] App tools: add "Returns: direct result"
  - [ ] `read_tool_result` gets specific description with parameter info
- [ ] Task 3: Tests
  - [ ] Test context includes "Tool Execution Modes" section when container tools present
  - [ ] Test context does NOT include section when only app tools present
  - [ ] Test each tool has correct execution mode marker
  - [ ] Test container tool description includes execution ID note
  - [ ] Test app tool description includes direct result note

## Dev Notes

- Changes are in `SessionContextService#build_tool_descriptions` only
- The "Tool Execution Modes" section is static text injected once before the tool list
- `tool.execution_mode` is already available on the Tool model after Story 19.1
- Keep the markdown clean and readable — agents process this as part of their system context

### Project Structure Notes

- `app/services/session_context_service.rb` — modify existing file

### References

- [Source: ai/epics/epic-19-tool-execution-framework.md#Story-19.12] — full markdown examples
- [Source: app/services/session_context_service.rb] — current build_tool_descriptions implementation
