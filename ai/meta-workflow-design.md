# System Meta-Workflow: Aixle Builder

**Date:** 2026-02-28
**Status:** Draft
**Author:** Artem Petrov + AI Analysis
**Depends on:** [workflow-architecture.md](./workflow-architecture.md), [BMAD-structure-description.md](./BMAD-structure-description.md)

---

## 1. Goal

Create **Aixle Builder** — a system-level meta-workflow that can programmatically create Aixle entities: Agents, Tools, MCP Servers, Skills, Workflows, Steps, SubSteps, **Board Columns, Column Workflow Bindings**. The ultimate goal is to quickly build new workflows, configure the project board, and bind automated workflows to columns — all with the help of an agent in interactive mode.

**Aixle Builder is NOT an ordinary workflow in the list.** It is not displayed among the project/company workflows. Instead, it is accessible through a **separate entry point** on the project workflows page (see §1.2).

The meta-workflow is a **System-level workflow** (available to all companies). It is always interactive: the agent holds a dialog with the user, clarifies requirements, proposes a structure, and creates entities. The agent receives a **huge detailed instruction** (§4.2) explaining all Aixle entities, how the board is structured, how automation works, and how to correctly build new workflows.

### 1.2 UI Entry Point: "Build with Aixle Builder"

Aixle Builder is launched **not through the standard workflow list**, but through a dedicated entry point on the project's workflows page (`WorkflowsPanel`).

#### Current page structure

```
WorkflowsPanel (features/workflows/ui/WorkflowsPanel.tsx)
┌─────────────────────────────────────────────────────────────┐
│  Workflows                            [+ New Workflow]      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │ WF Card  │ │ WF Card  │ │ WF Card  │  ...               │
│  └──────────┘ └──────────┘ └──────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

#### With Aixle Builder

```
WorkflowsPanel
┌─────────────────────────────────────────────────────────────┐
│  Workflows                            [+ New Workflow]      │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │  🤖 Aixle Builder                                       ││
│  │  Create a new workflow with AI assistance.              ││
│  │  Describe what you need — the builder will create       ││
│  │  agents, steps, board columns, and automation for you.  ││
│  │                                                         ││
│  │  [Start Aixle Builder]                                  ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │ WF Card  │ │ WF Card  │ │ WF Card  │  ...               │
│  └──────────┘ └──────────┘ └──────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

#### Component: AixleBuilderBanner

Located **above** the workflows list as a promo banner / CTA card.

```typescript
// features/workflows/ui/AixleBuilderBanner.tsx

interface AixleBuilderBannerProps {
  projectId: number;
  onStart: () => void;  // Opens the Meta-Workflow Run Page
}
```

**Behavior:**
- Always visible on the workflows page (above the grid list)
- The "Start Aixle Builder" button → launches the System Meta-Workflow for the current project
- Navigation: `→ /company/projects/{projectId}/aixle-builder` (separate page)
- Or, if there is an active builder run: shows "Continue building..." with a link to the current run

**Alternative option:** Aixle Builder as an item in the dropdown next to the "New Workflow" button:

```
[+ New Workflow ▾]
  ├── Blank Workflow        (current behavior — CreateWorkflowDialog)
  └── 🤖 Aixle Builder     (launch meta-workflow)
```

**Recommendation:** banner + dropdown. The banner for discovery (new users), the dropdown for quick access (experienced users).

### 1.1 What makes the Meta-Workflow unique

| Regular Workflow | Meta-Workflow |
|---|---|
| Works with files in `/workspace/` | Works with the Aixle API — creates entities in the DB |
| Tools: `mark_sub_step`, `export_asset` | Tools: `create_agent`, `create_workflow`, `create_step`, `create_tool`, `create_board_column`, `create_column_binding`, etc. |
| Result — documents/assets | Result — a ready workflow + a configured board with automation |
| UI shows terminal + sub-steps progress | UI shows terminal + **live workflow builder** + **board preview** + activity log |

---

## 2. Architecture

### 2.1 System levels

```
┌─────────────────────────────────────────────────────────────────┐
│  UI: Meta-Workflow Run Page                                      │
│  ┌──────────────┐  ┌─────────────────┐  ┌────────────────────┐  │
│  │  Terminal     │  │  Activity Log    │  │  Live Workflow     │  │
│  │  (agent chat) │  │  (created items) │  │  Constructor       │  │
│  │              │  │                  │  │  (preview of new   │  │
│  │              │  │  ✅ Agent: PM     │  │   workflow being   │  │
│  │              │  │  ✅ Step 1: ...   │  │   built)           │  │
│  │              │  │  🔄 Step 2: ...  │  │                    │  │
│  └──────────────┘  └─────────────────┘  └────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                    │                       │
         ▼                    ▼                       ▼
┌─────────────────┐  ┌───────────────────┐  ┌──────────────────┐
│  Terminal        │  │  ActionCable      │  │  RTK Query       │
│  Session         │  │  broadcasts       │  │  cache           │
│  (agent runs in  │  │  (real-time       │  │  invalidation    │
│   container)     │  │   updates)        │  │                  │
└────────┬────────┘  └───────────────────┘  └──────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Internal Tools (MCP)                                            │
│                                                                  │
│  Meta-workflow exclusive tools:                                   │
│  • create_workflow    • create_agent     • create_tool           │
│  • create_step        • create_skill     • create_mcp_server    │
│  • create_sub_step    • list_agents      • list_tools           │
│  • update_step        • list_skills      • list_mcp_servers     │
│  • delete_step        • link_tool        • finalize_workflow    │
│  • reorder_steps      • link_mcp_server  • import_bmad_context  │
│                                                                  │
│  Standard workflow tools:                                        │
│  • mark_sub_step, write_step_note, list_sub_steps               │
└────────┬────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Aixle Backend                                                   │
│  • Creates DB records (Workflow, Step, SubStep, Agent, Tool...)  │
│  • Broadcasts via ActionCable after each mutation                 │
│  • Validates consistency (positions, references, scoping)        │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Scope and availability

- Aixle Builder has `scope_type: 'System'`
  (a new value — the current ones are: Company, Project; System is being added)
- System workflows are **NOT displayed** in the regular workflow list (`WorkflowsPanel`)
- Standard scopes (`visible_for_project`, `for_company`) **exclude** System workflows
- Aixle Builder is accessible only through a separate entry point (§1.2)
- When a user launches Aixle Builder, a WorkflowRun is created in the context of a specific **Project** (the target project where the entities will be created)

**Backend filtering:**

```ruby
# Workflow model — System workflows are excluded from standard scopes
class Workflow < ApplicationRecord
  scope :visible_for_project, ->(project) {
    where(scope_type: "Company", scope_id: project.company_id)
      .or(where(scope_type: "Project", scope_id: project.id))
    # System scope intentionally excluded
  }

  # Separate scope for Aixle Builder
  scope :system_meta, -> { where(scope_type: "System", config: { meta_workflow: true }) }
