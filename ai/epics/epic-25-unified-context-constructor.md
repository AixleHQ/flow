# Epic 25: Unified Context Constructor & XML Renderer

> Single composable pipeline that assembles XML-structured session context for all agent session types, replacing fragmented markdown generation. Clean interfaces, session-centric API, and JSON traceability.

**Phase:** 16 (Depends on: Epic 9 Session Context, Epic 10 Agent Sessions Core)

**Design Document:** [Session Context Constructor](../session-context-constructor.md)

**User Outcome:** All agent sessions (standalone, workflow step, board-triggered) receive consistent, high-quality XML-structured context with explicit priority levels and deterministic ordering. Agent instruction adherence improves due to structured sections and sandwich pattern. Developers can inspect the full context structure as JSON for debugging and audit.

**FRs Covered:** FR-SCC1, FR-SCC2, FR-SCC3, FR-SCC6, FR-SCC8, FR-SCC10

---

## Problem

Session context is assembled in three disconnected places (`SessionContextService#build_context_content`, `WorkflowStepStrategy#build_workflow_prompt`, `WorkflowContextAssembler`) with no unified pipeline. The output is plain markdown without prioritization — LLMs may ignore critical instructions buried in the middle. Adding a new context layer (board, custom instructions) requires changes in multiple places. There is no way to inspect what context an agent received — no traceability.

This epic creates a single composable pipeline with XML-tagged output where each section has an explicit priority level, and critical rules follow the sandwich pattern (repeated at start and end) to maximize instruction adherence. Every build produces a ContextResult with both the rendered output and structured JSON metadata for debugging.

---

## Stories

### Story 25.1: ContextSection Value Object & ContextRenderer

**As a** system,
**I want** a frozen ContextSection value object and a ContextRenderer that renders sections as XML-tagged markdown,
**So that** all context output has consistent structure with priority-based ordering and each section is self-describing.

**Acceptance Criteria:**

**Given** a ContextSection created with `tag: "test"`, `priority: :critical`, `content: "hello"`, `position_hint: :top`, `builder_name: "critical_rules"`
**When** the section is inspected
**Then** `section.tag` returns `"test"`, `section.critical?` returns `true`
**And** `section.to_h` returns `{ tag: "test", priority: :critical, position_hint: :top, builder_name: "critical_rules", content_length: 5 }`

**Given** a ContextSection created with `priority: :unknown`
**When** initialization runs
**Then** `ArgumentError` is raised with message "unknown priority: unknown"

**Given** an array of ContextSection structs with mixed priorities and positions
**When** `ContextRenderer.render(sections)` is called
**Then** output contains XML open/close tags for each section (e.g. `<critical-rules priority="critical">...</critical-rules>`)
**And** sections are sorted first by position_hint (`:top` → `:middle` → `:bottom`), then by priority (`:critical` → `:important` → `:info`)
**And** every open tag has a matching close tag
**And** output is a single string with sections separated by double newlines

**Technical notes:**
- `ContextSection` — frozen value object (not bare Struct) with validation in `initialize`
- Includes `#critical?`, `#to_h` (with `content_length`)
- `builder_name` tracks which builder produced this section — key for traceability
- Priority order: `{ critical: 0, important: 1, info: 2 }`
- Position order: `{ top: 0, middle: 1, bottom: 2 }`
- Files: `app/services/context_section.rb`, `app/services/context_renderer.rb`

---

### Story 25.2: Base Builder Interface & CriticalRules Builder

**As a** system,
**I want** a base builder class with navigation helpers and a CriticalRules builder that generates non-interactive mode rules and language preferences,
**So that** mandatory agent rules are always present at the top of context, and all builders share a clean interface.

**Acceptance Criteria:**

**Given** a TerminalSession in `non_interactive` mode with user `preferred_agent_language` set to "Russian"
**When** `ContextBuilders::CriticalRules` builder builds sections
**Then** output includes a ContextSection with tag `critical-rules`, priority `:critical`, position_hint `:top`
**And** content includes non-interactive mode rules (never ask questions, save all results, etc.)
**And** content includes language rule ("Communication Language: Russian")
**And** section's `builder_name` is `"critical_rules"`

**Given** a TerminalSession in `interactive` mode with no preferred language
**When** CriticalRules builder builds sections
**Then** output section has no non-interactive rules and no language directive

**Given** any builder subclass
**When** `applicable?` is called
**Then** it returns `true` by default (subclasses override as needed)

**Given** a builder subclass
**When** `section(tag:, priority:, content:)` helper is called
**Then** `builder_name` is auto-populated from `self.name`

