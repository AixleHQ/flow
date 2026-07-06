# Session Context Constructor — Architecture Design

**Date:** 2026-02-28
**Status:** Draft
**Author:** Artem Petrov + AI Analysis

---

## Related Documents

| Document | Description |
|----------|-------------|
| [Workflow Architecture](./workflow-architecture.md) | Workflow, Steps, SubSteps, execution model |
| [BMAD Structure Analysis](./BMAD-structure-description.md) | Why XML + config + critical notes work |
| [Architecture](./architecture/index.md) | Core architecture decisions |

---

## 1. Problem Statement

The context for agent sessions is currently assembled in **three different places**, each of which knows only about "its own" part:

| Component | What it assembles | Problem |
|-----------|-------------|----------|
| `SessionContextService#build_context_content` | Persona, MCP, tools, skills, repos, workspace layout | Plain markdown without prioritization. No workflow/board context |
| `WorkflowStepStrategy#build_workflow_prompt` | Step instructions, sub-steps, repos, input assets | Duplicates part of SessionContextService. Goes into `AGENT_PROMPT` separately |
| `WorkflowContextAssembler` | Workflow name, step, sub-steps, previous steps | **Not used at all** — orphaned code |
| `BoardContextResolver` | Board → project mapping | Used only inside the board MCP tools, not injected into the prompt |

### Key problems

1. **No single pipeline** — context is scattered across strategies and services
2. **No prioritization** — everything is plain markdown, the LLM may ignore critical instructions
3. **No composability** — adding a new layer (board, task, custom instructions) requires edits in several places
4. **Board context is invisible to the agent** — the agent does not know about the task, column, or board until it calls an MCP tool
5. **Duplication** — repos and assets are described both in the context file and in the workflow prompt

---

## 2. Design Goals

1. **Single constructor** — one pipeline assembles the entire context for any type of session
2. **XML-structured sections** — the LLM follows structured tags better than plain markdown
3. **Composable layers** — each layer (base, agent, workflow, board, step) is a separate builder
4. **Priority levels** — critical / important / informational sections with different "strength"
5. **Deterministic order** — the order of sections is predictable and optimal for attention
6. **Testable** — each builder is tested in isolation

---

## 3. XML-Structured Context: Why and How

### 3.1 Why XML tags in prompts

From the analysis of BMAD-METHOD (and confirmed in practice in Cursor, Claude, Gemini):

| Reason | Rationale |
|---------|-------------|
| **Reduces "lost in the middle"** | XML tags create visual and semantic "anchors" that the model returns to |
| **Prioritization without repetition** | `<critical-rules>` carries more weight than a regular markdown header — the model "sees" it |
| **Machine-readability** | Tags can be parsed, validated, and tested automatically |
| **Less ambiguity** | A closing tag (`</step-instructions>`) explicitly signals the end of a section |
| **Nesting** | XML allows logical grouping (workflow > step > sub-steps) without ambiguity |

### 3.2 Our XML DSL convention

```xml
<section name="..." priority="critical|important|info">
  Content here
</section>
```

**Priority levels:**
- `critical` — rules the agent MUST follow. A violation = a bug. Placed at the beginning and the end of the context (sandwich pattern)
- `important` — context that affects the quality of the work. Skipping it ≠ an error, but it degrades the result
- `info` — reference information. Can be used as needed

### 3.3 Practical tags

| Tag | Purpose | Priority |
|-----|-----------|----------|
| `<critical-rules>` | Mandatory behavior rules | critical |
| `<agent-role>` | Persona, communication style, principles | important |
| `<session-context>` | Session ID, mode, project, language | info |
| `<workspace>` | Directory layout, file rules | important |
| `<workflow-context>` | Workflow name, mode, run info | important |
| `<current-step>` | Step instructions, sub-steps | critical |
| `<previous-steps>` | History from prior steps | info |
| `<board-context>` | Board task, column, related tasks | important |
| `<available-tools>` | MCP servers, tools, shell commands | info |
| `<available-resources>` | Repos, assets, skills | info |
| `<output-rules>` | Where/how to save results | critical |

---

## 4. Architecture: Context Constructor Pipeline

### 4.1 High-Level Flow

```
SessionContextConstructor.build(session)
  │
  ├─→ BaseContextBuilder        (always)      → critical-rules, session-context, workspace
  ├─→ AgentContextBuilder       (if agent)    → agent-role
  ├─→ ToolsContextBuilder       (always)      → available-tools, available-resources
  ├─→ WorkflowContextBuilder    (if workflow)  → workflow-context, current-step, previous-steps
  ├─→ BoardContextBuilder       (if board)     → board-context
  ├─→ CustomInstructionsBuilder (if present)   → user-defined sections
  │
  └─→ Renderer.render(sections, format: :xml_markdown)
        │
        ├─→ Context file (CLAUDE.md / AGENTS.md / GEMINI.md)
        └─→ AGENT_PROMPT env var (for non-interactive / workflow steps)
```

