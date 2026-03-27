# Story 20.2: Column Model with Purpose Field

Status: review

## Story

As a user,
I want to manage columns on my board with names, positions, and purpose descriptions,
so that I can define my workflow stages and communicate their intent to agents.

## Acceptance Criteria

1. Migration creates `board_columns` table: `id` (bigint PK), `board_id` (references boards, not null, FK), `name` (string, not null), `position` (integer, not null), `purpose` (text, nullable), `timestamps`
2. Unique composite index on `[board_id, position]`
3. Index on `board_id` for foreign key queries
4. `BoardColumn` model with `belongs_to :board`, validates `name` presence, validates `position` uniqueness scoped to `board_id`
5. Board `has_many :board_columns, -> { order(:position) }, dependent: :destroy` (added in 20.1, verify)
6. Column CRUD nested under board: `POST /board/columns`, `PATCH /board/columns/:id`, `DELETE /board/columns/:id`
7. Reorder endpoint: `PATCH /board/columns/reorder` accepts `{ column_ids: [3, 1, 2] }`, updates positions in transaction
8. Pundit policy: Admin can create/update/destroy/reorder columns; Collaborator can read
9. `BoardColumnSerializer` with `id`, `name`, `position`, `purpose`, `created_at`, `updated_at`
10. Creating a column auto-assigns next position (max position + 1)
11. Deleting a column re-compacts positions of remaining columns

## Tasks / Subtasks

