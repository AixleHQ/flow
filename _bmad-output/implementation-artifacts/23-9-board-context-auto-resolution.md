# Story 23.9: Board Context Auto-Resolution

Status: ready-for-dev

## Story

As a system,
I want board_id to be automatically resolved from session context,
so that agents never need to pass board_id and cannot access other projects' boards.

## Acceptance Criteria

1. `BoardContextResolver` service: given a `TerminalSession`, returns `Board` or nil
2. Resolution chain: (1) `session.step_run.workflow_run.board_task.board` → (2) `session.project.board` fallback
3. `board_id` is NOT a parameter in any MCP tool input schema
4. All board MCP tools call `BoardContextResolver.resolve(session)` before operations
5. All task operations validate: `task.board_id == resolved_board.id`
6. Security test: agent in project A cannot read/write tasks from project B's board
7. Returns descriptive error when no board found: "No board available in current context"

## Tasks / Subtasks

- [ ] Task 1: Create `BoardContextResolver` service with resolution chain
- [ ] Task 2: Create shared concern or base class for board tool authorization
- [ ] Task 3: Write unit tests for both resolution paths
- [ ] Task 4: Write security test: cross-project board access prevention
- [ ] Task 5: Write test: descriptive error when no board available

## Dev Notes

### Architecture Compliance

- **Service object**: `BoardContextResolver` — stateless, class method
- **Session context chain**: leverages existing `TerminalSession → StepRun → WorkflowRun` associations
- **FR45**: board_id never accepted as agent parameter — enforced by tool input schemas

### Implementation

```ruby
# frozen_string_literal: true

class BoardContextResolver
  class << self
    # Resolve the board from session context.
    # Priority:
    # 1. workflow_run.board_task.board (workflow triggered from board)
    # 2. session.project.board (fallback for any project session)
    def resolve(session)
      from_workflow_run(session) || from_project(session)
    end

    private

    def from_workflow_run(session)
      session&.step_run&.workflow_run&.board_task&.board
    end

    def from_project(session)
      session&.project&.board
    end
  end
end
```

### Shared Board Tool Concern

To avoid repeating context resolution in every tool:

```ruby
module InternalTools
  module BoardToolConcern
    extend ActiveSupport::Concern

    private

    def resolved_board
      @resolved_board ||= BoardContextResolver.resolve(session)
    end

    def require_board!
      return error("No board available in current context") unless resolved_board
      resolved_board
    end

    def find_board_task!(task_id)
      board = require_board!
      return board if board.is_a?(Hash) # error response
      task = board.board_tasks.find_by(id: task_id)
      return error("Task #{task_id} not found on this board") unless task
      task
    end

    def resolve_actor(task)
      task.assignee || workflow_run&.user
    end

    def broadcast_board_event(event_type, data)
      BoardChannel.broadcast_event(resolved_board, event_type, data)
    rescue StandardError => e
      Rails.logger.warn("[BoardTool] broadcast failed: #{e.message}")
    end
  end
end
```

### Security: Cross-Project Prevention

The resolver only returns boards accessible from the session's project. Since `board_id` is never a tool parameter, the agent can't override it. The `find_board_task!` method ensures task belongs to the resolved board.

Test scenario:
```ruby
test "agent cannot access task from different project's board" do
  other_project = create(:project, company: @company)
  other_board = create(:board, project: other_project)
  other_task = create(:board_task, board: other_board)

  tool = InternalTools::BoardGetTask.new(params: { task_id: other_task.id }, session: @session)
  result = tool.execute
  assert_equal 1, result[:exit_code]
  assert_match /not found/, result[:stderr]
end
```

### Dependency

- This is a **foundation story** — co-implement with 23.6, 23.7, 23.8
- Depends on existing `TerminalSession → StepRun → WorkflowRun → BoardTask → Board` association chain (all established in Epics 20-22)

### Project Structure Notes

- `app/services/board_context_resolver.rb` (new)
- `app/services/internal_tools/board_tool_concern.rb` (new — shared module)
- `test/services/board_context_resolver_test.rb` (new)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.9]
- [Source: ai/prd/board-tasks.md#FR45]
- [Source: app/models/terminal_session.rb — session → step_run association]
- [Source: app/models/step_run.rb — belongs_to :workflow_run]
- [Source: app/models/workflow_run.rb — belongs_to :board_task]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
