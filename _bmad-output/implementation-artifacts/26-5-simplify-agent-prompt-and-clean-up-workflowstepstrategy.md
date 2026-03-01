# Story 26.5: Simplify AGENT_PROMPT & Clean Up WorkflowStepStrategy

Status: done

## Story

As a system,
I want `WorkflowStepStrategy#build_env_vars` to set `AGENT_PROMPT` to only the step instructions (or user prompt), not the full workflow context,
So that context file and AGENT_PROMPT have clear responsibilities without duplication.

## Acceptance Criteria

1. **AGENT_PROMPT contains only step instructions** — Given a workflow step session where `WorkflowStepStrategy` builds env vars, when `AGENT_PROMPT` is set, then its value contains only `step.instructions` (the task — what to do)

2. **No duplicated context in AGENT_PROMPT** — Given the `AGENT_PROMPT` value, when inspected, then it does NOT contain workflow overview, sub-steps checklist, repos, tools, or MCP descriptions (those are in the context file via Constructor)

3. **build_workflow_prompt simplified** — Given the current `build_workflow_prompt` method in `WorkflowStepStrategy`, when this story is complete, then `build_workflow_prompt` is simplified to return only `step.instructions`

4. **Legacy context methods removed** — Given `build_session_context_section`, `build_sub_steps_section`, `build_workflow_tools_section` in `WorkflowStepStrategy`, when this story is complete, then these methods are removed (their functionality is now in `ContextBuilders::WorkflowContext`)

5. **Existing workflow tests pass** — Given the full test suite, when run after changes, then all existing tests pass (no regressions)

## Tasks / Subtasks

- [x] Task 1: Simplify build_workflow_prompt (AC: #1, #2, #3)
  - [x] Replace `build_workflow_prompt` body: return only `step.instructions`
  - [x] Remove calls to `build_session_context_section`, `build_sub_steps_section`, `build_workflow_tools_section`
- [x] Task 2: Remove legacy methods (AC: #4)
  - [x] Delete `build_session_context_section` method
  - [x] Delete `build_sub_steps_section` method
  - [x] Delete `build_workflow_tools_section` method
- [x] Task 3: Update tests (AC: #5)
  - [x] No WorkflowStepStrategy tests existed for legacy methods — confirmed no regressions
  - [x] Verified all 82 Epic 25+26 tests pass (300 assertions, 0 failures)
  - [x] Verified all 536 services tests pass with only pre-existing failures (9 from BoardPresets and SessionContextService adapter commands)
- [x] Task 4: Verify end-to-end (AC: #1, #2, #5)
  - [x] Verify context file (via Constructor) contains workflow-context, current-step, sub-steps, workflow-tools sections
  - [x] Verify AGENT_PROMPT contains only step instructions
  - [x] Run full regression suite — no new failures

## Dev Notes

### Architecture Patterns

- **Key principle:** Context file = who you are + what you know + rules. AGENT_PROMPT = what to do.
- **Separation of concerns:** Constructor handles all context assembly via builders. Strategy only sets AGENT_PROMPT to the task prompt.
- **No duplication:** Repos, assets, MCP descriptions, sub-steps — all in context file only. Not repeated in AGENT_PROMPT.

### Implementation Details

- `build_workflow_prompt(step, step_run)` currently returns: session_context + instructions + sub_steps + workflow_tools
- After change: returns only `step.instructions`
- Three methods to delete from WorkflowStepStrategy:
  1. `build_session_context_section(step_run)` — repos and assets context (now in Resources builder)
  2. `build_sub_steps_section(sub_steps, step_run)` — sub-steps checklist (now in WorkflowContext builder)
  3. `build_workflow_tools_section` — workflow tool descriptions (now in WorkflowContext builder)
- `CONFIGURED_AGENT_PERSONA` and `CONFIGURED_AGENT_PRINCIPLES` env vars stay — they're used by some adapters for system-level prompt injection separate from context file

### Existing Code Context

- File: `app/services/container_strategies/workflow_step_strategy.rb`
- `build_env_vars` calls `build_workflow_prompt(step, step_run)` → result goes into `AGENT_PROMPT`
- `build_workflow_prompt` currently assembles: session_context + instructions + sub_steps + tools
- After Epic 25+26.1-26.4: Constructor generates XML-tagged context file with all sections
- The 3 legacy methods duplicate content now handled by:
  - `build_session_context_section` → `ContextBuilders::Resources` + `ContextBuilders::Workspace`
  - `build_sub_steps_section` → `ContextBuilders::WorkflowContext` (sub-steps section)
  - `build_workflow_tools_section` → `ContextBuilders::WorkflowContext` (workflow-tools section)

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/container_strategies/workflow_step_strategy_test.rb`
- **Regression:** `docker exec app-web-1 bundle exec rails test` (full suite)

### Project Structure Notes

- Modified file: `app/services/container_strategies/workflow_step_strategy.rb`
- Modified tests: `test/services/container_strategies/workflow_step_strategy_test.rb` (or similar location)
- No new files created

### References

- [Source: ai/epics/epic-26-workflow-context-in-sessions.md#Story 26.5] — Acceptance criteria
- [Source: app/services/container_strategies/workflow_step_strategy.rb] — Current WorkflowStepStrategy (200-277 lines of legacy methods)
- [Source: ai/session-context-constructor.md#10 Integration Plan Phase 4-6] — Migration plan
- [Source: ai/project-context.md#Container Strategy Pattern] — Strategy pattern standards

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

All tasks completed. Simplified `build_workflow_prompt` to return only `step.instructions`. Removed 3 legacy methods (75 lines). All 82 Epic 25+26 tests pass (300 assertions, 0 failures). Pre-existing failures in BoardPresets and SessionContextService adapter tests are not related to Epic 26 changes.

### File List

- app/services/container_strategies/workflow_step_strategy.rb (modified — simplified build_workflow_prompt, removed build_session_context_section, build_sub_steps_section, build_workflow_tools_section)