### 4.2 Value Objects

Clean, frozen value objects with validation — no bare hashes or mutable structures.

```ruby
class ContextSection
  PRIORITIES = %i[critical important info].freeze
  POSITIONS  = %i[top middle bottom].freeze

  attr_reader :tag, :priority, :content, :position_hint, :builder_name

  def initialize(tag:, priority:, content:, position_hint: :middle, builder_name: nil)
    raise ArgumentError, "unknown priority: #{priority}" unless PRIORITIES.include?(priority)
    raise ArgumentError, "unknown position: #{position_hint}" unless POSITIONS.include?(position_hint)
    raise ArgumentError, "tag required" if tag.blank?
    raise ArgumentError, "content required" if content.blank?

    @tag = tag.to_s.freeze
    @priority = priority
    @content = content.freeze
    @position_hint = position_hint
    @builder_name = builder_name&.to_s&.freeze
  end

  def critical? = priority == :critical

  def to_h
    { tag:, priority:, position_hint:, builder_name:, content_length: content.length }
  end

  def freeze
    super
    self
  end
end
```

### 4.3 Builder Interface

A clean abstract interface. The builder's sole responsibility is to decide `applicable?` and return `Array<ContextSection>`.

```ruby
class ContextBuilders::Base
  attr_reader :session

  def initialize(session)
    @session = session
  end

  # @return [Array<ContextSection>] ordered list of sections
  def build
    raise NotImplementedError
  end

  # Whether this builder should run for the given session.
  # All discovery logic lives HERE — callers never pass flags.
  def applicable?
    true
  end

  # Human-readable builder name for traceability
  def name
    self.class.name.demodulize.underscore
  end

  private

  # Convenience: build a section with auto-populated builder_name
  def section(tag:, priority:, content:, position_hint: :middle)
    ContextSection.new(tag:, priority:, content:, position_hint:, builder_name: name)
  end

  # Session navigation helpers — builders use these, no raw association traversal
  def project       = session.project
  def step_run      = session.step_run
  def workflow_run  = step_run&.workflow_run
  def workflow      = workflow_run&.workflow
  def board_task    = workflow_run&.board_task
end
```

### 4.4 Constructor (Orchestrator)

**Single entry point:** `SessionContextConstructor.build(session)` — you pass any `TerminalSession` and get a ready context. All the discovery logic (workflow? board? agent?) is inside the builders.

```ruby
class SessionContextConstructor
  BUILDERS = [
    ContextBuilders::CriticalRules,    # Always first
    ContextBuilders::AgentRole,        # Persona
    ContextBuilders::SessionInfo,      # Session metadata
    ContextBuilders::Workspace,        # Directory layout
    ContextBuilders::WorkflowContext,  # Workflow + step (if applicable)
    ContextBuilders::BoardContext,     # Board task (if applicable)
    ContextBuilders::Tools,           # MCP servers, tools, shell tools
    ContextBuilders::Resources,       # Repos, assets, skills
    ContextBuilders::OutputRules,     # Always last
  ].freeze

  # Primary API — returns rendered XML-markdown string
  def self.build(session)
    new(session).build.render
  end

  # Full API — returns ContextResult with render + inspect + to_json
  def self.build_result(session)
    new(session).build
  end

  def initialize(session)
    @session = session
  end

  def build
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    builder_instances = BUILDERS.map { |klass| klass.new(@session) }
    applicable = builder_instances.select(&:applicable?)
    skipped = builder_instances.reject(&:applicable?)

    sections = applicable.flat_map(&:build).compact

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

    ContextResult.new(
      session: @session,
      sections:,
      applied_builders: applicable.map(&:name),
      skipped_builders: skipped.map(&:name),
      built_at: Time.current,
      build_time_ms: elapsed_ms
    )
  end
end
```

### 4.5 ContextResult — a single result with two faces

`ContextResult` — a value object that knows both how to render XML-markdown for the agent and how to provide JSON for traceability.

```ruby
class ContextResult
  attr_reader :session, :sections, :applied_builders, :skipped_builders,
              :built_at, :build_time_ms

  def initialize(session:, sections:, applied_builders:, skipped_builders:, built_at:, build_time_ms:)
    @session = session
    @sections = sections.freeze
    @applied_builders = applied_builders.freeze
    @skipped_builders = skipped_builders.freeze
    @built_at = built_at
    @build_time_ms = build_time_ms
  end

  # For agent context file — XML-markdown string
  def render
    ContextRenderer.render(@sections)
  end
  alias_method :to_s, :render

  # For traceability API / logs — full structured JSON
  def to_json_hash
    {
      session_id: session.id,
      session_type: detect_session_type,
      project_id: session.project_id,
      built_at: built_at.iso8601,
      build_time_ms:,
      total_content_length:,
      applied_builders:,
      skipped_builders:,
      sections: sections.map { |s| section_metadata(s) }
    }
  end

  def to_json(*args)
    to_json_hash.to_json(*args)
  end

  def total_content_length
    sections.sum { |s| s.content.length }
  end

  private

  def detect_session_type
    if session.step_run&.workflow_run&.board_task.present?
      "board_triggered"
    elsif session.step_run.present?
      "workflow_step"
    else
      "standalone"
    end
  end

  def section_metadata(section)
    {
      tag: section.tag,
      priority: section.priority,
      position_hint: section.position_hint,
      builder: section.builder_name,
      content_length: section.content.length
    }
  end
end
```

