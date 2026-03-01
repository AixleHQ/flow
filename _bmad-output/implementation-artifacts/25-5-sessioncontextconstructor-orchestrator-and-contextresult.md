# Story 25.5: SessionContextConstructor Orchestrator & ContextResult

Status: done

## Story

As a system,
I want a SessionContextConstructor that orchestrates all builders and returns a ContextResult with both XML-markdown rendering and JSON traceability,
So that a single `.build(session)` produces the context string, and `.build_result(session)` additionally provides structured metadata for debugging and audit.

## Acceptance Criteria

1. **Constructor.build returns XML-markdown string** — Given a standalone session with agent, MCP servers, tools, and repos, when `SessionContextConstructor.build(session)` is called, then returns a string with XML sections: `critical-rules`, `agent-role`, `session-context`, `workspace`, `shell-tools`, `mcp-servers`, `custom-tools`, `available-resources`, `output-rules`

2. **Constructor excludes non-applicable builders** — Given the same standalone session, then output does NOT contain `workflow-context`, `current-step`, or `board-context` sections

3. **Sandwich pattern enforced** — Given any session, when Constructor builds, then `critical-rules` appears before all other sections AND `output-rules` appears after all other sections

4. **Constructor.build_result returns ContextResult** — Given a session, when `SessionContextConstructor.build_result(session)` is called, then returns a `ContextResult` object with `.render` (XML-markdown string same as `.build`), `.to_json_hash` (structured hash), `.applied_builders`, `.skipped_builders`, `.total_content_length`

5. **ContextResult.to_json_hash structure** — The hash contains: `session_id`, `session_type`, `project_id`, `built_at` (ISO8601), `build_time_ms`, `total_content_length` (integer), `applied_builders` (array of strings), `skipped_builders` (array of strings), and `sections` (array of section metadata hashes with `tag`, `priority`, `position_hint`, `builder`, `content_length`)

6. **Skipped builders tracked** — Given a session where AgentRole builder's `applicable?` returns false (no configured agent), when Constructor runs, then `"agent_role"` appears in `skipped_builders`, not in `applied_builders`

7. **Session type detection** — `detect_session_type` returns `"board_triggered"` if `session.step_run.workflow_run.board_task` present, `"workflow_step"` if `session.step_run` present, `"standalone"` otherwise

8. **BUILDERS constant is append-only** — Given the BUILDERS constant array, when a new builder is added, then it only needs to be appended to the array — no other orchestrator changes required

9. **Build time measured** — `build_time_ms` in ContextResult is measured via `Process.clock_gettime(Process::CLOCK_MONOTONIC)` and is a positive float

10. **ContextResult is frozen** — ContextResult sections array and builder arrays are frozen after creation

## Tasks / Subtasks

