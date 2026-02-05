# Epic 11: Workflows (Phase 5-6)

Users can create and execute workflows with step-by-step execution.

**FRs covered:** FR10, FR11, FR12, FR13, FR14, FR15, FR16, FR17, FR18

**Phase:** 5-6 (Depends on: Epic 10 Artifacts)

**User Outcome:** Complete workflow system with both execution modes.

## Story 11.1: Create New Workflow

**Acceptance Criteria:**
- Create workflow with name, description
- Associate with project
- Redirect to edit page

## Story 11.2: Define Workflow Steps

**Acceptance Criteria:**
- Add steps with: name, instructions, input_requirements, expected_outputs
- allow_non_interactive flag per step
- Reorder steps (drag & drop)
- Variables in instructions: {{artifact_name}}

## Story 11.3: Edit Existing Workflow

**Acceptance Criteria:**
- Modify all workflow properties
- Existing runs not affected
- Warning if currently running

## Story 11.4: Delete Workflow

**Acceptance Criteria:**
- Delete with confirmation
- Historical runs preserved
- Warning if active runs

## Story 11.5: View Workflows List

**Acceptance Criteria:**
- List all project workflows
- Shows name, steps count, last run
- Search and filter

## Story 11.6: Start Workflow Execution

**Acceptance Criteria:**
- Select input artifacts (auto + manual)
- Select mode (Interactive / Non-interactive)
- Creates WorkflowRun + first StepRun
- Temporal workflow started

## Story 11.7: Interactive Mode Execution

**Acceptance Criteria:**
- WorkflowStepper shows progress
- Each step opens session
- Approve/Reject after step
- Artifacts passed to next step

## Story 11.8: Non-Interactive Mode Execution

**Acceptance Criteria:**
- Steps with allow_non_interactive run automatically
- Steps without wait for approval
- Notifications on completion
- Total cost displayed

## Story 11.9: Artifact Passing Between Steps

**Acceptance Criteria:**
- Step outputs → next step inputs
- input_requirements resolved automatically
- Provenance tracks workflow origin
- Variables replaced in instructions

---