**Usage:**

```ruby
# Simple variant — a string for the context file
content = SessionContextConstructor.build(session)

# Full variant — a result object with both formats
result = SessionContextConstructor.build_result(session)
result.render              # → XML-markdown for the agent
result.to_json             # → JSON for traceability
result.total_content_length  # → 15200
result.applied_builders    # → ["critical_rules", "agent_role", "workflow_context", ...]
result.skipped_builders    # → ["board_context"]
```

---

## 5. Builders: Detail Design

### 5.1 CriticalRules Builder

Always first. Contains the rules that MUST NOT be violated.

```ruby
class ContextBuilders::CriticalRules < ContextBuilders::Base
  def build
    rules = []

    rules << mode_rules
    rules << language_rule if preferred_language.present?

    [
      ContextSection.new(
        tag: "critical-rules",
        priority: :critical,
        content: rules.compact.join("\n\n"),
        position_hint: :top
      )
    ]
  end

  private

  def mode_rules
    case session_mode
    when "non_interactive"
      <<~RULES
        ## Non-Interactive Mode

        This session runs WITHOUT human interaction. There is NO user to respond.

        - NEVER ask questions, request clarifications, or wait for input
        - NEVER present options and ask the user to choose
        - Make reasonable assumptions when details are missing
        - Save ALL results to the designated output directory
        - Write a summary of what was done and assumptions made
      RULES
    when "interactive"
      nil # No special rules for interactive mode
    end
  end

  def language_rule
    lang = session.user&.preferred_agent_language
    return nil if lang.blank?
    "**Communication Language:** #{lang} — ALL communication with the user MUST be in this language."
  end
end
```

### 5.2 AgentRole Builder

```ruby
class ContextBuilders::AgentRole < ContextBuilders::Base
  def applicable?
    session.configured_agent.present?
  end

  def build
    agent = session.configured_agent
    [
      ContextSection.new(
        tag: "agent-role",
        priority: :important,
        content: agent.to_system_prompt,
        position_hint: :top
      )
    ]
  end
end
```

### 5.3 WorkflowContext Builder

The most complex builder. Replaces both `WorkflowContextAssembler` and `WorkflowStepStrategy#build_workflow_prompt`.