end
```

**API endpoint for launching Aixle Builder:**

```
POST /api/v1/company/projects/{project_id}/aixle_builder/start
→ Creates a WorkflowRun for the System meta-workflow in the project context
→ Returns { workflow_run_id, redirect_url }
```

**Or** you can use the existing workflow launch endpoint, passing the ID of the System meta-workflow:

```
POST /api/v1/company/projects/{project_id}/workflow_runs
{ workflow_id: AIXLE_BUILDER_WORKFLOW_ID, mode: "interactive" }
```

### 2.3 Permissions

The meta-workflow tools require:
- The user must be an **admin** or **owner** in the company (to create company-level entities)
- Or have permissions to create project-level entities

Each internal tool checks permissions through the standard policy layer.

---

## 3. Internal Tools for the Meta-Workflow

### 3.1 Overview

All the tools below are **internal tools** (like `mark_sub_step`), available only in the meta-workflow via the `tool_ids` mechanism on the Step.

| Tool | Description | Broadcasts |
|------|----------|------------|
| `meta_create_workflow` | Create the target workflow | `workflow:created` |
| `meta_create_step` | Add a step to the target workflow | `workflow:step_created` |
| `meta_create_sub_step` | Add a sub-step to a step | `workflow:sub_step_created` |
| `meta_update_step` | Update a step (instructions, config) | `workflow:step_updated` |
| `meta_delete_step` | Delete a step | `workflow:step_deleted` |
| `meta_reorder_steps` | Change the order of steps | `workflow:steps_reordered` |
| `meta_create_agent` | Create a new agent | `agent:created` |
| `meta_create_tool` | Create a new tool | `tool:created` |
| `meta_create_mcp_server` | Create an MCP server | `mcp_server:created` |
| `meta_create_skill` | Create a skill | `skill:created` |
| `meta_link_tool_to_step` | Link a tool to a step | `workflow:step_updated` |
| `meta_link_mcp_server_to_step` | Link an MCP server to a step | `workflow:step_updated` |
| `meta_link_skill_to_step` | Link a skill to a step | `workflow:step_updated` |
| `meta_link_agent_to_step` | Link an agent to a step | `workflow:step_updated` |
| `meta_list_agents` | List available agents | — |
| `meta_list_tools` | List available tools | — |
| `meta_list_mcp_servers` | List available MCP servers | — |
| `meta_list_skills` | List available skills | — |
| `meta_list_workflows` | List existing workflows (for reference) | — |
| `meta_get_workflow` | Get the full workflow with steps/sub-steps | — |
| `meta_finalize_workflow` | Finalize and validate the workflow | `workflow:finalized` |
| `meta_import_bmad` | Import BMAD context (see §5) | — |
| **Board & Column tools** | | |
| `meta_get_board` | Get the current state of the project board (columns, bindings) | — |
| `meta_create_board_column` | Create a new column on the board | `board:column_created` |
| `meta_update_board_column` | Update a column (name, purpose, position) | `board:column_updated` |
| `meta_delete_board_column` | Delete an empty column | `board:column_deleted` |
| `meta_reorder_board_columns` | Reorder columns | `board:columns_reordered` |
| `meta_create_column_binding` | Bind a workflow to a column (auto/manual trigger) | `board:binding_created` |
| `meta_update_column_binding` | Update a binding (trigger_mode, cooldown) | `board:binding_updated` |
| `meta_delete_column_binding` | Remove a workflow binding from a column | `board:binding_deleted` |
| `meta_setup_board_from_preset` | Create a board from a preset (simple_kanban, dev_team, full_sdlc) | `board:created` |

### 3.2 Key Tool Definitions

#### meta_create_workflow

```json
{
  "name": "meta_create_workflow",
  "description": "Create a new workflow in the target project. Returns workflow_id for subsequent step creation.",
  "parameters": {
    "name": { "type": "string", "required": true },
    "description": { "type": "string", "required": false },
    "scope": { "type": "string", "enum": ["project", "company"], "default": "project" }
  }
}
```

Logic:
1. Create a `Workflow` in the target scope (the current user's project or company)
2. Save `workflow_id` in `StepRun.data[:target_workflow_id]` for subsequent tools
3. Broadcast via ActionCable
4. Return `{ workflow_id, name, scope }`

#### meta_create_step

```json
{
  "name": "meta_create_step",
  "description": "Add a step to the workflow being built. Steps are added sequentially unless position is specified.",
  "parameters": {
    "workflow_id": { "type": "integer", "required": true },
    "name": { "type": "string", "required": true },
    "description": { "type": "string", "required": false },
    "instructions": { "type": "string", "required": false },
    "agent_id": { "type": "integer", "required": false },
    "position": { "type": "integer", "required": false },
    "allow_non_interactive": { "type": "boolean", "default": false },
    "skip_policy": { "type": "string", "enum": ["never", "if_outputs_exist", "manual"], "default": "never" },
    "on_failure": { "type": "string", "enum": ["retry", "skip", "fail"], "default": "fail" },
    "max_retries": { "type": "integer", "default": 0 },
    "tool_ids": { "type": "array", "items": { "type": "integer" }, "required": false },
    "mcp_server_ids": { "type": "array", "items": { "type": "integer" }, "required": false },
    "skill_ids": { "type": "array", "items": { "type": "integer" }, "required": false },
    "input_asset_specs": { "type": "array", "required": false },
    "output_asset_specs": { "type": "array", "required": false },
    "mount_repositories": { "type": "boolean", "default": false },
    "depends_on_step_ids": { "type": "array", "items": { "type": "integer" }, "required": false }
  }
}
```

#### meta_create_agent

```json
{
  "name": "meta_create_agent",
  "description": "Create a new agent (LLM persona). Use for specialized roles needed by the workflow.",
  "parameters": {
    "title": { "type": "string", "required": true },
    "system_prompt": { "type": "string", "required": true },
    "description": { "type": "string", "required": false },
    "scope": { "type": "string", "enum": ["project", "company"], "default": "company" }
  }
}
```

#### meta_finalize_workflow

```json
{
  "name": "meta_finalize_workflow",
  "description": "Validate and finalize the workflow. Checks: all steps have instructions, agent references are valid, dependency graph is acyclic, positions are sequential.",
  "parameters": {
    "workflow_id": { "type": "integer", "required": true }
  }
}
```

Logic:
1. Load the workflow with all associations
2. Validate:
   - All steps have a name and instructions
   - All agent_id values reference existing agents
   - All tool_ids, mcp_server_ids, skill_ids are valid
   - The dependency graph is a DAG (no cycles)
   - Positions are sequential
   - All sub-steps have a name
3. Return `{ valid: true/false, errors: [...], summary: "..." }`

### 3.3 Board & Column Tool Definitions

#### meta_get_board

```json
{
  "name": "meta_get_board",
  "description": "Get the current state of the project board: columns with positions, purposes, and workflow bindings. Use this to understand existing board structure before making changes.",
  "parameters": {}
}
```

Logic:
1. Get the current project's Board (board = project.board)
2. Load columns with column_workflow_bindings and their associated workflows
3. Return:

```json
{
  "board_id": 1,
  "name": "Project Board",
  "preset_origin": "dev_team",
  "columns": [
    {
      "id": 10,
      "name": "Backlog",
      "position": 0,
      "purpose": "Tasks waiting to be picked up",
      "tasks_count": 12,
      "workflow_binding": null
    },
    {
      "id": 11,
      "name": "Tech Design",
      "position": 1,
      "purpose": "Architecture and technical specification",
      "tasks_count": 3,
      "workflow_binding": {
        "id": 5,
        "workflow_id": 42,
        "workflow_name": "Tech Design Review",
        "trigger_mode": "auto",
        "cooldown_seconds": 5
      }
    }
  ]
}
```

#### meta_create_board_column

```json
{
  "name": "meta_create_board_column",
  "description": "Create a new column on the project board. Position is auto-assigned to the end unless specified.",
  "parameters": {
    "name": { "type": "string", "required": true },
    "purpose": { "type": "string", "required": false, "description": "Description of what this column represents in the workflow process" },
    "position": { "type": "integer", "required": false, "description": "0-based position. If omitted, appended to end" }
  }
}
```

Logic:
1. Get the project's board
2. Create a `BoardColumn` with the given name and purpose
3. If position is not specified, assign the next one after the last
4. If position is specified, shift the remaining columns
5. Broadcast `board:column_created`
6. Return `{ column_id, name, position, purpose }`

#### meta_update_board_column

```json
{
  "name": "meta_update_board_column",
  "description": "Update an existing board column's name, purpose, or position.",
  "parameters": {
    "column_id": { "type": "integer", "required": true },
    "name": { "type": "string", "required": false },
    "purpose": { "type": "string", "required": false },
    "position": { "type": "integer", "required": false }
  }
}
```

#### meta_delete_board_column

```json
{
  "name": "meta_delete_board_column",
  "description": "Delete a board column. Column must have no tasks (tasks_count == 0). Fails if column contains tasks — move them first.",
  "parameters": {
    "column_id": { "type": "integer", "required": true }
  }
}
```

#### meta_reorder_board_columns

```json
{
  "name": "meta_reorder_board_columns",
  "description": "Reorder all board columns. Pass an array of column_ids in the desired order.",
  "parameters": {
    "column_ids": { "type": "array", "items": { "type": "integer" }, "required": true, "description": "Ordered array of all column IDs" }
  }
}
```

#### meta_create_column_binding

```json
{
  "name": "meta_create_column_binding",
  "description": "Bind a workflow to a board column. When a task enters this column, the workflow can be triggered manually or automatically. Only one binding per column.",
  "parameters": {
    "column_id": { "type": "integer", "required": true },
    "workflow_id": { "type": "integer", "required": true },
    "trigger_mode": { "type": "string", "enum": ["manual", "auto"], "default": "manual", "description": "manual = button in UI, auto = triggers when task enters column" },
    "cooldown_seconds": { "type": "integer", "default": 5, "description": "Minimum seconds between auto-triggers for same task" }
  }
}
```

Logic:
1. Verify that the column belongs to the current board
2. Verify that the workflow is available in the project (`Workflow.visible_for_project`)
3. Verify that the column does not already have a binding (unique constraint)
4. Create a `ColumnWorkflowBinding`
5. Broadcast `board:binding_created`
6. Return `{ binding_id, column_id, column_name, workflow_id, workflow_name, trigger_mode, cooldown_seconds }`

#### meta_update_column_binding

```json
{
  "name": "meta_update_column_binding",
  "description": "Update a column workflow binding's trigger mode or cooldown.",
  "parameters": {
    "binding_id": { "type": "integer", "required": true },
    "trigger_mode": { "type": "string", "enum": ["manual", "auto"], "required": false },
    "cooldown_seconds": { "type": "integer", "required": false }
  }
}
```

#### meta_delete_column_binding

```json
{
  "name": "meta_delete_column_binding",
  "description": "Remove a workflow binding from a column. Tasks will no longer trigger the workflow.",
  "parameters": {
    "binding_id": { "type": "integer", "required": true }
  }
}
```

#### meta_setup_board_from_preset

```json
{
  "name": "meta_setup_board_from_preset",
  "description": "Create or reset board columns from a predefined preset. WARNING: this replaces existing columns if board already has them (only if empty). Use for new projects or initial setup.",
  "parameters": {
    "preset": { "type": "string", "enum": ["simple_kanban", "dev_team", "full_sdlc"], "required": true }
  }
}
```

Available presets:
- **simple_kanban**: Backlog → In Progress → Done (3 columns)
- **dev_team**: Backlog → Tech Design → Implementation → Code Review → QA → Ready for Release → Done (7 columns, with purposes)
- **full_sdlc**: 19 columns of the full SDLC cycle (from Design to Release)

---

## 4. Steps Meta-Workflow

The meta-workflow itself consists of steps (like any other). The key point: it is **always interactive**.

### 4.1 Structure

```
Meta-Workflow: "Aixle Builder"
Mode: interactive (forced)
Scope: System

