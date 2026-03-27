# Story 23.7: Board MCP Write Tools (6 tools)

Status: done

## Story

As an agent in a workflow session,
I want to modify board data through MCP tools,
so that I can create tasks, add comments, attach files, and move tasks.

## Acceptance Criteria

1. 6 internal tools implemented as `InternalTools::Board*` classes
2. **`board_create_task`**: params `title` (required), `description`, `task_type`, `column_name`, `tags`. Creates task with `author_type: :agent`. Returns created task
3. **`board_update_task`**: params `task_id` (required), `title`, `description`, `priority`, `tags`, `task_type`. Updates specified fields only
4. **`board_move_task`**: params `task_id` (required), `column_name` (required). Delegates to `TaskMoveService` with `actor_type: :agent`
5. **`board_add_comment`**: params `task_id` (required), `body` (required), `tags` (optional). Auto-sets `author_type: :agent`, `author_id: task.assignee_id`
6. **`board_attach_asset`**: params `task_id` (required), `file_content` (required, base64), `name` (required), `tags` (optional). Creates TaskAsset from decoded base64
7. **`board_manage_tags`**: params `action` ("add"/"remove"), `entity_type` ("task"/"comment"), `entity_id` (required), `tag` (required). Adds/removes tag from entity's tags array
8. All write tools broadcast ActionCable events after successful operations
9. Unit tests for each tool

## Tasks / Subtasks

- [x] Task 1: Create `InternalTools::BoardCreateTask`
- [x] Task 2: Create `InternalTools::BoardUpdateTask`
- [x] Task 3: Create `InternalTools::BoardMoveTask`
- [x] Task 4: Create `InternalTools::BoardAddComment`
- [x] Task 5: Create `InternalTools::BoardAttachAsset`
- [x] Task 6: Create `InternalTools::BoardManageTags`
- [x] Task 7: Write unit tests for all 6 tools
- [x] Task 8: Verify ActionCable broadcasts from write tools

## Dev Notes

### Architecture Compliance

- **Agent acts as task assignee**: `author_id = task.assignee_id` (per PRD). If no assignee, use workflow_run.user_id as fallback
- **`board_move_task` cascades**: moving task via MCP tool can trigger auto-trigger on target column (another workflow). This is intentional — agent moves task → system handles bindings
- **base64 for `attach_asset`**: agents can't do multipart uploads. They encode file content as base64
- **ActionCable broadcasts**: write tools broadcast same events as controller actions

### board_move_task — Cascade Risk

Agent moves task to column with auto-trigger → new workflow starts. This is by design. The cooldown service prevents rapid double-triggers. But it means a workflow can chain: Workflow A (agent moves task) → Workflow B auto-triggered. This is the intended "pipeline" behavior.

### board_attach_asset — Base64 Pattern

```ruby
module InternalTools
  class BoardAttachAsset < Base
    def execute
      require_workflow_context!
      board = BoardContextResolver.resolve(session)
      return error("No board available") unless board

      task = board.board_tasks.find_by(id: params[:task_id])
      return error("Task not found") unless task

      decoded = Base64.decode64(params[:file_content])
      io = StringIO.new(decoded)

      asset = task.task_assets.build(
        name: params[:name],
        author: resolve_actor(task),
        author_type: :agent,
        tags: params[:tags] || []
      )
      asset.file = { io: io, filename: params[:name] }
      asset.save!

      broadcast_event(board, "task_updated", BoardTaskSerializer.new(task.reload).as_json)
      success({ id: asset.id, name: asset.name }.to_json)
    end
  end
end
```

### Actor Resolution Helper

Shared across write tools:
```ruby
def resolve_actor(task)
  task.assignee || workflow_run&.user
end
```

### board_manage_tags — Array Manipulation

```ruby
def execute
  entity = find_entity
  return entity if entity.is_a?(Hash) # error response

  current_tags = entity.tags || []
  if params[:action] == "add"
    entity.update!(tags: (current_tags + [params[:tag]]).uniq)
  elsif params[:action] == "remove"
    entity.update!(tags: current_tags - [params[:tag]])
  end

  success({ tags: entity.tags }.to_json)
end
```

### Dependency

- Requires Story 23.6 (BoardContextResolver, find_task! pattern)
- Requires Story 23.3 (TaskMoveService) for `board_move_task`
- Requires Story 23.5 (ColumnTransition) for transition recording on `board_move_task`

### Project Structure Notes

- `app/services/internal_tools/board_create_task.rb` (new)
- `app/services/internal_tools/board_update_task.rb` (new)
- `app/services/internal_tools/board_move_task.rb` (new)
- `app/services/internal_tools/board_add_comment.rb` (new)
- `app/services/internal_tools/board_attach_asset.rb` (new)
- `app/services/internal_tools/board_manage_tags.rb` (new)
- `test/services/internal_tools/board_create_task_test.rb` (new)
- `test/services/internal_tools/board_update_task_test.rb` (new)
- `test/services/internal_tools/board_move_task_test.rb` (new)
- `test/services/internal_tools/board_add_comment_test.rb` (new)
- `test/services/internal_tools/board_attach_asset_test.rb` (new)
- `test/services/internal_tools/board_manage_tags_test.rb` (new)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.7]
- [Source: ai/prd/board-tasks.md#FR37-FR42]
- [Source: app/services/internal_tools/base.rb — base class]
- [Source: app/uploaders/task_asset_uploader.rb — Shrine upload pattern]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List

- `app/services/internal_tools/board_create_task.rb` (new)
- `app/services/internal_tools/board_update_task.rb` (new)
- `app/services/internal_tools/board_move_task.rb` (new)
- `app/services/internal_tools/board_add_comment.rb` (new)
- `app/services/internal_tools/board_attach_asset.rb` (new)
- `app/services/internal_tools/board_manage_tags.rb` (new)
- `test/services/internal_tools/board_write_tools_test.rb` (new)
