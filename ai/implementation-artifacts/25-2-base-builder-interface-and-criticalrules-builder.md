# Story 25.2: Base Builder Interface & CriticalRules Builder

Status: done

## Story

As a system,
I want a base builder class with navigation helpers and a CriticalRules builder that generates non-interactive mode rules and language preferences,
So that mandatory agent rules are always present at the top of context, and all builders share a clean interface.

## Acceptance Criteria

1. **CriticalRules builder for non-interactive session with language** — Given a TerminalSession in `non_interactive` mode with user `preferred_agent_language` set to "Russian", when `ContextBuilders::CriticalRules` builder builds sections, then output includes a ContextSection with tag `critical-rules`, priority `:critical`, position_hint `:top`, and content includes non-interactive mode rules ("NEVER ask questions", "Save ALL results") AND language rule ("Communication Language: Russian"), and section's `builder_name` is `"critical_rules"`

2. **CriticalRules builder for interactive session without language** — Given a TerminalSession in `interactive` mode with no preferred language, when CriticalRules builder builds sections, then output section has no non-interactive rules and no language directive (content may be minimal or empty — builder should still produce a section with general critical rules if any, or return empty array if nothing applies)

3. **Base builder `applicable?` returns true by default** — Given any builder subclass, when `applicable?` is called, then it returns `true` by default (subclasses override as needed)

4. **Base builder `build` raises NotImplementedError** — Given the base builder directly, when `build` is called, then `NotImplementedError` is raised

5. **Base builder `section` helper auto-populates builder_name** — Given a builder subclass, when `section(tag:, priority:, content:)` helper is called, then `builder_name` is auto-populated from `self.name` which returns the demodulized, underscored class name

6. **Base builder navigation helpers** — Given a builder with a session that has `step_run → workflow_run → workflow → board_task`, when navigation helpers are called, then `project` returns `session.project`, `step_run` returns `session.step_run`, `workflow_run` returns `step_run.workflow_run`, `workflow` returns `workflow_run.workflow`, `board_task` returns `workflow_run.board_task`, `step` returns `step_run.step`

7. **Navigation helpers return nil safely** — Given a standalone session (no step_run), when `workflow_run`, `workflow`, `board_task`, `step` helpers are called, then they return `nil` without raising NoMethodError (safe navigation)

8. **CriticalRules non-interactive content backward compatible** — The non-interactive rules text must match the behavior of the current `SessionContextService#build_general_instructions` non-interactive section for backward compatibility

## Tasks / Subtasks