Step 1: "Understand Requirements"
  Agent: Workflow Architect
  SubSteps:
    1. Gather Context — understand what the user wants to build
    2. Analyze BMAD Input — if BMAD artifacts provided, parse and map
    3. Define Workflow Goals — identify deliverables, modes, agent roles
    4. Propose Structure — present high-level plan for user approval

Step 2: "Create Foundation"
  Agent: Workflow Architect
  SubSteps:
    1. Create Agents — create required agent personas
    2. Create Tools — create custom tools if needed
    3. Register MCP Servers — configure MCP servers if needed
    4. Create Skills — create skills for specialized knowledge

Step 3: "Build Workflow Structure"
  Agent: Workflow Architect
  SubSteps:
    1. Create Workflow — create the target workflow entity
    2. Build Steps — create steps one by one with instructions
    3. Add Sub-Steps — add sub-steps to each step
    4. Configure Dependencies — set up step dependencies
    5. Link Resources — attach agents, tools, MCP servers, skills to steps

Step 4: "Configure Board & Automation"
  Agent: Workflow Architect
  SubSteps:
    1. Inspect Board — get current board state via meta_get_board
    2. Propose Board Changes — suggest column additions/modifications for new workflow
    3. Create/Update Columns — add columns matching workflow stages
    4. Bind Workflows — create ColumnWorkflowBindings (auto/manual triggers)
    5. Review Automation — show user the complete board → workflow automation map

Step 5: "Validate & Refine"
  Agent: Workflow Architect
  SubSteps:
    1. Run Validation — execute meta_finalize_workflow
    2. Review with User — walk through the complete workflow + board setup
    3. Apply Corrections — make any adjustments user requests
    4. Final Approval — user confirms the workflow is ready
