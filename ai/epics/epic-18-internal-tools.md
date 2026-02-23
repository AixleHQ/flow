# Epic 18: Internal Tools

System-provided tools executed as Ruby classes (not Docker containers), available to all agent sessions via MCP.

**Phase:** 11 (Depends on: Epic 6 Tools, Epic 8 Container Execution, Epic 11 Workflows)

**User Outcome:** Agents can call platform-provided tools (workflow progress tracking, Code Climate analysis) alongside custom Docker-based tools, through a unified MCP interface.

---

## Problem

Internal tools (`kind: internal`) are declared in the Tool model but have no execution path. `Tool#execute` always goes through `ToolExecutionStrategy` which rejects non-custom tools. The MCP dynamic tools patch (`action_mcp_dynamic_tools.rb`) routes all `tools/call` through the same Docker path. `TerminalSession#available_tools` only returns custom tools — internal tools never appear in `tools/list`.

---

## Architecture

### Routing

```
tools/call(tool_name, arguments)
    │
    ├── tool.custom?  → ToolExecutionStrategy → Docker container (existing)
    │
    └── tool.internal? → InternalToolExecutor → Ruby handler class
                              │
                              ├── finds handler: InternalTools::{ToolName}
                              ├── validates input against tool.input_schema
                              ├── calls handler.execute(params, session)
                              └── returns { exit_code:, stdout:, stderr: }
```

### Handler Convention

```
app/services/internal_tools/
├── base.rb                    # Base class with validation, error handling
├── list_sub_steps.rb          # Workflow: list sub-steps
├── mark_sub_step.rb           # Workflow: update sub-step progress
├── write_step_note.rb         # Workflow: save step note
└── code_climate.rb            # Docker-in-Docker: Code Climate analysis
```

Each handler is a plain Ruby class:

```ruby
module InternalTools
  class Base
    attr_reader :params, :session

    def initialize(params:, session:)
      @params = params
      @session = session
    end

    def execute
      raise NotImplementedError
    end

    private

    def project = session.project
    def step_run = session.step_run
    def workflow_run = step_run&.workflow_run
    def success(text) = { exit_code: 0, stdout: text, stderr: "" }
    def error(text) = { exit_code: 1, stdout: "", stderr: text }
  end
end
```

### Code Climate Strategy

`code_climate` is special — it needs to run a Docker container with the repository bind-mounted. Uses a new `CodeClimateStrategy < BaseStrategy` (similar to `ToolExecutionStrategy`) with:
- Image: `codeclimate/codeclimate`
- Bind mount: repo path → `/code`
- Docker socket mount (Code Climate spawns engine containers)
- Shared `/tmp/cc` for intermediate results

```ruby
module InternalTools
  class CodeClimate < Base
    def execute
      repo = project.repositories.find(params[:repository_id])
      # Clone repo to temp dir if needed, or reuse cached clone
      strategy = ContainerStrategies::CodeClimateStrategy.new(
        repo: repo, engines: params[:engines], format: params[:format] || "json"
      )
      result = strategy.run
      success(result[:stdout])
    end
  end
end
```

---

## Stories

### Story 18.1: Internal Tool Execution Router

**As a** system,
**I want** to route internal tool calls to Ruby handler classes,
**So that** internal and custom tools work through the same MCP interface.

**Acceptance Criteria:**
- `Tool#execute` checks `kind` and routes:
  - `custom` → existing `ToolExecutionStrategy` (no changes)
  - `internal` → `InternalToolExecutor.execute(tool, params, session)`
- `InternalToolExecutor` resolves handler class by tool name convention: `InternalTools::{tool.name.classify}`
- Handler receives `params` + `session`, returns `{ exit_code:, stdout:, stderr: }`
- Input validated against `tool.input_schema` before handler call
- Errors caught and returned as `{ exit_code: 1, stderr: error_message }`
- `InternalTools::Base` provides shared helpers (project, step_run, success/error)

**Technical notes:**
- `Tool#execute` signature gains `session:` keyword (optional, for internal tools)
- `action_mcp_dynamic_tools.rb` passes session to `tool.execute(parameters:, project:, session:)`
- `ToolExecutionStrategy` ignores `session:` — no breaking change

### Story 18.2: Internal Tools Visible in MCP tools/list

**As an** agent in a container,
**I want** to see internal tools in the MCP `tools/list` response,
**So that** I can discover and call them.

**Acceptance Criteria:**
- `TerminalSession#available_tools` includes internal tools
- Internal tools always present regardless of session scope
- `tools/list` returns both internal and custom tools
- Internal tools show `description` and `input_schema` correctly
- Workflow-specific tools (`list_sub_steps`, `mark_sub_step`, `write_step_note`) only visible when `session.step_run` is present (workflow session)

**Technical notes:**
- Update `available_tools` to merge `Tool.internal_tools.enabled` with existing logic
- Add `workflow_only: boolean` field to Tool (default: false) — when true, tool only appears if session has a step_run
- Alternatively: handler can return error if called outside workflow context (simpler, no schema change)

### Story 18.3: list_sub_steps Tool

**As an** agent running a workflow step,
**I want** to list current sub-steps with their statuses,
**So that** I can track progress and know what to work on next.

**Acceptance Criteria:**
- Returns JSON array of sub-step runs for current step
- Each entry: `{ id, position, name, description, status, note, data }`
- Status values: `pending`, `in_progress`, `completed`, `skipped`
- Returns error if called outside workflow context (no step_run)
- No input parameters required