```ruby
class ContextBuilders::WorkflowContext < ContextBuilders::Base
  def applicable?
    session.step_run.present?
  end

  def build
    sections = []
    sections << workflow_overview_section
    sections << current_step_section
    sections << sub_steps_section if sub_steps.any?
    sections << previous_steps_section if completed_step_runs.any?
    sections << workflow_tools_section if sub_steps.any?
    sections
  end

  private

  def workflow_overview_section
    ContextSection.new(
      tag: "workflow-context",
      priority: :important,
      content: build_workflow_overview,
      position_hint: :top
    )
  end

  def current_step_section
    ContextSection.new(
      tag: "current-step",
      priority: :critical,
      content: build_current_step,
      position_hint: :middle
    )
  end

  def sub_steps_section
    ContextSection.new(
      tag: "sub-steps",
      priority: :important,
      content: build_sub_steps,
      position_hint: :middle
    )
  end

  def previous_steps_section
    ContextSection.new(
      tag: "previous-steps",
      priority: :info,
      content: build_previous_steps,
      position_hint: :middle
    )
  end

  def workflow_tools_section
    ContextSection.new(
      tag: "workflow-tools",
      priority: :important,
      content: build_workflow_tools,
      position_hint: :middle
    )
  end

  def build_workflow_overview
    <<~MD
      ## Workflow: #{workflow.name}

      #{workflow.description}

      **Mode:** #{workflow_run.mode} | **Run:** #{workflow_run.id}
      **Step #{step.position} of #{workflow.steps.count}**
    MD
  end

  def build_current_step
    lines = []
    lines << "## Step: #{step.name}"
    lines << ""
    lines << step.description if step.description.present?
    lines << ""
    lines << "### Instructions"
    lines << ""
    lines << step.instructions if step.instructions.present?
    lines.join("\n")
  end

  def build_sub_steps
    lines = ["## Sub-Steps Checklist"]
    lines << ""

    sub_step_runs = step_run.sub_step_runs.includes(:sub_step).index_by(&:sub_step_id)

    sub_steps.each do |ss|
      ssr = sub_step_runs[ss.id]
      status = ssr ? ssr.state : "pending"
      icon = status_icon(status)
      id_ref = ssr ? " `id: #{ssr.id}`" : ""

      line = "#{ss.position}. #{icon} **#{ss.name}**#{id_ref} [#{status}]"
      line += " — #{ss.description}" if ss.description.present?
      lines << line

      if ssr&.note.present?
        lines << "   → #{ssr.note.truncate(200)}"
      end
      if ssr&.data.present?
        lines << "   → data: #{ssr.data.to_json.truncate(300)}"
      end
    end

    lines << ""
    lines << "Track progress: call `mark_sub_step` with the sub-step `id` shown above."
    lines << "Mark `in_progress` when starting, `completed` when done."
    lines << ""
    lines << "**IMPORTANT:** Do NOT mark the last sub-step `completed` until ALL work is done — including writing output files. Marking the last sub-step completed triggers session termination."
    lines.join("\n")
  end

  def build_previous_steps
    lines = ["## Previous Steps"]
    lines << ""

    completed_step_runs.each do |sr|
      icon = sr.state == "completed" ? "✅" : "⏭️"
      lines << "### Step #{sr.step.position}: #{sr.step.name} #{icon}"

      if sr.step_note.present?
        lines << "Note: #{sr.step_note.truncate(500)}"
      end

      sr.sub_step_runs.where(state: "completed").includes(:sub_step).each do |ssr|
        next unless ssr.note.present? || ssr.data.present?
        parts = ["- #{ssr.sub_step.name}"]
        parts << ": #{ssr.note.truncate(150)}" if ssr.note.present?
        lines << parts.join
        if ssr.data.present?
          lines << "  data: #{ssr.data.to_json.truncate(200)}"
        end
      end
      lines << ""
    end

    lines.join("\n")
  end

  def build_workflow_tools
    <<~MD
      ## Workflow Tools (via MCP)

      - **list_sub_steps** — List all sub-steps with current statuses
      - **mark_sub_step** — Update status: `id`, `status` (in_progress/completed/skipped), optional `note`, `data`
      - **write_step_note** — Save a note visible to subsequent steps
    MD
  end

  # Helpers

  def step_run     = session.step_run
  def workflow_run  = step_run.workflow_run
  def workflow      = workflow_run.workflow
  def step          = step_run.step
  def sub_steps     = @sub_steps ||= step.sub_steps.order(:position)

  def completed_step_runs
    @completed_step_runs ||= workflow_run.step_runs
      .includes(step: :sub_steps, sub_step_runs: :sub_step)
      .where.not(id: step_run.id)
      .where(state: %w[completed skipped])
      .joins(:step).order("steps.position ASC")
  end

  def status_icon(status)
    { "completed" => "✅", "in_progress" => "🔄", "skipped" => "⏭️" }.fetch(status, "⬜")
  end
end
```

### 5.4 BoardContext Builder

A new builder — injects board/task context if the session is linked to a board.

```ruby
class ContextBuilders::BoardContext < ContextBuilders::Base
  def applicable?
    board_task.present?
  end

  def build
    [
      ContextSection.new(
        tag: "board-context",
        priority: :important,
        content: build_board_context,
        position_hint: :top
      )
    ]
  end

  private

  def build_board_context
    task = board_task
    board = task.board
    column = task.board_column

    lines = []
    lines << "## Board Task Context"
    lines << ""
    lines << "You are working on a specific task from the project board."
    lines << ""
    lines << "- **Board:** #{board.name}"
    lines << "- **Task:** #{task.title} (id: #{task.id})"
    lines << "- **Column:** #{column.name}" if column
    lines << "- **Priority:** #{task.priority}" if task.respond_to?(:priority) && task.priority.present?
    lines << "- **Description:** #{task.description.truncate(500)}" if task.description.present?

    if task.tags.present?
      lines << "- **Tags:** #{task.tags.join(', ')}"
    end

    # Related context
    if task.task_comments.recent.any?
      lines << ""
      lines << "### Recent Comments"
      task.task_comments.recent.limit(5).each do |comment|
        lines << "- #{comment.author_name}: #{comment.body.truncate(200)}"
      end
    end

    lines << ""
    lines << "Use board MCP tools (`board_get_task`, `board_add_comment`, `board_move_task`) to interact with the board."
    lines.join("\n")
  end

  def board_task
    @board_task ||= session.step_run&.workflow_run&.board_task
  end
