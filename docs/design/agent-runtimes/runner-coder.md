# Coder runners: one more consumer of the Coder integration

**Status:** proposed (task #284, "Runners 17a"). Written against `origin/develop` after the interactive runner sessions of #277 (16g), the session lifecycle service of #273, #283 (`Sessions::Lifecycle.fail_if` and `finalize` are still there), the Add machine work of #286 and #288 (`machine-install.sh`, `--mode machine`) and the design of #295 (integrations chosen per session, [`../session-integrations.md`](../session-integrations.md)).
**Parent:** [`DESIGN.md`](DESIGN.md) §15 row 17. It refines DESIGN.md §2.2, §2.3, §2.5, §2.6, §2.7, §5, §7, §8, §9.2, §10 and §11 for the `coder` type, and replaces row 17 with rows 17b to 17e (§14 below), as `runner-relay.md` did for row 16.
**Scope:** design only. This pull request changes this document, `DESIGN.md` and `docs/index.md`. Rows 17c and 17d also update [`docs/architecture/runtime-layers.md`](../../architecture/runtime-layers.md), which describes the start path as built (§14).

_A section number with `DESIGN.md` in front of it is the parent document's; a bare one is this document's._

**What the design relies on from the integration** (code reading, and #295 as designed):

- A Coder integration is created per project only (`create_coder` always passes the current project). Creating a company-wide one from the UI is deferred by #295, so a `coder` runner is in practice a project runner, and the form offers the type when the scope has an eligible integration.
- Today a project cannot have a second active Coder integration (`Coder::IntegrationService#ensure_only_active!`). #295 removes that rule: several Coder integrations per scope, each with a required default template and machine prefix, and the tools take the integration's id. Its implementation is task #298. A runner already names its integration (`Runner#integration`), so this design does not wait for it. 17b and 17c do not depend on #298; **17d and 17e are cut after it** (§14).
- Until #298, a Coder runner and the agents' `coder_*` tools of one project share one integration, its pool and its quota. After it, a customer keeps them apart with two integrations, and attaches only one of them to workflows.

## 1. Overview

A `coder` runner creates Coder workspaces for its sessions itself, through a Coder integration. Each workspace is a virtual machine that runs `aixle-runner --mode machine` as a system service and takes one session, in container mode, as a `manual` machine does. What is new is everything before the session: the platform allocates, builds, boots and installs the machine, and deletes it after the session.

**`coder` ships with `fresh` only.** Each session gets an environment of its own. It is torn down when the session ends, is cancelled or fails. `reuse` and `reset` on `coder` are a later row of the plan, after row 18 (§17).

Setting up a `coder` runner means picking the Coder integration to take machines from. That is all it names about Coder: the template that workspaces are created from is the integration's default template. A runner's integration never changes after the runner is created (§7.1).

Today the type cannot be created. `Runners::Adapter::REGISTRY` holds `manual` only, and `Runners::Save` and the controllers refuse `coder` as "not available yet" (the registry raises `UnavailableType`). The pieces item 17 needs and the code lacks:

| Piece | In the code today | Target |
| --- | --- | --- |
| Coder services for a second consumer | `Coder::Allocator`, `LockService`, `WorkspaceService` serve a terminal session only, and block up to 240 s per call | §4 (17b) |
| Runner allocator | `Runners::Machines.acquire!` takes a free registered machine (DESIGN.md §7.3 as 8a built it). No step 4 | `Runners::Allocator` (§5) |
| Provisioned states | `RunnerEnvironmentStateMachine` has `registered`, `failed`, `gone`, and `resetting`, which only Return to service uses and #302 removes. The reset after a session runs while the machine is still `registered` and held | The provisioned arm (§6) |
| Delivery of `aixle-runner` | `register` creates an environment for a `manual` machine | `register` fills the environment the allocator created (§8) |
| `CoderAdapter` | None | §7 |
| `reuse_policy` | `reuse` and `reset` on `manual`, in `RunnerRuntime#cleanup_session` | `fresh` only on `coder`: a workspace per session, deleted after it (§9). No `on_release` |
| What differs between types on the start path | `RunnerRuntime` and `Machines` never call the adapter | Adapter methods with one implementation per type, called by `Runners::Allocator` and `RunnerRuntime`, which check no type (§7.4). Ending an environment's registration is one of them (§6.1) |
| Integration state | Not read by any runner | An `inactive` or `error` integration makes its runners `unreachable`, with the integration named (§7.3). Nothing about templates |
| VM-only rule | A sentence in DESIGN.md §2.6 | A command the platform runs on the workspace before installing (§8.2) |
| Form and page | `manual` only | §12 |

## 2. What exists, and what a second consumer needs

The hosted pool is a set of workspaces that the platform leases to terminal sessions and drives over `coder ssh`. The Coder integration's services do that work today:

| Service (`app/services/coder/`) | What it does today | What a runner needs from it |
| --- | --- | --- |
| `Allocator` | Lists the token owner's workspaces under `machine_prefix`, locks a free one for a **terminal session**, probes it over SSH (a sick one is quarantined and passed over), and otherwise creates one from `default_template`. `ensure_started` and `create_new_workspace` call `await_build`, which sleeps up to 240 s in one call. It raises `ExhaustedError` when it has nothing to give | A holder that is a runner environment. A variant that does not block an activity for the build, and that gives the workspace only when it is ready: running, agent connected, probe passed. The workspace status classification (it is private to the allocator and the reaper). A delete through the integration |
| `LockService` | A row in `integration_data` per workspace, keyed by `terminal_session_id`, expiring after the integration's `lock_ttl_minutes` (default 120) of inactivity, pushed forward by every Coder tool call (`touch`). `expires_at` is already nullable in the table and the queries | A holder that is not a session, and a hold with no expiry |
| `WorkspaceService` | `list`, `find_by_name`, `find_template`, `create_workspace`, `start`, `stop`, `delete`, `await_build`, error mapping with the token redacted | A status that does not block |
| `SshRunner#exec` | Runs a command over `coder ssh`, with `stdin_data:` | Nothing. It is used as it is |
| `HealthCheck` | `probe` over SSH: reachable, or sick with a reason | Used inside `allocate` only |
| `QuarantineService`, `DeadWorkspaceReaper` | Quarantine marks a sick pool box so the allocator passes over it. The reaper deletes pool workspaces under the prefix whose agents are gone, with no live lock, twice sighted | Nothing. Quarantine is internal to the probe inside `allocate`. A held workspace is never reaped, and a hold with no expiry is always live (§4.5) |
| `TokenService`, `IntegrationService` | URL, token, redaction, and `test` (a rejected token marks the integration `error`) | `check_health` calls `IntegrationService#test` |
| `RepoBootstrap` | Clones repositories onto a leased workspace | Not used. `SessionContextService` clones inside the session container, as on every runner |

**What moves into `app/services/coder/`.** Three things the runner needs are done today by the session path in its own code. They move so that both consumers use one copy:

1. The classification of a workspace's last build (a succeeded `start` is running, a `start` in flight is starting, anything else needs a start). It is in `Allocator#ensure_started` and again, differently, in `DeadWorkspaceReaper`. It becomes `Coder::WorkspaceStatus.from(workspace_hash)` with `state` (`building`, `running`, `stopped`, `deleting`, `deleted`, `failed`) and `agent` (`connected`, `disconnected`, `none`). `HealthCheck.agents_unhealthy?` and `unhealthy_reason` stay where they are and `WorkspaceStatus` calls them.
2. The explanation of a refused request (`with_coder_explanation` in `WorkspaceService`) is reused as it is, and gains one more distinction: a refusal for quota raises `WorkspaceService::QuotaError < OperationError`. Its status and body shape are unverified, so 17b records them on staging (§15). An unrecognised refusal stays an `OperationError`.
3. The lock's ownership predicate (`value ->> 'terminal_session_id' = ?`), repeated in five methods of `LockService`, becomes one `Holder` (§4.1).

## 3. Approach

**Chosen.** The runner is a consumer of the integration's services. It asks the integration for a machine (`allocate`), runs commands on it (`SshRunner`), and asks the integration to delete it. It never calls Coder directly and never decides which workspace it gets. The state of an environment stays in `runner_environments` and advances one idempotent step per call, from the place that already retries: the `create_container` phase of `ContainerWorkflowV2`, through `capacity_wait`. A minutely reconciler drives teardowns and covers a session that no longer retries. No step holds a long wait.

| Alternative | Rejected because |
| --- | --- |
| The runner calls Coder directly through `Coder::Api` and keeps its own hold | A second copy of the lock, the exclusion rule and the template choice. Alex's direction asks for the services |
| A create-only `provision` that never takes a free workspace, or a dedicated runner integration with create-only workspaces | Alex decided the runner takes machines through `allocate`, and that the integration decides what it gives (D18, D29, D30, D35) |
| Provision, build and install inside one long heartbeating activity | A cold build plus an image pull outlasts the phase's 300 s `start_to_close_timeout`, and a long activity holds a slot and gives coarse progress. `capacity_wait` is the platform's wait already (D3) |
| A Temporal workflow per environment | A second orchestration layer for state that is a row and a few API calls |
| A hold with an expiry that a reconciler renews | Alex decided on an explicit hold with no expiry. It removes the renewal and the outage window |
| `manual` stays on `Runners::Machines`, with a second owner for provisioned environments | Two lifecycle owners behind one contract. One `Runners::Allocator` for every type (D36) |
| `busy` as a state (DESIGN.md §5.2 as drawn) | `manual` derives it from the hold (`RunnerEnvironment#busy?`), and the patterns document names that predicate. A second source of truth would drift |

## 4. Changes to the Coder services

All of this is 17b. It is a task of its own because it changes what the agents' `coder_*` tools use in production, so its staging check includes an agent session that uses `coder_*` as before (§14).

### 4.1 Who holds a lock

`Coder::LockService::Holder = Data.define(:kind, :id)`, with `Holder.session(id)` and `Holder.environment(id)`. The row's `value` keeps `terminal_session_id` for a session holder, so every row written before this change stays valid, and gains `runner_environment_id` for an environment holder. `acquire`, `touch`, `release_owned`, `held_by_session?` and `release_for_session` take `holder:` where they take `terminal_session_id:` now, and one private method builds the `value ->> '<key>' = ?` predicate. The Coder tools and `Coder::Allocator` pass `Holder.session(session.id)`. `release_all_for_session` and its `IntegrationCleanupService` hook stay, and release session holders only, so ending a terminal session never releases a runner's workspace. A new `held_by(holder:)` returns the workspace a holder holds, which makes `allocate` idempotent for it (§4.3).

`Coder::Allocator.new(integration:, terminal_session:, …)` takes `holder:` in place of `terminal_session:`. The hosted behaviour and its tests do not change.

### 4.2 An explicit hold

A hold of an environment holder is **explicit**. `LockService` derives it from `Holder#kind`: `acquire` writes an environment holder's row with `expires_at` NULL, and a session holder's row with its expiry as today. There is no `explicit:` parameter, so a caller cannot get the wrong one. The hold has no expiry and no renewal. The existing expiry check (`expires_at IS NOT NULL AND expires_at <= now`) never reclaims it, `touch` is not called for it, and `live_locks` counts it. It ends in two ways only:

- the runner deletes the workspace (§9), and the integration releases the hold when Coder reports the workspace `deleted`;
- the reconciler's sweep of an environment that is `gone` (§11) calls `delete(holder:)` first and releases the hold only when it returns `:gone` (§4.5). It never releases the lock directly: a workspace locked after the environment's teardown returned `:gone` (a late `allocate`, §5.2) is deleted by the sweep, not returned to the pool. This also covers a delete that finished while the platform was not looking.

### 4.3 Allocating without blocking, and handing over a ready machine

`Coder::Allocator#allocate(holder:, wait: true, note: nil, …)`. With `wait: true` it is today's method. With `wait: false` it does the same work and **never sleeps in `await_build`**. It returns a `Coder::Allocator::Result`: `status: :ready` with the workspace, or `status: :pending` with the workspace it holds and a message ("Building workspace X", "Starting workspace X", "Waiting for the agent of X"). The workspace is handed over only when it is ready, as the integration defines it: **the build succeeded, the agent is connected, and the integration's own SSH probe passed.** This holds for a new workspace, a stopped one and one that already runs.

- It first returns the workspace `held_by(holder)` already holds, if any, and continues from where that one stands. A retried step, or one that crashed between the allocation and the write of `external_id`, gets the same workspace, and every retry is the poll: a build in flight returns `:pending`, a finished one is probed once the agent is connected.
- Otherwise it takes a free workspace of the pool, or creates one from the integration's default template, as it does for a session. The integration decides, by its own logic, and the runner has no say in it. The candidate is locked for the holder at once, so nothing else takes it while it builds.
- A stopped workspace is started with `WorkspaceService#ensure_started_async` (a `start` build, no wait). The blocking `ensure_started` is rebuilt on it plus `await_build`.
- The probe (`Coder::HealthCheck#probe` over `SshRunner`) runs once the build has succeeded and the agent is connected. **What the integration does with a workspace that fails its probe is the integration's own logic**: the runner does not know and does not ask. It may therefore see a different `workspace.name` in a later `Result` for the same holder, and the adapter writes whatever `external_id` the result carries. A failed build it cannot recover from raises `WorkspaceService::OperationError` with Coder's message, which the adapter turns into a `ProvisionError`.
- When it has nothing to give (`ExhaustedError`, a quota refusal) it raises `Coder::Allocator::ExhaustedError` with the integration's message. §5.1 turns that into `capacity_wait`. With a required template and prefix (#295) the integration can always create a workspace, so `ExhaustedError` means quota or a provider limit.

Polling the build and the agent belongs to the integration. The runner's own checks (VM, root or sudo, systemd, §8.2) and the install stay in the adapter and run on a workspace that `allocate` has handed over. `allocate` has **no create-only mode**.

`Coder::WorkspaceService` gains `status(name)` → `WorkspaceStatus` (one `GET`) and `ensure_started_async(workspace)`. `status` is used inside `allocate` and `delete`.

### 4.4 The pool exclusion rule is dropped

An earlier design hid runner workspaces from the hosted pool by matching names against `runner_environments`. With the lock, it is not needed:

- `Coder::Allocator#allocate` locks each candidate and passes over one that is held (`LockNotAcquired`).
- `DeadWorkspaceReaper` deletes only a workspace with **no live lock**, and an explicit hold is always live.
- The lock is taken in the same call that chooses or creates the workspace (§4.3).

What remains is a window of a few milliseconds between the create and the lock, which `Allocator#create_and_lock` already has for the hosted pool.

### 4.5 Deleting a workspace through the integration

`Coder::Allocator#delete(holder:)` deletes the workspace `held_by(holder)` holds (a `delete` build through `WorkspaceService#delete`) and releases the hold when Coder reports it `deleted`. It returns `:pending` while the build runs and `:gone` when done. **It returns `:gone` when the holder holds no workspace**, and for a workspace Coder no longer knows. It is the only way the runner removes a machine (§9.3), and the runner calls it for every environment it tears down, whatever its state: a workspace locked in the crash window before `external_id` was written is found by its holder and deleted, never returned to the pool. A delete refused by Coder raises `WorkspaceService::OperationError`, and the runner retries it (§11).

### 4.6 The template, the pool's free workspaces, and what `fresh` means

**The template is the integration's.** The integration's `default_template` setting is the one every runner on it builds from, as the hosted pool grows from it. The runner has no template, version policy, version or parameters. A template that builds from required parameters it has no default for fails at the create with Coder's own message, which fails the environment: the integration's template is where that is fixed.

**A runner may get a free workspace of the pool.** This is accepted. The consequences, decided:

- `fresh` guarantees that a session sees **nothing of earlier runner sessions**, because the workspaces of earlier sessions are deleted after use. It does not guarantee that the workspace is one the runner has never used in any way: `allocate` may give a free workspace of the integration's pool that the runner never used.
- The runner deletes what it was given. A pool workspace that a runner took is deleted when the session ends, when its environment fails, or when it is revoked or the runner is deleted.
- `max_environments` counts the runner's environments, whatever the origin of their workspaces.
- **Where the pool is shared.** An integration that serves hosted sessions as well as runners shares its pool and quota with them. The user guide says so: **on an integration shared with hosted sessions, a `fresh` runner takes free workspaces of the pool and deletes them.** Keeping the runner's integration apart from the agents' is the customer's job, and after #298 it is a second integration.

## 5. `Runners::Allocator`

`app/services/runners/allocator.rb`. It owns the environment row and the hold, for every type. `Runners::Machines` keeps what is specific to `manual`: the launch availability and its messages. Return to service and the failure streak are removed by #302, so the allocator keeps no failure count.

```ruby
Runners::Allocator.acquire!(session)            # => RunnerEnvironment (held, ready), or raises
Runners::Allocator.release!(environment, session, failed:)
Runners::Allocator.let_go!(session)             # the runner is revoked: the hold goes, no outcome counted
Runners::Allocator.fail!(environment, reason, holder: nil)
```

`RunnerRuntime`, `Revocation`, `ContactLoss`, `CheckIn`, `CleanupStaleActivity` and `Credentials.rotate!` call these instead of the same methods on `Machines` (17c). The `manual` behaviour and its tests do not change.

**What is common, and what is the adapter's.** `Runners::Allocator` keeps what is common to every type: taking a free environment of the runner, setting and clearing the hold, the lock order and the `max_environments` count. What differs between types is a method of `Runners::Adapter` with one implementation per type (§7.4): making a new environment when none is free, bringing it to ready, release after a session, failure, ending its registration, and whether cleanup waits for an environment that is not heard. **`Runners::Allocator` and `RunnerRuntime` check no type, no capability and no policy.** `manual` answers each method as it behaves today, not with an error.

### 5.1 `acquire!`

Idempotent for a session: a session that holds an environment gets it back (a retried `create_container`), as `Machines.acquire!` does. Otherwise, in one transaction that first locks the runner row `FOR UPDATE` (the order is runner, then environment, as every issuer and the revoker use. Every runner type takes the runner row `FOR UPDATE`, `manual` included, so there is one lock mode and the count of step 2 is serial. The cost is that a `manual` runner's acquires queue for milliseconds; it is accepted and §14 names it):

1. **An idle, heard environment** of this runner, lowest id first, `FOR UPDATE SKIP LOCKED`. The hold (`current_session_id`) is set. On `coder`, which is `fresh` only, an environment never returns to `idle` unheld, so this step finds nothing there. (Affinity and project binding are out of the plan, DESIGN.md §7.3 steps 1 to 3.)
2. **When the adapter makes a new environment** (`adapter.new_environment(runner)` answers the row's attributes, not `nil`) **and `count(environments not gone) < max_environments`** (null means `max_concurrency`): insert the row the adapter described, held by the session. `CoderAdapter` describes a row in **`provisioning`**, `origin: allocated`, `key` a platform-made identifier unique in the runner (`coder-` and 8 hex); `boot_started_at` stays null (§5.2). `tearing_down` and `failed` rows count until they are `gone`, so a slow delete cannot let the pool grow past its limit. `max_environments` limits the runner's machines, not concurrency (D12).
3. Otherwise raise `ContainerRuntime::CapacityError` with `reason: "runner_capacity"` (§10). `ManualAdapter#new_environment` answers `nil`, so a `manual` runner goes from step 1 to step 3 and the offline rules of DESIGN.md §7.3, unchanged.

After the transaction commits, the environment is advanced once with `adapter.advance!(environment)` (§5.2; `ManualAdapter` answers `:ready` for a registered machine), and `acquire!` raises `Runners::Allocator::Pending`, a `CapacityError` subclass with `reason: "runner_provisioning"`, until the environment is `idle`. The activity treats it as any `CapacityError` (`AdmittedPhaseActivity`, `capacity_wait`): it keeps the reservation, records the wait reason and message on the admission, and the workflow tries again 30 s later (`CAPACITY_RETRY_INTERVAL`). No new workflow code.

**Nothing in the runner layer retries a failed start.** Only a capacity wait is retried (`CapacityError`, `Pending`). Any other error comes out of `RunnerRuntime#create_container` as a `ProvisionError` → `CreateRefusedError`, and `AdmittedPhaseActivity` fails the phase as non-retryable and runs the cleanup. That is what a hosted session does when its pod does not start, and what a `manual` session does when its machine refuses `container.start`. A session behaves the same wherever it starts.

`runner_provisioning` (D3) joins `SessionAdmission::WAIT_REASONS` and `LAUNCH_WAITS`, and `launchStatus.ts` shows "Starting a workspace" with the message beneath. It is not `runner_capacity`, because the session page would say "Waiting for a free machine" while the platform builds one for it.

### 5.2 `CoderAdapter#advance!` and `Runners::Provisioning.advance!`

`CoderAdapter#advance!(environment)` is `Runners::Provisioning.advance!(environment, adapter)`: one step per call, under the environment's row lock, decided by its state, calling the adapter's `provision`, `prepare` and `inject_bootstrap`. A test adapter reuses it (§14, 17c). Each step is idempotent, because Temporal retries the phase:

| State | Step |
| --- | --- |
| `provisioning` | If `boot_started_at` is set and `boot_started_at + Settings.runners.bootstrap_timeout` has passed, `mark_failed` with the message of §11 and raise `Runners::ProvisionError`. Otherwise, with no `external_id`: `adapter.provision(env)` (`allocate(holder:, wait: false)`), which writes `external_id` and, on its first write, sets `boot_started_at`; with one: `adapter.prepare(env)` (the same call again). `:pending` until the integration hands the machine over ready. On `:ready`: `adapter.inject_bootstrap(env)` (§8: the runner's checks, then the install), then `finish_build` (`booting`) if the row is still `provisioning` (`register` may have moved it, §8.4). `ExhaustedError` leaves the row `provisioning` with no workspace and no clock, and the retry asks again (§11) |
| `booting` | `register` and the first check-in move it (§8.4). If `boot_started_at + Settings.runners.bootstrap_timeout` has passed (it is always set here), `mark_failed` with the message of §11 and raise `Runners::ProvisionError` |
| any other | none |

The HTTP and SSH calls run outside the allocator's runner lock, and the result of each is saved under the row's own lock. **The step does not re-read the environment after each adapter call** to see whether a teardown began meanwhile: a workspace locked after the teardown returned `:gone` is deleted by the reconciler's sweep (§11), which is the guard. The one re-read is the register race of §8.4. A `ProvisionError` (the template refused, the build failed, the VM check failed, the install failed) fires `mark_failed` with the message and propagates; the environment is then torn down and its workspace deleted (§9.3). `RunnerRuntime#create_container` turns it into a `CreateRefusedError` (§5.1), so the phase fails with the diagnosis and the cleanup frees the hold (§10).

**Who advances.** Only the session's phase advances the environment it holds. With `fresh` only, an environment that no session holds is being torn down, never booted: a session that is cancelled or released ends in `begin_teardown` (§9.2). The reconciler (§11) therefore does not advance anything. It drives teardowns and covers a session that no longer retries (a timed-out environment).

`Settings.runners.bootstrap_timeout` is one setting, 900 s (D5). **Its clock starts when the integration hands over a workspace**: `boot_started_at` is written with the first write of `external_id` and not changed by a later one. It bounds the build and the boot. It does not bound the wait for the integration's capacity: until the integration gives a workspace, the session waits as on every runtime, in `capacity_wait` with `runner_capacity` and the integration's message, with no time limit, as a hosted session waits for cluster capacity (`ContainerWorkflowV2` retries with no limit) (D46).

## 6. The provisioned arm of the environment state machine

`RunnerEnvironmentStateMachine` gains the states and events below. It stays AASM with `whiny_persistence`, and nothing writes `state` past it (implementation-patterns, Anti-Patterns).

```
(row inserted, held)  provisioning ─finish_build─▶ booting ─check_in─▶ idle      (idle + a hold = busy)
 any state but gone ── mark_failed ──▶ failed ── begin_teardown ──▶ tearing_down ─finish_teardown─▶ gone
 provisioning | booting | idle ── begin_teardown ──▶ tearing_down
 unregister (manual: per-machine Revoke, aixle-runner unregister) ──▶ gone
```

- **An allocated row is created in `provisioning`**, held by its session, with `boot_started_at` null until the integration hands over a workspace (§5.2). There is no `requested` state. Teardown does not branch on whether a workspace exists: it always calls `Coder::Allocator#delete(holder:)`, which returns `:gone` when the holder holds none (§4.5).
- `idle` is free when no session holds it and busy when one does. `RunnerEnvironment` gets `in_service?` (`registered` or `idle`) and the `free` scope reads it, so `Allocator`, `Resolver`'s availability and the `manual` code share one definition of "can take a session".
- `registered`, `failed` and `gone` are the `manual` states. #302 removes `resetting`: the reset after a session runs while the machine is held. The two arms never mix: a `manual` environment is created `registered`, an allocated one `provisioning`, chosen by `origin`.
- `failed` on a provisioned environment is not a resting state. The reconciler (§11) tears it down (the workspace is deleted), and the allocator takes another machine on demand. This is the **rebuild** (D4): retire-and-replace, a new key and a new row. `Adapter#reset(level: :rebuild)` is not built. The `rebuildable` capability stays `true` for `coder`, and the runner page's Rebuild action calls `begin_teardown`.
- `check_in` is `booting → idle`, fired by the first check-in after `register` (§8.4). It is not fired by `register`, so an environment is never `idle` before its preflight is reported.
- There is no `restart` event and no revival: a workspace that stops under a session fails the session through the contact-loss grace (§11).
- `unreachable` stays an overlay (DESIGN.md §5.2): a silent `idle` or `busy` environment is shown offline and skipped by the allocator.

**Schema (17c).** `bin/rails generate migration` (never by hand): `runner_environments.external_id` (string, null; the Coder workspace's name, unique per runner where not null), `runner_environments.boot_started_at` (datetime, null; set with the first `external_id`), and `origin` accepts `allocated`. Each has its first reader in this task. `reusable` of §2.2 is not added. No backfill: nothing allocated exists.

### 6.1 Ending an environment's registration: one adapter method

Revoke of an allocated environment cannot be `unregister` then `gone`: that would leave the workspace running and its hold in place. The difference between types lives in **one adapter method with one implementation per type**, not in a type check in the callers (as D13 does for launch refusals): `Adapter#end_registration!(environment, ended_by:)`.

- `ManualAdapter` keeps today's behaviour: the body of `Registration.unregister!` (the credentials revoked, the hold released, the row `gone`, the relay signalled, a live session failed with the message that names the machine).
- `CoderAdapter` revokes the environment's credentials, signals the relay, fails a live session through `Sessions::Lifecycle.fail_if` with the same message, and fires `begin_teardown`. The environment is `gone` only when the workspace is deleted (§9.3).

Every path that ends an environment's registration calls it: `Registration.revoke!` (per-environment Revoke), `Registration.unregister!` (the machine's own `unregister`), and `Revocation.end_sessions!` for each environment of a runner that is revoked or deleted. 17c moves them. Tests cover per-environment Revoke and runner Revoke for both types. A runner's Revoke calls `end_registration!` for every environment of the runner, whatever its type: on `manual`, each machine becomes `gone` (D50, accepted).

**The teardown lock path.** `end_registration!` runs after the runner is retired, and `Credentials.lock_live_runner!` refuses a retired runner (`runner_revoked`). So `Credentials` gets a lock path for teardown, `lock_runner!(runner_id)`, that takes the same runner row lock and accepts a retired runner. `lock_live_runner!` is that call plus the live check, and stays for registration and token issuance. The order stays runner → environment → credentials. `Registration.unregister!`, `Registration.revoke!` and the credential revocation inside `end_registration!` use `lock_runner!`. The 17c runner-Revoke test checks that every `manual` environment reaches `gone` without a `runner_revoked` refusal.

## 7. `Runners::CoderAdapter`

`app/services/runners/coder_adapter.rb`, `Adapter` subclass. Stateless; every method is idempotent on the environment, and none calls Coder except through the integration's services (§4).

### 7.1 Config, the integration, and `reuse_policy`

`ConfigSchema` keys for `coder`: the `container.*` keys only. `on_release`, `template_id`, `template_version_policy`, `template_version_id`, the `parameters` key and the `if/then` rule of `for_type("coder")` are removed. The runner's `integration` (already validated by `Runner#integration_usable`, DESIGN.md §2.6) is how it names Coder.

- **`reuse_policy` is `fresh` on `coder`.** `Runner` validates it as it does for `kubernetes` (`inclusion: { in: %w[fresh] }`), `DEFAULT_REUSE_POLICY["coder"]` becomes `fresh`, and the form shows no choice.
- **The integration never changes.** It is chosen when the runner is created. `Runners::Form` permits `integration_id` only when creating, as it does `runner_type`, and the model refuses a change on update (`validate :integration_unchanged, on: :update`). To use another integration, create a new runner. The integration itself (its token and settings) stays editable. Changing a runner's integration may be added later (§17). So an environment and its explicit hold always belong to the integration the runner names.

### 7.2 The methods

| Method | Behaviour |
| --- | --- |
| `capabilities` | `provisionable: true`, `rebuildable: true` |
| `provision(env)` | `Coder::Allocator#allocate(holder: Holder.environment(env.id), wait: false)`. Writes the workspace's name (`result.workspace.name`) to `external_id`; the result may be `:pending`. `ExhaustedError` raises `ContainerRuntime::CapacityError` with the integration's message (`reason: "runner_capacity"`, §5.1); a refusal of Coder for the create (the template needs a parameter, a build error) raises `ProvisionError` with Coder's `message (detail)` text |
| `prepare(env)` | `allocate(holder:, wait: false)` again. `:pending` → `:pending`; `:ready` → `:ready`. The adapter does not poll the build or the agent and does not probe: the integration does. It updates `external_id` when the result names another workspace. An `OperationError` → `ProvisionError` with Coder's message |
| `inject_bootstrap(env)` | §8.2 and §8.3, on a workspace that `allocate` has handed over |
| `rebuild!(env)` | §7.4. It begins the teardown (a failed `coder` environment is torn down, D15). `reset(env, level:)` is not built on `coder` while it is `fresh` only |
| `new_environment`, `advance!`, `release!`, `fail!`, `cleanup_waits_for_unheard?` | §7.4 |
| `teardown(env)` | `Coder::Allocator#delete(holder:)` (§4.5, §9.3). `:pending` until the workspace is deleted, then `:gone` |
| `end_registration!(env, ended_by:)` | §6.1 |
| `observe(env)` | **As `ManualAdapter#observe`**: `:running` while the environment is heard (`Runners::Liveness`), `:unknown` otherwise. No Coder call. `ScanDeadContainersActivity` does not change (§11) |
| `check_health(runner)` | §7.3 |
| `launch_refusal(runner)` | §10 |

**When the runner's own part fails** (the checks, the install, the boot, the check-in, the workspace stopping past the grace, credential reuse; never a session's outcome, §11) the runner fails its environment with the message and asks the integration to delete the workspace (§9.3). It does not quarantine: quarantine belongs to the integration's own probe inside `allocate`.

### 7.3 `check_health`

`Runners::HealthCheck` already runs every minute for every live runner and applies the adapter's `Health` (status, reason). The runner's health checks **the integration only**. The coder adapter returns, in order:

1. The integration is `inactive` or `error` (a column, no IO): `unreachable`, `Coder integration "<name>" is <inactive | in error: <settings.error>>. Reconnect it, or pick another runner.` This is DESIGN.md §2.6's rule, and it needs no Coder call.
2. Otherwise `IntegrationService#test` (the token), **at most once every 5 minutes**. Only this call is cached: the stamp is `runners.health["checked_at"]`, and in between the last test result is reused. Rule 1 is evaluated on every run. Refused: the integration becomes `error` and the runner `unreachable` as in 1. Coder unreachable: `unreachable` with the reason.
3. Otherwise `connected`.

**There is no provisioning-failure streak in this item.** A `degraded` runner is still admitted (§10), and every failed session shows the integration's or the runner's own message. A rule that marks a runner `degraded` after repeated failed environments is deferred (§17).

Nothing about the template (that it exists, its version, its parameters), the workspace name or the autostop is checked: the first two are the integration's, and the autostop is a prerequisite in the user guide (§12). `status_reason` is capped at 255 characters, as `ManualAdapter` caps it.

### 7.4 The adapter on the start path

Today the session start does not reach the adapter: `RunnerRuntime` and `Runners::Machines` never call it (`docs/architecture/runtime-layers.md`). 17c moves the start path to `Runners::Allocator`, and every difference between types becomes a method of `Runners::Adapter` with one implementation per type. `Runners::Allocator` and `RunnerRuntime` check no type, no capability and no policy. That includes the check of §9.2 in `RunnerRuntime#cleanup_ready?`, which becomes the adapter's answer. The allocator takes the locks, sets and clears the hold and counts `max_environments`; it calls an adapter method that does IO outside its runner lock.

| Method | `ManualAdapter` (what it does today) | `CoderAdapter` |
| --- | --- | --- |
| `new_environment(runner)` | `nil`: no new environment can be made, so the allocator goes to the capacity wait and the offline rules | The attributes of a new row: `provisioning`, `allocated`, a platform-made `key` (§5.1) |
| `advance!(environment)` | `:ready` (a registered machine is ready) | `Runners::Provisioning.advance!` (§5.2): `:pending` or `:ready`, or raises |
| `release!(environment, session, failed:)` | The scrub or reset by the runner's policy, and on success the machine returns to rotation; a failed reset takes it out of rotation. The code of `RunnerRuntime#cleanup_session` after the stop (the scrub or reset) and `Machines.release!` moves here. What `settle_resets!` still does is whatever #302 leaves, and 17c builds on that | `begin_teardown`, then `teardown` once (§9.3). No scrub |
| `fail!(environment, reason)` | The machine goes `failed`, out of rotation, with the reason (`Machines.fail!`). It stays `failed` until it is revoked and registered again with Add machine | `mark_failed` with the reason, `begin_teardown`, then `teardown` once |
| `end_registration!(environment, ended_by:)` | §6.1: the row becomes `gone` | §6.1: `begin_teardown`; `gone` when the workspace is deleted |
| `cleanup_waits_for_unheard?(environment)` | `true`: cleanup waits for a machine that is not heard (the guarantee of `runtime-layers.md`, 7) | `false` |
| `rebuild!(environment)` | Raises `Runners::UnsupportedOperation` | `begin_teardown` (§6): retire-and-replace |

Only an action that makes no sense for a type raises `UnsupportedOperation`: Rebuild on `manual`. The UI hides it by `capabilities` (`rebuildable`), so a user does not reach the error. Return to service is not an adapter method: #302 removes it, with the failure streak. `Runners::Allocator.release!` and `fail!` run the common part (the lock and the hold), keep no failure count, and call the adapter. A machine is failed only for a failure of the machine or its runner, never for a session's outcome. 17c and 17d update `docs/architecture/runtime-layers.md` (§14).

## 8. Delivering `aixle-runner`

No new runner command, no new credential kind and no new form of `check-in`. The runner binary does not change for item 17.

### 8.1 The token, bound to the environment

`Credentials.mint_registration!(runner, created_by: nil, environment: nil)`: for a `coder` runner it requires `environment:` (an `allocated` environment of that runner, in `provisioning`) and stores it in the credential's `runner_environment_id`. A `manual` runner's token is unchanged (no environment, one machine per use). It is minted under the runner's lock like every issuer. **One token is minted per environment, once**, and its expiry is the existing `REGISTRATION_TTL` (1 hour), longer than `bootstrap_timeout`. The minted token is also the record that the install began (§8.2).

### 8.2 The checks, then the install

`CoderAdapter#inject_bootstrap` runs two commands over `Coder::SshRunner#exec(workspace_name: env.external_id, …)`, so the integration's token, the redaction and the `coder` CLI handling are the integration's:

1. **The VM check and the privilege check**, one short command. It exits with a distinct code, and the adapter turns each into a `ProvisionError` with a message for people:
   - the workspace is a container or a pod (`systemd-detect-virt --container` reports one, or `/.dockerenv` exists, or `KUBERNETES_SERVICE_HOST` is set): "This workspace is a container or a pod. Aixle coder runners support virtual-machine workspaces only";
   - not root and `sudo -n true` fails: "The workspace gives neither root nor passwordless sudo, which the runner service needs";
   - no `systemctl`: "The workspace has no systemd, which the runner service needs".
   This is DESIGN.md §2.6's rule, run by the platform. The runner has no preflight for it, and a `manual` runner is unaffected. Decision 4 of task 8b stays: a Docker daemon that cannot see the runner's files is found by Docker's refusal of the sidecar's bind mount, as built.
2. **The install**: `Runners::MachineInstallScript.render(version:, gateway_url:, digests:)` (the same module and pins as `GET /runner/v1/machine-install.sh`, #288) is piped on stdin: `sh -s -- --token <token> --name <external_id>`, run through `sudo -n` when the user is not root. The script picks the architecture, downloads from `/runner/v1/releases/:version/:platform`, checks the SHA-256 against the pin, and runs `configure`, `service install` and `service start`, as it does for an operator. A mismatch stops it before anything runs, with the script's own message, which the adapter keeps as the bootstrap output.

**The install call has an explicit timeout**, `Settings.runners.install_timeout` (120 s), passed to `SshRunner#exec(timeout:)`. It is well under the phase's 300 s, so the outcome is known before the activity can be cut off. An install that does not finish in time fails the environment with "The install on workspace X did not finish within 120 s" (no second install, below).

The token is in argv for the few seconds before it is spent. Accepted: it is single use and spent at once, and it stays in argv (no stdin or file delivery). The adapter redacts the registration token from the output it keeps and logs. `SshRunner` redacts only the integration's own token, and is not changed.

**A failed install fails the attempt. There is no second install.** The install runs once per environment. Any failure of the runner's checks or of the install, **an interrupted install call included**, fails the environment (`mark_failed`, a `ProvisionError`), and the environment is torn down. There is no new token and no second install. The plaintext of a token cannot be recovered after it is minted, so a retry could not resend it. The session fails through the path of §5.1.

How an interrupted call is recognised: the step that finds an environment in `provisioning` with a bound registration token that is unspent (the install began and its outcome is unknown) does not run the install again. It fails the environment with "The install on workspace X was interrupted". A step that finds the environment `booting` just waits for the check-in. Retrying an install is deferred (§17), for when such failures turn out to be frequent.

### 8.3 The runner is a system service

The workspace must give root or passwordless sudo, and `machine-install.sh` runs as it is (`configure`, `service install`, `service start`). There is no `service install --user` and no user-level unit. The runner needs Docker, and membership of the `docker` group is root-equivalent, so the requirement adds nothing the runner did not already need. The user guide states it (§12). A template whose user cannot sudo fails with the message of §8.2, and the workspace is deleted (§9.3).

### 8.4 `register` fills the row

`Runners::Registration.register!(credential, …)` today creates a `registered` environment. When the credential names an environment, it fills that row instead, under the runner's lock and the row's:

- the environment must be `allocated`, of the credential's runner, in `provisioning` or `booting`; otherwise `invalid_token`;
- it records `display_name` (the `--name`, which is the workspace's name), os, arch, facts, `auto_update`, versions and `first_seen_ip`, and the token is spent;
- its state becomes `booting` through `finish_build` when it was `provisioning` (the install call had not returned yet). **`register` may move the row to `booting` before the install call returns, and the step then fires no second transition**: it re-reads the row under its lock and fires `finish_build` only if the row is still `provisioning`;
- the credential pair is issued as for a `manual` machine.

The runner then checks in at its start (`runner/internal/cli/machine.go`). `CheckIn.check_in!` fires `check_in` (`booting → idle`) when the preflight reports nothing wrong, and `fail_for_preflight!` fails it otherwise, the failure being the reason, as it does for `manual`. For an allocated environment `fail_for_preflight!` calls `Allocator.fail!`, not `Machines.fail!`.

Credentials of a provisioned environment are invalid when it leaves `idle` for `tearing_down` or `failed`, and when it is `gone` (§9.3). `RunnerGateway::V1::ApplicationController` refuses those states for an `allocated` environment (a `failed` environment's credentials are invalid for both types: the `manual` exception that kept them for Return to service goes with it, #302).

**Credential reuse.** `Credentials.rotate!` calls `Allocator.fail!` where it calls `Machines.fail!` on refresh-token reuse (17c). For an allocated environment the family is revoked, a live session fails through `Sessions::Lifecycle.fail_if`, and the environment is torn down. Tests cover reuse on a `manual` and on an allocated environment, including the failure of a live session and the teardown of the latter.

## 9. Release

What happens to a workspace is fixed. There is no `on_release` setting and nothing is handed back to the pool.

### 9.1 `reuse_policy`

`coder` has `fresh` only: a workspace per session, deleted after it. `reuse` and `reset` decide how a machine is cleaned between sessions, as DESIGN.md §7.1 and §7.2 say. They are not built on `coder` and come after row 18, once the start time of a `fresh` session is measured (§17). D28 stays for that row.

### 9.2 What happens when the session ends (`cleanup_session`, then `Allocator.release!`)

| Environment when the session ends | What happens |
| --- | --- |
| `provisioning`, `booting` (never started) | The hold is cleared; no op is sent. `begin_teardown`, and the delete finds the workspace by its holder (or none, §4.5) |
| `idle` | `container.stop` (best effort, and only when the environment is heard), hold cleared, `begin_teardown` (§9.3). No scrub: the workspace is deleted |
| `failed`, or the session lost contact | `container.stop` is skipped when the environment is not heard (its op would only expire), hold cleared, and the environment is torn down. `RunnerRuntime#cleanup_ready?` asks `adapter.cleanup_waits_for_unheard?(environment)`, which is false on `coder`: nobody will hear a machine we delete (§7.4) |

### 9.3 `teardown`: the workspace is deleted

`teardown` always deletes: it calls `Coder::Allocator#delete(holder:)` (§4.5) once the environment is `tearing_down`. It happens in four cases and no other:

- the session ends, is cancelled or fails (`fresh`);
- a broken machine (a failed check, install, preflight or boot timeout): the environment is failed with the message, then torn down;
- an environment revoked from the runner page, or by credential reuse;
- the runner deleted (or revoked): every environment that is not `gone` is torn down (§6.1).

**A session's own cleanup starts the teardown at once.** `Allocator.release!` calls `adapter.release!`, which on `coder` fires `begin_teardown` and calls `adapter.teardown` once (idempotent; `:pending` is fine). The reconciler only retries `tearing_down` environments and sweeps; `Settings.runners.max_teardowns_per_run` applies only to its retries (§11). A test ends N sessions at once and checks that all N teardowns start, whatever the cap.

The environment is `gone` when Coder reports the workspace deleted, and the integration then releases the hold. The reconciler's sweep of a `gone` environment that still has a hold calls `delete(holder:)` and releases the hold only on `:gone`, so a workspace locked late is deleted, never returned to the pool (§4.2, §11). The credentials of the environment are revoked at `tearing_down` (§8.4), so a runner that is still alive on a workspace being deleted calls nothing.

## 10. Sessions: how the allocator and the release fit `Sessions::Lifecycle`

**`create_container`** (`RunnerRuntime`): `Allocator.acquire!(session)`, then `container.start` once the environment is ready, as today. `Pending` and `CapacityError` reach `capacity_wait`. A `ProvisionError` becomes a `CreateRefusedError` (§5.1). The admission's `runtime_id` is persisted before the phase (`AdmittedPhaseActivity`), so the cleanup always runs.

**`start_container`**: unchanged, a `status` loop. The environment is already `idle`.

**The admission slot** (D12). Concurrency counts running sessions. A machine being deleted holds no admission slot, and `max_environments` limits the runner's machines, not concurrency. `Allocator.release!` clears the hold at the end of cleanup and the session's admission is released as today, after `Sessions::Lifecycle.finalize`. The rule for an unreachable machine stays for `manual` (DESIGN.md §10). On `coder` a session that lost contact is cleaned up at once and its environment is torn down (§9.2).

**Lifecycle rules.** The allocator and provisioning never write a session's state. Where an environment fails under a live session the caller is the end-of-registration path or the dead-container scan, and it uses `Sessions::Lifecycle.fail_if(session, error_message:)`, as `Runners::ContactLoss` and `Runners::Revocation` do. The `terminal_sessions.runner_environment_id` write stays the one `Machines.take!` makes today.

**Interactive sessions** (#277) work as on `manual`: the runner on the workspace opens the tunnel, the relay maps the session to the environment through the hold (`RunnerEnvironment`'s `after_save` signal), and the browser path is unchanged. The coder-specific requirement is egress from the workspace to the relay host (DESIGN.md §12.5).

**Launch refusals** become polymorphic. `Runners::Resolver` calls `Machines.availability(runner)`, which is `manual`'s. `Adapter` gets `launch_refusal(runner)` (nil, or `Refusal(reason, message)`), declared on the base with no default. `ManualAdapter` delegates to the existing availability code; `CoderAdapter` refuses an `unreachable` runner with `runner_unreachable` and §8's message ("Runner "X" is unreachable: <the health reason>"), which names the integration. A `degraded` runner is admitted.

## 11. The failure paths of §8 on `coder`

`Runners::Reconciler` (`app/services/runners/reconciler.rb`) runs every minute, as a new activity in `runner_health_check_workflow` after the health check. Each rule works on one provisioned environment and is idempotent; one that fails is logged and does not stop the others. The reconciler has three jobs: drive teardowns, fail an environment that outlived `bootstrap_timeout` under a session that no longer retries, and sweep the holds of `gone` environments (delete the workspace, then release the hold).

| Condition | Detected by | Outcome |
| --- | --- | --- |
| **Provisioning fails** (template refused, build failed) | `provision`/`prepare` raise `ProvisionError` | `mark_failed` with Coder's message. The session fails with that message (§5.1). The environment is torn down and the workspace deleted |
| **The workspace is a container or a pod, gives no root or sudo, or the install fails or is interrupted** | The checks and the install of §8.2 | `mark_failed` with the message, and the workspace is deleted (§9.3). No quarantine, no second install. The session fails with the message |
| **The build or boot times out** | `boot_started_at + bootstrap_timeout` (set when the integration handed over a workspace, §5.2), in `advance!` (`provisioning`, `booting`) and in the reconciler for an environment whose session no longer retries | `mark_failed`, teardown; the session fails with the message below |
| **No check-in within `bootstrap_timeout`** | Same rule, `booting` | "Workspace started but aixle-runner did not check in within 15 min. Check that the workspace can reach <platform host>:443." plus the install script's last output (§8.2). `failed`, then teardown |
| **The integration has nothing to give** (its quota is reached, the provider is out of capacity at create) | `allocate` raises `ExhaustedError` | `capacity_wait` with `runner_capacity` and the integration's own message, the reservation kept, admission otherwise unchanged (§5.1). The environment stays in `provisioning` with no workspace and no clock (`boot_started_at` is null), and **the wait has no time limit**, as a hosted session waits for cluster capacity (D46). The session ends when it is cancelled, which tears the row down (§9.2). A failed build is a diagnosed failure of that session, with Coder's message. Parsing provider errors for "out of capacity" is deferred |
| **A session ends or is cancelled while its environment is `provisioning` or `booting`** | `Allocator.release!` | `begin_teardown` (§9.2). Teardown calls `delete(holder:)`, which deletes a workspace the holder holds, including one locked before `external_id` was written. Not a failure unless it timed out |
| **Workspace stopped or deleted under a session** (a spot reclaim, as `DeadWorkspaceReaper` describes; a template autostop; the integration's token revoked and the workspace gone) | The existing contact-loss grace: `CoderAdapter#observe` returns `:unknown` while the environment is not heard, and `ScanDeadContainersActivity` (unchanged) fails the session after `ContactLoss::GRACE` (15 minutes) with the grace message | The session fails by contact loss. Its cleanup then fails the environment and tears it down (§9.2): the workspace is deleted if it still exists. There is no Coder call to tell a stopped workspace from a silent service, no two-sighting rule and no revival |
| **The integration's token is revoked** | `check_health` (§7.3) every 5 minutes; any adapter call that gets 401/403 calls `IntegrationService#test` | The integration is `error`, the runner `unreachable`, launches are refused with the integration named. Running sessions continue: the runner talks to the platform, not to Coder. A session waiting in provisioning fails with "Coder integration "X" rejected its token. Replace the token." Teardowns that cannot reach Coder stay `tearing_down`, retried every minute, and count toward `max_environments` until the token is replaced |
| **Runner revoked or deleted** | `Runner`'s `after_save` already ends its sessions (`Revocation.end_sessions!`) | It also calls `end_registration!` for every environment that is not `gone` (§6.1), which tears the coder ones down and deletes their workspaces. The reconciler finishes them. The runner page lists any that Coder would not delete ("must be removed by the customer") |
| **Disabled** | | No new sessions; environments are left. Running sessions finish |
| **Environment revoked from the runner page** | `Registration.revoke!` | `end_registration!` (§6.1): credentials revoked, a live session failed, `begin_teardown`, `gone` when the workspace is deleted |
| **A `tearing_down` or `failed` provisioned environment** | The reconciler, every minute | `failed` → `begin_teardown`; `tearing_down` → `adapter.teardown`, `finish_teardown` on `:gone`. A delete Coder refuses is retried |
| **A `gone` environment still has a hold** (for example, a workspace locked by an `allocate` that was still in flight when the session was cancelled) | The reconciler's sweep | `Coder::Allocator#delete(holder:)` first. While it returns `:pending` the hold stays and the sweep asks again next minute. The hold is released only when it returns `:gone` (`LockService#release_owned`). No direct release of a `gone` environment's hold, so the late-locked workspace is deleted, never returned to the pool |

**Only the environment's own failures fail a `coder` environment; no session outcome does.** The paths that call `fail!` or `mark_failed` are: provisioning refused by Coder (`ProvisionError`), a failed check or install (including an interrupted one), the boot timeout, no check-in within `bootstrap_timeout`, a preflight failure at check-in, a workspace that stays silent past `ContactLoss::GRACE`, and credential reuse (`Credentials.rotate!`). A session that ends, fails, is cancelled or is revoked releases its environment (`release!`, `let_go!`), which tears a `fresh` one down as a matter of course, not as a failure. `Allocator.release!(…, failed:)` carries the session's outcome to the adapter only for the cleanup it needs (whether the machine is heard, §9.2), and records nothing on the environment. A test per path checks the environment's reason, and a test checks that a failed session ends its `coder` environment in `tearing_down`, never `failed`. 17c and 17d add this to the guarantees of `docs/architecture/runtime-layers.md`.

**A workspace that stops under a session** waits for the grace, so it holds its session and its slot for up to 15 minutes. That is the existing contract of every runner type. **The user guide says that the template's autostop must be off, or longer than a session**: Coder moves the deadline only when someone connects through Coder, and the runner never does. Pushing the deadline forward is deferred (§17).

The reconciler never acts on: a healthy environment held by a session; any workspace that is not an environment's `external_id`; and, per the reaper's cap, more than `Settings.runners.max_teardowns_per_run` (default 3) workspace deletions **of its own retries and sweeps** in one pass. The cap does not apply to the teardown that a session's own cleanup starts (§9.3). A provider outage that fails every build at once must not empty a pool in a single sweep.

## 12. UI and API surface

No new feature flag. The type is behind `external_runners` as the rest of the runners are, and `coder` becomes visible and creatable only in 17e, the last task, so nobody sees it before the work is done. `Runners::Adapter::REGISTRY` gains `"coder"` in 17d, so that sessions, the health check and the reconciler can dispatch to it (`Adapter.for`). Until 17e the type is not offered in the form, and creation refuses it in one place (`Adapter::UNRELEASED_TYPES = %w[coder]`, read by `Runners::Save` and by `Adapter.available_types`), which 17e removes. A 17d test resolves the adapter through `Adapter.for`, as a session does.

- **Form.** Step 2 for `coder`, generated from `ConfigSchema.for_type("coder")` as for `manual`: **the integration select** (the visible active Coder integrations that DESIGN.md §2.6 allows for the runner's scope), the `container` options, and `max_environments` (step 3). **No `reuse_policy` choice**: `coder` is `fresh` only, and the form says so in a line. No template, version, parameter or `on_release` fields. Beside the select, a line says that the integration's pool and quota are shared with whatever else uses it, that a `fresh` runner takes free workspaces of the pool and deletes them, and that workspaces come from the integration's default template. The integration select is shown on create only; the runner page shows the integration as read-only (§7.1). "Connect" runs the config checks and `Runners::HealthCheck.check!` inline. `Runners::Save` and the controllers already refuse a type with no adapter; adding the adapter lifts "not available yet". No templates endpoint is needed.
- **Which runners can use Coder.** Today in practice only a project runner finds an eligible integration (the facts at the top). The card is offered when the integration select has an eligible option for the scope. After #298, a project can have several, which is what lets a customer keep the runner's integration apart from the agents'.
- **Runner page.** The Machines section becomes **Environments** for `coder`: key, state (`provisioning`…`gone`, with the reason), the session it holds (link), last heard, runner version, workspace link to Coder, and the actions Rebuild (`begin_teardown`) and per-environment Revoke (`end_registration!`; both delete the workspace). The overview shows the integration. A `manual` runner's page is unchanged. The runners list shows "environments busy/total" with `Runner#machine_counts` extended to a provisioned runner, counting every environment not `gone`.
- **Integration removal.** A Coder integration can be removed when no runner that is not deleted references it and no environment of a deleted runner is still not `gone`. `IntegrationsController#destroy` refuses otherwise, and its message names the runners. Removing it sets `integration_id` to null on the deleted runners that reference it. A deleted runner row is kept: its sessions keep their `runner_id` history. Three changes (17d): the `runners_coder_integration` check requires an integration only on a `coder` runner that is not deleted (a migration); `Integration`'s `has_many :runners` restriction counts only runners that are not deleted; and the removal service nulls the reference and refuses while a deleted runner still has an environment that is not `gone` (its teardown needs the integration). Delete the runner first, which revokes and tears down.
- **Docs.** The user guide and its portal mirror (`docs/user-guide/` and `app/frontend/pages/Docs/data/pages/`): that a coder runner takes machines from the integration (a free workspace of its pool, or a new one from its default template); **that on an integration shared with hosted sessions, a `fresh` runner takes free workspaces of the pool and deletes them**; that `fresh` means a session sees nothing of earlier runner sessions; the requirements on the machines (a virtual machine, root or passwordless sudo, systemd, Docker); **that the template's autostop must be off, or longer than a session**; that workspaces are deleted after each session, for a broken machine, on revoke and on delete; keeping the runners' integration apart from the agents' is the customer's job; and the egress the workspace needs.

## 13. Testing approach

Tests follow the area's conventions: Minitest and FactoryBot, no fixtures, sequences in factories (`test/factories/runners.rb` and `runner_environments.rb` get `:coder` and `:allocated` traits). Coder is stubbed at the HTTP layer with WebMock, as `test/services/coder/` does. `SshRunner` is passed to the adapter as a dependency (as `Coder::HealthCheck` takes one), never stubbed with a block returning a fake object. Concurrency tests copy `machines_concurrency_test.rb`. The `Runners::Allocator` public contract is tested for a `manual` runner too, so the move is covered before any Coder code exists. The per-task tests are in §14.

## 14. The split of item 17

The split is four tasks. Each is cut when the one before has merged, against the code as it is then, as §15 of DESIGN.md says. All are behind `external_runners`, with no new flag. The `coder` type becomes creatable only in 17e. 17b and 17c do not depend on each other and may be cut in either order, and neither depends on #298. **17d and 17e are cut after #298** (the implementation of #295), because the integration lookup and the form depend on several Coder integrations per scope. The runner (Go) does not change in any of them.

| Row | Delivers | Tests | Staging check | Item 18 (DESIGN.md §12.5) needs from it |
| --- | --- | --- | --- | --- |
| **17b** The Coder services for a second consumer | `LockService::Holder`, `held_by`, and the explicit hold of an environment holder, derived from the holder kind (`expires_at` NULL) (§4.1, §4.2); the Coder tools passing `Holder.session`. `Allocator#allocate(wait: false)` with the ready-machine handover (§4.3). `Coder::WorkspaceStatus` extracted from `Allocator` and `DeadWorkspaceReaper`. `WorkspaceService#status`, `ensure_started_async`, `QuotaError`. `Allocator#delete(holder:)` (§4.5). No runner code | The hosted suites (`allocator_test`, `lock_service_test`, the tool tests, `dead_workspace_reaper_test`) pass **unchanged in behaviour**. New: an environment holder's lock is not released by `release_all_for_session`, never reclaimed by expiry, skipped by `allocate` and by the reaper, released by `release_owned`; `held_by` makes `allocate` idempotent for a holder. `allocate(wait: false)` against WebMock: returns `:pending` without a build wait for a stopped and for a new workspace, and `:ready` only when the build succeeded, the agent is connected and the probe passed; a probe that fails is handled by the integration and the result never hands over that workspace; a retry for the same holder continues the same workspace; takes a free one; `ExhaustedError` when it has nothing. `delete`: `:pending`, `:gone`, **`:gone` for a holder that holds no workspace**, an unknown workspace, a refusal, and a workspace locked before any name was recorded is deleted. `WorkspaceStatus` for every build and agent state, from the reaper's and the allocator's old fixtures. `QuotaError` for a recorded refusal | **An agent session that uses `coder_*` as before** (allocate, run, release; the reaper's next sweep). A `bin/rails runner` script: `allocate(wait: false)` with an environment holder, `status` until running, `delete`. The hosted pool's next allocation and the reaper's next sweep leave the held workspace alone. The quota refusal's status and body recorded (§15) | A workspace the platform holds for a runner, with no runner code |
| **17c** The runner core without Coder | `Runners::Allocator` (`acquire!`, `release!`, `let_go!`, `fail!`) replacing the `Machines` calls in `RunnerRuntime`, `Revocation`, `ContactLoss`, `CheckIn`, `CleanupStaleActivity` and **`Credentials.rotate!`**, with step 2 and the `max_environments` count. The provisioned arm of `RunnerEnvironmentStateMachine` and its migration (§6). The adapter methods of §7.4 on `Adapter` and `ManualAdapter` (`new_environment`, `advance!`, `release!`, `fail!`, `cleanup_waits_for_unheard?`, `rebuild!`); the code of `Machines` and `RunnerRuntime#cleanup_session` that is `manual`-specific moves into `ManualAdapter`. 17c starts after #302 is merged and builds on the code #302 leaves (no Return to service, no failure streak). `Adapter#end_registration!` and its callers (`Registration.revoke!`, `unregister!`, `Revocation`) (§6.1), with `Credentials.lock_runner!` for a retired runner. `Runners::Provisioning.advance!`. `Adapter#launch_refusal`, `RunnerEnvironment#in_service?`, the `runner_provisioning` wait reason (model, `launchStatus.ts`), `Settings.runners.bootstrap_timeout`. `Runner` validates `fresh` for `coder` and refuses a change of `integration_id`; `Runners::Form` permits it on create only. Registering into a row the platform created: `Credentials.mint_registration!(…, environment:)`, `Registration.register!` filling the row (§8.4), `CheckIn.check_in!` firing `check_in` and failing an allocated environment through `Allocator.fail!`, the gateway's refusal of the states of §8.4, a `PROTOCOL.md` note (no schema change). `RunnerRuntime#cleanup_ready?` and `cleanup_session` through the adapter (§9.2, §7.4). Updates `docs/architecture/runtime-layers.md`: the layers, "Where differences between types live", the guarantees and "Adding a runtime or a runner type" (the guarantee that an environment is failed only for its own failure, never for a session's outcome, as #302 leaves it) | Model and state-machine tests for every event and refusal. Allocator tests with a fake provisionable adapter registered in the test only: steps 1 to 3, the `max_environments` count including `tearing_down`, two sessions racing one environment, a retried acquire, revoke vs acquire lock order. `ExhaustedError` and `Pending` through `AdmittedPhaseActivity` end as `capacity_wait` with the reservation kept; a `ProvisionError` ends the phase as non-retryable and runs the cleanup. **Per-environment Revoke and runner Revoke for `manual` and for an allocated environment**, including a live session and a `gone` workspace; **the runner-Revoke test checks every `manual` environment reaches `gone` without a `runner_revoked` refusal**. `ManualAdapter`'s answer to each method of §7.4 (a `manual` runner behaves as #302 leaves it), Rebuild on `manual` raising, a `failed` environment's credentials refused for both types, and a test that `Allocator` and `RunnerRuntime` contain no `runner_type` check. The fake adapter reuses `Provisioning.advance!`. **Credential reuse on a `manual` and on an allocated environment**, with a live session. Credentials tests (a bound token, one token per environment, expiry). `advance!` with a fake adapter: a timeout counted from the first `external_id` and none before it, an interrupted install fails the environment with no second install, the runner registering while the install call is in flight (no second transition), a session cancelled while `provisioning` and `booting`, a session cancelled while `allocate` is in flight (the environment ends `gone` and the workspace locked late is left held for the sweep of §11, which deletes it in 17d, not released to the pool). `register!`: fills the row, refuses another runner's environment, a `gone` one and a wrong state, spends the token once under two racing registrations. The conformance fixtures of `register` and the `manual` suites (`machines_test`, `runner_session_launch_test`, `runner_failed_machine_test`) pass as #302 leaves them, except where §6.1 names a change | The DESIGN.md §12.4 `manual` run: a session, two in parallel with one machine (`runner_capacity`), a reset, a runner Revoke. Nothing else visible changes. `aixle-runner configure --token` by hand against staging with a token bound to a row made in the console: the row fills and reaches `idle` | The `capacity_wait` path of step 3, and a machine that registers into a row the platform made |
| **17d** A Coder runner created from the console | `CoderAdapter` (§7, §7.4): the checks and the install over `SshRunner` (§8.2, with `Settings.runners.install_timeout`), `provision` and `prepare` through `allocate(wait: false)`, `teardown` through `Allocator#delete`, `observe` as `manual`'s, `check_health`, `launch_refusal`, `end_registration!`, `release!` (which starts the teardown at once), `fail!` and `rebuild!`. `coder` in `REGISTRY` and `Adapter::UNRELEASED_TYPES` (§12). The migration and the model changes for integration removal (§12). Updates `docs/architecture/runtime-layers.md` for the `coder` guarantees (a `fresh` environment is deleted, not scrubbed; only the `coder` paths of §11 fail an environment, never a session's outcome) and "Adding a runtime or a runner type". Sessions on `coder`: `create_container` (`Pending`, `ProvisionError`), `cleanup_session` for `fresh` (§9.2), the boot-timeout failure. The complete `Runners::Reconciler` (§11): teardown pacing and cap, `failed` to `tearing_down`, timed-out environments, sweeping the holds of `gone` environments (`delete(holder:)` first, release on `:gone`). `ConfigSchema` without the template keys and `on_release`. The runner is created from the console, not the form | Adapter tests for each health outcome in §7.3. `provision` idempotent on a retried step; `prepare` pending, ready, and an `external_id` that changes; `ExhaustedError` as `CapacityError`. `inject_bootstrap` with a recording `SshRunner`: the container, no-sudo and no-systemd exits, the token placement, an interrupted call. `teardown`. `observe`. `runner_session_launch_test`-style integration tests on a provisioned runner with the provider stubbed: one session, two in parallel, a third waiting (`runner_capacity`), `fresh` ends `gone`, a session cancelled while `provisioning` and `booting`, a session cancelled while `allocate` is in flight (the workspace it locks late is deleted by the sweep, not released to the pool), a timeout in `provisioning`, a silent environment failed by the grace and torn down, `Sessions::Lifecycle.finalize` ordering, the admission slot not held by a deleting machine. One test per row of §11, with time travel for the 15 minute rules; a teardown that Coder refuses, retried; a deletion cap on the reconciler's retries and none on a session's own cleanup (N sessions end at once, N teardowns start). `Adapter.for` resolves `coder` as a session does, and creation through `Runners::Save` is refused. An install slower than `install_timeout` fails the environment with the message of §8.2. Delete a `coder` runner, finish its teardown, then remove its integration; removal is refused while a deleted runner's environment is not `gone`, and while a live runner references it | A `coder` runner created from the console on the staging integration: `check_health`, a non-interactive and an interactive session, two in parallel plus a queued third, `fresh` deleting its workspace, a tampered pin refusing the install, a stopped workspace under a session failing it by the grace, a revoked integration token, a runner Revoke deleting the workspaces. The answers to DESIGN.md §12.5's three questions (Docker daemon, disk, pruning) | DESIGN.md §12.5 steps 2 to 9, run on a runner made from the console |
| **17e** The type, the form, the page and the docs | the form (the type offered, `Adapter::UNRELEASED_TYPES` removed, integration on create only, the `fresh` line, the shared-pool line), the Environments section, Rebuild, per-environment Revoke, the runners list column, the integration-removal message, the user guide and its mirror (§12), DESIGN.md's built-state notes | Frontend tests for the form, schema errors at their fields, the page for each state. Controller and policy tests (the scope rules of DESIGN.md §2.6 and the integration lookup of #298; an update that changes `integration_id` is refused). The user-guide mirror pair check | The whole of DESIGN.md §12.5 by hand, without the console | The type creatable from the UI (the one refusal removed), which is what DESIGN.md §12.5 step 1 starts from |

Row 18 stays the QA task of DESIGN.md §12.5 and is cut after 17e. Its steps 10 and 11 (a second project's refusal, hosted unchanged) need no code from item 17 and are the existing selection and DESIGN.md §12.3 regression tests. **Row 28** (after row 18) carries `reuse` and `reset` on `coder`, once the start time of a `fresh` session is measured (§17).

**What breaks for companies on `external_runners` today** (the runners are a beta for one company, and a break is weighed case by case). Nothing is identified:

- `manual` runners, machines and versions: 17c moves the allocator under `RunnerRuntime`, and the `manual` suites pass as #302 leaves them. **Three changes are costs, not breaks:** `Runners::Allocator` takes the runner row `FOR UPDATE` for every type, where `Machines` takes `FOR SHARE` for a `manual` runner (its concurrent acquires and other `FOR SHARE` issuers now queue for milliseconds; 17c's PR states it, and a test shows two racing acquires on one `manual` runner still end correctly), a runner Revoke now ends each `manual` machine through `end_registration!` (§6.1, D50), and the `manual`-specific code of `Machines` and `RunnerRuntime#cleanup_session` moves into `ManualAdapter` (§7.4), with the `manual` suites passing as #302 leaves them.
- The migration of 17c is additive (two nullable columns, one `origin` value). `ConfigSchema` loses keys of a type nobody can create.
- 17b changes the Coder services that the agents' `coder_*` tools use in production. That is why it is its own task and why its staging check includes an agent session. Locks written before it stay valid.

If an implementation task finds a break, its pull request names it with the cost of keeping compatibility, and the reviewer weighs it.

## 15. Edge cases and risks

- **A manual runner's acquires queue on the runner row.** One lock mode for every type. The hold of the row lasts one transaction (no IO), so the wait is milliseconds.
- **The 30 s retry interval is a floor on start latency.** A workspace that is ready 5 s after a retry waits up to 25 s more. Accepted: a cold build takes minutes. Lowering `CAPACITY_RETRY_INTERVAL` would affect every runtime. Every `fresh` session pays a cold start; row 28 is cut when that is measured.
- **`coder` CLI in the worker.** `SshRunner` needs the CLI in the process that runs the activity. The Dockerfile installs it for the hosted tools; 17d confirms the container-workflow worker runs that image and says so in its PR if not.
- **Coder's quota error shape is unverified.** 17b confirms the status and message on staging and records them; until then a refusal that is not recognised is an `OperationError`, which becomes a `ProvisionError`: the session fails with Coder's message, not silent.
- **A workspace that autostops under a session** fails the session after the 15-minute grace, not sooner. The user guide's prerequisite (autostop off or longer than a session) is the mitigation, and a runner with a short autostop fails sessions with the grace message.
- **A booting environment is not scanned as silent.** `ScanDeadContainersActivity` must not count a never-heard `provisioning` or `booting` environment as lost: the boot timeout owns that window. 17c checks the scan's selection (it looks at sessions whose container started) and adds a test.
- **An install that crashes the worker mid-call** leaves a bound, unspent token. The next step fails the environment (§8.2) rather than install twice.
- **A capacity wait has no time limit.** A session waiting for the integration's capacity (`ExhaustedError`) or for `max_environments` waits as on every runtime, until it is cancelled, as a hosted session waits for cluster capacity (D46). `bootstrap_timeout` starts only when the integration hands over a workspace. A wait that never ends is visible on the session page with the integration's message.
- **An install slower than its limit.** The install call is cut at `Settings.runners.install_timeout`, so its outcome is known before the activity's 300 s ends. An install that was slow but succeeded leaves a runner that registers later against a row that is already `failed` and torn down: `register` refuses it (§8.4).
- **A workspace that fails the integration's probe.** `allocate` never hands it over, and what happens to it is the integration's logic. The runner may see its `external_id` change between two retries, and the adapter takes whatever the result says. A workspace that passes the probe and then fails the runner's own checks is deleted, not quarantined.
- **The token is in argv on the workspace for the few seconds before it is spent.** Single use and spent at once (accepted). It is never logged: the adapter redacts it from the output it keeps.
- **A runner deletes a workspace it was given from the pool.** That is the decision: every session's workspace is deleted. A customer who does not want a pool workspace deleted keeps the runner's integration apart from the pool's users.
- **An integration shared by hosted sessions and runners shares Coder's quota and provider limits.** Documented in the user guide. The runner page does not show it.
- **A default template that cannot serve a runner** (a container template, no sudo, required parameters, no Docker) fails the first environment with the message of §8.2 or Coder's, and every session shows it. A template that suits the pool and not the runner needs a second integration, which #298 makes possible.
- **A `fresh` session on a workspace that is slow to delete.** The session is finished, the admission slot is free, and the machine counts toward `max_environments` until `gone`: the next session may wait in `runner_capacity` while the runner is at its limit with deleting machines. This is D12.
- **Nested-Docker workspaces** (sysbox, envbox) are containers by `systemd-detect-virt` and are refused (§8.2).
- **No production identifiers** appear in this document. The spot-reclaim and quota events are described in general terms.

## 16. Decisions and assumptions

The source column names the decision by its content: "Alex" is a review decision of the task, "DESIGN.md" is the parent document.

| # | Decision | Source |
| --- | --- | --- |
| D1 | **Superseded by D18.** A `coder` runner is one more consumer of the Coder integration. It reuses the allocator, the locks, `WorkspaceService`, `SshRunner`, the health probe and the integration and token services. Quarantine is internal to the integration's probe (D17, D26) | Alex; code reading in §2 |
| D2 | `busy` is not a state: `idle` with a hold | `RunnerEnvironment#busy?`, patterns "Model Predicates" |
| D3 | Provisioning advances one step per `capacity_wait` retry through a `CapacityError` subclass and the wait reason `runner_provisioning`; no new workflow. A single long provisioning activity is declined | Alex |
| D4 | Rebuild is retire-and-replace. `Adapter#reset(level: :rebuild)` is not built | Alex |
| D5 | One `bootstrap_timeout` setting, 900 s, counted from the first write of `external_id` (D46) | `coder` is the only provisioning type for now; amends §8's "10 min, 15 for `coder`" |
| D6 | There is no `GET /runner/v1/install.sh`. The workspace is installed with `machine-install.sh` (`Runners::MachineInstallScript`) | Alex |
| D7 | **Dropped.** There is no bootstrap exchange and no revival | Alex |
| D8 | **Dropped** with `on_release`. An idle-stop timer is not built either | Alex |
| D9 | `check_health` calls Coder at most every 5 minutes; only `IntegrationService#test` is cached; the integration's state is read on every run | DESIGN.md §2.5; Alex |
| D10 | A refusal because the integration has nothing to give is a wait (`capacity_wait`, `runner_capacity`), with no time limit (D46); a failed build is a diagnosed failure of that session (the streak is deferred, D56) | Two different facts: the platform may retry the first, not the second |
| D11 | The VM-only rule is a command the platform runs on the workspace through the integration before installing. The runner does not change. Decision 4 of 8b stands | Alex |
| D12 | Concurrency counts running sessions. A machine being deleted holds no admission slot. `max_environments` limits the runner's machines, not concurrency | Alex |
| D13 | Launch refusal is an adapter method, not a type check in `Resolver` | The patterns' "one decision, one factory or polymorphism" |
| D14 | **Replaced by D57.** An integration's removal is refused while a runner that is not deleted references it | The existing `restrict_with_error` |
| D15 | **A failed environment of any type stays failed**: a `manual` one until it is revoked (and registered again with Add machine), a `coder` one is torn down and replaced. A machine is failed only for a failure of the machine or its runner, never for a session's outcome (#302) | §6 |
| D16 | A `coder` runner names an integration and nothing about templates | Alex |
| D17 | No runner rule for a missing default template. The runner asks `Coder::Allocator#allocate`; the integration decides. With #295 the template and prefix are required, so the case ends | Alex; #295 |
| D18 | The runner takes machines through `allocate`, never through the Coder API. `allocate` gains `wait: false` and hands the workspace over only when it is ready. It may get a free pool workspace. A dedicated runner integration with create-only workspaces is declined | Alex |
| D19 | `on_release` is removed. Every session's workspace is deleted after it; nothing goes back to the pool | Alex |
| D20 | The hold is explicit: the holder is the runner environment, no expiry, no renewal, derived from `Holder#kind`. Released when the runner deletes the workspace; the reconciler's sweep of a `gone` environment deletes first (`delete(holder:)`) and releases the hold only on `:gone` | Alex |
| D21 | The table-match rule is dropped. The lock already hides a held workspace from the allocator and the reaper | Alex, §4.4 |
| D22 | The token of a `coder` runner is the ordinary registration token, bound to the environment row. `register` fills the row; `booting → idle` happens at the first check-in | Alex |
| D23 | The runner on a workspace is a system service. Root or passwordless sudo is required | Alex |
| D24 | The runner binary does not change for item 17, so no runner release is cut for it | Alex |
| D25 | **Replaced by D43.** The autostop deadline push is deferred | Alex |
| D26 | Quarantine is internal to the integration's SSH probe inside `allocate`. A runner's own failure fails the environment and deletes the workspace | Alex |
| D27 | The health check reads the integration only: its state and its token | Alex |
| D28 | `reuse` and `reset` decide only how a machine is cleaned between sessions. They are not built on `coder` now; D28 stays for row 28 | Alex |
| D29 | `fresh` guarantees that a session sees nothing of earlier runner sessions. `allocate` may give a free pool workspace the runner never used. No create-only mode | Alex |
| D30 | The integration used by runners is kept apart from the agents' by the customer. After #298, a second integration does it; until then a project's Coder runner and its tools share one | Alex; #295 |
| D31 | No new feature flag. `coder` becomes visible and creatable in 17e | Alex |
| D32 | A break of what `external_runners` companies use is decided case by case. None is identified; §14 names how it is avoided | Alex |
| D33 | The split is 17b to 17e | Alex |
| D34 | A runner environment's `external_id` is the Coder workspace's name (the lock key, `coder ssh`, the tools' `workspace_name`). The `key` is a platform-made identifier. The `autostop_error` column is **not built** (D43) | Alex |
| D35 | The integration hands over a ready machine. `allocate(wait: false)` checks build, agent and its SSH probe; polling belongs to the integration; `prepare` asks `allocate` again. `allocate(wait: false)` returns `:pending` with the workspace it holds, and `:ready` with the workspace once it is; `external_id` may change between retries | Alex |
| D36 | One lock mode: `Runners::Allocator` takes the runner row `FOR UPDATE` for every type. One allocator for `manual` too; keeping `manual` on `Machines` is declined | Alex |
| D37 | **Dropped** with the deadline push | Alex |
| D38 | **Dropped** with `autostop_error` | Alex |
| D39 | The integration lookup and whether company-wide Coder integrations exist follow #295 (merged as a design). Several Coder integrations per scope, template and prefix required. 17b and 17c do not depend on its implementation (#298); 17d and 17e are cut after it | Alex |
| D40 | No production identifiers in the document or the PR: decisions are cited by content or D-label, no comment ids, no dates, no round history | Alex |
| D41 | The explicit hold is derived from `Holder#kind` (no `explicit:` parameter) | Alex |
| D42 | **`coder` ships with `fresh` only.** The form offers only `fresh`, and `Runner` validates it. `reuse` and `reset` on `coder` are row 28, after row 18, once a `fresh` session's start time is measured. The reuse/reset rows of §9.2, the `restart` event, the revival (the earlier §8.5) and the reconciler rules for warm environments are removed. The user guide states the shared-pool behaviour | Alex |
| D43 | **No autostop deadline push in this item.** The earlier §4.4, `WorkspaceService#extend_deadline`, the `autostop_error` column, the two settings, rule 3 of `check_health`, the runner page's refusal and the reconciler's deadline rule are removed. The user guide says the template's autostop must be off, or longer than a session. A workspace that stops anyway fails its session by contact loss. The push goes to §17. Replaces D25, D37, D38 and the autostop part of D34 | Alex |
| D44 | **No `requested` state.** An allocated row is created in `provisioning`, held by its session, with `boot_started_at` set at the insert. Teardown always calls `Allocator#delete(holder:)`, which returns `:gone` for a holder with no workspace, so a workspace locked before `external_id` was written is deleted. Replaces the `requested` lifecycle of the earlier design | Alex |
| D45 | **Contact loss through the existing grace.** `CoderAdapter#observe` is `ManualAdapter#observe`; `ScanDeadContainersActivity` does not change. A silent environment fails its session after `ContactLoss::GRACE`, and the environment is failed and torn down. No provider-aware `observe`, no two-sighting rule, no revival | Alex |
| D46 | **`bootstrap_timeout` counts from the first write of `external_id`**, when the integration hands over a workspace (`boot_started_at` is null before). Until then the session waits for capacity like on every runtime: `runner_capacity` with the integration's message, no time limit. Amends the earlier decision on the `requested` state on this one point | Alex |
| D47 | **A runner's integration never changes.** Chosen at create; `Runners::Form` permits `integration_id` on create only and the model refuses a change. The integration's own token and settings stay editable. Changing it may be added later | Alex |
| D48 | **Revoke goes through one adapter method.** `Adapter#end_registration!(environment, ended_by:)`: `ManualAdapter` keeps today's behaviour; `CoderAdapter` revokes credentials, fails a live session, fires `begin_teardown`, and the environment is `gone` when the workspace is deleted. `Registration.revoke!`, `unregister!` and the runner's Revoke call it | Alex |
| D49 | **A failed install fails the attempt.** One install per environment; no new token, no second install; an interrupted call fails the environment. The session fails through `ProvisionError` → `CreateRefusedError` → a non-retryable phase failure and cleanup, as on every runtime. Only a capacity wait is retried. Retrying an install is §17. Replaces the earlier retry with a new token | Alex |
| D50 | A runner's Revoke calls `end_registration!` for every environment, whatever its type; on `manual` each machine becomes `gone`. It runs after the runner is retired, so it uses a teardown lock path (`Credentials.lock_runner!`, runner → environment → credentials) that accepts a retired runner; `lock_live_runner!` stays for registration and token issuance. The 17c Revoke test checks every `manual` environment reaches `gone` with no `runner_revoked` refusal | Alex |
| D51 | `Runners::Credentials.rotate!` is part of the 17c move: its call to `Machines.fail!` on refresh-token reuse becomes `Allocator.fail!`, with tests on both types | Alex |
| D52 | `DESIGN.md` has one definition of each contract: §2.2 `external_id` and `reusable`, §2.3 the bootstrap credential, §2.5 template health, §2.6 heading, §7.2 Rebuild and §9.2 the bound registration token are updated in this change | Alex |
| D53 | **What differs between runner types is an adapter method on the start path too.** `Runners::Allocator` and `RunnerRuntime` check no type, no capability and no policy. The methods and each type's answer are in §7.4. `manual` answers what it does today; only an action that makes no sense for a type raises `UnsupportedOperation` | Alex |
| D54 | **Return to service is removed (#302).** It is not an adapter method and there is no `returnable` capability. Rebuild on `manual` raises `UnsupportedOperation`, and the UI hides it by `rebuildable` | Alex |
| D55 | **17c and 17d update `docs/architecture/runtime-layers.md`**: the layers (`Runners::Allocator` in place of `Machines`, the adapter on the start path), "Where differences between types live", the guarantees that change for `coder` (a `fresh` environment is deleted, not scrubbed), and "Adding a runtime or a runner type" | Alex |
| D56 | **No provisioning-failure streak in this item.** The `check_health` rule that marked a runner `degraded` is removed and goes to §17. A `degraded` runner is still admitted; every failed session shows the message | Alex |
| D57 | **An integration is removable once no live runner needs it**: no runner that is not deleted references it and no environment of a deleted runner is not `gone`. Removal nulls `integration_id` on the deleted runners; the `runners_coder_integration` check applies to runners that are not deleted; `Integration`'s restriction counts only those. Deleted runner rows stay | Alex |
| D58 | **The install call has a timeout** (`Settings.runners.install_timeout`, 120 s), well under the phase's 300 s; the token stays in argv | Alex |
| D59 | **A session's own cleanup starts the teardown at once**: `release!` calls `teardown` once. The reconciler retries and sweeps, and `max_teardowns_per_run` applies only to its retries | Alex |
| D60 | **No re-read after each adapter call** in `advance!`. The sweep that deletes before it releases is the guard | Alex |
| D61 | **`CoderAdapter` is registered in 17d**, so sessions, the health check and the reconciler dispatch to it. Until 17e the form does not offer the type and creation refuses it in one place (`Adapter::UNRELEASED_TYPES`), which 17e removes | Alex |

**The reviewer is asked to check:** the adapter methods of §7.4 and each type's answer (D53, D54), in particular what `ManualAdapter#release!` takes over from `RunnerRuntime#cleanup_session` and `Machines`; the removal of Return to service (D54); `Credentials.lock_runner!` and the 17c Revoke test (D50); that a capacity wait has no limit and `bootstrap_timeout` starts at the first `external_id` (D46); the install timeout (D58); how an interrupted install is recognised, by the bound unspent token and without a new column (§8.2, D49); that a session whose workspace stops waits for the 15-minute grace and then deletes the environment (§11, D45); the cleanup of an unheard `fresh` environment that skips `container.stop` (§9.2); and the split of §14 with 17d and 17e after #298.

## 17. Deferred, and what to check

- **`reuse` and `reset` on `coder`** (row 28, after row 18), once the start time of a `fresh` session is measured. Then the warm environment, the scrub and reset on release, the revival of an idle environment and the reconciler's rules for warm environments come back, with D28.
- **Pushing the workspace's autostop deadline forward** while a session runs (the earlier §4.4: `WorkspaceService#extend_deadline`, a reconciler rule, a refusal shown on the runner page). Cut when templates with a short autostop turn out to be common.
- **A rule that marks a `coder` runner `degraded`** after repeated failed environments (D56), cut when failing templates turn out to be hard to see from the session messages alone.
- **Retrying a failed install**, with a new token, for when such failures turn out to be frequent.
- **Changing a runner's integration** after creation.
- **Provider-aware `observe`** (the Coder status of a silent workspace, a faster failure than the 15-minute grace).
- **An idle-stop timer**, a **pool floor** and **warm-disk affinity** (out of the plan, Alex).
- **Classifying provider capacity errors in a failed build** (EC2 instance-type exhaustion and its like). It needs a per-provider reading of the build's error; every failed session shows the message until then.
- **Nested-Docker workspaces** (sysbox, envbox) as a supported shape. Refused by §8.2 until someone needs it.
- **A runner-level template or parameters.** Removed by decision. If a customer needs two templates, they use two integrations, which #298 makes possible.
- **A company-wide Coder integration** created from the UI, which a company runner on Coder would need (DESIGN.md §2.6). Deferred by #295.
- **The `host` execution mode** (row 20), Kubernetes (row 19) and the relay rows 24 to 27: out of scope, as the task says.
- **To check in 17b on staging:** the quota error's status and body, and the workspace-status fields of `GET /workspaces/{id}` for a stopped and a reclaimed workspace.
- **To check in 17c:** the dead-container scan's selection (a never-heard booting environment is not silent, §15), and that `machine-install.sh` runs on a fresh VM with no earlier service.
- **To check in 17d:** that the container-workflow worker image has the `coder` CLI.
- **To check in 17d on staging:** the template's Docker daemon, disk and image pruning (DESIGN.md §12.5's three questions).
