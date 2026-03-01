# Epic 31: Workflow Base Resources & Builder UI

> Workflow Builder UI gets a "Base Resources" section for configuring tools/skills/MCP/assets shared across all steps, an "Inherit All" toggle, step `required_agent_runtime` selector, and "Effective" resource hints per step.

**Phase:** 17 (Depends on: Epic 29 Session Config Resolver, Epic 12 Workflows)

**Design Document:** [Session Config Cascade](../session-config-cascade.md)

**User Outcome:** Workflow designers can configure base resources that are automatically available in every step — no need to duplicate tool assignments across steps. The "Inherit All" toggle makes all project resources available at once, which is ideal for auto-triggered workflows from the board. Each step shows its "effective" resource set (base + step-specific) so designers can verify what the agent will receive.

**FRs Covered:** FR-CC8, FR-CC9

---

## Problem

Currently, resources (tools, skills, MCP servers) are only configurable per-step. If a workflow needs the same MCP server (e.g., context7) in all 5 steps, the designer must add it to each step individually. There's no way to say "give this workflow all project resources" — which is especially needed for auto-triggered workflows from the board where no user is present to select resources at launch time.

This epic adds UI for workflow-level base resources, the inherit_all toggle, and per-step required_agent_runtime — all backed by the `config` jsonb and the new Step field from Epic 29.

---

## Stories

### Story 31.1: Workflow Base Resources API

**As a** workflow designer,
**I want** to configure base tools, skills, MCP servers, and assets on a workflow,
**So that** these resources are available in all steps without per-step duplication.

**Acceptance Criteria:**

**Given** a PATCH request to workflow with `config.base_tool_ids = [1, 2]`
**When** the workflow is saved
**Then** `workflow.base_tool_ids` returns `[1, 2]`

**Given** a workflow update with `config.inherit_all_project_resources = true`
**When** saved
**Then** `workflow.inherit_all_project_resources` returns `true`

**Given** a workflow with no config set
**When** `workflow.base_tool_ids` is called
**Then** returns `[]` (safe default)

**Given** a workflow API response
**When** serialized
**Then** response includes `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids`, `base_asset_ids`, `inherit_all_project_resources`

**Technical notes:**
- Workflow model: add reader methods for `config` jsonb keys (base_tool_ids, base_skill_ids, base_mcp_server_ids, base_asset_ids, inherit_all_project_resources)
- WorkflowSerializer: include base resource fields
- WorkflowsController: permit config nested params
- No new columns — uses existing `config` jsonb

---

### Story 31.2: Workflow Builder — Base Resources Section UI

**As a** workflow designer,
**I want** a "Base Resources" section in the Workflow Builder page,
**So that** I can add tools, skills, MCP servers, and assets that will be shared across all steps.

**Acceptance Criteria:**

**Given** the Workflow Builder page
**When** designer views the workflow settings
**Then** a "Base Resources" section is visible above the steps list

**Given** the Base Resources section
**When** designer adds a tool to it
**Then** the tool appears in base resources and will be included in all step sessions

**Given** base resources with tools [context7]
**When** designer views Step 1 which has tools [security_scan]
**Then** Step 1 shows "Effective tools: context7, security_scan" hint

**Technical notes:**
- Reuse existing resource selector components (tool picker, skill picker, MCP picker, asset picker)
- "Effective" hint is computed client-side: union of base + step resources
- State management via RTK Query — same mutation pattern as step config

---

### Story 31.3: Workflow Builder — Inherit All Project Resources Toggle

**As a** workflow designer,
**I want** a checkbox "Inherit all project resources" on the workflow,
**So that** I can quickly make all project tools, skills, and MCP servers available in every step.

**Acceptance Criteria:**

**Given** the Workflow Builder page
**When** "Inherit all project resources" is checked
**Then** the "Effective" hint for each step shows all project resources + step resources

**Given** the toggle is checked
**When** designer views base resources section
**Then** base resource selectors are visually dimmed/disabled with a hint: "All project resources are inherited"

**Given** the toggle is unchecked
**When** designer views base resources
**Then** selectors are active and editable

**Technical notes:**
- Single boolean in workflow `config` jsonb
- Frontend: fetch project resources to compute effective set when toggle is on
- Step effective list = (project resources if inherit_all) + workflow base + step

---

### Story 31.4: Step Required Agent Runtime Selector

**As a** workflow designer,
**I want** to optionally specify a required agent runtime for a step,
**So that** certain steps always use the correct agent regardless of user defaults.

**Acceptance Criteria:**

**Given** the Step edit form in Workflow Builder
**When** designer views agent configuration
**Then** there is a "Required Agent Runtime" dropdown with options: [None (use default), claude_code, gemini_cli, codex, cursor_cli]

**Given** "Required Agent Runtime" set to "claude_code"
**When** step is saved
**Then** `step.required_agent_runtime = "claude_code"`

**Given** "Required Agent Runtime" set to "None (use default)"
**When** step is saved
**Then** `step.required_agent_runtime = nil`

**Given** a step with required_agent_runtime = "claude_code"
**When** viewing the step card in Workflow Builder
**Then** a badge shows "Requires: Claude Code" next to the agent name

**Technical notes:**
- Step model already has the `required_agent_runtime` column from Epic 29 Story 29.5
- StepSerializer: include `required_agent_runtime`
- StepsController: permit `required_agent_runtime` param
- Frontend: add to AddStepDialog / EditStepDialog

---

## Dependency Graph

```
Story 31.1 (API for base resources)
    │
    ├──→ Story 31.2 (Base Resources section UI)
    │        │
    │        └──→ Story 31.3 (Inherit All toggle)
    │
    └──→ Story 31.4 (Step required_agent_runtime selector)
```

---

## Implementation Notes

- No new database columns on Workflow — everything in existing `config` jsonb
- Step gets `required_agent_runtime` column in Epic 29 — this epic only adds the UI
- "Effective" resource hint is a UX enhancement computed entirely client-side
- Reuses existing resource picker components from session launch / step configuration
- Inherit All toggle is powerful but simple — one boolean controls whether project resources flow through
