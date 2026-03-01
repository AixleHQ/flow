# Epic 26: Workflow Context in Agent Sessions

> Agents running workflow steps receive full workflow context (overview, current step, sub-steps, previous steps) directly in their context file, with clean separation between context file and AGENT_PROMPT.

**Phase:** 16 (Depends on: Epic 25 Unified Context Constructor, Epic 12 Workflows)

**Design Document:** [Session Context Constructor — §5.3 WorkflowContext Builder](../session-context-constructor.md)

**User Outcome:** Workflow step agents have complete awareness of their position in the workflow, progress so far, and remaining work — all visible in the context file without separate prompt injection. AGENT_PROMPT is simplified to contain only the user's task/prompt, not duplicated context.

**FRs Covered:** FR-SCC4, FR-SCC7

---

## Problem

Currently workflow context is assembled in `WorkflowStepStrategy#build_workflow_prompt` and injected via `AGENT_PROMPT` env var — separate from the main context file. This causes duplication (repos, assets described in both places) and prevents the agent from seeing workflow context alongside agent role, tools, and rules in a unified document.

Additionally, `WorkflowContextAssembler` exists as orphaned code — built but never wired in. This epic moves workflow context into a proper builder within the Constructor pipeline and simplifies `AGENT_PROMPT` to be the task prompt only.

---

## Stories

### Story 26.1: WorkflowContext Builder

**As a** system,
**I want** a WorkflowContext builder that produces workflow overview and current step sections,
**So that** workflow agents see their workflow position and step instructions in the context file.

**Acceptance Criteria:**

**Given** a session with `step_run` present (workflow step session)
**When** `ContextBuilders::WorkflowContext` runs
**Then** output includes a section with tag `workflow-context`, priority `:important`, containing:
  - Workflow name and description
  - Workflow run mode and ID
  - Current step position ("Step 3 of 7")
**And** output includes a section with tag `current-step`, priority `:critical`, containing:
  - Step name
  - Step description
  - Step instructions

**Given** a standalone session (no step_run)
**When** `applicable?` is called
**Then** returns `false` — no workflow sections produced

**Technical notes:**
- Builder accesses: `session.step_run` → `step_run.workflow_run` → `workflow_run.workflow`
- `current-step` is `:critical` priority because it's the primary task for the agent
- Content generation logic comes from design doc §5.3

---

### Story 26.2: Sub-Steps Checklist Section

**As a** system,
**I want** the WorkflowContext builder to include a sub-steps checklist with progress tracking,
**So that** agents can see which sub-steps are completed, in progress, or pending and know how to report progress.

**Acceptance Criteria:**

**Given** a workflow step with 6 sub-steps where 2 are completed, 1 is in_progress, and 3 are pending
**When** WorkflowContext builder runs
**Then** output includes a section with tag `sub-steps`, priority `:important`, containing:
  - Numbered list with status icons (✅ completed, 🔄 in_progress, ⏭️ skipped, ⬜ pending)
  - Sub-step name, ID reference, and status
  - Notes from completed sub-steps (truncated to 200 chars)
  - Data from completed sub-steps (truncated JSON to 300 chars)
  - Instructions to use `mark_sub_step` MCP tool with sub-step ID
  - Warning: "Do NOT mark the last sub-step completed until ALL work is done"

**Given** a step with no sub-steps
**When** WorkflowContext builder runs
**Then** no `sub-steps` section is produced

**Technical notes:**
- Sub-step runs accessed via `step_run.sub_step_runs.includes(:sub_step).index_by(&:sub_step_id)`
- Status icon mapping: `{ "completed" => "✅", "in_progress" => "🔄", "skipped" => "⏭️" }.fetch(status, "⬜")`

---

### Story 26.3: Previous Steps Summary Section

**As a** system,
**I want** the WorkflowContext builder to include summaries of completed previous steps,
**So that** agents have continuity and can reference decisions and outputs from earlier steps.

**Acceptance Criteria:**

