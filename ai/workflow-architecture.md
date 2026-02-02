# Workflow Architecture Design

**Date:** 2026-01-30
**Status:** Approved
**Author:** Artem Petrov + AI Analysis

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Architecture](./architecture.md) | Core architecture decisions, tech stack |
| [PRD](./prd.md) | Product Requirements Document |
| [Implementation Notes](./implementation-notes.md) | Detailed implementation decisions |

---

## Overview

Workflow system architecture for Palad, based on an analysis of the BMAD Method.

---

## 1. Core Concepts

### 1.1 Separation of entities

| Concept | Description |
|-----------|----------|
| **Agent** | LLM configuration (persona, system prompt). Not tied to a workflow |
| **Workflow** | Process definition: steps, inputs, outputs |
| **WorkflowStep** | A single workflow step with instructions |
| **WorkflowRun** | A specific workflow execution |
| **StepRun** | Execution of a single step |
| **Artifact** | File/document with versioning |

### 1.2 Key decisions

- **Agents are separate from Workflows** — an agent is just an LLM configuration, not a workflow entry point
- **Standalone sessions** — a user can work with an agent without a workflow
- **Workflow sessions** — each step = a separate terminal session
- **Simple workspace** — only `input/` (readonly) and `output/` (collect)

---

## 2. Workspace Structure

### 2.1 Directories in the container

```
/workspace/
├── input/              # READONLY — input artifacts
│   ├── prd.md          # Automatically from input_requirements
│   ├── architecture.md # Added by the user manually
│   └── repo/           # GitHub clone (if needed)
│
└── output/             # COLLECT — everything the agent created
    ├── story-1-1.md    # New artifact
    └── architecture.md # Modified copy from input
```

### 2.2 Preparing input artifacts

**Two sources:**

| Source | How it gets in | Example |
|----------|--------------|--------|
| **Auto** | From `step.input_requirements` | PRD, epics — required for the step |
| **Manual** | The user adds it in the UI before starting | "I want to add architecture.md as context" |

**UI at step start:**
```
┌─────────────────────────────────────────┐
│ Start Step: Create User Story           │
├─────────────────────────────────────────┤
│ Required inputs (auto):                  │
│   ✓ prd.md                              │
│   ✓ epics.md                            │
│                                          │
│ Add more context (optional):            │
│   [ ] architecture.md                    │
│   [ ] previous-story.md                  │
│   [+ Add artifact...]                    │
│                                          │
│ [Start Step]                             │
└─────────────────────────────────────────┘
```

### 2.3 Rules for the agent

In the step instructions we specify:

```
- Read from: /workspace/input/
- Save all results to: /workspace/output/
- If you need to modify an existing document, copy it from input to output first
```

### 2.4 Collecting artifacts

On step completion:
1. Collect all files from `/workspace/output/`
2. Upload to S3
3. Create `Artifact` records in the DB
4. If a file with the same name already exists → new version (parent_id)
5. Artifacts are available for subsequent steps (via the same auto/manual mechanism)

---

## 3. Data Model

### 3.1 Core Entities

