# Runtime and Runner Adapter Layers

How a session start travels from the phase activity down to the machine it runs on, what each layer decides, and what every runtime and runner type guarantees whichever one the session uses. A new runtime or runner type has to keep these guarantees.

This describes the code as it is. The Coder runner type is designed (`docs/design/agent-runtimes/runner-coder.md`) and its core is built: the allocator, the provisioned arm of the environment state machine and the adapter methods of the start path. The `CoderAdapter` itself is not, so what a `coder` environment does after a session is not described here. Class and method names are the reference; each statement can be checked in the file named next to it.

## The layers

```
ContainerWorkflowV2
  → AdmittedPhaseActivity            (app/temporal/activities/container/admitted_phase_activity.rb)
    → ContainerService               (app/services/container_service.rb)
      → the strategy                 (app/services/container_strategies/)
        → ContainerRuntime           (app/services/container_runtime/)
            DockerRuntime | KubernetesRuntime | RunnerRuntime
          → for a runner only:
            Runners::Allocator       (app/services/runners/allocator.rb)
              → Runners::Adapter     (app/services/runners/adapter.rb)
                  ManualAdapter      (Runners::Machines: its launch availability and messages)
                  a provisioned type's adapter, which advances through Runners::Provisioning
```

| Layer | Decides | Leaves to others |
|-------|---------|------------------|
| `ContainerWorkflowV2` | The phase order (`pull_image`, `create_container`, `start_container`, `exec`), that `cleanup` always runs after them, and how long to wait: 30 s between capacity retries (`CAPACITY_RETRY_INTERVAL`), 15 s between cleanup retries (`CLEANUP_RETRY_INTERVAL`). | What a phase does. |
| `AdmittedPhaseActivity` | Whether a phase may run at all (`SessionAdmissionService.permit!`, `SessionService.revalidate_admission!`), the session's move to `running` (`Sessions::Lifecycle.start`), the durable operation record before a runtime call (`begin_operation!`), the runtime's identity before the create, and what a failure means: `CapacityError` becomes `capacity_wait`, anything else is raised non-retryable. In `cleanup`, whether the reservation can be released. | Which runtime serves the session (`ContainerRuntime.for_session`), and everything a phase does inside the container. |
| `ContainerService` | Only the hook order of one phase: `before_X`, `X`, `after_X`. It merges each hook's returned hash into the phase state, removes `CREATE_ONLY_KEYS` (the environment with the session's secrets) from the result, and wraps any error in `PhaseError`. | Timeouts and signals (Temporal's), retries, and what the hooks do. |
| The strategy (`BaseStrategy` and subclasses) | What to run: the image, the container spec (name, labels, environment, command), and the order of runtime calls inside a phase. It reaches the runtime only through `runtime`, which is `ContainerRuntime.for_session`. | Where the container runs, and how a call is carried out. |
| `ContainerRuntime` (`BaseRuntime` interface) | How and where: create, start and wait for ready, `exec`, file I/O, status, callback addresses, and for a session its `session_identity`, `session_absent?`, `cleanup_ready?`, `cleanup_session` and `transient_error?`. | Whether to start, wait or give up (the activity), and what the container runs (the strategy). |
| `Runners::Allocator` | Which environment of the runner a session holds, for every type: taking a free one or making a new one (`acquire!`), the hold and its clearing (`free!`, `let_go!`), the lock order (the runner row `FOR UPDATE`, then the environment) and the `max_environments` count (`tearing_down` and `failed` rows count until `gone`). It hands the type's part to the adapter and calls it outside its runner lock: `release!`, `fail!`, and the sweep of stale sessions (`sweep_abandoned!`, run every minute by `RunnerAbandonedMachinesWorkflow`). Called by `RunnerRuntime`. | The runner's type: it does not look at it. It does not count a session's outcome, and keeps no failure count. |
| `Runners::Adapter` (`ManualAdapter`, and a provisioned type's) | What is specific to a type: `capabilities`, `check_health`, `observe`, and the methods of the start path: `launch_refusal`, `new_environment`, `wait_for_environment!`, `advance!`, `release!`, `fail!`, `end_registration!`, `cleanup_waits_for_unheard?`, `rebuild!`, `settle_abandoned!`. | The locks, the hold and the count (the allocator's). `RunnerRuntime` calls `cleanup_waits_for_unheard?`; the allocator calls the rest. The adapter is also used by the runner form and save (`Runners::Form`, `Runners::Save`), the resolver (`launch_refusal`), the health check (`Runners::HealthCheck`) and the dead-container scan (`ScanDeadContainersActivity`). |

On the admitted path the activity's `cleanup` does not call the strategy's `cleanup`. It calls the strategy's `before_cleanup` (output collection), then `runtime.cleanup_session`.

## Where differences between types live

A difference between types lives in the implementation of one layer, behind one method with one implementation per type. Callers call the method and do not check the type.

- **Runtime.** `ContainerRuntime.for_session(session)` is the one place that picks the runtime: `RunnerRuntime` when the session has a `runner_id`, otherwise `ContainerRuntime.build` (Docker or Kubernetes from `Settings.container_runtime`). Everything after it calls the `BaseRuntime` methods. The same methods give each runtime's own answer: `session_identity` (`terminal-<route token>` on Docker, `<namespace>/terminal-<route token>` on Kubernetes, `runner-session-<id>` on a runner), `session_absent?`, `cleanup_session`, `callback_url` (the `Settings` value on the hosted runtimes, the session's callback proxy on a runner), `transient_error?` (Kubernetes only; the default is false), `cleanup_ready?` (the default is true; `RunnerRuntime` waits while an earlier op is open on the machine).
- **Runner adapter.** `Runners::Adapter.for(runner)` picks the adapter from `REGISTRY` by `runner_type`; a type without one raises `UnavailableType`. The per-type methods are `capabilities`, `check_health`, `observe` and the start path's, each with one implementation per type and none with a default that hides a type (only `wait_for_environment!` has one: the generic wait). `ManualAdapter` answers each as `manual` behaves: `observe` is `:running` while the machine is heard and `:unknown` after, and never `:missing`; `new_environment` is `nil` (an operator installs the machines); `advance!` is `:ready`; `release!` is the scrub or the reset by the runner's policy; `fail!` takes the machine out of rotation; `end_registration!` makes it `gone`; `cleanup_waits_for_unheard?` is `true`; `rebuild!` raises `UnsupportedOperation`. `ScanDeadContainersActivity` calls `observe` for any runner type.
- **The environment's states.** `RunnerEnvironmentStateMachine` has two arms, chosen by `origin` and never mixed: a `manual` machine is `registered` (and `failed`, `gone`), and an environment the platform creates (`origin: allocated`) goes `provisioning`, `booting`, `idle`, then `tearing_down` and `gone`; `failed` leads to `tearing_down` there. `RunnerEnvironment#in_service?` (`registered` or `idle`) is the one definition of "can take a session", read by the `free` scope and the allocator.
- **Making an environment ready.** A provisioned type's adapter implements `advance!` with `Runners::Provisioning.advance!` and supplies `provision`, `prepare` and `inject_bootstrap`. One step per call, each idempotent, the clock of `Settings.runners.bootstrap_timeout` starting with the first `external_id`.
- **`exec` and `exec!`.** Each runtime implements both; callers pick between them by what they need to know, not by runtime (see guarantee 6).

