# Story 24.3: Filtered Board Views

**Epic:** 24 — Activity Feed & Filtered Views
**Status:** ready-for-dev
**Priority:** P1 (Post-MVP)
**Independent** (no dependency on 24.1/24.2)

## User Story

**As a** user,
**I want** to filter the board by assignee, type, tags, and priority,
**So that** I can focus on relevant tasks when the board has many items.

## Acceptance Criteria

- [x] Board tasks API supports Ransack filters via `q` params:
  - `q[assignee_id_eq]` — filter by assignee
  - `q[task_type_eq]` — filter by task type
  - `q[priority_eq]` — filter by priority
  - `q[title_cont]` — search by title (contains)
  - `q[tags_contains]` — custom predicate for PostgreSQL array "any of" match
- [x] Frontend: filter bar above board columns with controls:
  - Assignee dropdown (project members)
  - Task type dropdown (epic, story, bug, not_specified)
  - Priority dropdown (low, medium, high, critical)
  - Tag multi-select (free-form + suggestions)
  - Search input (title_cont)
- [x] Filtered view: all columns still show, but only matching tasks visible
- [x] Empty columns with no matching tasks show "No matching tasks" placeholder
- [x] "Clear filters" button when any filter is active
- [x] Filter params synced to URL query string (shareable filtered views)
- [x] Tests for Ransack filtering on tasks controller

## Tasks / Subtasks

### 1. Backend: Ransack integration in tasks index
- Update `Board::TasksController#index` to use `ransack(q_params).result`
- Existing manual filters (`board_column_id`, `assignee_id`, etc.) replaced by Ransack
- Add custom `tags_contains` Ransack predicate for PostgreSQL array matching

### 2. Custom Ransack predicate for tags
- Register `tags_contains` predicate using Ransack custom predicates
- SQL: `WHERE tags && ARRAY[:values]::varchar[]` (overlaps operator)
- Alternative: custom ransacker on `BoardTask` model

### 3. Frontend: FilterBar component
- `BoardFilterBar` component in `features/board-management/ui/`
- MUI: `Select` for assignee/type/priority, `Autocomplete` for tags, `TextField` for search
- Compact horizontal layout above board columns
- "Clear all" button (visible when filters active)

### 4. Frontend: URL sync
- Filter state stored in URL search params using TanStack Router
- Params: `?assignee=1&type=story&priority=high&tag=tech_design&search=login`
- On page load: read URL params → set filters → fetch filtered data
- On filter change: update URL + refetch data

### 5. Frontend: Filtered board rendering
- `getBoard` query passes filter params to tasks API
- Columns still render (from board data)
- Tasks grouped by column, only matching tasks shown
- Columns with zero matching tasks show muted "No matching tasks" text

### 6. Frontend: Members dropdown data
- Add RTK Query endpoint for project collaborators (or reuse existing)
- Populate assignee dropdown with `[{ id, name }]`

### 7. Tests
- Controller test: Ransack filters return correct tasks
- Controller test: `tags_contains` works with PostgreSQL arrays
- Frontend: FilterBar renders controls, URL sync works

## Dev Notes

### Ransack Integration

Update `Board::TasksController#index`:

```ruby
def index
  tasks = current_board.board_tasks.ransack(q_params).result
  tasks = tasks.where(board_column_id: params[:board_column_id]) if params[:board_column_id].present?
  respond_with tasks, each_serializer: BoardTaskSerializer
end
```

Existing `q_params` helper from `ApplicationController` extracts `params[:q]`.

### Custom Tags Ransacker

Add to `BoardTask` model:

```ruby
ransacker :tags_contains, formatter: proc { |v| v } do |parent|
  parent.table[:tags]
end
```

Or use a scope-based approach:

```ruby
# In BoardTask
scope :tags_overlap, ->(tags) {
  where("tags && ARRAY[?]::varchar[]", Array(tags))
}

# In controller, combine with ransack:
tasks = current_board.board_tasks.ransack(q_params).result
tasks = tasks.tags_overlap(params[:tags]) if params[:tags].present?
```

The scope approach is simpler and avoids custom Ransack predicate registration complexity.

### Ransackable Attributes (already configured)

```ruby
# app/models/board_task.rb
def self.ransackable_attributes(_auth_object = nil)
  %w[title task_type priority assignee_id board_column_id parent_task_id position created_at updated_at]
end
```

This already supports: `title_cont`, `task_type_eq`, `priority_eq`, `assignee_id_eq`, etc.

### Frontend URL Sync Pattern

```typescript
// In BoardPanel or parent page:
const searchParams = useSearch();  // TanStack Router
const filters = {
  assignee: searchParams.assignee,
  type: searchParams.type,
  priority: searchParams.priority,
  tags: searchParams.tags?.split(','),
  search: searchParams.search,
};

// Build q params for API:
const qParams: Record<string, string> = {};
if (filters.assignee) qParams['q[assignee_id_eq]'] = filters.assignee;
if (filters.type) qParams['q[task_type_eq]'] = filters.type;
if (filters.priority) qParams['q[priority_eq]'] = filters.priority;
if (filters.search) qParams['q[title_cont]'] = filters.search;
// tags passed separately as tags[]
```

### Frontend Filter Bar Layout

```
┌─────────────────────────────────────────────────────────────┐
│ [Assignee ▾]  [Type ▾]  [Priority ▾]  [Tags...]  [🔍 Search]  [Clear] │
└─────────────────────────────────────────────────────────────┘
```

- All controls in a single horizontal `Box` with `flexWrap: 'wrap'`
- Each control: compact MUI `Select` (size="small") or `Autocomplete`
- "Clear" button: `Button variant="text"` with `onClick` that resets all filters

### Filtered Column Rendering

```typescript
const filteredTasks = boardData.tasks.filter(/* matches filters */);
const tasksByColumn = groupBy(filteredTasks, 'boardColumnId');

columns.map(col => (
  <BoardColumn key={col.id} column={col}>
    {tasksByColumn[col.id]?.length > 0
      ? tasksByColumn[col.id].map(task => <TaskCard ... />)
      : <Typography color="text.disabled">No matching tasks</Typography>
    }
  </BoardColumn>
));
```

Note: Client-side filtering is acceptable for boards with up to ~200 tasks (PRD target: 100 tasks). For larger boards, server-side filtering via API params.

### Dependencies
- BoardTask model with `ransackable_attributes` (already configured)
- Existing `q_params` helper in ApplicationController
- TanStack Router for URL param management
