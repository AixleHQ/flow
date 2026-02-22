# Story 12.6: Start Workflow Execution

Status: done

## Story

As a project member,
I want to start a workflow execution by selecting input assets and execution mode,
so that the workflow begins processing steps with the right context.

## Acceptance Criteria

1. **AC1: WorkflowRun model** — `WorkflowRun` model with fields: `workflow_id` (FK, required), `project_id` (FK, required — execution is always project-scoped even for company workflows), `user_id` (FK, required), `status` (enumerize: pending/running/paused/completed/failed/cancelled, default: pending), `mode` (enumerize: interactive/non_interactive/mixed, default: interactive), `input_asset_ids` (jsonb — project Assets selected by user), `shared_context` (jsonb — accumulated context from step notes), `started_at` (datetime), `completed_at` (datetime). Has many step_runs, has many workflow_run_assets. **Note:** Workflow has polymorphic scope (Company|Project) but WorkflowRun always belongs_to :project — executing a company workflow in a project creates a project-scoped run.

2. **AC2: StepRun model** — `StepRun` model with fields: `workflow_run_id` (FK, required), `step_id` (FK, required), `terminal_session_id` (FK, optional), `status` (enumerize: pending/running/waiting_input/completed/failed/skipped), `step_note` (text — written by agent via tool), `skip_reason` (string), `started_at` (datetime), `completed_at` (datetime), `error_message` (text). Has many sub_step_runs, has many produced_workflow_run_assets.

3. **AC3: SubStepRun model** — `SubStepRun` model with fields: `step_run_id` (FK, required), `sub_step_id` (FK, required), `status` (enumerize: pending/in_progress/completed/skipped), `note` (text), `data` (jsonb — structured decisions/findings), `started_at` (datetime), `completed_at` (datetime).

4. **AC4: WorkflowRunAsset model** — `WorkflowRunAsset` model with fields: `workflow_run_id` (FK, required), `produced_by_step_run_id` (FK, optional), `name` (string), `s3_key` (string), `content_type` (string), `file_size` (integer).

5. **AC5: Migrations** — Create 4 tables: `workflow_runs`, `step_runs`, `sub_step_runs`, `workflow_run_assets` with all columns, indexes, and foreign keys.

6. **AC6: Start execution endpoint** — `POST /api/v1/company/projects/:project_id/workflow_runs` creates WorkflowRun. Params: `workflow_id` (from merged scope — can be company or project workflow), `mode` (interactive/non_interactive/mixed), `input_asset_ids` (array of project asset IDs). Validates: workflow accessible via `merged_for_project`, mode against workflow capabilities. Creates WorkflowRun (pending, project-scoped) → creates first StepRun (pending) → starts Temporal workflow.

7. **AC7: Non-interactive mode validation** — If `mode: non_interactive` is selected, verify ALL steps have `allow_non_interactive: true`. If not, return 422: "Cannot run non-interactive: steps {names} require user interaction."

8. **AC8: Temporal workflow** — `Workflows::WorkflowExecutionWorkflow` orchestrates the full workflow execution. Input: `{ workflow_run_id: }`. Manages step transitions, signal handling for interactive steps, failure policies.

9. **AC9: WorkflowRun serializer** — `WorkflowRunSerializer` with: id, workflow_id, status, mode, started_at, completed_at, step_runs (nested with status), current_step info.

10. **AC10: Start workflow UI** — "Run Workflow" button on workflow page. Opens dialog: select mode (radio buttons with descriptions), select input assets (multi-select from project assets), optional initial config. On confirm, creates run and redirects to workflow run detail page.

11. **AC11: WorkflowRun state machine** — AASM state machine for WorkflowRun: `pending → running → completed/failed/cancelled`, with `paused` state for interactive waits. Events: `start!`, `pause!`, `resume!`, `complete!`, `fail!`, `cancel!`.

## Tasks / Subtasks