end
```

### 5.5 Tools Builder

```ruby
class ContextBuilders::Tools < ContextBuilders::Base
  def build
    sections = []
    sections << shell_tools_section
    sections << mcp_servers_section if mcp_servers.any?
    sections << custom_tools_section if custom_tools.any?
    sections
  end

  private

  def shell_tools_section
    ContextSection.new(
      tag: "shell-tools",
      priority: :info,
      content: build_shell_tools,
      position_hint: :bottom
    )
  end

  def mcp_servers_section
    ContextSection.new(
      tag: "mcp-servers",
      priority: :info,
      content: build_mcp_descriptions,
      position_hint: :bottom
    )
  end

  def custom_tools_section
    ContextSection.new(
      tag: "custom-tools",
      priority: :info,
      content: build_tool_descriptions,
      position_hint: :bottom
    )
  end

  # ... (existing implementation from SessionContextService)
end
```

### 5.6 Resources Builder

```ruby
class ContextBuilders::Resources < ContextBuilders::Base
  def build
    sections = []
    sections << repositories_section if session.repository_ids.present?
    sections << assets_section if has_input_assets?
    sections << skills_section if session.skill_ids.present?
    sections
  end
  # ...
end
```

### 5.7 OutputRules Builder

Always last. Repeats the critical rules (sandwich pattern — the key points at the beginning AND at the end).

```ruby
class ContextBuilders::OutputRules < ContextBuilders::Base
  def build
    [
      ContextSection.new(
        tag: "output-rules",
        priority: :critical,
        content: build_output_rules,
        position_hint: :bottom
      )
    ]
  end

  private

  def build_output_rules
    lines = ["## Output Rules"]
    lines << ""
    lines << "- Save ALL results and deliverables to `/workspace/outputs/`"
    lines << "- Files in `/workspace/assets/` are READ-ONLY — copy to outputs before editing"
    lines << "- Use all available MCP servers and tools"
    lines << "- Write clean, production-quality code following project conventions"

    if workflow_step?
      lines << "- Marking the last sub-step `completed` triggers session termination — ensure all files are saved first"
    end

    lines.join("\n")
  end
end
```

---

## 6. Renderer: XML-Markdown Format

### 6.1 Output Format

The renderer takes `Array<ContextSection>` and renders it into an XML-Markdown hybrid:

```ruby
class ContextRenderer
  PRIORITY_ORDER = { critical: 0, important: 1, info: 2 }.freeze
  POSITION_ORDER = { top: 0, middle: 1, bottom: 2 }.freeze

  def self.render(sections)
    sorted = sections.sort_by do |s|
      [POSITION_ORDER[s.position_hint], PRIORITY_ORDER[s.priority]]
    end

    parts = sorted.map { |s| render_section(s) }
    parts.join("\n\n")
  end

  def self.render_section(section)
    <<~XML
      <#{section.tag} priority="#{section.priority}">

      #{section.content.strip}

      </#{section.tag}>
    XML
  end
end
```

### 6.2 Example Output

Here is what the assembled context looks like for a workflow step session with a board task:

```xml
<critical-rules priority="critical">

## Non-Interactive Mode

This session runs WITHOUT human interaction. There is NO user to respond.

- NEVER ask questions, request clarifications, or wait for input
- NEVER present options and ask the user to choose
- Make reasonable assumptions when details are missing
- Save ALL results to the designated output directory

**Communication Language:** Russian — ALL communication with the user MUST be in this language.

</critical-rules>

<agent-role priority="important">

## Your Role

You are the **Architect** — a senior software architect specializing in system design.

**Communication Style:** Direct, structured, decision-oriented.

**Principles:**
- Always consider trade-offs explicitly
- Prefer boring technology unless there's a strong reason
- Document decisions with rationale

</agent-role>

<board-context priority="important">

## Board Task Context

You are working on a specific task from the project board.

- **Board:** Sprint 12
- **Task:** Implement user authentication (id: 42)
- **Column:** In Progress
- **Priority:** high
- **Description:** Add JWT-based authentication with refresh tokens...

### Recent Comments
- PM: Please use bcrypt for password hashing
- Dev Lead: Consider OAuth2 for third-party providers

Use board MCP tools (`board_get_task`, `board_add_comment`, `board_move_task`) to interact with the board.

</board-context>

<workflow-context priority="important">

## Workflow: Product Planning (Greenfield)

Full product planning from brainstorming to readiness check.

**Mode:** mixed | **Run:** run_abc123
**Step 3 of 7**

</workflow-context>

<current-step priority="critical">

## Step: Create Architecture

Design the system architecture based on PRD and product brief.

### Instructions

Analyze the PRD and make critical architectural decisions. Start with technology
choices, then define data model, API structure, and deployment topology.
Focus on decisions that are hard to change later.

</current-step>

<sub-steps priority="important">

## Sub-Steps Checklist

1. ✅ **Context Analysis** `id: 101` [completed]
   → Loaded PRD, identified 12 FRs and 8 NFRs
2. ✅ **Starter Template** `id: 102` [completed]
   → Selected Rails + React monorepo
   → data: {"framework":"Rails 7.2","frontend":"React 18"}
