# Story 24.4: Saved Filter Presets

**Epic:** 24 — Activity Feed & Filtered Views
**Status:** ready-for-dev
**Priority:** P2 (Post-MVP)
**Depends on:** Story 24.3

## User Story

**As a** user,
**I want** to save named filter presets,
**So that** I can quickly switch between views like "my work" or "all bugs".

## Acceptance Criteria

- [x] Migration creates `board_view_presets` table:
  - `id`, `board_id` (not null, FK)
  - `name` (string, not null)
  - `filters` (jsonb, not null) — Ransack filter params
  - `user_id` (not null, FK) — creator
  - `shared` (boolean, default: false) — visible to all project members
  - `timestamps`
- [x] `BoardViewPreset` model with validations:
  - name presence, uniqueness per board+user
  - filters presence
- [x] CRUD API:
  - `GET /board/view_presets` — list presets (personal + shared)
  - `POST /board/view_presets` — create preset
  - `DELETE /board/view_presets/:id` — delete own preset (admin can delete any)
- [x] Policy: collaborators can CRUD own presets; admin can delete any
- [x] Frontend: preset selector dropdown in filter bar
  - Dropdown shows: built-in presets + saved presets
  - "Save current filters" button
  - Delete preset via dropdown menu
- [x] Built-in presets (frontend-only, not saved):
  - "My Work" — `{ assignee_id_eq: currentUserId }`
  - "All Bugs" — `{ task_type_eq: "bug" }`
- [x] Unit tests for model and controller tests for API

## Tasks / Subtasks

### 1. Migration
- Create `board_view_presets` table
- Indexes: `[board_id, user_id]`, `[board_id, shared]`
- Unique index: `[board_id, user_id, name]`

### 2. Model
- `BoardViewPreset` with associations (belongs_to board, belongs_to user)
- Validations: name presence, name uniqueness per board+user, filters presence
- Scopes: `personal(user)`, `shared`, `visible_to(user)`

### 3. Serializer
- `BoardViewPresetSerializer`: `id`, `name`, `filters`, `user_id`, `shared`, `created_at`

### 4. Controller
- `Board::ViewPresetsController` (index, create, destroy)
- `index`: returns `preset.visible_to(current_user)` — personal + shared
- `create`: builds preset for current_user on current_board
- `destroy`: own presets + admin can delete any

### 5. Policy
- `Board::ViewPresetsPolicy`
- `index?` → `project_accessible?`
- `create?` → `project_accessible?`
- `destroy?` → own preset OR `project_admin?`

### 6. Route
- Add inside `resource :board` block:
  ```ruby
  resources :view_presets, controller: "board/view_presets", only: %i[index create destroy]
  ```

### 7. Frontend: Preset selector
- Add preset dropdown to `BoardFilterBar` (from 24.3)
- MUI `Select` or `Menu` with:
  - Section: "Built-in" — My Work, All Bugs
  - Section: "Saved" — user's presets + shared presets
  - Each item: name + delete icon (if own)
- Selecting a preset → applies its filters → updates URL + board

### 8. Frontend: Save preset dialog
- Button "Save filters" in FilterBar (visible when filters active)
- MUI `Dialog` with: name input, shared checkbox
- Calls `POST /board/view_presets` with current filter state

### 9. RTK Query endpoints
- `getViewPresets: builder.query(...)` — fetches list
- `createViewPreset: builder.mutation(...)` — creates preset
- `deleteViewPreset: builder.mutation(...)` — deletes preset

### 10. Tests
- Model tests: validations, scopes, uniqueness
- Controller tests: CRUD, access control, visibility rules

## Dev Notes

### Model

```ruby
class BoardViewPreset < ApplicationRecord
  belongs_to :board
  belongs_to :user

  validates :name, presence: true
  validates :name, uniqueness: { scope: %i[board_id user_id] }
  validates :filters, presence: true

  scope :personal, ->(user) { where(user: user) }
  scope :shared_presets, -> { where(shared: true) }
  scope :visible_to, ->(user) { personal(user).or(shared_presets) }
end
```

### Controller Pattern

```ruby
module Api::V1::Company::Projects::Board
  class ViewPresetsController < Api::V1::Company::Projects::ApplicationController
    def index
      presets = current_board.board_view_presets.visible_to(current_user)
      respond_with presets, each_serializer: BoardViewPresetSerializer
    end

    def create
      preset = current_board.board_view_presets.build(preset_params)
      preset.user = current_user
      preset.save
      respond_with preset, serializer: BoardViewPresetSerializer
    end

    def destroy
      preset = current_board.board_view_presets.find(params[:id])
      unless preset.user_id == current_user.id || current_project.admin?(current_user)
        return head :forbidden
      end
      preset.destroy
      head :no_content
    end

    private

    def current_board
      @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
    end

    def preset_params
      params.require(:board_view_preset).permit(:name, :shared, filters: {})
    end
  end
end
```

### Filters JSONB Structure

Presets store the Ransack query hash:

```json
{
  "assignee_id_eq": 42,
  "task_type_eq": "bug",
  "priority_eq": "high",
  "title_cont": "login"
}
```

Tags stored separately (not Ransack):
```json
{
  "task_type_eq": "bug",
  "_tags": ["tech_design", "urgent"]
}
```

Frontend reads `filters` and applies them as URL params + API query params.

### Built-in Presets (Frontend-only)

```typescript
const BUILT_IN_PRESETS = [
  { id: 'my-work', name: 'My Work', filters: { assignee_id_eq: currentUserId } },
  { id: 'all-bugs', name: 'All Bugs', filters: { task_type_eq: 'bug' } },
];
```

These are not stored in DB — constructed at render time using `currentUserId`.

### Frontend Preset Dropdown

```
┌─────────────────────┐
│ ≡ Presets        ▾  │
├─────────────────────┤
│ Built-in            │
│   ○ My Work         │
│   ○ All Bugs        │
├─────────────────────┤
│ Saved               │
│   ○ Sprint 3 tasks  │ [×]
│   ○ High priority   │ [×]
│   ○ Agent reviews (shared) │
├─────────────────────┤
│ + Save current      │
└─────────────────────┘
```

### Dependencies
- Story 24.3 (FilterBar component, URL param sync)
- Existing: Board model, User model, project access control