**Tool definition (seed):**
```ruby
Tool.find_or_create_by!(name: "list_sub_steps", kind: :internal) do |t|
  t.display_name = "List Sub-Steps"
  t.description = "List current step's sub-steps with their statuses. Only available during workflow execution."
  t.input_schema = { type: "object", properties: {} }
end
```

### Story 18.4: mark_sub_step Tool

**As an** agent running a workflow step,
**I want** to update a sub-step's status with notes and structured data,
**So that** progress is tracked and data flows to subsequent steps.

**Acceptance Criteria:**
- Parameters: `id` (required), `status` (required: in_progress/completed/skipped), `note` (optional), `data` (optional jsonb)
- Updates corresponding `SubStepRun` record
- Sets `started_at` when status changes to `in_progress`
- Sets `completed_at` when status changes to `completed` or `skipped`
- Returns updated sub-step run as JSON
- Returns error if sub-step not found or not in current step
- Returns error if called outside workflow context

**Tool definition (seed):**
```ruby
Tool.find_or_create_by!(name: "mark_sub_step", kind: :internal) do |t|
  t.display_name = "Mark Sub-Step"
  t.description = "Update sub-step status with optional note and structured data. Only available during workflow execution."
  t.input_schema = {
    type: "object",
    properties: {
      id: { type: "integer", description: "Sub-step run ID" },
      status: { type: "string", enum: %w[in_progress completed skipped], description: "New status" },
      note: { type: "string", description: "What was done, decisions made" },
      data: { type: "object", description: "Structured data — decisions, metrics, findings" }
    },
    required: %w[id status]
  }
end
```

### Story 18.5: write_step_note Tool

**As an** agent running a workflow step,
**I want** to save a note visible to agents in subsequent steps,
**So that** context and decisions are passed forward.

**Acceptance Criteria:**
- Parameter: `note` (required string)
- Appends to `StepRun#step_note` (not replaces — multiple calls accumulate)
- Returns confirmation with current full note text
- Returns error if called outside workflow context

**Tool definition (seed):**
```ruby
Tool.find_or_create_by!(name: "write_step_note", kind: :internal) do |t|
  t.display_name = "Write Step Note"
  t.description = "Save a note for this step. Visible to agents in subsequent steps via workflow context."
  t.input_schema = {
    type: "object",
    properties: {
      note: { type: "string", description: "Note text to append" }
    },
    required: %w[note]
  }
end
```

### Story 18.6: Code Climate Tool + Container Strategy

**As an** agent,
**I want** to run Code Climate static analysis on a repository,
**So that** I can include quality metrics in code reports.

**Acceptance Criteria:**
- Parameters: `repository_id` (required), `engines` (optional string, comma-separated), `format` (optional: json/text, default: json)
- Resolves repository from project, clones if needed
- `CodeClimateStrategy` creates Docker container:
  - Image: `codeclimate/codeclimate`
  - Bind mounts: repo → `/code`, Docker socket, `/tmp/cc`
  - Memory limit: 2GB, CPU quota
  - Labels: `palad.type=internal_tool`, `palad.tool=code_climate`
- Generates default `.codeclimate.yml` if not present in repo
- Returns analysis output (JSON or text)
- Container cleaned up after execution (even on error)
- Timeout: 10 minutes
- Returns error if repository not found or not accessible

**Container strategy:**
```ruby
module ContainerStrategies
  class CodeClimateStrategy < BaseStrategy
    # Overrides:
    # - resolve_image → "codeclimate/codeclimate"
    # - build_host_config → bind mounts (repo, docker.sock, /tmp/cc)
    # - build_cmd → ["analyze", "-f", format, "-e", engines...]
    # - build_working_dir → "/code"
  end
end
```

**Tool definition (seed):**
```ruby
Tool.find_or_create_by!(name: "code_climate", kind: :internal) do |t|
  t.display_name = "Code Climate Analysis"
  t.description = "Run Code Climate static analysis on a repository. Returns quality metrics, code smells, duplication, and maintainability scores."
  t.input_schema = {
    type: "object",
    properties: {
      repository_id: { type: "integer", description: "Repository ID to analyze" },
      engines: { type: "string", description: "Comma-separated engines (rubocop,eslint,duplication)" },
      format: { type: "string", description: "Output format: json or text", default: "json", enum: %w[json text] }
    },
    required: %w[repository_id]
  }
end
```

### Story 18.7: Internal Tool Seeds

**As a** developer,
**I want** all internal tools defined in seeds,
**So that** they are available in development and production after deploy.

**Acceptance Criteria:**
- `db/seeds.rb` creates all 4 internal tools with correct `input_schema`
- Idempotent: `find_or_create_by!(name:, kind: :internal)`
- Tools have clear `description` for MCP discovery
- Existing `code_climate` seed updated to match Story 18.6 schema

---

## Dependency Graph

```
Story 18.1 (Router)
    │
    ├──→ Story 18.2 (tools/list visibility)
    │        │
    │        ├──→ Story 18.3 (list_sub_steps)
    │        ├──→ Story 18.4 (mark_sub_step)
    │        └──→ Story 18.5 (write_step_note)
    │
    └──→ Story 18.6 (code_climate + strategy)

Story 18.7 (Seeds) — independent, can be done first
```

## Implementation Notes

- `InternalTools::Base` pattern mirrors `ContainerStrategies::BaseStrategy` — convention-based class resolution
- Workflow tools (18.3–18.5) need `StepRun` and `SubStepRun` models to exist (Epic 11 dependency)
- Code Climate (18.6) needs `Repository` model and GitHub integration (Epic 14)
- No frontend changes needed — tools appear automatically via MCP
- No migration needed — Tool model already supports `kind: internal`

---
