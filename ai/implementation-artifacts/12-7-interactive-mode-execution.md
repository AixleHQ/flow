# Story 12.7: Interactive Mode Execution

Status: done

## Story

As a project member,
I want to execute workflows in interactive mode where I approve each step,
so that I can guide the process and review outputs before proceeding.

## Acceptance Criteria

1. **AC1: WorkflowStepper UI** — Full workflow execution view showing: step progress (completed/current/pending), current step terminal embed, step outputs panel, Approve/Reject/Skip controls. Uses existing `WorkflowStepper` shared component as base.

2. **AC2: Step-by-step execution** — After each step completes (terminal session finishes), system collects outputs and shows review panel. User sees: step note (if agent wrote one), output files list, sub-step completion status. User can: [Approve] → proceed to next step, [Retry] → re-run same step, [Skip] → mark skipped and proceed, [Stop] → cancel workflow.

3. **AC3: Terminal session embed** — Current step shows embedded terminal (ttyd iframe) and VS Code editor (if available). Same widget as standalone session. User can interact with agent in real-time.

4. **AC4: Sub-step progress** — Real-time sub-step progress display. As agent calls `mark_sub_step` tool, UI updates to show completed/in-progress/pending sub-steps with notes. Uses ActionCable for real-time updates.

5. **AC5: Step transition flow** — When user approves a step: (1) StepRun status → completed, (2) outputs collected → WorkflowRunAssets created, (3) next StepRun created → terminal session started, (4) UI transitions to next step. Temporal workflow receives "step_approved" signal.

6. **AC6: Retry flow** — When user retries: (1) current StepRun status → failed, (2) new StepRun created for same Step, (3) retry count tracked, (4) respects `max_retries` from Step config.

7. **AC7: Skip flow** — When user skips: (1) StepRun status → skipped, (2) skip_reason recorded, (3) proceed to next step. Skip only available if step's `skip_policy != :never` or user is admin.

8. **AC8: Cancel flow** — When user cancels: (1) active terminal session stopped, (2) current StepRun → failed, (3) WorkflowRun → cancelled, (4) no cleanup of previously completed outputs.

9. **AC9: ActionCable channel** — `WorkflowRunChannel` broadcasts real-time updates: step_run status changes, sub_step_run updates, workflow_run status changes. Frontend subscribes on workflow run page.

10. **AC10: Workflow context injection** — Before each step starts, `WorkflowContextAssembler` generates context section injected into CLI context files. Includes: workflow info, current step, sub-steps, previous steps with notes and data. Follows the template from workflow-architecture.md section 5.2.

## Tasks / Subtasks

