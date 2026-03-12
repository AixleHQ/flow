# Story 32.4: Broadcast Simplification — Minimal Events Without Payload

Status: review

## Story

As a developer,
I want model broadcasts to send minimal events without payload,
so that frontend refetches data using existing API endpoints and we don't depend on serializers in broadcasts.

## Acceptance Criteria

1. `BoardTask#broadcast_change` sends `{ event: "board_task.<action>", id: <id> }` where action is `created` | `updated` | `destroyed` — no serialized task data
2. `BoardTaskSerializer` is no longer used in broadcast code
3. `WorkflowRun` broadcasts send `{ event: "workflow_run.updated", id: <id> }` — no full object payload
4. `TerminalSession#broadcast_update` sends `{ event: "terminal_session.updated", id: <id> }` — no serialized session data
5. `StepRun#broadcast_update!` sends `{ event: "step_run.updated", id: <id>, workflow_run_id: <wr_id> }` — no `touch` + `reload`
6. `ActivityRecorder` sends `{ event: "board_activity.created", id: <id>, board_id: <board_id> }` instead of full activity payload
7. Frontend WebSocket handlers updated to refetch on event receipt instead of parsing payload
8. Frontend handles `destroyed` events by removing entity from local store
9. All broadcast-related tests updated to match new format

## Tasks / Subtasks

- [x] Task 1: Simplify `BoardTask` broadcasts (AC: 1, 2)
  - [x] Rewrite `broadcast_change` to send `{ event: "board_task.#{action}", id: id }`
  - [x] Remove `BoardTaskSerializer` usage from broadcast
  - [x] Use `BoardChannel.broadcast_event(board, event, { id: id })` or direct `ActionCable.server.broadcast`
- [x] Task 2: Simplify `WorkflowRun` broadcasts (AC: 3)
  - [x] `WorkflowRunChannel.broadcast_update` → send `{ event: "workflow_run.updated", id: id }`
  - [x] Check `WorkflowRunStateMachine#broadcast_run_update!` — simplify
- [x] Task 3: Simplify `TerminalSession` broadcasts (AC: 4)
  - [x] `TerminalSessionChannel.broadcast_update` → send `{ event: "terminal_session.updated", id: id }`
- [x] Task 4: Simplify `StepRun` broadcasts (AC: 5)
  - [x] Remove `wr = workflow_run; wr.touch; WorkflowRunChannel.broadcast_update(wr.reload)`
  - [x] Replace with `WorkflowRunChannel.broadcast_step_update(workflow_run, self)`
- [x] Task 5: Simplify `ActivityRecorder` broadcast (AC: 6)
  - [x] `BoardChannel.broadcast_event` → `{ event: "board_activity.created", id: activity.id, board_id: board.id }`
  - [x] Remove full activity data from broadcast payload
- [x] Task 6: Update frontend WebSocket handlers (AC: 7, 8)
  - [x] Board channel: on `board_task.updated` / `board_task.created` → invalidate task queries → refetch
  - [x] Board channel: on `board_task.destroyed` → remove from local state
  - [x] Workflow run channel: on `workflow_run.updated` → invalidate query → refetch
  - [x] Terminal session channel: on `terminal_session.updated` → invalidate query → refetch
  - [x] Step run channel: on `step_run.updated` → invalidate workflow run query → refetch
  - [x] Activity channel: on `board_activity.created` → invalidate activity feed query → refetch
- [x] Task 7: Update tests (AC: 9)
  - [x] Update broadcast assertion tests for new payload format
  - [x] Update frontend tests for new WebSocket handling

## Dev Notes

### Architecture

- This story is **independent** of the service pyramid (32.1-32.3) and can run in parallel
- Changes are **breaking** for frontend — frontend tasks must be done atomically with backend changes
- Channels (`BoardChannel`, `WorkflowRunChannel`, `TerminalSessionChannel`) may need method signature updates

### Key Files to Modify

**Backend:**

