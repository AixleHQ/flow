# Story 21.1: Task Model & CRUD

Status: review

## Story

As a user,
I want to create tasks with structured fields,
so that I can track work items on my board.

## Acceptance Criteria

1. Migration creates `board_tasks` table: `id` (bigint PK), `board_id` (references boards, not null, FK), `board_column_id` (references board_columns, not null, FK), `title` (string, not null), `description` (text, nullable), `task_type` (string, not null, default: "not_specified"), `priority` (string, nullable), `assignee_id` (references users, nullable), `position` (integer, not null), `parent_task_id` (references board_tasks, nullable), `tags` (string array, default: []), `timestamps`
2. Index on `board_id`, `board_column_id`, `assignee_id`, `parent_task_id`
3. `BoardTask` model with `belongs_to :board`, `belongs_to :board_column`, `belongs_to :assignee, class_name: "User", optional: true`
4. `enumerize :task_type, in: %i[epic story bug not_specified], default: :not_specified`
5. `enumerize :priority, in: %i[low medium high critical], default: nil`
6. Auto-assigns position within column on create (max position + 1 for that column)
7. Task CRUD API at `api/v1/company/projects/:project_id/board/tasks`
8. Pundit policy: Admin and Collaborator (project members) can CRUD tasks
9. `BoardTaskSerializer` with all fields + `children_count`, `comments_count`, `assets_count`
10. Validates `title` presence
11. Validates `board_column` belongs to the same `board`

## Tasks / Subtasks

