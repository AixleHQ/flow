# Palad Platform — System Reference

> Complete reference for AI agents operating within the Palad platform.
> This document describes all entities, their relationships, and how automation works.

---

## 1. Platform Overview

Palad is an AI-powered project management and workflow automation platform. It enables teams to define business processes as **Workflows** that are executed by AI agents, triggered manually or automatically from a project **Board**.

### Core Concepts

- **Company** — top-level organization. Owns shared resources (agents, tools, skills, workflows).
- **Project** — a workspace within a company. Has its own board, tasks, workflows, and resources.
- **Board** — kanban-style task board (one per project). Has columns representing stages.
- **Workflow** — a sequence of steps that together accomplish a business process.
- **Agent** — an LLM persona with a system prompt that executes workflow steps.
- **Terminal Session** — a running agent instance inside a container.

---

## 2. Entity Hierarchy

```
Company
├── Users (members with roles)
├── Agents (company-scoped — shared across all projects)
├── Tools (company-scoped)
├── Skills (company-scoped)
├── MCP Servers (company-scoped)
├── Workflows (company-scoped — inherited by all projects)
├── Repositories (Git repos)
├── Config Items (secrets & variables)
│
└── Projects (many)
    ├── Board (exactly one per project)
    │   ├── BoardColumns (ordered stages)
    │   │   └── ColumnWorkflowBinding (0 or 1 — automation trigger)
    │   ├── BoardTasks (work items / cards)
    │   │   ├── TaskComments (threaded, with tags)
    │   │   ├── TaskAssets (file attachments)
    │   │   ├── ColumnTransitions (movement history)
    │   │   ├── TaskWaits (external blockers: CI/CD)
    │   │   └── WorkflowRuns (triggered by column bindings)
    │   ├── BoardActivities (immutable event log)
    │   └── BoardViewPresets (saved filters)
    │
    ├── Agents (project-scoped)
    ├── Tools (project-scoped)
    ├── Skills (project-scoped)
    ├── MCP Servers (project-scoped)
    ├── Workflows (project-scoped)
    │   ├── Steps (ordered, with DAG dependencies)
    │   │   ├── SubSteps (progress milestones)
    │   │   └── Links to: Agent, Tools, Skills, MCP Servers
    │   └── WorkflowRuns (execution instances)
    │       ├── StepRuns (one per step)
    │       │   └── SubStepRuns
    │       └── WorkflowRunAssets (produced files)
    │
    ├── Assets (project files)
    ├── Repositories (project-level Git repos)
    └── Terminal Sessions (agent instances)
```

---

## 3. Scoping & Visibility

All major entities use **polymorphic scoping**: `scope_type` (Company or Project) + `scope_id`.

| Scope | Visibility | Use When |
|-------|-----------|----------|
| **Company** | All projects in the company | Shared agents, reusable workflows, common tools |
| **Project** | Only within that project | Project-specific customizations |

**Resolution rule**: `visible_for_project(project)` returns both project-scoped AND company-scoped entities.

---

## 4. Board & Tasks

### Board

Each Project has exactly ONE Board. A Board contains ordered **BoardColumns** (stages). Tasks move between columns.

### BoardColumn

| Field | Description |
|-------|-------------|
| name | Column header (e.g., "Code Review") |
| position | Order on board (unique per board) |
| purpose | Description of what this stage represents — used by agents |

### BoardTask

| Field | Description |
|-------|-------------|
| title | Task title (required) |
| description | Task details (markdown) |
| task_type | epic, story, bug, not_specified |
| priority | low, medium, high, critical |
| tags | Array of string tags for filtering |
| position | Order within column |
| parent_task_id | Epic-story nesting (1 level max) |
| assignee_id | Assigned user |

Tasks have: **TaskComments** (with tags like `tech_design`, `code_review`, `qa_report`), **TaskAssets** (file attachments), **ColumnTransitions** (movement history with actor_type: human/agent/auto_trigger), **TaskWaits** (external process blockers for GitHub/GitLab CI).

### BoardActivity

Immutable event log: task_created, task_updated, task_deleted, task_moved, comment_added, asset_attached, workflow_started, workflow_completed, workflow_failed, human_help_requested. Each has actor_type (human/agent/system) and metadata.

---

## 5. Workflows

### Workflow

An ordered sequence of Steps that produce deliverables.

