# Story 23.5: Column Transition History

Status: ready-for-dev

## Story

As a system,
I want to record every task movement between columns,
so that we have audit trail and data for future analytics.

## Acceptance Criteria

1. Migration creates `column_transitions` table: `id`, `board_task_id` (references, not null), `from_column_id` (references board_columns, nullable), `to_column_id` (references board_columns, not null), `actor_id` (references users, not null), `actor_type` (string, not null), `workflow_run_id` (references, nullable), `created_at` (timestamp, not null) — NO `updated_at`
2. `ColumnTransition` model — append-only (no update, no destroy API)
3. `enumerize :actor_type, in: %i[human agent auto_trigger]`
4. Created in `TaskMoveService` on every task column change
5. `actor_type: :human` for API-initiated moves, `:agent` for MCP tool moves, `:auto_trigger` for system moves
6. `workflow_run_id` populated when the move triggers a workflow
7. API: `GET /board/tasks/:task_id/transitions` — read-only history
8. Unit tests for model
9. Controller test for index endpoint

## Tasks / Subtasks

- [ ] Task 1: Create migration for `column_transitions`
- [ ] Task 2: Create `ColumnTransition` model with enumerize and validations
- [ ] Task 3: Update `BoardTask` model — `has_many :column_transitions`
- [ ] Task 4: Create `ColumnTransitionSerializer`
- [ ] Task 5: Integrate transition creation into `TaskMoveService`
- [ ] Task 6: Create controller for transitions read-only endpoint
- [ ] Task 7: Create Pundit policy (project accessible for index)
- [ ] Task 8: Add route nested under tasks
- [ ] Task 9: Create factory and tests

## Dev Notes

### Architecture Compliance

- **Append-only**: No `updated_at` column — transitions are immutable event records
- **No update/destroy API** — only index endpoint
- **enumerize** for actor_type
- Uses `timestamp_attributes_for_update` pattern from `TaskComment` to suppress `updated_at`

### Model Pattern

```ruby
class ColumnTransition < ApplicationRecord
  extend Enumerize

  belongs_to :board_task
  belongs_to :from_column, class_name: "BoardColumn", optional: true
  belongs_to :to_column, class_name: "BoardColumn"
  belongs_to :actor, class_name: "User"
  belongs_to :workflow_run, optional: true

  enumerize :actor_type, in: %i[human agent auto_trigger]

  validates :actor_type, presence: true

  def self.timestamp_attributes_for_update
    []
  end
end
```

### TaskMoveService Integration

```ruby
# Inside TaskMoveService#execute, after successful move:
ColumnTransition.create!(
  board_task: @task,
  from_column: from_column,
  to_column: @target_column,
  actor: @actor,
  actor_type: @actor_type || :human,
  workflow_run_id: triggered_run&.id
)
```

### API Contract

```
GET /api/v1/company/projects/:project_id/board/tasks/:task_id/transitions
Response: { items: [{ id, from_column_id, from_column_name, to_column_id, to_column_name, actor_id, actor_type, workflow_run_id, created_at }] }
```

### Dependency

- Requires Story 23.3 (TaskMoveService) — transitions created inside the service

### Project Structure Notes

- `db/migrate/YYYYMMDDHHMMSS_create_column_transitions.rb`
- `app/models/column_transition.rb`
- `app/models/board_task.rb` (modified: has_many :column_transitions)
- `app/serializers/column_transition_serializer.rb`
- `app/controllers/api/v1/company/projects/board/task/transitions_controller.rb`
- `app/policies/api/v1/company/projects/board/task/transitions_policy.rb`
- `config/routes.rb` (modified)
- `test/factories/column_transitions.rb`
- `test/models/column_transition_test.rb`
- `test/controllers/api/v1/company/projects/board/task/transitions_controller_test.rb`

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.5]
- [Source: ai/prd/board-tasks.md#FR48]
- [Source: app/models/task_comment.rb — timestamp_attributes_for_update pattern]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
