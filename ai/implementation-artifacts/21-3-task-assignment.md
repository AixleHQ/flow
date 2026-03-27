# Story 21.3: Task Assignment

Status: review

## Story

As a user,
I want to assign tasks to project collaborators,
so that team members know what they're responsible for.

## Acceptance Criteria

1. `assignee_id` references `users` table (already in migration from 21.1)
2. Validation: assignee must be a member of the project (owner or collaborator)
3. API: update task with `assignee_id` parameter (already in permitted params from 21.1)
4. API: filter tasks by assignee: `GET /tasks?assignee_id=X` (already in index filters from 21.1)
5. Unassign by setting `assignee_id` to null

## Tasks / Subtasks

- [ ] Task 1: Add assignee validation to BoardTask (AC: #2)
  - [ ] Validate assignee is project member: `validate :assignee_is_project_member, if: -> { assignee_id.present? }`
  - [ ] Use `board.project.accessible_by?(assignee)` check
- [ ] Task 2: Verify unassignment works (AC: #5)
  - [ ] Ensure `assignee_id: nil` is accepted on update
  - [ ] Ensure filter `assignee_id=X` excludes unassigned tasks
- [ ] Task 3: Tests
  - [ ] Test: assign task to project owner → success
  - [ ] Test: assign task to collaborator → success
  - [ ] Test: assign task to non-member → validation error
  - [ ] Test: unassign task → `assignee_id` nil
  - [ ] Controller test: filter by assignee_id

## Dev Notes

### Architecture Compliance

- Assignee is a project member — validated through `project.accessible_by?(user)` method which checks both owner and collaborators
- In future (Epic 23), agent acts as task assignee when performing MCP operations — assignee_id is the authorization anchor for agent actions
- No separate User serialization in task response — just `assignee_id`. Frontend resolves user name from project members list.

### Validation Implementation

```ruby
validate :assignee_is_project_member, if: -> { assignee_id.present? }

private

def assignee_is_project_member
  return if assignee && board&.project&.accessible_by?(assignee)

  errors.add(:assignee, "must be a member of the project")
end
```

### Project Structure Notes

- Updated: `app/models/board_task.rb` — assignee validation
- Updated: `test/models/board_task_test.rb` — assignment tests
- Updated: `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` — assignment + filter tests

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.3]
- [Source: ai/prd/board-tasks.md#FR17]
- [Source: app/models/project.rb#accessible_by? — checks owner + collaborators]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
None — implemented in 21.1 model as single pass.

### Completion Notes List
- All ACs implemented in `BoardTask` model as part of 21.1 batch
- `assignee_is_project_member` validation using `board.project.accessible_by?(assignee)`
- Unassign via `assignee_id: ""` tested
- 4 model tests + 4 controller tests for assignment

### File List
- `app/models/board_task.rb` (assignee validation)
- `test/models/board_task_test.rb` (assignment test section)
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` (assignment tests)
