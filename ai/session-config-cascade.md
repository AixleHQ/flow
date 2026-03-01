# Session Config Cascade — Architecture Design

**Date:** 2026-02-28
**Status:** Draft
**Author:** Artem Petrov + AI Analysis

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Workflow Architecture](./workflow-architecture.md) | Workflow, Steps, SubSteps, execution model |
| [Session Context Constructor](./session-context-constructor.md) | How context is assembled for agent sessions |
| [Architecture](./architecture.md) | Core architecture decisions |

---

## 1. Problem Statement

Starting a session requires a set of parameters: agent_runtime, tools, skills, mcp_servers, repositories, assets. Right now these parameters are set in different places and it is unclear how they combine — especially on an auto-trigger of a workflow from the board.

---

## 2. Core Principle: Additive, Not Override

### Session-centric API

A single entry point: `SessionConfigResolver.resolve(session)`. The input is a `TerminalSession`; the resolver itself determines the session type (standalone / workflow / board-triggered) and assembles the config.

```ruby
config = SessionConfigResolver.resolve(session)
# => { session_type: :workflow, agent_runtime: "claude_code", tool_ids: [...], ... }
```

### Additivity

Resources **accumulate** from top to bottom. Each level **adds to** but does not overwrite.

```
Workflow session resources = Step resources
                           + Workflow base resources
                           + Workflow Run inputs (user at start)
                           + Board Task assets (on auto-trigger)

Standalone session resources = what the user selected in the UI
```

The only **non-additive** value is `agent_runtime`. It is scalar and is resolved by priority.

---

## 3. Where each value comes from

### 3.1 agent_runtime

A scalar value. Resolved by priority (first non-empty wins):

```
1. step.required_agent_runtime     ← the step REQUIRES a specific runtime
2. workflow_run.agent_runtime      ← user override on a manual launch
3. user.default_agent_credential   ← default from Profile
4. "claude_code"                   ← hardcoded fallback
```

**A step may require a specific runtime.** For example, the "Code Generation" step may require `claude_code`, because only it supports the needed capabilities. If `step.required_agent_runtime` is set — it overrides everything else.

**New field on Step:** `required_agent_runtime` (string, nullable). If set, it is used unconditionally.

On the **Profile** page the user sees the list of their AgentCredentials. One of them is marked as **default** — by default this is the last one added.

**New field on User:** `default_agent_credential_id` (references, nullable). When a new `AgentCredential` is created, it is automatically set as default.

```ruby
def resolve_agent_runtime
  step&.required_agent_runtime.presence ||
    workflow_run&.agent_runtime.presence ||
    user.default_agent_credential&.runtime ||
    user.agent_credentials.order(created_at: :desc).first&.runtime ||
    "claude_code"
end
```

### 3.2 configured_agent (persona)

Scalar. Set on the Step.

```
configured_agent = step.agent_id
```

Each step knows which persona it needs (Architect, PM, Analyst). Not inherited, not accumulated.

### 3.3 tools, skills, mcp_servers — additive

Each level **adds** its own. The final set is the union.

```ruby
def resolve_tool_ids(workflow, step)
  (workflow.base_tool_ids + step.tool_ids).uniq
end

def resolve_skill_ids(workflow, step)
  (workflow.base_skill_ids + step.skill_ids).uniq
end

def resolve_mcp_server_ids(workflow, step)
  (workflow.base_mcp_server_ids + step.mcp_server_ids).uniq
end
```

**Workflow** sets the "base" tools available to all steps (for example, context7 MCP for documentation). **Step** adds step-specific ones (for example, the security_scan tool for the Code Review step).

### 3.4 Workflow: "give everything" mode

A separate flag on Workflow: `inherit_all_project_resources` (boolean, default: false).

If `true` — all of the project's tools, skills, mcp_servers are automatically available in all steps. Step can still add its own on top.

```ruby
def resolve_tool_ids(workflow, step, project)
  base = workflow.inherit_all_project_resources ? project_tool_ids(project) : []
  (base + workflow.base_tool_ids + step.tool_ids).uniq
end
```

