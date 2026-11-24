# Session admission rollout

Admission is always on and cannot be paused (#325, 2026-09-25). Every installation, new or existing, sends every agent session through the queue: the migration `AlwaysEnableSessionAdmission` switched it on wherever it was still off. There is no Enable button, no pause, no cutover and no drain to run, and no command to run after a deploy. The product-side description of the same model is [user-guide/session-queues.md](../../user-guide/session-queues.md).

What follows is what an operator configures, reads and, rarely, repairs.

## Capacity

Capacity belongs to the company (#297). A company's limit is a `SessionConcurrencyLimit` row with scope `Company`, held in the database. Its company admins set it on **Settings → General**, unless the company is on the free trial or managed by Aixle; a platform admin sets it on the company's page in the admin. A company with no limit is unbounded and unbilled. Where the deployment bills capacity, a company admin cannot clear the limit. The drain applies the company's effective capacity (`Billing::EffectiveCapacity`), which a free allowance can hold below the configured number.

Every session that has a project queues in that project's pool. A project's own limit is a **reservation** drawn from its company's limit: that project can always reach its number, and the company's projects without one share what the reservations leave. A company admin sets it in the project's settings; a platform admin can edit any limit row, of either scope, under **Session concurrency limits** in the admin. A project without a limit of its own is sized by `SESSION_PROJECT_CONCURRENCY_DEFAULT` and reserves nothing.

A project reservation larger than what the company's other reservations leave of its limit is refused. Lowering a company below what its projects reserve is allowed, so that a downgrade is never blocked by how the capacity was divided: the company limit is then honoured and the reservations are not, which `QueueHealthCheck` reports as over-commitment and the admin's **Session admission** page shows.

Every change to a limit, from any of these places, bumps the policy revision and drains the queue at once. Lowering a limit never stops a running session; it blocks further grants until usage falls below it.

`SESSION_CONCURRENCY_LIMIT` is read by nothing. It was a deployment-wide ceiling every project reservation was drawn from, and it could not describe an installation running several organisations; it can be removed from a ConfigMap.

## Deployment settings

| Variable | Default | Effect |
| --- | --- | --- |
| `SESSION_PROJECT_CONCURRENCY_DEFAULT` | `4` | The size of a project that has set no limit of its own. Read live: an edit takes effect as each pod boots, with nothing to run afterwards. A value that is not a positive integer is logged and ignored in favour of 4, rather than raised, so a typo cannot wedge every queue. |
| `SESSION_PINNED_RELEASE_ENABLED` | `true` | `false` stops the reconciler from releasing a pinned reservation on its own (see Recovery). |
| `SESSION_PINNED_RELEASE_CONFIRMATION_MINUTES` | `5` | How long the reconciler must keep proving that no workload exists before it releases a pinned reservation. A pass that sees the workload again resets the clock. |

Reading live has one cost: during a rolling update, replicas briefly disagree about a queue's size, bounded by the size of the edit and settled once the rollout finishes.

## Which queue a session joins

**A session belongs to exactly one queue, and the project wins.** A session that has a project draws on that project's pool, whoever launched it. So ten people working in one project share the project's cap, and one person working across three projects can hold three times a project cap. This is AD-1: a session that consumed two slots could not be ordered in one FIFO queue.

A session without a project is, in practice, an agent login (`auth_setup`). It queues in a pool of its own user's, `user:<id>`, two at a time (`SessionAdmissionService::AUTH_POOL_LIMIT`), so two logins start at once while a runaway loop cannot fill the cluster. That pool draws on no company's limit.

Standalone tool executions do not consume slots.

## Health and alerting

The admin's **Session admission** page shows the queues, the company limits, the project reservations, any over-committed company and the current health counters. Nothing on it changes the queue.

Every reconciliation pass (every minute, a Temporal schedule) logs one structured line, `[SessionAdmission] queue health {...}`, carrying `queued`, `occupied`, `pools_with_queue`, `oldest_queue_wait_seconds`, `operations_in_flight`, `uncertain_operations`, `pinned_reservations`, `pinned_confirming` and `cleanup_lag_seconds`. A growing `oldest_queue_wait_seconds` with idle capacity means delivery is stuck, and a growing `cleanup_lag_seconds` means deletions are accepted but not completing. `operations_in_flight` rises with ordinary load: every session being provisioned has one. `uncertain_operations` is the wider count of operations whose outcome is unknown; only an unresolved create or start holds a slot, and those are `pinned_reservations`. `pinned_confirming` is the part of them whose absence the reconciler is already timing, on its way to release.

`QueueHealthCheck` runs every minute in the Solid Queue supervisor (the `jobs` deployment), not in Temporal, so it keeps watching when the worker is down. It logs `[QueueHealth] {...}` and sends a Sentry event only when something is wrong: runs that never reached Temporal or were never started, an over-committed company, pinned reservations while automatic release is off, or reservations pinned for more than twice the confirmation window. A pool that has granted nothing for 30 minutes while a session waits and it has room is a warning.

## Recovery

Lost Temporal start responses are retried with the same `agent-session-<id>` identity and reject-duplicate reuse policy. The reconciler retries confirmed cleanup for closed workflows; an API timeout or deletion acceptance is never proof that resources are gone.

Every create, start and exec phase writes a runtime operation before its request goes out. A phase that fails with an error proving nothing was dispatched (an ActiveRecord error, `NoMethodError`, `NameError`, `ArgumentError`, `TypeError`, `KeyError`, `Runners::Machines::NoMachine`) is recorded as `retryable`, as is a refusal the runtime answered; any other failure is `uncertain`. While the container workflow is alive, an unresolved create or start is simply repeated, because both are idempotent (`SessionRuntimeOperation#replayable?`). An unresolved `exec` is never repeated, since that would launch the agent twice, but it holds no slot. Once the container workflow is closed, the reconciler relabels any `in_flight` operation as `uncertain`, since nothing can report its result any more.

An unresolved create or start of a closed workflow **pins** the reservation, so that a late Pod can never land in a slot handed to someone else (AD-5). The runtime is still deleted, because deleting it is what makes absence provable. The reconciler then re-proves absence on every pass, and once it has held for `SESSION_PINNED_RELEASE_CONFIRMATION_MINUTES` without a break it marks the operations `abandoned` (never `completed`: their outcome stayed unknown), records the window in their error, and releases the slot (#286). A pin needs no operator.

With `SESSION_PINNED_RELEASE_ENABLED=false`, a pinned slot waits for an operator. Recovery then requires fencing the old worker/activity process and its outstanding runtime requests, confirming the Temporal execution is closed, and auditing the recorded runtime identity. Never clear an operation merely because it is old or the Pod is momentarily absent. After the old publisher is proven unable to act, an operator may mark that operation `abandoned` in a Rails console, with the evidence in its error field, request cancellation of the session, and let reconciliation delete and verify the runtime. Do not clear the reservation directly. If fencing cannot be proved, keep the slot and investigate.

Admission decisions — grant, cancel, release, policy and limit changes — serialize on one PostgreSQL policy row. Record saves, runtime work and Temporal RPCs are outside that lock, and the per-phase runtime-operation ledger locks its own admission row rather than the policy, so a busy installation does not funnel every container phase through one row.

Runtime deletion is asynchronous, so cleanup is a wait, not a failure: the container workflow re-confirms absence on a timer for about five minutes, and hands anything still pending to the minutely reconciler. A session that finished settles its own terminal state immediately; only the reservation waits for confirmed absence. A parent workflow whose step has not returned its capacity reads that step as `finishing`.

Waiting is exempt from the reapers, but nothing else is. A reservation whose `wait_reason` is `concurrency_limit`, `namespace_quota`, `cluster_capacity` or `runner_capacity` is doing its job and is left alone; an admitted session that simply stopped making progress is reaped on the normal 30-minute schedule by cancelling its workflow, which is what lets confirmed cleanup return the slot. Parent runs carry a 40-day execution timeout (`TemporalWorkflowRegistry::RUN_TIMEOUT`) — far more than queue time needs, and still a ceiling.

The parent workflow reads durable child state instead of trusting container signals, which are demoted to wake-ups. Polling backs off from 30 seconds to 15 minutes while nothing changes and resets on any signal, so a step that waits days on a human does not spend the run's Temporal history budget. The workflow definitions from before admission remain registered for replay.
