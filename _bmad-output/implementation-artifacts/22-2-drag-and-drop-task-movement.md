# Story 22.2: Drag-and-Drop Task Movement

Status: review

## Story

As a user,
I want to drag task cards between columns,
so that I can move tasks through workflow stages intuitively.

## Acceptance Criteria

1. Install `@dnd-kit/core` and `@dnd-kit/sortable` libraries
2. Drag task card from one column to another
3. Visual feedback during drag: ghost card, column highlight on hover (drop target indication)
4. Drop triggers `PATCH /board/tasks/:id/move` API call with `column_id` and `position`
5. Optimistic update: card moves immediately in Redux store, reverts on API error
6. Reorder within column supported (drag to specific position)
7. Response time: < 200ms visual feedback on drop
8. Debounce rapid moves: same task moved twice within 500ms → only last move sent to API

## Tasks / Subtasks

- [ ] Task 1: Install @dnd-kit dependencies (AC: #1)
  - [ ] `yarn add @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities`
  - [ ] Verify React 19 compatibility
- [ ] Task 2: Create DnD context for board (AC: #2, #3)
  - [ ] `app/frontend/features/board-management/ui/BoardDndContext.tsx`
  - [ ] Wrap board columns in `DndContext` from `@dnd-kit/core`
  - [ ] Each column is a `SortableContext` for within-column reorder
  - [ ] Each column acts as droppable container
  - [ ] `DragOverlay` component for ghost card rendering
- [ ] Task 3: Make TaskCard draggable (AC: #2)
  - [ ] Update `TaskCard` to use `useSortable` from `@dnd-kit/sortable`
  - [ ] Apply `transform` and `transition` CSS from sortable
  - [ ] Drag handle: entire card is draggable
- [ ] Task 4: Make BoardColumn droppable (AC: #2, #3)
  - [ ] Update `BoardColumn` to use `useDroppable` from `@dnd-kit/core`
  - [ ] Highlight column background when dragging over (visual indicator)
  - [ ] Accept task drops from any column
- [ ] Task 5: Add RTK Query mutation for move (AC: #4)
  - [ ] Add `moveTask` mutation to `boardApi.ts`
  - [ ] Endpoint: `PATCH /board/tasks/:id/move` with `{ column_id, position }`
  - [ ] Response: updated task
- [ ] Task 6: Implement optimistic update (AC: #5, #7)
  - [ ] On drag end: immediately update Redux cache (move task between columns in cached board data)
  - [ ] Fire `moveTask` mutation
  - [ ] On error: rollback Redux cache to previous state, show error toast via notistack
  - [ ] Use RTK Query's `onQueryStarted` with `updateQueryData` for optimistic update
- [ ] Task 7: Implement debounce for rapid moves (AC: #8)
  - [ ] Track last move timestamp per task
  - [ ] If same task moved within 500ms, cancel previous pending request
  - [ ] Use `AbortController` or RTK Query request cancellation
- [ ] Task 8: Position calculation on drop (AC: #6)
  - [ ] When dropping between tasks: calculate position from adjacent task positions
  - [ ] When dropping at end: use max position + 1
  - [ ] When dropping at start: use min position / 2 (fractional) or reindex

## Dev Notes

### Architecture Compliance

- **@dnd-kit** chosen over `react-beautiful-dnd` — actively maintained, supports React 19, Sortable preset for column reorder
- **Optimistic updates** via RTK Query's `onQueryStarted` + `updateQueryData` — follow Redux Toolkit best practices
- **No new global state** — DnD state is ephemeral (managed by @dnd-kit internally)
- **Debounce** prevents double-trigger API calls from drag jitter — aligns with NFR (cooldown mechanism on backend)

### @dnd-kit Setup Pattern

```tsx
import { DndContext, DragOverlay, closestCorners } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';

<DndContext
  collisionDetection={closestCorners}
  onDragStart={handleDragStart}
  onDragOver={handleDragOver}
  onDragEnd={handleDragEnd}
>
  {columns.map(col => (
    <SortableContext
      key={col.id}
      items={col.tasks.map(t => t.id)}
      strategy={verticalListSortingStrategy}
    >
      <BoardColumn column={col} />
    </SortableContext>
  ))}
  <DragOverlay>
    {activeTask ? <TaskCard task={activeTask} isDragging /> : null}
  </DragOverlay>
</DndContext>
```

### Optimistic Update Pattern (RTK Query)

```typescript
moveTask: builder.mutation({
  query: ({ taskId, columnId, position }) => ({
    url: `/board/tasks/${taskId}/move`,
    method: 'PATCH',
    body: decamelizeKeys({ columnId, position }),
  }),
  async onQueryStarted({ taskId, columnId, position, projectId }, { dispatch, queryFulfilled }) {
    const patchResult = dispatch(
      boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
        // Move task between columns in cached data
      })
    );
    try {
      await queryFulfilled;
    } catch {
      patchResult.undo(); // Rollback
    }
  },
}),
```

### Backend API (from Epic 21)

```
PATCH /api/v1/company/projects/:project_id/board/tasks/:id/move
Body: { column_id: number, position?: number }
Response: { data: BoardTask }
```

- Backend handles: row-level lock, position compaction, validation
- Backend returns 404 if column not found (different board)

### Project Structure Notes

- `app/frontend/features/board-management/ui/BoardDndContext.tsx`
- `app/frontend/features/board-management/lib/useBoardDnd.ts` (DnD hook logic)
- `app/frontend/features/board-management/api/boardApi.ts` (modified: add moveTask mutation)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (modified: add sortable)
- `app/frontend/features/board-management/ui/BoardColumn.tsx` (modified: add droppable)
- `package.json` (modified: add @dnd-kit dependencies)

### References

- [Source: ai/epics/epic-22-board-ui-realtime.md#Story 22.2]
- [Source: ai/prd/board-tasks.md#FR14, FR15, FR29]
- [Source: ai/project-context.md#TypeScript/Frontend — Redux Toolkit]
- [Source: app/controllers/api/v1/company/projects/board/tasks_controller.rb#move — backend endpoint]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Installed `@dnd-kit/core`, `@dnd-kit/sortable`, `@dnd-kit/utilities`
- DndContext wraps board with `closestCorners` collision detection
- Each column is a SortableContext with `verticalListSortingStrategy`
- SortableTaskCard wraps TaskCard with `useSortable` hook
- DragOverlay renders ghost card
- Optimistic update via RTK Query `onQueryStarted` + `updateQueryData` with undo on error
- 500ms debounce for rapid moves using `useRef` timestamp tracking
- Position calculation: max(column positions) + 1 on drop

### File List
- `app/frontend/features/board-management/ui/SortableTaskCard.tsx` (new)
- `app/frontend/features/board-management/ui/BoardColumn.tsx` (new — droppable)
- `app/frontend/features/board-management/ui/BoardPanel.tsx` (new — DndContext)
- `app/frontend/features/board-management/api/boardApi.ts` (moveTask mutation with optimistic update)
- `package.json` (modified: @dnd-kit dependencies)
