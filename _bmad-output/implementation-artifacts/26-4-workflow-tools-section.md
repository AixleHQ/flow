# Story 26.4: Workflow Tools Section

Status: done

## Story

As a system,
I want the WorkflowContext builder to include a reference to available workflow MCP tools,
So that agents know how to track progress and save notes.

## Acceptance Criteria

1. **Workflow tools section with sub-steps** — Given a workflow step session with sub-steps, when WorkflowContext builder runs, then output includes a section with tag `workflow-tools`, priority `:important`, listing `list_sub_steps`, `mark_sub_step`, and `write_step_note` tools

2. **Tool descriptions accurate** — Given the workflow-tools section, when rendered, then each tool includes: name, purpose description, and key parameters

3. **No section without sub-steps** — Given a workflow step session with no sub-steps, when WorkflowContext builder runs, then no `workflow-tools` section is produced

## Tasks / Subtasks

- [x] Task 1: Add workflow_tools_section to WorkflowContext builder (AC: #1, #2, #3)
  - [x] Add `workflow_tools_section` method returning ContextSection with tag `workflow-tools`, priority `:important`
  - [x] Implement `build_workflow_tools` content with descriptions of 3 tools
  - [x] `list_sub_steps` — List all sub-steps with current statuses
  - [x] `mark_sub_step` — Update status with id, status, optional note and data
  - [x] `write_step_note` — Save a note visible to subsequent steps
  - [x] Conditionally include only when `sub_steps.any?`
- [x] Task 2: Write tests (AC: #1-#3)
  - [x] Test workflow-tools section produced when sub-steps exist
  - [x] Test no section when no sub-steps
  - [x] Test content includes all 3 tool names
  - [x] Test content includes key parameters

## Dev Notes

### Architecture Patterns

- **Extends WorkflowContext builder** from Story 26.1 — adds `workflow_tools_section` to `build`.
- **Conditional section:** Same condition as sub-steps — only when `sub_steps.any?`. Without sub-steps, progress tracking tools are irrelevant.
- **Documentation, not registration:** These tools are already registered as MCP tools (Epic 18). This section just documents them in the agent's context for discoverability.

### Implementation Details

- Three workflow tools (already exist since Epic 18):
  - `list_sub_steps` — Lists all sub-steps with current statuses. No params needed.
  - `mark_sub_step` — Params: `id` (sub-step run ID), `status` (in_progress/completed/skipped), optional `note`, `data`
  - `write_step_note` — Params: `note` (text). Appends to StepRun#step_note.
- Content matches existing `WorkflowStepStrategy#build_workflow_tools_section` for backward compatibility
- These are already injected as MCP tools via `TerminalSession#available_tools` for workflow_step sessions

### Existing Code Context

- `WorkflowStepStrategy#build_workflow_tools_section` — existing implementation with same content
- `InternalTools::ListSubSteps` (Epic 18.3), `InternalTools::MarkSubStep` (Epic 18.4), `InternalTools::WriteStepNote` (Epic 18.5)
- Tool.workflow_tools scope auto-injects these for workflow_step sessions

### Testing Standards

- **Framework:** Minitest, mocha, factory_bot
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/context_builders/workflow_context_test.rb`

### Project Structure Notes

- Modified file: `app/services/context_builders/workflow_context.rb`
- Test file: `test/services/context_builders/workflow_context_test.rb` (add tests)

### References

- [Source: ai/epics/epic-26-workflow-context-in-sessions.md#Story 26.4] — Acceptance criteria
- [Source: app/services/container_strategies/workflow_step_strategy.rb#build_workflow_tools_section] — Existing implementation
- [Source: ai/session-context-constructor.md#5.3] — WorkflowContext builder design

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

All tasks completed. 4 new tests added (23 total in file), 88 assertions, 0 failures.

### File List

- app/services/context_builders/workflow_context.rb (modified — added workflow_tools_section, build_workflow_tools)
- test/services/context_builders/workflow_context_test.rb (modified — added workflow-tools tests)
