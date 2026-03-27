# Story 28.3: Clean Up WorkflowStepStrategy Residual Methods

Status: ready-for-dev

## Story

As a developer,
I want residual context-building methods in WorkflowStepStrategy cleaned up after workflow context was moved to the builder,
So that the strategy only handles container lifecycle concerns, not context assembly.

## Acceptance Criteria

1. **No residual content-generation methods** — Given `WorkflowStepStrategy` after Epic 26.5 simplified AGENT_PROMPT, when this story is complete, then any remaining helper methods that built workflow prompt content (repos descriptions, asset descriptions, MCP descriptions within the strategy) are removed

2. **build_env_vars simplified** — Given the strategy's `build_env_vars`, when inspected, then it only sets `AGENT_PROMPT` to `step.instructions` and `CONFIGURED_AGENT_PERSONA`/`CONFIGURED_AGENT_PRINCIPLES` from step agent

3. **build_workflow_prompt minimal** — Given `build_workflow_prompt`, when inspected, then it returns only `step&.instructions` with no additional assembly

4. **All tests pass** — Given the full test suite, when run after changes, then all existing workflow execution tests pass

## Tasks / Subtasks

- [ ] Task 1: Audit WorkflowStepStrategy for residual methods (AC: #1)
  - [ ] Read current `app/services/container_strategies/workflow_step_strategy.rb`
  - [ ] Identify any methods that generate content for agent context (beyond lifecycle)
  - [ ] Verify `build_workflow_prompt` is already simplified (done in 26.5)
- [ ] Task 2: Remove residual methods if any (AC: #1, #2, #3)
  - [ ] Remove any methods that overlap with Constructor builders
  - [ ] Ensure strategy is thin: lifecycle hooks + env vars + image resolution only
- [ ] Task 3: Verify and test (AC: #4)
  - [ ] Run `docker exec app-web-1 bundle exec rails test test/services/` — all pass
  - [ ] Verify strategy file is clean of content generation

## Dev Notes

### Architecture Patterns

- **Strategy responsibility:** Container lifecycle only — `phase_config`, `build_env_vars`, `build_labels`, `before_exec`, `before_cleanup`. No content generation.
- **Key principle:** Context file = who you are + what you know + rules (Constructor). AGENT_PROMPT = what to do (step.instructions). Strategy = container lifecycle.

### Implementation Details

- After Epic 26.5, `build_workflow_prompt` already returns only `step&.instructions`
- The 3 legacy methods (`build_session_context_section`, `build_sub_steps_section`, `build_workflow_tools_section`) were already deleted in 26.5
- This story is a verification/audit pass — may find nothing to do if 26.5 was thorough
- Remaining methods to keep: `collect_workflow_outputs`, `inject_prior_step_outputs`, `inject_workflow_run_assets`, `download_to_container`, `rewrite_url_for_container` — these are lifecycle concerns, not context assembly
- `build_workflow_prompt` should remain as a simple one-liner returning `step&.instructions`

### Existing Code Context

- File: `app/services/container_strategies/workflow_step_strategy.rb`
- After 26.5: ~200 lines, mostly lifecycle methods (output collection, asset injection, URL rewriting)
- `build_env_vars` calls `build_workflow_prompt(step, step_run)` → sets AGENT_PROMPT
- No tests exist for WorkflowStepStrategy private methods (confirmed in 26.5)

### Testing Standards

- **Framework:** Minitest
- **Run tests:** `docker exec app-web-1 bundle exec rails test test/services/`

### Project Structure Notes

- Modified file: `app/services/container_strategies/workflow_step_strategy.rb` (if changes needed)
- No new files

### References

- [Source: ai/epics/epic-28-context-optimization-cleanup.md#Story 28.3] — Acceptance criteria
- [Source: app/services/container_strategies/workflow_step_strategy.rb] — Current strategy (post-26.5)
- [Source: _bmad-output/implementation-artifacts/26-5-simplify-agent-prompt-and-clean-up-workflowstepstrategy.md] — Previous cleanup work

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