- [ ] Task 1: WorkflowStepper UI (AC: #1)
  - [ ] 1.1 Update existing `WorkflowRunPage` with full stepper layout
  - [ ] 1.2 Step list sidebar with progress indicators
  - [ ] 1.3 Main content area: terminal + outputs panel
  - [ ] 1.4 Action buttons bar: Approve, Retry, Skip, Stop
- [ ] Task 2: Terminal session integration (AC: #3)
  - [ ] 2.1 Embed `TerminalSessionWidget` for current step
  - [ ] 2.2 Handle session state transitions (loading → ready → finished)
- [ ] Task 3: Sub-step progress panel (AC: #4)
  - [ ] 3.1 Real-time sub-step list with status icons (✅🔄⬜⏭️)
  - [ ] 3.2 Show sub-step notes and data as they come in
  - [ ] 3.3 ActionCable subscription for SubStepRun updates
- [ ] Task 4: Step transition API endpoints (AC: #5, #6, #7, #8)
  - [ ] 4.1 `POST .../runs/:id/approve_step` — approve current step, advance
  - [ ] 4.2 `POST .../runs/:id/retry_step` — retry current step
  - [ ] 4.3 `POST .../runs/:id/skip_step` — skip current step
  - [ ] 4.4 `POST .../runs/:id/cancel` — cancel workflow run
  - [ ] 4.5 Each sends Temporal signal to WorkflowExecutionWorkflow
- [ ] Task 5: Temporal signal handling (AC: #5, #6, #7, #8)
  - [ ] 5.1 `step_approved` signal → proceed to next step
  - [ ] 5.2 `step_retried` signal → create new StepRun, re-execute
  - [ ] 5.3 `step_skipped` signal → mark skipped, advance
  - [ ] 5.4 `workflow_cancelled` signal → cleanup and finalize
- [ ] Task 6: WorkflowRunChannel (AC: #9)
  - [ ] 6.1 ActionCable channel broadcasting step/substep updates
  - [ ] 6.2 Frontend subscription hooks
- [ ] Task 7: WorkflowContextAssembler service (AC: #10)
  - [ ] 7.1 `WorkflowContextAssembler#assemble(step_run)` generates context markdown
  - [ ] 7.2 Include workflow info, current step, sub-steps, previous steps
  - [ ] 7.3 Integrate with `SessionContextService` for CLI context injection
- [ ] Task 8: Output review panel
  - [ ] 8.1 Show WorkflowRunAssets produced by completed step
  - [ ] 8.2 File list with preview capability
  - [ ] 8.3 Step note display
- [ ] Task 9: Frontend workflow run API
  - [ ] 9.1 `useApproveStepMutation`, `useRetryStepMutation`, `useSkipStepMutation`, `useCancelWorkflowMutation`
  - [ ] 9.2 ActionCable integration hooks
- [ ] Task 10: Write tests
  - [ ] 10.1 Controller: approve/retry/skip/cancel endpoints
  - [ ] 10.2 Temporal signals: step transitions
  - [ ] 10.3 WorkflowContextAssembler: context generation
  - [ ] 10.4 ActionCable: channel subscription and broadcasts

## Dev Notes

### Architecture

Interactive mode is the primary execution mode. The flow is:

```
User starts workflow (mode: interactive)
  → Temporal WorkflowExecutionWorkflow starts
  → For each step:
    → PrepareStepActivity: mount assets, inject context, create TerminalSession
    → Start AgentContainerWorkflow for the TerminalSession
    → Wait for "step_decision" signal (approve/retry/skip/cancel)
    → On approve: CompleteStepActivity → collect outputs → advance
    → On retry: FailStepActivity → create new StepRun → re-run
    → On skip: SkipStepActivity → record reason → advance
    → On cancel: CancelWorkflowActivity → stop all → finalize
```

**Key integration points:**
1. Each step = one TerminalSession (session_type: :workflow_step)
2. TerminalSession lifecycle managed by existing AgentContainerWorkflow
3. WorkflowExecutionWorkflow coordinates between steps
4. ActionCable for real-time UI updates (reuse TerminalSessionChannel pattern)

**WorkflowContextAssembler** is a new service following the template from workflow-architecture.md section 5.2. It generates a markdown context block injected into CLI context files (CLAUDE.md, AGENTS.md, etc.) via SessionContextService.

### Key files to create

**Backend:**
- `app/services/workflow_context_assembler.rb`
- `app/channels/workflow_run_channel.rb`
- `app/temporal/activities/workflow/prepare_step_activity.rb` (expand from 12-6)
- `app/temporal/activities/workflow/complete_step_activity.rb` (expand from 12-6)

**Frontend:**
- Update `app/frontend/pages/workflow-run/ui/WorkflowRunPage.tsx`
- `app/frontend/features/workflow-execution/ui/StepProgressSidebar.tsx`
- `app/frontend/features/workflow-execution/ui/StepActionBar.tsx`
- `app/frontend/features/workflow-execution/ui/SubStepProgress.tsx`
- `app/frontend/features/workflow-execution/ui/StepOutputPanel.tsx`
- `app/frontend/features/workflow-execution/hooks/useWorkflowRunChannel.ts`

### Key files to modify

- `app/temporal/workflows/workflow_execution_workflow.rb` — add signal handling
- `app/services/session_context_service.rb` — integrate WorkflowContextAssembler
- `config/routes.rb` — add step action routes
- `app/controllers/api/v1/company/projects/workflows/runs_controller.rb` — add action endpoints

### Internal tools for workflow steps

Four internal tools auto-available in workflow_step sessions (defined in workflow-architecture.md section 6):
- `list_sub_steps` — list sub-steps with statuses
- `mark_sub_step(id, status, note, data)` — update sub-step progress
- `write_step_note(note)` — save note for future steps
- `export_asset(file, tags, folder, public)` — promote output to project asset

These tools will be implemented as MCP tools or internal HTTP tools accessible within the container. Implementation detail: agent calls tool → HTTP request to Rails → updates SubStepRun/StepRun records → ActionCable broadcast.

### Dependencies

- Story 12-6 (WorkflowRun, StepRun, SubStepRun, Temporal workflow base)
- Story 12-2 (Step, SubStep models)
- Epic 10 done (TerminalSession, AgentContainerWorkflow, TerminalSessionWidget)

### Testing

- Step approval flow: step finishes → user approves → next step starts
- Retry flow: step fails → retry → new StepRun created → re-executed
- Skip flow: step skipped → reason recorded → proceed
- Cancel flow: workflow cancelled → active session stopped
- Context assembler: generates correct markdown with previous step data
- ActionCable: channel broadcasts on status changes

### References

- [Source: ai/workflow-architecture.md#4.2](ai/workflow-architecture.md) — Start Step flow
- [Source: ai/workflow-architecture.md#4.3](ai/workflow-architecture.md) — Complete Step flow
- [Source: ai/workflow-architecture.md#5](ai/workflow-architecture.md) — Workflow Context Injection
- [Source: ai/workflow-architecture.md#6](ai/workflow-architecture.md) — Internal Tools
- [Source: ai/prd/functional-requirements.md#FR16](ai/prd/functional-requirements.md) — FR16: Interactive mode execution
- [Source: app/channels/terminal_session_channel.rb](app/channels/terminal_session_channel.rb) — Reference ActionCable channel
- [Source: app/frontend/shared/ui/WorkflowStepper/](app/frontend/shared/ui/WorkflowStepper/) — Existing stepper component

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
