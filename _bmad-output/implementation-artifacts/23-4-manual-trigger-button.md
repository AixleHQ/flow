# Story 23.4: Manual Trigger Button

Status: ready-for-dev

## Story

As a user,
I want to manually start a bound workflow for a task,
so that I control when the workflow runs on manual-trigger columns.

## Acceptance Criteria

1. New API endpoint: `POST /board/tasks/:task_id/trigger_workflow`
2. Endpoint validates: column has `manual` binding, no active workflow run for this task
3. Endpoint starts workflow (same logic as auto-trigger from 23.3), returns workflow_run
4. Returns 422 if no manual binding on task's column, or if active workflow run already exists
5. Frontend: TaskCard shows "Start Workflow" button when column has `trigger_mode: :manual` and no active workflow run
6. Frontend: TaskSidebar header shows "Start Workflow" button with same conditions
7. Button disabled while workflow is running (indicator shown instead)
8. Controller test: trigger happy path, no binding, already running errors
9. Frontend: update `BoardColumn` type to include `workflowBinding` from serializer

## Tasks / Subtasks

- [ ] Task 1: Add `trigger_workflow` action to `TasksController`
- [ ] Task 2: Add route: `member { post :trigger_workflow }` on tasks
- [ ] Task 3: Implement trigger logic (reuse `TaskMoveService` trigger or extract shared method)
- [ ] Task 4: Write controller tests for trigger endpoint
- [ ] Task 5: Update frontend `BoardColumn` type with `workflowBinding`
- [ ] Task 6: Update `TaskCard` to show "Start Workflow" button conditionally
- [ ] Task 7: Update `TaskSidebar` header to show "Start Workflow" button
- [ ] Task 8: Add RTK Query mutation for `triggerWorkflow`

## Dev Notes

### Architecture Compliance

- **Reuses workflow trigger logic** from `TaskMoveService` — extract into shared method or call `TaskMoveService.trigger_for_task`
- **No cooldown for manual trigger** — cooldown only applies to auto-trigger from drag-and-drop
- **Pundit authorization**: project accessible (same as task CRUD)

### API Contract

```
POST /api/v1/company/projects/:project_id/board/tasks/:task_id/trigger_workflow
Response: { data: { id, state, workflow_id, board_task_id, ... } }
Error 422: { errors: ["No manual workflow binding on current column"] }
Error 422: { errors: ["Active workflow run already exists for this task"] }
```

### Controller Implementation

```ruby
def trigger_workflow
  task = current_board.board_tasks.find(params[:id])
  binding = task.board_column.column_workflow_binding

  unless binding&.trigger_mode&.to_sym == :manual
    return head :unprocessable_entity
  end

  if task.workflow_runs.where(state: %w[pending running paused]).exists?
    return head :unprocessable_entity
  end

  run = WorkflowRun.create!(
    workflow: binding.workflow,
    project: current_project,
    user: current_user,
    board_task_id: task.id,
    mode: :non_interactive
  )

  # Start via Temporal (same as auto-trigger)
  TemporalService.start_workflow(...)

  broadcast(:workflow_started, { task_id: task.id, run_id: run.id })
  respond_with run, serializer: WorkflowRunSerializer
end
```

### Frontend Button Visibility Logic

```tsx
const canTriggerWorkflow = column.workflowBinding?.triggerMode === 'manual'
  && !task.activeWorkflowRun;

{canTriggerWorkflow && (
  <Button size="small" onClick={() => triggerWorkflow({ projectId, taskId: task.id })}>
    Start Workflow
  </Button>
)}
```

### Dependency

- Requires Story 23.1 (ColumnWorkflowBinding) for binding data
- Requires Story 23.3 (TaskMoveService) for shared trigger logic

### Project Structure Notes

- `app/controllers/api/v1/company/projects/board/tasks_controller.rb` (modified: trigger_workflow action)
- `config/routes.rb` (modified: add trigger_workflow member route)
- `test/controllers/api/v1/company/projects/board/tasks_controller_test.rb` (modified)
- `app/frontend/features/board-management/api/boardApi.ts` (modified: triggerWorkflow mutation)
- `app/frontend/entities/board-task/model/types.ts` (modified: BoardColumn.workflowBinding)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (modified: trigger button)
- `app/frontend/features/board-management/ui/TaskSidebar.tsx` (modified: trigger button)

### References

- [Source: ai/epics/epic-23-workflow-triggers-mcp-tools.md#Story 23.4]
- [Source: ai/prd/board-tasks.md#FR11]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
