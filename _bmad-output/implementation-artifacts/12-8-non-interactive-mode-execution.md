# Story 12.8: Non-Interactive Mode Execution

Status: done

## Story

As a project member,
I want to execute workflows in non-interactive mode where steps auto-proceed,
so that automated processes run without manual intervention.

## Acceptance Criteria

1. **AC1: Auto-advance** — Steps with `allow_non_interactive: true` automatically proceed to the next step when the agent completes (terminal session finishes successfully). No user approval needed.

2. **AC2: Mixed mode** — In `mixed` mode: steps with `allow_non_interactive: true` auto-advance, steps without it wait for user approval (same as interactive mode). Mode determined at WorkflowRun level.

3. **AC3: Non-interactive validation** — `non_interactive` mode only available if ALL steps have `allow_non_interactive: true`. `mixed` mode always available. Validation in workflow run creation (Story 12-6 AC7).

4. **AC4: Notifications on completion** — When a non-interactive workflow completes, broadcast completion event via ActionCable. Frontend shows toast notification: "Workflow '{name}' completed successfully" or "Workflow '{name}' failed at step '{step_name}'".

5. **AC5: Total cost display** — After workflow completes, show total cost: sum of all StepRun terminal session costs (tokens + USD). Display on WorkflowRun detail page.

6. **AC6: Non-interactive step execution** — For non-interactive steps: (1) create TerminalSession with `mode: :non_interactive`, (2) agent runs with `initial_prompt` from step instructions, (3) container completes when agent finishes, (4) outputs collected automatically.

7. **AC7: Skip policy enforcement** — Before executing each step, check `skip_policy`:
   - `never` → always execute
   - `if_outputs_exist` → check if all `output_asset_specs` requirements are satisfied by existing WorkflowRunAssets → skip if yes
   - `manual` → in interactive/mixed mode, ask user; in non_interactive, always execute

8. **AC8: Failure handling** — When a step fails in non-interactive mode, apply `on_failure` policy:
   - `retry` → retry up to `max_retries` times
   - `skip` → mark skipped, proceed to next step
   - `fail` → mark WorkflowRun as failed, stop execution

9. **AC9: Progress monitoring** — Non-interactive workflow shows live progress on workflow run page: step completion indicators update in real-time, total elapsed time, current step name. User can cancel at any time.

10. **AC10: Completion summary** — When workflow finishes (success or failure), show summary: total steps completed/skipped/failed, total duration, total cost, list of produced assets.

## Tasks / Subtasks