```ruby
# Workflow definition
class Workflow < ApplicationRecord
  belongs_to :project
  has_many :steps, class_name: 'WorkflowStep', dependent: :destroy
  has_many :runs, class_name: 'WorkflowRun'

  # name: string
  # description: text
  # config: jsonb (additional settings)
end

# Workflow step (definition)
class WorkflowStep < ApplicationRecord
  belongs_to :workflow

  # position: integer
  # name: string
  # instructions: text (instructions for the agent)
  # input_requirements: jsonb — automatically pulled-in artifacts
  #   [{ artifact_type: "prd", required: true },
  #    { artifact_type: "epics", required: true },
  #    { from_previous_step: true }]  # Artifacts from the previous step
  # expected_outputs: jsonb
  #   [{ name_pattern: "*.md", type: "story", required: true, validation: {...} }]
  # allow_non_interactive: boolean (default: false)
end

# Step execution — stores which artifacts were selected
class StepRun < ApplicationRecord
  # ...
  # input_artifact_ids: jsonb — which artifacts were fed as input (auto + manual)
end

# Workflow execution
class WorkflowRun < ApplicationRecord
  belongs_to :workflow
  belongs_to :project
  belongs_to :user
  has_many :step_runs, dependent: :destroy
  has_many :artifacts, through: :step_runs

  # status: enum (pending, running, paused, completed, failed, cancelled)
  # mode: enum (interactive, non_interactive)
  # input_artifact_ids: jsonb (artifacts selected at start)
  # started_at: datetime
  # completed_at: datetime
end

# Step execution
class StepRun < ApplicationRecord
  belongs_to :workflow_run
  belongs_to :workflow_step
  belongs_to :terminal_session, optional: true
  has_many :artifacts

  # status: enum (pending, running, waiting_input, completed, failed, skipped)
  # started_at: datetime
  # completed_at: datetime
  # output: text (logs, terminal output)
  # error_message: text
end

# Artifact (file/document)
class Artifact < ApplicationRecord
  belongs_to :project
  belongs_to :step_run, optional: true  # nil = uploaded manually
  belongs_to :parent, class_name: 'Artifact', optional: true
  has_many :versions, class_name: 'Artifact', foreign_key: :parent_id

  # name: string
  # artifact_type: string (prd, story, architecture, diagram, code, etc.)
  # content_type: string (text/markdown, application/json, image/png, etc.)
  # s3_key: string
  # file_size: integer
  # version: integer (auto-increment within parent chain)
  # provenance: jsonb
  #   { type: 'manual_upload', user_id: X }
  #   { type: 'workflow', workflow_run_id: X, step_run_id: Y, step_name: "..." }
  #   { type: 'github_clone', repo_url: "...", branch: "...", commit: "..." }
end
```

### 3.2 Relationship to existing models

```ruby
# Already exists
class Project < ApplicationRecord
  has_many :workflows
  has_many :artifacts
  has_many :terminal_sessions
end

class TerminalSession < ApplicationRecord
  belongs_to :project
  has_one :step_run  # Link to step execution
end
```

---

## 4. Execution Flow

### 4.1 Starting a Workflow

```
User clicks "Run Workflow"
    │
    ├─→ Select mode (interactive / non-interactive)
    │
    ▼
Create WorkflowRun (status: pending)
    │
    ▼
Start first step (see 4.2)
```

### 4.2 Starting a step

```
Start Step
    │
    ▼
Resolve auto inputs (from step.input_requirements):
    - artifact_type: "prd" → find latest prd in project
    - artifact_type: "epics" → find latest epics
    - from_previous_step: true → outputs of previous StepRun
    │
    ▼
Show UI: "Add more context?" (optional manual artifacts)
    │
    ▼
Create StepRun with input_artifact_ids (auto + manual)
    │
    ▼
Prepare workspace:
    - Mount all input artifacts to /workspace/input/
    │
    ▼
Start terminal session (TerminalSession)
    │
    ▼
StepRun status → running
```

### 4.2 Completing a step

```
Agent completes work / User stops session
    │
    ▼
Collect artifacts from /workspace/output/
    │
    ▼
Validate against expected_outputs
    │
    ├─→ Valid: StepRun status → completed
    │          Create Artifact records
    │          Proceed to next step
    │
    └─→ Invalid (interactive): Show errors, allow retry
    └─→ Invalid (non-interactive): Based on step config
                                   (retry / skip / fail)
```

### 4.3 Interactive vs Non-Interactive

| Mode | Behavior |
|-------|-----------|
| **Interactive** | Waits for user input, shows the terminal, approval after each step |
| **Non-Interactive** | Automatically transitions between steps (if step.allow_non_interactive) |

```
if workflow_run.mode == 'non_interactive' && step.allow_non_interactive
  # Auto-proceed to next step
else
  # Wait for user action (Approve / Retry / Stop)
end
```

---

## 5. Validation

### 5.1 Expected Outputs Schema

```yaml
expected_outputs:
  - name_pattern: "{epic_num}-{story_num}-*.md"
    type: story
    required: true
    validation:
      format: markdown
      required_sections:
        - "## Acceptance Criteria"
        - "## Tasks"
      min_length: 500

  - name_pattern: "*.excalidraw"
    type: diagram
    required: false
```