| Field | Description |
|-------|-------------|
| name | Unique within scope |
| description | What this workflow accomplishes |
| config | Base resources: base_tool_ids, base_skill_ids, base_mcp_server_ids, base_asset_ids, inherit_all_project_resources |

**Execution modes**: interactive (agent asks user), non_interactive (fully autonomous), mixed (per-step).

### Step

ONE Step = ONE agent session = ONE terminal = ONE major deliverable.

| Field | Description |
|-------|-------------|
| name | Step name |
| position | Order in workflow |
| instructions | Detailed markdown instructions for the agent (**most important field**) |
| agent_id | Which agent runs this step |
| allow_non_interactive | Can run without user interaction |
| skip_policy | never, if_outputs_exist, manual |
| on_failure | retry, skip, fail |
| max_retries | Auto-retry count |
| tool_ids | Tools available in this step |
| skill_ids | Skills injected into context |
| mcp_server_ids | MCP servers connected |
| mount_repositories | Mount Git repos in /workspace |
| depends_on_step_ids | DAG dependencies (enables parallel execution) |
| preferred_model | LLM model override |
| bmad_enabled | Enable BMAD methodology |
| input_asset_specs | Required input files |
| output_asset_specs | Expected output files |

### SubStep

Progress milestones within a Step. NOT separate sessions — the agent marks them with `mark_sub_step` tool.

| Field | Description |
|-------|-------------|
| name | SubStep name |
| position | Order within step |
| required | Must be completed for step to finish |
| instructions | Additional guidance |

### Execution Flow

```
WorkflowRun (pending → running → completed/failed)
├── StepRun 1 (pending → running → completed)
│   ├── TerminalSession (container with agent)
│   ├── SubStepRun 1.1 → 1.2 → 1.3
│   └── Produces: WorkflowRunAssets
├── StepRun 2 (waits for StepRun 1 if depends_on_step_ids)
└── StepRun 3
```

Steps execute based on `depends_on_step_ids` (DAG). Steps with no dependencies can run in parallel.

---

## 6. Automation: Column → Workflow Binding

### ColumnWorkflowBinding

Connects a BoardColumn to a Workflow. When a task enters the column, the workflow triggers.

| Field | Description |
|-------|-------------|
| board_column_id | Target column (unique — one binding per column) |
| workflow_id | Workflow to trigger |
| trigger_mode | **manual** (button in UI) or **auto** (triggers on task entry) |
| cooldown_seconds | Minimum gap between auto-triggers (default: 5) |

### Automation Flow

```
Task moves to column
  → Has binding? → Auto mode?
    → No pending TaskWaits? → No active WorkflowRun?
      → START non_interactive WorkflowRun
        → Agent reads task context → Produces artifacts → Can move task to next column
```

### Board Presets

Pre-defined column layouts:

- **simple_kanban** (3): Backlog → In Progress → Done
- **dev_team** (7): Backlog → Tech Design → Implementation → Code Review → QA → Ready for Release → Done
- **full_sdlc** (19): Complete SDLC from Design through Release

Each preset column includes a `purpose` field guiding agents on expected activities.

---

## 7. Agents

An Agent is an LLM persona configuration.

| Field | Description |
|-------|-------------|
| name | Identifier (snake_case) |
| title | Display name |
| persona | Core system prompt — defines who the agent IS |
| communication_style | HOW the agent communicates |
| principles | Guiding constraints |
| source | custom or bmad_import |

`agent.to_system_prompt` concatenates: persona + communication_style + principles.

### Agent Runtimes

The actual LLM runtime that executes inside containers:

- **claude_code** — Anthropic Claude Code CLI
- **cursor_cli** — Cursor AI editor CLI
- **codex** — OpenAI Codex CLI
- **gemini_cli** — Google Gemini CLI

Users configure credentials per runtime. Each runtime supports different models.

---

## 8. Tools

| Field | Description |
|-------|-------------|
| name | Identifier (snake_case) |
| display_name | UI name |
| description | What the tool does (shown to LLM) |
| kind | custom, system, internal, workflow |
| execution_mode | app (Rails, sync) or container (Docker, async) |
| input_schema | JSON Schema for parameters |
| docker_image | For container tools |

**Tool kinds**:
- `custom` — user-created, scoped to Company/Project
- `system` — platform-provided (e.g., web search)
- `internal` — invisible helpers (finish_session, fail_session, read_tool_result)
- `workflow` — auto-injected in workflow steps (mark_sub_step, board_*, meta_*)