**Technical notes:**
- `ContextBuilders::Base` — abstract class with `#build` (NotImplementedError), `#applicable?` (true), `#name` (auto from class)
- Convenience method `section(tag:, priority:, content:, position_hint:)` auto-fills `builder_name`
- Navigation helpers in Base: `project`, `step_run`, `workflow_run`, `workflow`, `board_task`, `step` — builders never traverse raw associations
- Directory: `app/services/context_builders/`
- Non-interactive rules text matches current `SessionContextService#build_general_instructions` for backward compatibility

---

### Story 25.3: Core Builders (AgentRole, SessionInfo, Workspace, Tools, Resources)

**As a** system,
**I want** builders for AgentRole, SessionInfo, Workspace, Tools (shell + MCP + custom), and Resources (repos, assets, skills) that extract content from existing SessionContextService methods,
**So that** all current context content is generated through composable builders.

**Acceptance Criteria:**

**Given** a session with a configured agent
**When** `ContextBuilders::AgentRole` runs
**Then** output includes a section with tag `agent-role`, priority `:important`, containing the agent's system prompt
**And** `applicable?` returns `false` when no agent is configured

**Given** a session with project, agent_type, and mode
**When** `ContextBuilders::SessionInfo` runs
**Then** output includes a section with tag `session-context`, priority `:info`, containing session ID, agent runtime, mode, project name

**Given** a session with `input_asset_ids` and `repository_ids`
**When** `ContextBuilders::Workspace` runs
**Then** output includes a section with tag `workspace`, priority `:important`, describing `/workspace/outputs/`, `/workspace/assets/`, `/workspace/repo/`

**Given** a session with MCP servers, tools, and skills
**When** `ContextBuilders::Tools` and `ContextBuilders::Resources` run
**Then** output includes sections for `shell-tools`, `mcp-servers`, `custom-tools` (priority `:info`) and `available-resources` (priority `:info`)

**Given** a session without custom tools
**When** `ContextBuilders::Tools` builds
**Then** no `custom-tools` section is produced (only applicable sections)

**Technical notes:**
- Content generation logic extracted 1:1 from existing `SessionContextService` private methods
- Each builder returns `Array<ContextSection>` — some builders produce multiple sections (Tools produces shell + mcp + custom)

---

### Story 25.4: OutputRules Builder & Sandwich Pattern

**As a** system,
**I want** an OutputRules builder that places critical output rules at the bottom of context,
**So that** agents see critical rules both at the start (CriticalRules) and end (OutputRules) of context — sandwich pattern.

**Acceptance Criteria:**

**Given** any session type
**When** `ContextBuilders::OutputRules` builds
**Then** output includes a section with tag `output-rules`, priority `:critical`, position_hint `:bottom`
**And** content includes rules about saving to `/workspace/outputs/`, read-only assets, and using MCP tools

**Given** a workflow step session (session.step_run present)
**When** OutputRules builds
**Then** content additionally includes: "Marking the last sub-step completed triggers session termination — ensure all files are saved first"

**Technical notes:**
- Sandwich pattern: CriticalRules at `:top` + OutputRules at `:bottom` → LLMs remember start and end of context best
- Content extracted from current `build_general_instructions` method

---

### Story 25.5: SessionContextConstructor Orchestrator & ContextResult

**As a** system,
**I want** a SessionContextConstructor that orchestrates all builders and returns a ContextResult with both XML-markdown rendering and JSON traceability,
**So that** a single `.build(session)` produces the context string, and `.build_result(session)` additionally provides structured metadata for debugging and audit.

**Acceptance Criteria:**

**Given** a standalone session with agent, MCP servers, tools, and repos
**When** `SessionContextConstructor.build(session)` is called
**Then** returns a string with XML sections: `critical-rules`, `agent-role`, `session-context`, `workspace`, `shell-tools`, `mcp-servers`, `custom-tools`, `available-resources`, `output-rules`
**And** output does NOT contain `workflow-context`, `current-step`, or `board-context` sections
**And** `critical-rules` appears before all other sections
**And** `output-rules` appears after all other sections

**Given** the same session
**When** `SessionContextConstructor.build_result(session)` is called
**Then** returns a `ContextResult` object with:
  - `.render` → same XML-markdown string as `.build`
  - `.to_json_hash` → structured hash with `session_id`, `session_type`, `applied_builders`, `skipped_builders`, `total_content_length`, `build_time_ms`, and `sections` metadata
  - `.applied_builders` → `["critical_rules", "agent_role", "session_info", ...]`
  - `.skipped_builders` → `["workflow_context", "board_context"]`
  - `.total_content_length` → integer sum of all section content lengths

