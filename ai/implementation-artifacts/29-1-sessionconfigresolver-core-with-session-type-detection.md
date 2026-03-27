# Story 29.1: SessionConfigResolver Core with Session Type Detection

Status: done

## Story

As a system,
I want a SessionConfigResolver that accepts a TerminalSession and determines the session type (standalone / workflow / board_triggered),
So that config resolution logic has a single entry point and can branch based on session origin.

## Acceptance Criteria

1. **Session type detection — board_triggered** — Given a TerminalSession with `step_run` present and `workflow_run.board_task` present, when `SessionConfigResolver.resolve(session)` is called, then result includes `session_type: :board_triggered`

2. **Session type detection — workflow** — Given a TerminalSession with `step_run` present and no `board_task`, when resolver runs, then result includes `session_type: :workflow`

3. **Session type detection — standalone** — Given a TerminalSession with no `step_run`, when resolver runs, then result includes `session_type: :standalone`

4. **Standalone pass-through** — Given a standalone session with tool_ids, skill_ids, mcp_server_ids, repository_ids, input_asset_ids, agent_type, mode already set, when resolver runs, then result returns those values directly (no merging, no transformation)

5. **Return structure** — Given any session, when resolver runs, then result is a Hash with keys: `session_type`, `agent_runtime`, `configured_agent_id`, `tool_ids`, `skill_ids`, `mcp_server_ids`, `repository_ids`, `input_asset_ids`, `mode`

6. **Class method API** — `SessionConfigResolver.resolve(session)` is the single entry point, delegates to `new(session).resolve`

## Tasks / Subtasks

- [x] Task 1: Create `SessionConfigResolver` service (AC: #5, #6)
  - [x] Create `app/services/session_config_resolver.rb`
  - [x] Implement `self.resolve(session)` class method
  - [x] Add navigation helpers: `user`, `project`, `step_run`, `workflow_run`, `workflow`, `step`, `board_task`
  - [x] Add predicate helpers: `workflow_session?`, `board_triggered?`, `standalone_session?`
- [x] Task 2: Implement `session_type` detection (AC: #1, #2, #3)
  - [x] `board_triggered` when `step_run.present?` AND `workflow_run.board_task.present?`
  - [x] `workflow` when `step_run.present?` AND no board_task
  - [x] `standalone` when no step_run
- [x] Task 3: Implement standalone pass-through (AC: #4)
  - [x] For standalone: read `session.tool_ids` from HABTM `session.tools.pluck(:id)`
  - [x] Same for skill_ids, mcp_server_ids, repository_ids, input_asset_ids
  - [x] `agent_runtime` = `session.agent_type`
  - [x] `mode` = `session.mode`
  - [x] `configured_agent_id` = `session.configured_agent_id`
- [x] Task 4: Stub workflow/board resolution methods (AC: #5)
  - [x] `resolve_tool_ids` — for workflow sessions, return `step.tool_ids || []` (full merge in 29.2)
  - [x] Same pattern for skill_ids, mcp_server_ids
  - [x] `resolve_agent_runtime` — return `workflow_run.agent_runtime || "claude_code"` (full chain in 29.5)
  - [x] `resolve_input_asset_ids` — return `workflow_run.input_asset_ids || []`
  - [x] `resolve_repository_ids` — return step mount_repositories logic
  - [x] `resolve_mode` — workflow run mode logic
- [x] Task 5: Write tests (AC: #1-#6)
  - [x] Create `test/services/session_config_resolver_test.rb`
  - [x] Test standalone session pass-through
  - [x] Test workflow session type detection
  - [x] Test board_triggered session type detection
  - [x] Test return hash structure has all required keys

## Dev Notes

### Architecture Patterns

- **Service object pattern** — mirrors `SessionContextConstructor`: class method `self.resolve(session)` wraps `new(session).resolve`
- **Navigation helpers** use Ruby's endless method syntax: `def user = session.user`
- **TerminalSession associations** — tools/skills/mcp_servers/input_assets/repositories are HABTM associations (Epic 16, Story 16.9). To read IDs: `session.tools.pluck(:id)` or `session.tool_ids` (HABTM provides `_ids` accessor)
- **agent_type vs agent_runtime** — the DB column on `terminal_sessions` is `agent_type` (string: `claude_code`, `cursor_cli`, `codex`, `gemini_cli`). The resolver output key is `agent_runtime` to match the design document naming

### Existing Code Context

- `SessionContextConstructor` (app/services/session_context_constructor.rb) — same `session`-centric pattern, 48 lines, builds context sections from builders
- `ContextResult#detect_session_type` (app/services/context_result.rb, lines 51-59) — already has session type detection logic, same 3 types. Resolver should use identical logic
- `LaunchStepSessionActivity` (app/temporal/activities/workflow/launch_step_session_activity.rb) — currently builds session config ad-hoc in `attach_resources!`. Integration point for Story 29.6
- `WorkflowRun#board_task` — `belongs_to :board_task, optional: true` — used for board_triggered detection
- `TerminalSession#step_run` — `has_one :step_run, dependent: :nullify` — used for workflow detection

### File Locations

- New file: `app/services/session_config_resolver.rb`
- New test: `test/services/session_config_resolver_test.rb`

### Testing Standards

- **Framework:** Minitest with FactoryBot
- **Mocking:** Mocha
- **Run:** `docker exec app-web-1 bundle exec rails test test/services/session_config_resolver_test.rb`
- Use existing factories: `:terminal_session`, `:step_run`, `:workflow_run`, `:workflow`
- For board_triggered: ensure workflow_run factory supports `board_task` association

### References

- [Source: ai/session-config-cascade.md#5] — SessionConfigResolver full design with code
- [Source: ai/epics/epic-29-session-config-resolver.md#Story 29.1] — Story definition and AC
- [Source: app/services/context_result.rb#51-59] — Existing session type detection pattern
- [Source: app/services/session_context_constructor.rb] — Service pattern to mirror
- [Source: app/temporal/activities/workflow/launch_step_session_activity.rb] — Current ad-hoc config resolution

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