3. 🔄 **Core Decisions** `id: 103` [in_progress]
4. ⬜ **Implementation Patterns** `id: 104` [pending]
5. ⬜ **Project Structure** `id: 105` [pending]
6. ⬜ **Validation** `id: 106` [pending]

Track progress: call `mark_sub_step` with the sub-step `id` shown above.
Mark `in_progress` when starting, `completed` when done.

**IMPORTANT:** Do NOT mark the last sub-step `completed` until ALL work is done — including writing output files. Marking the last sub-step completed triggers session termination.

</sub-steps>

<previous-steps priority="info">

## Previous Steps

### Step 1: Brainstorming ⏭️
### Step 2: Create Product Brief ✅
Note: Defined B2B SaaS platform for developer teams
- Vision: Core vision statement established
- Users: 3 primary personas identified

</previous-steps>

<session-context priority="info">

## Session Context

- **Session ID:** sess_xyz789
- **Agent Runtime:** claude_code
- **Mode:** non_interactive
- **Project:** Aixle

</session-context>

<workspace priority="important">

## Workspace Layout

Your working directory is `/workspace`.

- **`/workspace/outputs/`** — Put all results here. Contents will be collected after the session.
- **`/workspace/assets/`** — Read-only reference documents. Do NOT modify.
- **`/workspace/repo/`** — Code repositories. See "Available Repositories" for details.

</workspace>

<workflow-tools priority="important">

## Workflow Tools (via MCP)

- **list_sub_steps** — List all sub-steps with current statuses
- **mark_sub_step** — Update status: `id`, `status` (in_progress/completed/skipped), optional `note`, `data`
- **write_step_note** — Save a note visible to subsequent steps

</workflow-tools>

<available-resources priority="info">

## Available Repositories

| ID | Repository | Path | Branch |
|---|---|---|---|
| 5 | acme/backend | /workspace/repo/backend | main |

## Input Assets (pre-loaded in /workspace/assets/)

- **PRD.md** (id: 12) → `/workspace/assets/PRD.md`
- **product-brief.md** (id: 11) → `/workspace/assets/product-brief.md`

</available-resources>

<mcp-servers priority="info">

## Available MCP Servers

### aixle-tools
Internal tools server. Call tools via MCP — use `tools/list` to see available tools.

### context7
Documentation lookup. Retrieve up-to-date docs for any library.

</mcp-servers>

<custom-tools priority="info">

## Available Tools

These tools are provided via the **aixle-tools** MCP server.

### cloc_analysis ⚡ app
Count lines of code by language — Returns: direct result
Parameters: repository_id (integer)

### security_scan ⏳ container
Run security analysis on repository — Returns: execution ID → use read_tool_result
Parameters: repository_id (integer), scan_type (string)

</custom-tools>

<shell-tools priority="info">

## Available Shell Tools

| Tool | Description | Example |
|------|-------------|---------|
| `tree` | Directory structure | `tree -d -L 2` |
| `cloc` | Lines of code | `cloc .` |
| `rg` | Fast code search | `rg 'TODO' --type ruby` |
| `fd` | Fast file finder | `fd -e rb` |
| `jq` | JSON processor | `jq '.dependencies' package.json` |
| `git` | Version control | `git log --oneline -20` |

</shell-tools>

<output-rules priority="critical">

## Output Rules

- Save ALL results and deliverables to `/workspace/outputs/`
- Files in `/workspace/assets/` are READ-ONLY — copy to outputs before editing
- Use all available MCP servers and tools
- Write clean, production-quality code following project conventions
- Marking the last sub-step `completed` triggers session termination — ensure all files are saved first

</output-rules>
```

---

## 7. Session Type Matrix

Which builders run for which types of sessions:

| Builder | Standalone | Workflow Step | System (internal tool) | Board-triggered |
|---------|-----------|--------------|----------------------|-----------------|
| CriticalRules | ✅ | ✅ | ✅ (minimal) | ✅ |
| AgentRole | ✅ (if agent) | ✅ (from step.agent) | ❌ | ✅ |
| SessionInfo | ✅ | ✅ | ✅ | ✅ |
| Workspace | ✅ | ✅ | ❌ | ✅ |
| WorkflowContext | ❌ | ✅ | ❌ | ✅ (if from workflow) |
| BoardContext | ❌ | ✅ (if board_task) | ❌ | ✅ |
| Tools | ✅ | ✅ | ✅ (minimal) | ✅ |
| Resources | ✅ | ✅ | ❌ | ✅ |
| OutputRules | ✅ | ✅ | ❌ | ✅ |

---

## 8. Integration Plan

### 8.1 Where the Constructor Fits

```
Before (current):
  AgentSessionStrategy#before_exec
    → SessionContextService.assemble_session_context
        → build_context_content (markdown)
        → inject_context_file

  WorkflowStepStrategy#build_env_vars
    → build_workflow_prompt (separate markdown in AGENT_PROMPT)

