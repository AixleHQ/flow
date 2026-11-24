# Session lifecycle: every state change through the state machine and one service

Status: proposed (task #273). Nothing here is built. The rule it applies is "change state only through its owner" (`docs/architecture/implementation-patterns.md`, Anti-Patterns, added by #274).

## 1. What and why

`TerminalSession` has an AASM state machine (`app/state_machines/terminal_session_state_machine.rb`), but:
- some moves a session really makes are written past it with `update!(state: …)`, because the machine has no event for them;
- the side effects of an ending (stop the admission's operations, signal or cancel the container workflow, wake the run, set the error message first) are decided again at every call site;
- the relay's `session_ended` signal (#270) had no single place to live, so it sits in a model `after_save` (`left_ready?`).

The target: every move is an event of the machine, and one service, `Sessions::Lifecycle`, is the only code that fires those events. Nothing a user sees, no outcome and no message changes, with one accepted exception: `Lifecycle.cancel` now fires the event for a session that has no admission (§3.2, decision 9).

## 2. Inventory

### 2.1 State written past the machine

| Where | Write | Why the machine lacks it |
|---|---|---|
| `AdmittedPhaseActivity#finalize_session` | `update!(state: outcome_state)` | `running`/`ready`/`not_started` → `finished` (agent exited), `finished` → `failed` (output collection failed), and writes of the state the session already has |
| `Sessions::Suspension.suspended!` | `update!(state: "suspended")` | no event enters `suspended` (the machine's own comment says so) |
| `Sessions::SuspensionExpiry#expire_step!` | `update!(state: "failed")` | `suspended` → `failed` is not an event |
| `Sessions::SuspensionExpiry#discard!` | `update!(state: "finished")` | the move exists as `expire_suspension`, but is not used |

All of them also skip the events' `after` callbacks.

### 2.2 Events fired outside the model

| Caller | Events | Notes |
|---|---|---|
| `SessionService.finish` | `start_finishing!`, then a signal or `finish!` | queued sessions go to `cancel` or cancel the step's run |
| `SessionService.suspend` | `start_finishing!` + signal | sets the suspend request key first |
| `SessionService.fail_session` / `fail_admitted_session` | `fail!`, or `SessionAdmissionService.cancel!(outcome: "failed")` | error message first; a signal after |
| `SessionService.fail_session_if` | `fail!` under `with_lock`, or `SessionAdmissionService.fail_if!` | compare-and-set |
| `SessionService.fail_on_runner_refusal` | `fail!` | before any admission |
| `SessionService.admit_step_session!` | `cancel!` | the run was stopped before enqueue |
| `SessionService.cancel` | `SessionAdmissionService.cancel!` + workflow cancel | also called by `reset_auth`, `ProjectMove::Mover`, `WorkflowService.cancel_active_step_runs` |
| `SessionAdmissionService` | `enqueue!` (in `enqueue!`), `cancel!`/`fail!` (`conclude!`, from `cancel!`, `fail_if!` and `drain!` through `close_queued!`) | the admission service ends sessions inside its writer lock |
| `SessionLaunchRelay` | `SessionAdmissionService.cancel!`, then `update!(error_message:)` | a refused launch; also `abandon` → `fail_session` |
| `ContainerStrategies::BaseStrategy#after_cleanup` | `fail!`, `TerminalSession#complete_finish!` | used by the v1 `ContainerWorkflow` (tool sessions), inside the workflow's cleanup |
| `ContainerStrategies::AgentBaseStrategy#mark_session_ready` | `mark_ready!` | |
| `Activities::Session::CleanupStaleActivity` | `fail!`, `start_finishing!`, `finish!`, each after `update(error_message:)` | the container workflow is already gone |
| `AdmittedPhaseActivity#run` | `start!` | first phase |
| `ProjectMove::Mover#cancel_waiting_work!` | `SessionService.cancel`, then `cancel!` for a session with no admission | |
| `Sessions::Suspension.restored!`, `SuspensionExpiry#expire!` | `mark_restored!`, `expire_suspension!` | |

Already through `SessionService` and staying there in spirit: `PersonalTools::StopSession`, `InternalTools::FinishSession`/`FailSession`, `CompanyMembership`, `Sessions::AuthPause`, `Sessions::Checks::Base`, `Runners::Revocation`, `Runners::ContactLoss`, `Runners::Registration`, `ScanDeadContainersActivity`, `CleanupStaleRunsActivity`, `WorkflowService.fail_active_step_runs`. They change a call (`SessionService.x` → `Sessions::Lifecycle.x`), not a behaviour.

The task text lists `AuthConcern` (`start!`). That is `UserSession.start!`, a different model: out of scope, no change.

### 2.3 Side effects that live in the model

`TerminalSession#on_*` callbacks mix two things. Assignments that belong to the transition (`started_at`, `ready_at`, `finishing_at`, usage totals, `finished_at`, `container_id`), and effects that leave the process: `notify_workflow_execution_if_step_session` (after commit), `start_workflow_run_execution` (an `update_all` on `WorkflowRun`), `Sessions::Suspension.restored!` (on ready, after commit), and the `after_save` relay signal. `complete_finish!` is a model helper that chains two events.

## 3. Approach

### 3.1 Decision: a new `Sessions::Lifecycle`, not `SessionService`

`SessionService` is 600 lines of creation, preflight and workflow-step building, and the lifecycle half is a quarter of it. A new module `Sessions::Lifecycle` (`app/services/sessions/lifecycle.rb`, a module with `module_function` methods, as `Sessions::Suspension` and `Runners::RelaySignals` are) keeps the one question "how does a session change state" in one file. `SessionService` keeps creating, restoring and revalidating sessions. Its lifecycle methods (`finish`, `suspend`, `cancel`, `reset_auth`, `fail_session`, `fail_session_if`) move to `Lifecycle`; no delegating copies stay behind, so there is one entry point. Callers are renamed in the same change.

Alternative rejected: grow `SessionService`. It would avoid renaming about 25 call sites, but it keeps the file where lifecycle rules are mixed with preflight code, and #274's rule asks for one owner that is easy to name and find.

### 3.2 Two families of methods

Every ending has two kinds of caller, and they must not be mixed:

**From outside the container workflow.** The workflow is still running, so the method also stops the admission's operations and signals (or cancels) the workflow so cleanup runs. These are the methods today's `SessionService` has.

| Method | Replaces |
|---|---|
| `enqueue(session)` | `SessionAdmissionService.enqueue!` call sites |
| `finish(session)` | `SessionService.finish` |
| `suspend(session)` | `SessionService.suspend` |
| `fail(session, error_message:)` | `fail_session`, `fail_on_runner_refusal`, the `SessionLaunchRelay.abandon` write |
| `fail_if(session, expected_state:, error_message:, &guard)` | `fail_session_if` (compare-and-set, §3.5) |
| `cancel(session, error_message: nil)` | `SessionService.cancel`, `admit_step_session!`'s `cancel!`, `Mover`'s second `cancel!`, `SessionLaunchRelay`'s cancel plus message. **One behaviour change, see below** |

**From inside the container workflow, or after it is gone.** The state is recorded and nothing is signalled: the workflow is already ending.

| Method | Replaces |
|---|---|
| `start(session)` | `session.start! if may_start?` in `AdmittedPhaseActivity` |
| `ready(session, container_id:)` | `AgentBaseStrategy#mark_session_ready` |
| `record_finishing(session)`, `record_finished(session)` | `start_finishing!`/`finish!` in `CleanupStaleActivity`; `complete_finish!` (removed from the model; `record_finished` is the same idempotent chain) |
| `record_failure(session, error_message:)` | `update(error_message:)` + `fail!` in `CleanupStaleActivity` and `BaseStrategy#after_cleanup` |
| `finalize(session, error:)` | `finalize_session` (§3.4) |
| `suspended(session)` | `Suspension.suspended!` |
| `restored(origin)` | `Suspension.restored!` |
| `expire_suspension(session)`, `expire_suspended_step(session)` | `SuspensionExpiry#expire!`, `#expire_step!`, `#discard!` |
| `slot_released(session)` | `session.send(:notify_workflow_execution_if_step_session)` after `SessionAdmissionService.release!` |

**Behaviour change in `cancel`.** Today `SessionService.cancel` leaves the state of a session with no admission unchanged: `SessionAdmissionService.cancel!` returns when there is no admission, and only the Temporal cancel runs, for a workflow that cannot exist. `Lifecycle.cancel` fires `cancel` for such a session. This is accepted, as one rule for every caller, and it replaces `ProjectMove::Mover`'s second `cancel!`, which exists only to cover this case.

The path it changes is the run cancel fan-out (`WorkflowService.cancel_active_step_runs`). It now cancels a step session that was built but not yet admitted. Today that session stays as it is until `admit_step_session!` meets the stopped run, and cancels it after `Stopped`. The outcome stays `cancelled`. What differs is that the event and its callbacks run from the fan-out, before the step run is marked cancelled, and that the later `cancel!` in `admit_step_session!` finds the session already cancelled and does nothing (`Lifecycle.cancel` on an ended session is a no-op, as `may_cancel?` is today). The run's wake-up is skipped there, because the run's stop was requested (§3.6). Nothing else changes for this path.

The one primitive underneath is `Lifecycle.transition!(session, event, error_message: nil, notify: true)`. It sets the error message, fires the event inside one transaction, and runs the effects of §3.6. It is public for exactly one other caller, `SessionAdmissionService` (§3.3). No other code calls an event of `TerminalSession` that changes `state`.

### 3.3 `SessionAdmissionService` stops moving sessions, except in its lock

The admission service keeps the queue, permits, the operation ledger and the release. Its session moves happen inside the writer lock, atomic with closing the admission (`enqueue!`, `cancel!`, `fail_if!`, and `drain!` closing an admission whose run was stopped). They cannot move out of the lock without leaving a closed admission with a live session after a crash. So inside the lock it calls `Sessions::Lifecycle.transition!` and nothing else on the session; `conclude!` is deleted. `Lifecycle.cancel` and `Lifecycle.fail_if` call `SessionAdmissionService.cancel!`/`fail_if!` as they do today. Calling `transition!` out of the lock is allowed, since it takes the session's own row lock when it needs one.

Alternatives rejected:
- Moving the lock logic of `cancel!`/`fail_if!` into `Lifecycle`. `drain!` still has to end sessions in its lock, so the dependency stays; the admission code would be split across two files.
- Yielding the verdict from the admission service to a block. Four call shapes (`enqueue!`, `cancel!`, `fail_if!`, `drain!`) would each need a block protocol for one call.

`SessionAdmission` gets a predicate for the repeated condition `admitted_at.nil? || (launch_state == "pending" && claimed_at.nil?)` (`unlaunched?`), as the Model Predicates rule asks. It is used in `cancel!` and `fail_if!`.

### 3.4 `finalize` and the machine's missing moves

`finalize(session, error:)` replaces `finalize_session`. Inside one transaction it reloads the row, computes the outcome, fires the event for the (from, to) pair, assigns `finished_at ||= now`, `container_id = nil` and the preferred error message, and saves once.

The outcome rules do not change, but they move out of the activity into the model, where the Model Predicates rule puts what a state means: `TerminalSession#ending_error(error)` (was `outcome_error`) and `#ending_state(error)` (was `outcome_state`). The activity still needs them before `finalize` (`session_failed?`, `collect_outputs`), and calls the model.

| From | To | Event |
|---|---|---|
| `finishing` | `finished` | `finish` (exists) |
| `not_started`, `queued`, `running`, `ready` | `finished` | **new** `finish_without_request` (the agent exited). `queued` was added in the implementation: a launch that ends before the first phase starts the session is finalized from `queued` today, so the table had to cover it |
| `not_started`, `queued`, `running`, `ready`, `finishing` | `failed` | `fail` (exists) |
| `finished` | `failed` | **new** `fail_after_finish` (output collection failed) |
| `not_started`, `queued`, `running`, `ready`, `finishing` | `cancelled` | `cancel` (exists) |
| `finished`, `failed`, `cancelled` | the same state | no event: no state changes. Only `finished_at`, `container_id` and `error_message` are assigned, which are plain columns with no owner method |
| anything else | | `finalize` raises `TerminalSession::InvalidStateError`: the cleanup retries and Sentry shows it. No state is guessed |

The `suspended` branch of `finalize_session` becomes `Lifecycle.suspended`, firing the new event `mark_suspended` (from `running`, `ready`, `finishing`; callback assigns `finished_at ||= now`, `container_id = nil`; `suspended_at` and `restore_expires_at` are passed as event arguments). `Suspension` keeps `window_end` and `due?`, and writes no state.

`SuspensionExpiry`:
- `expire!` and `discard!` both fire `expire_suspension` (`suspended` → `finished`); `discard!` adds its metadata key first.
- `expire_step!` fires the new event `expire_suspended_step` (`suspended` → `failed`), with the step run's `update!(state: :running)` in the same transaction, and notifies the run after commit.

Four events are added in all: `finish_without_request`, `fail_after_finish`, `mark_suspended`, `expire_suspended_step`. They are separate events and not wider `from` lists on `finish`/`fail`, because `may_fail?` and `may_finish?` guard live code (`fail_session` on a suspended session is a no-op today, and must stay one).

### 3.5 Compare-and-set and `fail` order

- `fail_if` keeps its shape: under the session's row lock (or, with an unreleased admission, under the admission service's writer lock, which locks the admission and then the session), re-check `expected_state` (or "not ended") and the block, set the message, fire `fail`; the stop of the admission's operations and the workflow signal go after the commit. A session that finished or was cancelled meanwhile keeps its outcome and `fail_if` returns false. `Sessions::Checks`, `AuthPause`, `Revocation`, `ContactLoss` and `Registration` call it unchanged apart from the module name.
- `fail` keeps its order: message, stop operations, `fail`, then the signal. The cleanup phase decides the step's outcome from `session.state` (`CompleteStepActivity`), so the session must be `failed` before the signal.
- Admission: a session with an unreleased admission ends through `SessionAdmissionService.cancel!(outcome: "failed")` / `fail_if!` as now, and the reservation is released only once the runtime is confirmed gone (AD-6). The verdict stays `failed` for a watchdog and `cancelled` for a stop someone asked for. A cancelled step session cancels its run; a failed one does not. `Lifecycle.fail` and `.cancel` keep that choice.

### 3.6 Side effects: written once, in `transition!`

The `on_*` callbacks keep only assignments that belong to the transition. After commit, `transition!` runs the effects, by event and option:

| Effect | When | Replaces |
|---|---|---|
| Wake the parent run (`notify_container_finished`), skipped when the run's stop was requested | an ending event (`finish`, `fail`, `cancel`, `expire_suspended_step`, `finish_without_request`) with `notify: true` | the notify inside `on_finished`/`on_failed`/`on_cancelled` |
| `Runners::RelaySignals.session_ended` | any event whose from-state is `ready`, on a runner session (`on_runner?`) | the model `after_save` and `left_ready?` |
| `Sessions::Suspension.restored!` | `mark_ready` of a session with `restored_from_session_id` | `on_ready` |
| `WorkflowRun.execution_started_at` | `start` of a workflow step, in the same transaction | `start_workflow_run_execution` |

What runs for `finalize`, transition by transition:
- **`notify: false` for every move `finalize` makes.** Today `finalize_session` writes no callbacks, and the run is woken once, by `slot_released`, after the reservation is released (the parent reads "unreleased + terminal" as `finishing`, so it waits for capacity). Waking it earlier would change when the next step may start. So `finalize` wakes nobody, and `slot_released` is kept. The notify is a flag, so a second one (as `finish!` plus `slot_released` already give) changes nothing.
- **Usage totals** are assigned by `sync_usage` just before `finalize`, and again by the callbacks of `finish`/`fail`/`cancel` (a read of the same row), so `fail_after_finish` does not need its own copy. It assigns nothing but what `finalize` assigns after it.
- **`session_ended`** is sent by `finalize` when the session was `ready` (`ready` → `finished`, `failed`, `cancelled`, `suspended`), and by `finish`/`suspend` (`ready` → `finishing`), as the after_save does today. A repeated `finalize` on a session that left `ready` sends nothing.

The model's `after_save :signal_relay_session_ended`, `left_ready?`, `signal_relay_session_ended` and `complete_finish!` are removed. `notify_workflow_execution_if_step_session` moves to `Lifecycle` (private). `sync_usage` stays on the model; `finalize` calls it through a public method instead of `send`.

#270's tests for the signal (`test/services/runners/relay_signals_test.rb`, "session_ended" block) move to a `Sessions::Lifecycle` test. The test "a state written directly out of ready sends session_ended too" is deleted: a direct write is no longer a supported move. It is replaced by the same assertion for `finalize` from `ready`.

### 3.7 Enforcement

- **A hard guard on direct writes: AASM's `no_direct_assignment: true`** on the `TerminalSession` machine (AASM 6.0.0 in `Gemfile.lock`). It makes `state=` and `update!(state: …)` raise `AASM::NoDirectAssignmentError`, so a direct write cannot get in, and no request-local state is needed. It is adopted in change 4, once nothing writes `state` directly.
  - **Cost.** Factories and tests that set `state:` directly need another way to put a session in a state: a factory trait that walks the events, or a small test helper that writes the column with `update_column`/`update_all`. Finding them is part of change 4.
  - **What it does not catch.** `update_all`, `update_column(s)` and raw SQL skip the setter. The source scan below covers `update_all`/`update_column` on `state` too.
- **An ownership test** (`test/services/sessions/lifecycle_ownership_test.rb`) only has to find state events fired outside `Sessions::Lifecycle`, since AASM covers direct writes. It fails when `app/` outside `terminal_session.rb`, the state machine and `sessions/lifecycle.rb` contains a state event on a session (`start_finishing!`, `mark_ready!`, `expire_suspension!`, `mark_restored!`, `finish_without_request!`, and `\.(start|enqueue|cancel|fail|finish)!` on a variable named `session`), or `update_all`/`update_column(s)` that sets `state`. It is heuristic, and says so in its message; code review still flags a new violation as `[Must]`.
- `whiny_persistence: true` stays.

## 4. Data model changes

None. No migration, no new column. New events, callbacks and a `SessionAdmission#unlaunched?` predicate only.

## 5. API / interface changes

No HTTP, MCP or Temporal change. Internal only:
- New: `Sessions::Lifecycle` (§3.2), `TerminalSession#ending_state`/`#ending_error`, `SessionAdmission#unlaunched?`, four machine events.
- Removed: the lifecycle methods of `SessionService`, `SessionAdmissionService.conclude!`, `TerminalSession#complete_finish!` and the `after_save` relay signal.
- Temporal: activities keep their inputs and results, so running workflows are unaffected by a deploy.

## 6. Implementation steps

Delivery is two tasks:
- **#273** builds changes 1 to 3 in one PR.
- **#283** builds change 4 (effects into `transition!`, the guards, the docs). It starts after #273's implementation PR merges.

Four changes, in this order. Each leaves the tests green.

1. **Machine and model, additive.** Add the four events and their assignment-only callbacks to `TerminalSessionStateMachine`; add `ending_state`/`ending_error` (moved with their comments and the `GENERIC_ERROR_MESSAGES` rule) and `SessionAdmission#unlaunched?`. `AdmittedPhaseActivity` calls the model's `ending_*`. Tests: the state machine test gets every event, every `from` that must be refused, and the callbacks.
2. **`Sessions::Lifecycle`, outside family.** Add `transition!` (events fired as today; effects still in the model callbacks) and `enqueue`, `finish`, `suspend`, `fail`, `fail_if`, `cancel`, moving the bodies from `SessionService`. `SessionAdmissionService` calls `transition!` instead of `session.enqueue!`/`fail!`/`cancel!` and drops `conclude!`. Rename all the callers (§2.2), including `SessionLaunchRelay`, `ProjectMove::Mover` (one `Lifecycle.cancel`, no second `cancel!`), `WorkflowService`, `PersonalTools::StopSession`, `InternalTools::*`, `CompanyMembership`, `Sessions::*`, `Runners::Revocation`, `Runners::ContactLoss`, `Runners::Registration`, `ScanDeadContainersActivity`, `CleanupStaleRunsActivity`. The existing `SessionService` tests move to the Lifecycle test files with their bodies unchanged apart from the module name, except the cancel case of §3.2.
3. **Inside family.** Add `start`, `ready`, `record_*`, `finalize`, `suspended`, `restored`, `expire_suspension`, `expire_suspended_step`, `slot_released`. Move `AdmittedPhaseActivity#finalize_session`, `BaseStrategy#after_cleanup`, `AgentBaseStrategy#mark_session_ready`, `CleanupStaleActivity`, `Suspension` and `SuspensionExpiry` onto them. `finalize` uses the table in §3.4.
4. **Move the effects, and close it (task #283).** Move the effects out of the model callbacks into `transition!` (§3.6), delete the `after_save`, `left_ready?`, `complete_finish!` and the notify from the model, move #270's tests. Turn on `no_direct_assignment: true`, fix the factories and tests that set `state:` (§3.7), and add the ownership test. Update `docs/architecture/implementation-patterns.md`: the `finalize_session` "Avoid" example becomes a "done" example (`AdmittedPhaseActivity#finalize` through `Sessions::Lifecycle`), and the State Machines section names the service as the owner. Add a `CHANGELOG.md` line only if the project's rule asks for one for internal refactors.

Changes 1 to 3 do not change who sends which effect, which is why they can be reviewed apart from change 4.

#277 (PR 859) changes only `refuse_runner_pick` in `SessionService`, which is creation-side code and stays there, plus `Runners::Selection`, the session form and docs. It does not touch the files this design renames. If #277 merges first, the implementation rebases on it.

## 7. Testing approach

Following `test/` mirroring `app/`:
- **State machine** (`test/state_machines/terminal_session_state_machine_test.rb`): each new event allowed and refused from the right states; the callbacks' assignments; `may_fail?` is false from `suspended` (the reason events are separate).
- **`finalize` matrix** (`test/temporal/activities/admitted_phase_activity_test.rb`, existing cases kept): every (from, to) pair of §3.4, the same-state case with no event, the unknown pair raising, the outcome rules (requested stop is not a failure, `finishing_at` without `ready_at` is `cancelled`, `preferred_error_message`), and a second `finalize` changing nothing.
- **Lifecycle** (`test/services/sessions/lifecycle_test.rb`, taking over `session_service_test.rb`, `session_service_fail_session_if_test.rb`): one test per ending path of §2.2, each asserting the state, the message, the signal or workflow cancel, and the run's wake-up. Compare-and-set: a session that finished or was cancelled meanwhile keeps its outcome. Admission: unreleased admission ends through the admission service, and the reservation stays until released.
- **Relay signal:** `session_ended` for each of `finish`, `fail`, `cancel`, `finalize` and `suspended` from `ready`; none from `running`; none for a hosted session; none on a repeated `finalize`.
- **Admission** (`session_admission_service_test.rb`, `…_concurrency_test.rb`): the same cases with `transition!` in the lock.
- **Unchanged and must pass:** `CleanupStaleActivity`, `Runners::Revocation`, `ContactLoss`, suspension tests, `SessionLaunchRelay`.
- **Cancel of an unadmitted session** (§3.2): the run cancel fan-out cancels a step session that was built but not yet admitted. Assert the state is `cancelled`, the callbacks ran once, the run is not woken (its stop was requested), the step run ends `cancelled`, and a following `admit_step_session!` that meets `Stopped` leaves the session as it is. A direct `Lifecycle.cancel` of a session with no admission fires the event, and a second one does nothing.
- **Hard guard** (§3.7, change 4): `session.update!(state: …)` raises.
- **Ownership test** (§3.7).

QA on staging, as the task lists: a hosted session finished, stopped before ready, and failed; a workflow step that succeeds and one that fails; a runner session on a simulated machine, finished and revoked. Same state and message as before.

## 8. Edge cases and risks

- **The run is woken at a different moment** if `finalize` notified. That is why it does not (§3.6). A test asserts that no notify goes out from `finalize` and one goes out from `slot_released`.
- **Retried cleanup.** `finalize` is repeated until the container is gone. The same-state branch must not move `finished_at` (kept with `||=`) and must not resend signals.
- **`not_started` → `finished`** is accepted from the machine because the current code allows it. If it can never happen, the event's `from` can lose it later; today's outcome rules do not exclude it.
- **Lock order.** `transition!` called inside the writer lock must not take the admission lock or the policy lock again. It takes none: the caller holds what it needs. `fail_if` keeps the order writer lock → admission → session.
- **Effects in `transition!` after commit.** `after_all_transactions_commit` runs at once when no transaction is open, so a caller that fires an event outside a transaction still gets its effects, in order.
- **Heuristic ownership test** can miss a differently named variable. Review is the second guard.
- **v1 `ContainerWorkflow`** (tool sessions) still runs `BaseStrategy#after_cleanup`. It is routed through `record_failure`/`record_finished` unchanged in behaviour. Whether it can be removed is a separate question.
- **Hosted sessions** run through the same code and show no change in outcome or message. The one difference is the cancel of an unadmitted step session (§3.2).
- **Hard guard breaks test setup.** Tests and factories that set `state:` fail once `no_direct_assignment` is on (§3.7). They are found and fixed in change 4, not left to CI to discover.

## 9. Decisions and assumptions

| # | Decision | Source |
|---|---|---|
| 1 | New `Sessions::Lifecycle` as the one owner; `SessionService` loses its lifecycle methods | task scope item 2 leaves the choice to the design; §3.1 |
| 2 | `finalize`'s missing moves are two new events, `finish_without_request` and `fail_after_finish`; same-state writes are not transitions | task §1; §3.4 |
| 3 | `finalize` does not wake the run; `slot_released` does, after the release, as now | task "Callbacks run once"; `finalize_session` has no callbacks today, and the cleanup notifies after the release |
| 4 | Suspension's three direct writes are brought in too, with `mark_suspended` and `expire_suspended_step` | task "Nothing writes `state` directly any more"; found in the inventory, not named in the task |
| 5 | `SessionAdmissionService` fires events only through `Lifecycle.transition!`, inside its lock | §3.3 |
| 6 | The outcome rules move to `TerminalSession#ending_state`/`#ending_error`, unchanged | Model Predicates rule; the task says the rules stay as they are |
| 7 | `session_ended` and the run's wake-up are effects of `transition!`; the model `after_save` is removed | task scope item 3 |
| 8 | `AuthConcern`'s `start!` is `UserSession`, not a session of this model | read from `app/controllers/concerns/auth_concern.rb` |
| 9 | **Behaviour change, accepted.** `Lifecycle.cancel` of a session with no admission fires `cancel` (today the state is left unchanged) and does not cancel a workflow (none can exist without an admission). One rule for every caller; it replaces `Mover`'s second `cancel!`. It changes the run cancel fan-out, which now cancels a built, unadmitted step session (§3.2) | `SessionService.cancel` left the state alone and called Temporal for a workflow that cannot exist; Alex's decision on the design |
| 10 | #277's PR was read: it does not touch what this design renames, so nothing waits for it. If it merges first, the implementation rebases | Alex's decision on the design |
| 11 | Delivery in two tasks: #273 builds changes 1 to 3, #283 builds change 4 after #273's PR merges | Alex's decision on the design |
| 12 | The hard guard is AASM's `no_direct_assignment: true`, adopted in change 4 | AASM 6.0.0; Alex's decision on the design |

## 10. Deferred questions

- Removing the v1 `ContainerWorkflow` and `BaseStrategy#after_cleanup`: out of scope; they are routed, not deleted.
- `StepRun` and the operation models keep writing their own state (task, Out of scope).