- [ ] Task 1: Create migration (AC: #1, #2)
  - [ ] Generate migration `CreateBoardTasks`
  - [ ] `board_id` with FK to boards, not null
  - [ ] `board_column_id` with FK to board_columns, not null
  - [ ] `title` (string, not null), `description` (text, nullable)
  - [ ] `task_type` (string, not null, default: "not_specified"), `priority` (string, nullable)
  - [ ] `assignee_id` with FK to users, nullable
  - [ ] `position` (integer, not null)
  - [ ] `parent_task_id` with self-referencing FK to board_tasks, nullable
  - [ ] `tags` (string array, default: [])
  - [ ] Timestamps
  - [ ] Indexes on `board_id`, `board_column_id`, `assignee_id`, `parent_task_id`
- [ ] Task 2: Create BoardTask model (AC: #3, #4, #5, #6, #10, #11)
  - [ ] `app/models/board_task.rb`
  - [ ] `belongs_to :board`, `belongs_to :board_column`, `belongs_to :assignee, class_name: "User", optional: true`
  - [ ] `belongs_to :parent_task, class_name: "BoardTask", optional: true` (prepared for Story 21.2)
  - [ ] `has_many :child_tasks, class_name: "BoardTask", foreign_key: :parent_task_id` (prepared for Story 21.2)
  - [ ] `enumerize :task_type, in: %i[epic story bug not_specified], default: :not_specified`
  - [ ] `enumerize :priority, in: %i[low medium high critical]` (no default — nil allowed)
  - [ ] Validates `title` presence
  - [ ] Validate `board_column` belongs to same board: `validate :column_belongs_to_board`
  - [ ] `before_validation :assign_next_position, on: :create`
  - [ ] Ransack config
- [ ] Task 3: Add Board associations (AC: #3)
  - [ ] `Board` gains `has_many :board_tasks, dependent: :destroy`
  - [ ] `BoardColumn` gains `has_many :board_tasks, dependent: :restrict_with_error`
- [ ] Task 4: Create BoardTaskSerializer (AC: #9)
  - [ ] `app/serializers/board_task_serializer.rb` inheriting `ApplicationSerializer`
  - [ ] Attributes: `id`, `title`, `description`, `task_type`, `priority`, `assignee_id`, `board_column_id`, `position`, `parent_task_id`, `tags`, `created_at`, `updated_at`
  - [ ] Virtual attributes: `children_count`, `comments_count`, `assets_count`
  - [ ] `children_count` → `object.child_tasks.count`
  - [ ] `comments_count` → `0` for now (Story 21.5 will add TaskComment)
  - [ ] `assets_count` → `0` for now (Story 21.6 will add TaskAsset)
- [ ] Task 5: Create Pundit policy (AC: #8)
  - [ ] `app/policies/api/v1/company/projects/board/tasks_policy.rb`
  - [ ] All CRUD actions → `project_accessible?` (both admin and collaborator)
- [ ] Task 6: Create controller (AC: #7)
  - [ ] `app/controllers/api/v1/company/projects/board/tasks_controller.rb`
  - [ ] Inherit from `Api::V1::Company::Projects::ApplicationController`
  - [ ] `index`: list tasks for board with optional filters (column_id, assignee_id, task_type, parent_task_id)
  - [ ] `show`: single task
  - [ ] `create`: build task with auto-position
  - [ ] `update`: update task fields
  - [ ] `destroy`: destroy task
  - [ ] Strong params: `params.require(:board_task).permit(:title, :description, :task_type, :priority, :assignee_id, :board_column_id, :parent_task_id, tags: [])`
- [ ] Task 7: Add routes (AC: #7)
  - [ ] Add `resources :tasks, controller: "board/tasks"` nested under board in routes
- [ ] Task 8: Factory and tests
  - [ ] FactoryBot factory for `board_task`
  - [ ] Model test: validations (title presence, column belongs to board, auto-position, enumerize)
  - [ ] Controller test: CRUD, filters, authorization

## Dev Notes

### Architecture Compliance

- **NOT a polymorphic-scoped resource.** BoardTask belongs directly to a Board and BoardColumn.
- Task position is scoped per column, not per board — column is the position scope.
- `tags` uses PostgreSQL array type: `t.string :tags, array: true, default: []`. Enables `ANY()` queries.
- `enumerize` for `task_type` and `priority` — NEVER ActiveRecord enums.
- `board_column_id` enforces task is in exactly one column at any time (FR18).

### Existing Patterns to Follow

- **Controller hierarchy:** `Api::V1::Company::Projects::Board::TasksController < Api::V1::Company::Projects::ApplicationController`
- Same pattern as `Board::ColumnsController` — access board via `current_project.board`.
- **`respond_with`** from responders gem for all responses.
- **Serializer:** inherit from `ApplicationSerializer`.
- **Policy:** inherit from `Api::V1::Company::ApplicationPolicy`, use `project_accessible?`.
- **`# frozen_string_literal: true`** at top of every Ruby file.
- **Tests:** Minitest, FactoryBot factories in `test/factories/`.

### Database Schema

```sql
CREATE TABLE board_tasks (
  id bigserial PRIMARY KEY,
  board_id bigint NOT NULL REFERENCES boards(id),
  board_column_id bigint NOT NULL REFERENCES board_columns(id),
  title varchar NOT NULL,
  description text,
  task_type varchar NOT NULL DEFAULT 'not_specified',
  priority varchar,
  assignee_id bigint REFERENCES users(id),
  position integer NOT NULL,
  parent_task_id bigint REFERENCES board_tasks(id),
  tags varchar[] DEFAULT '{}',
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL
);
CREATE INDEX index_board_tasks_on_board_id ON board_tasks(board_id);
CREATE INDEX index_board_tasks_on_board_column_id ON board_tasks(board_column_id);
CREATE INDEX index_board_tasks_on_assignee_id ON board_tasks(assignee_id);
CREATE INDEX index_board_tasks_on_parent_task_id ON board_tasks(parent_task_id);
```

### API Contract

```
GET    /api/v1/company/projects/:project_id/board/tasks            → index
GET    /api/v1/company/projects/:project_id/board/tasks/:id        → show
POST   /api/v1/company/projects/:project_id/board/tasks            → create
PATCH  /api/v1/company/projects/:project_id/board/tasks/:id        → update
DELETE /api/v1/company/projects/:project_id/board/tasks/:id        → destroy
```

Index supports query params: `board_column_id`, `assignee_id`, `task_type`, `parent_task_id`

### Column Dependency (from Epic 20)

- `BoardColumn` already exists with `belongs_to :board`, `position`, `purpose`
- Task's `board_column_id` must reference a column that belongs to the same board

### Previous Story Intelligence (Epic 20)

- Board model at `app/models/board.rb` — `has_many :board_columns, -> { order(:position) }, dependent: :destroy`
- Controller pattern: `current_board` helper returning `current_project.board || raise(ActiveRecord::RecordNotFound)`
- Two-pass reorder for unique constraint avoidance
- `compact_positions` pattern for re-numbering after delete

### Project Structure Notes

- `app/models/board_task.rb`
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb`
- `app/serializers/board_task_serializer.rb`
- `app/policies/api/v1/company/projects/board/tasks_policy.rb`
- `test/models/board_task_test.rb`
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb`
- `test/factories/board_tasks.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_board_tasks.rb`

### References

- [Source: ai/epics/epic-21-tasks-comments-assets.md#Story 21.1]
- [Source: ai/prd/board-tasks.md#FR12, FR16, FR18]
- [Source: ai/project-context.md#Implementation Rules]
- [Source: app/models/board.rb — existing Board model]
- [Source: app/models/board_column.rb — existing BoardColumn model]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References
- Board `has_many` order fix: moved `board_tasks` before `board_columns` in Board model to fix cascade destroy (restrict_with_error on columns blocked deletion when tasks existed)

### Completion Notes List
- All ACs implemented: migration, model, serializer, policy, controller, routes, factory
- Stories 21.2-21.4 validations implemented in same model (hierarchy, assignee, move) for efficiency
- 23 model tests + 26 controller tests = 49 tests passing

### File List
- `db/migrate/20260227100002_create_board_tasks.rb`
- `app/models/board_task.rb`
- `app/models/board.rb` (modified: added `has_many :board_tasks`)
- `app/models/board_column.rb` (modified: added `has_many :board_tasks, dependent: :restrict_with_error`)
- `app/serializers/board_task_serializer.rb`
- `app/policies/api/v1/company/projects/board/tasks_policy.rb`
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb`
- `config/routes.rb` (modified: added tasks routes)
- `test/factories/board_tasks.rb`
- `test/models/board_task_test.rb`
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb`
