# State Machine Lifecycle Analysis

> Analytical document: a study of the current model lifecycle management and a proposal to centralize it via state machines.

## 1. Current state (AS-IS)

### 1.1 Model hierarchy

```
BoardTask (column = "state")
    └── WorkflowRun [AASM: pending → running → paused → completed/failed/cancelled]
            └── StepRun [Enumerize: pending → running → waiting_input → completed/failed/skipped/cancelled]
                    ├── TerminalSession [AASM: not_started → running → ready → finished/failed]
                    └── SubStepRun [Enumerize: pending → in_progress → completed/skipped]
```

### 1.2 State transitions map: who triggers them and from where

#### TerminalSession

| Call site | Event | File |
|---|---|---|
| TerminalSessionsController#create | `start!` | controllers/api/v1/terminal_sessions_controller.rb:32 |
| LaunchStepSessionActivity | `start!` | temporal/activities/workflow/launch_step_session_activity.rb:39 |
| AgentBaseStrategy#mark_session_ready | `mark_ready!` | services/container_strategies/agent_base_strategy.rb |
| BaseStrategy#after_cleanup | `finish!` / `fail!` | services/container_strategies/base_strategy.rb |
| CleanupStaleActivity | `fail!` / `finish!` | temporal/activities/session/cleanup_stale_activity.rb |
| WorkflowRunStateMachine#cancel_session | `fail!` | state_machines/workflow_run_state_machine.rb:74 |
| TerminalSession#on_started (rescue) | `fail!` | models/terminal_session.rb:181 |

**Side effects in model callbacks:**
- `on_started` → `start_workflow!` (launch Temporal ContainerWorkflow + update temporal_workflow_id)
- `on_ready` → `update!(ready_at: ...)`
- `on_finished`/`on_failed` → `sync_usage`, `signal_workflow_execution_finished`
- `after_update :broadcast_update` → ActionCable broadcast

#### WorkflowRun

| Call site | Event | File |
|---|---|---|
| UpdateWorkflowRunStatusActivity | `start!`, `complete!`, `fail!`, `cancel!`, `pause!` | temporal/activities/workflow/update_workflow_run_status_activity.rb |
| WorkflowRunsController#cancel | `cancel!` | controllers/api/v1/.../workflow_runs_controller.rb:71 |
| WorkflowAutoTriggerService#cancel_active_runs! | `cancel!` | services/workflow_auto_trigger_service.rb:41 |

**Side effects in the state machine:**
- `on_started` → `update_column(:started_at)`, broadcast
- `on_completed` → `update_column(:completed_at)`, broadcast
- `on_cancelled` → `cancel_active_step_runs!` (cascade to StepRun + TerminalSession), broadcast
- `broadcast_run_update!` → WorkflowRunChannel + ActivityRecorder (for board tasks)

#### StepRun (NO AASM — direct update!)

| Call site | Method | File |
|---|---|---|
| PrepareStepActivity | `mark_running!`, `mark_failed!` | temporal/activities/workflow/prepare_step_activity.rb |
| CompleteStepActivity | `mark_completed!`, `mark_failed!` | temporal/activities/workflow/complete_step_activity.rb |
| WorkflowRunsController | `mark_completed!`, `mark_failed!`, `mark_skipped!` | controllers/workflow_runs_controller.rb |
| WorkflowRunStateMachine | `mark_cancelled!` | state_machines/workflow_run_state_machine.rb:64 |

**Problem:** `mark_*!` methods are just `update!` without guards. You can call `mark_completed!` on an already cancelled StepRun.

#### SubStepRun

| Call site | Method | File |
|---|---|---|
| InternalTools::MarkSubStep | `ssr.state = new_status` | services/internal_tools/mark_sub_step.rb |
| StepRun#create_sub_step_runs! | creation in pending | models/step_run.rb:51 |

#### BoardTask (NO state machine)

The "state" is `board_column_id`. On a move:
- `TaskMoveService` → creates a `ColumnTransition` → calls `WorkflowAutoTriggerService.check!`
- `WorkflowAutoTriggerService` → cancels active runs → creates a new `WorkflowRun` → starts Temporal

### 1.3 Creating and launching a WorkflowRun (3 different places!)

1. **WorkflowRunsController#create** — manual launch: creates the run, creates step_runs, calls `WorkflowService.start_workflow_execution`
2. **TasksController#trigger_workflow** — manual trigger from the board: creates the run, calls `WorkflowService.start_workflow_execution`
3. **WorkflowAutoTriggerService#check!** — auto-trigger on task move: cancels active ones, creates the run, starts execution

In each place the creation logic is partially duplicated.

---

## 2. Identified problems

### 2.1 No single entry point for lifecycle events

State transitions are triggered from 5+ different places. There is no guarantee that all side effects execute correctly. For example:
- The controller calls `session.start!` directly
- A Temporal activity calls `session.start!` directly
- Both rely on a callback in the model

### 2.2 StepRun: no protection against invalid transitions

`mark_completed!` can be called on a cancelled StepRun. There are no AASM guards, no `may_*?` checks.

