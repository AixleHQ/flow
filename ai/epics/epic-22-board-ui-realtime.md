# Epic 22: Board UI & Real-time Updates

> Kanban board interface with drag-and-drop, task cards, workflow indicators, and real-time updates via ActionCable.

**Phase:** 13 (Depends on: Epic 20, Epic 21)

**PRD:** [Board & Tasks PRD](../prd/board-tasks.md)

**User Outcome:** Users see a Kanban board with columns and task cards, drag tasks between columns, see workflow status on cards, and get real-time updates when teammates or agents modify the board.

**FRs Covered:** FR28, FR29, FR30, FR31

---

## Stories

### Story 22.1: Board Page & Column Layout

**As a** user,
**I want** to see my board with columns and task cards in a Kanban layout,
**So that** I can visualize my workflow and task distribution.

**Acceptance Criteria:**
- New page: `/projects/:id/board` (TanStack Router)
- Board page loads board data with columns and tasks via API
- Columns displayed horizontally, scrollable if many columns
- Each column shows: name, purpose (tooltip/expandable), task count
- Task cards show: title, task_type badge, priority indicator, assignee avatar, tags, comments count
- Empty column shows placeholder encouraging task creation
- Column header shows "Add Task" button
- Loading state and error handling

**Technical notes:**
- Feature-Sliced Design: `pages/board/`, `features/board-management/`, `entities/board-task/`
- Use Redux Toolkit for board data (global state — multiple components need it)
- Board data fetched in single API call: `GET /board` with `include=columns.tasks`

---

### Story 22.2: Drag-and-Drop Task Movement

**As a** user,
**I want** to drag task cards between columns,
**So that** I can move tasks through workflow stages intuitively.

**Acceptance Criteria:**
- Drag-and-drop using `@dnd-kit/core` or `react-beautiful-dnd` (evaluate for React 19 compatibility)
- Drag task card from one column to another
- Visual feedback during drag: ghost card, column highlight on hover
- Drop triggers `PATCH /tasks/:id/move` API call
- Optimistic update: card moves immediately, reverts on API error
- Reorder within column supported (drag to position)
- Response time: < 200ms visual feedback on drop

**Technical notes:**
- `@dnd-kit` preferred for React 19 compatibility and active maintenance
- Optimistic update pattern: update Redux store immediately, send API request, rollback on error
- Debounce rapid moves (same task moved twice in < 500ms)

---

### Story 22.3: Task Detail Sidebar

**As a** user,
**I want** to open a task detail view,
**So that** I can see full description, comments, assets, and manage the task.

**Acceptance Criteria:**
- Click task card → opens right sidebar (or modal) with full task details
- Sections: Description, Comments (with tag filters), Assets, Activity
- Inline editing for title, description, assignee, priority, tags, task_type
- Add comment form with tag selection (multi-select from common tags + custom input)
- Upload asset button with file picker
- Epic→Story relationship display: link to parent epic, list of child stories
- Close sidebar returns to board view

**Technical notes:**
- Sidebar preferred over modal — allows seeing board context while editing task
- Comment list supports filtering by tag and author_type
- Zustand for sidebar local state (open/closed, active tab)

---

### Story 22.4: Workflow-in-Progress Indicator

**As a** user,
**I want** to see when a workflow is running for a task,
**So that** I know an agent is currently working on it.

**Acceptance Criteria:**
- Task card shows animated indicator (spinner/pulse) when a workflow run is active for this task
- Indicator links to the workflow run page
- API: task serializer includes `active_workflow_run` field (id + status, or null)
- Board API returns workflow run status for each task
- Indicator disappears when workflow completes or fails

**Technical notes:**
- Workflow run association: `BoardTask` needs `workflow_run_id` or polymorphic link
- Alternative: query `WorkflowRun.where(board_task_id: task.id, status: :running)` — simpler, no migration needed if we add `board_task_id` to `workflow_runs`
- This story connects Board to existing Workflow system — coordinate with Epic 23

---

### Story 22.5: ActionCable Real-time Board Updates

**As a** user,
**I want** my board to update in real-time when others make changes,
**So that** I always see the current state without refreshing.

**Acceptance Criteria:**
- New ActionCable channel: `BoardChannel` subscribed per project board
- Events broadcast:
  - `task_moved` — task changed column (includes task_id, from_column, to_column)
  - `task_created` / `task_updated` / `task_deleted`
  - `comment_added` — new comment on task (includes task_id, comment preview)
  - `workflow_started` / `workflow_completed` — workflow status change for task
- Frontend subscribes to `BoardChannel` on board page mount, unsubscribes on unmount
- Events trigger Redux store updates — board re-renders with new data
- Delivery target: < 500ms from server event to UI update

**Technical notes:**
- Broadcast from model callbacks or service objects after task/comment operations
- Channel authorization: verify user is project member
- Use `ActionCable.server.broadcast("board_#{board.id}", payload)` pattern
- Frontend: existing ActionCable setup from terminal sessions can be reused

---

## Dependency Graph

```
Story 22.1 (Board page + column layout)
    │
    ├──→ Story 22.2 (Drag-and-drop)
    │
    ├──→ Story 22.3 (Task detail sidebar)
    │
    └──→ Story 22.4 (Workflow indicator) — also depends on Epic 23
    
Story 22.5 (ActionCable real-time) — depends on 22.1, can be developed in parallel with 22.2-22.4
```

---

## Implementation Notes

- Board page is a new top-level page in project navigation (alongside Sessions, Workflows, Assets)
- Drag-and-drop library choice: evaluate `@dnd-kit` first — it's maintained, supports React 19, and has Sortable preset for column reorder
- ActionCable channel follows existing pattern from `TerminalSessionChannel`
- Workflow indicator requires `board_task_id` on `WorkflowRun` — this is added in Epic 23