### When to Use Tools vs MCP Servers

**Prefer MCP Servers** for external service integrations (APIs, databases, SaaS). MCP is the standard protocol — many servers already exist for popular services.

**Use custom Tools only when** no MCP server exists for the needed functionality. Custom tools run as Docker containers — the recommended approach is:
- Write the tool logic as a compiled binary (Go recommended for small image size and fast startup)
- Package it in a Docker image (`docker_image` field on the tool)
- Define `input_schema` for the parameters the tool accepts

**Important**: Creating custom tools is an advanced operation. The Palad Builder agent should NOT attempt to create tools automatically. Instead, explain to the user what tool is needed, recommend an approach, and let them build it separately. The tool can then be registered via `meta_create_tool` and linked to workflow steps.

---

## 9. Skills

Reusable instruction blocks injected into agent context.

| Field | Description |
|-------|-------------|
| name | Identifier |
| title | Display name |
| content | The actual instructions/knowledge (markdown) |
| kind | internal or custom |

Use skills for: domain knowledge, methodology instructions, reusable guidelines.

---

## 10. MCP Servers

External tool providers via Model Context Protocol.

| Field | Description |
|-------|-------------|
| name | Identifier |
| url | Server endpoint (http/sse) |
| transport | http, sse, stdio |
| command | For stdio transport |
| headers/env | Auth configuration |

---

## 11. Assets

### Project Assets
Files uploaded to the project (documents, templates, data files). Mountable as workflow inputs.

### Workflow Run Assets
Files produced by workflow steps. Each asset tracks which step produced it (`produced_by_step_run_id`).

### Task Assets
Files attached to board tasks. Agents can attach via `board_attach_asset` tool.

---

## 12. Context Building

When a session runs, the platform builds the agent's context from multiple builders:

1. **CriticalRules** — system instructions, mode constraints
2. **AgentRole** — agent persona (from agent.to_system_prompt)
3. **SessionInfo** — session metadata, mode, runtime
4. **Workspace** — file structure and key locations
5. **WorkflowContext** — (workflow only) step instructions, previous outputs
6. **BoardContext** — (board-triggered only) task details
7. **Tools** — available tools with schemas
8. **Resources** — skills, MCP servers, repositories
9. **BmadMethod** — (if enabled) BMAD methodology framework
10. **OutputRules** — output formatting expectations

---

## 13. Agent Runtime Environment

When a workflow step executes, the platform spins up an isolated container with a specific filesystem layout, injected data, and connected services. Understanding this runtime is critical for designing effective workflows.

### Container Filesystem

```
/workspace/                     ← agent working directory
├── outputs/                    ← put all deliverables here (collected after session)
├── assets/                     ← pre-loaded input files (read-only)
│   ├── design-spec.md          ← from workflow base_asset_ids
│   ├── requirements.pdf        ← from workflow_run input_asset_ids
│   └── task-brief.md           ← from board task assets
├── repo/                       ← mounted Git repositories (if mount_repositories: true)
│   └── <repo_name>/            ← shallow clone, default branch
│       └── .git/               ← full git access: branch, commit, push
└── references/                 ← reference docs (Palad Builder sessions only)
```

### Data Sources for Input Assets

Assets arrive from three additive sources (resolved by `SessionConfigResolver`):

| Source | Configured On | When Used |
|--------|---------------|-----------|
| **Workflow base assets** | `workflow.config.base_asset_ids` | Always — shared docs, templates, style guides |
| **Run-time assets** | `workflow_run.input_asset_ids` | Per-run — user-selected files when starting the run |
| **Board task assets** | `board_task.task_assets` | Board-triggered — files attached to the task card |

All three are merged, deduplicated, and downloaded to `/workspace/assets/<folder>/<name>`.