### 2.3 Duplication of WorkflowRun creation logic

Three different controllers/services create a WorkflowRun in different ways. There is no single "factory" method.

### 2.4 Cascade operations are spread out

On WorkflowRun cancel:
- the state machine cancels StepRuns
- for each StepRun it cancels the TerminalSession (cancel Temporal workflow + fail!)
- but this logic is hardcoded into a private method of the state machine

On TerminalSession completion:
- the model signals the workflow execution
- but only if `session_type == "workflow_step"`

### 2.5 Mixed responsibilities in models

The `TerminalSession` model contains:
- Temporal workflow management (start_workflow!, cancel_workflow, signal_workflow)
- State machine callbacks
- Strategy resolution
- Usage sync

---

## 3. Proposal (TO-BE): Centralized lifecycle management via State Machines

### 3.1 Principles

1. **The state machine is the only way to change a model's state** (Single Point of Transition)
2. **Side effects live in the state machine's after_transition callbacks**, not in the model
3. **Guards (`may_*?`) are mandatory** before any transition
4. **Cascade relationships between models are managed via state machines** (if TerminalSession → finished, then the state machine signals the parent StepRun/WorkflowRun)
5. **Controllers and Temporal activities only trigger events**, they do not think about side effects
6. **Model creation can also be part of the lifecycle** (factory via state machine entry)

### 3.2 Target State Machines

#### TerminalSession State Machine (extended)

```
                            ┌─────────────┐
                            │ not_started  │ (initial)
                            └──────┬───────┘
                                   │ start!
                                   │ after: launch ContainerWorkflow
                                   ▼
                            ┌─────────────┐
                    ┌───────│   running    │
                    │       └──────┬───────┘
                    │              │ mark_ready!
                    │              │ after: set ready_at, container_id
                    │              ▼
                    │       ┌─────────────┐
                    │       │    ready     │
                    │       └──────┬───────┘
                    │              │
              fail! │    finish!   │ request_finish!
  (from any         │              │ after: signal ContainerWorkflow
   active state)   │              ▼
                    │       ┌─────────────┐
                    │       │  finishing   │  ← NEW STATE
                    │       └──────┬───────┘
                    │              │ complete! / fail!
                    ▼              ▼
              ┌──────────┐  ┌──────────┐
              │  failed   │  │ finished │
              └──────────┘  └──────────┘
                    │              │
                    └──────┬───────┘
                           │ after: sync_usage, signal_workflow_execution
                           │        broadcast
```

**New:** a `finishing` state has been added — for when a finish has been requested but the container has not yet stopped. This removes the need for `request_finish!` as a separate method.

#### WorkflowRun State Machine (extended)

```
              ┌──────────┐
              │ pending   │ (initial)
              └────┬──────┘
                   │ start!
                   │ after: update started_at, broadcast, record_activity
                   ▼
              ┌──────────┐          pause!
          ┌───│ running   │─────────────────┐
          │   └────┬──────┘                 │
          │        │                        ▼
          │        │                  ┌──────────┐
          │        │                  │  paused   │
          │        │                  └────┬──────┘
          │        │      resume!          │
          │        │◄──────────────────────┘
          │        │
          │   complete! / fail!
          │        │ after: update completed_at, broadcast, record_activity
          │        ▼
          │   ┌──────────┐    ┌──────────┐
          │   │ completed │    │  failed  │
          │   └──────────┘    └──────────┘
          │
          │ cancel!
          │ after: cancel_active_step_runs! (cascade), record_activity
          ▼
    ┌──────────┐
    │ cancelled │
    └──────────┘
```

#### StepRun State Machine (NEW AASM!)

```
    ┌──────────┐
    │ pending   │ (initial)
    └────┬──────┘
         │ prepare!
         │ after: create_sub_step_runs!
         ▼
    ┌──────────┐
    │ running   │
    └────┬──────┘
         │
    ┌────┼────────────┬──────────────┐
    │    │            │              │
    │  complete!    fail!         skip!
    │    │            │              │
    │    ▼            ▼              ▼
    │ ┌──────────┐ ┌──────────┐  ┌──────────┐
    │ │ completed│ │  failed  │  │ skipped  │
    │ └──────────┘ └──────────┘  └──────────┘
    │
    │ wait!                          cancel!
    │    ▼                         (from any active state)
    │ ┌──────────────┐                    │
    │ │ waiting_input│                    ▼
    │ └──────────────┘            ┌──────────┐
    │  approve!/retry!/skip!      │ cancelled│
    │  → complete/running/skipped └──────────┘
    │
```

**Key change:** guards ensure that you cannot transition into an invalid state.

#### BoardTask Lifecycle (via ColumnTransitions)

BoardTask does not need a classic state machine, since its "states" are columns on the board, which are configurable. But it needs a **single orchestrator service** for moves:

```
BoardTask is moved to a column
    │
    ├── ColumnTransition.create! (history record)
    ├── WorkflowAutoTriggerService.check! (if auto trigger)
    │       ├── cancel_active_runs! (cascade via WorkflowRun state machine)
    │       └── create + start new WorkflowRun
    └── broadcast (via ActionCable)
```

