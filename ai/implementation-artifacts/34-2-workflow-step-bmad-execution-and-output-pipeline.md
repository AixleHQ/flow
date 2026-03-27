# Story 34.2: Workflow Step BMAD Execution & Output Pipeline

Status: ready-for-dev

## Story

As a **workflow user**,
I want BMAD to be automatically installed when a workflow step with BMAD enabled executes,
so that BMAD methodology is available during that step and outputs are passed to subsequent steps.

## Acceptance Criteria

1. **Given** a workflow step with `bmad_enabled: true` starts execution
   **When** `SessionConfigResolver.new(session).resolve_bmad_enabled` is called
   **Then** it returns `true` (reading from `step.bmad_enabled`)

2. **Given** a BMAD-enabled step produces output files in `/workspace/outputs/`
   **When** the step completes
   **Then** BMAD artifacts are collected as `WorkflowRunAsset` records
   **And** they are available to subsequent steps in `/workspace/input/`

3. **Given** a BMAD-enabled step produces a PRD document at `/workspace/outputs/prd.md`
   **When** the next step starts
   **Then** the PRD is accessible at `/workspace/input/prd.md` via the standard WorkflowRunAsset pipeline

4. **Given** a non-BMAD step follows a BMAD-enabled step
   **When** the non-BMAD step starts
   **Then** BMAD outputs from the previous step are still available in `/workspace/input/`

## Tasks / Subtasks

- [ ] Task 1: Verify SessionConfigResolver workflow path works (AC: #1)
  - [ ] Write test: create workflow step session with `step.bmad_enabled = true`
  - [ ] Assert `SessionConfigResolver.new(session).resolve_bmad_enabled` returns `true`
  - [ ] Write test: step with `bmad_enabled = false` → returns `false`
- [ ] Task 2: Verify output collection pipeline (AC: #2, #3)
  - [ ] Write integration test: BMAD-enabled step produces files in `/workspace/outputs/`
  - [ ] Assert `WorkflowRunAsset` records created via `collect_workflow_outputs`
  - [ ] Assert files have correct `produced_by_step_run` association
- [ ] Task 3: Verify asset passing to subsequent steps (AC: #3, #4)
  - [ ] Write test: next step's `WorkflowStepStrategy#inject_workflow_assets` includes BMAD outputs
  - [ ] Verify files mounted at `/workspace/input/` in next step container

## Dev Notes

- **This is primarily a validation/testing story.** The code paths already exist:
  - `SessionConfigResolver#resolve_bmad_enabled` (Story 33.5) already handles `step.bmad_enabled`
  - `BmadMethodInjector` (Story 33.2) runs via `assemble_session_context` (Story 33.6)
  - `WorkflowStepStrategy#collect_workflow_outputs` (lines 73–127) collects everything from `/workspace/outputs/`
  - `WorkflowStepStrategy#inject_workflow_assets` mounts previous step assets to `/workspace/input/`
- **No new code expected** — this story validates the E2E flow works correctly when BMAD is configured on a step
- **Output collection path:** `WorkflowStepStrategy#before_cleanup` → `collect_workflow_outputs` → `find /workspace/outputs -type f` → creates `WorkflowRunAsset` per file → S3 upload

### Key Code Paths

1. **Step starts** → `assemble_session_context` → `resolve_bmad_enabled` reads `step.bmad_enabled` → `BmadMethodInjector#inject!`
2. **Agent works** → BMAD slash-commands produce files in `/workspace/outputs/`
3. **Step completes** → `WorkflowStepStrategy#before_cleanup` → `collect_workflow_outputs` → `WorkflowRunAsset` records
4. **Next step starts** → `WorkflowStepStrategy#inject_workflow_assets` → mounts all previous `WorkflowRunAsset`s to `/workspace/input/`

### Project Structure Notes

- No new files — integration/system tests only
- Test files: `test/services/session_config_resolver_test.rb`, `test/services/container_strategies/workflow_step_strategy_test.rb`

### References

- [Source: app/services/session_config_resolver.rb#L58-70] — session type detection + resolve_bmad_enabled
- [Source: app/services/container_strategies/workflow_step_strategy.rb#L73-127] — collect_workflow_outputs
- [Source: app/services/container_strategies/workflow_step_strategy.rb#L145-190] — inject_workflow_assets
- [Source: ai/epics/epic-34-bmad-workflow-step.md#Story-34.2] — story spec

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