### 5.2 Validation Process

1. **Existence** — the file exists in output
2. **Naming** — matches the pattern
3. **Structure** — contains required sections (for markdown)
4. **Size** — minimum length

### 5.3 On Validation Failure

```yaml
# Per-step config
on_validation_fail: retry | skip | fail
max_retries: 3
```

---

## 6. GitHub Integration

### 6.1 Repository as Input

```yaml
# In the step's input_requirements
input_requirements:
  - type: github_repo
    required: true
    config:
      repo_url: "{{project.github_repo}}"
      branch: "main"
      sparse_paths: ["src/", "docs/"]  # Optional
      depth: 1  # Shallow clone
```

### 6.2 Clone Process

```ruby
class WorkspacePreparator
  def prepare_github_input(config, project)
    repo_path = "/workspace/input/repo"

    Git.clone(
      config['repo_url'],
      repo_path,
      depth: config['depth'] || 1,
      branch: config['branch'] || 'main',
      credentials: project.github_credentials
    )

    repo_path
  end
end
```

---

## 7. Artifact Versioning

### 7.1 Version Chain

```
Artifact (v1, parent: nil)
    │
    └─→ Artifact (v2, parent: v1)
            │
            └─→ Artifact (v3, parent: v1)  # parent always points to root
```

### 7.2 Version Creation

When collecting artifacts, if a file with the same name already exists in the project:

```ruby
def create_or_version_artifact(file, step_run)
  existing = project.artifacts.find_by(name: file.name, parent_id: nil)

  if existing
    # Create a new version
    Artifact.create!(
      parent: existing,
      version: existing.versions.count + 1,
      # ... remaining fields
    )
  else
    # New artifact
    Artifact.create!(
      version: 1,
      # ...
    )
  end
end
```

---

## 8. Builder (Level 2 - Assisted)

### 8.1 Approach

The agent helps create a workflow via chat, using a tool:

```ruby
# Tool definition
{
  name: "create_workflow",
  description: "Create a new workflow with steps",
  parameters: {
    name: { type: "string", required: true },
    description: { type: "string" },
    steps: {
      type: "array",
      items: {
        name: { type: "string" },
        instructions: { type: "string" },
        input_requirements: { type: "array" },
        expected_outputs: { type: "array" },
        allow_non_interactive: { type: "boolean" }
      }
    }
  }
}
```

### 8.2 Flow

```
User: "I want a workflow for code review"

Agent: "Creating workflow:
- Step 1: Clone repository
- Step 2: Security analysis
- Step 3: Generate report

Save?"

User: "Yes"

Agent: *calls create_workflow tool*
```

---

## 9. Migration Path

### 9.1 From BMAD Files

```ruby
class BmadImporter
  def import_workflow(path)
    yaml = YAML.load_file("#{path}/workflow.yaml")

    workflow = Workflow.create!(
      name: yaml['name'],
      description: yaml['description'],
      config: yaml.except('name', 'description')
    )

    # Import steps if they exist
    import_steps(workflow, path)

    workflow
  end

  def import_steps(workflow, path)
    Dir.glob("#{path}/steps/*.md").sort.each_with_index do |step_file, idx|
      content = File.read(step_file)
      name = File.basename(step_file, '.md')

      workflow.steps.create!(
        position: idx + 1,
        name: name,
        instructions: content
      )
    end
  end
end
```

---

## 10. Prerequisites Detail

### 10.1 Agents

```ruby
class Agent < ApplicationRecord
  belongs_to :company
  belongs_to :project, optional: true  # nil = company-wide

  # name: string
  # title: string (e.g., "Business Analyst")
  # icon: string (emoji)
  # persona: text (system prompt / persona description)
  # communication_style: text
  # principles: text
  # source: enum (bmad_import, custom)
end
```

**Functionality:**
- CRUD via UI
- Import from BMAD files
- Agent selection at session start
- Agent's persona → system prompt for the LLM

---

### 10.2 Tools

```ruby
class Tool < ApplicationRecord
  belongs_to :company

  # name: string (unique identifier)
  # display_name: string
  # description: text
  # input_schema: jsonb (JSON Schema for parameters)
  # docker_image: string
  # docker_command: string (template with {{param}} placeholders)
  # required_secrets: jsonb (array of secret names)
  # timeout_seconds: integer
end
```