### 3.3 Cascade relationships between state machines

```
TerminalSession.finish! / fail!
    └── signal WorkflowExecutionWorkflow (Temporal)
            └── WorkflowExecutionWorkflow decides next step
                    └── UpdateWorkflowRunStatusActivity → WorkflowRun.complete! / fail!
                            └── WorkflowRun.on_completed → broadcast, record_activity

WorkflowRun.cancel!
    └── cancel_active_step_runs!
            └── StepRun.cancel!
                    └── TerminalSession.cancel! → cancel Temporal workflow
                            └── ContainerWorkflow cleanup → TerminalSession.fail!
```

### 3.4 Refactoring: what to extract from models into State Machines

| Currently in the model | Move to | What it does |
|---|---|---|
| `TerminalSession#start_workflow!` | StateMachine `after :start` | Launch Temporal |
| `TerminalSession#request_finish!` | StateMachine event `:request_finish` → state `:finishing` | Signal Temporal |
| `TerminalSession#cancel!` | StateMachine event `:cancel` | Cancel Temporal workflow |
| `TerminalSession#sync_usage` | StateMachine `after [:finish, :fail]` | Sync usage stats |
| `TerminalSession#signal_workflow_execution_finished` | StateMachine `after [:finish, :fail]` | Signal parent workflow |
| `StepRun#mark_*!` (all 6) | AASM events with guards | Validated transitions |

### 3.5 Single WorkflowRun Creation Service

Instead of three creation places:

```ruby
class WorkflowRunCreator
  def self.create!(workflow:, project:, user:, board_task: nil, mode: :interactive, step_overrides: {}, **opts)
    run = WorkflowRun.create!(
      workflow: workflow, project: project, user: user,
      board_task: board_task, mode: mode, step_overrides: step_overrides, **opts
    )

    workflow.steps.order(:position).each do |step|
      run.step_runs.find_or_create_by!(step: step)
    end

    WorkflowService.start_workflow_execution(run)
    run
  end
end
```

---

## 4. Implementation plan (priorities)

### Phase 1: StepRun → AASM (high priority, low risk)

- Migrate StepRun to AASM with validated transitions
- Add guards (you cannot `complete` from `cancelled`)
- Side effects (broadcast) remain in state machine callbacks
- Minimal changes to calling code (Activities, Controllers)

### Phase 2: TerminalSession State Machine — add a `finishing` state

- Add state `:finishing` and event `:request_finish`
- Remove the ad-hoc `request_finish!` method from the model
- All Temporal logic remains in the state machine's after callbacks

### Phase 3: WorkflowRunCreator — single creation point

- Create a `WorkflowRunCreator` service
- Refactoring: the controller, TasksController, and WorkflowAutoTriggerService use it

### Phase 4: Extract business logic from models into state machine concerns

- `start_workflow!`, `cancel_workflow`, `signal_workflow` → state machine concern
- `sync_usage` → state machine after callback
- The model becomes clean: associations, validations, scopes

### Phase 5 (optional): SubStepRun → AASM

- If a need for more complex transitions arises

---

## 5. Risks and limitations

1. **Temporal workflows** — part of the orchestration lives in Temporal. State machines on the Rails side manage the _model state_, while Temporal manages the _sequence of steps_. It is important not to duplicate orchestration.

2. **Race conditions** — concurrent updates require `lock!` before state transitions. AASM supports pessimistic locking.

3. **Backward compatibility** — StepRun#mark_*! methods are called from Temporal activities. When migrating to AASM, the API must be preserved or all call sites must be updated.

4. **BoardTask** — has no fixed states (columns are configurable). A classic state machine does not fit. TaskMoveService already serves as the lifecycle manager.

---

## 6. Target Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Controllers / API                     │
│  (invoke ONLY state machine events)                  │
└───────────┬──────────────────────┬──────────────────────┘
            │                      │
            ▼                      ▼
┌───────────────────┐  ┌───────────────────────────────────┐
│  State Machines   │  │  Services (single responsibility) │
│  ─────────────    │  │  ─────────────────────────────── │
│  TerminalSession  │  │  WorkflowRunCreator              │
│  WorkflowRun      │  │  TaskMoveService                 │
│  StepRun          │  │  SessionConfigResolver            │
│  SubStepRun       │  │                                   │
│                   │  │                                   │
│  after_transition │  │                                   │
│  callbacks:       │  │                                   │
│  → Temporal       │──│→ start/signal/cancel workflows   │
│  → Broadcasts     │  │                                   │
│  → Cascades       │  │                                   │
│  → Activity log   │  │                                   │
└───────────────────┘  └───────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│                  Temporal Workflows                       │
│  (orchestration of the step sequence)                  │
│  ContainerWorkflow, WorkflowExecutionWorkflow            │
│                                                          │
│  Activities invoke state machine events:                │
│  → workflow_run.start!                                   │
│  → step_run.prepare!                                     │
│  → session.start!                                        │
└─────────────────────────────────────────────────────────┘
```