```

### 4.2 Workflow Architect Agent

A system-level agent, created specifically for the meta-workflow:

```yaml
title: "Workflow Architect"
scope: system
description: "Specialized agent for designing and building Aixle workflows, board columns, and automation bindings"
system_prompt: |
  You are a Workflow Architect for the Aixle platform. Your job is to help users
  design and build complete automation systems: workflows, board columns, and
  workflow-to-column bindings — through the provided meta-tools.

  ═══════════════════════════════════════════════════════════════════
  SECTION 1: AIXLE PLATFORM — COMPLETE ENTITY REFERENCE
  ═══════════════════════════════════════════════════════════════════

  ## 1.1 Entity Hierarchy Overview

  Aixle organizes work around Projects within Companies. Each entity is scoped
  to either a Company or a Project via polymorphic `scope_type`/`scope_id`.

  ```
  Company
  ├── Projects (many)
  │   ├── Board (1:1 with project)
  │   │   ├── BoardColumns (ordered by position)
  │   │   │   └── ColumnWorkflowBinding (0 or 1 per column)
  │   │   └── BoardTasks (cards on the board)
  │   │       ├── TaskComments
  │   │       ├── TaskAssets
  │   │       ├── ColumnTransitions (movement history)
  │   │       └── WorkflowRuns (triggered by column bindings)
  │   └── Workflows (scoped to project)
  │       ├── Steps (ordered, with DAG dependencies)
  │       │   ├── SubSteps (ordered, trackable units)
  │       │   └── Links to: Agent, Tools, Skills, MCP Servers
  │       └── WorkflowRuns (execution instances)
  │           └── StepRuns → SubStepRuns
  ├── Workflows (scoped to company — inherited by all projects)
  ├── Agents (company-level — shared across projects)
  ├── Tools (company-level)
  ├── Skills (company-level)
  └── MCP Servers (company-level)
  ```

  ## 1.2 Scoping Rules

  - **Company-scoped** entities are visible to ALL projects in the company.
  - **Project-scoped** entities are visible ONLY within that project.
  - When creating entities, choose scope wisely:
    - Use `company` scope for reusable agents, tools, skills across projects.
    - Use `project` scope for project-specific workflows and customizations.
  - `Workflow.visible_for_project(project)` returns both company + project workflows.

  ## 1.3 Agent

  An Agent is an LLM persona with a system prompt that defines its role, expertise,
  and behavioral guidelines.

  | Field | Type | Required | Description |
  |-------|------|----------|-------------|
  | title | string | yes | Display name (e.g., "Product Manager") |
  | name | string | auto | Auto-generated snake_case identifier |
  | persona | text | yes | Core system prompt — defines who the agent IS |
  | communication_style | text | no | HOW the agent communicates (tone, format) |
  | principles | text | no | Guiding principles and constraints |
  | description | text | no | Brief description for UI display |
  | scope | enum | yes | "company" or "project" |

  When building the system prompt, the platform concatenates:
  `persona + communication_style + principles` → agent.to_system_prompt

  **Best practices for persona design:**
  - Start with a clear role definition: "You are a [role] responsible for..."
  - Define expertise areas explicitly
  - Include domain-specific knowledge the agent should have
  - Set boundaries: what the agent should and should NOT do
  - For non-interactive workflows: emphasize autonomous decision-making

  ## 1.4 Workflow

  A Workflow is an ordered sequence of Steps that together produce a deliverable
  or accomplish a process.

  | Field | Type | Required | Description |
  |-------|------|----------|-------------|
  | name | string | yes | Unique name within scope |
  | description | text | no | What this workflow accomplishes |
  | scope | enum | yes | "company" or "project" |
  | config | jsonb | no | Base resources (see below) |

  **Config options:**
  - `base_tool_ids` — tools available to ALL steps by default
  - `base_skill_ids` — skills available to ALL steps
  - `base_mcp_server_ids` — MCP servers available to ALL steps
  - `base_asset_ids` — input assets for the workflow
  - `inherit_all_project_resources` — if true, all project-level tools/skills/MCP servers are available

  **Execution modes:**
  - `interactive` — agent can ask questions, user provides input mid-run
  - `non_interactive` — agent runs autonomously, must complete without user input
  - `mixed` — some steps interactive, some non-interactive (per-step `allow_non_interactive`)

  ## 1.5 Step

  A Step is ONE agent session = ONE terminal = ONE major deliverable.
  This is the most important entity to design correctly.

  | Field | Type | Required | Description |
  |-------|------|----------|-------------|
  | name | string | yes | Step name |
  | position | integer | auto | Order in workflow (0-based) |
  | instructions | text | recommended | Detailed instructions for the agent |
  | description | text | no | Brief UI description |
  | agent_id | integer | no | Which agent runs this step |
  | allow_non_interactive | boolean | false | Can run without user interaction |
  | skip_policy | enum | "never" | "never", "if_outputs_exist", "manual" |
  | on_failure | enum | "fail" | "retry", "skip", "fail" |
  | max_retries | integer | 0 | Retry count on failure |
  | tool_ids | array[int] | no | Tools available in this step |
  | skill_ids | array[int] | no | Skills injected into context |
  | mcp_server_ids | array[int] | no | MCP servers connected |
  | mount_repositories | boolean | false | Mount Git repos in /workspace |
  | input_asset_specs | jsonb | no | Required input files |
  | output_asset_specs | jsonb | no | Expected output files |
  | depends_on_step_ids | array[int] | no | DAG dependencies (parallel execution) |
  | preferred_model | string | no | LLM model ID override |
  | bmad_enabled | boolean | false | Enable BMAD methodology support |

  **Key design principles:**
  1. ONE step = ONE agent = ONE deliverable. Never split one logical unit across steps.
  2. Instructions are the MOST IMPORTANT field — they define what the agent does.
     Write them as detailed markdown with clear sections, requirements, and examples.
  3. Use `depends_on_step_ids` for parallel execution (DAG). Steps with no
     dependencies run in parallel. Steps depending on others wait.
  4. `skip_policy: "if_outputs_exist"` — skip if output assets already exist
     (useful for idempotent re-runs).
  5. `on_failure: "retry"` + `max_retries: 2` — auto-retry on transient failures.

  ## 1.6 SubStep

  A SubStep is a trackable unit of work within a Step. SubSteps are markers
  that the agent reports progress against — NOT separate execution contexts.

  | Field | Type | Required | Description |
  |-------|------|----------|-------------|
  | name | string | yes | SubStep name |
  | position | integer | yes | Order within step |
  | description | text | no | What this unit of work involves |
  | instructions | text | no | Additional guidance (injected into step context) |
  | required | boolean | false | Must be completed for step to finish |

  The agent uses the `mark_sub_step` tool to report progress:
  ```
  mark_sub_step(name: "Research Phase", status: "completed")
  ```

  **SubSteps are NOT:**
  - Separate terminal sessions (the whole step is one session)
  - Menu items for the user to choose from
  - Sub-workflows or nested steps

  **SubSteps ARE:**
  - Progress indicators visible in the UI
  - Checkpoints the agent marks as it proceeds through its work
  - A way to break complex instructions into trackable milestones

  ## 1.7 Tool

  A Tool is an executable capability available to agents during workflow execution.

  | Field | Type | Description |
  |-------|------|-------------|
  | name | string | Unique identifier (snake_case) |
  | display_name | string | UI display name |
  | description | text | What the tool does (shown to LLM) |
  | kind | enum | custom, system, internal, workflow |
  | execution_mode | enum | "app" (Rails) or "container" (Docker) |
  | docker_image | string | Required for container tools |
  | input_schema | jsonb | JSON Schema for parameters |

  **Tool kinds:**
  - `custom` — user-created, scoped, runs in Docker
  - `system` — platform-provided, visible in UI (e.g., web search)
  - `internal` — invisible helpers, auto-injected (e.g., mark_sub_step)
  - `workflow` — invisible, auto-injected only in workflow step sessions

  When designing workflows, you primarily attach `custom` and `system` tools to steps.
  Internal and workflow tools are managed by the platform.

  ## 1.8 Skill

  A Skill is a block of instructions/knowledge injected into the agent's context.
  Think of it as a "plug-in system prompt" that can be reused across steps.

  | Field | Type | Description |
  |-------|------|-------------|
  | name | string | Identifier (can include hyphens) |
  | title | string | Display name |
  | content | text | The actual instructions/knowledge |
  | description | text | Brief description |
  | kind | enum | "internal" or "custom" |

  **Use skills for:**
  - Domain knowledge (e.g., "Our API design standards")
  - Methodology instructions (e.g., "How to write a PRD")
  - Reusable guidelines across multiple workflow steps

  ## 1.9 MCP Server

  An MCP (Model Context Protocol) Server provides external tools to agents.

  | Field | Type | Description |
  |-------|------|-------------|
  | name | string | Identifier |
  | display_name | string | UI name |
  | url | string | Server endpoint (http/sse) |
  | command | string | Command for stdio transport |
  | transport | enum | "http", "sse", "stdio" |
  | headers | jsonb | Auth headers |
  | env | jsonb | Environment variables |

  **When to create MCP servers:**
  - When the workflow needs access to external APIs (Jira, Confluence, etc.)
  - When specialized tools are provided by third-party MCP servers
  - Usually configured at company level for broad reuse

  ═══════════════════════════════════════════════════════════════════
  SECTION 2: BOARD & AUTOMATION SYSTEM
  ═══════════════════════════════════════════════════════════════════

  ## 2.1 Board Architecture

  Every Project has exactly ONE Board. A Board has ordered BoardColumns.
  Tasks (BoardTasks) live in columns and can move between them.

  ```
  Board (1:1 with Project)
  ├── BoardColumn "Backlog" (position: 0)
  │   ├── BoardTask "Implement login" (position: 0)
  │   └── BoardTask "Fix header bug" (position: 1)
  ├── BoardColumn "In Progress" (position: 1)
  │   └── ColumnWorkflowBinding → Workflow "Code Review Prep" (auto)
  ├── BoardColumn "Code Review" (position: 2)
  │   └── ColumnWorkflowBinding → Workflow "Run Code Review" (auto)
  └── BoardColumn "Done" (position: 3)
  ```

  ## 2.2 BoardColumn

  | Field | Type | Description |
  |-------|------|-------------|
  | name | string | Column header (e.g., "Code Review") |
  | position | integer | Order on board (0-based, unique per board) |
  | purpose | text | Describes what this stage represents |

  **Purpose field** is important — it's used by agents when working with board
  tasks to understand what's expected at each stage. Write clear, actionable purposes.

  Example purposes:
  - "Tasks waiting for technical design and architecture decisions"
  - "Active development — code is being written and unit tested"
  - "Code review in progress — reviewer checks code quality, tests, and standards"

  ## 2.3 ColumnWorkflowBinding (Automation)

  A ColumnWorkflowBinding connects a BoardColumn to a Workflow. When a task
  moves into a column with a binding, the workflow can be triggered.

  | Field | Type | Description |
  |-------|------|-------------|
  | column_id | integer | Target column |
  | workflow_id | integer | Workflow to trigger |
  | trigger_mode | enum | "manual" or "auto" |
  | cooldown_seconds | integer | Min gap between auto-triggers (default: 5) |

  **Trigger modes:**
  - `manual` — shows a "Run Workflow" button in the UI. User clicks to trigger.
  - `auto` — workflow starts automatically when task enters the column.
    - Only triggers if no other active run exists for that task.
    - Respects `cooldown_seconds` between runs.
    - Respects TaskWait — if task has pending waits (CI/CD), auto-trigger is delayed.

  **One binding per column.** A column can have at most one workflow bound.

  **Automation flow:**
  ```
  Task moves to column → check_auto_trigger()
    → Has binding? → auto mode? → No pending waits? → No active run?
    → START non_interactive WorkflowRun(task: task, workflow: binding.workflow)
  ```

  ## 2.4 Board Presets

  Three predefined column layouts exist:

  **simple_kanban** (3 columns):
  Backlog → In Progress → Done

  **dev_team** (7 columns):
  Backlog → Tech Design → Implementation → Code Review → QA → Ready for Release → Done
  (Each column has a `purpose` describing expected artifacts and activities.)

  **full_sdlc** (19 columns):
  Backlog → Ready for Design → In Design → Design Review → Ready for Tech Design →
  In Tech Design → Tech Design Review → Ready for Dev → In Development → Code Review →
  Ready for QA → In QA → QA Approved → Ready for UAT → In UAT → UAT Approved →
  Ready for Release → In Release → Done

  ## 2.5 Designing Board + Workflow Automation

  The most powerful feature of Aixle is connecting board columns to workflows:

  **Pattern: "Column as Trigger"**
  When a task reaches a certain stage, a workflow automatically processes it.

  Example: Dev Team Automation
  ```
  Column: "Tech Design"
    → Binding: Workflow "Generate Tech Spec" (auto)
      Agent reads task description, produces technical design document

  Column: "Code Review"
    → Binding: Workflow "Automated Code Review" (auto)
      Agent reviews PR, comments on code quality

  Column: "QA"
    → Binding: Workflow "Run QA Checklist" (auto)
      Agent executes test plan, reports results
  ```

  **Design guidelines for automation:**
  1. Not every column needs a binding — only automate stages that benefit from AI.
  2. Use `manual` trigger for expensive or sensitive workflows.
  3. Use `auto` trigger for routine, well-defined processes.
  4. Board columns represent STATES, workflows represent ACTIONS triggered by state entry.
  5. A workflow bound to a column should expect the task's context (description, comments,
     assets) as its primary input — the platform injects board context automatically.
  6. Consider the flow: what happens AFTER the workflow completes? The agent can move
     the task to the next column via board tools.

  ═══════════════════════════════════════════════════════════════════
  SECTION 3: WORKFLOW EXECUTION MODEL
  ═══════════════════════════════════════════════════════════════════

  ## 3.1 How Workflows Execute

  ```
  WorkflowRun (state machine: pending → running → completed/failed)
  │
  ├── StepRun 1 (pending → running → completed)
  │   ├── TerminalSession (Docker container with agent)
  │   ├── SubStepRun 1.1 (pending → in_progress → completed)
  │   ├── SubStepRun 1.2 (pending → in_progress → completed)
  │   └── SubStepRun 1.3 (pending → completed)
  │
  ├── StepRun 2 (pending → running → completed)
  │   └── ...
  │
  └── StepRun 3 (pending → running → failed)
      └── error_message: "Agent could not complete task"
  ```

  **Execution order:**
  - Steps execute based on `depends_on_step_ids` (DAG).
  - Steps with NO dependencies → run in parallel (if infra supports).
  - Steps depending on others → wait until dependencies complete.
  - Within a step, sub-steps are sequential (agent marks them one by one).

  **State transitions:**
  - WorkflowRun: pending → running ↔ paused → completed/failed/cancelled
  - StepRun: pending → running → waiting_input → completed/failed/skipped/cancelled
  - SubStepRun: pending → in_progress → completed/skipped

  ## 3.2 Context Injection

  When a step runs, the platform builds the agent's system prompt from multiple
  context builders:

  1. **AgentRole** — agent persona (from agent.to_system_prompt)
  2. **CriticalRules** — mode rules (non-interactive constraints)
  3. **OutputRules** — output formatting
  4. **Resources** — available files, repos, assets
  5. **Tools** — tool schemas with descriptions
  6. **Board Context** — current task info (if workflow triggered from board)
  7. **Workflow Context** — step instructions, previous step outputs, shared_context
  8. **Skills** — injected skill content blocks
  9. **BMAD Method** — if bmad_enabled on step

  **shared_context** is a JSONB field on WorkflowRun that passes data between steps.
  Step 1 can write to shared_context, Step 2 can read from it.

  ## 3.3 What Agents Can Do Inside a Step

  Agents in workflow steps have access to these internal tools:
  - `mark_sub_step(name, status)` — report progress
  - `list_sub_steps()` — see expected sub-steps
  - `finish_session()` — mark step as completed (REQUIRED in non-interactive mode)
  - `fail_session(reason)` — mark step as failed

  If the step has board context (triggered from a task), agents also get:
  - `board_create_task`, `board_update_task`, `board_move_task`
  - `board_get_task`, `board_list_tasks`
  - `board_add_comment`, `board_get_comments`
  - `board_attach_asset`, `board_get_task_assets`
  - `board_get_board_info`, `board_manage_tags`
  - `board_create_wait` (for GitHub/GitLab CI blocking)

  ═══════════════════════════════════════════════════════════════════
  SECTION 4: HOW TO BUILD NEW ENTITIES — DESIGN METHODOLOGY
  ═══════════════════════════════════════════════════════════════════

  ## 4.1 Workflow Design Process

  Follow this methodology when building a workflow:

  **Step A: Understand the Goal**
  - What is the final deliverable? (document, code, review, deployment?)
  - Who triggers this? (human from board, auto-trigger, manual run?)
  - Interactive or autonomous?

  **Step B: Identify Stages**
  - Break the process into discrete stages where the focus shifts.
  - Each stage = one Step. Ask: "Would I assign this to a different person?"
  - Common patterns:
    - Research → Design → Implementation → Review
    - Analysis → Planning → Execution → Validation
    - Input Gathering → Processing → Output Generation

  **Step C: Design Each Step**
  For each step, define:
  1. **Agent** — who does this work? Create a new agent if needed.
  2. **Instructions** — the detailed prompt. This is the CORE of the step.
  3. **SubSteps** — trackable milestones within the step.
  4. **Resources** — tools, skills, MCP servers needed.
  5. **Dependencies** — which steps must complete first?
  6. **Mode** — can this run without user input?

  **Step D: Write Instructions**
  Step instructions are THE most important thing you create. Write them as
  detailed markdown:

  ```markdown
  ## Your Task
  [Clear statement of what the agent must produce]

  ## Context
  [What inputs are available, what previous steps have done]

  ## Requirements
  1. [Specific requirement 1]
  2. [Specific requirement 2]
  ...

  ## Output Format
  [Exactly what the output should look like]

  ## Quality Criteria
  - [What makes a good output]
  - [What to avoid]
  ```

  **Step E: Configure Board Integration (if applicable)**
  - Which board column should trigger this workflow?
  - What should happen after the workflow completes?
  - Should the agent move the task to the next column?

  ## 4.2 Agent Design Guidelines

  **When to create a new agent vs. reuse existing:**
  - Create new if the role has a fundamentally different expertise or perspective.
  - Reuse if the same persona can handle the work with different instructions.
  - Company-scoped agents are shared — avoid creating duplicates.

  **Persona writing formula:**
  ```
  You are a [ROLE] with expertise in [DOMAINS].
  Your primary responsibility is [RESPONSIBILITY].

  ## Expertise
  - [Area 1]: [Specific knowledge]
  - [Area 2]: [Specific knowledge]

  ## Working Style
  - [How you approach problems]
  - [How you communicate]
  - [What you prioritize]

  ## Constraints
  - [What you must NOT do]
  - [Boundaries of your role]
  ```

  ## 4.3 Common Workflow Patterns

  **Pattern 1: Linear Pipeline**
  ```
  Step 1 → Step 2 → Step 3 → Step 4
  ```
  Use when each step depends on the previous. Set `depends_on_step_ids` sequentially.

  **Pattern 2: Fan-Out / Fan-In**
  ```
  Step 1 (prep) → Step 2a, 2b, 2c (parallel) → Step 3 (merge)
  ```
  Steps 2a/2b/2c depend on Step 1. Step 3 depends on 2a, 2b, 2c.
  Use for independent analyses that feed into a synthesis step.

  **Pattern 3: Conditional Skip**
  ```
  Step 1 → Step 2 (skip_policy: if_outputs_exist) → Step 3
  ```
  Step 2 is skipped on re-runs if it already produced its outputs.

  **Pattern 4: Board-Triggered Automation**
  ```
  Task enters column → Workflow runs non_interactive
  → Agent reads task → Produces artifacts → Moves task to next column
  ```
  No user interaction needed. Agent completes and advances the board.

  **Pattern 5: Review Loop**
  ```
  Step 1: Generate → Step 2: Review (interactive)
  → User requests changes → Step 1 re-runs (with feedback in shared_context)
  ```

  ## 4.4 Anti-Patterns to Avoid

  ❌ **Micro-steps**: Don't create a step for every tiny action. One step that
     "writes a document" is better than 5 steps that "write intro", "write body",
     "write conclusion", "format", "review".

  ❌ **Vague instructions**: "Do the analysis" — too vague. Be specific about
     WHAT to analyze, HOW to analyze it, and WHAT the output should look like.

  ❌ **Tool overload**: Don't attach 20 tools to a step. Give agents only
     what they need. Excess tools confuse the LLM.

  ❌ **Missing non-interactive support**: If a workflow is auto-triggered from
     a board column, ALL steps MUST have `allow_non_interactive: true` and
     instructions must work without user input.

  ❌ **Circular dependencies**: depends_on_step_ids must form a DAG.
     Step A → Step B → Step A is invalid.

  ═══════════════════════════════════════════════════════════════════
  SECTION 5: BMAD INTEGRATION
  ═══════════════════════════════════════════════════════════════════

  ## 5.1 BMAD → Aixle Mapping

  When the user provides BMAD artifacts, map them:

  | BMAD Concept | Aixle Entity |
  |-------------|--------------|
  | BMAD Agent (.agent.yaml) | Agent (persona → system_prompt) |
  | BMAD Workflow (workflow.yaml) | Workflow |
  | BMAD Workflow step | Step |
  | BMAD step file (step-04-*.md) | SubSteps + Step instructions |
  | BMAD critical action | Part of Step instructions |
  | BMAD template | Skill (reusable content) |
  | BMAD checklist | SubStep with required=true |

  ## 5.2 Translating BMAD Agent YAML

  ```yaml
  # BMAD agent YAML
  title: Product Manager
  persona: "You are a strategic product manager..."
  communication_style: "Clear, data-driven..."
  principles: ["User-first", "Data-driven"]
  ```

  Maps to:
  ```
  meta_create_agent(
    title: "Product Manager",
    system_prompt: "[composed from persona + communication_style + principles]",
    scope: "company"
  )
  ```

  ## 5.3 Translating BMAD Workflow

  BMAD workflow.yaml defines phases and steps. Each BMAD workflow step file
  (.md) contains instructions, critical actions, and expected outputs.

  Map the workflow structure, but ADAPT the instructions for Aixle's execution
  model (terminal-based, tool-calling, asset-producing).

  ═══════════════════════════════════════════════════════════════════
  SECTION 6: YOUR INTERACTION PROTOCOL
  ═══════════════════════════════════════════════════════════════════

  ## 6.1 Always Propose Before Creating

  NEVER create entities without user confirmation. Always:
  1. Analyze requirements
  2. Propose a structure (show what you plan to create)
  3. Wait for user approval or modifications
  4. Create entities one by one, reporting progress

  ## 6.2 Show Current State

  After each creation, show the updated picture:
  ```
  ✅ Created Agent: "Product Manager" (company scope)
  ✅ Created Workflow: "Product Planning" (project scope)
  ✅ Created Step 1: "Research" (agent: Analyst)
     - SubStep 1.1: "Gather Requirements" ✅
     - SubStep 1.2: "Competitive Analysis" ✅
  🔄 Creating Step 2: "PRD Draft"...
  ```

  ## 6.3 Board Configuration

  When the workflow is designed to be triggered from the board:
  1. First inspect the current board state (meta_get_board)
  2. Propose column changes if needed (new columns, renamed columns)
  3. Show the binding map: which column triggers which workflow
  4. Explain trigger modes and get user preference (auto vs manual)
  5. Create bindings after user confirms

  ## 6.4 Ask Clarifying Questions

  When requirements are ambiguous, ask about:
  - Scope: company or project?
  - Mode: interactive, non-interactive, or mixed?
  - Board integration: should this bind to a column?
  - Trigger: manual or automatic?
  - Existing resources: reuse existing agents/tools or create new?
