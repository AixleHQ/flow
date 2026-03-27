# Story 21.4: Move Task Between Columns

Status: review

## Story

As a user,
I want to move tasks between columns,
so that I can track task progress through my workflow stages.

## Acceptance Criteria

1. API endpoint: `PATCH /board/tasks/:id/move` with `column_id` and optional `position`
2. No transition constraints — any task can move to any column (FR15)
3. Task position updated in target column
4. Source column positions re-compacted after move
5. Database-level: row-level lock (`task.lock!`) before column change to prevent race conditions
6. Returns updated task with new `board_column_id` and `position`

## Tasks / Subtasks

- [ ] Task 1: Add `move` action to TasksController (AC: #1, #2, #3, #5, #6)
  - [ ] `PATCH /board/tasks/:id/move`
  - [ ] Accept `column_id` (required) and `position` (optional)
  - [ ] Validate target column belongs to same board
  - [ ] `task.lock!` before modification
  - [ ] Update `board_column_id` and `position`
  - [ ] Default position: end of target column (max position + 1)
  - [ ] Wrap in transaction
- [ ] Task 2: Position compaction on source column (AC: #4)
  - [ ] After moving task out, re-compact positions of remaining tasks in source column
  - [ ] Reuse compact pattern from ColumnsController or extract into a shared concern
- [ ] Task 3: Add route (AC: #1)
  - [ ] Add `member { patch :move }` to tasks resources
- [ ] Task 4: Add policy method (AC: #1)
  - [ ] `move?` → `project_accessible?` (same as other CRUD)
- [ ] Task 5: Tests
  - [ ] Test: move task to different column → success, correct column_id and position
  - [ ] Test: move task with explicit position → correct position
  - [ ] Test: move task to same column → works (reposition within column)
  - [ ] Test: move task to invalid column (different board) → 422 or 404
  - [ ] Test: source column positions re-compacted
  - [ ] Test: concurrent move safety (lock test)

## Dev Notes

### Architecture Compliance

- No transition constraints — any column → any column (FR15). This is intentional per PRD.
- Row-level lock prevents race conditions: `task.lock!` fetches with `SELECT ... FOR UPDATE`
- This endpoint is critical — it's the trigger point for workflow bindings in Epic 23
- Position in target column: if not specified, append to end. If specified, shift existing tasks.

### Move Implementation

```ruby
def move
  task = current_board.board_tasks.find(params[:id])
  target_column = current_board.board_columns.find(params[:column_id])

  ActiveRecord::Base.transaction do
    task.lock!
    source_column = task.board_column

    new_position = params[:position] || (target_column.board_tasks.maximum(:position).to_i + 1)
    task.update!(board_column: target_column, position: new_position)

    compact_task_positions(source_column) if source_column != target_column
  end

  respond_with task.reload, serializer: BoardTaskSerializer
end
```

### Position Compaction

```ruby
def compact_task_positions(column)
  column.board_tasks.order(:position).each_with_index do |t, idx|
    t.update_column(:position, idx + 1)
  end
end
```

### API Contract

```
PATCH  /api/v1/company/projects/:project_id/board/tasks/:id/move
```

Request body:
```json
{ "column_id": 5, "position": 2 }
```

Response: updated task (same as show)

### Project Structure Notes

- Updated: `app/controllers/api/v1/company/projects/board/tasks_controller.rb` — `move` action
- Updated: `config/routes.rb` — member route for move
- Updated: `app/policies/api/v1/company/projects/board/tasks_policy.rb` — `move?`
- Updated: `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` — move tests

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.4]
- [Source: ai/prd/board-tasks.md#FR14, FR15, FR18]
- [Source: app/controllers/api/v1/company/projects/board/columns_controller.rb — compact_positions pattern]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — implemented in 21.1 controller as single pass.

### Completion Notes List
- All ACs implemented: `PATCH /move` with `column_id` and optional `position`
- Row-level lock via `task.lock!` before modification
- Position compaction on source column after cross-column move
- Policy `move?` → `project_accessible?`
- 7 controller tests for move action

### File List
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb` (move action + compact_task_positions)
- `app/policies/api/v1/company/projects/board/tasks_policy.rb` (move? method)
- `config/routes.rb` (member route for move)
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` (move tests)
