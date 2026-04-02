# Story 20.1: Board Model & Project Association

Status: review

## Story

As a user,
I want to create a board for my project,
so that I have a dedicated task management space integrated with AIXLE workflows.

## Acceptance Criteria

1. Migration creates `boards` table with columns: `id` (bigint PK), `project_id` (references projects, not null, unique index), `name` (string, not null), `preset_origin` (string, nullable), `timestamps`
2. `Board` model with `belongs_to :project`, uniqueness validation on `project_id`
3. `Project` model gains `has_one :board, dependent: :destroy`
4. Board API at `api/v1/company/projects/:project_id/board` as singular resource (`resource :board, only: [:show, :create, :update, :destroy]`)
5. Create endpoint accepts `name` and `preset` parameters
6. Pundit policy: Admin can create/update/destroy board; Collaborator can read (show)
7. Serializer: `BoardSerializer` with `id`, `name`, `preset_origin`, `columns` (embedded `has_many`), `created_at`, `updated_at`
8. Show returns 404 if no board exists for the project
9. Create returns 422 if board already exists for the project (unique constraint)

## Tasks / Subtasks

- [x] Task 1: Create migration (AC: #1)
  - [x] Generate migration `CreateBoards`
  - [x] Add `project_id` with unique index and foreign key constraint
  - [x] Add `name` (string, not null) and `preset_origin` (string, nullable)
  - [x] Add timestamps
- [x] Task 2: Create Board model (AC: #2)
  - [x] `app/models/board.rb` with `belongs_to :project`
  - [x] Validate `project_id` uniqueness
  - [x] Validate `name` presence
  - [x] Add `has_many :board_columns, -> { order(:position) }, dependent: :destroy`
  - [x] Add Ransack config: `ransackable_attributes`, `ransackable_associations`
- [x] Task 3: Update Project model (AC: #3)
  - [x] Add `has_one :board, dependent: :destroy` to `app/models/project.rb`
- [x] Task 4: Create BoardSerializer (AC: #7)
  - [x] `app/serializers/board_serializer.rb` inheriting `ApplicationSerializer`
  - [x] Attributes: `id`, `name`, `preset_origin`, `created_at`, `updated_at`
  - [x] `has_many :board_columns` (will be empty until Story 20.2)
- [x] Task 5: Create Pundit policy (AC: #6)
  - [x] `app/policies/api/v1/company/projects/boards_policy.rb`
  - [x] Inherit from `Api::V1::Company::ApplicationPolicy`
  - [x] `show?` → `project_accessible?`
  - [x] `create?`, `update?`, `destroy?` → `project_admin?`
- [x] Task 6: Create controller (AC: #4, #5, #8, #9)
  - [x] `app/controllers/api/v1/company/projects/boards_controller.rb`
  - [x] Inherit from `Api::V1::Company::Projects::ApplicationController`
  - [x] Actions: `show`, `create`, `update`, `destroy`
  - [x] `show`: `current_project.board` or 404
  - [x] `create`: build board from params, handle unique constraint
  - [x] Strong params: `params.require(:board).permit(:name)`
- [x] Task 7: Add routes (AC: #4)
  - [x] Add singular `resource :board, only: [:show, :create, :update, :destroy]` inside project scope
- [x] Task 8: Create factory and tests
  - [x] FactoryBot factory for `board`
  - [x] Model test: validations (uniqueness, presence)
  - [x] Controller test: CRUD operations, authorization

## Dev Notes

### Architecture Compliance

- **NOT a polymorphic-scoped resource.** Board belongs directly to Project (1:1), not polymorphic like Agent/Tool/Skill. No `scope_type`/`scope_id` pattern here.
- Use singular `resource :board` in routes (not `resources :boards`) — one board per project.
- Controller uses `current_project.board` / `current_project.build_board(board_params)` pattern.

### Existing Patterns to Follow

- **Controller hierarchy:** `Api::V1::Company::Projects::BoardsController < Api::V1::Company::Projects::ApplicationController`
- **`current_project`** is provided by `ApplicationController` — use it directly.
- **`respond_with`** from responders gem for all responses.
- **Serializer:** inherit from `ApplicationSerializer`. Do NOT include `ScopeIndicatorSerialization` (Board is not polymorphic-scoped).
- **Policy:** inherit from `Api::V1::Company::ApplicationPolicy`, use `project_accessible?` helper.
- **`# frozen_string_literal: true`** at top of every Ruby file.
- **enumerize** if any enum fields needed (none for Board currently).
- **Tests:** Minitest in `test/` directory, FactoryBot factories in `test/factories/`.

### Database Schema

```sql
CREATE TABLE boards (
  id bigserial PRIMARY KEY,
  project_id bigint NOT NULL REFERENCES projects(id),
  name varchar NOT NULL,
  preset_origin varchar,
  created_at timestamp NOT NULL,
  updated_at timestamp NOT NULL
);
CREATE UNIQUE INDEX index_boards_on_project_id ON boards(project_id);
```

### API Contract

```
GET    /api/v1/company/projects/:project_id/board     → show
POST   /api/v1/company/projects/:project_id/board     → create
PATCH  /api/v1/company/projects/:project_id/board     → update
DELETE /api/v1/company/projects/:project_id/board     → destroy
```

Response format (show/create/update):
```json
{
  "data": {
    "id": 1,
    "name": "Dev Board",
    "preset_origin": "dev_team",
    "columns": [],
    "created_at": "...",
    "updated_at": "..."
  }
}
```

### Project Structure Notes

- `app/models/board.rb`
- `app/controllers/api/v1/company/projects/boards_controller.rb`
- `app/serializers/board_serializer.rb`
- `app/policies/api/v1/company/projects/boards_policy.rb`
- `test/models/board_test.rb`
- `test/factories/boards.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_boards.rb`

### References

- [Source: ai/epics/epic-20-board-column-foundation.md#Story 20.1]
- [Source: ai/prd/board-tasks.md#FR1, FR5]
- [Source: ai/project-context.md#Architecture Patterns]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References

### Completion Notes List
- Created `boards` table migration with unique project_id index and FK constraint
- Board model with belongs_to :project, uniqueness/presence validations, has_many :board_columns
- Updated Project model with `has_one :board, dependent: :destroy`
- BoardSerializer with id, name, preset_origin, timestamps, has_many board_columns
- BoardsPolicy: show → project_accessible?, create/update/destroy → project_admin?
- BoardsController: singular resource CRUD, 404 for missing board, 422 for duplicate
- Routes: `resource :board` nested under projects
- Factory + 20 tests (model + controller) covering validations, CRUD, authorization

### File List
- db/migrate/20260227100000_create_boards.rb (new)
- app/models/board.rb (new)
- app/models/project.rb (modified — added has_one :board)
- app/serializers/board_serializer.rb (new)
- app/policies/api/v1/company/projects/boards_policy.rb (new)
- app/controllers/api/v1/company/projects/boards_controller.rb (new)
- config/routes.rb (modified — added board routes)
- test/factories/boards.rb (new)
- test/models/board_test.rb (new)
- test/controllers/api/v1/company/projects/boards_controller_test.rb (new)

## Change Log
- 2026-02-27: Implemented Board model, controller, serializer, policy, routes, factory, and tests (Story 20.1)