## What every runtime and runner type guarantees

Each guarantee names the code that holds it and a test that covers it where one exists.

### 1. A start that cannot succeed fails through one path

A session whose container or machine cannot start fails the same way on every runtime:

1. The runtime raises from `create_container`, or from the wait for readiness (`wait_for_ready`, called in the `start_container` phase). A runner with no machine that can take a session raises `Runners::Machines::NoMachine`; an environment that could not be made ready raises `Runners::ProvisionError`, which `RunnerRuntime#create_container` turns into a `CreateRefusedError`; a refused or failed `container.start` raises `CreateRefusedError` or `RuntimeError`.
2. `ContainerService#run_phase` wraps it in `PhaseError`.
3. `AdmittedPhaseActivity#run` raises it with `TemporalExceptions.non_retryable`, so Temporal does not retry the activity. The failed operation record is set to `retryable` for an error that proves no request left the process (`NEVER_DISPATCHED`, `ProvisioningError`, `CreateRefusedError`) and to `uncertain` otherwise (`record_failed_operation`).
4. `ContainerWorkflow#run` catches the activity error, runs `cleanup` (`run_cleanup`) and then `on_failure`, and fails.

No runtime retries a failed start. The only retry is of a single transient API call inside that call: `KubernetesRuntime#create_or_verify` repeats a create up to `CREATE_ATTEMPTS` times when `transient_error?` says the error is transient. Docker and runner runtimes retry nothing inside a phase. A transient error during cleanup defers the cleanup (`cleanup_pending`), as below; it never retries a start.