### 3.5 repositories

Additive. Step controls this via `mount_repositories` (bool):

```ruby
def resolve_repository_ids(workflow_run, step, project)
  return [] unless step.mount_repositories

  (workflow_run.repository_ids.presence || project.repositories.pluck(:id))
end
```

On a manual workflow launch the user selects repos. On an auto-trigger — all of the project's repos are taken.

### 3.6 input_assets — additive

Three sources, all combined:

```ruby
def resolve_input_asset_ids(workflow, workflow_run, board_task)
  ids = []

  # 1. Workflow-level assets (configured in the workflow builder)
  ids += workflow.base_asset_ids

  # 2. Run-level assets (user selected at manual start)
  ids += workflow_run.input_asset_ids || []

  # 3. Board task assets (on auto-trigger)
  if board_task.present?
    ids += board_task.task_assets.pluck(:asset_id)
  end

  ids.uniq
end
```

---

## 4. Full table

| Parameter | Type | Source | Additivity |
|----------|-----|----------|-------------|
| `agent_runtime` | scalar | Step required → WorkflowRun override → User default | No, priority chain |
| `configured_agent` | scalar | Step.agent_id | No, scalar |
| `tools` | set | Workflow.base + Step + (Project if inherit_all) | Yes, union |
| `skills` | set | Workflow.base + Step + (Project if inherit_all) | Yes, union |
| `mcp_servers` | set | Workflow.base + Step + (Project if inherit_all) | Yes, union |
| `repositories` | set | WorkflowRun (user) or Project (fallback) | No, fallback |
| `input_assets` | set | Workflow.base + WorkflowRun (user) + BoardTask | Yes, union |
| `mode` | scalar | WorkflowRun.mode + Step.allow_non_interactive | No, resolved |

---

## 5. SessionConfigResolver

A single entry point — `TerminalSession`. The resolver itself determines the session type and assembles the config.

```ruby
class SessionConfigResolver
  TYPES = %i[workflow standalone].freeze

  attr_reader :session

  def self.resolve(session)
    new(session).resolve
  end

  def initialize(session)
    @session = session
  end

  def resolve
    {
      session_type: session_type,
      agent_runtime: resolve_agent_runtime,
      configured_agent_id: step&.agent_id,
      tool_ids: resolve_tool_ids,
      skill_ids: resolve_skill_ids,
      mcp_server_ids: resolve_mcp_server_ids,
      repository_ids: resolve_repository_ids,
      input_asset_ids: resolve_input_asset_ids,
      mode: resolve_mode
    }
  end

  private

  # --- Session navigation (same pattern as SessionContextConstructor) ---

  def user            = session.user
  def project         = session.project
  def step_run        = session.step_run
  def workflow_run    = step_run&.workflow_run
  def workflow        = workflow_run&.workflow
  def step            = step_run&.step
  def board_task      = workflow_run&.board_task

  def workflow_session? = step_run.present?
  def board_triggered?  = board_task.present?

  def session_type
    if board_triggered?
      :board_triggered
    elsif workflow_session?
      :workflow
    else
      :standalone
    end
  end

  # --- Scalar ---

  def resolve_agent_runtime
    return session.agent_runtime if standalone_session?

    step&.required_agent_runtime.presence ||
      workflow_run&.agent_runtime.presence ||
      user.default_agent_credential&.runtime ||
      user.agent_credentials.order(created_at: :desc).first&.runtime ||
      "claude_code"
  end

  def resolve_mode
    return session.mode unless workflow_session?

    case workflow_run.mode
    when "non_interactive" then "non_interactive"
    when "interactive" then "interactive"
    else
      step&.allow_non_interactive ? "non_interactive" : "interactive"
    end
  end

  # --- Additive sets ---

  def resolve_tool_ids
    return session.tool_ids unless workflow_session?

    ids = []
    ids += project_tool_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_tool_ids || []
    ids += step&.tool_ids || []
    ids.uniq
  end

  def resolve_skill_ids
    return session.skill_ids unless workflow_session?

    ids = []
    ids += project_skill_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_skill_ids || []
    ids += step&.skill_ids || []
    ids.uniq
  end

  def resolve_mcp_server_ids
    return session.mcp_server_ids unless workflow_session?

    ids = []
    ids += project_mcp_server_ids if workflow&.inherit_all_project_resources
    ids += workflow&.base_mcp_server_ids || []
    ids += step&.mcp_server_ids || []
    ids.uniq
  end

  def resolve_input_asset_ids
    ids = []

    if workflow_session?
      ids += workflow&.base_asset_ids || []
      ids += workflow_run&.input_asset_ids || []
    else
      ids += session.input_asset_ids || []
    end

    ids += board_task_asset_ids
    ids.uniq
  end

  def resolve_repository_ids
    if workflow_session?
      return [] unless step&.mount_repositories
      workflow_run&.repository_ids.presence || project_repository_ids
    else
      session.repository_ids.presence || []
    end
  end

  # --- Helpers ---

  def standalone_session? = !workflow_session?

  def project_tool_ids
    Tool.merged_for_project(project).pluck(:id)
  end

  def project_skill_ids
    Skill.merged_for_project(project).pluck(:id)
  end

  def project_mcp_server_ids
    MCPServer.merged_for_project(project).pluck(:id)
  end

  def project_repository_ids
    project.repositories.pluck(:id)
  end

  def board_task_asset_ids
    return [] unless board_task.present?
    board_task.task_assets.pluck(:asset_id)
  end
end
```

