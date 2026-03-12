# Story 32.3: TaskService — Task Management

Status: review

## Story

As a developer,
I want a single `TaskService` for all task operations,
so that activity recording, workflow auto-triggering, and validation happen consistently regardless of entry point.

## Acceptance Criteria

1. `TaskService.create(board:, params:, actor:)` creates task, records `task_created` activity, checks auto-trigger on column binding, starts workflow via `WorkflowService.start` if needed
2. `TaskService.update(task:, params:, actor:)` updates task, records `task_updated` activity with changed attributes
3. `TaskService.destroy(task:, actor:)` destroys task, records `task_deleted` activity
4. `TaskService.move(task:, to_column:, position: nil, actor:, actor_type: :human)` moves task with position reordering, creates `ColumnTransition`, checks auto-trigger, starts workflow if needed
5. `TaskService.trigger_workflow(task:, binding:, actor:)` validates manual binding, checks no active runs, calls `WorkflowService.start(task: task)`
6. `TasksController` delegates all mutating actions to `TaskService` — no direct `ActivityRecorder`, `WorkflowAutoTriggerService`, or `TemporalWorkflowRegistry` calls
7. `TaskMoveService` is deleted — logic absorbed into `TaskService.move`
8. `WorkflowAutoTriggerService` is deleted — logic inline in `TaskService.create` and `TaskService.move`
9. All existing tests pass; new unit tests cover `TaskService`

## Tasks / Subtasks

- [x] Task 1: Create `TaskService` (AC: 1-5)
  - [x] Create `app/services/task_service.rb` with class methods
  - [x] `create`: `board.board_tasks.build(params)`, save, `ActivityRecorder.record(task_created)`, check auto-trigger
  - [x] `update`: `task.assign_attributes(params)`, capture changes, save, `ActivityRecorder.record(task_updated, changes)`
  - [x] `destroy`: capture title, destroy, `ActivityRecorder.record(task_deleted)`
  - [x] `move`: transaction with lock + position reorder, `ColumnTransition.create!`, auto-trigger check
  - [x] `trigger_workflow`: validate binding is manual, check no active runs, `WorkflowService.start`
  - [x] Private: `check_auto_trigger(task:, column:, actor:)`, `insert_at_position`, `reorder_within_column`
- [x] Task 2: Simplify `TasksController` (AC: 6)
  - [x] `create` → `TaskService.create(board:, params:, actor:)`, respond with result
  - [x] `update` → `TaskService.update(task:, params:, actor:)`
  - [x] `destroy` → `TaskService.destroy(task:, actor:)`
  - [x] `move` → `TaskService.move(task:, to_column:, position:, actor:)`
  - [x] `trigger_workflow` → `TaskService.trigger_workflow(task:, binding:, actor:)`
  - [x] Remove all `ActivityRecorder` and `WorkflowAutoTriggerService` calls
- [x] Task 3: Delete obsolete services (AC: 7, 8)
  - [x] Delete `app/services/task_move_service.rb`
  - [x] Delete `app/services/workflow_auto_trigger_service.rb`
  - [x] Delete corresponding test files
- [x] Task 4: Tests (AC: 9)
  - [x] Unit tests for all `TaskService` public methods
  - [x] Test auto-trigger logic (column with auto binding → workflow started)
  - [x] Test manual trigger validation (no active runs, manual binding)
  - [x] Update `TasksController` tests
  - [x] Verify no references to deleted services remain

## Dev Notes

### Architecture

- `TaskService` is the **top layer** — uses `WorkflowService.start` downward, never called by lower layers
- Uses `ActivityRecorder` as infrastructure utility (not part of pyramid)
- Does NOT know about Temporal — only about `WorkflowService`

### Key Files to Modify

| File | Action |
|------|--------|
| `app/services/task_service.rb` | **CREATE** — new service |
| `app/controllers/api/v1/company/projects/board/tasks_controller.rb` | **MODIFY** — delegate to TaskService |
| `app/services/task_move_service.rb` | **DELETE** |
| `app/services/workflow_auto_trigger_service.rb` | **DELETE** |
| `test/services/task_service_test.rb` | **CREATE** — new tests |
| `test/services/task_move_service_test.rb` | **DELETE** (if exists) |
| `test/services/workflow_auto_trigger_service_test.rb` | **DELETE** (if exists) |

### Position Reorder Logic (from TaskMoveService)

Migrate these private methods to `TaskService`:

```ruby
def insert_at_position(target_column, task, position)
  target_column.board_tasks.where.not(id: task.id)
    .where("position >= ?", position)
    .update_all("position = position + 1")
end

def reorder_within_column(target_column, task, old_pos, new_pos)
  if old_pos < new_pos
    target_column.board_tasks.where.not(id: task.id)
      .where("position > ? AND position <= ?", old_pos, new_pos)
      .update_all("position = position - 1")
  elsif old_pos > new_pos
    target_column.board_tasks.where.not(id: task.id)
      .where("position >= ? AND position < ?", new_pos, old_pos)
      .update_all("position = position + 1")
  end
end
```

### Auto-Trigger Logic (from WorkflowAutoTriggerService)

Simplified inline:
```ruby
def check_auto_trigger(task:, column:, actor:)
  binding = column.column_workflow_binding
  return unless binding&.trigger_mode&.to_sym == :auto

  WorkflowService.start(
    workflow: binding.workflow,
    project: column.board.project,
    user: actor,
    task: task,
    mode: :non_interactive
  )
rescue StandardError => e
  Rails.logger.error("[TaskService] Auto-trigger failed: #{e.message}")
end
```

### Dependency: Story 32.2

- `WorkflowService` must exist before `TaskService` can call `WorkflowService.start`

### References

- [Source: app/controllers/api/v1/company/projects/board/tasks_controller.rb] — current controller
- [Source: app/services/task_move_service.rb] — move logic to absorb
- [Source: app/services/workflow_auto_trigger_service.rb] — auto-trigger logic to absorb
- [Source: app/services/activity_recorder.rb] — used by TaskService
- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-323] — epic definition

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- Created `TaskService` with 5 public class methods: create, update, destroy, move, trigger_workflow
- Controller reduced to thin delegation — no direct ActivityRecorder, WorkflowAutoTriggerService, or Temporal calls
- Deleted `TaskMoveService` and `WorkflowAutoTriggerService` — logic absorbed into TaskService
- Updated `InternalTools::BoardMoveTask` to use `TaskService.move` instead of `TaskMoveService`
- 11 unit tests, 21 assertions, 0 failures; 28 controller tests pass

### File List

- app/services/task_service.rb (CREATED)
- app/controllers/api/v1/company/projects/board/tasks_controller.rb (MODIFIED)
- app/services/internal_tools/board_move_task.rb (MODIFIED — uses TaskService.move)
- app/services/task_move_service.rb (DELETED)
- app/services/workflow_auto_trigger_service.rb (DELETED)
- test/services/task_service_test.rb (CREATED)