Use `input_asset_specs` on a Step to document what files the step expects (informational, helps the builder and users understand the step's requirements).
Use `output_asset_specs` on a Step to document what files the step produces into `/workspace/outputs/`.

### Repository Mounting & Git Capabilities

When `mount_repositories: true` on a Step:

1. Project repositories are shallow-cloned into `/workspace/repo/<repo_name>/`
2. A GitHub installation token is injected — agent has authenticated git access
3. The agent can:
   - Read and search the entire codebase
   - Create branches, make commits, push changes
   - Create pull requests (via GitHub MCP or CLI tools)
   - The platform can track PR status via `board_create_wait` (waits for CI checks)

Repository resolution for workflow steps:
- First: `workflow_run.repository_ids` (explicit per-run selection)
- Fallback (board-triggered + `inherit_all_project_resources`): all project repositories

**Important**: `mount_repositories` is just a flag on the Step. The actual repositories come from the workflow run or project. If no repositories are configured at project/run level, the flag does nothing.

### MCP Server Connectivity

MCP servers configured on a Step are resolved and connected to the container at startup:

1. **Internal MCP** (`palad-tools`) — always connected. Provides board_*, workflow progress, and session tools.
2. **External MCP servers** — resolved from three additive sources:
   - `workflow.config.base_mcp_server_ids` — always active for this workflow
   - `step.mcp_server_ids` — step-specific servers
   - All project MCP servers (if `inherit_all_project_resources: true`)

Each server's credentials are resolved from Config Items (Secrets & Variables) at runtime. The agent sees them as available MCP tool providers.

### Resource Resolution (Additive Merge)

Tools, Skills, and MCP Servers are resolved identically — additive from three layers:

```
Resolved = Project (if inherit_all) + Workflow base + Step-level
```

This means a Step inherits everything from the workflow and optionally from the entire project, plus its own step-specific resources.

### Inter-Step Data Flow

Steps in a workflow execute sequentially (or in parallel per DAG). Later steps receive context about previous steps:

1. **Previous step summaries** — each completed step's `step_note` and sub-step `data`/`note` are shown in the "Previous Steps" context section. Use `finish_session` with a note to pass structured context forward.
2. **WorkflowRunAssets** — files produced by earlier steps (saved to `/workspace/outputs/`) are collected as `WorkflowRunAsset` records with `produced_by_step_run_id`. These can be referenced by later steps.
3. **Sub-step data** — `mark_sub_step` accepts a `data` hash and `note` string. Both are visible to subsequent steps in the workflow context.
4. **Board task** — all steps in a board-triggered workflow share the same task. Comments, assets, and tags added by step 1 are visible to step 2 via board tools.

### Workflow Config (`workflow.config`)

| Key | Type | Description |
|-----|------|-------------|
| `base_tool_ids` | Array | Tools available to all steps |
| `base_skill_ids` | Array | Skills injected into all steps |
| `base_mcp_server_ids` | Array | MCP servers connected to all steps |
| `base_asset_ids` | Array | Assets loaded for all steps |
| `inherit_all_project_resources` | Boolean | Merge all project-level resources into every step |

---

## 14. Available Agent Tools (in workflow/session context)

### Session Lifecycle
- `finish_session` — signal successful completion (required in non-interactive)
- `fail_session(reason)` — signal failure

### Workflow Progress
- `list_sub_steps` — see expected sub-steps
- `mark_sub_step(id, status)` — report progress (in_progress/completed/skipped)

### Board Interaction
- `board_get_board_info` — board with columns and metadata
- `board_list_tasks` — filter by column, tag, type, assignee
- `board_get_task` — full task details
- `board_update_task` — update title, description, priority, tags
- `board_create_task` — create new task
- `board_move_task` — move task to column
- `board_add_comment` — add comment with tags
- `board_get_comments` — list comments
- `board_attach_asset` — attach file from container
- `board_get_task_assets` — list attached files
- `board_manage_tags` — add/remove tags on tasks or comments
- `board_create_wait` — block auto-trigger until CI/CD completes

### Meta Tools (Palad Builder)
- `meta_create_workflow`, `meta_delete_workflow`, `meta_create_step`, `meta_create_sub_step`
- `meta_create_agent`, `meta_create_tool`, `meta_create_skill`, `meta_create_mcp_server`
- `meta_update_step`, `meta_delete_step`, `meta_reorder_steps`
- `meta_link_resource_to_step` — attach tool/skill/mcp to step
- `meta_list_workflows`, `meta_list_agents`, `meta_list_tools`, `meta_list_skills`
- `meta_get_workflow`, `meta_get_board`, `meta_finalize_workflow`
- `meta_create_board_column`, `meta_update_board_column`, `meta_delete_board_column`, `meta_reorder_board_columns`
- `meta_create_column_binding`, `meta_update_column_binding`, `meta_delete_column_binding`
- `meta_setup_board_from_preset`
