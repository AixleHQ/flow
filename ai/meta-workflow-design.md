# System Meta-Workflow: Workflow Builder Agent

**Date:** 2026-02-28
**Status:** Draft
**Author:** Artem Petrov + AI Analysis
**Depends on:** [workflow-architecture.md](./workflow-architecture.md), [BMAD-structure-description.md](./BMAD-structure-description.md)

---

## 1. Goal

Create a **System Meta-Workflow** — the single workflow capable of programmatically creating Palad entities: Agents, Tools, MCP Servers, Skills, Workflows, Steps, SubSteps. The ultimate goal is to quickly build new workflows using an agent in interactive mode.

The meta-workflow is a **System-level workflow** (available to all companies). It is always interactive: the agent conducts a dialogue with the user, clarifies requirements, proposes a structure, and creates entities.

### 1.1 What makes the Meta-Workflow unique

| Regular Workflow | Meta-Workflow |
|---|---|
| Works with files in `/workspace/` | Works with the Palad API — creates entities in the DB |
| Tools: `mark_sub_step`, `export_asset` | Tools: `create_agent`, `create_workflow`, `create_step`, `create_tool`, etc. |
| Result — documents/assets | Result — a ready workflow with agents, tools, steps and sub-steps |
| UI shows the terminal + sub-step progress | UI shows the terminal + **live workflow builder** + activity log |

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
│  Palad Backend                                                   │
│  • Creates DB records (Workflow, Step, SubStep, Agent, Tool...)  │
│  • Broadcasts via ActionCable after each mutation                 │
│  • Validates consistency (positions, references, scoping)        │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Scope and availability

- The meta-workflow has `scope_type: 'System'`  
  (a new value — the current ones are: Company, Project; System is being added)
- System workflows are visible to all companies but not editable by them
- When a user runs the meta-workflow, the WorkflowRun is created in the context of a specific **Project** (the target project where the entities will be created)

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
Meta-Workflow: "Workflow Builder"
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
description: "Specialized agent for designing and building Palad workflows"
system_prompt: |
  You are a Workflow Architect for the Palad platform. Your job is to help users
  design and build workflows by creating the necessary entities (agents, tools,
  steps, sub-steps) through the provided meta-tools.

  ## Your Capabilities
  You can create and configure:
  - Workflows (process definitions)
  - Steps (one agent session = one deliverable)
  - SubSteps (trackable units of work within a step)
  - Agents (LLM personas with system prompts)
  - Tools (executable tools for agents)
  - MCP Servers (external tool servers)
  - Skills (domain-specific instruction sets)

  ## Design Principles
  1. Each Step = one terminal session = one agent = one major deliverable
  2. SubSteps are trackable work units, NOT interactive menu items
  3. Instructions should be detailed enough for the agent to work autonomously
  4. Consider both interactive and non-interactive execution modes
  5. Think about input/output asset specs for step validation
  6. Consider skip_policy for optional steps

  ## BMAD Integration
  When the user provides BMAD artifacts:
  - Map BMAD phases/processes → Palad Workflows
  - Map BMAD workflows (like "Create Architecture") → Palad Steps
  - Map BMAD step files (like step-04-decisions.md) → Palad SubSteps
  - Translate BMAD agent personas → Palad Agents
  - Translate BMAD critical instructions → Step instructions
  - Preserve BMAD's XML-DSL structure as markdown instructions

  ## Interaction Style
  - Always propose structure before creating entities
  - Explain your reasoning for each design decision
  - Show the current state of the workflow being built
  - Ask for confirmation before creating/modifying entities