```

---

## 5. BMAD context

### 5.1 The problem

BMAD-METHOD defines workflows, agents, and processes in YAML/MD/XML format. The user wants to:
1. Upload their BMAD artifacts (`.agent.yaml`, `workflow.yaml`, `instructions.md`, step files)
2. The agent must **read** these artifacts
3. And **translate** them into Aixle entities

### 5.2 Solution: BMAD as Input Assets

BMAD artifacts are passed through the standard **input assets** mechanism of WorkflowRun:

```
The user starts the Meta-Workflow
    │
    ├─→ Selects input assets:
    │     • _bmad/ folder (uploaded as archive or individual files)
    │     • Or specific files: agent YAML, workflow YAML, instructions.md
    │
    ▼
Input assets are mounted into /workspace/input/
    │
    ├── _bmad/
    │   ├── agents/
    │   │   ├── pm.agent.yaml
    │   │   ├── architect.agent.yaml
    │   │   └── dev.agent.yaml
    │   ├── workflows/
    │   │   ├── create-architecture/
    │   │   │   ├── workflow.yaml
    │   │   │   └── instructions.md
    │   │   └── product-planning/
    │   │       ├── workflow.yaml
    │   │       └── instructions.md
    │   ├── templates/
    │   ├── checklists/
    │   └── core-config.yaml
    │
    ▼
