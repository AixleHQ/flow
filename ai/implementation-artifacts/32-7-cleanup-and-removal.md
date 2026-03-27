# Story 32.7: Delete Obsolete Services and Cleanup

Status: review

## Story

As a developer,
I want to remove obsolete services and methods,
so that there's a single way to perform each operation.

## Acceptance Criteria

1. `app/services/task_move_service.rb` is deleted
2. `app/services/workflow_auto_trigger_service.rb` is deleted
3. `TerminalSession` no longer contains: `start_workflow!`, `request_finish!`, `cancel!` (override), `signal_workflow`, `signal_workflow_execution_finished`, `cancel_workflow`
4. `WorkflowRunStateMachine` no longer contains: `cancel_active_step_runs!`, `cancel_session`
5. `WorkflowRunsController` no longer contains: `start_temporal_workflow`, `send_workflow_signal`, `validate_mode!`
6. `grep -r "WorkflowAutoTriggerService\|TaskMoveService" --include="*.rb"` returns 0 results
7. `grep -r "start_workflow!\|request_finish!\|signal_workflow_execution_finished" app/models/` returns 0 results (excluding comments)
8. All tests pass with no broken references
9. No orphaned routes or controller actions

## Tasks / Subtasks

- [x] Task 1: Verify file deletions (AC: 1, 2)
  - [x] Confirm `app/services/task_move_service.rb` is deleted (done in 32.3) ✓
  - [x] Confirm `app/services/workflow_auto_trigger_service.rb` is deleted (done in 32.3) ✓
  - [x] No test files for deleted services existed
- [x] Task 2: Verify model cleanup (AC: 3)
  - [x] Grep `app/models/terminal_session.rb` for removed methods — 0 results ✓
  - [x] Confirm no `start_workflow!`, `request_finish!`, `cancel!` override, private Temporal methods ✓
- [x] Task 3: Verify state machine cleanup (AC: 4)
  - [x] Grep `app/state_machines/workflow_run_state_machine.rb` for removed methods — 0 results ✓
  - [x] Confirm no `cancel_active_step_runs!`, `cancel_session` ✓
- [x] Task 4: Verify controller cleanup (AC: 5)
  - [x] Grep controllers for removed methods — 0 results ✓
  - [x] Confirm no `start_temporal_workflow`, `send_workflow_signal`, `validate_mode!` ✓
- [x] Task 5: Full codebase grep (AC: 6, 7)
  - [x] `WorkflowAutoTriggerService|TaskMoveService` in *.rb → 0 results ✓
  - [x] `start_workflow!|request_finish!|signal_workflow_execution_finished` in app/models/ → 0 results ✓
  - [x] `cancel_active_step_runs|cancel_session` in app/state_machines/ → 0 results ✓
  - [x] Fixed remaining references: InternalTools::FinishSession and InternalTools::FailSession used request_finish!
- [x] Task 6: Route audit (AC: 9)
  - [x] No controller actions were removed — only internal methods
  - [x] All routes intact ✓
- [x] Task 7: Final test run (AC: 8)
  - [x] 1781 tests, 0 errors, 3 pre-existing failures (serializer ide_url test, unrelated)
  - [x] All Epic 32 related tests pass

## Dev Notes

### Architecture

- This is the **final cleanup story** — runs after all other stories are complete
- Purely verification and deletion — no new code

### Key Files to Verify/Delete

| File | Expected State |
|------|---------------|
| `app/services/task_move_service.rb` | **DELETED** (in 32.3) |
| `app/services/workflow_auto_trigger_service.rb` | **DELETED** (in 32.3) |
| `app/models/terminal_session.rb` | **CLEAN** — no Temporal methods (in 32.1) |
| `app/state_machines/workflow_run_state_machine.rb` | **CLEAN** — no cancel helpers (in 32.5) |
| `app/controllers/api/v1/company/projects/workflow_runs_controller.rb` | **CLEAN** — no Temporal helpers (in 32.2) |
| `test/services/task_move_service_test.rb` | **DELETED** |
| `test/services/workflow_auto_trigger_service_test.rb` | **DELETED** |

### Verification Commands

```bash
rg "WorkflowAutoTriggerService|TaskMoveService" --type ruby
rg "start_workflow!|request_finish!|signal_workflow_execution_finished" app/models/
rg "cancel_active_step_runs|cancel_session" app/state_machines/
rg "start_temporal_workflow|send_workflow_signal|validate_mode!" app/controllers/
rails routes | grep -i "dead\|orphan"  # manual check
make test
make lint
```

### References

- [Source: ai/epics/epic-32-service-layer-pyramid.md#story-327] — epic definition
- All previous stories (32.1-32.6) — this story verifies their completeness

## Dev Agent Record

### Agent Model Used

claude-4.6-opus-high

### Completion Notes List

- All obsolete services deleted (TaskMoveService, WorkflowAutoTriggerService) — verified in 32.3
- TerminalSession model clean — no Temporal methods remain
- State machines clean — no external service calls
- Controllers clean — no Temporal helpers
- Fixed InternalTools::FailSession and InternalTools::FinishSession — replaced request_finish! with SessionService.finish
- Fixed InternalTools::BoardMoveTask — replaced TaskMoveService with TaskService.move (done in 32.3)
- Full codebase grep: 0 references to deleted methods/services
- Full test suite: 1781 tests, 0 errors, 3 pre-existing failures (unrelated serializer tests)

### File List

- app/services/internal_tools/fail_session.rb (MODIFIED — uses SessionService.finish)
- app/services/internal_tools/finish_session.rb (MODIFIED — uses SessionService.finish)
- app/services/internal_tools/board_move_task.rb (MODIFIED in 32.3 — uses TaskService.move)
