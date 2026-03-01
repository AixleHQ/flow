# Epic 29: Session Config Resolver

> Session-centric service that resolves the full session configuration (agent_runtime, tools, skills, mcp_servers, repositories, assets) by additively merging resources from Step, Workflow, WorkflowRun, and BoardTask — single entry point: `SessionConfigResolver.resolve(session)`.

**Phase:** 17 (Depends on: Epic 16 Config Normalization, Epic 12 Workflows)

**Design Document:** [Session Config Cascade](../session-config-cascade.md)

**User Outcome:** Session resources are assembled consistently regardless of how the session was triggered (standalone, workflow, board auto-trigger). Step-level and workflow-level tools/skills/assets are additively merged — nothing is lost. Steps can require a specific agent runtime when needed. Config resolution is traceable via JSON metadata.

**FRs Covered:** FR-CC1, FR-CC2, FR-CC3, FR-CC5, FR-CC6

---

## Problem

Session configuration parameters (agent_runtime, tools, skills, mcp_servers, repositories, assets) are currently resolved ad-hoc in `LaunchStepSessionActivity` and `WorkflowStepStrategy`. Workflow-level base resources don't exist — steps can only bring their own. There's no concept of "inherit all project resources" for auto-triggered workflows. The agent runtime resolution is hardcoded and doesn't account for step-specific requirements.

This epic creates a single `SessionConfigResolver` with a session-centric API that additively merges resources from all levels and provides deterministic, traceable config resolution.

---

## Stories

### Story 29.1: SessionConfigResolver Core with Session Type Detection

**As a** system,
**I want** a SessionConfigResolver that accepts a TerminalSession and determines the session type (standalone / workflow / board_triggered),
**So that** config resolution logic has a single entry point and can branch based on session origin.

**Acceptance Criteria:**

**Given** a TerminalSession with `step_run` present and `workflow_run.board_task` present
**When** `SessionConfigResolver.resolve(session)` is called
**Then** result includes `session_type: :board_triggered`

**Given** a TerminalSession with `step_run` present and no `board_task`
**When** resolver runs
**Then** result includes `session_type: :workflow`

**Given** a TerminalSession with no `step_run`
**When** resolver runs
**Then** result includes `session_type: :standalone`

**Given** a standalone session
**When** resolver runs
**Then** result returns session's own values directly (tool_ids, skill_ids, mcp_server_ids, repository_ids, input_asset_ids, agent_runtime, mode)

**Technical notes:**
- `SessionConfigResolver` — service object with `self.resolve(session)` class method
- Navigation helpers mirror SessionContextConstructor: `user`, `project`, `step_run`, `workflow_run`, `workflow`, `step`, `board_task`
- Standalone sessions pass through values directly — resolver doesn't alter them
- File: `app/services/session_config_resolver.rb`

---

### Story 29.2: Additive Resource Resolution (Tools, Skills, MCP Servers)

**As a** system,
**I want** the resolver to additively merge tools, skills, and mcp_servers from Workflow base + Step,
**So that** workflow-level base resources are available in every step alongside step-specific ones.

**Acceptance Criteria:**

**Given** a Workflow with `config.base_tool_ids = [1, 2]` and Step with `tool_ids = [2, 3]`
**When** resolver resolves tool_ids
**Then** result is `[1, 2, 3]` (union, deduplicated)

**Given** a Workflow with `config.base_skill_ids = [10]` and Step with `skill_ids = [11]`
**When** resolver resolves skill_ids
**Then** result is `[10, 11]`

**Given** a Workflow with `config.base_mcp_server_ids = [20]` and Step with `mcp_server_ids = []`
**When** resolver resolves mcp_server_ids
**Then** result is `[20]` (workflow base still present even when step has none)

**Given** a standalone session with `tool_ids = [5, 6]`
**When** resolver resolves tool_ids
**Then** result is `[5, 6]` (pass-through, no merging)

**Technical notes:**
- Workflow model gets helper methods: `base_tool_ids`, `base_skill_ids`, `base_mcp_server_ids` reading from `config` jsonb
- Pattern: `(workflow.base_X_ids + step.X_ids).uniq`

---

### Story 29.3: Workflow `inherit_all_project_resources` Flag

**As a** system,
**I want** a Workflow flag `inherit_all_project_resources` that includes all project-level tools, skills, and MCP servers,
**So that** auto-triggered workflows from the board can have full access to project resources without manually configuring each.

**Acceptance Criteria:**

**Given** a Workflow with `config.inherit_all_project_resources = true` and a Project with tools [1..5]
**When** resolver resolves tool_ids
**Then** result includes all project tools plus workflow base plus step tools

**Given** a Workflow with `config.inherit_all_project_resources = false`
**When** resolver resolves tool_ids
**Then** result includes only workflow base + step tools (no project-level injection)

**Given** a Workflow with `inherit_all_project_resources = true` and Step with additional tools [6]
**When** resolver resolves
**Then** step tools are added on top of project tools (additive)

**Technical notes:**
- Workflow model: `def inherit_all_project_resources = config&.dig("inherit_all_project_resources") || false`
- Uses existing scopes: `Tool.merged_for_project`, `Skill.merged_for_project`, `MCPServer.merged_for_project`

---

### Story 29.4: Input Assets Resolution with Board Task Assets

**As a** system,
**I want** input assets to be additively merged from Workflow base assets + WorkflowRun user inputs + BoardTask assets,
**So that** board task attachments automatically become available in the session alongside other configured assets.