The agent reads the files and uses the meta_import_bmad tool
```

### 5.3 Tool: meta_import_bmad

```json
{
  "name": "meta_import_bmad",
  "description": "Parse BMAD artifacts and return a structured mapping to Aixle entities. Does NOT create entities — returns a plan for user review.",
  "parameters": {
    "path": {
      "type": "string",
      "required": true,
      "description": "Path to BMAD root or specific file within /workspace/input/"
    }
  }
}
```

Logic (server-side parsing):
1. Scan BMAD directory structure
2. Parse `.agent.yaml` files → propose Agent mappings
3. Parse `workflow.yaml` + `instructions.md` → propose Workflow/Step/SubStep mappings  
4. Parse `core-config.yaml` → extract project-level configuration
5. Return structured plan:

```json
{
  "agents": [
    {
      "bmad_source": "agents/pm.agent.yaml",
      "proposed_title": "Product Manager",
      "proposed_system_prompt": "...(extracted from YAML)...",
      "confidence": "high"
    }
  ],
  "workflows": [
    {
      "bmad_source": "workflows/create-architecture/",
      "proposed_name": "Create Architecture",
      "proposed_steps": [
        {
          "bmad_source": "step-01-context.md",
          "proposed_name": "Context Analysis",
          "proposed_sub_steps": ["Load PRD", "Identify Requirements", "..."]
        }
      ]
    }
  ],
  "config": {
    "output_folder": "ai-output",
    "ephemeral_files": "..."
  }
}
```

The agent then:
1. Shows the plan to the user
2. Discusses changes
3. Creates entities via the `meta_create_*` tools

### 5.4 Alternative: Agent Reads BMAD Files Directly

Instead of (or in addition to) `meta_import_bmad`, the agent can simply **read the BMAD files** as ordinary files in `/workspace/input/` and interpret them on its own. This is a more flexible approach, since the agent can ask questions and adapt the mapping.

Recommendation: **use both approaches**:
- `meta_import_bmad` for automatic parsing and a structured plan
- Direct file reading by the agent for fine-tuning and discussion

---

## 6. Real-Time UI

### 6.0 Routing & Pages

Aixle Builder has **its own routes**, separate from the regular workflow run pages:

```typescript
// shared/routes.ts
aixleBuilderPath: '/company/projects/:projectId/aixle-builder',
aixleBuilderRunPath: '/company/projects/:projectId/aixle-builder/:runId',

// routeTree.tsx
export const aixleBuilderRoute = createRoute({
  getParentRoute: () => projectLayoutRoute,
  path: Routes.frontend.aixleBuilderPath,
  component: AixleBuilderPage,        // Start page / list of past builder runs
});

export const aixleBuilderRunRoute = createRoute({
  getParentRoute: () => projectLayoutRoute,
  path: Routes.frontend.aixleBuilderRunPath,
  component: AixleBuilderRunPage,      // Specialized page for a running builder
});
```

**AixleBuilderPage** — start page:
- The "Start new build" button → POST launch of meta-workflow → redirect to AixleBuilderRunPage
- List of past builder runs (if any) with results (which workflows were created)
- If there is an active run → show the "Continue building..." banner

**AixleBuilderRunPage** — page for a running builder (§6.3):
- Terminal + Activity Log + Workflow Preview + Board Preview
- Specialized for the meta-workflow (the regular WorkflowRunPage is not used)

### 6.1 Activity Log

On successful execution, each meta-tool creates a **MetaWorkflowActivity** record:

```ruby
class MetaWorkflowActivity < ApplicationRecord
  belongs_to :workflow_run
  belongs_to :created_entity, polymorphic: true, optional: true

  # action: string (created_workflow, created_step, created_agent, ...)
  # entity_type: string (Workflow, Step, SubStep, Agent, Tool, ...)
  # entity_name: string
  # details: jsonb
  # created_at: datetime
end
```

Broadcasts via ActionCable on the `MetaWorkflowChannel` channel:

```ruby
MetaWorkflowChannel.broadcast_to(
  workflow_run,
  {
    type: "activity",
    action: "created_step",
    entity_type: "Step",
    entity_name: "Create Architecture",
    entity_id: step.id,
    details: { position: 3, workflow_id: target_workflow.id },
    timestamp: Time.current.iso8601
  }
)
```

### 6.2 Live Workflow Constructor

The frontend subscribes to two channels:
1. `WorkflowRunChannel` — standard (sub-step progress, state changes)
2. `MetaWorkflowChannel` — specific (activity + entity updates)

When events are received from `MetaWorkflowChannel`, the UI **invalidates the RTK Query cache** for the target workflow:

```typescript
// On receiving a meta-workflow event:
onMessage(event) {
  if (event.type === 'activity') {
    // Invalidate the target workflow's cache
    dispatch(
      workflowsApi.util.invalidateTags([
        { type: 'Workflow', id: event.details.workflow_id },
        { type: 'Step', id: event.entity_id },
      ])
    );
  }
}
```

### 6.3 UI Layout: AixleBuilderRunPage

The page uses a **tabbed layout** — the right panel switches between Workflow Preview and Board Preview.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  🤖 Aixle Builder                                                         │
│  Step 3 of 5: Build Workflow Structure   🔄 Running                      │
├──────────────────┬───────────────────┬───────────────────────────────────┤
│  Terminal Panel   │  Activity Log     │  [Workflow ◉] [Board ○]          │
│  ┌──────────────┐│  ┌───────────────┐│  ┌─────────────────────────────┐ │
│  │ > Creating   ││  │ 14:23 ✅ Agent││  │ Product Planning            │ │
│  │   step 3...  ││  │   PM          ││  │                             │ │
│  │              ││  │ 14:24 ✅ Agent││  │ Step 1: Research            │ │
│  │ I'll now     ││  │   Architect   ││  │   Agent: Analyst            │ │
│  │ create the   ││  │ 14:25 ✅ WF   ││  │   SubSteps: 4  ✅          │ │
│  │ Architecture ││  │   "Prod Plan" ││  │                             │ │
│  │ step with    ││  │ 14:25 ✅ Step ││  │ Step 2: PRD                 │ │
│  │ 6 sub-steps  ││  │   Research    ││  │   Agent: PM                 │ │
│  │ ...          ││  │ 14:26 ✅ Step ││  │   SubSteps: 5  ✅          │ │
│  │              ││  │   PRD         ││  │                             │ │
│  │              ││  │ 14:26 🔄 Step ││  │ Step 3: Arch  🔄           │ │
│  │              ││  │   Architecture││  │   Agent: Architect          │ │
│  │              ││  │               ││  │   SubSteps: ...             │ │
│  └──────────────┘│  └───────────────┘│  └─────────────────────────────┘ │
├──────────────────┴───────────────────┴───────────────────────────────────┤
│  Sub-Steps: ✅ Create Workflow  ✅ Build Steps (3/7)  ⬜ SubSteps       │
│             ⬜ Configure Deps  ⬜ Link Resources                        │
└──────────────────────────────────────────────────────────────────────────┘
```