**Given** a session where AgentRole builder's `applicable?` returns false
**When** Constructor runs
**Then** `"agent_role"` appears in `skipped_builders`, not in `applied_builders`

**Given** the BUILDERS constant array
**When** a new builder is added
**Then** it only needs to be appended to the array — no other orchestrator changes required

**Technical notes:**
- Two class methods: `.build(session)` → string (simple), `.build_result(session)` → ContextResult (full)
- `ContextResult` is a frozen value object: `render`, `to_json_hash`, `to_json`, `total_content_length`, `applied_builders`, `skipped_builders`
- `build_time_ms` measured via `Process.clock_gettime(Process::CLOCK_MONOTONIC)`
- `detect_session_type`: board_task → "board_triggered", step_run → "workflow_step", else → "standalone"
- Files: `app/services/session_context_constructor.rb`, `app/services/context_result.rb`

---

### Story 25.6: Context Traceability Storage & API

**As a** developer,
**I want** the context metadata saved on each session and available via API,
**So that** I can debug what context an agent received, which builders ran, and how large each section was.

**Acceptance Criteria:**

**Given** a session whose context is being assembled
**When** `SessionContextService#inject_context_file` runs
**Then** `session.context_metadata` is updated with the JSON hash from `ContextResult#to_json_hash`

**Given** a completed session with `context_metadata` stored
**When** `GET /api/v1/company/terminal_sessions/:id` is called
**Then** the response includes `context_metadata` field with structured builder/section data

**Given** `terminal_sessions` table
**When** migration runs
**Then** `context_metadata` column (JSONB, nullable, default nil) is added

**Technical notes:**
- Migration: `add_column :terminal_sessions, :context_metadata, :jsonb`
- Serializer: include `context_metadata` in `TerminalSessionSerializer` (show action only)
- Only metadata stored, NOT rendered content — content can be re-generated from session
- Storage cost: ~500 bytes per session

---

### Story 25.7: Integrate Constructor into SessionContextService

**As a** system,
**I want** `SessionContextService#build_context_content` to delegate to `SessionContextConstructor`,
**So that** the unified pipeline replaces fragmented context generation without changing the external interface.

**Acceptance Criteria:**

**Given** the existing `SessionContextService#inject_context_file` flow
**When** session context is assembled via `assemble_session_context`
**Then** context file content is produced by `SessionContextConstructor.build_result(session)`
**And** `.render` output is written to the adapter-specific path (CLAUDE.md / AGENTS.md / GEMINI.md)
**And** `.to_json_hash` is saved to `session.context_metadata`
**And** all existing `SessionContextService` tests continue to pass (backward compatibility)

**Given** the old `build_context_content` and its helper methods
**When** this story is complete
**Then** old methods (`build_context_content`, `build_agent_persona`, `build_session_context`, `build_workspace_layout`, `build_shell_tools_section`, `build_mcp_descriptions`, `build_tool_descriptions`, `build_skills_section`, `build_repositories_section`, `build_general_instructions`, `tool_execution_modes_section`) are removed from `SessionContextService`

**Technical notes:**
- Key migration point — external interface unchanged, internal implementation replaced
- `SessionContextService#inject_context_file` uses `SessionContextConstructor.build_result(session)` — both `.render` and `.to_json_hash`
- Run full test suite to verify backward compatibility

---

## Dependency Graph

```
Story 25.1 (ContextSection + Renderer)
    │
    └──→ Story 25.2 (Base + CriticalRules builder)
             │
             └──→ Story 25.3 (Core builders)
                      │
                      └──→ Story 25.4 (OutputRules + sandwich)
                               │
                               └──→ Story 25.5 (Constructor + ContextResult)
                                        │
                                        ├──→ Story 25.6 (Traceability storage + API)
                                        │
                                        └──→ Story 25.7 (Integration + cleanup)
```

---

## Implementation Notes

- All builders live in `app/services/context_builders/` directory
- Content generation logic is extracted 1:1 from `SessionContextService` — no behavioral changes in output during migration
- XML tags add ~2-5% token overhead which is acceptable for improved instruction adherence
- Constructor output works with all 4 agent adapters (ClaudeCode, CursorCli, Codex, GeminiCli) — adapter determines file path, Constructor provides content
- Session-centric API: callers pass `TerminalSession`, never pass flags or type hints — builders discover context via `applicable?`
- ContextResult provides dual interface: `.render` for agents, `.to_json` for observability
- `context_metadata` JSONB column enables future debug UI without re-building context
- Testing: each builder tested in isolation; ContextResult tested for both render and JSON; integration test verifies full Constructor output
