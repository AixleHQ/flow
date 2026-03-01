# Story 22.3: Task Detail Sidebar

Status: review

## Story

As a user,
I want to open a task detail view,
so that I can see full description, comments, assets, and manage the task.

## Acceptance Criteria

1. Click task card opens right sidebar panel with full task details
2. Sidebar sections: Description, Comments, Assets, Hierarchy (parent epic / child stories)
3. Inline editing for: title, description, assignee, priority, tags, task_type
4. Add comment form with tag selection (multi-select from common tags + custom input)
5. Upload asset button with file picker
6. Epic→Story relationship: link to parent epic, list of child stories (from `parent_task_id`, `children_count`)
7. Close sidebar (X button or click outside) returns to board view
8. Sidebar state managed via Zustand (open/closed, active task ID)
9. Comment list supports filtering by tag and author_type

## Tasks / Subtasks

- [ ] Task 1: Create Zustand store for sidebar state (AC: #8)
  - [ ] `app/frontend/features/board-management/model/useBoardSidebarStore.ts`
  - [ ] State: `isOpen: boolean`, `activeTaskId: number | null`, `activeTab: string`
  - [ ] Actions: `openTask(id)`, `close()`, `setTab(tab)`
- [ ] Task 2: Create RTK Query endpoints for task details (AC: #2, #9)
  - [ ] `getTask(taskId)` — full task detail
  - [ ] `getTaskComments(taskId, filters?)` — comments with optional `tag`, `author_type` filters
  - [ ] `getTaskAssets(taskId, filters?)` — assets with optional `tag` filter
  - [ ] `createComment(taskId, body, tags)` — create comment
  - [ ] `createAsset(taskId, formData)` — upload asset
  - [ ] `deleteAsset(taskId, assetId)` — delete asset
- [ ] Task 3: Create TaskSidebar container component (AC: #1, #7)
  - [ ] `app/frontend/features/board-management/ui/TaskSidebar.tsx`
  - [ ] MUI `Drawer` (anchor: right, variant: persistent or temporary)
  - [ ] Width: 450-500px
  - [ ] Header: task title (editable), close button, task_type badge
  - [ ] Tab navigation: Details, Comments, Assets
- [ ] Task 4: Create TaskDetailsTab component (AC: #2, #3, #6)
  - [ ] `app/frontend/features/board-management/ui/TaskDetailsTab.tsx`
  - [ ] Description field: inline editable (textarea, save on blur)
  - [ ] Assignee: select dropdown from project members
  - [ ] Priority: select dropdown
  - [ ] Task type: select dropdown
  - [ ] Tags: chip input (add/remove)
  - [ ] Hierarchy: parent epic link (if `parent_task_id`), children list (if `children_count > 0`)
  - [ ] React Hook Form for editable fields
- [ ] Task 5: Create CommentsTab component (AC: #4, #9)
  - [ ] `app/frontend/features/board-management/ui/CommentsTab.tsx`
  - [ ] Comment list with author name, author_type badge, timestamp, tags, body
  - [ ] Filter controls: tag dropdown, author_type radio/chips
  - [ ] Add comment form at bottom: body textarea, tag multi-select
  - [ ] Common tags: `feedback`, `tech_design`, `code_review`, `qa_report`, custom input
  - [ ] Submit creates comment via RTK Query mutation
- [ ] Task 6: Create AssetsTab component (AC: #5)
  - [ ] `app/frontend/features/board-management/ui/AssetsTab.tsx`
  - [ ] Asset list with name, file size, content type, author, tags
  - [ ] Download link (presigned URL from `file_url`)
  - [ ] Upload button: file picker, calls `createAsset` mutation
  - [ ] Delete button (visible for author or admin)
- [ ] Task 7: Wire TaskCard click to sidebar (AC: #1)
  - [ ] Update `TaskCard` onClick → `useBoardSidebarStore().openTask(task.id)`
  - [ ] `BoardPage` renders `TaskSidebar` component
  - [ ] Sidebar opens when `activeTaskId` is set

## Dev Notes

### Architecture Compliance

- **Zustand** for sidebar local state — appropriate for UI-only state (open/close, active tab), not shared with other features
- **RTK Query** for task detail API calls — cached, invalidated when mutations succeed
- **MUI Drawer** for sidebar — persistent variant allows seeing board context while editing
- **React Hook Form + Zod** for inline editing forms — follow existing project patterns
- **Feature-Sliced Design**: sidebar components go in `features/board-management/ui/`

### Existing Patterns to Follow

- **Sidebar/Drawer:** No existing sidebar pattern — this is a new pattern for the project. Use MUI `Drawer` with right anchor.
- **Inline editing:** Follow React Hook Form patterns from existing forms
- **File upload:** Follow existing asset upload patterns (if any in `features/assets-management/`)
- **Comment rendering:** Markdown support via `react-markdown` (already installed)

### API Endpoints (Backend from Epic 21)

```
GET    /board/tasks/:id                    → task detail
GET    /board/tasks/:task_id/comments      → comments (filter: tag, author_type)
POST   /board/tasks/:task_id/comments      → create comment { body, tags[] }
GET    /board/tasks/:task_id/assets         → assets (filter: tag)
POST   /board/tasks/:task_id/assets         → upload asset { name, file, tags[] }
DELETE /board/tasks/:task_id/assets/:id     → delete asset
PATCH  /board/tasks/:id                    → update task fields
```

### Comment Tag Suggestions

Predefined tags (can be extended):
- `feedback` — human feedback to agent
- `tech_design` — technical design output
- `code_review` — code review results
- `qa_report` — QA testing results
- `implementation_notes` — implementation notes
- Custom tags via free text input

### Project Structure Notes

- `app/frontend/features/board-management/model/useBoardSidebarStore.ts`
- `app/frontend/features/board-management/ui/TaskSidebar.tsx`
- `app/frontend/features/board-management/ui/TaskDetailsTab.tsx`
- `app/frontend/features/board-management/ui/CommentsTab.tsx`
- `app/frontend/features/board-management/ui/AssetsTab.tsx`
- `app/frontend/features/board-management/api/boardApi.ts` (modified: add detail endpoints)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (modified: add click handler)
- `app/frontend/pages/board/ui/BoardPage.tsx` (modified: add sidebar)

### References

- [Source: ai/epics/epic-22-board-ui-realtime.md#Story 22.3]
- [Source: ai/prd/board-tasks.md#FR16, FR19, FR20, FR23, FR24, FR26]
- [Source: ai/project-context.md#TypeScript/Frontend — Zustand, React Hook Form + Zod]
- [Source: app/controllers/api/v1/company/projects/board/task/comments_controller.rb — comments API]
- [Source: app/controllers/api/v1/company/projects/board/task/assets_controller.rb — assets API]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Zustand store manages sidebar state: isOpen, activeTaskId, activeTab
- MUI Drawer (temporary, right anchor, 480px width)
- Three tabs: Details, Comments, Assets
- TaskDetailsTab: inline editing for description (blur to save), select dropdowns for type/priority
- CommentsTab: filter by author_type and tag, add comment with tag autocomplete (freeSolo)
- AssetsTab: file upload via hidden input, download link, delete button
- RTK Query endpoints for comments (with filters), assets, and CRUD mutations
- TaskCard click opens sidebar via Zustand store

### File List
- `app/frontend/features/board-management/model/useBoardSidebarStore.ts` (new)
- `app/frontend/features/board-management/ui/TaskSidebar.tsx` (new)
- `app/frontend/features/board-management/ui/TaskDetailsTab.tsx` (new)
- `app/frontend/features/board-management/ui/CommentsTab.tsx` (new)
- `app/frontend/features/board-management/ui/AssetsTab.tsx` (new)
- `app/frontend/features/board-management/api/boardApi.ts` (modified: detail endpoints)