After (proposed):
  AgentSessionStrategy#before_exec
    → SessionContextService.assemble_session_context
        → SessionContextConstructor.build(session)     ← NEW: unified pipeline
        → inject_context_file (with XML-structured output)

  WorkflowStepStrategy#build_env_vars
    → AGENT_PROMPT = step.instructions                  ← simplified, context is in file
```

### 8.2 Context File vs AGENT_PROMPT Split

| Destination | What goes there | Why |
|-------------|----------------|-----|
| Context file (CLAUDE.md etc.) | Everything from Constructor | Persistent, visible to agent throughout session |
| AGENT_PROMPT env var | Only the user's initial prompt (for non-interactive) or step instructions (for workflow) | This is the "task" — what to do, not how to behave |

Key principle: **Context file = who you are + what you know + the rules. AGENT_PROMPT = what to do.**

### 8.3 Migration Path

1. **Phase 1:** Create `SessionContextConstructor` and builders, output same markdown (no XML yet)
2. **Phase 2:** Switch `SessionContextService#build_context_content` to use Constructor
3. **Phase 3:** Add XML tags to renderer
4. **Phase 4:** Move workflow context from `WorkflowStepStrategy` to `WorkflowContextBuilder`
5. **Phase 5:** Add `BoardContextBuilder`
6. **Phase 6:** Delete `WorkflowContextAssembler` (orphaned), clean up `WorkflowStepStrategy`

---

## 9. Token Budget Considerations

XML tags add ~2-5% overhead to the context size. This is acceptable, given:

- Average context: 2000-4000 tokens
- XML overhead: ~100-200 tokens
- Benefit: significantly better instruction following

### 9.1 Section Compression for Large Contexts

If the context exceeds the threshold (~6000 tokens), we apply:

1. **Previous steps** — truncate notes, drop data fields
2. **Board comments** — limit to 3 most recent
3. **Tool descriptions** — drop parameter details, keep names only
4. **Skills** — omit content, keep names only
5. Never truncate: critical-rules, current-step, output-rules

---

## 10. Validation & Testing

### 10.1 Builder Tests

Each builder is tested in isolation:

```ruby
class ContextBuilders::WorkflowContextTest < ActiveSupport::TestCase
  test "applicable? returns false for standalone sessions" do
    session = create(:terminal_session, :standalone)
    builder = ContextBuilders::WorkflowContext.new(session)
    assert_not builder.applicable?
  end

  test "builds correct sections for workflow step" do
    session = create(:terminal_session, :workflow_step)
    builder = ContextBuilders::WorkflowContext.new(session)
    sections = builder.build

    assert sections.any? { |s| s.tag == "current-step" && s.priority == :critical }
    assert sections.any? { |s| s.tag == "workflow-context" }
  end
end
```

### 10.2 Integration Tests

```ruby
class SessionContextConstructorTest < ActiveSupport::TestCase
  test "standalone session produces base sections only" do
    session = create(:terminal_session, :standalone)
    output = SessionContextConstructor.build(session)

    assert_includes output, "<critical-rules"
    assert_includes output, "<output-rules"
    assert_not_includes output, "<workflow-context"
    assert_not_includes output, "<board-context"
  end

  test "workflow step session includes all context layers" do
    session = create(:terminal_session, :workflow_step, :with_board_task)
    output = SessionContextConstructor.build(session)

    assert_includes output, "<critical-rules"
    assert_includes output, "<workflow-context"
    assert_includes output, "<current-step"
    assert_includes output, "<board-context"
    assert_includes output, "<output-rules"
  end
end
```

### 10.3 XML Validation

```ruby
class ContextRendererTest < ActiveSupport::TestCase
  test "all sections have matching open/close tags" do
    sections = [
      ContextSection.new(tag: "test", priority: :critical, content: "hello", position_hint: :top)
    ]
    output = ContextRenderer.render(sections)

    assert_match /<test priority="critical">/, output
    assert_match /<\/test>/, output
  end

  test "critical sections appear before info sections" do
    # ...
  end
end
```

---

## 11. JSON Traceability Interface

### 11.1 Why

For debugging, auditing, and a future UI, we need to see exactly what the Constructor assembled for a specific session. Not just the final text, but **structured metadata**: which builders fired, which did not, how many tokens each section used, and whether compression occurred.

### 11.2 API Endpoint

```
GET /api/v1/company/terminal_sessions/:id/context_debug
```

**Response (JSON):**

