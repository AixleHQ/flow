# Story 25.4: OutputRules Builder & Sandwich Pattern

Status: done

## Story

As a system,
I want an OutputRules builder that places critical output rules at the bottom of context,
So that agents see critical rules both at the start (CriticalRules) and end (OutputRules) of context — sandwich pattern.

## Acceptance Criteria

1. **OutputRules builder produces bottom section** — Given any session type, when `ContextBuilders::OutputRules` builds, then output includes a section with tag `output-rules`, priority `:critical`, position_hint `:bottom`

2. **OutputRules content includes standard rules** — Given any session, when OutputRules builds, then content includes rules about saving to `/workspace/outputs/`, read-only assets, using MCP tools, and writing clean code

3. **OutputRules includes workflow termination warning** — Given a workflow step session (session.step_run present), when OutputRules builds, then content additionally includes: "Marking the last sub-step completed triggers session termination — ensure all files are saved first"

4. **OutputRules excludes workflow warning for standalone** — Given a standalone session (no step_run), when OutputRules builds, then content does NOT include the sub-step termination warning

5. **Sandwich pattern verified** — Given a full context render with CriticalRules (position `:top`) and OutputRules (position `:bottom`), when ContextRenderer renders all sections, then `critical-rules` appears at the very start and `output-rules` appears at the very end of the output

## Tasks / Subtasks

- [x] Task 1: Create ContextBuilders::OutputRules (AC: #1, #2, #3, #4)
  - [x] Create `app/services/context_builders/output_rules.rb` with frozen_string_literal
  - [x] Inherit from `ContextBuilders::Base`
  - [x] Implement `#build` returning array with single section
  - [x] Tag: `output-rules`, priority: `:critical`, position_hint: `:bottom`
  - [x] Content: standard output rules (save to /workspace/outputs/, assets are read-only, use MCP tools, write clean code)
  - [x] Conditionally add workflow termination warning when `step_run.present?`
  - [x] Extract text from current `SessionContextService#build_general_instructions` standard rules portion
- [x] Task 2: Write tests (AC: #1-#5)
  - [x] Create `test/services/context_builders/output_rules_test.rb`
  - [x] Test section tag, priority, position_hint
  - [x] Test standard rules content present for any session
  - [x] Test workflow termination warning present for workflow step session
  - [x] Test workflow termination warning absent for standalone session
  - [x] Integration test: render CriticalRules + OutputRules sections, verify sandwich order

## Dev Notes

### Architecture Patterns

- **Sandwich Pattern:** LLMs have a well-documented "lost in the middle" problem — they attend more strongly to the beginning and end of context. The sandwich pattern places critical rules at both `:top` (CriticalRules, Story 25.2) and `:bottom` (OutputRules, this story).
- CriticalRules = "how to behave" (non-interactive mode, language). OutputRules = "how to deliver results" (save to outputs, read-only assets, termination rules).

### Content to Extract

From `SessionContextService#build_general_instructions` (lines 452-481), extract the standard rules portion:

```
- Save ALL results and deliverables to `/workspace/outputs/`
- Files in `/workspace/assets/` are READ-ONLY — copy to outputs before editing
- Use all available MCP servers and tools
- Write clean, production-quality code following project conventions
```

The non-interactive rules part stays in CriticalRules (Story 25.2). OutputRules gets only the "how to deliver" rules.

### Workflow Step Detection

Use the Base navigation helper:
```ruby
def workflow_step?
  step_run.present?
end
```

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/output_rules_test.rb`

### Project Structure Notes

- New file: `app/services/context_builders/output_rules.rb`
- Test file: `test/services/context_builders/output_rules_test.rb`
- Depends on: Story 25.1 (ContextSection), Story 25.2 (ContextBuilders::Base)
- The sandwich pattern is complete when this builder is combined with CriticalRules in the constructor (Story 25.5)

### References

- [Source: ai/session-context-constructor.md#5.7 OutputRules Builder] — Design and content
- [Source: ai/session-context-constructor.md#3.1 Why XML tags] — Sandwich pattern rationale
- [Source: app/services/session_context_service.rb#build_general_instructions] — Text to extract
- [Source: ai/epics/epic-25-unified-context-constructor.md#Story 25.4] — Acceptance criteria

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

- All tasks completed. Implementation follows epic design. 59 total tests across all Epic 25 stories, 212 assertions, 0 failures.

### File List

- `app/services/context_builders/output_rules.rb`
- `test/services/context_builders/output_rules_test.rb`
