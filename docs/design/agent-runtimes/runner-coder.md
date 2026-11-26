# Coder runners: one more consumer of the Coder integration

**Status:** proposed (task #284, "Runners 17a"), round 3. Written against `origin/develop` after the interactive runner sessions of #277 (16g), the session lifecycle service of #273, #283 (`Sessions::Lifecycle.fail_if` and `finalize` are still there) and the Add machine work of #286 and #288 (`machine-install.sh`, `--mode machine`).
**Parent:** [`DESIGN.md`](DESIGN.md) §15 row 17. It refines DESIGN.md §2.2, §2.5, §2.6, §2.7, §5, §7.3, §8, §9.2, §10 and §11 for the `coder` type, and replaces row 17 with rows 17b to 17e (§14 below), as `runner-relay.md` did for row 16.
**Scope:** design only. This pull request changes this document, `DESIGN.md` and `docs/index.md`.

_A section number with `DESIGN.md` in front of it is the parent document's; a bare one is this document's._

**What round 3 changes.** Alex's review decisions of 2026-11-26, parts 1 to 4 (task comments 115825, 115857, 115882, 115897; the numbers 1 to 18 below are theirs):

| Round 2 | Round 3 |
| --- | --- |
| The runner only created its own workspaces and never took a free one of the pool (D18). `Allocator#provision` was create-only | The runner takes machines through `Coder::Allocator#allocate`, as the Coder tools do, in a variant that locks and returns at once (`starting`). It may get a free workspace of the pool. `allocate` gets no create-only mode (3, 15) |
| A runner with an integration that has no default template was `unreachable` (D17). The health check verified the template and the name length | No runner rule. The integration decides what it gives; when it has nothing the session waits in `capacity_wait` with the integration's message. The health check reads the integration only: inactive, in error, its token (1, 2) |
| `on_release: delete \| stop`, with a cleanup of a workspace handed back to the pool (D19) | `on_release` is removed. `fresh` deletes the workspace after the session, a broken machine fails its environment and the workspace is deleted, revoking an environment or deleting the runner deletes the workspaces. Nothing goes back to the pool (7) |
| A hold of 60 minutes, renewed every minute by the reconciler (D20) | An explicit hold with no expiry and no renewal. The holder is the runner environment. It is released when the runner deletes the workspace, and the reconciler releases the holds of `gone` environments (9) |
| Open: how Coder's autostop is prevented | While a session runs the reconciler pushes the workspace's autostop deadline forward through the Coder API. An idle warm workspace stops by its template and is started again before the next session. A refused extension makes the runner `degraded` (10, 12) |
| Quarantine had no reader on the runner path | Quarantine is internal to the integration's SSH probe inside `allocate`. When the runner's own part fails, it fails the environment and deletes the workspace; no quarantine (4, 13) |
| Rows 17b to 17g and 17h (seven tasks) | Rows 17b to 17e (16) |

**Facts about the integration that the design relies on** (code reading, Alex's comment 115882): a Coder integration is created per project only (`create_coder` always passes the current project); a project cannot have a second active one (`Coder::IntegrationService#ensure_only_active!`); so until #295 a Coder runner and the agents' `coder_*` tools of one project share one integration, its pool and its quota. A company runner on Coder cannot be set up, because DESIGN.md §2.6 asks for a company-wide integration for it. How the Coder tools pick an integration is a gap of the platform that #295 covers (several integrations, attached to workflows and sessions, named by id in the tools). #284 does not wait for it: a runner already names its integration (14).


## 1. Overview

A `coder` runner creates Coder workspaces for its sessions itself, through the company's Coder integration. Each workspace is a virtual machine that runs `aixle-runner --mode machine` as a system service and takes one session at a time in container mode, exactly as a `manual` machine does. What is new is everything before the session: the platform allocates, builds, boots and installs the machine, and releases it.

Setting up a `coder` runner means picking the Coder integration to take machines from. That is all it names about Coder: the template that workspaces are created from is the integration's default template.

Today the type cannot be created. `Runners::Adapter::REGISTRY` holds `manual` only, and the controllers refuse `coder` as "not available yet". The pieces item 17 needs and the code lacks:

| Piece | In the code today | Target |
| --- | --- | --- |
| Coder services for a second consumer | `Coder::Allocator`, `LockService`, `WorkspaceService` serve a terminal session only, and block up to 240 s per call | §4 (17b) |
| Runner allocator | `Runners::Machines.acquire!` takes a free registered machine (DESIGN.md §7.3 as 8a built it). No step 4 | `Runners::Allocator` (§5) |
| Provisioned states | `RunnerEnvironmentStateMachine` has `registered`, `resetting`, `failed`, `gone` | The provisioned arm (§6) |
| Delivery of `aixle-runner` | `register` creates an environment for a `manual` machine | `register` fills the environment the allocator created (§8) |
| `CoderAdapter` | None | §7 |
| `reuse_policy` | `reuse` and `reset` on `manual`, in `RunnerRuntime#cleanup_session` | `fresh` on `coder`, and the deletes of §9. No `on_release` |
| Integration state | Not read by any runner | An `inactive` or `error` integration makes its runners `unreachable`, with the integration named (§7.3). Nothing about templates |
| VM-only rule | A sentence in DESIGN.md §2.6 | A command the platform runs on the workspace before installing (§8.2) |
| Form and page | `manual` only | §12 |

## 2. What exists, and what a second consumer needs

The hosted pool is a set of workspaces that the platform leases to terminal sessions and drives over `coder ssh`. The Coder integration's services do that work today:

| Service (`app/services/coder/`) | What it does today | What a runner needs from it |
| --- | --- | --- |
| `Allocator` | Lists the token owner's workspaces under `machine_prefix`, locks a free one for a **terminal session**, probes it over SSH (a sick one is quarantined and passed over), and otherwise creates one from `default_template`. `ensure_started` and `create_new_workspace` call `await_build`, which sleeps up to 240 s in one call. It raises `ExhaustedError` when it has nothing to give | A holder that is a runner environment. A variant that locks and returns at once, without waiting for the build. The workspace status classification (it is private to the allocator and the reaper). A delete through the integration |
| `LockService` | A row in `integration_data` per workspace, keyed by `terminal_session_id`, expiring after the integration's `lock_ttl_minutes` (default 120) of inactivity, pushed forward by every Coder tool call (`touch`). `expires_at` is already nullable in the table and the queries | A holder that is not a session, and a hold with no expiry |
| `WorkspaceService` | `list`, `find_by_name`, `find_template`, `create_workspace`, `start`, `stop`, `delete`, `await_build`, error mapping with the token redacted | A status that does not block. A way to push the autostop deadline forward |
| `SshRunner#exec` | Runs a command over `coder ssh`, with `stdin_data:` | Nothing. It is used as it is |
| `HealthCheck` | `probe` over SSH: reachable, or sick with a reason. `reachable` is evidence only that the box answered | `observe` for a runner environment that is not heard (§7.2) |
| `QuarantineService`, `DeadWorkspaceReaper` | Quarantine marks a sick pool box so the allocator passes over it. The reaper deletes pool workspaces under the prefix whose agents are gone, with no live lock, twice sighted | Nothing. Quarantine is internal to the probe inside `allocate` and a consumer knows nothing about it (13). A held workspace is never reaped, and a hold with no expiry is always live (§4.5) |
| `TokenService`, `IntegrationService` | URL, token, redaction, and `test` (a rejected token marks the integration `error`) | `check_health` calls `IntegrationService#test` |
| `RepoBootstrap` | Clones repositories onto a leased workspace | Not used. `SessionContextService` clones inside the session container, as on every runner |

**What moves into `app/services/coder/`.** Three things the runner needs are done today by the session path in its own code. They move so that both consumers use one copy:

1. The classification of a workspace's last build (a succeeded `start` is running, a `start` in flight is starting, anything else needs a start). It is in `Allocator#ensure_started` and again, differently, in `DeadWorkspaceReaper`. It becomes `Coder::WorkspaceStatus.from(workspace_hash)` with `state` (`building`, `running`, `stopped`, `deleting`, `deleted`, `failed`), `agent` (`connected`, `disconnected`, `none`) and `deadline` (the autostop time, or nil). `HealthCheck.agents_unhealthy?` and `unhealthy_reason` stay where they are and `WorkspaceStatus` calls them.
2. The explanation of a refused request (`with_coder_explanation` in `WorkspaceService`) is reused as it is, and gains one more distinction: a refusal for quota raises `WorkspaceService::QuotaError < OperationError`. Its status and body shape are unverified, so 17b records them on staging (§15). An unrecognised refusal stays an `OperationError`.
3. The lock's ownership predicate (`value ->> 'terminal_session_id' = ?`), repeated in five methods of `LockService`, becomes one `Holder` (§4.1).

## 3. Approach

**Chosen.** The runner is a consumer of the integration's services. It asks the integration for a machine (`allocate`), runs commands on it (`SshRunner`), and asks the integration to delete it. It never calls Coder directly and never decides which workspace it gets. The state of an environment stays in `runner_environments` and advances one idempotent step per call, from the places that already retry: the `create_container` and `start_container` phases of `ContainerWorkflowV2`, and a minutely reconciler. No step holds a long wait.

| Alternative | Rejected because |
| --- | --- |
| The runner calls Coder directly through `Coder::Api` and keeps its own hold (round 1) | A second copy of the lock, the exclusion rule and the template choice. Alex's direction of 2026-11-26 asks for the services |
| A create-only `provision` that never takes a free workspace (round 2) | Alex decided the runner takes machines through `allocate`, and that the integration decides what it gives (3, 15) |
| Provision, build and install inside one activity (`create_container` waits for the runner) | A cold build plus an image pull outlasts the phase's 300 s `start_to_close_timeout`, and a retry would repeat the work. `capacity_wait` is the platform's wait already |
| A Temporal workflow per environment | A second orchestration layer for state that is a row and a few API calls |
| A hold with an expiry that a reconciler renews (round 2) | Alex decided on an explicit hold with no expiry (9). It removes the renewal and the outage window |
| `busy` as a state (DESIGN.md §5.2 as drawn) | `manual` derives it from the hold (`RunnerEnvironment#busy?`), and the patterns document names that predicate. A second source of truth would drift |

## 4. Changes to the Coder services

All of this is 17b. It is a task of its own because it changes what the agents' `coder_*` tools use in production, so its staging check includes an agent session that uses `coder_*` as before (§14).

### 4.1 Who holds a lock

`Coder::LockService::Holder = Data.define(:kind, :id)`, with `Holder.session(id)` and `Holder.environment(id)`. The row's `value` keeps `terminal_session_id` for a session holder, so every row written before this change stays valid, and gains `runner_environment_id` for an environment holder. `acquire`, `touch`, `release_owned`, `held_by_session?` and `release_for_session` take `holder:` where they take `terminal_session_id:` now, and one private method builds the `value ->> '<key>' = ?` predicate. The three Coder tools and `Coder::Allocator` pass `Holder.session(session.id)`. `release_all_for_session` and its `IntegrationCleanupService` hook stay, and release session holders only, so ending a terminal session never releases a runner's workspace. A new `held_by(holder:)` returns the workspace a holder holds, which makes `allocate` idempotent for it (§4.3).

`Coder::Allocator.new(integration:, terminal_session:, …)` takes `holder:` in place of `terminal_session:`. The hosted behaviour and its tests do not change.

### 4.2 An explicit hold

A hold of an environment holder is **explicit**: `acquire(…, explicit: true)` writes the row with `expires_at` NULL. It has no expiry and no renewal. The existing expiry check (`expires_at IS NOT NULL AND expires_at <= now`) never reclaims it, `touch` is not called for it, and `live_locks` counts it. It ends in two ways only:

- the runner deletes the workspace (§9), and the integration releases the hold when Coder reports the workspace `deleted`;
- the reconciler releases the hold of an environment that is `gone` (§11), which covers a delete that finished while the platform was not looking.

A platform outage longer than an expiry would have been is not considered: there is no expiry.

### 4.3 Allocating without waiting for the build

`Coder::Allocator#allocate(holder:, wait: true, note: nil, …)`. With `wait: true` it is today's method. With `wait: false` it does the same work and returns at once with `status: "starting"` for a workspace that is building or stopped, instead of calling `await_build`:

- It first returns the workspace `held_by(holder)` already holds, if any. A retried step, or one that crashed between the allocation and the write of `external_id`, gets the same workspace.
- Otherwise it takes a free workspace of the pool, or creates one from the integration's default template, as it does for a session. The integration decides, by its own logic, and the runner has no say in it.
- A candidate that is already running is probed over SSH as today; a sick one is quarantined and passed over, inside `allocate`. A candidate that is building or stopped is locked and returned `starting` without a probe, because there is nothing to probe yet. The runner's own checks (§8.2) cover it: when they fail, the environment is failed and the workspace deleted.
- A stopped candidate is started with `WorkspaceService#ensure_started_async` (a `start` build, no wait). The blocking `ensure_started` is rebuilt on it plus `await_build`.
- When it has nothing to give (`ExhaustedError`, a quota refusal) it raises `Coder::Allocator::ExhaustedError` with the integration's message. §5.1 turns that into `capacity_wait`.
- Under #294 the template and the prefix of every integration are required, so the integration can always create a workspace and `ExhaustedError` means quota or a provider limit. Today an integration without them may have nothing to give, and its sessions wait with the integration's message (1).

`allocate` has **no create-only mode** (15).

`Coder::WorkspaceService` gains `status(name)` → `WorkspaceStatus` (one `GET`), `ensure_started_async(workspace)`, and `extend_deadline(workspace, to:)` (§4.4).

### 4.4 Pushing the autostop deadline forward

A template stops a workspace some hours after it starts (our staging template: 3 hours). Coder moves that deadline only when someone connects through Coder (SSH, an IDE), and the runner never does. So while a session runs the integration pushes the deadline forward (10, 12):

`WorkspaceService#extend_deadline(workspace, to:)` calls Coder's API for the workspace's deadline. The candidate call is `PUT /api/v2/workspaces/{id}/extend` with a `deadline`; 17b checks on staging which call works, and records its refusals (a template whose maximum deadline is exceeded, a workspace with no deadline). The reconciler (§11) calls it for every environment held by a session, once a minute, **only when the deadline in `WorkspaceStatus` is less than `Settings.runners.autostop_margin_minutes` (30) away**, and extends it to `autostop_extend_minutes` (60) from now. A refusal is recorded on the environment (`runner_environments.autostop_error`, §6) and makes the runner `degraded` with the message (§7.3); a success clears it. An idle warm workspace is **not** extended: it stops by its template, and the next acquire starts it again (§5.1 step 2).

### 4.5 The pool exclusion rule is dropped

Round 1 hid runner workspaces from the hosted pool by matching names against `runner_environments`. With the lock, it is not needed:

- `Coder::Allocator#allocate` locks each candidate and passes over one that is held (`LockNotAcquired`).
- `DeadWorkspaceReaper` deletes only a workspace with **no live lock**, and an explicit hold is always live.
- The lock is taken in the same call that chooses or creates the workspace (§4.3).

What remains is a window of a few milliseconds between the create and the lock, which `Allocator#create_and_lock` already has for the hosted pool. Dropping the rule removes a `WorkspaceService#list` filter, a scope on `RunnerEnvironment` and a table match on every listing. A runner needs no workspace-name rule either: the integration names its workspaces.

### 4.6 Deleting a workspace through the integration

`Coder::Allocator#delete(holder:)` deletes the workspace `held_by(holder)` holds (a `delete` build through `WorkspaceService#delete`) and releases the hold when Coder reports it `deleted`. It returns `:pending` while the build runs, `:gone` when done, and `:gone` for a workspace Coder no longer knows. It is the only way the runner removes a machine (§9.3). A delete refused by Coder raises `WorkspaceService::OperationError`, and the runner retries it (§11).

### 4.7 The template, the pool's free workspaces, and what `fresh` means

**The template is the integration's.** The integration's `default_template` setting is the one every runner on it builds from, as the hosted pool grows from it. The runner has no template, version policy, version or parameters. What the integration does when it has no default template is the integration's own logic (§4.3), and #294 removes the case by making the template and the prefix required. A template that builds from required parameters it has no default for fails at the create with Coder's own message, which fails the environment (§7.2): the integration's default template is where that is fixed.

**A runner may get a free workspace of the pool.** This is accepted (15). The consequences, decided:

- `fresh` guarantees that a session sees **nothing of earlier runner sessions**, because the workspaces of earlier sessions are deleted after use. It does not guarantee that the workspace is one the runner has never used in any way: `allocate` may give a free workspace of the integration's pool that the runner never used. The user guide says so.
- The runner deletes what it was given, as the integration's `delete` does (7). A pool workspace that a runner took is deleted when the session ends (`fresh`), when its environment fails, or when it is revoked or the runner is deleted.
- `max_environments` counts the runner's environments, whatever the origin of their workspaces.
- **Where the pool is shared.** An integration that serves hosted sessions as well as runners shares its pool and quota with them, and until #295 a project's Coder tools and a Coder runner are on the same integration (see the facts in the header). Keeping the integration used by runners apart from the one used by agent tools is the customer's job, not the runner's (6).
- **`fresh` on an integration without a template** empties its pool: each session takes a free workspace and deletes it. This is accepted, and #294 removes the case (5).

## 5. `Runners::Allocator`

`app/services/runners/allocator.rb`. It owns the environment row and the hold, for every type. `Runners::Machines` keeps what is specific to `manual`: `return_to_service!`, `settle_resets!`, the launch availability and its messages.

```ruby
Runners::Allocator.acquire!(session)            # => RunnerEnvironment (held, ready), or raises
Runners::Allocator.release!(environment, session, failed:)
Runners::Allocator.let_go!(session)             # the runner is revoked: the hold goes, no outcome counted
Runners::Allocator.fail!(environment, reason, holder: nil)
```

`RunnerRuntime`, `Revocation`, `ContactLoss` and `CheckIn` call these instead of the same methods on `Machines`. 17c moves them; the `manual` behaviour and its tests do not change.

### 5.1 `acquire!`

Idempotent for a session: a session that holds an environment gets it back (a retried `create_container`), as `Machines.acquire!` does. Otherwise, in one transaction that first locks the runner row `FOR UPDATE` (the order is runner, then environment, as every issuer and the revoker use. A provisionable runner takes the runner row `FOR UPDATE`, because the count of step 3 must be serial; a `manual` runner keeps the `FOR SHARE` that `Machines` takes, so its behaviour does not change, §14):

1. **An idle, heard environment** of this runner, lowest id first, `FOR UPDATE SKIP LOCKED`. The hold (`current_session_id`) is set. (Affinity and project binding are out of the plan, DESIGN.md §7.3 steps 1 to 3.)
2. **On a `provisionable` runner, an idle environment that is not heard** and is held by no session, taken under the same lock: its workspace was stopped (a template autostop) or its runner service is down. The hold is set and the environment is revived (`restart`, §6). This keeps a warm workspace useful after the template stopped it.
3. **On a `provisionable` runner, with `count(environments not gone) < max_environments`** (null means `max_concurrency`): insert a row in `requested`, `origin: allocated`, `key` a platform-made identifier unique in the runner (`coder-` and 8 hex), held by the session. The workspace is chosen later, by `provision`. `tearing_down` and `failed` rows count until they are `gone`, so a slow delete cannot let the pool grow past its limit. `max_environments` limits the runner's machines, not concurrency (D12).
4. Otherwise raise `ContainerRuntime::CapacityError` with `reason: "runner_capacity"` (§10). The same error, with the integration's own message, comes out of `provision` when `allocate` raises `ExhaustedError` (§7.2): the integration has nothing to give. On `manual` only steps 1, 4 and the offline rules of DESIGN.md §7.3 exist, unchanged.

After the transaction commits, a row that is not `idle` is advanced once (`Runners::Provisioning.advance!`, §5.2), and `acquire!` raises `Runners::Allocator::Pending`, a `CapacityError` subclass with `reason: "runner_provisioning"`, until the environment is `idle`. The activity treats it as any `CapacityError` (`AdmittedPhaseActivity`, `capacity_wait`): it keeps the reservation, records the wait reason and message on the admission, and the workflow tries again 30 s later (`CAPACITY_RETRY_INTERVAL`). No new workflow code.

`runner_provisioning` (D3, accepted) joins `SessionAdmission::WAIT_REASONS` and `LAUNCH_WAITS`, and `launchStatus.ts` shows "Starting a workspace" with the message beneath. It is not `runner_capacity`, because the session page would say "Waiting for a free machine" while the platform builds one for it.

### 5.2 `Runners::Provisioning.advance!(environment)`

One step per call, under the environment's row lock, decided by its state. Each step is idempotent, because Temporal retries and two callers (the session's phase and the reconciler) may race:

| State | Step |
| --- | --- |
| `requested` | `adapter.provision(env)`: `Coder::Allocator#allocate(holder:, wait: false)` (§4.3). Writes `external_id` (the workspace's name) and `boot_started_at`, fires `begin_provision`. `ExhaustedError` leaves the row `requested` and the retry asks again; a row that waited longer than `bootstrap_timeout` is deleted (it holds nothing) |
| `provisioning` | `adapter.prepare(env)`: `:pending` while the build runs or the agent is not connected. On `:ready`, `adapter.inject_bootstrap(env)` (§8) and fire `finish_build` (`booting`) |
| `booting` | Nothing to do: `register` and the first check-in move it (§8.4). If `boot_started_at + Settings.runners.bootstrap_timeout` has passed, `mark_failed` with the message of §11 and raise `Runners::ProvisionError` |
| any other | none |

The HTTP and SSH calls run outside the allocator's runner lock, and the row is re-read and saved under its own lock after each. A `ProvisionError` (the template refused, the build failed, the VM check failed) fires `mark_failed` with the message and propagates; the environment is then torn down and its workspace deleted (§9.3). `RunnerRuntime#create_container` turns it into a `CreateRefusedError`, so the phase fails with the diagnosis and the cleanup frees the hold (§10).

`Settings.runners.bootstrap_timeout` is one setting, 900 s (D5).

## 6. The provisioned arm of the environment state machine

`RunnerEnvironmentStateMachine` gains the states and events below. It stays AASM with `whiny_persistence`, and nothing writes `state` past it (implementation-patterns, Anti-Patterns).

```
requested ─begin_provision─▶ provisioning ─finish_build─▶ booting ─check_in─▶ idle ◀─finish_reset─ resetting
                                                             ▲                │  ▲                     ▲
                                                             └──── restart ───┘  └── begin_reset ─────┘
 any state but gone ── mark_failed ──▶ failed ── begin_teardown ──▶ tearing_down ─finish_teardown─▶ gone
 idle | resetting | booting | provisioning | requested ── begin_teardown ──▶ tearing_down
 unregister (per-machine Revoke, runner Revoke) ──▶ gone                          (as on manual)
```

- `idle` is free when no session holds it and busy when one does. `RunnerEnvironment` gets `in_service?` (`registered` or `idle`) and the `free` scope reads it, so `Allocator`, `Resolver`'s availability and the `manual` code share one definition of "can take a session".
- `registered` stays the `manual` state. The two arms never mix: a `manual` environment is created `registered`, an allocated one `requested`, chosen by `origin`.
- `failed` on a provisioned environment is not a resting state. The reconciler (§11) tears it down (the workspace is deleted), and the allocator takes another machine on demand. This is the **rebuild** (D4, accepted): retire-and-replace, a new key and a new row. `Adapter#reset(level: :rebuild)` is not built. The `rebuildable` capability stays `true` for `coder`, and the runner page's Rebuild action calls `begin_teardown`.
- `restart` (`idle → booting`) revives a stopped or silent workspace (§8.5).
- `check_in` is `booting → idle`, fired by the first check-in after `register` (§8.4). It is not fired by `register`, so an environment is never `idle` before its preflight is reported.
- `unreachable` stays an overlay (DESIGN.md §5.2): a silent `idle` or `busy` environment is shown offline and skipped by the allocator.

**Schema (17c).** `bin/rails generate migration` (never by hand): `runner_environments.external_id` (string, null; the Coder workspace's name, unique per runner where not null), `runner_environments.boot_started_at` (datetime, null), `runner_environments.autostop_error` (string, null; the last refusal to extend the autostop deadline, §4.4, first read by `check_health`, §7.3, in 17d), and `origin` accepts `allocated`. Each has its first reader in this task. `reusable` of §2.2 is not added: `reuse_policy` is read from the runner at release. No backfill: nothing allocated exists.

## 7. `Runners::CoderAdapter`

`app/services/runners/coder_adapter.rb`, `Adapter` subclass. Stateless; every method is idempotent on the environment, and none calls Coder except through the integration's services (§4).

### 7.1 Config

`ConfigSchema` keys for `coder`: the `container.*` keys only. `on_release` (7), `template_id`, `template_version_policy`, `template_version_id`, the `parameters` key and the `if/then` rule of `for_type("coder")` are removed. The runner's `integration` (already validated by `Runner#integration_usable`, DESIGN.md §2.6) is how it names Coder.

### 7.2 The methods

| Method | Behaviour |
| --- | --- |
| `capabilities` | `provisionable: true`, `rebuildable: true` |
| `provision(env)` | `Coder::Allocator#allocate(holder: Holder.environment(env.id), wait: false)`. Writes the workspace's name to `external_id`. `ExhaustedError` raises `ContainerRuntime::CapacityError` with the integration's message (§5.1); a refusal of Coder for the create (the template needs a parameter, a build error) raises `ProvisionError` with Coder's `message (detail)` text |
| `prepare(env)` | `WorkspaceService#status`: `building` → `:pending`; `stopped` → `ensure_started_async` and `:pending`; `running` with the agent `connected` → `:ready`; `running` with the agent still connecting → `:pending`; `failed` → `ProvisionError` with the build's error |
| `inject_bootstrap(env)` | §8.2 and §8.3 |
| `reset(env, level: :reset)` | The `env.reset` runner op (`Runners::Operations.enqueue_reset!`), as `Machines.return_to_service!` does. `level: :rebuild` raises `Runners::UnsupportedOperation` |
| `teardown(env)` | `Coder::Allocator#delete(holder:)` (§4.6, §9.3). `:pending` until the workspace is deleted, then `:gone` |
| `observe(env)` | `:running` while the environment is heard, with **no call**, as `ManualAdapter#observe`. Not heard: `status` → `:stopped`, `:missing` (404 or `deleted`), and for a running workspace with the agent connected, `HealthCheck#probe`: reachable means the box is up and the runner service is down (`:running`), not reachable means `:unknown`. `:unknown` also when Coder cannot be asked |
| `check_health(runner)` | §7.3 |
| `launch_refusal(runner)` | §10 |

**When the runner's own part fails** (the checks, the install, a session that breaks its machine) the runner fails its environment with the message and asks the integration to delete the workspace (§9.3). It does not quarantine: quarantine belongs to the integration's own probe inside `allocate` (4, 13).

### 7.3 `check_health`

`Runners::HealthCheck` already runs every minute for every live runner and applies the adapter's `Health` (status, reason). The runner's health checks **the integration only** (2). The coder adapter returns, in order:

1. The integration is `inactive` or `error` (a column, no IO): `unreachable`, `Coder integration "<name>" is <inactive | in error: <settings.error>>. Reconnect it, or pick another runner.` This is DESIGN.md §2.6's rule, and it needs no Coder call.
2. Otherwise, **at most once every 5 minutes** (the stamp is `runners.health["checked_at"]`; in between the last result is returned unchanged): `IntegrationService#test` (the token). Refused: the integration becomes `error` and the runner `unreachable` as in 1. Coder unreachable: `unreachable` with the reason.
3. An environment of the runner has an `autostop_error` (§4.4): `degraded`, with the message ("Coder refused to extend the autostop of workspace X: …").
4. The last `Settings.runners.max_consecutive_failures` allocated environments all `failed` while provisioning or booting: `degraded`, `Provisioning has failed N times in a row: <last reason>`. This is the signal for a template that cannot build or a machine that cannot install.
5. Otherwise `connected`.

Nothing about the template (that it exists, its version, its parameters) and nothing about the workspace name is checked: both are the integration's.

`status_reason` is capped at 255 characters, as `ManualAdapter` caps it.

## 8. Delivering `aixle-runner`

No new runner command, no new credential kind and no new form of `check-in`. The runner binary does not change for item 17.

### 8.1 The token, bound to the environment

`Credentials.mint_registration!(runner, created_by: nil, environment: nil)`: for a `coder` runner it requires `environment:` (an `allocated` environment of that runner, in `provisioning` or `booting`) and stores it in the credential's `runner_environment_id`. A `manual` runner's token is unchanged (no environment, one machine per use). It is minted under the runner's lock like every issuer. Minting a token for an environment revokes its earlier unused registration tokens, so one live token exists per environment. Its expiry is the existing `REGISTRATION_TTL` (1 hour), longer than `bootstrap_timeout`.

### 8.2 The checks, then the install

`CoderAdapter#inject_bootstrap` runs two commands over `Coder::SshRunner#exec(workspace_name: env.external_id, …)`, so the integration's token, the redaction and the `coder` CLI handling are the integration's:

1. **The VM check and the privilege check**, one short command. It exits with a distinct code, and the adapter turns each into a `ProvisionError` with a message for people:
   - the workspace is a container or a pod (`systemd-detect-virt --container` reports one, or `/.dockerenv` exists, or `KUBERNETES_SERVICE_HOST` is set): "This workspace is a container or a pod. Aixle coder runners support virtual-machine workspaces only";
   - not root and `sudo -n true` fails: "The workspace gives neither root nor passwordless sudo, which the runner service needs";
   - no `systemctl`: "The workspace has no systemd, which the runner service needs".
   This is DESIGN.md §2.6's rule, run by the platform. The runner has no preflight for it, and a `manual` runner is unaffected. Decision 4 of task 8b stays: a Docker daemon that cannot see the runner's files is found by Docker's refusal of the sidecar's bind mount, as built.
2. **The install**: `Runners::MachineInstallScript.render(version:, gateway_url:, digests:)` (the same module and pins as `GET /runner/v1/machine-install.sh`, #288) is piped on stdin: `sh -s -- --token <token> --name <external_id>`, run through `sudo -n` when the user is not root. The script picks the architecture, downloads from `/runner/v1/releases/:version/:platform`, checks the SHA-256 against the pin, and runs `configure`, `service install` and `service start`, as it does for an operator. A mismatch stops it before anything runs, with the script's own message, which the adapter keeps as the bootstrap output.

The token is in argv for the few seconds before it is spent. Accepted (Alex, 2026-11-26): it is single use and spent at once. The adapter redacts the registration token from the output it keeps and logs. `SshRunner` redacts only the integration's own token, and is not changed.

**Idempotence.** `advance!` mints a token only for an environment with no unspent one. If the environment's token is already spent when the step runs again (the SSH call broke after the script ran `configure`), the install is not sent twice: the step moves to `booting` and waits for the check-in.

### 8.3 The runner is a system service

The workspace must give root or passwordless sudo, and `machine-install.sh` runs as it is (`configure`, `service install`, `service start`). There is no `service install --user` and no user-level unit. The runner needs Docker, and membership of the `docker` group is root-equivalent, so the requirement adds nothing the runner did not already need. The user guide states it (§12). A template whose user cannot sudo fails with the message of §8.2, and the workspace is deleted (§9.3).

### 8.4 `register` fills the row

`Runners::Registration.register!(credential, …)` today creates a `registered` environment. When the credential names an environment, it fills that row instead, under the runner's lock and the row's:

- the environment must be `allocated`, of the credential's runner, in `provisioning` or `booting`; otherwise `invalid_token`;
- it records `display_name` (the `--name`, which is the workspace's name), os, arch, facts, `auto_update`, versions and `first_seen_ip`, and the token is spent;
- its state becomes `booting` (from `provisioning`, if the install call had not returned yet) and it stays so;
- the credential pair is issued as for a `manual` machine.

The runner then checks in at its start (`runner/internal/cli/machine.go`). `CheckIn.check_in!` fires `check_in` (`booting → idle`) when the preflight reports nothing wrong, and `fail_for_preflight!` fails it otherwise, the failure being the reason, as it does for `manual`. For an allocated environment `fail_for_preflight!` calls `Allocator.fail!`, not `Machines.fail!`.

Credentials of a provisioned environment are invalid when it leaves `idle` and `resetting` for `tearing_down` or `failed`, and when it is `gone` (§9.3). `RunnerGateway::V1::ApplicationController` refuses those states for an `allocated` environment (a `failed` `manual` machine keeps its credentials so Return to service can reach it; a failed provisioned one never needs to).

### 8.5 A revival

A stopped workspace that is started again may or may not have kept its runner service, depending on its template's disks. The platform does not rely on it. A revival (`restart`, from §5.1 step 2 or the reconciler) revokes the environment's credential family, mints a new token bound to the same row, fires `idle → booting` and runs §8.2 again. `register` fills the same row. A workspace that kept its service starts a runner with revoked credentials, which fails its calls and is replaced by the re-install. `machine-install.sh` on a machine that already has the service is re-run as it is; if it refuses that case, 17d settles the one-line change (§15, "To check").

## 9. Release

What happens to a workspace is fixed (7). There is no `on_release` setting and nothing is handed back to the pool.

### 9.1 `reuse_policy`

Read from the runner at release, so an edit applies from the next release. `reuse` and `reset` only decide **how a machine is cleaned between sessions**, as DESIGN.md §7.1 and §7.2 say: a scrub, a reset, and a rebuild after a failed scrub (container mode only for `reset`). They do nothing else to the Coder workspace. `fresh` gives each session a workspace of its own and deletes it after the session.

### 9.2 What happens when the session ends (`cleanup_session`, then `Allocator.release!`)

| Environment when the session ends | What happens |
| --- | --- |
| `requested`, `provisioning`, `booting` (never started) | The hold is cleared; no op is sent. The environment keeps booting as a warm one (`reuse`, `reset`), or is torn down (`fresh`) |
| `idle`, `reuse` | `container.stop`, `env.scrub`, hold cleared. A failed scrub is followed by `env.reset`, as on `manual` |
| `idle`, `reset` | `container.stop`, `env.reset`, hold cleared |
| `idle`, `fresh` | `container.stop` (best effort), hold cleared, `begin_teardown` (§9.3). No scrub: the workspace is deleted |
| Any, and the scrub or reset failed, or the session is the `max_consecutive_failures`th failed one in a row | `mark_failed`, hold cleared. The reconciler tears it down (§9.3), which deletes the workspace, and the next acquire takes another machine. A `coder` environment does not stay `failed`: nobody can fix a machine we were given, and Return to service is `manual`-only (`Machines::NotManual`, as built) |

### 9.3 `teardown`: the workspace is deleted

`teardown` always deletes: it calls `Coder::Allocator#delete(holder:)` (§4.6) once the environment is `tearing_down`. It happens in four cases and no other:

- `fresh`, after the session;
- a broken machine (a failed check, install, preflight, scrub or reset, or a boot timeout): the environment is failed with the message, then torn down;
- an environment revoked from the runner page;
- the runner deleted (or revoked): every environment that is not `gone` is torn down.

The environment is `gone` when Coder reports the workspace deleted, and the integration then releases the hold. The reconciler releases the hold of any `gone` environment that still has one (§11). The credentials of the environment are revoked at `tearing_down` (§8.4), so a runner that is still alive on a workspace being deleted calls nothing. The cleanup of a workspace to hand it back (round 2's §9.3) is **not built**.

## 10. Sessions: how the allocator and the release fit `Sessions::Lifecycle`

**`create_container`** (`RunnerRuntime`): `Allocator.acquire!(session)`, then `container.start` once the environment is ready, as today. `Pending` and `CapacityError` reach `capacity_wait`. A `ProvisionError` becomes a `CreateRefusedError`: the phase fails with the message and the session ends through the usual path. The admission's `runtime_id` is persisted before the phase (`AdmittedPhaseActivity`), so the cleanup always runs.

**`start_container`**: unchanged, a `status` loop. The environment is already `idle`.

**The admission slot** (D12, accepted). Concurrency counts running sessions. A machine being deleted holds no admission slot, and `max_environments` limits the runner's machines, not concurrency. `Allocator.release!` clears the hold at the end of cleanup and the session's admission is released as today, after `Sessions::Lifecycle.finalize`. The rule for an unreachable machine stays (DESIGN.md §10): its slot is held until the machine is heard and reset, because the session's container may still be running there. A `coder` environment the platform lost contact with is in this case until it is heard again and reset, or `gone`.

**Lifecycle rules.** The allocator and provisioning never write a session's state. Where an environment fails under a live session (§11) the caller is the reconciler or the dead-container scan, and it uses `Sessions::Lifecycle.fail_if(session, error_message:)`, as `Runners::ContactLoss` and `Runners::Revocation` do. The `terminal_sessions.runner_environment_id` write stays the one `Machines.take!` makes today.

**Interactive sessions** (#277) work as on `manual`: the runner on the workspace opens the tunnel, the relay maps the session to the environment through the hold (`RunnerEnvironment`'s `after_save` signal), and the browser path is unchanged. The coder-specific requirement is egress from the workspace to the relay host (DESIGN.md §12.5).

**Launch refusals** become polymorphic. `Runners::Resolver` calls `Machines.availability(runner)`, which is `manual`'s. `Adapter` gets `launch_refusal(runner)` (nil, or `Refusal(reason, message)`), declared on the base with no default. `ManualAdapter` delegates to the existing availability code; `CoderAdapter` refuses an `unreachable` runner with `runner_unreachable` and §8's message ("Runner "X" is unreachable: <the health reason>"), which names the integration. A `degraded` runner is admitted.

## 11. The failure paths of §8 on `coder`

`Runners::Reconciler` (`app/services/runners/reconciler.rb`) runs every minute, as a new activity in `runner_health_check_workflow` after the health check. Each rule works on one provisioned environment and is idempotent; one that fails is logged and does not stop the others.

| Condition | Detected by | Outcome |
| --- | --- | --- |
| **Provisioning fails** (template refused, build failed) | `provision`/`prepare` raise `ProvisionError` | `mark_failed` with Coder's message. A session holding it fails with that message. The reconciler tears the environment down (the workspace is deleted) |
| **The workspace is a container or a pod, or gives no root or sudo** | The checks of §8.2 | `mark_failed` with the message of §8.2, and the workspace is deleted (§9.3). No quarantine (4). The streak of §7.3 rule 4 counts it. A session holding it fails with that message |
| **Build times out** | `boot_started_at + bootstrap_timeout`, in `advance!` and in the reconciler for an environment no session is advancing | `mark_failed`, teardown; the session fails with the message below |
| **No check-in within `bootstrap_timeout`** | Same rule, `booting` | "Workspace started but aixle-runner did not check in within 15 min. Check that the workspace can reach <platform host>:443." plus the install script's last output (§8.2). `failed`, then teardown |
| **Workspace stopped or gone under a session** (a spot reclaim, as `DeadWorkspaceReaper` describes: the build is a succeeded start and every agent is `disconnected`) | `ScanDeadContainersActivity` calls `observe` for a machine it does not hear. `:stopped`/`:missing` now count as dead: the scan's two-sighting `confirm_or_mark` fails the session with "Workspace stopped or deleted by Coder (a spot reclaim, or a template autostop)" | The session fails after the scan's confirmation (about 3 minutes), not the 15-minute grace. The environment is `failed`, then torn down. `observe` returning `:running` changes nothing: it falls to the grace (`ContactLoss`), the evidence the reaper's doctrine asks for |
| **Autostop under a running session** | The reconciler's deadline check for every environment held by a session (§4.4) | The deadline is pushed forward. A refusal is recorded as `autostop_error` and the runner is `degraded` with Coder's message. The session is not touched: if the workspace stops anyway, the row above applies |
| **An idle warm workspace stopped by its template** | `observe` `:stopped` for an idle environment that is not heard | Nothing is done until the next acquire, which starts it again and re-installs (§5.1 step 2, §8.5). The reconciler does not start idle workspaces |
| **Runner service down, workspace up** | An `idle` or `busy` environment not heard for 5 minutes with `observe` `:running` | The reconciler revives it (§8.5), once every 5 minutes. A session's container keeps running on the VM (DESIGN.md §6.7), so a restarted service picks it up. If it is still not heard after `ContactLoss::GRACE`, the session fails by the grace and the environment is `failed` |
| **The integration's token is revoked** | `check_health` (§7.3) every 5 minutes; any adapter call that gets 401/403 calls `IntegrationService#test` | The integration is `error`, the runner `unreachable`, launches are refused with the integration named. Running sessions continue: the runner talks to the platform, not to Coder. A session waiting in provisioning fails with "Coder integration "X" rejected its token. Replace the token." Teardowns that cannot reach Coder stay `tearing_down`, retried every minute, and count toward `max_environments` until the token is replaced |
| **The integration has nothing to give** (its quota is reached, its pool and limits are used, the provider is out of capacity at create) | `allocate` raises `ExhaustedError` | `capacity_wait` with `runner_capacity` and the integration's own message, the reservation kept, admission otherwise unchanged (§5.1). A failed build is a diagnosed failure of that session, and it counts in the streak that makes the runner `degraded` (§7.3 rule 4). Parsing provider errors for "out of capacity" is deferred |
| **Runner revoked or deleted** | `Runner`'s `after_save` already ends its sessions (`Revocation.end_sessions!`) | It also `begin_teardown`s every environment that is not `gone`, best effort, which deletes the workspaces. The reconciler finishes them. The runner page lists any that Coder would not delete ("must be removed by the customer") |
| **Disabled** | | No new sessions; environments are left. Running sessions finish |
| **Environment revoked from the runner page** | `Registration.revoke!` | Credential family revoked, `begin_teardown` first for a provisioned environment, `gone` when the workspace is deleted |
| **A `gone` environment still has a hold** | The reconciler's sweep | The hold is released (`LockService#release_owned`) |

The reconciler never acts on: an environment held by a session that has not ended and is heard (except the deadline push); any workspace that is not an environment's `external_id`; and, per the reaper's cap, more than `Settings.runners.max_teardowns_per_run` (default 3) workspace deletions in one pass. A provider outage that fails every build at once must not empty a pool in a single sweep.

## 12. UI and API surface

No new feature flag (17). The type is behind `external_runners` as the rest of the runners are, and `coder` becomes visible and creatable only in 17e, the last task, so nobody sees it before the work is done. `Runners::Adapter::REGISTRY` gains `"coder"` in 17e, not before.

- **Form.** Step 2 for `coder`, generated from `ConfigSchema.for_type("coder")` as for `manual`: **the integration select** (the project's visible active Coder integrations, DESIGN.md §2.6), the `container` options, `reuse_policy` (all three, with DESIGN.md §7.1's wording), and `max_environments` (step 3). No template, version, parameter or `on_release` fields. Beside the select, a line says that the integration's pool and quota are shared with the agents' Coder tools of the project and that the workspaces come from the integration's default template. "Connect" runs the config checks and `Runners::HealthCheck.check!` inline. `Runners::Save` and the controllers already refuse a type with no adapter; adding the adapter lifts "not available yet". No templates endpoint is needed.
- **Company runners.** A Coder integration is per project, so no integration is eligible for a company runner (DESIGN.md §2.6 asks for a company-wide one). The `coder` card is offered when creating a project runner only. A company-wide Coder integration is not part of this design (§17).
- **Runner page.** The Machines section becomes **Environments** for `coder`: key, state (`requested`…`gone`, with the reason), the session it holds (link), last heard, runner version, workspace link to Coder, and the actions Rebuild (`begin_teardown`) and per-environment Revoke (both delete the workspace). The overview adds the integration. A `manual` runner's page is unchanged. The runners list shows "environments busy/total" with `Runner#machine_counts` extended to a provisioned runner, counting every environment not `gone`.
- **Integration removal.** `IntegrationsController#destroy` keeps refusing while a runner references the integration (`dependent: :restrict_with_error`), and its message names the runners. Delete the runner first, which revokes and tears down.
- **Docs.** The user guide and its portal mirror (`docs/user-guide/` and `app/frontend/pages/Docs/data/pages/`): that a coder runner takes machines from the integration (a free workspace of its pool, or a new one from its default template); that `fresh` means a session sees nothing of earlier runner sessions; the requirements on the machines (a virtual machine, root or passwordless sudo, systemd, Docker); that workspaces are deleted by `fresh`, a broken machine, revoke and delete; the autostop behaviour; keeping the runners' integration apart from the agents' is the customer's job; and the egress the workspace needs.

## 13. Testing approach

Tests follow the area's conventions: Minitest and FactoryBot, no fixtures, sequences in factories (`test/factories/runners.rb` and `runner_environments.rb` get `:coder` and `:allocated` traits). Coder is stubbed at the HTTP layer with WebMock, as `test/services/coder/` does. `SshRunner` is passed to the adapter as a dependency (as `Coder::HealthCheck` takes one), never stubbed with a block returning a fake object. Concurrency tests copy `machines_concurrency_test.rb`. The `Runners::Allocator` public contract is tested for a `manual` runner too, so the move is covered before any Coder code exists. The per-task tests are in §14.

## 14. The split of item 17

Round 2's seven tasks are now four (16). Each is cut when the one before has merged, against the code as it is then, as §15 of DESIGN.md says. All are behind `external_runners`, with no new flag (17). The `coder` type becomes creatable only in 17e. 17b and 17c do not depend on each other and may be cut in either order. The runner (Go) does not change in any of them.

| Row | Delivers | Tests | Staging check | Item 18 (DESIGN.md §12.5) needs from it |
| --- | --- | --- | --- | --- |
| **17b** The Coder services for a second consumer | `LockService::Holder`, `held_by`, and explicit holds (`expires_at` NULL) (§4.1, §4.2); the three tools passing `Holder.session`. `Allocator#allocate(wait: false)` (§4.3). `Coder::WorkspaceStatus` extracted from `Allocator` and `DeadWorkspaceReaper`. `WorkspaceService#status`, `ensure_started_async`, `extend_deadline`, `QuotaError`. `Allocator#delete(holder:)` (§4.6). No runner code | The hosted suites (`allocator_test`, `lock_service_test`, the tool tests, `dead_workspace_reaper_test`) pass **unchanged in behaviour**. New: an environment holder's lock is not released by `release_all_for_session`, never reclaimed by expiry, skipped by `allocate` and by the reaper, released by `release_owned`; `held_by` makes `allocate` idempotent for a holder. `allocate(wait: false)` against WebMock: returns `starting` without a build wait for a stopped and for a new workspace, probes a running candidate, takes a free one, `ExhaustedError` when it has nothing. `delete`: `:pending`, `:gone`, an unknown workspace, a refusal. `extend_deadline` for a success and a refusal. `WorkspaceStatus` for every build state, agent state and deadline, from the reaper's and the allocator's old fixtures. `QuotaError` for a recorded refusal | **An agent session that uses `coder_*` as before** (allocate, run, release; the reaper's next sweep). A `bin/rails runner` script: `allocate(wait: false)` with an environment holder, `status` until running, `extend_deadline` on the staging template (which call works; its refusals), `delete`. The hosted pool's next allocation and the reaper's next sweep leave the held workspace alone. The quota refusal's status and body recorded (§15) | A workspace the platform holds for a runner, with no runner code |
| **17c** The runner core without Coder | `Runners::Allocator` (`acquire!`, `release!`, `let_go!`, `fail!`) replacing the `Machines` calls in `RunnerRuntime`, `Revocation`, `ContactLoss`, `CheckIn`, with step 4 and the `max_environments` count. The provisioned arm of `RunnerEnvironmentStateMachine` and its migration (§6). `Runners::Provisioning.advance!`. `Adapter#launch_refusal`, `RunnerEnvironment#in_service?`, the `runner_provisioning` wait reason (model, `launchStatus.ts`), `Settings.runners.bootstrap_timeout`. Registering into a row the platform created: `Credentials.mint_registration!(…, environment:)`, `Registration.register!` filling the row (§8.4), `CheckIn.check_in!` firing `check_in` and failing an allocated environment through `Allocator.fail!`, the gateway's refusal of the states of §8.4, a `PROTOCOL.md` note (no schema change) | Model and state-machine tests for every event and refusal. Allocator tests with a fake provisionable adapter registered in the test only: steps 1 to 4, the `max_environments` count including `tearing_down`, two sessions racing one idle environment, a retried acquire, revoke vs acquire lock order. `ExhaustedError` and `Pending` through `AdmittedPhaseActivity` end as `capacity_wait` with the reservation kept. Credentials tests (a bound token, one live token per environment, expiry). `register!`: fills the row, refuses another runner's environment, a `gone` one and a wrong state, spends the token once under two racing registrations. The conformance fixtures of `register` and the `manual` suites (`machines_test`, `runner_session_launch_test`, `runner_failed_machine_test`) pass unchanged | The DESIGN.md §12.4 `manual` run: a session, two in parallel with one machine (`runner_capacity`), a reset. Nothing visible changes. `aixle-runner configure --token` by hand against staging with a token bound to a row made in the console: the row fills and reaches `idle` | The `capacity_wait` path of step 4, and a machine that registers into a row the platform made |
| **17d** A Coder runner created from the console | `CoderAdapter` (§7): the checks and the install over `SshRunner` (§8.2), `provision` through `allocate(wait: false)`, `prepare`, `teardown` through `Allocator#delete`, `observe`, `check_health`, `launch_refusal`. Sessions on `coder`: `create_container` (`Pending`, `ProvisionError`), `cleanup_session` by `reuse_policy` (`reuse`, `reset`, `fresh`, never started), replacement of a failed environment, the bootstrap-timeout failure. The failure paths of §11 and the complete `Runners::Reconciler`: boot timeout, teardown pacing and cap, the dead-workspace scan for `:stopped`/`:missing`, revival (§8.5), the deadline push (§4.4) and `autostop_error`, releasing the holds of `gone` environments, teardown on Revoke and on runner deletion, the integration-token paths. `ConfigSchema` without the template keys and `on_release`. Not in `REGISTRY`: the runner is created from the console | Adapter tests for each health outcome in §7.3. `provision` idempotent on a retried step; `ExhaustedError` as `CapacityError`. `inject_bootstrap` with a recording `SshRunner`: the container, no-sudo and no-systemd exits, the token placement, a spent token not re-sent. `teardown`. `runner_session_launch_test`-style integration tests on a provisioned runner with the provider stubbed: one session, two in parallel, a third waiting (`runner_capacity`), reuse gets the warm environment, `fresh` ends `gone`, a failed scrub replaces the environment, a cancelled booting session, `Sessions::Lifecycle.finalize` ordering, the admission slot not held by a deleting machine. One test per row of §11, with time travel for the 5 and 15 minute rules; a teardown that Coder refuses, retried; a deletion cap; the deadline push and its refusal | A `coder` runner created from the console on the staging integration: `check_health`, a non-interactive and an interactive session, two in parallel plus a queued third, warm reuse, `fresh` deleting its workspace, a tampered pin refusing the install, a stopped workspace under a session failing it in about 3 minutes, the deadline push past the template's 3 hours, a revoked integration token. The answers to DESIGN.md §12.5's three questions (Docker daemon, disk, pruning) | DESIGN.md §12.5 steps 2 to 9, run on a runner made from the console |
| **17e** The type, the form, the page and the docs | `coder` in `REGISTRY`, the form (integration, the shared-pool line), the Environments section, Rebuild, per-environment Revoke, the runners list column, the integration-removal message, the user guide and its mirror, DESIGN.md's built-state notes | Frontend tests for the form, schema errors at their fields, the page for each state. Controller and policy tests (project runner only, scope rules of DESIGN.md §2.6). The user-guide mirror pair check | The whole of DESIGN.md §12.5 by hand, without the console | The type creatable from the UI, which is what DESIGN.md §12.5 step 1 starts from |

Row 18 stays the QA task of DESIGN.md §12.5 and is cut after 17e. Its steps 10 and 11 (a second project's refusal, hosted unchanged) need no code from item 17 and are the existing selection and DESIGN.md §12.3 regression tests.

**What breaks for companies on `external_runners` today** (18; the runners are a beta for one company, and a break is weighed case by case). Nothing is identified:

- `manual` runners, machines and versions: 17c moves the allocator under `RunnerRuntime`, and the `manual` suites pass unchanged. To keep that true the allocator takes the runner row `FOR UPDATE` on a provisionable runner only; a `manual` runner keeps `FOR SHARE`, as `Machines` takes it. Taking `FOR UPDATE` for both would serialise a `manual` runner's acquires. That is the cost of not keeping compatibility, and it is not paid.
- The migration of 17c is additive (two nullable columns, one `origin` value). `ConfigSchema` loses keys of a type nobody can create.
- 17b changes the Coder services that the agents' `coder_*` tools use in production. That is why it is its own task and why its staging check includes an agent session. Locks written before it stay valid.

If an implementation task finds a break, its pull request names it with the cost of keeping compatibility, and the reviewer weighs it.

## 15. Edge cases and risks

- **The 30 s retry interval is a floor on start latency.** A workspace that is ready 5 s after a retry waits up to 25 s more. Accepted: a cold build takes minutes. Lowering `CAPACITY_RETRY_INTERVAL` would affect every runtime.
- **`coder` CLI in the worker.** `SshRunner` needs the CLI in the process that runs the activity. The Dockerfile installs it for the hosted tools; 17d confirms the container-workflow worker runs that image and says so in its PR if not.
- **Coder's quota error shape is unverified.** 17b confirms the status and message on staging and records them; until then a refusal that is not recognised is an `OperationError`, which becomes a `ProvisionError`: the session fails with Coder's message and the failure feeds the streak, not silent.
- **Which Coder call extends the autostop deadline is unverified** (§4.4). 17b settles it on staging. If the template refuses every extension, the runner is `degraded` with the message, and a session longer than the template's limit is stopped by Coder and fails by the dead-workspace row of §11.
- **A pushed deadline costs one Coder `GET` per busy environment per minute.** Accepted: the Coder tools poll as often.
- **Two callers advance one environment** (the session's phase and the reconciler). The row lock and idempotent steps make a repeat a no-op; the one non-idempotent step, minting a token, revokes the previous unused one and is skipped when the token is spent (§8.2). `allocate` is idempotent for its holder (§4.3).
- **A workspace taken from the pool is probed only when it already runs** (§4.3). A building or stopped one is returned unprobed. The runner's checks cover it, and a failed one is deleted, not quarantined. A sick workspace that the integration would have quarantined is therefore deleted when a runner takes it before the probe. Accepted (4).
- **The token is in argv on the workspace for the few seconds before it is spent.** Single use and spent at once (accepted). It is never logged: the adapter redacts it from the output it keeps.
- **A runner deletes a workspace it was given from the pool.** That is the decision (15, 7): `fresh` and every broken machine delete. A customer who does not want a pool workspace deleted keeps the runner's integration apart from the pool's users (6).
- **An integration shared by hosted sessions and runners shares Coder's quota and provider limits.** Until #295 it is the same integration for a project's agents and its Coder runner. Documented in the user guide. The runner page does not show it.
- **A default template that cannot serve a runner** (a container template, no sudo, required parameters, no Docker) fails the first environment with the message of §8.2 or Coder's, and the streak makes the runner `degraded`. A template that suits the pool and not the runner needs a second integration, which #295 makes possible.
- **A `fresh` session on a workspace that is slow to delete.** The session is finished, the admission slot is free, and the machine counts toward `max_environments` until `gone`: the next session may wait in `runner_capacity` while the runner is at its limit with deleting machines. This is D12.
- **A stopped workspace that kept `aixle-runner`** (a template autostop of an idle warm environment, a customer's `coder stop`) stays held by its environment, so the hosted pool cannot take it. Its revival is §8.5.
- **Nested-Docker workspaces** (sysbox, envbox) are containers by `systemd-detect-virt` and are refused (§8.2).
- **No production identifiers** appear in this document. The spot-reclaim and quota events are described in general terms.

## 16. Decisions and assumptions

Numbers 1 to 18 in the source column are the numbered points of Alex's round 2 review (comments 115825, 115857, 115882, 115897).

| # | Decision | Source |
| --- | --- | --- |
| D1 | **Superseded.** A `coder` runner is one more consumer of the Coder integration. It reuses the allocator, the locks, `WorkspaceService`, `SshRunner`, the health probe and the integration and token services. Quarantine is internal to the integration's probe (D17, D26) | Alex, 2026-11-26 (115468, 115825 item 13); code reading in §2 |
| D2 | `busy` is not a state: `idle` with a hold | `RunnerEnvironment#busy?`, patterns "Model Predicates" |
| D3 | **Accepted.** Provisioning advances one step per `capacity_wait` retry through a `CapacityError` subclass and the wait reason `runner_provisioning`; no new workflow | Alex, 2026-11-26 (115468) |
| D4 | **Accepted.** Rebuild is retire-and-replace. `Adapter#reset(level: :rebuild)` is not built | Alex, 2026-11-26 (115468) |
| D5 | One `bootstrap_timeout` setting, 900 s | `coder` is the only provisioning type for now; amends §8's "10 min, 15 for `coder`" |
| D6 | **Accepted.** There is no `GET /runner/v1/install.sh`. The workspace is installed with `machine-install.sh` (`Runners::MachineInstallScript`) | Alex, 2026-11-26 (115468) |
| D7 | **Dropped.** A revival re-runs the install with a new bound registration token (§8.5); there is no bootstrap exchange | Alex, 2026-11-26 (115499) |
| D8 | **Dropped** with `on_release`. An idle-stop timer is not built either | Alex, 2026-11-26 (115825 item 7) |
| D9 | `check_health` calls Coder at most every 5 minutes; the integration's state is read on every run | DESIGN.md §2.5 ("passed within the last 5 minutes") |
| D10 | A refusal because the integration has nothing to give is a wait (`capacity_wait`, `runner_capacity`, the integration's message); a failed build is a failure that feeds a `degraded` streak | Two different facts: the platform may retry the first, not the second |
| D11 | The VM-only rule is a command the platform runs on the workspace through the integration before installing. The runner does not change. Decision 4 of 8b stands | Alex, 2026-11-26 (115499) |
| D12 | **Accepted.** Concurrency counts running sessions. A machine being deleted holds no admission slot. `max_environments` limits the runner's machines, not concurrency. An unreachable machine keeps its slot until it is heard and reset | Alex, 2026-11-26 (115499) |
| D13 | Launch refusal is an adapter method, not a type check in `Resolver` | The patterns' "one decision, one factory or polymorphism" |
| D14 | The integration's removal stays refused while a runner references it | The existing `restrict_with_error` |
| D15 | A failed provisioned environment is torn down and replaced; Return to service stays `manual`-only | §5.2 |
| D16 | A `coder` runner names an integration and nothing about templates. `template_id`, `template_version_policy`, `template_version_id`, `parameters` are removed from the config, the form and the health check | Alex, 2026-11-26 (115499) |
| D17 | **Changed.** No runner rule for a missing default template. The runner asks `Coder::Allocator#allocate`; the integration decides; when it has nothing the session waits in `capacity_wait` with its message. Designed for #294 (template and prefix required) | Alex (115825 item 1) |
| D18 | **Changed.** The runner takes machines through `allocate`, never through the Coder API. `allocate` gains `wait: false` (lock, return `starting`); the runner polls the status. It may get a free pool workspace | Alex (115825 item 3, 115882 item 15) |
| D19 | **Changed.** `on_release` is removed. `fresh` deletes after the session, a broken machine fails its environment and the workspace is deleted, revoking an environment or deleting the runner deletes the workspaces. Nothing goes back to the pool | Alex (115825 item 7) |
| D20 | **Changed.** The hold is explicit: the holder is the runner environment, no expiry, no renewal. Released when the runner deletes the workspace; the reconciler releases the holds of `gone` environments | Alex (115825 item 9) |
| D21 | The table-match rule is dropped. The lock already hides a held workspace from the allocator and the reaper | Alex, 2026-11-26 (115468: "reconsider"), §4.5 |
| D22 | The token of a `coder` runner is the ordinary registration token, bound to the environment row. `register` fills the row; `booting → idle` happens at the first check-in | Alex, 2026-11-26 (115499) |
| D23 | The runner on a workspace is a system service. Root or passwordless sudo is required | Alex, 2026-11-26 (115499), option (a) |
| D24 | The runner binary does not change for item 17, so no runner release is cut for it | Alex, 2026-11-26 (115499) |
| D25 | **Autostop.** While a session runs the reconciler pushes the workspace's deadline forward through the Coder API. An idle warm workspace stops by its template and is started before the next session. A refused extension makes the runner `degraded`. 17b checks which call works | Alex (115857 item 12) |
| D26 | **Quarantine is internal** to the integration's SSH probe inside `allocate`. A runner's own failure fails the environment and deletes the workspace | Alex (115857 item 13, 115825 item 4) |
| D27 | The health check reads the integration only: its state and its token | Alex (115825 item 2) |
| D28 | `reuse` and `reset` decide only how a machine is cleaned between sessions | Alex (115825 item 8) |
| D29 | `fresh` guarantees that a session sees nothing of earlier runner sessions. `allocate` may give a free pool workspace the runner never used. No create-only mode. A `fresh` runner on an integration without a template empties its pool (accepted, #294 removes it) | Alex (115825 item 5, 115882 item 15) |
| D30 | The integration used by runners is kept apart from the agents' by the customer. How the tools pick an integration is #295's gap. Until then a project's Coder runner and its tools share one integration | Alex (115825 item 6, 115857 item 14, 115882 facts) |
| D31 | No new feature flag. `coder` becomes visible and creatable in 17e | Alex (115897 item 17) |
| D32 | A break of what `external_runners` companies use is decided case by case. None is identified; §14 names how it is avoided | Alex (115897 item 18) |
| D33 | The split is 17b to 17e | Alex (115882 item 16) |
| D34 | **Assumptions of this round, for the reviewer:** a runner environment's `external_id` is the Coder workspace's name; `allocate(wait: false)` probes only a candidate that already runs; the deadline is extended when less than 30 minutes remain, to 60 minutes from now; `autostop_error` is a column on the environment; the `coder` card is offered for project runners only | Decided here; the comments left them to the design |

**The reviewer is asked to check** D34's assumptions, the split of §14 (17b to 17e) and what 17b has to verify on staging (the quota refusal and the deadline call).

## 17. Deferred, and what to check

- **An idle-stop timer** for `reuse` environments (cost). Cut when a customer's bill shows it.
- **Classifying provider capacity errors in a failed build** (EC2 instance-type exhaustion and its like). It needs a per-provider reading of the build's error; the streak makes it visible until then.
- **Nested-Docker workspaces** (sysbox, envbox) as a supported shape. Refused by §8.2 until someone needs it.
- **A pool floor** (a minimum number of warm environments) and **warm-disk affinity** (out of the plan, Alex 2026-11-13).
- **A runner-level template or parameters.** Removed by decision. If a customer needs two templates, they use two integrations, which #295 makes possible.
- **Several Coder integrations per project, attached to workflows and sessions, and named by id in the tools** (#295), and **required template and prefix** (#294). This design does not wait for them; it is written so that both land without a change here.
- **A company-wide Coder integration**, which a company runner on Coder would need (DESIGN.md §2.6). Not in the plan.
- **The `host` execution mode** (row 20), Kubernetes (row 19) and the relay rows 24 to 27: out of scope, as the task says.
- **To check in 17b on staging:** the quota error's status and body, which Coder call extends the autostop deadline and how it refuses, and the workspace-status fields of `GET /workspaces/{id}` for a stopped and a reclaimed workspace.
- **To check in 17c and 17d:** that `machine-install.sh` re-runs on a machine that already has the service (§8.5), and that the container-workflow worker image has the `coder` CLI.
- **To check in 17d on staging:** the template's Docker daemon, disk and image pruning (DESIGN.md §12.5's three questions).