- [x] Task 1: Create ContextBuilders::Base abstract class (AC: #3, #4, #5, #6, #7)
  - [x] Create directory `app/services/context_builders/`
  - [x] Create `app/services/context_builders/base.rb` with frozen_string_literal
  - [x] Define `attr_reader :session` and `initialize(session)`
  - [x] Implement `#build` raising `NotImplementedError`
  - [x] Implement `#applicable?` returning `true`
  - [x] Implement `#name` → `self.class.name.demodulize.underscore`
  - [x] Implement private `section(tag:, priority:, content:, position_hint: :middle)` → creates `ContextSection.new` with `builder_name: name`
  - [x] Implement private navigation helpers: `project`, `step_run`, `workflow_run`, `workflow`, `board_task`, `step` — all using safe navigation (`&.`)
- [x] Task 2: Create ContextBuilders::CriticalRules builder (AC: #1, #2, #8)
  - [x] Create `app/services/context_builders/critical_rules.rb` with frozen_string_literal
  - [x] Inherit from `ContextBuilders::Base`
  - [x] Implement `#build` returning array of ContextSection
  - [x] Build non-interactive mode rules matching current `SessionContextService#build_general_instructions` text when `session.mode == "non_interactive"`
  - [x] Build language rule from `session.user&.preferred_agent_language`
  - [x] Combine rules into single section with tag `critical-rules`, priority `:critical`, position_hint `:top`
  - [x] Return empty array if no rules apply (interactive mode + no language preference)
- [x] Task 3: Write tests (AC: #1-#8)
  - [x] Create `test/services/context_builders/base_test.rb`
  - [x] Test `applicable?` returns true
  - [x] Test `build` raises NotImplementedError
  - [x] Test `name` returns underscored class name
  - [x] Test `section` helper auto-fills builder_name
  - [x] Test navigation helpers with workflow session
  - [x] Test navigation helpers with standalone session (nil safety)
  - [x] Create `test/services/context_builders/critical_rules_test.rb`
  - [x] Test non-interactive mode with language preference
  - [x] Test interactive mode without language preference
  - [x] Test non-interactive rules content matches backward-compatible text

## Dev Notes

### Architecture Patterns

- **Builder Pattern:** All context builders inherit from `ContextBuilders::Base`. Each builder has three responsibilities: (1) decide if applicable via `applicable?`, (2) produce `Array<ContextSection>` via `build`, (3) self-describe via `name`.
- **Session-Centric API:** Builders receive only `TerminalSession` — they discover context themselves via navigation helpers. Callers NEVER pass flags or type hints.
- **Navigation Helpers:** Builders use `project`, `step_run`, `workflow_run`, `workflow`, `board_task`, `step` — they NEVER traverse raw associations like `session.step_run.workflow_run.workflow.name`. This creates a clean interface boundary.

### Existing Code to Extract From

The non-interactive rules text in CriticalRules builder MUST match `SessionContextService#build_general_instructions` (lines 452-481 in `app/services/session_context_service.rb`). Key text to extract:

```
This session runs **non-interactively** — there is NO human to respond.
- NEVER ask questions, request clarifications, or wait for input
- NEVER present options and ask the user to choose
- NEVER stop mid-task saying you need more information
- Make reasonable assumptions when details are missing and document them
- Save ALL results to `/workspace/outputs/`
```

The language preference currently lives in `build_session_context` (line 312-314). In the new architecture, it moves to CriticalRules as a critical-priority rule.

### Key Associations for Navigation Helpers

```
TerminalSession
  ├── project (belongs_to)
  ├── step_run (belongs_to, optional) → StepRun
  │     ├── step (belongs_to) → Step
  │     └── workflow_run (belongs_to) → WorkflowRun
  │           ├── workflow (belongs_to) → Workflow
  │           └── board_task (belongs_to, optional) → Task
  └── user (belongs_to)
```

### Testing Standards

- **Framework:** Minitest
- **Mocks:** mocha gem
- **Factories:** Use `factory_bot_rails` — session factories like `:terminal_session` exist. Use traits if available (`:standalone`, `:workflow_step`), or create sessions with appropriate associations.
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/`

### Project Structure Notes

- New directory: `app/services/context_builders/`
- New files: `app/services/context_builders/base.rb`, `app/services/context_builders/critical_rules.rb`
- Test files: `test/services/context_builders/base_test.rb`, `test/services/context_builders/critical_rules_test.rb`
- Depends on: Story 25.1 (ContextSection value object)

### References

- [Source: ai/session-context-constructor.md#4.3 Builder Interface] — Base builder design
- [Source: ai/session-context-constructor.md#5.1 CriticalRules Builder] — CriticalRules implementation
- [Source: app/services/session_context_service.rb#build_general_instructions] — Non-interactive rules text to extract
- [Source: app/services/session_context_service.rb#build_session_context] — Language preference text to extract
- [Source: ai/epics/epic-25-unified-context-constructor.md#Story 25.2] — Acceptance criteria

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- All tasks completed. Implementation follows epic design. 59 total tests across all Epic 25 stories, 212 assertions, 0 failures.

### File List

- `app/services/context_builders/base.rb`
- `app/services/context_builders/critical_rules.rb`
- `test/services/context_builders/base_test.rb`
- `test/services/context_builders/critical_rules_test.rb`