- [x] Task 1: Create ContextResult value object (AC: #4, #5, #7, #9, #10)
  - [x] Create `app/services/context_result.rb` with frozen_string_literal
  - [x] Define `attr_reader :session, :sections, :applied_builders, :skipped_builders, :built_at, :build_time_ms`
  - [x] Implement `initialize` freezing sections, applied_builders, skipped_builders arrays
  - [x] Implement `#render` → delegates to `ContextRenderer.render(@sections)`
  - [x] Implement `#to_s` as alias for `#render`
  - [x] Implement `#total_content_length` → `sections.sum { |s| s.content.length }`
  - [x] Implement `#to_json_hash` with full structure including session_id, session_type, project_id, built_at (ISO8601), build_time_ms, total_content_length, applied_builders, skipped_builders, sections metadata
  - [x] Implement `#to_json(*args)` → `to_json_hash.to_json(*args)`
  - [x] Implement private `#detect_session_type` → board_triggered / workflow_step / standalone
  - [x] Implement private `#section_metadata(section)` → `{ tag:, priority:, position_hint:, builder:, content_length: }`
- [x] Task 2: Create SessionContextConstructor orchestrator (AC: #1, #2, #3, #6, #8)
  - [x] Create `app/services/session_context_constructor.rb` with frozen_string_literal
  - [x] Define BUILDERS constant array (CriticalRules, AgentRole, SessionInfo, Workspace, Tools, Resources, OutputRules) — note: WorkflowContext and BoardContext are NOT included yet (Epic 26, 27)
  - [x] Implement `self.build(session)` → `new(session).build.render`
  - [x] Implement `self.build_result(session)` → `new(session).build`
  - [x] Implement `#build`:
    - Measure start time via `Process.clock_gettime(Process::CLOCK_MONOTONIC)`
    - Instantiate all BUILDERS with session
    - Partition into applicable/skipped via `applicable?`
    - Collect sections via `flat_map(&:build).compact`
    - Measure elapsed_ms
    - Return `ContextResult.new(session:, sections:, applied_builders:, skipped_builders:, built_at:, build_time_ms:)`
- [x] Task 3: Write tests (AC: #1-#10)
  - [x] Create `test/services/context_result_test.rb`
  - [x] Test render delegates to ContextRenderer
  - [x] Test to_json_hash structure with all required keys
  - [x] Test detect_session_type for standalone, workflow_step, board_triggered
  - [x] Test total_content_length calculation
  - [x] Test frozen arrays
  - [x] Create `test/services/session_context_constructor_test.rb`
  - [x] Test standalone session: critical-rules and output-rules present, workflow-context absent
  - [x] Test applied_builders and skipped_builders tracking
  - [x] Test build_time_ms is positive
  - [x] Test BUILDERS constant is frozen array

## Dev Notes

### Architecture Patterns

- **Two-API Design:** `.build(session)` for simple string output (used by most callers), `.build_result(session)` for full ContextResult (used by traceability in Story 25.6).
- **Open-Closed Principle:** Adding a new builder = append to BUILDERS array. No switch statements, no type checks in orchestrator.
- **Builder Discovery:** Constructor doesn't know about session types. Builders self-select via `applicable?`.

### BUILDERS Array (Epic 25 scope)

```ruby
BUILDERS = [
  ContextBuilders::CriticalRules,    # Story 25.2
  ContextBuilders::AgentRole,        # Story 25.3
  ContextBuilders::SessionInfo,      # Story 25.3
  ContextBuilders::Workspace,        # Story 25.3
  ContextBuilders::Tools,            # Story 25.3
  ContextBuilders::Resources,        # Story 25.3
  ContextBuilders::OutputRules,      # Story 25.4
].freeze
```

**Note:** `WorkflowContext` (Epic 26) and `BoardContext` (Epic 27) will be appended later. The orchestrator requires NO changes when they are added.

### Session Type Detection Logic

```ruby
def detect_session_type
  if session.step_run&.workflow_run&.board_task.present?
    "board_triggered"
  elsif session.step_run.present?
    "workflow_step"
  else
    "standalone"
  end
end
```

### Performance Notes

- Build time is measured with monotonic clock for accuracy (not affected by system time changes)
- Typical build time expected: 1-15ms (pure Ruby, no DB queries in orchestrator — builders handle their own data loading)
- `ContextResult#render` is lazy — only calls `ContextRenderer.render` when accessed

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Integration style:** Create real session with associations, run full Constructor, assert on output structure
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/session_context_constructor_test.rb test/services/context_result_test.rb`

### Project Structure Notes

- New files: `app/services/session_context_constructor.rb`, `app/services/context_result.rb`
- Test files: `test/services/session_context_constructor_test.rb`, `test/services/context_result_test.rb`
- Depends on: Stories 25.1 (ContextSection, ContextRenderer), 25.2 (Base, CriticalRules), 25.3 (Core builders), 25.4 (OutputRules)

### References

- [Source: ai/session-context-constructor.md#4.4 Constructor] — Orchestrator design
- [Source: ai/session-context-constructor.md#4.5 ContextResult] — ContextResult design
- [Source: ai/epics/epic-25-unified-context-constructor.md#Story 25.5] — Acceptance criteria

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- All tasks completed. Implementation follows epic design. 59 total tests across all Epic 25 stories, 212 assertions, 0 failures.

### File List

- `app/services/session_context_constructor.rb`
- `app/services/context_result.rb`
- `test/services/session_context_constructor_test.rb`
- `test/services/context_result_test.rb`