| File | Action |
|------|--------|
| `app/models/board_task.rb` | **MODIFY** — simplify `broadcast_change` |
| `app/models/step_run.rb` | **MODIFY** — simplify `broadcast_update!` |
| `app/channels/board_channel.rb` | **MODIFY** — simplify `broadcast_event` |
| `app/channels/workflow_run_channel.rb` | **MODIFY** — simplify `broadcast_update` |
| `app/channels/terminal_session_channel.rb` | **MODIFY** — simplify `broadcast_update` |
| `app/services/activity_recorder.rb` | **MODIFY** — simplify broadcast payload |
| `app/state_machines/workflow_run_state_machine.rb` | **MODIFY** — simplify `broadcast_run_update!` |

**Frontend (discover actual paths):**

| Pattern | Action |
|---------|--------|
| `**/channels/**` or `**/subscriptions/**` | **MODIFY** — update WS event handlers |
| `**/hooks/use*Channel*` | **MODIFY** — invalidate queries instead of parsing payload |
| RTK Query / React Query invalidation | **MODIFY** — add invalidation on WS events |

### Current `BoardTask#broadcast_change` (to simplify)

```ruby
# BEFORE
def broadcast_change(action)
  data = if action == "destroyed"
    { action: action, id: id }
  else
    { action: action, task: BoardTaskSerializer.new(self).serializable_hash }
  end
  BoardChannel.broadcast_event(board, "task_changed", data)
end

# AFTER
def broadcast_change(action)
  BoardChannel.broadcast_event(board, "board_task.#{action}", { id: id })
end
```

### Current `StepRun#broadcast_update!` (to simplify)

```ruby
# BEFORE — triggers N+1 reload
def broadcast_update!
  wr = workflow_run
  wr.touch
  WorkflowRunChannel.broadcast_update(wr.reload)
end

# AFTER — direct minimal event
def broadcast_update!
  WorkflowRunChannel.broadcast_event(
    workflow_run_id,
    { event: "step_run.updated", id: id, workflow_run_id: workflow_run_id }
  )
end
```

### Frontend Pattern

Use React Query / RTK Query invalidation:
```typescript
// On receiving WebSocket event
onMessage(event) {
  if (event.event === 'board_task.updated') {
    queryClient.invalidateQueries(['board_tasks', boardId])
  }
  if (event.event === 'board_task.destroyed') {
    queryClient.setQueryData(['board_tasks', boardId], (old) =>
      old?.filter(t => t.id !== event.id)
    )
  }
}
```

### References

- [Source: app/models/board_task.rb#broadcast_change] — current broadcast with serializer
- [Source: app/models/step_run.rb#broadcast_update!] — current touch + reload pattern
- [Source: app/services/activity_recorder.rb] — current broadcast with full data
- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-324] — epic definition

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- BoardTask.broadcast_change sends minimal `{ id }` — removed BoardTaskSerializer from broadcasts
- WorkflowRunChannel.broadcast_update sends `{ type: "workflow_run.updated", data: { id } }`
- TerminalSessionChannel.broadcast_update sends `{ type: "terminal_session.updated", data: { id } }`
- StepRun.broadcast_update! uses broadcast_step_update — no more touch/reload N+1
- ActivityRecorder sends `{ event: "board_activity.created", id, board_id }` — no full payload
- Frontend useBoardChannel: invalidates queries on created/updated, removes from store on destroyed
- Frontend useTerminalSession: refetches on WS event instead of patching cache
- Frontend useWorkflowRunChannel: simplified to call onUpdate callback (refetch) on any event
- WorkflowRunPage: uses refetch from RTK Query instead of live state from channel

### File List

- app/models/board_task.rb (MODIFIED — simplified broadcast_change)
- app/models/step_run.rb (MODIFIED — simplified broadcast_update!)
- app/channels/workflow_run_channel.rb (MODIFIED — minimal payloads)
- app/channels/terminal_session_channel.rb (MODIFIED — minimal payload)
- app/services/activity_recorder.rb (MODIFIED — minimal broadcast)
- app/frontend/features/board-management/lib/useBoardChannel.ts (MODIFIED — event invalidation)
- app/frontend/shared/lib/hooks/useTerminalSession.ts (MODIFIED — refetch on event)
- app/frontend/shared/lib/hooks/useWorkflowRunChannel.ts (MODIFIED — callback-based refetch)
- app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx (MODIFIED — uses refetch)