**Acceptance Criteria:**

**Given** a Workflow with `config.base_asset_ids = [100]`, WorkflowRun with `input_asset_ids = [101]`, BoardTask with task_assets pointing to asset_ids `[102, 103]`
**When** resolver resolves input_asset_ids
**Then** result is `[100, 101, 102, 103]`

**Given** a workflow session without board_task
**When** resolver resolves input_asset_ids
**Then** result is `[100, 101]` (no board contribution)

**Given** a standalone session with `input_asset_ids = [200]`
**When** resolver resolves
**Then** result is `[200]` (pass-through)

**Technical notes:**
- Workflow model: `def base_asset_ids = config&.dig("base_asset_ids") || []`
- Board task assets via existing `board_task.task_assets.pluck(:asset_id)`

---

### Story 29.5: Step `required_agent_runtime` Field

**As a** workflow designer,
**I want** to mark a step as requiring a specific agent runtime,
**So that** certain steps always run on the correct agent regardless of user preferences.

**Acceptance Criteria:**

**Given** a Step with `required_agent_runtime = "claude_code"` and User default credential runtime = "gemini_cli"
**When** resolver resolves agent_runtime
**Then** result is `"claude_code"` (step requirement overrides user default)

**Given** a Step with `required_agent_runtime = nil` and WorkflowRun with `agent_runtime = "gemini_cli"`
**When** resolver resolves agent_runtime
**Then** result is `"gemini_cli"` (workflow run override)

**Given** a Step with `required_agent_runtime = nil`, WorkflowRun with `agent_runtime = nil`, User with `default_agent_credential.runtime = "claude_code"`
**When** resolver resolves
**Then** result is `"claude_code"` (user default)

**Given** no step requirement, no run override, no user credential
**When** resolver resolves
**Then** result is `"claude_code"` (hardcoded fallback)

**Technical notes:**
- Migration: `add_column :steps, :required_agent_runtime, :string, null: true`
- Priority chain: step.required → run.agent_runtime → user.default_credential.runtime → user.latest_credential.runtime → "claude_code"
- Workflow Builder UI for this field is covered in Epic 31

---

### Story 29.6: Integrate Resolver into LaunchStepSessionActivity

**As a** system,
**I want** `LaunchStepSessionActivity` to use `SessionConfigResolver` for determining session configuration,
**So that** the centralized resolver replaces ad-hoc config assembly in the workflow execution path.

**Acceptance Criteria:**

**Given** a workflow step session being launched
**When** `LaunchStepSessionActivity` creates the TerminalSession
**Then** it uses `SessionConfigResolver.resolve(session)` to determine agent_runtime, tool_ids, skill_ids, mcp_server_ids, repository_ids, input_asset_ids

**Given** existing workflow runs with current config resolution
**When** the resolver is integrated
**Then** all existing tests pass — behavioral backward compatibility maintained

**Technical notes:**
- Replace direct `workflow_run.agent_runtime || "claude_code"` with resolver
- Replace step-only tool_ids with resolver's additive resolution
- File: `app/services/launch_step_session_activity.rb` (or wherever session creation happens for workflow steps)

---

### Story 29.7: Config Resolution in ContextResult Traceability

**As a** developer,
**I want** a `config_resolution` section in the ContextResult JSON metadata,
**So that** I can trace exactly where each resource came from (project inherit, workflow base, step, board task).

**Acceptance Criteria:**

**Given** a workflow session resolved via `SessionConfigResolver`
**When** `ContextResult.to_json_hash` is called
**Then** result includes a `config_resolution` key with:
  - `agent_runtime` value and `agent_runtime_source` ("step_required" / "run_override" / "user_default" / "fallback")
  - `tools` breakdown: `from_project_inherit_all`, `from_workflow_base`, `from_step`, `resolved`
  - `input_assets` breakdown: `from_workflow_base`, `from_run_user`, `from_board_task`, `resolved`

**Given** a standalone session
**When** traceability runs
**Then** `config_resolution.session_type` is `"standalone"` and all resources show single source

**Technical notes:**
- Resolver returns structured breakdown alongside flat resolved values
- `ContextResult` (from Epic 25) consumes this breakdown
- Depends on Epic 25 Story 25.5 (ContextResult) — can be implemented after or in parallel

---

## Dependency Graph

```
Story 29.1 (Core + session type detection)
    │
    ├──→ Story 29.2 (Additive tools/skills/mcp)
    │        │
    │        └──→ Story 29.3 (inherit_all flag)
    │
    ├──→ Story 29.4 (Input assets + board task)
    │
    └──→ Story 29.5 (Step required_agent_runtime)
             │
             └──→ Story 29.6 (Integration into LaunchStepSessionActivity)
                      │
                      └──→ Story 29.7 (Traceability in ContextResult)
```

---

## Implementation Notes

- Core principle: **additive, not override** — resources accumulate, never replace
- `agent_runtime` is the only scalar with a priority chain (step required > run > user > fallback)
- Resolver mirrors SessionContextConstructor pattern: takes session, navigates associations internally
- Workflow `config` jsonb is reused for base resource IDs — no new columns on Workflow (except `inherit_all_project_resources` in config)
- Step gets one new column: `required_agent_runtime` (string, nullable)
- Standalone sessions are pass-through — resolver doesn't alter user selections
- Testing: each resolution method tested in isolation; integration test verifies full resolve output for all 3 session types
