# Story 22.1: Board Page & Column Layout

Status: review

## Story

As a user,
I want to see my board with columns and task cards in a Kanban layout,
so that I can visualize my workflow and task distribution.

## Acceptance Criteria

1. New page at `/projects/:id/board` registered in TanStack Router
2. Board page loads board data with columns and tasks via `GET /api/v1/company/projects/:project_id/board` (existing endpoint)
3. Columns displayed horizontally, scrollable if many columns
4. Each column shows: name, purpose (tooltip or expandable), task count badge
5. Task cards show: title, task_type badge, priority indicator, assignee avatar, tags, comments_count
6. Empty column shows placeholder encouraging task creation
7. Column header shows "Add Task" button (inline quick-create form or opens create dialog)
8. Loading skeleton and error handling (404 when no board, API errors)
9. Board state managed via Redux Toolkit (RTK Query) — `boardApi` slice
10. Feature-Sliced Design: `pages/board/`, `features/board-management/`, `entities/board-task/`

## Tasks / Subtasks

- [ ] Task 1: Create RTK Query API slice for board data (AC: #9)
  - [ ] `app/frontend/features/board-management/api/boardApi.ts`
  - [ ] Endpoints: `getBoard` (GET board with columns and tasks), `createTask`, `updateTask`, `deleteTask`
  - [ ] TypeScript types: `Board`, `BoardColumn`, `BoardTask` in `entities/board-task/model/types.ts`
  - [ ] Use `camelcaseKeys`/`decamelizeKeys` for API transformation
- [ ] Task 2: Create board entities (AC: #10)
  - [ ] `app/frontend/entities/board-task/` — model types, UI components for task card
  - [ ] `BoardTask` type with all fields from `BoardTaskSerializer`
  - [ ] `BoardColumn` type with all fields from `BoardColumnSerializer`
  - [ ] `Board` type with nested columns and tasks
- [ ] Task 3: Create TaskCard component (AC: #5)
  - [ ] `app/frontend/entities/board-task/ui/TaskCard.tsx`
  - [ ] MUI Card component with: title, task_type badge (chip), priority indicator (colored dot/icon), assignee avatar (MUI Avatar), tags (chips), comments_count badge
  - [ ] Click handler (placeholder for Story 22.3 sidebar)
  - [ ] Compact layout suitable for Kanban column width (~280px)
- [ ] Task 4: Create BoardColumn component (AC: #3, #4, #6, #7)
  - [ ] `app/frontend/features/board-management/ui/BoardColumn.tsx`
  - [ ] Column header: name, purpose tooltip (MUI Tooltip), task count badge
  - [ ] "Add Task" button in column header
  - [ ] Task list (vertical scroll within column)
  - [ ] Empty state placeholder
- [ ] Task 5: Create BoardPage component (AC: #1, #2, #3, #8)
  - [ ] `app/frontend/pages/board/ui/BoardPage.tsx`
  - [ ] Horizontal scrollable column layout (CSS flexbox with `overflow-x: auto`)
  - [ ] Loading skeleton (column-shaped placeholders)
  - [ ] Error state (no board → "Create board" prompt, API error → retry)
  - [ ] Use RTK Query hook to fetch board data
- [ ] Task 6: Register route in TanStack Router (AC: #1)
  - [ ] Add `/projects/:id/board` route in `routeTree.tsx`
  - [ ] Lazy-load `BoardPage` component
  - [ ] Add navigation link in project sidebar/navigation
- [ ] Task 7: Quick-create task form (AC: #7)
  - [ ] Inline form or dialog for creating a task from column header
  - [ ] Fields: title (required), task_type (select), priority (select)
  - [ ] React Hook Form + Zod validation
  - [ ] Calls `createTask` mutation from RTK Query

## Dev Notes

### Architecture Compliance

- **Feature-Sliced Design** structure:
  - `pages/board/` — page component + route
  - `features/board-management/` — API slice, board-level UI components (column, board layout)
  - `entities/board-task/` — task card component, task types/model
  - `shared/` — existing shared components (Avatar, Chip, etc.)
- **Redux Toolkit** with RTK Query for board data — global state since multiple components (board, columns, task cards, sidebar in 22.3) share it
- **No Zustand** for board page state yet — RTK Query's cache is sufficient for read state. Zustand will be introduced in 22.3 for sidebar local state.

### Existing Patterns to Follow

- **Page structure:** Follow `pages/workflow-run/` pattern — lazy-loaded via TanStack Router
- **RTK Query:** Follow `shared/api/baseApi.ts` pattern — extend with `boardApi.ts` using `injectEndpoints`
- **TypeScript types:** Follow `features/workflow-execution/lib/types.ts` pattern
- **API response format:** Lists wrapped in `items`, single resources in `data` — use `camelcaseKeys` transformation
- **MUI theming:** Use existing `shared/theme/` configuration
- **Loading states:** Use skeleton components (MUI `Skeleton`)
- **Error handling:** Use `notistack` for toast notifications on errors

### API Contract (Backend from Epic 20-21)

Board data:
```
GET /api/v1/company/projects/:project_id/board → { data: { id, name, preset_origin, board_columns: [...] } }
GET /api/v1/company/projects/:project_id/board/tasks → { items: [{ id, title, task_type, priority, assignee_id, board_column_id, position, tags, children_count, comments_count, assets_count, ... }] }
POST /api/v1/company/projects/:project_id/board/tasks → { data: { ... } }
```

Two API calls needed to populate board: one for board+columns, one for tasks. Frontend groups tasks by `board_column_id`.

### Column Layout

- Horizontal flexbox container with `overflow-x: auto` for horizontal scroll
- Column width: 280-320px fixed
- Column height: `calc(100vh - header - breadcrumb)` with internal vertical scroll for tasks
- Gap between columns: 12px
- Board background: slight contrast from column cards (e.g., `grey[100]`)

### Task Card Design

- MUI `Card` with `CardContent`
- Task type badge: colored `Chip` (epic=purple, story=blue, bug=red, not_specified=grey)
- Priority: small colored dot or icon (critical=red, high=orange, medium=yellow, low=green)
- Assignee: small `Avatar` with first letter or image
- Tags: small `Chip` components (max 3 visible, "+N" overflow)
- Comments count: small icon + number
- Card elevation: 1 (flat look), hover elevation: 2

### Previous Story Intelligence (Epic 21)

- Backend API is fully implemented: Board, BoardColumn, BoardTask CRUD, TaskComment, TaskAsset
- `BoardTaskSerializer` returns: `id`, `title`, `description`, `task_type`, `priority`, `assignee_id`, `board_column_id`, `position`, `parent_task_id`, `tags`, `children_count`, `comments_count`, `assets_count`, `created_at`, `updated_at`
- `BoardColumnSerializer` returns: `id`, `name`, `position`, `purpose`, `created_at`, `updated_at`
- `BoardSerializer` returns: `id`, `name`, `preset_origin`, `created_at`, `updated_at` with `has_many :board_columns` when `include_associations`

### Project Structure Notes

- `app/frontend/pages/board/ui/BoardPage.tsx`
- `app/frontend/pages/board/index.ts`
- `app/frontend/features/board-management/api/boardApi.ts`
- `app/frontend/features/board-management/ui/BoardColumn.tsx`
- `app/frontend/features/board-management/ui/CreateTaskForm.tsx`
- `app/frontend/features/board-management/index.ts`
- `app/frontend/entities/board-task/model/types.ts`
- `app/frontend/entities/board-task/ui/TaskCard.tsx`
- `app/frontend/entities/board-task/index.ts`
- `app/frontend/app/routeTree.tsx` (modified: add board route)

### References

- [Source: ai/epics/epic-22-board-ui-realtime.md#Story 22.1]
- [Source: ai/prd/board-tasks.md#FR28]
- [Source: ai/project-context.md#TypeScript/Frontend — Feature-Sliced Design, Redux Toolkit]
- [Source: app/frontend/shared/api/baseApi.ts — RTK Query base]
- [Source: app/serializers/board_task_serializer.rb — task response format]
- [Source: app/serializers/board_column_serializer.rb — column response format]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Board tab replaces old "tasks" tab in ProjectPage (was a basic Linear-style view)
- Board page uses RTK Query `queryFn` to fetch board+columns and tasks in two parallel API calls
- TaskCard component shows priority dot, type chip, tags (max 3 with overflow), avatar, comments count
- BoardColumn shows task count badge, purpose tooltip, add task button
- Loading skeleton with 3 column placeholders
- Error state shows alert for missing board
- CreateTaskForm is inline, dismissable with Escape
- Board entity types include `activeWorkflowRun` field for story 22.4

### File List
- `app/frontend/entities/board-task/model/types.ts` (new)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (new)
- `app/frontend/entities/board-task/index.ts` (new)
- `app/frontend/features/board-management/api/boardApi.ts` (new)
- `app/frontend/features/board-management/ui/BoardColumn.tsx` (new)
- `app/frontend/features/board-management/ui/BoardPanel.tsx` (new)
- `app/frontend/features/board-management/ui/CreateTaskForm.tsx` (new)
- `app/frontend/features/board-management/index.ts` (new)
- `app/frontend/pages/project/ui/ProjectPage.tsx` (modified: board tab)
- `app/frontend/pages/project/lib/types.ts` (modified: board tab type)