```json
{
  "session_id": 42,
  "session_type": "workflow_step",
  "project_id": 7,
  "built_at": "2026-02-28T14:30:00Z",
  "build_time_ms": 12.3,
  "total_content_length": 15200,
  "applied_builders": [
    "critical_rules",
    "agent_role",
    "session_info",
    "workspace",
    "workflow_context",
    "tools",
    "resources",
    "output_rules"
  ],
  "skipped_builders": [
    "board_context"
  ],
  "sections": [
    {
      "tag": "critical-rules",
      "priority": "critical",
      "position_hint": "top",
      "builder": "critical_rules",
      "content_length": 580
    },
    {
      "tag": "agent-role",
      "priority": "important",
      "position_hint": "top",
      "builder": "agent_role",
      "content_length": 840
    },
    {
      "tag": "current-step",
      "priority": "critical",
      "position_hint": "middle",
      "builder": "workflow_context",
      "content_length": 2080
    }
  ]
}
```

### 11.3 Integration

```ruby
# In SessionContextService#inject_context_file — save the metadata
def inject_context_file(container_id, session)
  result = SessionContextConstructor.build_result(session)

  # Write the context into the container
  write_file(container_id, expanded_path, result.render, uid)

  # Save metadata for traceability
  session.update_column(:context_metadata, result.to_json_hash)
end
```

Metadata is stored in `terminal_sessions.context_metadata` (JSONB, nullable) — one migration is added, one column.

### 11.4 Usage

- **Debug UI:** a "Context" tab on the session page with a table of sections, token counts, builder info
- **Logs:** `Rails.logger.info("[SessionContext] #{result.to_json}")` — structured logging
- **Monitoring:** alert if `build_time_ms > 100` or `total_estimated_tokens > 8000`
- **Testing:** `assert_equal ["critical_rules", "agent_role", "output_rules"], result.applied_builders`

---

## 12. Clean Interface Design Principles

### 12.1 Session-Centric API

The entire API is built around a single argument — `TerminalSession`. The calling code **never** decides which session type it is dealing with. The builders detect the context themselves:

```ruby
# ✅ CORRECT — the calling code does not know the details
content = SessionContextConstructor.build(session)

# ❌ INCORRECT — leaking implementation details
if session.step_run.present?
  content = build_workflow_context(session) + build_base_context(session)
else
  content = build_base_context(session)
end
```

### 12.2 Navigation Helpers in the Base Builder

Builders do not reach directly into associations. Instead of `session.step_run.workflow_run.workflow.name` they use helpers from Base:

```ruby
class ContextBuilders::Base
  private

  def project       = session.project
  def step_run      = session.step_run
  def workflow_run  = step_run&.workflow_run
  def workflow      = workflow_run&.workflow
  def board_task    = workflow_run&.board_task
  def step          = step_run&.step
end
```

### 12.3 Builder Self-Description

Each builder is self-contained. Looking at the file, you immediately see:
- When it fires (`applicable?`)
- What it generates (which tags, priorities)
- Where it gets its data

```ruby
class ContextBuilders::BoardContext < ContextBuilders::Base
  # Fires only if the session is tied to a board task
  def applicable?
    board_task.present?
  end

  def build
    [
      section(
        tag: "board-context",
        priority: :important,
        position_hint: :top,
        content: build_board_context
      )
    ]
  end

  private

  def build_board_context
    # ...pure logic, no "do we even have a board_task" conditions
    # applicable? already guaranteed it
  end
end
```

### 12.4 Convenience Method: `section(...)`

Instead of manually creating `ContextSection.new(tag:, priority:, content:, position_hint:, builder_name: name)` every time — the `section(...)` helper in Base:

```ruby
# Instead of:
ContextSection.new(tag: "board-context", priority: :important, content: text, position_hint: :top, builder_name: "board_context")

# We write:
section(tag: "board-context", priority: :important, content: text, position_hint: :top)
```

`builder_name` is filled in automatically.

---

## 13. Open Questions

| # | Question | Leaning |
|---|----------|---------|
| 1 | Is a `<critical-rules>` sandwich needed (duplication at the end)? | Yes — the LLM remembers the beginning and end better, the "middle gets lost" |
| 2 | XML tags or `===== CRITICAL: ... =====` markers? | XML — more structural, less ambiguity, parses better |
| 3 | A separate AGENT_PROMPT for the workflow or everything in the context file? | Separate — context file = role/rules, AGENT_PROMPT = task |
| 4 | Are nested tags needed (`<workflow><step>...</step></workflow>`)? | No — flat structure is simpler, the LLM does not get lost in nesting |
| 5 | Is a `priority` attribute needed or is the position in the document enough? | Both — priority for validation/tests, position for LLM attention |
| 6 | Custom instructions from the user — where? | A separate builder, priority=important, position=middle |
| 7 | Should rendered content be stored in `context_metadata`? | No — metadata only. The content can be rebuilt from the session |
| 8 | Is an admin UI needed for context debug? | Yes, but post-MVP — for the first iteration an API endpoint is enough |

---

_Document updated 2026-02-28 — added ContextResult, JSON traceability, clean interface design_
