# Story 23.3: Auto-Trigger on Task Column Entry

Status: ready-for-dev

## Story

As a system,
I want to automatically start a workflow when a task enters a column with auto trigger,
so that task movement drives the AI execution pipeline.

## Acceptance Criteria

1. Extract move logic into `TaskMoveService` — single place for: move task, create transition (23.5), check binding, trigger workflow
2. After task moves to column with `trigger_mode: :auto` binding → check cooldown → start workflow
3. `CooldownService.can_trigger?(task, column)` — Redis-based: key `board_trigger:#{task_id}:#{column_id}`, TTL = `cooldown_seconds`
4. If cooldown allows: create `WorkflowRun` with `board_task_id` reference, start workflow via `TemporalService`
5. Workflow execution receives `board_task_id` in input params
6. ActionCable broadcast: `workflow_started` event to board channel
7. Controller `move` action delegates to `TaskMoveService#execute`
8. Unit tests for `CooldownService` and `TaskMoveService`
9. Integration test: move task → workflow triggered

## Tasks / Subtasks

- [ ] Task 1: Create `TaskMoveService` extracting logic from `TasksController#move`
- [ ] Task 2: Create `CooldownService` with Redis-based cooldown check
- [ ] Task 3: Add workflow trigger logic to `TaskMoveService` after successful move
- [ ] Task 4: Create `WorkflowRun` with `board_task_id` when triggering
- [ ] Task 5: Update `TasksController#move` to delegate to `TaskMoveService`
- [ ] Task 6: Write unit tests for `CooldownService`
- [ ] Task 7: Write unit tests for `TaskMoveService`
- [ ] Task 8: Write controller integration test for auto-trigger

## Dev Notes

### Architecture Compliance

- **Service object pattern**: `TaskMoveService` encapsulates move + transition + trigger logic
- **Redis for cooldown**: Simple TTL-based — no database queries, very fast
- **Temporal integration**: Uses existing `TemporalService.start_workflow` pattern
- **`board_task_id` on WorkflowRun**: Already added in Story 22.4 migration

### TaskMoveService Design

```ruby
class TaskMoveService
  def initialize(task:, target_column:, actor:, position: nil)
    @task = task
    @target_column = target_column
    @actor = actor
    @position = position
  end

  def execute
    from_column = @task.board_column

    ActiveRecord::Base.transaction do
      @task.lock!
      new_pos = @position || (@target_column.board_tasks.maximum(:position).to_i + 1)
      @task.update!(board_column: @target_column, position: new_pos)
      compact_positions(from_column) if from_column.id != @target_column.id
    end

    check_auto_trigger!
    broadcast_move(from_column)
    @task.reload
  end

  private

  def check_auto_trigger!
    binding = @target_column.column_workflow_binding
    return unless binding&.trigger_mode&.to_sym == :auto
    return unless CooldownService.can_trigger?(@task.id, @target_column.id, binding.cooldown_seconds)

    trigger_workflow(binding)
  end

  def trigger_workflow(binding)
    workflow = binding.workflow
    run = WorkflowRun.create!(
      workflow: workflow,
      project: @task.board.project,
      user: @actor,
      board_task_id: @task.id,
      mode: :non_interactive
    )
    TemporalService.start_workflow(
      WorkflowService.workflow_execution_workflow,
      { workflow_run_id: run.id, board_task_id: @task.id },
      id: "workflow-execution-#{run.id}"
    )
  end
end
```

### CooldownService Design

```ruby
class CooldownService
  REDIS_PREFIX = "board_trigger"

  class << self
    def can_trigger?(task_id, column_id, cooldown_seconds)
      key = "#{REDIS_PREFIX}:#{task_id}:#{column_id}"
      redis = Redis.new(url: Settings.redis.url)
      return false if redis.exists?(key)

      redis.set(key, "1", ex: cooldown_seconds)
      true
    end
  end
end
```

### Redis Configuration

Redis is already configured at `Settings.redis.url` and used for ActionCable. Direct Redis client usage is straightforward — `redis` gem is in Gemfile.

### WorkflowService Reference

Need to check `WorkflowService` for the correct workflow class to pass to `TemporalService.start_workflow`. The existing pattern uses `WorkflowService.container_workflow` for tool execution. For workflow execution, it should be `WorkflowService.workflow_execution_workflow` or similar.

### Dependency

- Requires Story 23.1 (ColumnWorkflowBinding model)
- Story 22.4 already added `board_task_id` to `workflow_runs`

### Project Structure Notes

- `app/services/task_move_service.rb` (new)
- `app/services/cooldown_service.rb` (new)
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb` (modified: delegate to service)
- `test/services/task_move_service_test.rb` (new)
- `test/services/cooldown_service_test.rb` (new)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.3]
- [Source: ai/prd/board-tasks.md#FR8, FR10]
- [Source: app/services/temporal_service.rb — start_workflow pattern]
- [Source: config/settings.yml — Redis URL]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