- [ ] Task 1: Temporal workflow auto-advance logic (AC: #1, #2)
  - [ ] 1.1 After step completes, check step.allow_non_interactive and workflow_run.mode
  - [ ] 1.2 If auto-advance: collect outputs → advance to next step automatically
  - [ ] 1.3 If not: wait for user signal (interactive behavior)
- [ ] Task 2: Non-interactive terminal session (AC: #6)
  - [ ] 2.1 Create TerminalSession with mode: :non_interactive
  - [ ] 2.2 Set initial_prompt from step.instructions
  - [ ] 2.3 Container auto-completes when agent finishes task
- [ ] Task 3: Skip policy implementation (AC: #7)
  - [ ] 3.1 Before step execution, evaluate skip_policy
  - [ ] 3.2 `if_outputs_exist` check: compare output_asset_specs with existing WorkflowRunAssets
  - [ ] 3.3 Create `StepSkipEvaluator` service
- [ ] Task 4: Failure handling (AC: #8)
  - [ ] 4.1 On step failure, check on_failure policy from Step config
  - [ ] 4.2 Retry: create new StepRun, re-execute (up to max_retries)
  - [ ] 4.3 Skip: mark StepRun skipped, advance
  - [ ] 4.4 Fail: mark WorkflowRun failed, halt
- [ ] Task 5: Completion notifications (AC: #4)
  - [ ] 5.1 ActionCable broadcast on workflow completion/failure
  - [ ] 5.2 Frontend toast notification
- [ ] Task 6: Cost aggregation (AC: #5)
  - [ ] 6.1 Aggregate costs from all StepRun terminal sessions
  - [ ] 6.2 Add `total_cost`, `total_tokens` to WorkflowRunSerializer
- [ ] Task 7: Progress monitoring UI (AC: #9)
  - [ ] 7.1 Live step progress indicators
  - [ ] 7.2 Elapsed time counter
  - [ ] 7.3 Cancel button
- [ ] Task 8: Completion summary UI (AC: #10)
  - [ ] 8.1 Summary card: steps completed/skipped/failed
  - [ ] 8.2 Duration and cost display
  - [ ] 8.3 Produced assets list with links
- [ ] Task 9: Write tests
  - [ ] 9.1 Auto-advance: non-interactive step completes → next starts
  - [ ] 9.2 Mixed mode: non-interactive auto-advances, interactive waits
  - [ ] 9.3 Skip policy: if_outputs_exist correctly evaluates
  - [ ] 9.4 Failure handling: retry, skip, fail policies
  - [ ] 9.5 Cost aggregation: sum of step costs

## Dev Notes

### Architecture

Non-interactive mode is built on top of the interactive workflow (Story 12-7). The key difference is the decision logic in the Temporal workflow:

```ruby
# In WorkflowExecutionWorkflow, after step completes:
if auto_advance?(step, workflow_run)
  # Collect outputs and proceed automatically
  complete_step_activity(step_run_id:)
  advance_to_next_step
else
  # Wait for user signal (interactive)
  wait_for_signal("step_decision", timeout: 23.hours)
end

def auto_advance?(step, workflow_run)
  return true if workflow_run.mode == 'non_interactive'
  return true if workflow_run.mode == 'mixed' && step.allow_non_interactive
  false
end
```

**Non-interactive terminal sessions:** Use existing `mode: :non_interactive` on TerminalSession. The agent receives `initial_prompt` (from step.instructions) and runs autonomously. The container exits when the agent completes.

**Skip policy:** `StepSkipEvaluator` service checks if step should be skipped before execution. For `if_outputs_exist`, it checks all required outputs in `output_asset_specs` against existing WorkflowRunAssets (from previous steps or retries).

**Cost aggregation:** Each TerminalSession already tracks `total_cost_usd` and token counts. WorkflowRun total = sum of all step_run.terminal_session costs. Add computed methods to WorkflowRun or WorkflowRunSerializer.

### Key files to create

**Backend:**
- `app/services/step_skip_evaluator.rb`

**Frontend:**
- `app/frontend/features/workflow-execution/ui/WorkflowCompletionSummary.tsx`
- `app/frontend/features/workflow-execution/ui/CostSummary.tsx`

### Key files to modify

- `app/temporal/workflows/workflow_execution_workflow.rb` — add auto-advance logic, skip policy, failure handling
- `app/serializers/workflow_run_serializer.rb` — add total_cost, total_tokens, completion summary
- `app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx` — add non-interactive progress view

### Dependencies

- Story 12-6 (WorkflowRun, StepRun models, Temporal workflow base)
- Story 12-7 (Interactive mode — non-interactive builds on same infrastructure)
- Story 12-2 (Step model with allow_non_interactive, skip_policy, on_failure)

### Testing

- Non-interactive mode: all steps auto-advance, no signals needed
- Mixed mode: interactive steps wait, non-interactive auto-advance
- Skip policy evaluation (unit test StepSkipEvaluator)
- Retry: step fails → retried → succeeds (or max retries exceeded)
- Cost aggregation: correct sum across all steps
- Completion notification broadcast

### References

- [Source: ai/workflow-architecture.md#4.1](ai/workflow-architecture.md) — Mode logic
- [Source: ai/workflow-architecture.md#4.3](ai/workflow-architecture.md) — Complete Step validation
- [Source: ai/workflow-architecture.md#9](ai/workflow-architecture.md) — Output validation
- [Source: ai/prd/functional-requirements.md#FR17](ai/prd/functional-requirements.md) — FR17: Non-interactive mode
- [Source: ai/epics/epic-11-workflows-phase-5-6.md#Story 11.8](ai/epics/epic-11-workflows-phase-5-6.md) — Story ACs

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