When switching to the **Board** tab:

```
                                        [Workflow ○] [Board ◉]
                                        ┌─────────────────────────────┐
                                        │  Project Board (dev_team)   │
                                        │                             │
                                        │  Backlog                    │
                                        │  Planning        ✨ NEW     │
                                        │  Tech Design     → WF ⚡   │
                                        │  Implementation             │
                                        │  Code Review     → WF ⚡   │
                                        │  QA              → WF ⚡   │
                                        │  Ready for Rel.             │
                                        │  Done                       │
                                        │                             │
                                        │  ⚡ = auto-trigger binding  │
                                        └─────────────────────────────┘
```

### 6.4 Workflow Preview Component

The `WorkflowPreview` component is a **read-only version of WorkflowBuilder** that:
- Is subscribed to `MetaWorkflowChannel`
- Automatically loads new steps/sub-steps when events are received
- Shows the current state of the target workflow "as if the user were viewing it in the builder"
- Highlights the last added/changed entity (animation)

Implementation: reuse components from `WorkflowBuilderPage`, but in `readonly + live-updates` mode:

```typescript
interface WorkflowPreviewProps {
  targetWorkflowId: number;
  metaWorkflowRunId: number;
  // read-only mode — no edit controls
  // auto-refreshes on ActionCable events
}
```

### 6.5 Board Preview Component

The `BoardPreview` component — a compact visualization of the project board with bindings:

```typescript
interface BoardPreviewProps {
  projectId: number;
  metaWorkflowRunId: number;
  // Shows columns as vertical list (compact, not full kanban)
  // Highlights newly created columns (animation)
  // Shows workflow bindings with trigger mode icons
  // Auto-refreshes on MetaWorkflowChannel events
}
```

Shows:
- List of columns in position order
- Next to each column — the bound workflow (if any) + trigger mode (⚡ auto / 👆 manual)
- New columns and bindings are highlighted with animation
- On hover — a tooltip with details (workflow name, cooldown, purpose)

---

## 7. Storing the target workflow reference

### 7.1 Where to store the target workflow ID

When the meta-workflow creates a new workflow, a reference to it must be stored so that:
- All subsequent steps know which workflow to work with
- The UI knows which workflow to show in the preview

Options:

**Option A: In `WorkflowRun.shared_context`**

```json
{
  "target_workflow_id": 42,
  "created_agents": [1, 2, 3],
  "created_tools": [5, 6]
}
```

Pros: standard mechanism, already present in the architecture.
Cons: shared_context is passed to the agent via the context file — the agent may not know the ID.

**Option B: Via `WorkflowRun.metadata` (a new jsonb field)**

```ruby
class WorkflowRun < ApplicationRecord
  # metadata: jsonb — system-level data, not injected into agent context
  # { target_workflow_id: 42, meta_mode: true }
end
```

Pros: clean separation of agent context vs system state.
Cons: a new field.

**Recommendation: Option A** — use `shared_context`. The agent receives this information anyway via workflow context injection, and can use `target_workflow_id` in tool calls. Additionally, the frontend reads `shared_context.target_workflow_id` to render the preview.

### 7.2 Tool State Management

Meta tools implement the **"implicit target"** pattern: after the first `meta_create_workflow`, its ID is automatically remembered in shared_context. Subsequent `meta_create_step` calls may omit `workflow_id` — it is taken from the context.

```ruby
class InternalTools::MetaCreateStep < InternalTools::Base
  def execute(params)
    workflow_id = params[:workflow_id] || current_workflow_run.shared_context&.dig("target_workflow_id")
    raise "No target workflow. Create one first with meta_create_workflow." unless workflow_id
    
    # ...create step...
  end
end
```

---

## 8. Safeguards and limits

### 8.1 Only the Meta-Workflow has meta-tools

Meta-tools (all `meta_*`) are registered as `tool_type: :internal` with `category: :meta`. They are available **only** to steps that belong to a workflow with `scope_type: 'System'` and `config.meta_workflow: true`.

```ruby
class InternalTools::MetaCreateWorkflow < InternalTools::Base
  def self.available_for?(step_run)
    step_run.workflow_run.workflow.meta_workflow?
  end
end

class Workflow < ApplicationRecord
  def meta_workflow?
    scope_type == 'System' && config&.dig('meta_workflow') == true
  end
end
```

### 8.2 Cleanup on a Failed Run

If a meta-workflow run fails or is cancelled:
- All created entities (workflow, steps, agents, tools) **remain** (they are not deleted automatically)
- The user can continue working manually or restart the meta-workflow
- The MetaWorkflowActivity log preserves the full history of what was created

### 8.3 Rate Limits

Meta-tools have limits for safety:
- At most 1 workflow per run
- At most 20 steps per run
- Maximum 100 sub-steps per run
- Maximum 10 agents per run
- Maximum 10 tools per run
- Maximum 30 board columns per run
- Maximum 30 column bindings per run

---

## 9. Detailed Flow

### 9.1 User scenario: Build a workflow from BMAD

```
1. The user opens a project in Aixle
2. Uploads BMAD artifacts as Assets (archive _bmad/)
3. Launches Aixle Builder
4. On the launch screen:
   - Selects input assets: _bmad/ archive
   - Mode: Interactive (locked, meta-workflow only interactive)
   
5. Step 1: Understand Requirements
   The agent:
   - Reads /workspace/input/_bmad/
   - Calls meta_import_bmad for structured parsing
   - Shows the user the mapping:
     "I found 3 agents (PM, Architect, Dev), 
      2 workflow (Product Planning, Code Report).
      Product Planning has 7 steps: ..."
   - The user clarifies: "Let's start with Product Planning"
   - The agent marks sub-steps as completed

6. Step 2: Create Foundation
   The agent:
   - "Creating Agent: Product Manager..."
   - Calls meta_create_agent(title: "PM", system_prompt: "...")
   - UI: Activity Log updates ✅ Created Agent: PM
   - "Creating Agent: Architect..."
   - UI: Activity Log ✅ Created Agent: Architect
   - ...and so on for all required agents/tools
   
7. Step 3: Build Workflow Structure
   The agent:
   - "Creating Workflow 'Product Planning'..."
   - meta_create_workflow(name: "Product Planning", ...)
   - UI: Workflow Preview appears, showing an empty workflow
   
   - "Adding Step 1: Research & Brainstorming..."
   - meta_create_step(name: "Research", agent_id: analyst_id, ...)
   - UI: Workflow Preview updates — Step 1 appeared
   
   - "Adding Sub-Steps to Step 1..."
   - meta_create_sub_step(step_id: ..., name: "Session Setup")
   - meta_create_sub_step(step_id: ..., name: "Technique Selection")
   - UI: Workflow Preview — Step 1 expands, sub-steps are visible
   
   - ...repeats for each step
   - The user can intervene: "This step is not needed" / "Add another sub-step"

8. Step 4: Configure Board & Automation
   The agent:
   - meta_get_board() — gets the current state of the board
   - "Your board uses the dev_team preset. I suggest binding the
     'Product Planning' workflow to the 'Tech Design' column with auto-trigger."
   - User: "Yes, and add a 'Planning' column before 'Tech Design'"
   - meta_create_board_column(name: "Planning", purpose: "Product planning and research", position: 1)
   - meta_create_column_binding(column_id: ..., workflow_id: ..., trigger_mode: "auto")
   - UI: Board Preview updates — new column + binding icon

9. Step 5: Validate & Refine
   The agent:
   - meta_finalize_workflow(workflow_id: ...)
   - "Validation passed! All steps have instructions, agents are attached..."
   - Shows the full map: Board columns → Workflow bindings → Steps
   - Or: "Issues found: Step 5 has no instructions"
   - Discusses with the user, makes edits
   - The user confirms: "The workflow is ready"

10. The meta-workflow completes
    - The user sees a link to the created workflow
    - Sees the updated board with bindings
    - Can go to the builder for final edits
    - Can immediately launch the new workflow
```

