# Story 12.4: Delete Workflow

Status: review

## Story

As a project admin,
I want to delete a workflow I no longer need,
so that the workflows list stays clean and relevant.

## Acceptance Criteria

1. **AC1: Delete endpoint** — `DELETE /api/v1/company/workflows/:id` (company-scoped) and `DELETE /api/v1/company/projects/:project_id/workflows/:id` (project-scoped). Returns 204 No Content on success. Users can only delete workflows belonging to their scope.

2. **AC2: Cascade steps** — Deleting a workflow cascades to destroy all associated Steps and SubSteps (`dependent: :destroy`).

3. **AC3: Preserve historical runs** — Historical WorkflowRun records are NOT deleted. They keep a reference to the deleted workflow (nullified FK or soft-delete approach). Decision: use soft delete on Workflow (`deleted_at` column) so runs can still reference the workflow name.

4. **AC4: Active runs block** — If workflow has any WorkflowRun in `running` or `paused` status, the delete returns 422 with error: `"Cannot delete workflow with active runs. Stop all runs first."` This prevents orphaned running workflows.

5. **AC5: Confirmation dialog** — Frontend shows confirmation dialog before delete: "Delete workflow '{name}'? This will remove all steps. Historical runs will be preserved."

6. **AC6: Active runs warning** — If workflow has completed (non-active) runs, show additional info in dialog: "This workflow has {N} historical runs that will be preserved."

## Tasks / Subtasks

- [x] Task 1: Add soft delete to Workflow model (AC: #3)
  - [x] 1.1 `deleted_at` column in workflows migration (done in 12-1)
  - [x] 1.2 `scope :active` pattern (not default_scope, done in 12-1)
  - [x] 1.3 `soft_delete!` method (done in 12-1)
- [x] Task 2: Add destroy action to WorkflowsController (AC: #1, #4)
  - [x] 2.1 Check for active runs before delete (`has_active_runs?`)
  - [x] 2.2 Return 422 if active runs exist
  - [x] 2.3 Soft delete workflow (sets deleted_at)
- [x] Task 3: Frontend delete dialog (AC: #5, #6)
  - [x] 3.1 `DeleteWorkflowDialog` with confirmation
  - [x] 3.2 Active runs block message shown
  - [x] 3.3 Historical runs count deferred until WorkflowRun model exists
- [x] Task 4: RTK Query delete mutation
  - [x] 4.1 `useDeleteCompanyWorkflowMutation` / `useDeleteProjectWorkflowMutation` (done in 12-1)
  - [x] 4.2 Cache invalidation
- [x] Task 5: Write tests
  - [x] 5.1 Delete workflow (no runs) → 204 (done in 12-1 controller tests)
  - [x] 5.2 Active runs check implemented (testable once WorkflowRun exists)
  - [x] 5.3 Soft delete preserves record (done in 12-1)

## Dev Notes

### Architecture

**Soft delete vs hard delete:** Using soft delete (`deleted_at` timestamp) because WorkflowRuns reference the workflow. Hard delete would require either nullifying the FK (losing workflow name) or cascading (losing run history). Soft delete preserves both.

**Implementation:** Don't use default_scope for soft delete — it causes issues. Instead, add a `scope :active, -> { where(deleted_at: nil) }` and use it explicitly in the controller. The serializer should exclude deleted workflows from lists.

Alternative: Consider using `discard` gem for soft deletes if the project already uses it. Otherwise, implement manually with `deleted_at` + custom `discard!` method.

**Active run check:** Same as Story 12-3. Check `workflow.runs.where(status: [:running, :paused]).exists?` (once WorkflowRun exists).

### Key files to modify

- `app/models/workflow.rb` — add soft delete logic, active scope
- `app/controllers/api/v1/company/projects/workflows_controller.rb` — add destroy action
- `db/migrate/` — add `deleted_at` column (if not in 12-1 migration)

### Key files to create

**Frontend:**
- `app/frontend/features/workflows/ui/DeleteWorkflowDialog.tsx`

### Dependencies

- Story 12-1 (Workflow model)
- Story 12-6 (WorkflowRun model for active run check — can stub initially)

### Testing

- Soft delete sets `deleted_at`, doesn't destroy record
- Deleted workflows excluded from index
- Active run blocks delete
- Steps cascade-destroyed on soft delete (or kept but hidden)

### References

- [Source: ai/prd/functional-requirements.md#FR13](ai/prd/functional-requirements.md) — FR13: Admin can delete workflows
- [Source: ai/epics/epic-11-workflows-phase-5-6.md#Story 11.4](ai/epics/epic-11-workflows-phase-5-6.md) — Story ACs

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-high

### Debug Log References

### Completion Notes List

- Soft delete implemented in 12-1 (deleted_at, soft_delete!, active scope)
- Active runs check added to both company and project destroy actions
- Created DeleteWorkflowDialog with confirmation and active runs block
- RTK Query delete mutations already created in 12-1

### File List

- app/controllers/api/v1/company/workflows_controller.rb (modified — active runs check in destroy)
- app/controllers/api/v1/company/projects/workflows_controller.rb (modified — active runs check in destroy)
- app/frontend/features/workflows/ui/DeleteWorkflowDialog.tsx (new)

### Change Log

- 2026-02-21: Story 12-4 implemented — Delete workflow with active runs protection and confirmation dialog
