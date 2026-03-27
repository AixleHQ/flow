# Story 26.1: WorkflowContext Builder

Status: done

## Story

As a system,
I want a WorkflowContext builder that produces workflow overview and current step sections,
So that workflow agents see their workflow position and step instructions in the context file.

## Acceptance Criteria

1. **WorkflowContext applicable only for workflow sessions** — Given a session with `step_run` present (workflow step session), when `ContextBuilders::WorkflowContext#applicable?` is called, then it returns `true`

2. **Not applicable for standalone sessions** — Given a standalone session (no step_run), when `applicable?` is called, then it returns `false`

3. **Produces workflow-context section** — Given a workflow step session, when `WorkflowContext#build` runs, then output includes a section with tag `workflow-context`, priority `:important`, position_hint `:top`, containing workflow name, description, mode, run ID, and step position ("Step N of M")

4. **Produces current-step section** — Given a workflow step session, when `WorkflowContext#build` runs, then output includes a section with tag `current-step`, priority `:critical`, containing step name, description, and instructions

5. **Builder registered in BUILDERS** — Given the `SessionContextConstructor::BUILDERS` array, when inspected, then `ContextBuilders::WorkflowContext` is present after `Workspace` and before `Tools`

## Tasks / Subtasks

- [x] Task 1: Create WorkflowContext builder (AC: #1, #2, #3, #4)
  - [x] Create `app/services/context_builders/workflow_context.rb`
  - [x] Implement `applicable?` → `session.step_run.present?`
  - [x] Implement `build` → returns array of sections (workflow-context, current-step)
  - [x] Implement `workflow_overview_section` → tag `workflow-context`, priority `:important`, position `:top`
  - [x] Implement `current_step_section` → tag `current-step`, priority `:critical`
  - [x] Build content: workflow name, description, mode, run ID, step position (N of M)
  - [x] Build content: step name, step description, step instructions
- [x] Task 2: Register in SessionContextConstructor (AC: #5)
  - [x] Add `ContextBuilders::WorkflowContext` to BUILDERS after `Workspace` and before `Tools`
- [x] Task 3: Write tests (AC: #1-#5)
  - [x] Create `test/services/context_builders/workflow_context_test.rb`
  - [x] Test `applicable?` returns false for standalone session
  - [x] Test `applicable?` returns true for workflow step session
  - [x] Test `build` produces `workflow-context` section with correct tag, priority, position
  - [x] Test `build` produces `current-step` section with correct tag and `:critical` priority
  - [x] Test content includes workflow name, step position, instructions
  - [x] Test BUILDERS array includes WorkflowContext in correct position

## Dev Notes

### Architecture Patterns

- **Builder pattern:** Extends `ContextBuilders::Base` from Story 25.2. Same interface: `applicable?`, `build`, `name`.
- **Navigation helpers:** Use `step_run`, `workflow_run`, `workflow`, `step` from Base class.
- **Multiple sections per builder:** WorkflowContext is the first builder that returns >2 sections. Stories 26.2-26.4 add more sections to this builder.
- **Session-centric API:** All data accessed through `session.step_run` → `step_run.workflow_run` → `workflow_run.workflow`.

### Implementation Details

- `workflow-context` section: priority `:important`, position `:top` — gives agent awareness of its workflow position
- `current-step` section: priority `:critical` — this is the primary task for the agent
- Step position: `step.position` of `workflow.steps.count`
- Workflow mode: `workflow_run.mode` (interactive / non_interactive / mixed)
- Content format matches design doc §5.3

### Existing Code Context

- `WorkflowStepStrategy#build_workflow_prompt` (see `app/services/container_strategies/workflow_step_strategy.rb`) currently injects workflow context into `AGENT_PROMPT` env var. This builder replaces the context-file portion.
- `WorkflowContextAssembler` exists as orphaned code — will be deleted in Epic 28.
- Navigation chain: `session.step_run` → `step_run.step` / `step_run.workflow_run` → `workflow_run.workflow`
- `Step` model: has `name`, `position`, `description`, `instructions`, `sub_steps`
- `Workflow` model: has `name`, `description`, `steps`, polymorphic `scope`
- `WorkflowRun` model: has `mode` (enumerize: interactive/non_interactive/mixed), `step_runs`, `board_task`

### Testing Standards

- **Framework:** Minitest (NOT RSpec)
- **Mocks:** mocha gem
- **Factories:** Need workflow, step, step_run, workflow_run factories
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/workflow_context_test.rb`

### Project Structure Notes

- New file: `app/services/context_builders/workflow_context.rb`
- Modified: `app/services/session_context_constructor.rb` (add to BUILDERS)
- Test file: `test/services/context_builders/workflow_context_test.rb`
- Existing builders dir: `app/services/context_builders/` (6 files from Epic 25)

### References

- [Source: ai/session-context-constructor.md#5.3 WorkflowContext Builder] — Design specification
- [Source: ai/epics/epic-26-workflow-context-in-sessions.md#Story 26.1] — Acceptance criteria
- [Source: app/services/container_strategies/workflow_step_strategy.rb#build_workflow_prompt] — Existing implementation to replace
- [Source: ai/project-context.md#Implementation Rules] — Ruby coding standards
- [Source: app/services/context_builders/base.rb] — Base builder interface

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

All tasks completed. 8 tests, 27 assertions, 0 failures.

### File List

- app/services/context_builders/workflow_context.rb (new)
- app/services/session_context_constructor.rb (modified — added WorkflowContext to BUILDERS)
- test/services/context_builders/workflow_context_test.rb (new)
