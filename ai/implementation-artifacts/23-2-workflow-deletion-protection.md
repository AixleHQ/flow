# Story 23.2: Workflow Deletion Protection

Status: ready-for-dev

## Story

As a system,
I want to prevent deletion of workflows bound to columns,
so that board automation doesn't break silently.

## Acceptance Criteria

1. `Workflow` model: `before_destroy` callback that checks `column_workflow_bindings.any?`
2. If bindings exist, abort destroy and add error message listing which columns use this workflow
3. Error message format: "Cannot delete — bound to column 'X' in project 'Y'"
4. API returns 422 with clear error when attempting to delete bound workflow
5. User must unbind workflow from column before deleting it
6. Unit test: workflow with binding cannot be destroyed
7. Unit test: workflow without binding can be destroyed normally
8. Controller test: DELETE returns 422 with error message for bound workflow

## Tasks / Subtasks

- [ ] Task 1: Add `before_destroy` callback to `Workflow` model
- [ ] Task 2: Create descriptive error message with column and project names
- [ ] Task 3: Write model tests for destroy protection
- [ ] Task 4: Write controller test for API error response

## Dev Notes

### Architecture Compliance

- `Workflow` already uses `soft_delete!` pattern. This protection applies to both `destroy` AND `soft_delete!`
- Use `throw(:abort)` in `before_destroy` callback
- Error message should use `errors.add(:base, ...)` for clear API response

### Implementation Pattern

```ruby
# In Workflow model
before_destroy :check_column_bindings

def check_column_bindings
  return if column_workflow_bindings.empty?

  bound_columns = column_workflow_bindings.includes(board_column: { board: :project })
  descriptions = bound_columns.map { |b|
    "'#{b.board_column.name}' in project '#{b.board_column.board.project.name}'"
  }
  errors.add(:base, "Cannot delete — bound to column #{descriptions.join(', ')}")
  throw(:abort)
end
```

### Soft Delete Consideration

Workflow uses `soft_delete!` (`update!(deleted_at: Time.current)`). The `before_destroy` callback protects against hard delete. For soft delete protection, add validation in `soft_delete!` method:

```ruby
def soft_delete!
  if column_workflow_bindings.any?
    # Same error as destroy protection
    raise ActiveRecord::RecordNotDestroyed, "Cannot delete — bound to columns"
  end
  update!(deleted_at: Time.current)
end
```

### Dependency

- Requires Story 23.1 (ColumnWorkflowBinding model) — `has_many :column_workflow_bindings` on Workflow

### Project Structure Notes

- `app/models/workflow.rb` (modified: before_destroy callback, soft_delete! guard)
- `test/models/workflow_test.rb` (modified: new destroy protection tests)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.2]
- [Source: ai/prd/board-tasks.md#FR9]
- [Source: app/models/workflow.rb — existing soft_delete! method]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
