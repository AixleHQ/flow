# Story 23.6: Board MCP Read Tools (5 tools)

Status: done

## Story

As an agent in a workflow session,
I want to read board data through MCP tools,
so that I can understand task context and board structure.

## Acceptance Criteria

1. 5 internal tools implemented as `InternalTools::Board*` classes inheriting from `InternalTools::Base`
2. All tools auto-resolve `board_id` from session context (via `BoardContextResolver`)
3. All tools validate that requested task belongs to resolved board
4. **`board_list_tasks`**: params `column_name`, `tag`, `task_type`, `assignee_id` (all optional). Returns array of task summaries
5. **`board_get_task`**: params `task_id` (required). Returns full task details with description, comments count, assets count, parent/children info
6. **`board_get_comments`**: params `task_id` (required), `tag`, `author_type` (optional). Returns filtered comments
7. **`board_get_task_assets`**: params `task_id` (required), `tag` (optional). Returns asset metadata with presigned download URLs
8. **`board_get_board_info`**: no params. Returns board structure — columns with names, positions, purposes, workflow bindings
9. All tools return `success(result.to_json)` for valid results, `error(message)` for failures
10. Unit tests for each tool with session context mocking

## Tasks / Subtasks

- [x] Task 1: Create `BoardContextResolver` service
- [x] Task 2: Create `InternalTools::BoardListTasks`
- [x] Task 3: Create `InternalTools::BoardGetTask`
- [x] Task 4: Create `InternalTools::BoardGetComments`
- [x] Task 5: Create `InternalTools::BoardGetTaskAssets`
- [x] Task 6: Create `InternalTools::BoardGetBoardInfo`
- [x] Task 7: Write unit tests for all 5 tools
- [x] Task 8: Write unit tests for `BoardContextResolver`

## Dev Notes

### Architecture Compliance

- **InternalTools::Base** pattern: all tools inherit from it, implement `execute`
- **InternalToolExecutor** resolves handler class from tool name: `board_list_tasks` → `InternalTools::BoardListTasks`
- **execution_mode: :app** — runs in Rails process, synchronous
- **kind: :workflow** — auto-injected into workflow_step sessions only
- **board_id auto-resolved** from session context — never a tool parameter (FR45)

### BoardContextResolver

```ruby
class BoardContextResolver
  def self.resolve(session)
    # Priority 1: workflow run → board_task → board
    if session.step_run&.workflow_run&.board_task_id.present?
      return session.step_run.workflow_run.board_task.board
    end

    # Priority 2: project → board
    session.project&.board
  end
end
```

### InternalTools Base Pattern

```ruby
module InternalTools
  class BoardListTasks < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available in current context") unless board

      tasks = board.board_tasks
      tasks = tasks.joins(:board_column).where(board_columns: { name: params[:column_name] }) if params[:column_name].present?
      tasks = tasks.with_tag(params[:tag]) if params[:tag].present?
      tasks = tasks.where(task_type: params[:task_type]) if params[:task_type].present?
      tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?

      result = tasks.map { |t| serialize_task_summary(t) }
      success(result.to_json)
    end
  end
end
```

### Task Validation Pattern

All tools that accept `task_id` must validate:
```ruby
def find_task!(task_id)
  board = BoardContextResolver.resolve(session)
  return error("No board available") unless board

  task = board.board_tasks.find_by(id: task_id)
  return error("Task not found on this board") unless task
  task
end
```

### `get_board_info` Response Format

Critical tool — agent reads `purpose` to understand workflow context:
```json
{
  "board": { "id": 1, "name": "Dev Board" },
  "columns": [
    {
      "id": 1, "name": "Tech Design", "position": 1,
      "purpose": "Technical design is being created. Expected: comment with tag tech_design",
      "workflow_binding": { "workflow_name": "Create Tech Design", "trigger_mode": "auto" }
    }
  ]
}
```

### Dependency

- Requires Story 23.9 (BoardContextResolver) — but can be co-implemented
- Requires Story 23.1 (ColumnWorkflowBinding) for binding info in `get_board_info`

### Project Structure Notes

- `app/services/board_context_resolver.rb` (new)
- `app/services/internal_tools/board_list_tasks.rb` (new)
- `app/services/internal_tools/board_get_task.rb` (new)
- `app/services/internal_tools/board_get_comments.rb` (new)
- `app/services/internal_tools/board_get_task_assets.rb` (new)
- `app/services/internal_tools/board_get_board_info.rb` (new)
- `test/services/board_context_resolver_test.rb` (new)
- `test/services/internal_tools/board_list_tasks_test.rb` (new)
- `test/services/internal_tools/board_get_task_test.rb` (new)
- `test/services/internal_tools/board_get_comments_test.rb` (new)
- `test/services/internal_tools/board_get_task_assets_test.rb` (new)
- `test/services/internal_tools/board_get_board_info_test.rb` (new)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.6]
- [Source: ai/prd/board-tasks.md#FR32-FR36, FR45]
- [Source: app/services/internal_tools/base.rb — base class]
- [Source: app/services/internal_tools/list_sub_steps.rb — example tool]
- [Source: app/services/internal_tool_executor.rb — dispatch pattern]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

- `app/services/board_context_resolver.rb` (new)
- `app/services/internal_tools/board_list_tasks.rb` (new)
- `app/services/internal_tools/board_get_task.rb` (new)
- `app/services/internal_tools/board_get_comments.rb` (new)
- `app/services/internal_tools/board_get_task_assets.rb` (new)
- `app/services/internal_tools/board_get_board_info.rb` (new)
- `test/services/board_context_resolver_test.rb` (new)
- `test/services/internal_tools/board_read_tools_test.rb` (new)
