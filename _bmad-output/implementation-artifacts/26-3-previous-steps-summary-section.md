# Story 26.3: Previous Steps Summary Section

Status: done

## Story

As a system,
I want the WorkflowContext builder to include summaries of completed previous steps,
So that agents have continuity and can reference decisions and outputs from earlier steps.

## Acceptance Criteria

1. **Previous steps section with summaries** — Given a workflow run where steps 1 and 2 are completed and current step is 3, when WorkflowContext builder runs, then output includes a section with tag `previous-steps`, priority `:info`, containing step number, name, and status icon (✅ or ⏭️)

2. **Step notes included and truncated** — Given a completed step with step_note "Analyzed codebase and found 15 issues...", when section is rendered, then the note is shown truncated to 500 chars

3. **Sub-step details from previous steps** — Given a completed step with completed sub-step names, when section is rendered, then sub-step names are listed with their notes truncated to 150 chars and data truncated to 200 chars JSON

4. **No section on first step** — Given a workflow run on step 1 (no previous steps), when WorkflowContext builder runs, then no `previous-steps` section is produced

## Tasks / Subtasks

- [x] Task 1: Add previous_steps_section to WorkflowContext builder (AC: #1, #2, #3, #4)
  - [x] Add `previous_steps_section` method returning ContextSection with tag `previous-steps`, priority `:info`
  - [x] Implement `build_previous_steps` content generator
  - [x] Query completed step runs: `workflow_run.step_runs.where.not(id: step_run.id).where(state: %w[completed skipped]).joins(:step).order("steps.position ASC")`
  - [x] Eager load: `.includes(step: :sub_steps, sub_step_runs: :sub_step)`
  - [x] For each completed step: show position, name, status icon
  - [x] Include `step_note` truncated to 500 chars
  - [x] Include completed sub-step names with notes truncated to 150 chars
  - [x] Include sub-step data truncated to 200 chars JSON
  - [x] Conditionally include in `build` only when `completed_step_runs.any?`
- [x] Task 2: Write tests (AC: #1-#4)
  - [x] Test previous-steps section produced when earlier steps completed
  - [x] Test no section when on first step
  - [x] Test step note truncation to 500 chars
  - [x] Test sub-step note truncation to 150 chars
  - [x] Test status icons ✅ and ⏭️

## Dev Notes

### Architecture Patterns

- **Extends WorkflowContext builder** from Story 26.1 — adds `previous_steps_section` to `build`.
- **Conditional section:** Only when `completed_step_runs.any?` — first step has no previous context.
- **Eager loading critical:** Must use `.includes(step: :sub_steps, sub_step_runs: :sub_step)` to prevent N+1 queries.

### Implementation Details

- Completed step runs query: `workflow_run.step_runs.where.not(id: step_run.id).where(state: %w[completed skipped]).joins(:step).order("steps.position ASC")`
- Status icon: completed → ✅, skipped → ⏭️
- Step note: `step_run.step_note` — text field appended by `write_step_note` MCP tool
- Truncation lengths from design doc §5.3: step notes 500 chars, sub-step notes 150 chars, sub-step data 200 chars JSON
- Purpose: give current agent continuity about what happened in previous workflow steps

### Existing Code Context

- `StepRun` model: `state` (enumerize: pending/running/waiting_input/completed/failed/skipped), `step_note` (text)
- `StepRun` has `sub_step_runs` association with eager loading support
- No equivalent in current `WorkflowStepStrategy` — this is new functionality previously planned in orphaned `WorkflowContextAssembler`

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/workflow_context_test.rb`

### Project Structure Notes

- Modified file: `app/services/context_builders/workflow_context.rb`
- Test file: `test/services/context_builders/workflow_context_test.rb` (add tests)

### References

- [Source: ai/session-context-constructor.md#5.3 build_previous_steps] — Previous steps section design
- [Source: ai/epics/epic-26-workflow-context-in-sessions.md#Story 26.3] — Acceptance criteria
- [Source: app/models/step_run.rb] — StepRun model with step_note field and state enumerize

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

All tasks completed. 6 new tests added (19 total in file), 71 assertions, 0 failures.

### File List

- app/services/context_builders/workflow_context.rb (modified — added previous_steps_section, build_previous_steps, completed_step_runs)
- test/services/context_builders/workflow_context_test.rb (modified — added previous-steps tests)