**Given** a workflow run where steps 1 and 2 are completed, and current step is 3
**When** WorkflowContext builder runs
**Then** output includes a section with tag `previous-steps`, priority `:info`, containing:
  - Step number, name, and status icon (✅ or ⏭️)
  - Step note (truncated to 500 chars) if present
  - Completed sub-step names with notes (truncated to 150 chars)
  - Sub-step data (truncated JSON to 200 chars)

**Given** a workflow run on step 1 (no previous steps)
**When** WorkflowContext builder runs
**Then** no `previous-steps` section is produced

**Technical notes:**
- Completed step runs: `workflow_run.step_runs.where.not(id: step_run.id).where(state: %w[completed skipped]).joins(:step).order("steps.position ASC")`
- Uses eager loading: `.includes(step: :sub_steps, sub_step_runs: :sub_step)`
- Truncation prevents context bloat from verbose step notes

---

### Story 26.4: Workflow Tools Section

**As a** system,
**I want** the WorkflowContext builder to include a reference to available workflow MCP tools,
**So that** agents know how to track progress and save notes.

**Acceptance Criteria:**

**Given** a workflow step session with sub-steps
**When** WorkflowContext builder runs
**Then** output includes a section with tag `workflow-tools`, priority `:important`, listing:
  - `list_sub_steps` — List all sub-steps with current statuses
  - `mark_sub_step` — Update status with id, status, optional note and data
  - `write_step_note` — Save a note visible to subsequent steps

**Given** a workflow step session with no sub-steps
**When** WorkflowContext builder runs
**Then** no `workflow-tools` section is produced

**Technical notes:**
- These are already-existing MCP tools — this section just documents them in context for the agent
- Only shown when sub-steps exist (no point in showing progress tools without sub-steps)

---

### Story 26.5: Simplify AGENT_PROMPT & Clean Up WorkflowStepStrategy

**As a** system,
**I want** `WorkflowStepStrategy#build_env_vars` to set `AGENT_PROMPT` to only the step instructions (or user prompt), not the full workflow context,
**So that** context file and AGENT_PROMPT have clear responsibilities without duplication.

**Acceptance Criteria:**

**Given** a workflow step session where `WorkflowStepStrategy` builds env vars
**When** `AGENT_PROMPT` is set
**Then** its value contains only `step.instructions` (the task — what to do)
**And** it does NOT contain workflow overview, sub-steps checklist, repos, or tools (those are in the context file)

**Given** the current `build_workflow_prompt` method in `WorkflowStepStrategy`
**When** this story is complete
**Then** `build_workflow_prompt` is removed or simplified to return only `step.instructions`
**And** any duplicated context (repos, assets, MCP descriptions) is no longer in AGENT_PROMPT

**Technical notes:**
- Key principle: **context file = who you are + what you know + rules. AGENT_PROMPT = what to do.**
- Verify existing workflow tests pass after simplification
- `WorkflowStepStrategy` only needs to set `AGENT_PROMPT = step.instructions` — Constructor handles everything else via context file

---

## Dependency Graph

```
Story 26.1 (WorkflowContext builder — overview + current step)
    │
    ├──→ Story 26.2 (Sub-steps checklist)
    │
    ├──→ Story 26.3 (Previous steps summary)
    │
    └──→ Story 26.4 (Workflow tools section)

Story 26.5 (Simplify AGENT_PROMPT) ← depends on 26.1-26.4 being complete
```

---

## Implementation Notes

- WorkflowContext builder is the most complex builder — it produces up to 5 sections (workflow-context, current-step, sub-steps, previous-steps, workflow-tools)
- `current-step` is `:critical` priority — it's the most important section for the agent's task
- Previous steps are `:info` — reference material, not primary task
- All truncation lengths match the design doc (§5.3): notes 200/500 chars, data 300/200 chars
- Builder must be registered in `SessionContextConstructor::BUILDERS` after `Workspace` and before `Tools`
