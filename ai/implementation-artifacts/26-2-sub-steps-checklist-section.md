# Story 26.2: Sub-Steps Checklist Section

Status: done

## Story

As a system,
I want the WorkflowContext builder to include a sub-steps checklist with progress tracking,
So that agents can see which sub-steps are completed, in progress, or pending and know how to report progress.

## Acceptance Criteria

1. **Sub-steps section with status icons** — Given a workflow step with 6 sub-steps where 2 are completed, 1 is in_progress, and 3 are pending, when WorkflowContext builder runs, then output includes a section with tag `sub-steps`, priority `:important`, containing numbered list with status icons (✅ completed, 🔄 in_progress, ⏭️ skipped, ⬜ pending)

2. **Sub-step details included** — Given sub-steps with names and IDs, when the section is rendered, then each line includes sub-step name, sub_step_run ID reference, and status

3. **Notes and data from completed sub-steps** — Given a completed sub-step with note "Done analyzing" and data `{"files": 12}`, when section is rendered, then note is shown truncated to 200 chars and data shown as truncated JSON to 300 chars

4. **Progress tracking instructions** — Given the sub-steps section, when rendered, then it includes instructions to use `mark_sub_step` MCP tool with sub-step ID, and a warning: "Do NOT mark the last sub-step completed until ALL work is done"

5. **No section when no sub-steps** — Given a step with no sub-steps, when WorkflowContext builder runs, then no `sub-steps` section is produced

## Tasks / Subtasks

- [x] Task 1: Add sub_steps_section to WorkflowContext builder (AC: #1, #2, #3, #4, #5)
  - [x] Add `sub_steps_section` method returning ContextSection with tag `sub-steps`, priority `:important`
  - [x] Implement `build_sub_steps` content generator
  - [x] Add status icon mapping: `{ "completed" => "✅", "in_progress" => "🔄", "skipped" => "⏭️" }.fetch(status, "⬜")`
  - [x] Access sub_step_runs via `step_run.sub_step_runs.includes(:sub_step).index_by(&:sub_step_id)`
  - [x] Include note truncated to 200 chars for completed/in_progress sub-steps
  - [x] Include data as truncated JSON to 300 chars for sub-steps with data
  - [x] Add `mark_sub_step` usage instructions
  - [x] Add warning about last sub-step triggering termination
  - [x] Conditionally include in `build` only when `sub_steps.any?`
- [x] Task 2: Write tests (AC: #1-#5)
  - [x] Test sub-steps section includes status icons for all states
  - [x] Test note and data truncation
  - [x] Test no sub-steps section when step has no sub-steps
  - [x] Test mark_sub_step instructions present
  - [x] Test termination warning present

## Dev Notes

### Architecture Patterns

- **Extends WorkflowContext builder** from Story 26.1 — adds `sub_steps_section` to the `build` method.
- **Conditional section:** Only produced when `sub_steps.any?` — same pattern as Resources builder.
- **Eager loading:** Access sub_step_runs via `step_run.sub_step_runs.includes(:sub_step).index_by(&:sub_step_id)` for N+1 prevention.

### Implementation Details

- Status icon mapping: `{ "completed" => "✅", "in_progress" => "🔄", "skipped" => "⏭️" }.fetch(status, "⬜")`
- Sub-step access: `step.sub_steps.order(:position)` — default scope already orders by position
- SubStepRun states (enumerize): `pending`, `in_progress`, `completed`, `skipped`
- Note truncation: `.truncate(200)` — Ruby's built-in String method
- Data truncation: `.to_json.truncate(300)` — serialize then truncate
- ID reference: show `ssr.id` so agent can call `mark_sub_step(id: ssr.id, status: "completed")`

### Existing Code Context

- `WorkflowStepStrategy#build_sub_steps_section` has similar logic — this is the canonical replacement
- `SubStep` model: `name`, `position`, `description`, `instructions`, `required`, belongs_to `step`
- `SubStepRun` model: `state` (enumerize), `note`, `data` (jsonb), belongs_to `step_run` and `sub_step`
- MCP tool `mark_sub_step` (Epic 18.4): accepts `id`, `status`, `note`, `data`

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/workflow_context_test.rb`

### Project Structure Notes

- Modified file: `app/services/context_builders/workflow_context.rb`
- Test file: `test/services/context_builders/workflow_context_test.rb` (add tests)

### References

- [Source: ai/session-context-constructor.md#5.3 build_sub_steps] — Sub-steps section design
- [Source: ai/epics/epic-26-workflow-context-in-sessions.md#Story 26.2] — Acceptance criteria
- [Source: app/services/container_strategies/workflow_step_strategy.rb#build_sub_steps_section] — Existing implementation
- [Source: app/models/sub_step_run.rb] — SubStepRun model with state enumerize

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

All tasks completed. 5 new tests added (13 total in file), 51 assertions, 0 failures.

### File List

- app/services/context_builders/workflow_context.rb (modified — added sub_steps_section, build_sub_steps, sub_steps, status_icon)
- test/services/context_builders/workflow_context_test.rb (modified — added sub-steps tests)
