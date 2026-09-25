# Changing Temporal workflow code

> How to change code under `app/temporal/workflows/` without breaking executions
> that are already running, and how the test suite checks it.

## Why a change can break a running execution

A worker does not keep an execution's state in memory. When it picks an execution
up (after a deploy, a restart, or a cache eviction) it **replays** the execution's
history through the current workflow code and checks that the code issues the same
commands, in the same order, that the history records: schedule this activity,
start that timer, record this marker. If the code now does something else at any
point, the workflow task fails with a nondeterminism error (`[TMPRL1100]`). The
server retries that task forever, so the execution is stuck until code that
replays it is deployed.

Our executions stay open for a long time. A workflow run
(`WorkflowExecutionWorkflow`) can stay open for 24 hours, and an admitted run
(`WorkflowExecutionWorkflowV2`) for 7 days (`TemporalWorkflowRegistry`). Every
deploy therefore replays histories recorded by older code.

`WorkflowExecutionWorkflowV2` inherits its step loop from
`WorkflowExecutionWorkflow`, and `ContainerWorkflowV2` inherits its phases from
`ContainerWorkflow`. A change to the parent changes the child too.

## What is safe and what is not

Safe without a patch, because it does not change which commands are issued:

- Changing an activity's implementation, including what it returns. Replay uses
  the results recorded in history, not new results.
- Adding or changing a signal handler that only writes instance variables.
- Removing code that no execution can reach.
- Changing log lines.

Needs a patch, because a recorded history would see different commands:

- Adding, removing or reordering activity calls, timers (`Workflow.sleep`,
  `Workflow.timeout`), child workflows or markers.
- Changing a condition that decides whether one of those runs, including how a
  signal or an activity result is interpreted.
- Renaming an activity in `app/temporal/workflows.yml`. The activity type is
  part of the command.
- Changing the activity or timer id sequence, for example by starting activities
  in a different order.

## Using `patched`

Put the new behaviour behind `Temporalio::Workflow.patched("<patch-id>")`:

```ruby
if Temporalio::Workflow.patched("step-state-decides-without-signal")
  # new behaviour
else
  # old behaviour, exactly as it was
end
```

A new execution records a marker the first time it reaches the call, and gets
`true`. Replaying a history that has the marker also gets `true`. Replaying a
history recorded before the patch gets `false` and keeps the old behaviour for the
rest of that execution.

Rules:

- Call `patched` at the point where the old and new code diverge, not earlier.
  Calling it at the start of `run` would put a marker into every history,
  including histories that never reach the change.
- Patch ids are permanent. Never reuse one for a different change.
- Do not call `patched` in `initialize`. The SDK does not allow commands there.
- Retire a patch in two deploys:
  1. Once no execution started without the patch can still be open, replace
     `patched(id)` with `Temporalio::Workflow.deprecate_patch(id)` and delete
     the old branch. That is 24 hours after the deploy for a patch only
     `WorkflowExecutionWorkflow` runs, and 7 days for one V2 inherits, plus a
     margin.
  2. Once no execution started before step 1 can still be open, delete the
     `deprecate_patch` call.

  Deleting a `patched` call in one step breaks every history that has its
  marker (`Non-deprecated patch marker encountered`).

Patches in use:

| Patch id | Workflow | What it guards |
|---|---|---|
| `keep-signals-delivered-before-run` | `WorkflowExecutionWorkflow` (and V2) | `run` no longer clears decisions that signals delivered before it |
| `keep-signals-delivered-during-launch` | `WorkflowExecutionWorkflow` | a retried step's decision is cleared before its launch, so a signal that arrives while the launch activity runs is kept |
| `step-state-decides-without-signal` | `WorkflowExecutionWorkflowV2` | a Skip or Approve that is written to the step counts even if its signal is lost |

## The replay test

`test/temporal/workflows/history_replay_test.rb` replays every history under
`test/fixtures/files/temporal_histories/<workflow>/<scenario>/<label>.json`
through the production workflow classes, with the activity names the registry
gives them. It fails on any nondeterminism error and names the history. A second
test fails if a scenario in `test/support/temporal_history_scenarios.rb` has no
recorded history.

A scenario is one execution: its input, scripted activity results, and a `drive`
that sends signals or a cancel once the execution is waiting on a timer. The
recorder runs it against the time-skipping test server and saves the history.

The label says which code recorded the history:

- `2026-09-23-develop-1a9fb535`: `develop` at 1a9fb535, before the patches
  above existed.
- `2026-09-23`: the code with those patches.

### When you change workflow code

1. Make sure the histories on disk come from the code you are about to change.
   If you add a scenario for the path you are changing, record it **before**
   the change, with the current code:

   ```bash
   docker compose exec -T web env RECORD_TEMPORAL_HISTORIES=$(date +%F)-before-<change> \
     TEMPORAL_HISTORY_SCENARIOS=workflow_execution_workflow/<scenario> \
     bin/rails test test/temporal/workflows/history_replay_test.rb
   ```

2. Make the change, behind `patched` where the list above says so.
3. Run the replay test. If it fails, the change is not replay-safe.
4. Record histories for the new code under a new label:
   `RECORD_TEMPORAL_HISTORIES=$(date +%F)`. Leave `TEMPORAL_HISTORY_SCENARIOS`
   unset to record every scenario. Recording never overwrites a history with a
   different label.
5. Commit the new histories and keep the old ones.

Delete a history only when no execution shaped like it can still be open, which
is when you retire the patch it covers. A history for a workflow that did not
change is a duplicate of the one before it and does not need to be recorded again.

A history can stay after its scenario has been removed. It is a record of what
older code did, and the replay test still replays it.

## Workflow task failures are reported

An exception from workflow code that is not a Temporal failure (a `NoMethodError`,
or an illegal call that the SDK turns into `NondeterminismError`) fails the
workflow task. It does not fail the workflow. The SDK only logs it at WARN, so
`Interceptors::SentryInterceptor` reports it to Sentry, tagged
`temporal.failure=workflow_task` with the workflow type, id and run id. A task
that fails again on retry is reported at most once an hour per run and error.

The interceptor does not see a nondeterminism error detected by the SDK core
(commands that do not match the history). That error shows up only as a
`WorkflowTaskFailed` event in the Temporal UI. The replay test is what prevents it.
