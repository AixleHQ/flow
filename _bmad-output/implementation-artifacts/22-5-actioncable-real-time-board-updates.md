# Story 22.5: ActionCable Real-time Board Updates

Status: review

## Story

As a user,
I want my board to update in real-time when others make changes,
so that I always see the current state without refreshing.

## Acceptance Criteria

1. New ActionCable channel: `BoardChannel` subscribed per project board
2. Channel authorization: verify user is project member via `project.accessible_by?(current_user)`
3. Events broadcast:
   - `task_moved` — task changed column (task_id, from_column_id, to_column_id, new_position)
   - `task_created` / `task_updated` / `task_deleted` — full task data
   - `comment_added` — new comment on task (task_id, comment data)
   - `workflow_started` / `workflow_completed` — workflow status change for task
4. Frontend subscribes to `BoardChannel` on board page mount, unsubscribes on unmount
5. Events trigger RTK Query cache updates — board re-renders with new data
6. Delivery target: < 500ms from server event to UI update
7. Broadcast triggered from model callbacks or controller after_actions

## Tasks / Subtasks

- [ ] Task 1: Create BoardChannel (AC: #1, #2)
  - [ ] `app/channels/board_channel.rb`
  - [ ] Subscribe with `board_id` parameter
  - [ ] Verify current_user is project member (via board.project.accessible_by?)
  - [ ] `stream_for` board instance
  - [ ] `refresh` method to re-send current board state
  - [ ] Class method `broadcast_event(board, event_type, data)` for easy broadcasting
- [ ] Task 2: Add broadcast hooks for task operations (AC: #3, #7)
  - [ ] After task create → broadcast `task_created` with serialized task
  - [ ] After task update → broadcast `task_updated` with serialized task
  - [ ] After task destroy → broadcast `task_deleted` with task_id
  - [ ] After task move → broadcast `task_moved` with task_id, from/to column, position
  - [ ] Implementation: `after_commit` callbacks in model OR explicit calls in controller
  - [ ] Prefer controller-level broadcasts (more control, clearer intent)
- [ ] Task 3: Add broadcast hooks for comments (AC: #3)
  - [ ] After comment create → broadcast `comment_added` with task_id and serialized comment
  - [ ] Broadcast to board channel (not task-specific — all board viewers see it)
- [ ] Task 4: Add broadcast hooks for workflow status (AC: #3)
  - [ ] After workflow_run status changes to running → broadcast `workflow_started` with task_id, run_id
  - [ ] After workflow_run completes/fails → broadcast `workflow_completed` with task_id, run_id, status
  - [ ] Only broadcast if `workflow_run.board_task_id` is present
- [ ] Task 5: Create frontend useBoardChannel hook (AC: #4, #5)
  - [ ] `app/frontend/features/board-management/lib/useBoardChannel.ts`
  - [ ] Follow `useWorkflowRunChannel` pattern
  - [ ] Subscribe with `board_id` on mount, unsubscribe on unmount
  - [ ] Handle each event type:
    - `task_moved` → update task's column_id and position in RTK Query cache
    - `task_created` → add task to RTK Query cache
    - `task_updated` → update task in RTK Query cache
    - `task_deleted` → remove task from RTK Query cache
    - `comment_added` → increment comments_count on task, optionally update sidebar
    - `workflow_started` → set activeWorkflowRun on task
    - `workflow_completed` → clear activeWorkflowRun on task
- [ ] Task 6: Integrate useBoardChannel into BoardPage (AC: #4)
  - [ ] Call `useBoardChannel({ boardId })` in `BoardPage` component
  - [ ] Board re-renders automatically when RTK Query cache is updated
- [ ] Task 7: Backend tests (AC: #1, #2, #3)
  - [ ] Channel test: subscription accepted for project member
  - [ ] Channel test: subscription rejected for non-member
  - [ ] Broadcast test: task CRUD events are broadcast correctly
- [ ] Task 8: Skip self-updates (AC: #5)
  - [ ] Include `actor_id` in broadcast payload
  - [ ] Frontend skips cache update if `actorId === currentUserId` (already applied via optimistic update)

## Dev Notes

### Architecture Compliance

- **ActionCable pattern:** Follow existing `TerminalSessionChannel` and `WorkflowRunChannel` patterns
- **Broadcast scope:** Per board (not per task) — all board viewers get all events. Efficient for boards with < 100 tasks.
- **RTK Query integration:** Update cache directly from WebSocket events (no refetch needed)
- **Self-update skip:** Prevent duplicate updates when user's own action triggers broadcast

### Existing ActionCable Patterns

Backend channel pattern (from `TerminalSessionChannel`):
```ruby
class BoardChannel < ApplicationCable::Channel
  def subscribed
    @board = Board.find_by(id: params[:board_id])
    return reject unless @board && can_access?(@board)

    stream_for @board
  end

  def refresh
    return unless @board
    transmit_board_data(@board)
  end

  class << self
    def broadcast_event(board, event_type, data)
      broadcast_to(board, { "type" => event_type, "data" => data })
    end
  end
end
```

Frontend hook pattern (from `useWorkflowRunChannel`):
```typescript
const subscription = consumer.subscriptions.create(
  { channel: 'BoardChannel', board_id: boardId },
  {
    received(message: BoardEvent) {
      handleBoardEvent(message);
    },
  },
);
```

### Broadcasting from Controllers

Prefer explicit broadcasts in controllers over model callbacks:
```ruby
# In TasksController#create
def create
  task = current_board.board_tasks.build(task_params)
  if task.save
    BoardChannel.broadcast_event(current_board, "task_created", BoardTaskSerializer.new(task).as_json)
  end
  respond_with task, serializer: BoardTaskSerializer
end
```

This is cleaner than `after_commit` callbacks because:
- Only broadcasts on successful API calls (not on internal model saves)
- Controller knows the full context (board, user)
- Easier to add `actor_id` to payload

### Event Payload Format

```json
{
  "type": "task_moved",
  "data": {
    "task_id": 123,
    "from_column_id": 1,
    "to_column_id": 2,
    "position": 3,
    "actor_id": 456
  }
}
```

```json
{
  "type": "task_created",
  "data": { /* full serialized BoardTask */ },
  "actor_id": 456
}
```

### Self-Update Skip Pattern

```typescript
received(message: BoardEvent) {
  if (message.actor_id === currentUserId) return;
  // Process event...
}
```

### Project Structure Notes

- `app/channels/board_channel.rb`
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb` (modified: add broadcasts)
- `app/controllers/api/v1/company/projects/board/task/comments_controller.rb` (modified: add broadcast)
- `app/frontend/features/board-management/lib/useBoardChannel.ts`
- `app/frontend/pages/board/ui/BoardPage.tsx` (modified: integrate useBoardChannel)
- `test/channels/board_channel_test.rb`

### References

- [Source: ai/epics/epic-22-board-ui-realtime.md#Story 22.5]
- [Source: ai/prd/board-tasks.md#FR31]
- [Source: ai/project-context.md#ActionCable — TerminalSessionChannel]
- [Source: app/channels/terminal_session_channel.rb — existing channel pattern]
- [Source: app/frontend/shared/lib/hooks/useWorkflowRunChannel.ts — existing frontend hook pattern]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- BoardChannel: subscribes with board_id, verifies project access via `board.project.accessible_by?`
- `stream_for @board` + `refresh` method for on-demand state
- Class method `broadcast_event(board, event_type, data, actor_id:)` for easy broadcasting
- TasksController: broadcasts task_created, task_updated, task_deleted, task_moved after successful operations
- CommentsController: broadcasts comment_added after successful create
- WorkflowRunStateMachine: broadcasts workflow_started/workflow_completed when board_task_id present
- Frontend useBoardChannel hook: subscribes on mount, unsubscribes on unmount
- Handles 7 event types: task_created, task_updated, task_deleted, task_moved, comment_added, workflow_started, workflow_completed
- Updates RTK Query cache directly from WebSocket events
- actor_id included in broadcast payload for self-update skip capability
- 4 channel tests: subscription accepted, rejected (not found), rejected (no access), broadcast

### File List
- `app/channels/board_channel.rb` (new)
- `app/controllers/api/v1/company/projects/board/tasks_controller.rb` (modified: broadcasts)
- `app/controllers/api/v1/company/projects/board/task/comments_controller.rb` (modified: broadcast)
- `app/state_machines/workflow_run_state_machine.rb` (modified: board broadcast)
- `app/frontend/features/board-management/lib/useBoardChannel.ts` (new)
- `app/frontend/features/board-management/lib/useAppDispatch.ts` (new)
- `test/channels/board_channel_test.rb` (new)