- [ ] Task 1: Create migrations (AC: #5)
  - [ ] 1.1 `create_workflow_runs` migration
  - [ ] 1.2 `create_step_runs` migration
  - [ ] 1.3 `create_sub_step_runs` migration
  - [ ] 1.4 `create_workflow_run_assets` migration
  - [ ] 1.5 Run all, verify schema
- [ ] Task 2: Create `WorkflowRun` model (AC: #1, #11)
  - [ ] 2.1 Associations: belongs_to workflow, project, user; has_many step_runs, workflow_run_assets
  - [ ] 2.2 Enumerize: status, mode
  - [ ] 2.3 AASM state machine (or just enumerize state column)
  - [ ] 2.4 `can_run_non_interactive?` delegation to workflow
- [ ] Task 3: Create `StepRun` model (AC: #2)
  - [ ] 3.1 Associations: belongs_to workflow_run, step, terminal_session (optional); has_many sub_step_runs
  - [ ] 3.2 Enumerize: status
  - [ ] 3.3 Auto-create SubStepRuns when StepRun transitions to running
- [ ] Task 4: Create `SubStepRun` model (AC: #3)
  - [ ] 4.1 Associations: belongs_to step_run, sub_step
  - [ ] 4.2 Enumerize: status
- [ ] Task 5: Create `WorkflowRunAsset` model (AC: #4)
  - [ ] 5.1 Associations: belongs_to workflow_run, produced_by_step_run (optional)
- [ ] Task 6: Create serializers (AC: #9)
  - [ ] 6.1 `WorkflowRunSerializer` with nested step_runs
  - [ ] 6.2 `StepRunSerializer` with nested sub_step_runs
  - [ ] 6.3 `SubStepRunSerializer`
  - [ ] 6.4 `WorkflowRunAssetSerializer`
- [ ] Task 7: Create `WorkflowRunsController` (AC: #6, #7)
  - [ ] 7.1 `Api::V1::Company::Projects::Workflows::RunsController`
  - [ ] 7.2 Actions: create, show, index
  - [ ] 7.3 Mode validation logic
  - [ ] 7.4 Start Temporal workflow on create
- [ ] Task 8: Create `Workflows::WorkflowExecutionWorkflow` (AC: #8)
  - [ ] 8.1 Temporal workflow with workflow_run_id input
  - [ ] 8.2 Step iteration logic (process steps in order)
  - [ ] 8.3 Signal handling for interactive step completion
  - [ ] 8.4 Error handling per step (retry/skip/fail per on_failure policy)
- [ ] Task 9: Create Temporal activities
  - [ ] 9.1 `PrepareStepActivity` — prepare workspace, mount assets, create terminal session
  - [ ] 9.2 `CompleteStepActivity` — collect outputs, create WorkflowRunAssets
  - [ ] 9.3 `UpdateWorkflowRunStatusActivity` — status transitions
- [ ] Task 10: Pundit policies for WorkflowRuns
- [ ] Task 11: Routes for workflow runs
- [ ] Task 12: Frontend "Run Workflow" dialog (AC: #10)
  - [ ] 12.1 Mode selection radio group
  - [ ] 12.2 Asset multi-select (from project assets)
  - [ ] 12.3 Validation and submit
- [ ] Task 13: Frontend WorkflowRunPage (basic) 
  - [ ] 13.1 Show workflow run status, step progress
  - [ ] 13.2 Link to existing UI stub at `pages/workflow-run/`
- [ ] Task 14: RTK Query API for workflow runs
- [ ] Task 15: Factories and tests
  - [ ] 15.1 Factories for all 4 new models
  - [ ] 15.2 Model tests: validations, associations, state transitions
  - [ ] 15.3 Controller tests: create, show, mode validation
  - [ ] 15.4 Temporal workflow test (mock activities)

## Dev Notes

### Architecture

This is the CORE story of the epic — it introduces 4 new models and the Temporal workflow that drives execution. The workflow follows the same pattern as `ContainerWorkflow` but orchestrates multiple sequential steps.

**Temporal workflow design:**
```
WorkflowExecutionWorkflow(workflow_run_id:)
  → for each step in order:
    → PrepareStepActivity(step_run_id:)
    → Start terminal session (delegates to ContainerWorkflow)
    → if interactive: wait for "step_completed" signal (23h timeout)
    → if non-interactive: wait for container completion
    → CompleteStepActivity(step_run_id:)
    → if failed: apply on_failure policy (retry/skip/fail)
  → UpdateWorkflowRunStatusActivity(workflow_run_id:, status: "completed")
```

**Key insight:** Each step creates a TerminalSession (session_type: `workflow_step`). The terminal session lifecycle is managed by the existing `ContainerWorkflow`. The `WorkflowExecutionWorkflow` coordinates between steps.

**Polymorphic scope note:** Workflow has polymorphic scope (Company|Project) but WorkflowRun always `belongs_to :project`. When running a company workflow in a project, the WorkflowRun references both the company workflow and the project. This means company workflow run history is tracked per-project.

**State machine for WorkflowRun:** Use AASM (consistent with TerminalSession pattern). Column name: `status` (not `state` — to avoid conflict and because the workflow-architecture.md uses `status`). Actually, per project convention, use `state` column with AASM. **Decision needed:** The workflow-architecture.md uses `status` but AASM convention uses `state`. Recommend: use `state` with AASM for consistency with TerminalSession.

### Key files to create

**Backend:**
- `db/migrate/YYYYMMDDHHMMSS_create_workflow_runs.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_step_runs.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_sub_step_runs.rb`
- `db/migrate/YYYYMMDDHHMMSS_create_workflow_run_assets.rb`
- `app/models/workflow_run.rb`
- `app/models/step_run.rb`
- `app/models/sub_step_run.rb`
- `app/models/workflow_run_asset.rb`
- `app/state_machines/workflow_run_state_machine.rb`
- `app/serializers/workflow_run_serializer.rb`
- `app/serializers/step_run_serializer.rb`
- `app/serializers/sub_step_run_serializer.rb`
- `app/serializers/workflow_run_asset_serializer.rb`
- `app/controllers/api/v1/company/projects/workflows/runs_controller.rb`
- `app/policies/api/v1/company/projects/workflows/runs_policy.rb`
- `app/temporal/workflows/workflow_execution_workflow.rb`
- `app/temporal/activities/workflow/prepare_step_activity.rb`
- `app/temporal/activities/workflow/complete_step_activity.rb`
- `app/temporal/activities/workflow/update_workflow_run_status_activity.rb`
- `test/factories/workflow_runs.rb`
- `test/factories/step_runs.rb`
- `test/factories/sub_step_runs.rb`
- `test/factories/workflow_run_assets.rb`

**Frontend:**
- `app/frontend/features/workflows/ui/RunWorkflowDialog.tsx`
- `app/frontend/features/workflows/ui/AssetSelector.tsx`
- Update `app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx`

### Key files to modify

- `app/models/workflow.rb` — add `has_many :runs, class_name: 'WorkflowRun'` (runs via workflow_id, not scope)
- `app/models/terminal_session.rb` — add `has_one :step_run`
- `config/routes.rb` — add workflow runs routes
- `app/services/workflow_service.rb` — register new Temporal workflow
- `app/temporal/workflows.yml` — add workflow_execution_workflow

### Important constraints

- `enumerize` for all enum fields (NOT ActiveRecord::Enum)
- AASM for state machine
- Column name for AASM: recommend `state` (project convention) even though architecture doc says `status`
- Temporal workflow must be registered in `workflows.yml`
- Terminal sessions with `session_type: :workflow_step` already supported

### Dependencies

- Story 12-1 (Workflow model)
- Story 12-2 (Step, SubStep models)
- Epic 10 done (TerminalSession, ContainerWorkflow)
- Epic 11 done (Asset model for input selection)

### Testing

- WorkflowRun: state transitions (pending→running→completed), mode validation
- StepRun: auto-creation of SubStepRuns
- Controller: create with valid mode, invalid mode rejection, asset selection
- Temporal workflow: mock activities, verify step ordering, signal handling

### References

- [Source: ai/workflow-architecture.md#2.4](ai/workflow-architecture.md) — WorkflowRun data model
- [Source: ai/workflow-architecture.md#2.5](ai/workflow-architecture.md) — StepRun data model
- [Source: ai/workflow-architecture.md#2.6](ai/workflow-architecture.md) — SubStepRun data model
- [Source: ai/workflow-architecture.md#2.7](ai/workflow-architecture.md) — WorkflowRunAsset data model
- [Source: ai/workflow-architecture.md#4.1](ai/workflow-architecture.md) — Start Workflow flow
- [Source: ai/prd/functional-requirements.md#FR15](ai/prd/functional-requirements.md) — FR15: Start workflow execution
- [Source: app/temporal/workflows/container_workflow.rb](app/temporal/workflows/container_workflow.rb) — Reference Temporal workflow

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