```

---

## 5. BMAD context

### 5.1 The problem

BMAD-METHOD defines workflows, agents, and processes in YAML/MD/XML format. The user wants to:
1. Upload their BMAD artifacts (`.agent.yaml`, `workflow.yaml`, `instructions.md`, step files)
2. The agent must **read** these artifacts
3. And **translate** them into Palad entities

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
  "description": "Parse BMAD artifacts and return a structured mapping to Palad entities. Does NOT create entities — returns a plan for user review.",
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

### 6.3 UI Layout Meta-Workflow Run Page

```
┌─────────────────────────────────────────────────────────────────────┐
│  Meta-Workflow: Building "Product Planning" workflow                  │
│  Step 3 of 4: Build Workflow Structure   🔄 Running                 │
├──────────────────┬────────────────────────┬─────────────────────────┤
│  Terminal Panel   │  Activity Log          │  Workflow Preview       │
│  ┌──────────────┐│  ┌──────────────────┐  │  ┌───────────────────┐ │
│  │ > Creating   ││  │ 14:23 ✅ Created  │  │  │ Product Planning  │ │
│  │   step 3...  ││  │   Agent: PM      │  │  │                   │ │
│  │              ││  │ 14:24 ✅ Created  │  │  │ Step 1: Research  │ │
│  │ I'll now     ││  │   Agent: Arch    │  │  │   Agent: Analyst  │ │
│  │ create the   ││  │ 14:25 ✅ Created  │  │  │   SubSteps: 4     │ │
│  │ Architecture ││  │   Workflow:      │  │  │   ✅ Done          │ │
│  │ step with    ││  │   "Prod Plan"    │  │  │                   │ │
│  │ 6 sub-steps  ││  │ 14:25 ✅ Step 1  │  │  │ Step 2: PRD       │ │
│  │ ...          ││  │   Research       │  │  │   Agent: PM       │ │
│  │              ││  │ 14:26 ✅ Step 2  │  │  │   SubSteps: 5     │ │
│  │              ││  │   PRD Creation   │  │  │   ✅ Done          │ │
│  │              ││  │ 14:26 🔄 Step 3  │  │  │                   │ │
│  │              ││  │   Architecture   │  │  │ Step 3: Arch  🔄  │ │
│  │              ││  │   (in progress)  │  │  │   Agent: Architect│ │
│  │              ││  │                  │  │  │   SubSteps: ...   │ │
│  │              ││  │                  │  │  │                   │ │
│  └──────────────┘│  └──────────────────┘  │  └───────────────────┘ │
├──────────────────┴────────────────────────┴─────────────────────────┤
│  Sub-Steps: ✅ Create Workflow  ✅ Build Steps (3/7)  ⬜ SubSteps  │
│             ⬜ Configure Deps  ⬜ Link Resources                   │
└─────────────────────────────────────────────────────────────────────┘
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

---

## 9. Detailed Flow

### 9.1 User scenario: Build a workflow from BMAD

```
1. The user opens a project in Palad
2. Uploads BMAD artifacts as Assets (archive _bmad/)
3. Launches the Meta-Workflow "Workflow Builder"
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

8. Step 4: Validate & Refine
   The agent:
   - meta_finalize_workflow(workflow_id: ...)
   - "Validation passed! All steps have instructions, agents are attached..."
   - Or: "Issues found: Step 5 has no instructions"
   - Discusses with the user, makes edits
   - The user confirms: "The workflow is ready"
   
9. The meta-workflow completes
   - The user sees a link to the created workflow
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
   
3. Then — the same flow, but the agent builds the structure from the dialogue
```

---

## 10. Implementation Plan

### Phase 1: Foundation (2-3 days)
- [ ] Add `scope_type: 'System'` to the Workflow model
- [ ] Create `MetaWorkflowActivity` model + migration
- [ ] Create `MetaWorkflowChannel` (ActionCable)
- [ ] Implement basic meta-tools: `meta_create_workflow`, `meta_create_step`, `meta_create_sub_step`
- [ ] Permissions for meta-tools

### Phase 2: Full Tool Set (2-3 days)
- [ ] Implement all meta-tools from §3.1
- [ ] `meta_import_bmad` — BMAD artifact parser
- [ ] `meta_finalize_workflow` — validator
- [ ] Tool state management (implicit target workflow)
- [ ] Rate limits

### Phase 3: UI (3-4 days)
- [ ] `ActivityLog` component for the meta-workflow
- [ ] `WorkflowPreview` component (read-only live constructor)
- [ ] `MetaWorkflowRunPage` — specialized launch page
- [ ] ActionCable subscriptions + RTK Query invalidation
- [ ] Animations for live updates

### Phase 4: System Workflow & Agent (1-2 days)
- [ ] Seed: System meta-workflow with 4 steps
- [ ] Seed: Workflow Architect agent (system-level)
- [ ] Seed: Meta-tools registration
- [ ] UI: display System workflows in the list of available ones

### Phase 5: Polish & Testing (2-3 days)
- [ ] E2E test: creating a workflow from BMAD
- [ ] E2E test: creating a workflow from scratch
- [ ] Handling edge cases (failed tools, partial creation, retry)
- [ ] UX polish: loading states, error messages, confirmation dialogs

**Overall estimate: 10-15 days**

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
A full-fledged compiler from BMAD YAML → Palad entities, without an agent.

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
| 5 | How to version the System meta-workflow during Palad updates? | Seed update + migration. Running runs use a snapshot |
| 6 | Do we need a meta_delete_workflow tool? | Not yet — too destructive for automation |

---

_Document v1 generated 2026-02-28_