**Functionality:**
- CRUD via UI
- Docker image pull/build
- Execution as a Temporal Activity
- Secrets injection

---

### 10.3 MCP Servers

```ruby
class McpServer < ApplicationRecord
  belongs_to :company
  belongs_to :project, optional: true
  has_many :mcp_server_tools
  has_many :tools, through: :mcp_server_tools

  # name: string
  # description: text
  # transport: enum (stdio, http, websocket)
  # config: jsonb (transport-specific config)
  # enabled: boolean
end

class McpServerTool < ApplicationRecord
  belongs_to :mcp_server
  belongs_to :tool

  # exposed_name: string (can rename tool for MCP)
end
```

**Functionality:**
- Configure which tools are exposed via MCP
- MCP server runs alongside agent container
- CLI agents connect to MCP server

---

### 10.4 Session Context (CLI-specific)

Each CLI agent requires its own configuration:

| CLI | Config Location | Required | Context Files |
|-----|-----------------|----------|---------------|
| **Claude Code** | `~/.claude/` | `ANTHROPIC_API_KEY` | `settings.json`, `claude.md` |
| **Cursor CLI** | `~/.cursor/` | Auth tokens | `settings.json`, `.cursorrules` |
| **Gemini CLI** | `~/.config/gemini/` | `GOOGLE_API_KEY` | config files |
| **Codex** | `~/.codex/` | `OPENAI_API_KEY` | config files |

```ruby
class SessionContextConfig < ApplicationRecord
  belongs_to :company

  # agent_type: enum (claude_code, cursor_cli, gemini_cli, codex)
  # config_files: jsonb
  #   {
  #     "~/.claude/settings.json": "{ ... }",
  #     "~/.claude/claude.md": "content..."
  #   }
  # env_vars: jsonb
  #   { "ANTHROPIC_API_KEY": "secret:anthropic_key" }  # reference to Secret
  # mcp_servers: array of McpServer IDs to connect
end
```

**At session start:**
1. Load `SessionContextConfig` for selected `agent_type`
2. Resolve secrets → actual values
3. Write config files to container
4. Set environment variables
5. Connect MCP servers

```ruby
class SessionPreparator
  def prepare(terminal_session)
    config = SessionContextConfig.find_by(
      company: terminal_session.user.company,
      agent_type: terminal_session.agent_type
    )

    # Write config files
    config.config_files.each do |path, content|
      write_to_container(terminal_session, path, content)
    end

    # Set env vars (with secret resolution)
    config.env_vars.each do |name, value|
      resolved = resolve_secret_reference(value)
      set_env_var(terminal_session, name, resolved)
    end

    # Connect MCP servers
    config.mcp_servers.each do |mcp_server|
      connect_mcp(terminal_session, mcp_server)
    end
  end
end
```

---

## 11. Open Questions — Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Tool calling | ✅ MCP servers |
| 2 | MCP integration | ✅ Yes, the primary mechanism |
| 3 | Parallel steps | ❌ Not for now — sequential only |
| 4 | Branching | ❌ Not needed. The UI should show step status (done/running/pending + who started it) |
| 5 | Templates | ✅ Yes, needed. Like in BMAD (template.md for output documents) |
| 6 | MCP server lifecycle | ✅ Per-session — the MCP server is brought up together with the session |
| 7 | Custom tools via MCP | ✅ Yes, the user creates tools (project/company scope), code in any language in Docker + secrets |
| 8 | Prompt injection | 🔬 Research needed — each CLI has its own mechanism |

---

### 11.1 Prompt Injection Research (TODO)

| CLI | Config File | What to research |
|-----|-------------|------------------|
| **Claude Code** | `claude.md` | Main instructions + per-step instructions? Or everything in claude.md? |
| **Cursor CLI** | `.cursorrules`, `rules/*.mdc` | Rules format, how they are connected |
| **Gemini CLI** | ? | How to inject system prompts |
| **Codex** | ? | How to inject system prompts |

**Action:** Do research on each CLI — which files, formats, how to inject custom prompts.

---