Tests: `test/integration/runner_failed_machine_test.rb`, `test/integration/hosted_runtime_unchanged_test.rb`.

### 2. Only a lack of capacity waits

`ContainerRuntime::CapacityError` is the only error that does not fail the phase. `AdmittedPhaseActivity#run` answers it with `{ "capacity_wait" => true }`: the operation record becomes `retryable`, the admission gets `wait_reason` (the error's `reason`) and `last_error`, and the admission is not released, so the reservation stays. `ContainerWorkflowV2#run_phase` sleeps `CAPACITY_RETRY_INTERVAL` and runs the same phase again. A phase that succeeds clears `wait_reason`.

The sources today:

- `Runners::Allocator.acquire!` when every machine that can take a session is busy, or the runner is at its `max_environments` (`runner_capacity`), or the type's adapter has nothing to give (`ExhaustedError` of an integration, mapped to the same reason); when the runner's machines are all offline for a session that was already waiting and `ContactLoss::GRACE` has not passed (`ManualAdapter#wait_for_environment!`); and while the platform makes the session's environment (`Runners::Allocator::Pending`, `runner_provisioning`). The reservation is kept in each case.
- `KubernetesRuntime#create_container` for an exceeded namespace quota (`namespace_quota`), and `wait_for_pod_ready` for an unschedulable pod (`cluster_capacity`, raised in the wait of `start_container`).

`DockerRuntime` never raises it. The accepted reasons are `SessionAdmission::WAIT_REASONS`. A runner with no machine registered, every machine failed, or every machine offline for a session that was not waiting does not wait: the allocator raises `NoMachine`, and guarantee 1 applies. An environment that fails while it is made is not a wait either: guarantee 1.

### 3. The runtime's identity is persisted before the create

In the `create_container` phase, before `ContainerService` runs, `AdmittedPhaseActivity` writes `runtime_id` (`runtime.session_identity(session)`) and `runtime_kind` (the runtime's class name) on the admission. This is done for every runtime. Cleanup therefore finds what was created even when the answer to the create never arrived, and a failure or stop during the create still reaches `cleanup_session`. The container name the strategy chooses (`terminal-<route token>`) is the same identity on Docker; `RunnerRuntime` replaces its `runner-session-<id>` identity with the container's name once `container.start` answers, and checks that the answer names the session's own container.

Cleanup refuses to run on a different runtime than the one that created: it raises when `runtime_kind` differs from the class of `ContainerRuntime.for_session(session)`.

### 4. Cleanup always runs, and the slot is released only on proven absence

`ContainerWorkflow#run` runs `cleanup` after the phases whether they failed or not, and `run_cleanup_detached` runs it when the workflow is cancelled. `AdmittedPhaseActivity#cleanup`:

1. Marks the admission `stop_requested_at`, so later phases find a closed permit.
2. If the runtime is not ready (`cleanup_ready?` false), skips the runtime calls; otherwise collects outputs (`strategy.before_cleanup`) and calls `runtime.cleanup_session(runtime_id, failed:)`.
3. Ends the session with `Sessions::Lifecycle.finalize`.
4. Returns `cleanup_pending: true` while `runtime.session_absent?` is false. A deletion that is accepted is not proof of absence, so the workflow retries (`CLEANUP_RETRY_ATTEMPTS`, then leaves the rest to `SessionAdmissionReconciler`).
5. Releases the reservation (`SessionAdmissionService.release!`) only after absence is proven. An unresolved create or start operation holds the release until absence has held for `SessionAdmissionPolicy.pinned_release_window`.

A transient error from the runtime's API during cleanup (`runtime.transient_error?`) returns `cleanup_pending` instead of failing; any other error is raised.

### 5. A session's state is written only through `Sessions::Lifecycle`

Runtimes, `Allocator`, adapters and the activity do not change `TerminalSession#state`. The activity calls `Sessions::Lifecycle.start`, `finalize` and `slot_released`; `Runners::ContactLoss` calls `Sessions::Lifecycle.fail_if`. `AASM`'s `no_direct_assignment` makes a direct write raise, and `test/services/sessions/lifecycle_ownership_test.rb` fails on a state event fired elsewhere. What runtimes do write on the session is not its state: `Allocator.acquire!` sets `runner_environment_id`, and `ContactLoss` sets and clears a metadata mark (`mark_contact_lost!`).

### 6. An unreachable container is told apart from a failed command

`exec` reports a command's exit code. `exec!` raises `ContainerRuntime::ContainerUnreachableError` when the container cannot be reached: a missing container on Docker, an unreachable pod on Kubernetes, and on a runner an answer of `no_session_container` or `session_mismatch` (`RunnerRuntime::GONE`) or an expired op. `exec` on a runner answers `[[], [message], 1]` in those cases, as the hosted runtimes answer an exit code. Callers that must tell the two apart, such as `Sessions::LiveLogReader`, call `exec!`. `container_status` answers `:missing` for a container that is not there on every runtime.

Test: `test/services/container_runtime/runner_runtime_contract_test.rb`.

### 7. Contact loss with a runner's machine fails the session and keeps the slot

This holds for runner sessions, for any runner type. `ScanDeadContainersActivity` asks the runner's adapter (`Adapter#observe`) about the session's machine without sending an op. For `:unknown`, `Runners::ContactLoss.fail_if_lapsed!` fails the session through `Sessions::Lifecycle.fail_if` once the machine has been silent for `ContactLoss::GRACE` (15 minutes), unless the session already ended. A session that was not failed has the mark removed.

The failed session keeps its machine, and so its admission slot. `RunnerRuntime#cleanup_ready?` stays false while the session is contact-lost and its machine is not heard, so the cleanup waits (`cleanup_pending`) until the machine is heard again, then stops the container, resets the machine and releases the slot. The type decides whether the cleanup waits for a machine that is not heard (`Adapter#cleanup_waits_for_unheard?`: `true` for `manual`, where the operator's machine comes back with its containers). When the runner is revoked or deleted, `Allocator.let_go!` frees the machine at once, since it will never be heard again.

### 8. One session per machine, and an op reaches the machine only while the session holds it

`Allocator.acquire!` sets `runner_environments.current_session_id` under the machine's row lock, with a unique index, so two sessions never hold one machine; two attempts of one session get the same machine. `Runners::Operations.enqueue!` checks the hold under the same lock, so a session that has released its machine (or never had one) gets `no_session_container` from every `RunnerRuntime` call, and nothing is sent to the next session's machine.

### 9. The machine is freed only after a successful scrub or reset

`RunnerRuntime#cleanup_session` stops the container (skipped for an environment that is not heard when its type does not wait for it), then calls `Allocator.release!`, which hands the environment to its adapter. `ManualAdapter#release!` runs `env.scrub` (runner policy `reuse`) or `env.reset` (policy `reset`, or any session that failed). A failed scrub is followed by a reset. `Allocator.free!` runs only after one of them succeeded. A reset that fails, or that a machine heard throughout its deadline did not answer, takes the machine out of rotation (`ManualAdapter#fail!`); a session's outcome does not. A stale session (its workflow ended without cleanup) leaves the machine held: `CleanupStaleActivity` only fails the session, and a sweep every minute (`Allocator.sweep_abandoned!`, which asks the machine's adapter, `ManualAdapter#settle_abandoned!`) finds the machines held by a session that has ended and whose admission is released or absent. It sends them the `env.reset` as that session, frees the machine when it succeeds and fails it if it fails or expires. The sweep never waits for an op. A machine whose session's cleanup is alive (contact loss) is not touched. A reset nobody answered for a contact-lost session whose machine is not heard leaves the session holding the machine, as guarantee 7 says.

### 10. The create environment does not outlive the create

`ContainerService::CREATE_ONLY_KEYS` (environment variables, command, host config, labels and the rest of the spec) are removed from the phase state after each phase, so the secrets in the environment are not stored in the admission's `phase_state` or in Temporal's history. This holds for every runtime because it is done above them.

### 11. An environment fails only for its own failure, never for a session's outcome

`Allocator.fail!` is called for a failed reset (`ManualAdapter#release!`, `ManualAdapter#settle_abandoned!`), a check-in that reports missing prerequisites (`CheckIn.fail_for_preflight!`), a refresh token presented twice (`Credentials.rotate!`) and an environment that did not become ready (`Runners::Provisioning`: a refused build, a failed install, a timeout). No count of failed sessions, and no stale session, fails an environment: `Allocator.free!` frees a `manual` machine once its reset or scrub succeeded, whatever the session's outcome, and a session's outcome is only which cleanup level the machine gets. A `failed` `manual` machine stays so until it is revoked, and its credentials are refused like a `gone` machine's; a failed provisioned environment is torn down and replaced. There is no Return to service. The credentials of an environment that is `failed`, `tearing_down` or `gone` are refused (`RunnerEnvironment#out_of_service?`).

### 12. A runner's Revoke ends every environment through its adapter

`Registration.revoke!` (one environment), `Registration.unregister!` (the machine's own `unregister`) and `Revocation.end_sessions!` (every environment of a runner that is revoked or deleted) all call `Adapter#end_registration!`. A `manual` machine becomes `gone`; a provisioned environment is torn down and is `gone` when its machine is deleted. They take the runner lock with `Credentials.lock_runner!`, which accepts a retired runner, so a runner's own Revoke ends its machines without a `runner_revoked` refusal. The order of locks stays runner, environment, credentials.

## Adding a runtime or a runner type

- A new runtime implements `BaseRuntime`, including `session_identity`, `session_absent?` and `cleanup_session`, and is chosen only in `ContainerRuntime.for_session`. It raises from the create or the wait on failure, raises `CapacityError` only for a lack of capacity, and does not retry a start.
- A new runner type adds an `Adapter` subclass and its entry in `Adapter::REGISTRY`, implementing `capabilities`, `check_health`, `observe` and every method of the start path, each as the type behaves (a type that cannot do something answers so, as `ManualAdapter#new_environment` answers `nil`; only an action with no meaning for the type, such as Rebuild on `manual`, raises `UnsupportedOperation`). A type whose environments the platform makes implements `advance!` with `Runners::Provisioning.advance!`, and its `release!`, `fail!` and `end_registration!` fire the state machine's `begin_teardown` through `Allocator.transition!`, so the lock and the hold are the allocator's. `RunnerRuntime`, `Allocator`, `ContactLoss` and the scan stay as they are and must keep guarantees 1, 2 and 7 to 9, 11 and 12 for it.
- No caller checks the type: not `Allocator`, not `RunnerRuntime`. A check of `runner_type` outside the adapter is not a pattern to copy (`Credentials.mint_registration!` is the one place that knows which runners bind a token to an environment).
