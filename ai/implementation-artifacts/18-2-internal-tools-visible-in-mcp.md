# Story 18.2: Internal Tools Visible in MCP tools/list

Status: review

## Story

As an agent in a container,
I want to see internal tools in the MCP `tools/list` response,
so that I can discover and call platform-provided capabilities.

## Acceptance Criteria

1. `TerminalSession#available_tools` includes `Tool.internal_tools.enabled`
2. Internal tools always present regardless of session scope (company/project)
3. `tools/list` MCP response returns both internal and custom tools
4. Internal tools show correct `description` and `input_schema` in MCP response
5. Workflow-specific tools (`list_sub_steps`, `mark_sub_step`, `write_step_note`) return error if called outside workflow context (no step_run on session)

## Tasks / Subtasks

- [x] Task 1: Update `TerminalSession#available_tools` (AC: #1, #2)
  - [x] Merge `Tool.internal_tools.enabled` into the result
  - [x] Internal tools come first, then scoped tools (existing logic)
  - [x] Return array that includes both (internal + custom)
- [x] Task 2: Verify MCP tools/list works (AC: #3, #4)
  - [x] Updated `action_mcp_dynamic_tools.rb` to use `.detect` instead of `.find_by` for array compat
  - [x] `input_schema` serialization works for internal tools (no docker_image needed for MCP)
- [x] Task 3: Workflow context guard in handlers (AC: #5)
  - [x] Already implemented in Story 18.1: `require_workflow_context!` in `InternalTools::Base`
  - [x] Raises `WorkflowContextError` if `session.step_run` is nil
  - [x] Will be called by workflow tools in 18.3/18.4/18.5
- [x] Task 4: Tests (AC: all)
  - [x] Test `available_tools` includes internal tools
  - [x] Test `available_tools` merges internal + custom without duplicates
  - [x] Test MCP lookup via detect works
  - [x] Test workflow guard (covered in 18.1 base_test)

## Dev Notes

### Key Files to Modify

- `app/models/terminal_session.rb` — `available_tools` method (line ~121)
- `app/services/internal_tools/base.rb` — add `require_workflow_context!`

### Current `available_tools` Implementation

```ruby
def available_tools
  if tools.any?
    tools.enabled
  elsif project.present?
    Tool.for_project(project).custom_tools.enabled
  else
    Tool.none
  end
end
```

Needs to become something like:
```ruby
def available_tools
  internal = Tool.internal_tools.enabled
  custom = if tools.any?
    tools.enabled
  elsif project.present?
    Tool.merged_for_project(project).select(&:custom?)
  else
    Tool.none
  end
  # Return combined — internal tools first, then custom
end
```

**Important:** Return type must work with `.map` in `action_mcp_dynamic_tools.rb` and `.find_by(name:)`. If mixing AR relation + array, may need to return array.

### References

- [Source: app/models/terminal_session.rb#available_tools]
- [Source: config/initializers/action_mcp_dynamic_tools.rb#send_tools_list]
- [Source: ai/epics/epic-18-internal-tools.md#Story 18.2]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Changed available_tools to return Array (internal + custom), not AR relation
- Internal tools always first via `Tool.internal_tools.enabled.to_a` + custom array concat
- Updated MCP patch: `.find_by(name:)` → `.detect { |t| t.name == tool_name }` for array compat
- 6 tests: inclusion, ordering, disabled exclusion, detect lookup

### File List
- app/models/terminal_session.rb (modified — available_tools)
- config/initializers/action_mcp_dynamic_tools.rb (modified — detect instead of find_by)
- test/models/terminal_session_available_tools_test.rb (new)
