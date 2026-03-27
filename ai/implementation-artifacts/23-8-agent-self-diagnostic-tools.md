# Story 23.8: Agent Self-Diagnostic Tools (2 tools)

Status: ready-for-dev

## Story

As an agent in a workflow session,
I want to signal when I'm stuck or need human help,
so that the system can handle failures gracefully.

## Acceptance Criteria

1. **`board_fail_session`**: params `reason` (required string). Terminates workflow session, sets workflow_run state to `failed`, adds system comment on task with tag `system`, broadcasts `workflow_failed` event
2. **`board_request_human_help`**: params `question` (required string). Pauses workflow session, sets workflow_run state to `paused`, adds system comment on task with tag `human_help`, broadcasts `human_help_requested` event
3. Both tools: `author_type: :system` on comments, `author_id: workflow_run.user_id`
4. Both tools interact with Temporal workflow execution — signal the workflow to handle state change
5. Unit tests for both tools
6. Frontend: `human_help_requested` event shows notification on task card (extend useBoardChannel)

## Tasks / Subtasks

- [ ] Task 1: Create `InternalTools::BoardFailSession`
- [ ] Task 2: Create `InternalTools::BoardRequestHumanHelp`
- [ ] Task 3: Implement Temporal signaling for session termination/pause
- [ ] Task 4: Add system comment creation to both tools
- [ ] Task 5: Add ActionCable broadcasts for new event types
- [ ] Task 6: Update frontend `useBoardChannel` to handle `workflow_failed` and `human_help_requested`
- [ ] Task 7: Write unit tests for both tools

## Dev Notes

### Architecture Compliance

- **Temporal interaction**: Both tools need to signal the running workflow to change state
- **System comments**: `author_type: :system` distinguishes from agent and human comments
- **Append-only comments**: consistent with existing immutable comment pattern

### Temporal Signaling Pattern

Existing pattern from `TerminalSession#signal_workflow_execution_finished`:
```ruby
execution_workflow_id = "workflow-execution-#{sr.workflow_run_id}"
TemporalService.send_signal(execution_workflow_id, :container_finished, sr.id)
```

For `fail_session`:
```ruby
def execute
  require_workflow_context!
  board = BoardContextResolver.resolve(session)
  task = board_task_from_context

  # Add system comment
  task.task_comments.create!(
    body: "Agent terminated session: #{params[:reason]}",
    author: workflow_run.user,
    author_type: :system,
    tags: ["system"]
  )

  # Signal workflow to fail
  workflow_run.fail!

  broadcast_event(board, "workflow_failed", { task_id: task.id, run_id: workflow_run.id, reason: params[:reason] })
  success("Session terminated: #{params[:reason]}")
end
```

For `request_human_help`:
```ruby
def execute
  require_workflow_context!
  board = BoardContextResolver.resolve(session)
  task = board_task_from_context

  task.task_comments.create!(
    body: "Agent requests help: #{params[:question]}",
    author: workflow_run.user,
    author_type: :system,
    tags: ["human_help"]
  )

  workflow_run.pause!

  broadcast_event(board, "human_help_requested", { task_id: task.id, run_id: workflow_run.id, question: params[:question] })
  success("Help requested. Session paused.")
end
```

### board_task_from_context Helper

```ruby
def board_task_from_context
  workflow_run&.board_task || error("No board task associated with this workflow run")
end
```

### WorkflowRun State Transitions

From existing state machine:
- `fail!` transitions from `[:running, :paused]` to `:failed`
- `pause!` transitions from `:running` to `:paused`
- Both transitions are valid for the diagnostic tools use case

### Frontend Event Handling

Add to `useBoardChannel`:
```typescript
case 'workflow_failed':
  // Clear activeWorkflowRun, same as workflow_completed
  // Optionally show error notification
  break;

case 'human_help_requested':
  // Could add a special indicator on the task card
  // For now, treat similarly to workflow status update
  break;
```

### Complexity Note

These are the most complex tools because they interact with Temporal workflow execution state. The key question is: does `workflow_run.fail!` / `workflow_run.pause!` (aasm transitions) automatically signal Temporal? If not, explicit `TemporalService.send_signal` may be needed. Check existing `WorkflowRunStateMachine` callbacks.

Looking at `on_completed` callback in state machine — it calls `broadcast_run_update!` but doesn't signal Temporal. The signal comes from `TerminalSession#signal_workflow_execution_finished` after session ends. So `fail_session` tool may need to both update the WorkflowRun state AND signal Temporal.

### Dependency

- Requires Story 23.6 (BoardContextResolver)
- Requires understanding of Temporal signaling pattern from existing codebase

### Project Structure Notes

- `app/services/internal_tools/board_fail_session.rb` (new)
- `app/services/internal_tools/board_request_human_help.rb` (new)
- `app/frontend/features/board-management/lib/useBoardChannel.ts` (modified: new event types)
- `test/services/internal_tools/board_fail_session_test.rb` (new)
- `test/services/internal_tools/board_request_human_help_test.rb` (new)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.8]
- [Source: ai/prd/board-tasks.md#FR43, FR44]
- [Source: app/state_machines/workflow_run_state_machine.rb — aasm transitions]
- [Source: app/models/terminal_session.rb#signal_workflow_execution_finished — Temporal signal pattern]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