### 11.2 WorkflowRun UI — Step Status Display

```
┌─────────────────────────────────────────────────────────────────┐
│ Workflow Run: Create PRD                                         │
│ Started by: Artem • 2026-01-30 14:30                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ● Step 1: Discovery          ✅ Completed                      │
│    └─ by Artem • 15 min • 3 artifacts                           │
│                                                                  │
│  ● Step 2: Vision             ✅ Completed                      │
│    └─ by Artem • 10 min • 1 artifact                            │
│                                                                  │
│  ● Step 3: Users              🔄 Running                        │
│    └─ by Artem • started 5 min ago                              │
│    └─ [Open Terminal]                                            │
│                                                                  │
│  ○ Step 4: Metrics            ⏳ Pending                        │
│                                                                  │
│  ○ Step 5: Scope              ⏳ Pending                        │
│                                                                  │
│  ○ Step 6: Complete           ⏳ Pending                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

### 11.3 Tools Scope

```ruby
class Tool < ApplicationRecord
  belongs_to :company
  belongs_to :project, optional: true  # nil = company-wide

  # When receiving tools for a session:
  # 1. Project tools
  # 2. Company tools (if there is no conflict by name)
  # Merge: project tools override company tools with same name
end
```

```ruby
def tools_for_session(session)
  company_tools = session.user.company.tools.where(project: nil)
  project_tools = session.project.tools

  # Project tools take precedence
  (company_tools + project_tools).uniq(&:name)
end
```

---

## 11. Implementation Priority

### Prerequisites (before Workflows)

Workflows depend on the base agent infrastructure:

| # | Component | Description | Why needed |
|---|-----------|-------------|------------|
| **P1** | **Agents** | Agent CRUD, persona, system prompts | Workflow steps are executed by agents |
| **P2** | **Tools** | Tool definitions, Docker images | Agents use tools |
| **P3** | **MCP Servers** | MCP configuration, tool distribution | Standard way of delivering tools |
| **P4** | **Session Context** | Context for different CLIs (Cursor, Gemini, Claude Code, Codex) | Each CLI requires its own configuration |

### Dependency Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                         WORKFLOWS                                │
│  (WorkflowRun, StepRun, Artifact collection)                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SESSION CONTEXT                             │
│  - Claude Code: ~/.claude/, ANTHROPIC_API_KEY                   │
│  - Cursor CLI: ~/.cursor/, auth tokens                          │
│  - Gemini CLI: ~/.config/gemini/, GOOGLE_API_KEY                │
│  - Codex: ~/.codex/, OPENAI_API_KEY                             │
│  - Custom prompts injection                                      │
│  - MCP server connections                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MCP SERVERS                              │
│  - MCP server definitions (company/project level)               │
│  - Tool exposure via MCP protocol                               │
│  - Connection management                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                           TOOLS                                  │
│  - Tool definitions (name, description, schema)                 │
│  - Docker images for execution                                  │
│  - Required secrets mapping                                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          AGENTS                                  │
│  - Agent definitions (persona, system prompt)                   │
│  - Company/project scoped                                        │
│  - Agent selection for sessions                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ depends on
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SECRETS MANAGEMENT                            │
│  - API keys (Anthropic, OpenAI, Google)                         │
│  - Integration credentials (GitHub, Linear)                     │
│  - Encrypted storage                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Phases (Updated)

| Phase | Scope | Deliverable |
|-------|-------|-------------|
| **Phase 0** | Secrets Management | Encrypted secrets CRUD, injection into containers |
| **Phase 1** | Agents | Agent model, CRUD, selection in sessions |
| **Phase 2** | Tools | Tool definitions, Docker execution, Temporal activities |
| **Phase 3** | MCP Servers | MCP config, tool exposure, connection to CLI agents |
| **Phase 4** | Session Context | Per-CLI configuration, credentials injection, MCP wiring |
| **Phase 5** | Workflows Core | Workflow/Step CRUD, WorkflowRun/StepRun |
| **Phase 6** | Artifacts | Collection, versioning, S3, validation |
| **Phase 7** | Advanced | Builder, non-interactive, GitHub integration |

---

_Document generated from brainstorm session 2026-01-30_
