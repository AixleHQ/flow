# Story 23.1: Column-Workflow Binding Model

Status: ready-for-dev

## Story

As a user,
I want to bind a workflow to a board column,
so that the workflow can be triggered when tasks enter that column.

## Acceptance Criteria

1. Migration creates `column_workflow_bindings` table with: `id`, `board_column_id` (references, not null, unique index), `workflow_id` (references, not null), `trigger_mode` (string, not null, default: "manual"), `cooldown_seconds` (integer, not null, default: 5), `timestamps`
2. `ColumnWorkflowBinding` model with `belongs_to :board_column`, `belongs_to :workflow`, `enumerize :trigger_mode`
3. Validation: workflow must belong to same project as board (`workflow.scope == board.project` or `workflow.scope == board.project.company`)
4. Validation: one binding per column (enforced by unique index + model uniqueness validation)
5. API: CRUD at `POST/GET/PATCH/DELETE /board/columns/:column_id/workflow_binding` (singular resource)
6. Pundit policy: project admin only for create/update/destroy, project accessible for show
7. `BoardColumnSerializer` extended with binding info: `workflow_binding: { workflow_id, workflow_name, trigger_mode, cooldown_seconds }` or null
8. Unit tests for model validations (workflow project scope, uniqueness)
9. Controller tests for CRUD operations and authorization

## Tasks / Subtasks

- [ ] Task 1: Create migration for `column_workflow_bindings`
- [ ] Task 2: Create `ColumnWorkflowBinding` model with validations
- [ ] Task 3: Update `BoardColumn` model — `has_one :column_workflow_binding, dependent: :destroy`
- [ ] Task 4: Update `Workflow` model — `has_many :column_workflow_bindings`
- [ ] Task 5: Create `ColumnWorkflowBindingSerializer`
- [ ] Task 6: Update `BoardColumnSerializer` to include binding info
- [ ] Task 7: Create Pundit policy for workflow binding
- [ ] Task 8: Create controller at `Api::V1::Company::Projects::Board::Columns::WorkflowBindingController`
- [ ] Task 9: Add route as singular resource nested under columns
- [ ] Task 10: Create factory and model tests
- [ ] Task 11: Create controller tests

## Dev Notes

### Architecture Compliance

- **enumerize** for `trigger_mode`, not `ActiveRecord::Enum`
- **Singular resource** — `resource :workflow_binding` (not `resources`) because one binding per column
- **Pundit policy**: admin-only for mutations, follows existing `project_admin?` pattern
- **Serializer**: follows `ApplicationSerializer` pattern

### Existing Patterns to Follow

- **Model validations:** Follow `BoardTask` pattern for cross-model validations (column_belongs_to_board)
- **Controller:** Follow `Api::V1::Company::Projects::Board::TasksController` pattern with `current_board` helper
- **Route nesting:** Board → Columns → WorkflowBinding (singular)
- **Serializer:** Follow `BoardColumnSerializer` pattern with virtual attributes

### API Contract

```
GET    /api/v1/company/projects/:project_id/board/columns/:column_id/workflow_binding
POST   /api/v1/company/projects/:project_id/board/columns/:column_id/workflow_binding
PATCH  /api/v1/company/projects/:project_id/board/columns/:column_id/workflow_binding
DELETE /api/v1/company/projects/:project_id/board/columns/:column_id/workflow_binding

Body (POST/PATCH): { column_workflow_binding: { workflow_id, trigger_mode, cooldown_seconds } }
Response: { data: { id, workflow_id, workflow_name, trigger_mode, cooldown_seconds, created_at, updated_at } }
```

### Workflow Scope Validation

```ruby
validate :workflow_accessible_from_project

def workflow_accessible_from_project
  return unless workflow && board_column
  project = board_column.board.project
  unless Workflow.visible_for_project(project).exists?(id: workflow_id)
    errors.add(:workflow, "must be accessible from this project")
  end
end
```

### Route Definition

```ruby
# Inside board scope
resources :columns, only: [] do
  resource :workflow_binding, only: [:show, :create, :update, :destroy],
           controller: 'board/columns/workflow_binding'
end
```

### BoardColumnSerializer Extension

```ruby
# In BoardColumnSerializer
def workflow_binding
  binding = object.column_workflow_binding
  return nil unless binding
  { workflow_id: binding.workflow_id, workflow_name: binding.workflow.name,
    trigger_mode: binding.trigger_mode, cooldown_seconds: binding.cooldown_seconds }
end
```

### Frontend Impact (Future)

Story 22.1 `BoardColumn` type will need `workflowBinding: { workflowId, workflowName, triggerMode, cooldownSeconds } | null` — added to frontend types when implementing 23.4.

### Project Structure Notes

- `db/migrate/YYYYMMDDHHMMSS_create_column_workflow_bindings.rb`
- `app/models/column_workflow_binding.rb`
- `app/models/board_column.rb` (modified)
- `app/models/workflow.rb` (modified)
- `app/serializers/column_workflow_binding_serializer.rb`
- `app/serializers/board_column_serializer.rb` (modified)
- `app/policies/api/v1/company/projects/board/columns/workflow_binding_policy.rb`
- `app/controllers/api/v1/company/projects/board/columns/workflow_binding_controller.rb`
- `config/routes.rb` (modified)
- `test/factories/column_workflow_bindings.rb`
- `test/models/column_workflow_binding_test.rb`
- `test/controllers/api/v1/company/projects/board/columns/workflow_binding_controller_test.rb`

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.1]
- [Source: ai/prd/board-tasks.md#FR6, FR7]
- [Source: app/models/workflow.rb — visible_for_project scope]
- [Source: app/serializers/board_column_serializer.rb — existing column serializer]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