- [x] Task 1: Create migration (AC: #1, #2, #3)
  - [x] Generate migration `CreateBoardColumns`
  - [x] `board_id` with FK constraint to boards
  - [x] `name` (string, not null), `position` (integer, not null), `purpose` (text, nullable)
  - [x] Unique index on `[board_id, position]`
  - [x] Timestamps
- [x] Task 2: Create BoardColumn model (AC: #4, #5, #10)
  - [x] `app/models/board_column.rb`
  - [x] `belongs_to :board`
  - [x] Validates `name` presence, `position` presence
  - [x] Validates `position` uniqueness scoped to `board_id`
  - [x] `before_validation :assign_next_position, on: :create` — sets position to `board.board_columns.maximum(:position).to_i + 1`
  - [x] Ransack config
- [x] Task 3: Verify Board model association (AC: #5)
  - [x] Confirm `has_many :board_columns, -> { order(:position) }, dependent: :destroy` on Board
- [x] Task 4: Create BoardColumnSerializer (AC: #9)
  - [x] `app/serializers/board_column_serializer.rb` inheriting `ApplicationSerializer`
  - [x] Attributes: `id`, `name`, `position`, `purpose`, `created_at`, `updated_at`
- [x] Task 5: Create Pundit policy (AC: #8)
  - [x] `app/policies/api/v1/company/projects/board/columns_policy.rb`
  - [x] `index?`, `show?` → `project_accessible?`
  - [x] `create?`, `update?`, `destroy?`, `reorder?` → `project_admin?`
- [x] Task 6: Create controller (AC: #6, #7, #10, #11)
  - [x] `app/controllers/api/v1/company/projects/board/columns_controller.rb`
  - [x] Inherit from `Api::V1::Company::Projects::ApplicationController`
  - [x] `index`: list columns for board (ordered by position)
  - [x] `create`: build column with auto-position, respond_with
  - [x] `update`: update name/purpose
  - [x] `destroy`: destroy + re-compact positions
  - [x] `reorder`: accept `column_ids` array, update positions in transaction
  - [x] Strong params: `params.require(:board_column).permit(:name, :purpose)`
- [x] Task 7: Add routes (AC: #6, #7)
  - [x] Nest under board: `resource :board do; resources :columns, controller: 'board/columns' do; collection { patch :reorder }; end; end`
- [x] Task 8: Position re-compaction service (AC: #11)
  - [x] After column destroy, re-number remaining columns: `board.board_columns.order(:position).each_with_index { |col, i| col.update_column(:position, i + 1) }`
  - [x] Implemented as private method in controller
- [x] Task 9: Factory and tests
  - [x] FactoryBot factory for `board_column` with sequence for position
  - [x] Model test: validations, auto-position assignment
  - [x] Controller test: CRUD, reorder, position compaction

## Dev Notes

### Architecture Compliance

- Table named `board_columns` (NOT `columns`) to avoid Rails reserved word conflict.
- Columns are NOT polymorphic-scoped — they belong directly to a board.
- Position management is manual (integer column with uniqueness constraint), NOT `acts_as_list` gem.
- Reorder endpoint uses bulk update in transaction to prevent race conditions.
- Two-pass reorder to avoid unique constraint violations (offset then final positions).

### Reorder Implementation

```ruby
def reorder
  board = current_project.board
  ActiveRecord::Base.transaction do
    offset = board.board_columns.count + 1
    params[:column_ids].each_with_index do |id, index|
      board.board_columns.find(id).update_column(:position, offset + index + 1)
    end
    params[:column_ids].each_with_index do |id, index|
      board.board_columns.find(id).update_column(:position, index + 1)
    end
  end
  respond_with board.board_columns.reload.order(:position), each_serializer: BoardColumnSerializer
end
```

### Position Compaction on Delete

```ruby
def destroy
  column = current_project.board.board_columns.find(params[:id])
  column.destroy!
  compact_positions(column.board)
  head :no_content
end

private

def compact_positions(board)
  board.board_columns.order(:position).each_with_index do |col, idx|
    col.update_column(:position, idx + 1)
  end
end
```

### API Contract

```
GET    /api/v1/company/projects/:project_id/board/columns            → index
POST   /api/v1/company/projects/:project_id/board/columns            → create
PATCH  /api/v1/company/projects/:project_id/board/columns/:id        → update
DELETE /api/v1/company/projects/:project_id/board/columns/:id        → destroy
PATCH  /api/v1/company/projects/:project_id/board/columns/reorder    → reorder
```

Create request:
```json
{ "board_column": { "name": "Tech Design", "purpose": "Agent creates tech design document" } }
```

Reorder request:
```json
{ "column_ids": [3, 1, 2] }
```

### Project Structure Notes

- `app/models/board_column.rb`
- `app/controllers/api/v1/company/projects/board/columns_controller.rb`
- `app/serializers/board_column_serializer.rb`
- `app/policies/api/v1/company/projects/board/columns_policy.rb`
- `test/models/board_column_test.rb`
- `test/factories/board_columns.rb`

### References

- [Source: ai/epics/epic-20-board-column-foundation.md#Story 20.2]
- [Source: ai/prd/board-tasks.md#FR2, FR3]
- [Source: ai/project-context.md#Implementation Rules]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Debug Log References

### Completion Notes List
- Created `board_columns` table migration with FK, unique composite index on [board_id, position]
- BoardColumn model with auto-position assignment, uniqueness validation, Ransack config
- BoardColumnSerializer with id, name, position, purpose, timestamps
- ColumnsPolicy (under Board module) with admin-only write operations
- ColumnsController with CRUD + reorder + position compaction
- Two-pass reorder to avoid unique constraint violations
- Routes nested under board with reorder collection action
- Factory + 25 tests (model + controller) covering all operations and authorization

### File List
- db/migrate/20260227100001_create_board_columns.rb (new)
- app/models/board_column.rb (new)
- app/serializers/board_column_serializer.rb (new)
- app/policies/api/v1/company/projects/board/columns_policy.rb (new)
- app/controllers/api/v1/company/projects/board/columns_controller.rb (new)
- config/routes.rb (modified — added columns routes under board)
- test/factories/board_columns.rb (new)
- test/models/board_column_test.rb (new)
- test/controllers/api/v1/company/projects/board/columns_controller_test.rb (new)

## Change Log
- 2026-02-27: Implemented BoardColumn model, controller, serializer, policy, routes, factory, and tests (Story 20.2)