### 9.2 User scenario: Build a workflow from scratch

```
1. The user launches the Meta-Workflow without BMAD context
2. Step 1: Understand Requirements
   The agent asks:
   - "What should your workflow do?"
   - "What deliverables are expected?"
   - "What roles/agents are needed?"
   - "Interactive or automatic process?"
   - "Would you like to bind this workflow to a column on the board?"

3. Then — the same flow, but the agent builds the structure from the dialogue
```

### 9.3 User scenario: Configure board automation

```
1. The user launches the Meta-Workflow and says:
   "I want to set up automation for our board.
    When a task lands in Code Review — run a code review.
    When a task lands in QA — run a test plan."

2. Step 1: Understand Requirements
   The agent:
   - meta_get_board() — looks at the current board
   - meta_list_workflows() — looks at existing workflows
   - "I see the dev_team board with 7 columns. There are 2 workflows:
     'Code Review Bot' and 'QA Checklist'. Bind them?"
   - Or: "There is no workflow for Code Review. Create a new one?"

3. Step 2: Create Foundation (if new agents/tools are needed)

4. Step 3: Build Workflow Structure (if new workflows are needed)

5. Step 4: Configure Board & Automation
   The agent:
   - "Binding 'Code Review Bot' to the 'Code Review' column (auto)..."
   - meta_create_column_binding(column_id: CR_col, workflow_id: CR_wf, trigger_mode: "auto")
   - "Binding 'QA Checklist' to the 'QA' column (auto)..."
   - meta_create_column_binding(column_id: QA_col, workflow_id: QA_wf, trigger_mode: "auto")
   - Shows the resulting automation map:
     ```
     Board: Project Board (dev_team)
     ──────────────────────────────────────
     Backlog          │ (no automation)
     Tech Design      │ (no automation)
     Implementation   │ (no automation)
     Code Review      │ → "Code Review Bot" (auto) ⚡
     QA               │ → "QA Checklist" (auto) ⚡
     Ready for Release│ (no automation)
     Done             │ (no automation)
     ```

6. Step 5: Validate & Refine
   - Checking bindings, discussion with the user
```

---

## 10. Implementation Plan

### Phase 1: Foundation (2-3 days)
- [ ] Add `scope_type: 'System'` to the Workflow model
- [ ] Create `MetaWorkflowActivity` model + migration
- [ ] Create `MetaWorkflowChannel` (ActionCable)
- [ ] Implement basic meta-tools: `meta_create_workflow`, `meta_create_step`, `meta_create_sub_step`
- [ ] Permissions for meta-tools

### Phase 2: Full Workflow Tool Set (2-3 days)
- [ ] Implement all workflow meta-tools from §3.1
- [ ] `meta_import_bmad` — BMAD artifact parser
- [ ] `meta_finalize_workflow` — validator
- [ ] Tool state management (implicit target workflow)
- [ ] Rate limits

### Phase 3: Board & Automation Tools (2-3 days)
- [ ] `meta_get_board` — retrieving the board state
- [ ] `meta_create_board_column`, `meta_update_board_column`, `meta_delete_board_column`
- [ ] `meta_reorder_board_columns`
- [ ] `meta_create_column_binding`, `meta_update_column_binding`, `meta_delete_column_binding`
- [ ] `meta_setup_board_from_preset`
- [ ] Board-specific broadcasts for MetaWorkflowChannel
- [ ] Validation: column belongs to project board, workflow visible for project

### Phase 4: UI — Entry Point & Routing (2-3 days)
- [ ] Routes: `/company/projects/:projectId/aixle-builder` and `aixle-builder/:runId`
- [ ] `AixleBuilderBanner` — CTA banner on `WorkflowsPanel` (above the workflows list)
- [ ] Dropdown "New Workflow" → "Blank Workflow" / "Aixle Builder"
- [ ] `AixleBuilderPage` — start page (start new / list past runs)
- [ ] API: `POST /projects/:id/aixle_builder/start` (or via workflow_runs with system workflow_id)
- [ ] Filter System workflows out of standard scopes (do not show in WorkflowsPanel)

### Phase 5: UI — Builder Run Page (3-4 days)
- [ ] `AixleBuilderRunPage` — specialized page with 3 panels
- [ ] `ActivityLog` component for the meta-workflow
- [ ] `WorkflowPreview` component (read-only live constructor)
- [ ] `BoardPreview` component (shows board state + bindings)
- [ ] Workflow/Board tab switcher in the right panel
- [ ] ActionCable subscriptions + RTK Query invalidation
- [ ] Animations for live updates (new columns, bindings, steps)

### Phase 6: System Workflow & Agent (1-2 days)
- [ ] Seed: System meta-workflow "Aixle Builder" with 5 steps
- [ ] Seed: Workflow Architect agent (system-level) with full instructions
- [ ] Seed: Meta-tools registration (workflow + board tools)
- [ ] Exclude System workflows from `visible_for_project` / `for_company` scopes

### Phase 6: Polish & Testing (2-3 days)
- [ ] E2E test: creating a workflow from BMAD + board binding
- [ ] E2E test: creating a workflow from scratch
- [ ] E2E test: configuring board automation (scenario 9.3)
- [ ] Handling edge cases (failed tools, partial creation, retry)
- [ ] Edge case: deleting a column with tasks (should fail)
- [ ] Edge case: binding to a non-existent workflow
- [ ] UX polish: loading states, error messages, confirmation dialogs

**Overall estimate: 14-20 days**

---

## 11. Alternative approaches (considered)

### A. Meta-workflow as a regular workflow with privileged tools
**Selected** — described above. Minimal changes to the architecture. Meta-tools are just internal tools with restricted access.

### B. A separate "Workflow Designer" system outside the workflow engine
A separate UI + backend for designing workflows with an AI assistant. Does not use the workflow engine.

Pros: clean separation.
Cons: duplication (its own execution engine, its own context), does not reuse existing infrastructure (terminal sessions, ActionCable, progress tracking).

### C. Code-generation approach
The agent generates a YAML/JSON description of the workflow, which is then imported in a single action.

Pros: simpler, no real-time updates needed.
Cons: no live preview, no incremental discussion, batch import is harder to debug.

### D. BMAD-compiler (server-side)
A full BMAD YAML → Aixle entities compiler, without an agent.

Pros: deterministic, fast.
Cons: inflexible (the mapping is not always 1:1, interpretation is needed), does not help create workflows from scratch.

---

## 12. Open questions

| # | Question | Proposal |
|---|--------|-------------|
| 1 | Do we need a separate `scope_type: 'System'` or is a `system: true` flag enough? | `scope_type: 'System'` is cleaner — no separate polymorphic scope object is needed |
| 2 | Should meta-tools be able to edit existing workflows? | Yes, via `meta_update_step`. But mutating other users' workflows is forbidden |
| 3 | How to handle the situation when the agent runtime is unavailable? | Standard error handling — retry or fail depending on the step config |
| 4 | Do we need the ability to "fork" the meta-workflow to create custom builder workflows? | Not yet — a single System meta-workflow is enough |
| 5 | How do we version the System meta-workflow on Aixle updates? | Seed update + migration. Running runs use a snapshot |
| 6 | Do we need a meta_delete_workflow tool? | Not yet — too destructive for automation |
| 7 | Can a meta-workflow change the board preset (reset to preset) if the board already contains tasks? | No — `meta_setup_board_from_preset` works only if all columns are empty. Otherwise — add columns one by one |
| 8 | How do we handle a binding conflict — a column is already bound to another workflow? | Show the user the current binding, ask: replace or keep? Do not overwrite automatically |
| 9 | Do we need a preview of board automation in the real-time UI (like WorkflowPreview)? | Yes — a `BoardPreview` component showing columns + bindings. Updated via MetaWorkflowChannel |
| 10 | Should the agent be able to delete other bindings (created not via meta-workflow)? | Yes, but with user confirmation. The agent shows the current binding and asks |

---

_Document v1 generated 2026-02-28_
_Document v2 updated 2026-03-27 — added Board columns, automation bindings, comprehensive agent instructions_
