# Story 21.2: Epic → Story Hierarchy

Status: review

## Story

As a user,
I want to create parent-child relationships between tasks,
so that I can organize epics with their stories.

## Acceptance Criteria

1. `BoardTask` gains `belongs_to :parent_task, class_name: "BoardTask", optional: true`
2. `BoardTask` gains `has_many :child_tasks, class_name: "BoardTask", foreign_key: :parent_task_id`
3. Validation: parent must have `task_type: :epic`; child can be any type
4. Validation: parent and child must belong to same board
5. Validation: max one level of nesting — if parent already has a parent, reject
6. API: create task with `parent_task_id` parameter (already in permitted params from 21.1)
7. API: `GET /tasks?parent_task_id=X` to list children of an epic
8. Serializer includes `parent_task_id` and `children_count`
9. Deleting an epic does NOT delete children — sets `parent_task_id` to nil (nullify)

## Tasks / Subtasks

- [ ] Task 1: Add hierarchy validations to BoardTask (AC: #1, #2, #3, #4, #5)
  - [ ] Validate `parent_task` is `task_type: :epic` (if parent present)
  - [ ] Validate parent and child belong to same board
  - [ ] Validate no deeper than 1 level: `parent_task.parent_task_id.nil?`
  - [ ] Note: `belongs_to :parent_task` and `has_many :child_tasks` already added in 21.1
- [ ] Task 2: Configure dependent nullification (AC: #9)
  - [ ] Update `has_many :child_tasks` to include `dependent: :nullify`
  - [ ] Test: deleting epic sets children's `parent_task_id` to nil
- [ ] Task 3: Verify filter support (AC: #7)
  - [ ] Ensure `parent_task_id` filter works in tasks controller index
  - [ ] Verify Ransack config includes `parent_task_id`
- [ ] Task 4: Tests
  - [ ] Test: create story with parent epic → success
  - [ ] Test: create task with parent that is NOT epic → validation error
  - [ ] Test: create task with parent from different board → validation error
  - [ ] Test: create task with grandparent (2 levels deep) → validation error
  - [ ] Test: delete epic → children's parent_task_id set to nil
  - [ ] Controller test: filter by parent_task_id

## Dev Notes

### Architecture Compliance

- Self-referencing FK: `parent_task_id` references `board_tasks(id)` — already in migration from 21.1
- No cascading delete — use `dependent: :nullify` on `has_many :child_tasks`
- Epic can have stories in different columns — no column constraint on hierarchy
- Max 1 level: epic → story. No epic → story → sub-story.

### Validation Implementation

```ruby
validate :parent_must_be_epic, if: -> { parent_task_id.present? }
validate :parent_same_board, if: -> { parent_task_id.present? }
validate :max_one_level_nesting, if: -> { parent_task_id.present? }

private

def parent_must_be_epic
  errors.add(:parent_task, "must be an epic") unless parent_task&.task_type&.to_sym == :epic
end

def parent_same_board
  errors.add(:parent_task, "must belong to the same board") unless parent_task&.board_id == board_id
end

def max_one_level_nesting
  errors.add(:parent_task, "cannot nest more than one level deep") if parent_task&.parent_task_id.present?
end
```

### Project Structure Notes

- Updated: `app/models/board_task.rb` — hierarchy validations + `dependent: :nullify`
- Updated: `test/models/board_task_test.rb` — hierarchy tests
- Updated: `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` — filter tests

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.2]
- [Source: ai/prd/board-tasks.md#FR13]
- [Source: ai/project-context.md#Implementation Rules — enumerize, not ActiveRecord enums]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — implemented in 21.1 model as single pass.

### Completion Notes List
- All ACs implemented in `BoardTask` model as part of 21.1 batch
- `belongs_to :parent_task`, `has_many :child_tasks, dependent: :nullify` configured
- 3 hierarchy validations: parent_must_be_epic, parent_same_board, max_one_level_nesting
- 6 hierarchy tests in model, 1 filter test in controller

### File List
- `app/models/board_task.rb` (hierarchy validations + dependent: :nullify)
- `test/models/board_task_test.rb` (hierarchy test section)
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` (parent_task_id filter test)