---

## 6. Required changes

### 6.1 User — default agent credential

```ruby
# New field:
# default_agent_credential_id: references (nullable)
#
# When creating an AgentCredential:
# after_create :set_as_default_if_first_or_latest
```

Configured on the **Profile** page. By default — the last added `AgentCredential`. The user can switch the default in the UI.

### 6.2 Workflow — base resources + inherit_all

We use the existing `config` jsonb:

```ruby
class Workflow < ApplicationRecord
  def base_tool_ids
    config&.dig("base_tool_ids") || []
  end

  def base_skill_ids
    config&.dig("base_skill_ids") || []
  end

  def base_mcp_server_ids
    config&.dig("base_mcp_server_ids") || []
  end

  def base_asset_ids
    config&.dig("base_asset_ids") || []
  end

  def inherit_all_project_resources
    config&.dig("inherit_all_project_resources") || false
  end
end
```

### 6.3 LaunchStepSessionActivity — use the Resolver

```ruby
# Now:
agent_type = workflow_run.agent_runtime || "claude_code"
# tools, skills, mcp_servers are taken only from the step

# After:
config = SessionConfigResolver.resolve(session)
# config[:tool_ids] = workflow.base + step (union)
# config[:session_type] = :workflow / :board_triggered / :standalone
```

---

## 7. Examples

### Example 1: Manual workflow launch

```
Input: session (session.step_run → workflow_run → workflow)

User: default_agent_credential.runtime = "gemini_cli"
User selects at start: repos=[1,3], assets=[10], does not change runtime

Workflow:
  inherit_all: false
  base_tools: [context7_id]
  base_assets: [template_id]

Step 1 (Create Architecture):
  agent: Architect
  tools: [cloc_id, security_scan_id]
  skills: [arch_skill_id]

SessionConfigResolver.resolve(session):
  session_type      = :workflow
  agent_runtime     = gemini_cli       (user default credential)
  configured_agent  = Architect        (step)
  tools             = [context7, cloc, security_scan]  (workflow + step)
  skills            = [arch_skill]     (step)
  repositories      = [1, 3]          (user selected at run start)
  input_assets      = [template, 10]  (workflow base + user run)
```

### Example 2: Step requires a specific runtime

```
Input: session (session.step_run → workflow_run → workflow)

User: default_agent_credential.runtime = "gemini_cli"

Workflow: (the same as in example 1)

Step 2 (Code Generation):
  agent: Developer
  required_agent_runtime: "claude_code"   ← the step REQUIRES claude_code
  tools: [code_gen_id]

SessionConfigResolver.resolve(session):
  session_type      = :workflow
  agent_runtime     = claude_code        (step required — overrides user default)
  configured_agent  = Developer          (step)
  tools             = [context7, code_gen]  (workflow + step)
```

