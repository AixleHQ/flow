# Epic 34: BMAD Method — Workflow Step Integration

> User or admin can enable BMAD for individual workflow steps. When a step executes, BMAD is installed automatically and output is passed as WorkflowRunAsset to subsequent steps, enabling workflows where specific steps use BMAD methodology.

**Phase:** 19 (Depends on: Epic 33, 11, 29)

**FRs covered:** FR2, FR11, FR14

---

## Story 34.1: Migration — bmad_enabled on Steps

As a **workflow builder admin**,
I want a `bmad_enabled` boolean field on the `steps` table,
So that BMAD can be configured per-step independently of the session-level setting.

**Acceptance Criteria:**

**Given** the migration is applied
**When** the `steps` table schema is inspected
**Then** a `bmad_enabled` column exists with type `boolean`, default `false`, not null

**Given** an existing step without BMAD configuration
**When** the migration runs
**Then** all existing steps have `bmad_enabled = false`

**Given** a new step is created with `bmad_enabled: true`
**When** the step record is persisted
**Then** `step.bmad_enabled` returns `true`

**Implementation Notes:**
- Migration: `add_column :steps, :bmad_enabled, :boolean, default: false, null: false`
- Add `bmad_enabled` to Step model's permitted attributes in the API

---

## Story 34.2: Workflow Step BMAD Execution & Output Pipeline

As a **workflow user**,
I want BMAD to be automatically installed when a workflow step with BMAD enabled executes,
So that BMAD methodology is available during that step and outputs are passed to subsequent steps.

**Acceptance Criteria:**

**Given** a workflow step with `bmad_enabled: true` starts execution
**When** `SessionConfigResolver.new(session).resolve_bmad_enabled` is called
**Then** it returns `true` (reading from `step.bmad_enabled`)

**Given** a BMAD-enabled step produces output files in `/workspace/outputs/`
**When** the step completes
**Then** BMAD artifacts are collected as `WorkflowRunAsset` records
**And** they are available to subsequent steps in `/workspace/input/`

**Given** a BMAD-enabled step produces a PRD document at `/workspace/outputs/prd.md`
**When** the next step starts
**Then** the PRD is accessible at `/workspace/input/prd.md` via the standard WorkflowRunAsset pipeline

**Implementation Notes:**
- `SessionConfigResolver#resolve_bmad_enabled` already handles workflow steps (from Story 33.5)
- Output collection uses existing `collect_outputs` → `WorkflowRunAsset` flow
- No new code for the pipeline — existing `WorkflowStepStrategy` handles asset passing
- This story validates the end-to-end workflow flow works correctly with BMAD outputs

---

## Story 34.3: Frontend — BMAD Toggle in Workflow Step Editor

As a **workflow builder admin**,
I want a "Use BMAD Method" toggle in the step configuration panel,
So that I can enable BMAD for specific steps when designing a workflow.

**Acceptance Criteria:**

**Given** the admin opens a step configuration panel in the workflow builder
**When** the step settings are displayed
**Then** a "Use BMAD Method" toggle (MUI Switch) is visible below the tools/MCP configuration

**Given** the admin enables the BMAD toggle on a step
**When** the workflow is saved
**Then** the step's `bmad_enabled` field is persisted as `true` via the API

**Given** the admin re-opens a step with BMAD enabled
**When** the step configuration panel loads
**Then** the BMAD toggle shows as active/on

**Given** the toggle is displayed
**When** rendered in the UI
**Then** it follows the same MUI 6 dark theme styling as other step configuration toggles
**And** it is keyboard-accessible with proper ARIA attributes

**Implementation Notes:**
- Add to `StepConfigPanel` component
- MUI `Switch` with `FormControlLabel`, label "Use BMAD Method"
- Included in the step update API payload as `bmad_enabled: boolean`
