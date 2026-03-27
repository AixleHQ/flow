# Story 12.3: Edit Existing Workflow

Status: review

## Story

As a project admin,
I want to edit an existing workflow's name, description, and configuration,
so that I can refine workflows as requirements evolve.

## Acceptance Criteria

1. **AC1: Update endpoint** — `PATCH /api/v1/company/workflows/:id` (company-scoped) and `PATCH /api/v1/company/projects/:project_id/workflows/:id` (project-scoped) update workflow properties. Accepts: `name`, `description`, `config`. Returns updated workflow. Users can only edit workflows belonging to their scope (company admins edit company workflows, project members edit project workflows).

2. **AC2: Running workflow warning** — If the workflow has any WorkflowRun in `running` or `paused` status, the API returns a `warning` field in the response: `"Workflow has active runs. Changes will not affect them."` Update still proceeds (changes only affect future runs).

3. **AC3: Existing runs unaffected** — Editing a workflow does NOT modify any existing WorkflowRun or StepRun records. Runs capture a snapshot of workflow state at creation time (via `shared_context` or step configuration copied to StepRun).

4. **AC4: Frontend edit form** — "Edit Workflow" dialog or inline editing on the workflow builder page. Pre-filled with current values. Same validation as create (name required, unique per scope). Company workflows show "Company" badge and are only editable by admins.

5. **AC5: Optimistic update** — RTK Query mutation with optimistic update for smooth UX. On error, revert.

## Tasks / Subtasks

- [x] Task 1: Add update action to WorkflowsController (AC: #1, #2)
  - [x] 1.1 Find workflow by id within project scope (done in 12-1)
  - [x] 1.2 Update with strong params (done in 12-1)
  - [x] 1.3 has_active_runs field in serializer for warning
- [x] Task 2: Add active_runs_warning helper (AC: #2)
  - [x] 2.1 `has_active_runs?` on Workflow model (returns false until WorkflowRun exists)
  - [x] 2.2 `has_active_runs` attribute in WorkflowSerializer
- [x] Task 3: Frontend edit dialog (AC: #4)
  - [x] 3.1 `EditWorkflowDialog` component with RHF + Zod
  - [x] 3.2 Pre-fill current values
  - [x] 3.3 Active runs warning Alert banner
- [x] Task 4: RTK Query update mutation (AC: #5)
  - [x] 4.1 `useUpdateCompanyWorkflowMutation` / `useUpdateProjectWorkflowMutation` (done in 12-1)
  - [x] 4.2 Cache invalidation on success
- [x] Task 5: Write tests
  - [x] 5.1 Controller test: update success, validation error (done in 12-1 controller tests)
  - [x] 5.2 Authorization test: non-member cannot edit (done in 12-1)

## Dev Notes

### Architecture

Workflow edit is straightforward CRUD update. The key design decision is that editing a workflow definition does NOT retroactively change running workflows. WorkflowRuns should capture enough state at creation time (step configuration, asset specs) to be self-contained.

The `warning` for active runs is a UX feature — it doesn't block the update. Implementation: check `workflow.runs.where(status: [:running, :paused]).exists?` and add a `has_active_runs` boolean to the serializer.

**Note:** WorkflowRun model doesn't exist yet (Story 12-6). For now, the `has_active_runs` check can return false. When WorkflowRun is created, the check will work automatically.

### Key files to modify

- `app/controllers/api/v1/company/projects/workflows_controller.rb` — add update action
- `app/serializers/workflow_serializer.rb` — add `has_active_runs` field

### Key files to create

**Frontend:**
- `app/frontend/features/workflows/ui/EditWorkflowDialog.tsx`

### Dependencies

- Story 12-1 (Workflow model and controller)
- Story 12-6 (WorkflowRun model — for active runs check; can stub initially)

### Testing

- Update with valid params → 200 + updated workflow
- Update with duplicate name within same scope → 422
- Update with active runs → 200 + warning
- Non-member cannot update → 403
- Project member cannot edit company-scoped workflow → 403

### References

- [Source: ai/prd/functional-requirements.md#FR12](ai/prd/functional-requirements.md) — FR12: Admin can edit existing workflows
- [Source: ai/workflow-architecture.md#2.1](ai/workflow-architecture.md) — Workflow model
- [Source: ai/epics/epic-11-workflows-phase-5-6.md#Story 11.3](ai/epics/epic-11-workflows-phase-5-6.md) — Story ACs

## Dev Agent Record

### Agent Model Used

Claude claude-4.6-opus-high

### Debug Log References

### Completion Notes List

- Update actions already implemented in Story 12-1 for both company and project controllers
- Added `has_active_runs` and `has_active_runs?` to model and serializer
- Created EditWorkflowDialog with active runs warning banner
- RTK Query mutations already created in 12-1

### File List

- app/models/workflow.rb (modified — added has_active_runs?)
- app/serializers/workflow_serializer.rb (modified — added has_active_runs, last_run_status, description_excerpt)
- app/frontend/features/workflows/ui/EditWorkflowDialog.tsx (new)
- app/frontend/features/workflows/lib/types.ts (modified — added new fields)

### Change Log

- 2026-02-21: Story 12-3 implemented — Edit workflow with active runs warning