### Example 3: Auto-trigger from the board

```
Input: session (session.step_run → workflow_run → board_task)

User (task assignee): default_agent_credential.runtime = "claude_code"
Board task: assets attached: [doc.pdf, spec.md]

Workflow:
  inherit_all: true     ← all project resources are available
  base_tools: []
  base_assets: []

Step 1 (Tech Design):
  agent: Architect
  tools: [security_scan_id]

SessionConfigResolver.resolve(session):
  session_type      = :board_triggered
  agent_runtime     = claude_code             (user default credential)
  configured_agent  = Architect               (step)
  tools             = [all project tools] + [security_scan]  (inherit_all + step)
  skills            = [all project skills]    (inherit_all)
  mcp_servers       = [all project mcp]       (inherit_all)
  repositories      = [all project repos]     (project fallback)
  input_assets      = [doc.pdf, spec.md]      (board task assets)
```

### Example 4: Standalone session

```
Input: session (session.step_run = nil)

On standalone start, the UI populates user.default_agent_credential.runtime
into the agent_runtime field. The user can change it, but by default it is their default.

The user selects tools, repos, assets. Runtime is already prefilled.

SessionConfigResolver.resolve(session):
  session_type      = :standalone
  agent_runtime     = gemini_cli            (session.agent_runtime — prefilled default, user did not change)
  configured_agent  = nil
  tools             = [tool1, tool2]         (session.tool_ids — selected by user)
  skills            = [skill1]               (session.skill_ids — selected by user)
  repositories      = [repo1]               (session.repository_ids — selected by user)
  input_assets      = [asset1]              (session.input_asset_ids — selected by user)
```

---

## 8. UI: Workflow Builder

In the Workflow Builder, the "Base Resources" section:

```
┌─ Workflow: Code Review Pipeline ──────────────────┐
│                                                    │
│  ☐ Inherit all project resources                   │
│                                                    │
│  Base Resources (available in all steps)            │
│  Tools:       [context7]  [+ Add]                  │
│  Skills:      []  [+ Add]                          │
│  MCP Servers: [context7]  [+ Add]                  │
│  Assets:      [code-standards.md]  [+ Add]         │
│                                                    │
│  Steps                                             │
│  1. Security Scan  [CodeAnalyst]                   │
│     + tools: [security_scan]                       │
│     Effective: context7, security_scan             │
│                                                    │
│  2. Architecture Review  [Architect]               │
│     + tools: [cloc]                                │
│     Effective: context7, cloc                      │
│                                                    │
└────────────────────────────────────────────────────┘
```

"Effective" — a hint that shows the resulting set (base + step).

---

## 9. Traceability

A `config_resolution` section is added to `ContextResult.to_json_hash`:

```json
{
  "config_resolution": {
    "agent_runtime": "claude_code",
    "agent_runtime_source": "user_default",
    "tools": {
      "from_project_inherit_all": [1, 2, 3],
      "from_workflow_base": [4],
      "from_step": [5, 6],
      "resolved": [1, 2, 3, 4, 5, 6]
    },
    "input_assets": {
      "from_workflow_base": [10],
      "from_run_user": [],
      "from_board_task": [11, 12],
      "resolved": [10, 11, 12]
    }
  }
}
```

---

## 10. Open Questions

| # | Question | Leaning |
|---|----------|---------|
| 1 | `inherit_all` — a single flag or per-resource (inherit_all_tools, inherit_all_skills...)? | A single flag — simpler. If you need all, you usually need all |
| 2 | Can a step **exclude** a tool from the workflow base? | No. Additive = add only. If needed — do not put it in the base |
| 3 | Are repos also additive or fallback? | Fallback: user run repos or project repos. The step only toggles on/off via mount_repositories |
| 4 | Board task description → an addition to step instructions? | A separate story, not in scope. For now the task description lives in the board-context section (Epic 27) |

---

_Document generated 2026-02-28_
