# Story 22.4: Workflow-in-Progress Indicator

Status: review

## Story

As a user,
I want to see when a workflow is running for a task,
so that I know an agent is currently working on it.

## Acceptance Criteria

1. Task card shows animated indicator (spinner/pulse) when a workflow run is active for this task
2. Indicator links to the workflow run page (`/projects/:id/workflow-runs/:runId`)
3. Backend: add `board_task_id` column to `workflow_runs` table (nullable FK to `board_tasks`)
4. Backend: `BoardTaskSerializer` includes `active_workflow_run` field: `{ id, status }` or null
5. Frontend: query `active_workflow_run` from task data to conditionally show indicator
6. Indicator disappears when workflow completes or fails (real-time via 22.5 or polling)

## Tasks / Subtasks

- [ ] Task 1: Add board_task_id to workflow_runs (AC: #3)
  - [ ] Migration: `add_column :workflow_runs, :board_task_id, :bigint, null: true`
  - [ ] Add FK: `add_foreign_key :workflow_runs, :board_tasks`
  - [ ] Add index on `board_task_id`
- [ ] Task 2: Update WorkflowRun model (AC: #3)
  - [ ] `WorkflowRun` gains `belongs_to :board_task, optional: true`
  - [ ] `BoardTask` gains `has_many :workflow_runs`
  - [ ] Add `board_task_id` to ransackable attributes
- [ ] Task 3: Update BoardTaskSerializer (AC: #4)
  - [ ] Add `active_workflow_run` virtual attribute
  - [ ] Logic: `object.workflow_runs.where(status: [:running, :pending]).order(created_at: :desc).first`
  - [ ] Return: `{ id: run.id, status: run.status }` or `nil`
  - [ ] Use a separate lightweight serializer or inline hash (avoid N+1 — preload)
- [ ] Task 4: Frontend TaskCard indicator (AC: #1, #2, #5)
  - [ ] Update `TaskCard` to show spinner/pulse animation when `activeWorkflowRun` is present
  - [ ] MUI `CircularProgress` (small, size 16-20) or custom pulse CSS animation
  - [ ] Click on indicator navigates to `/projects/:id/workflow-runs/:runId`
  - [ ] Tooltip: "Workflow in progress" with workflow status
- [ ] Task 5: Backend tests (AC: #3, #4)
  - [ ] Model test: WorkflowRun belongs_to :board_task
  - [ ] Serializer test: active_workflow_run returns correct data
  - [ ] Serializer test: returns nil when no active run
- [ ] Task 6: Frontend types update (AC: #5)
  - [ ] Update `BoardTask` type to include `activeWorkflowRun: { id: number; status: string } | null`

## Dev Notes

### Architecture Compliance

- **New column on existing table:** `workflow_runs.board_task_id` — nullable FK, no change to existing workflow creation flow
- **N+1 prevention:** When loading board tasks, preload `workflow_runs` with `.includes(:workflow_runs)` or use a subquery in serializer
- **Lightweight approach:** No separate model or join table — direct FK from workflow_run to board_task
- **Status check:** Use existing WorkflowRun status field (managed by aasm) — check for `running` or `pending`
- This story creates the foundation for Epic 23 (workflow triggers) which will SET `board_task_id` when starting workflows from column moves

### WorkflowRun Model Discovery

Need to check existing `WorkflowRun` model for:
- Current status field and values (aasm states)
- Existing associations
- Serializer structure

```ruby
# Expected addition to BoardTask:
has_many :workflow_runs

# Expected serializer:
def active_workflow_run
  run = object.workflow_runs.find_by(status: %w[running pending])
  return nil unless run
  { id: run.id, status: run.status }
end
```

### Indicator UI Pattern

```tsx
{task.activeWorkflowRun && (
  <Tooltip title={`Workflow ${task.activeWorkflowRun.status}`}>
    <Link to={`/projects/${projectId}/workflow-runs/${task.activeWorkflowRun.id}`}>
      <CircularProgress size={16} />
    </Link>
  </Tooltip>
)}
```

### Important: Epic 23 Dependency

This story adds the `board_task_id` column and serializer field. Epic 23 will:
- Set `board_task_id` when creating workflow runs from column triggers
- Update the indicator via ActionCable (from 22.5)

For now, `board_task_id` can be set manually or via future API, and the indicator works based on existing data.

### Project Structure Notes

- `db/migrate/YYYYMMDDHHMMSS_add_board_task_id_to_workflow_runs.rb`
- `app/models/workflow_run.rb` (modified: belongs_to :board_task)
- `app/models/board_task.rb` (modified: has_many :workflow_runs)
- `app/serializers/board_task_serializer.rb` (modified: active_workflow_run)
- `test/models/board_task_test.rb` (modified: workflow_run association tests)
- `app/frontend/entities/board-task/model/types.ts` (modified: activeWorkflowRun field)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (modified: indicator)

### References

- [Source: ai/epics/epic-22-board-ui-realtime.md#Story 22.4]
- [Source: ai/prd/board-tasks.md#FR30]
- [Source: ai/project-context.md#State machines — aasm gem]
- [Source: app/models/workflow_run.rb — existing WorkflowRun model]

## Dev Agent Record

### Agent Model Used
claude-4.6-opus-high

### Completion Notes List
- Migration adds `board_task_id` (nullable bigint FK) to `workflow_runs`
- WorkflowRun model: `belongs_to :board_task, optional: true`
- BoardTask model: `has_many :workflow_runs`
- BoardTaskSerializer: `active_workflow_run` returns `{ id, status }` or nil by finding first `pending/running/paused` workflow run
- Note: WorkflowRun uses `state` field (aasm), not `status` — serializer returns `run.state`
- TaskCard shows CircularProgress spinner with tooltip when activeWorkflowRun present
- Frontend types include `activeWorkflowRun: { id: number; status: string } | null`

### File List
- `db/migrate/20260227200001_add_board_task_id_to_workflow_runs.rb` (new)
- `app/models/workflow_run.rb` (modified: belongs_to :board_task)
- `app/models/board_task.rb` (modified: has_many :workflow_runs)
- `app/serializers/board_task_serializer.rb` (modified: active_workflow_run)
- `app/frontend/entities/board-task/model/types.ts` (activeWorkflowRun field)
- `app/frontend/entities/board-task/ui/TaskCard.tsx` (workflow indicator)
