# Coder runners: one more consumer of the Coder integration

**Status:** proposed (task #284, "Runners 17a"), round 2. Written against `origin/develop` after the interactive runner sessions of #277 (16g), the session lifecycle service of #273, #283 (`Sessions::Lifecycle.fail_if` and `finalize` are still there) and the Add machine work of #286 and #288 (`machine-install.sh`, `--mode machine`).
**Parent:** [`DESIGN.md`](DESIGN.md) §15 row 17. It refines DESIGN.md §2.2, §2.5, §2.6, §2.7, §5, §7.3, §8, §9.2, §10 and §11 for the `coder` type, and replaces row 17 with rows 17b to 17h (§14 below), as `runner-relay.md` did for row 16.
**Scope:** design only. This pull request changes this document, `DESIGN.md` and `docs/index.md`.

_A section number with `DESIGN.md` in front of it is the parent document's; a bare one is this document's._

**What round 2 changes.** Alex's review decisions of 2026-11-26 (task comments 115468 and 115499) replace the first round's direction:

| Round 1 | Round 2 |
| --- | --- |
| The runner reused the hosted pool's API client and `SshRunner`, and kept its own row, hold and health. Runner workspaces were hidden from the pool by matching names against `runner_environments` | A `coder` runner is one more consumer of the Coder integration. It allocates, holds, runs commands on and releases a workspace through the integration's services. The services change where a second consumer needs it (§4). The name-matching rule is dropped (§4.5) |
| The runner had `template_id`, `template_version_policy`, `template_version_id` and `parameters` | None of them. The template is the integration's default template (§4.6) |
| A new `bootstrap` credential kind, `aixle-runner bootstrap`, a new form of `check-in`, a rendered script of our own | An ordinary registration token bound to the environment row the allocator created. `register` fills that row. The workspace is installed with `machine-install.sh` (#288) as it is, over `SshRunner` (§8) |
| The runner ran as a `systemd --user` unit or under `setsid` | A system service. The workspace must give root or passwordless sudo (§8.3) |
| D12 asked for review | D12, D3, D4 and D6 are accepted (§16) |

## 1. Overview

A `coder` runner creates Coder workspaces for its sessions itself, through the company's Coder integration. Each workspace is a virtual machine that runs `aixle-runner --mode machine` as a system service and takes one session at a time in container mode, exactly as a `manual` machine does. What is new is everything before the session: the platform allocates, builds, boots and installs the machine, and releases it.

Setting up a `coder` runner means picking the Coder integration to take machines from. That is all it names about Coder: the template that workspaces are created from is the integration's default template.

Today the type cannot be created. `Runners::Adapter::REGISTRY` holds `manual` only, and the controllers refuse `coder` as "not available yet". The pieces item 17 needs and the code lacks:

| Piece | In the code today | Target |
| --- | --- | --- |
| Coder services for a second consumer | `Coder::Allocator`, `LockService`, `WorkspaceService` serve a terminal session only, and block up to 240 s per call | §4 |
| Runner allocator | `Runners::Machines.acquire!` takes a free registered machine (DESIGN.md §7.3 as 8a built it). No step 4 | `Runners::Allocator` (§5) |
| Provisioned states | `RunnerEnvironmentStateMachine` has `registered`, `resetting`, `failed`, `gone` | The provisioned arm (§6) |
| Delivery of `aixle-runner` | `register` creates an environment for a `manual` machine | `register` fills the environment the allocator created (§8) |
| `CoderAdapter` | None | §7 |
| `reuse_policy`, `on_release` | `reuse` and `reset` on `manual`, in `RunnerRuntime#cleanup_session` | `fresh` and `on_release` on `coder` (§9) |
| Integration state, default template | Not read by any runner | An `inactive` or `error` integration, or one with no default template, makes its runners `unreachable` (DESIGN.md §7.3) |
| VM-only rule | A sentence in DESIGN.md §2.6 | A command the platform runs on the workspace before installing (§8.2) |
| Form and page | `manual` only | §12 |

## 2. What exists, and what a second consumer needs

The hosted pool is a set of workspaces that the platform leases to terminal sessions and drives over `coder ssh`. The Coder integration's services do that work today:

| Service (`app/services/coder/`) | What it does today | What a runner needs from it |
| --- | --- | --- |
| `Allocator` | Lists the token owner's workspaces under `machine_prefix`, locks one for a **terminal session**, probes it, and otherwise creates one from `default_template`. `ensure_started` and `create_new_workspace` call `await_build`, which sleeps up to 240 s in one call | A holder that is a runner environment. A way to create and lock without waiting for the build. The status classification of a workspace (it is private to the allocator and the reaper) |
| `LockService` | A row in `integration_data` per workspace, keyed by `terminal_session_id`, expiring after the integration's `lock_ttl_minutes` (default 120) of inactivity, pushed forward by every Coder tool call (`touch`) | A holder that is not a session. A hold that outlives inactivity, with something other than a tool call renewing it |
| `WorkspaceService` | `list`, `find_by_name`, `find_template`, `create_workspace(name:, template_name:)`, `start`, `stop`, `delete`, `await_build`, error mapping with the token redacted | A build status that does not block. The create's refusals told apart |
| `SshRunner#exec` | Runs a command over `coder ssh`, with `stdin_data:` | Nothing. It is used as it is |
| `HealthCheck` | `probe` over SSH: reachable, or sick with a reason. `reachable` is evidence only that the box answered | `observe` for a runner environment that is not heard (§7.2) |
| `QuarantineService`, `DeadWorkspaceReaper` | Quarantine marks a sick pool box so the allocator passes over it. The reaper deletes pool workspaces under the prefix whose agents are gone, with no live lock, twice sighted | The reaper must never see a runner workspace. It does not, through the lock (§4.5). Quarantine has no reader on the runner path: a runner environment is not one candidate among many, its health is its heartbeat and its state. Unchanged |
| `TokenService`, `IntegrationService` | URL, token, redaction, and `test` (a rejected token marks the integration `error`) | `check_health` calls `IntegrationService#test` |
| `RepoBootstrap` | Clones repositories onto a leased workspace | Not used. `SessionContextService` clones inside the session container, as on every runner |

**What moves into `app/services/coder/`.** Three things the runner needs are done today by the session path in its own code. They move so that both consumers use one copy:

1. The classification of a workspace's last build (a succeeded `start` is running, a `start` in flight is starting, anything else needs a start). It is in `Allocator#ensure_started` and again, differently, in `DeadWorkspaceReaper`. It becomes `Coder::WorkspaceStatus.from(workspace_hash)` with `state` (`building`, `running`, `stopped`, `deleting`, `deleted`, `failed`) and `agent` (`connected`, `disconnected`, `none`). `HealthCheck.agents_unhealthy?` and `unhealthy_reason` stay where they are and `WorkspaceStatus` calls them.
2. The explanation of a refused request (`with_coder_explanation` in `WorkspaceService`) is reused as it is, and gains one more distinction: a refusal for quota raises `WorkspaceService::QuotaError < OperationError`. Its status and body shape are unverified, so 17b records them on staging (§15); an unrecognised refusal stays an `OperationError`.
3. The lock's ownership predicate (`value ->> 'terminal_session_id' = ?`), repeated in five methods of `LockService`, becomes one `Holder` (§4.1).

## 3. Approach

**Chosen.** The runner is a consumer of the integration's services. The state of an environment stays in `runner_environments` and advances one idempotent step per call, from the places that already retry: the `create_container` and `start_container` phases of `ContainerWorkflowV2`, and a minutely reconciler. No step holds a long wait.

| Alternative | Rejected because |
| --- | --- |
| The runner calls Coder directly through `Coder::Api` and keeps its own hold (round 1) | A second copy of the lock, the exclusion rule and the template choice. Alex's direction of 2026-11-26 asks for the services |
| Provision, build and install inside one activity (`create_container` waits for the runner) | A cold build plus an image pull outlasts the phase's 300 s `start_to_close_timeout`, and a retry would repeat the work. `capacity_wait` is the platform's wait already |
| A Temporal workflow per environment | A second orchestration layer for state that is a row and a few API calls |
| Let the runner take a free workspace of the hosted pool (§4.6) | Releasing it with `delete` would delete a workspace the platform did not create, and installing a root service on a pooled machine needs a cleanup the pool never had |
| `busy` as a state (DESIGN.md §5.2 as drawn) | `manual` derives it from the hold (`RunnerEnvironment#busy?`), and the patterns document names that predicate. A second source of truth would drift |

## 4. Changes to the Coder services

### 4.1 Who holds a lock

`Coder::LockService::Holder = Data.define(:kind, :id)`, with `Holder.session(id)` and `Holder.environment(id)`. The row's `value` keeps `terminal_session_id` for a session holder, so every row written before this change stays valid, and gains `runner_environment_id` for an environment holder. `acquire`, `touch`, `release_owned`, `held_by_session?` and `release_for_session` take `holder:` where they take `terminal_session_id:` now, and one private method builds the `value ->> '<key>' = ?` predicate. The three Coder tools and `Coder::Allocator` pass `Holder.session(session.id)`. `release_all_for_session` and its `IntegrationCleanupService` hook stay, and release session holders only, so ending a terminal session never releases a runner's workspace.

`Coder::Allocator.new(integration:, terminal_session:, …)` takes `holder:` in place of `terminal_session:`. The hosted behaviour and its tests do not change.

### 4.2 How long a runner holds, and what renews it

A runner environment holds its workspace from creation until the workspace is deleted, or handed back (§9.3). That is hours or days for a warm environment, and nothing about the hold depends on a tool call.

- The hold's expiry is `Settings.runners.workspace_hold_minutes` (60), not the integration's `lock_ttl_minutes`: that setting is the idle time of a terminal session, which is a different quantity.
- `Runners::Reconciler` (§11) renews every live environment's hold once a minute with `LockService#touch(holder:)`, and `Runners::Provisioning.advance!` renews it on each step. A platform that is down for an hour lets the holds expire, and the workspaces are then visible to the hosted pool. This is accepted: the environment rows still name them, the reconciler's first pass takes the holds again before anything else (§4.5), and a hosted session that locked one in the meantime is the cost of a platform outage of that length, which the hosted pool has with every lock.
- A `touch` that returns false (the hold was reclaimed) is handled in §11 as a lost workspace.
- The hold is released with `release_owned(holder:)` when the environment becomes `gone`, and when the workspace is handed back (§9.3).

### 4.3 Allocating without waiting for the build

`Coder::Allocator#provision(holder:, name:, note: nil)` is new and **creates only** (§4.6). It creates a workspace from the integration's default template named `name`, locks it for `holder` right after, and returns the plain hash `allocate` returns (`status: "starting"`) without calling `await_build`. If a workspace with that name exists it returns that one (a retried step). If the lock is refused (another consumer won the lock in the instant between create and lock), it raises `LockNotAcquired`, and the environment is retried under a new name. `allocate` (the hosted path) is unchanged.

`Coder::WorkspaceService` gains `status(workspace_id)` → `WorkspaceStatus` (one `GET /api/v2/workspaces/{id}`), `ensure_started_async(workspace)` (issues a `start` build for a stopped workspace and returns without waiting; the allocator's own `ensure_started` is rebuilt on it plus `await_build`), and `create_workspace` stays as it is. It already takes the template **name** and finds the template by it.

The runner's adapter calls these three. It calls `await_build` never.

### 4.4 The workspace's name

An environment's `key` is its workspace's name, generated by the allocator as `<machine_prefix or "aixle">-r<runner id>-<4 hex>`: it matches the integration's prefix, so a workspace the platform hands back to the pool (§9.3) is a pool member that the hosted allocator and reaper can see, and `r<runner id>` tells people whose it was. Coder's name limit is 32 characters; a prefix that leaves no room makes `check_health` `degraded` with the length named (DESIGN.md §7.3).

### 4.5 The pool exclusion rule is dropped

Round 1 hid runner workspaces from the hosted pool by matching names against `runner_environments`. With the lock, it is not needed:

- `Coder::Allocator#allocate` locks each candidate and passes over one that is held (`LockNotAcquired`).
- `DeadWorkspaceReaper` deletes only a workspace with **no live lock**.
- The lock is taken in the same call that creates the workspace (§4.3), and renewed (§4.2).

What remains is a window of a few milliseconds between the create and the lock, which `Allocator#create_and_lock` already has for the hosted pool, and a hold that expired during a platform outage (§4.2). Both are accepted. Dropping the rule removes a `WorkspaceService#list` filter, a scope on `RunnerEnvironment` and a table match on every listing.

### 4.6 The template, and the pool's free workspaces

**The template is the integration's.** The integration's `default_template` setting (a template name, chosen when the integration is set up) is the one every runner on it builds from, as the hosted pool grows from it. The runner has no template, version policy, version or parameters. What `check_health` verifies about a template is the integration's (DESIGN.md §7.3).

- **No default template.** A runner on an integration with none can create nothing. Its health is `unreachable` with `Coder integration "X" has no default template. Set one in the integration's settings.` The launch refusal reads that status (§10), so a session is refused at launch with the message, and the form's Connect step shows it at once. An environment that exists keeps working until it is released; none is created. (A runner could still serve sessions from warm environments, but a runner that can no longer replace a failed one is a runner a person must look at, so it is flagged.)
- **A template that builds from required parameters it has no default for** fails at create with Coder's own message (`ProvisionError`, §7.2). The runner has nowhere to set a parameter. This is a limit of the integration's default template, and the integration is where it is fixed.
- **An edit of the default template** applies to workspaces created after it. Environments that exist keep the build they have, until they are released with `fresh` or rebuilt.

**A runner creates its own workspaces and never takes a free one from the pool.** The allocator's pool path (`allocate`) is not used by the runner. The reasons:

1. `on_release: delete` and `fresh` delete the workspace. The platform may delete only what it created.
2. `max_environments` counts the runner's own environments. A pool workspace taken by a runner is not one, and cannot be counted or replaced.
3. Installing a system service as root on a machine that hosted sessions share leaves a state that has to be cleaned before the machine goes back, and the pool has no cleanup. For a workspace the runner created, the cleanup is a step of its own release (§9.3).

The cost is that a pool with idle workspaces does not feed runners. That is acceptable: a runner's workspaces are its own, and a customer who wants to feed a runner from their pool can use a `manual` runner on those machines.

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

Idempotent for a session: a session that holds an environment gets it back (a retried `create_container`), as `Machines.acquire!` does. Otherwise, in one transaction that first locks the runner row `FOR UPDATE` (the order is runner, then environment, as every issuer and the revoker use; `Machines` takes it `FOR SHARE`, and the allocator needs the count to be serial):

1. **An idle, heard environment** of this runner, lowest id first, `FOR UPDATE SKIP LOCKED`. The hold (`current_session_id`) is set. (Affinity and project binding are out of the plan, DESIGN.md §7.3 steps 1 to 3.)
2. **On a `provisionable` runner, an idle environment that is not heard** and is held by no session, taken under the same lock: its workspace was stopped (a template autostop) or its runner service is down. The hold is set and the environment is revived (`restart`, §6). This keeps a warm workspace useful after the template stopped it.
3. **On a `provisionable` runner, with `count(environments not gone) < max_environments`** (null means `max_concurrency`): insert a row in `requested`, `origin: allocated`, `key` from §4.4, held by the session. `tearing_down` and `failed` rows count until they are `gone`, so a slow delete cannot let the pool grow past its limit. `max_environments` limits the runner's machines, not concurrency (D12).
4. Otherwise raise `ContainerRuntime::CapacityError` with `reason: "runner_capacity"` (§10). On `manual` only steps 1, 4 and the offline rules of DESIGN.md §7.3 exist, unchanged.

After the transaction commits, a row that is not `idle` is advanced once (`Runners::Provisioning.advance!`, §5.2), and `acquire!` raises `Runners::Allocator::Pending`, a `CapacityError` subclass with `reason: "runner_provisioning"`, until the environment is `idle`. The activity treats it as any `CapacityError` (`AdmittedPhaseActivity`, `capacity_wait`): it keeps the reservation, records the wait reason and message on the admission, and the workflow tries again 30 s later (`CAPACITY_RETRY_INTERVAL`). No new workflow code.

`runner_provisioning` (D3, accepted) joins `SessionAdmission::WAIT_REASONS` and `LAUNCH_WAITS`, and `launchStatus.ts` shows "Starting a workspace" with the message beneath. It is not `runner_capacity`, because the session page would say "Waiting for a free machine" while the platform builds one for it.

### 5.2 `Runners::Provisioning.advance!(environment)`

One step per call, under the environment's row lock, decided by its state. Each step is idempotent, because Temporal retries and two callers (the session's phase and the reconciler) may race:

| State | Step |
| --- | --- |
| `requested` | `adapter.provision(env)`: `Coder::Allocator#provision` (§4.3). Writes `external_id` and `boot_started_at`, fires `begin_provision` |
| `provisioning` | `adapter.prepare(env)`: `:pending` while the build runs or the agent is not connected. On `:ready`, `adapter.inject_bootstrap(env)` (§8) and fire `finish_build` (`booting`) |
| `booting` | Nothing to do: `register` and the first check-in move it (§8.4). If `boot_started_at + Settings.runners.bootstrap_timeout` has passed, `mark_failed` with the message of §11 and raise `Runners::ProvisionError` |
| any other | none |

The HTTP and SSH calls run outside the allocator's runner lock, and the row is re-read and saved under its own lock after each. A `ProvisionError` (the template refused, the build failed, the VM check failed) fires `mark_failed` with the message and propagates. `RunnerRuntime#create_container` turns it into a `CreateRefusedError`, so the phase fails with the diagnosis and the cleanup frees the hold (§10).

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
- `failed` on a provisioned environment is not a resting state. The reconciler (§11) tears it down, and the allocator creates a replacement on demand. This is the **rebuild** (D4, accepted): retire-and-replace, a new key and a new row. `Adapter#reset(level: :rebuild)` is not built. The `rebuildable` capability stays `true` for `coder`, and the runner page's Rebuild action calls `begin_teardown`.
- `restart` (`idle → booting`) revives a stopped or silent workspace (§8.5).
- `check_in` is `booting → idle`, fired by the first check-in after `register` (§8.4). It is not fired by `register`, so an environment is never `idle` before its preflight is reported.
- `unreachable` stays an overlay (DESIGN.md §5.2): a silent `idle` or `busy` environment is shown offline and skipped by the allocator.

**Schema (17c).** `bin/rails generate migration` (never by hand): `runner_environments.external_id` (string, null; unique per runner where not null), `runner_environments.boot_started_at` (datetime, null), and `origin` accepts `allocated`. Each has its first reader in this task. `reusable` of §2.2 is not added: `reuse_policy` is read from the runner at release. No backfill: nothing allocated exists.

## 7. `Runners::CoderAdapter`

`app/services/runners/coder_adapter.rb`, `Adapter` subclass. Stateless; every method is idempotent on `environment.key`.

### 7.1 Config

`ConfigSchema` keys for `coder`: `on_release` and the `container.*` keys only. `template_id`, `template_version_policy`, `template_version_id`, the `parameters` key and the `if/then` rule of `for_type("coder")` are removed. The runner's `integration` (already validated by `Runner#integration_usable`, DESIGN.md §2.6) is how it names Coder.

### 7.2 The methods

| Method | Behaviour |
| --- | --- |
| `capabilities` | `provisionable: true`, `rebuildable: true` |
| `provision(env)` | `Coder::Allocator#provision(holder: Holder.environment(env.id), name: env.key)`. Returns `external_id`. `QuotaError` raises `CapacityError` (§11); any other `OperationError` raises `ProvisionError` with Coder's `message (detail)` text |
| `prepare(env)` | `WorkspaceService#status`: `building` → `:pending`; `stopped` → `ensure_started_async` and `:pending`; `running` with the agent `connected` → `:ready`; `running` with the agent still connecting → `:pending`; `failed` → `ProvisionError` with the build's error |
| `inject_bootstrap(env)` | §8.2 and §8.3 |
| `reset(env, level: :reset)` | The `env.reset` runner op (`Runners::Operations.enqueue_reset!`), as `Machines.return_to_service!` does. `level: :rebuild` raises `Runners::UnsupportedOperation` |
| `teardown(env)` | §9.3. Returns `:pending` until the workspace is deleted or handed back, then `:gone`. A workspace Coder no longer knows is `:gone` |
| `observe(env)` | `:running` while the environment is heard, with **no call**, as `ManualAdapter#observe`. Not heard: `status` → `:stopped`, `:missing` (404 or `deleted`), and for a running workspace with the agent connected, `HealthCheck#probe`: reachable means the box is up and the runner service is down (`:running`), not reachable means `:unknown`. `:unknown` also when Coder cannot be asked |
| `check_health(runner)` | §7.3 |
| `launch_refusal(runner)` | §10 |

### 7.3 `check_health`

`Runners::HealthCheck` already runs every minute for every live runner and applies the adapter's `Health` (status, reason). The coder adapter returns, in order:

1. The integration is `inactive` or `error` (a column, no IO): `unreachable`, `Coder integration "<name>" is <inactive | in error: <settings.error>>. Reconnect it, or pick another runner.` This is DESIGN.md §2.6's rule, and it needs no Coder call.
2. The integration has no `default_template`: `unreachable`, with the message of §4.6.
3. Otherwise, **at most once every 5 minutes** (the stamp is `runners.health["checked_at"]`; in between the last result is returned unchanged): `IntegrationService#test` (the token). Refused: the integration becomes `error` and the runner `unreachable` as in 1. Coder unreachable: `unreachable` with the reason.
4. The integration's default template exists: `WorkspaceService#find_template`. Not found: `unreachable`, `Coder template "<name>" was not found on integration "<integration>".` (the check task #209 moved out of the model).
5. The workspace name fits Coder's limit (§4.4): otherwise `degraded`, naming the prefix.
6. The last `Settings.runners.max_consecutive_failures` allocated environments all `failed` while provisioning or booting: `degraded`, `Provisioning has failed N times in a row: <last reason>`. This is the signal for a template that cannot build or a machine that cannot install, and where a provider that is out of capacity at build time becomes visible (§11).
7. Otherwise `connected`.

`status_reason` is capped at 255 characters, as `ManualAdapter` caps it.

## 8. Delivering `aixle-runner`

No new runner command, no new credential kind and no new form of `check-in`. The runner binary does not change for item 17.

### 8.1 The token, bound to the environment

`Credentials.mint_registration!(runner, created_by: nil, environment: nil)`: for a `coder` runner it requires `environment:` (an `allocated` environment of that runner, in `provisioning` or `booting`) and stores it in the credential's `runner_environment_id`. A `manual` runner's token is unchanged (no environment, one machine per use). It is minted under the runner's lock like every issuer. Minting a token for an environment revokes its earlier unused registration tokens, so one live token exists per environment. Its expiry is the existing `REGISTRATION_TTL` (1 hour), longer than `bootstrap_timeout`.

### 8.2 The checks, then the install

`CoderAdapter#inject_bootstrap` runs two commands over `Coder::SshRunner#exec(workspace_name: env.key, …)`, so the integration's token, the redaction and the `coder` CLI handling are the integration's:

1. **The VM check and the privilege check**, one short command. It exits with a distinct code, and the adapter turns each into a `ProvisionError` with a message for people:
   - the workspace is a container or a pod (`systemd-detect-virt --container` reports one, or `/.dockerenv` exists, or `KUBERNETES_SERVICE_HOST` is set): "This workspace is a container or a pod. Aixle coder runners support virtual-machine workspaces only";
   - not root and `sudo -n true` fails: "The workspace gives neither root nor passwordless sudo, which the runner service needs";
   - no `systemctl`: "The workspace has no systemd, which the runner service needs".
   This is DESIGN.md §2.6's rule, run by the platform. The runner has no preflight for it, and a `manual` runner is unaffected. Decision 4 of task 8b stays: a Docker daemon that cannot see the runner's files is found by Docker's refusal of the sidecar's bind mount, as built.
2. **The install**: `Runners::MachineInstallScript.render(version:, gateway_url:, digests:)` (the same module and pins as `GET /runner/v1/machine-install.sh`, #288) is piped on stdin: `sh -s -- --token <token> --name <key>`, run through `sudo -n` when the user is not root. The script picks the architecture, downloads from `/runner/v1/releases/:version/:platform`, checks the SHA-256 against the pin, and runs `configure`, `service install` and `service start`, as it does for an operator. A mismatch stops it before anything runs, with the script's own message, which the adapter keeps as the bootstrap output.

The token is in argv for the few seconds before it is spent. Accepted (Alex, 2026-11-26): it is single use and spent at once. The adapter redacts the registration token from the output it keeps and logs. `SshRunner` redacts only the integration's own token, and is not changed.

**Idempotence.** `advance!` mints a token only for an environment with no unspent one. If the environment's token is already spent when the step runs again (the SSH call broke after the script ran `configure`), the install is not sent twice: the step moves to `booting` and waits for the check-in.

### 8.3 The runner is a system service

The workspace must give root or passwordless sudo, and `machine-install.sh` runs as it is (`configure`, `service install`, `service start`). There is no `service install --user` and no user-level unit. The runner needs Docker, and membership of the `docker` group is root-equivalent, so the requirement adds nothing the runner did not already need. The user guide states it (§12). A template whose user cannot sudo fails with the message of §8.2.

### 8.4 `register` fills the row

`Runners::Registration.register!(credential, …)` today creates a `registered` environment. When the credential names an environment, it fills that row instead, under the runner's lock and the row's:

- the environment must be `allocated`, of the credential's runner, in `provisioning` or `booting`; otherwise `invalid_token`;
- it records `display_name` (the `--name`, which is the key), os, arch, facts, `auto_update`, versions and `first_seen_ip`, and the token is spent;
- its state becomes `booting` (from `provisioning`, if the install call had not returned yet) and it stays so;
- the credential pair is issued as for a `manual` machine.

The runner then checks in at its start (`runner/internal/cli/machine.go`). `CheckIn.check_in!` fires `check_in` (`booting → idle`) when the preflight reports nothing wrong, and `fail_for_preflight!` fails it otherwise, the failure being the reason, as it does for `manual`. For an allocated environment `fail_for_preflight!` calls `Allocator.fail!`, not `Machines.fail!`.

Credentials of a provisioned environment are invalid when it leaves `idle` and `resetting` for `tearing_down` or `failed`, and when it is `gone` (§9.2). `RunnerGateway::V1::ApplicationController` refuses those states for an `allocated` environment (a `failed` `manual` machine keeps its credentials so Return to service can reach it; a failed provisioned one never needs to).

### 8.5 A revival

A stopped workspace that is started again may or may not have kept its runner service, depending on its template's disks. The platform does not rely on it. A revival (`restart`, from §5.1 step 2 or the reconciler) revokes the environment's credential family, mints a new token bound to the same row, fires `idle → booting` and runs §8.2 again. `register` fills the same row. A workspace that kept its service starts a runner with revoked credentials, which fails its calls and is replaced by the re-install. `machine-install.sh` on a machine that already has the service is re-run as it is; if it refuses that case, 17d settles the one-line change (§15, "To check").

## 9. Release

### 9.1 `reuse_policy`

Read from the runner at release, so an edit applies from the next release. `reuse` and `reset` keep the workspace (container mode only for `reset`, DESIGN.md §7.1). `fresh` gives each session a workspace of its own and releases it after the session.

### 9.2 What happens when the session ends (`cleanup_session`, then `Allocator.release!`)

| Environment when the session ends | What happens |
| --- | --- |
| `requested`, `provisioning`, `booting` (never started) | The hold is cleared; no op is sent. The environment keeps booting as a warm one (`reuse`, `reset`), or is torn down (`fresh`) |
| `idle`, `reuse` | `container.stop`, `env.scrub`, hold cleared. A failed scrub is followed by `env.reset`, as on `manual` |
| `idle`, `reset` | `container.stop`, `env.reset`, hold cleared |
| `idle`, `fresh` | `container.stop` (best effort), hold cleared, `begin_teardown` (§9.3). No scrub: the workspace leaves |
| Any, and the scrub or reset failed, or the session is the `max_consecutive_failures`th failed one in a row | `mark_failed`, hold cleared. The reconciler tears it down (§9.3) and the next acquire creates a replacement. A `coder` environment does not stay `failed`: nobody can fix a machine we created, and Return to service is `manual`-only (`Machines::NotManual`, as built) |

### 9.3 `teardown`, and what goes back to the pool

`teardown` runs by `config.on_release`, once the environment is `tearing_down`:

- **`delete`** (the default): a delete build. The workspace is gone, nothing goes back to the pool. The hold is released when Coder reports `deleted`.
- **`stop`**: the workspace goes back to the integration's pool, **clean**. A workspace must not go back with `aixle-runner` installed and running, so the adapter:
  1. runs a cleanup command over `SshRunner` that stops and disables the service unit, removes the unit file and the runner's state directory (the paths `runner/internal/service` and `cli.DefaultStateDir` define: the unit `aixle-runner.service` and `/var/lib/aixle-runner`), reloads systemd, and ends by **checking** that the unit is not active and the directory is gone, with an exit code that says which check failed;
  2. only when it exits 0 issues the stop build, and when that build has succeeded, releases the hold. The workspace is then a free pool member: its name matches the integration's prefix (§4.4), no service runs on it, and the hosted allocator may lock it;
  3. if the cleanup fails or the workspace cannot be reached, deletes it instead, as `delete` does. A workspace is never handed back unverified.
  The environment is `gone` when the workspace has been deleted or the hold released. Docker's images and volumes the runner created stay on the machine: they are the pool's disk, as the hosted sessions' state is. The runner page says that `stop` hands the workspace to the pool.

The credentials of the environment are revoked at `tearing_down` (§8.4), so a runner that is still alive on a workspace being cleaned calls nothing.

## 10. Sessions: how the allocator and the release fit `Sessions::Lifecycle`

**`create_container`** (`RunnerRuntime`): `Allocator.acquire!(session)`, then `container.start` once the environment is ready, as today. `Pending` and `CapacityError` reach `capacity_wait`. A `ProvisionError` becomes a `CreateRefusedError`: the phase fails with the message and the session ends through the usual path. The admission's `runtime_id` is persisted before the phase (`AdmittedPhaseActivity`), so the cleanup always runs.

**`start_container`**: unchanged, a `status` loop. The environment is already `idle`.

**The admission slot** (D12, accepted). Concurrency counts running sessions. A machine being deleted holds no admission slot, and `max_environments` limits the runner's machines, not concurrency. `Allocator.release!` clears the hold at the end of cleanup and the session's admission is released as today, after `Sessions::Lifecycle.finalize`. The rule for an unreachable machine stays (DESIGN.md §10): its slot is held until the machine is heard and reset, because the session's container may still be running there. A `coder` environment the platform lost contact with is in this case until it is heard again and reset, or `gone`.

**Lifecycle rules.** The allocator and provisioning never write a session's state. Where an environment fails under a live session (§11) the caller is the reconciler or the dead-container scan, and it uses `Sessions::Lifecycle.fail_if(session, error_message:)`, as `Runners::ContactLoss` and `Runners::Revocation` do. The `terminal_sessions.runner_environment_id` write stays the one `Machines.take!` makes today.

**Interactive sessions** (#277) work as on `manual`: the runner on the workspace opens the tunnel, the relay maps the session to the environment through the hold (`RunnerEnvironment`'s `after_save` signal), and the browser path is unchanged. The coder-specific requirement is egress from the workspace to the relay host (DESIGN.md §12.5).

**Launch refusals** become polymorphic. `Runners::Resolver` calls `Machines.availability(runner)`, which is `manual`'s. `Adapter` gets `launch_refusal(runner)` (nil, or `Refusal(reason, message)`), declared on the base with no default. `ManualAdapter` delegates to the existing availability code; `CoderAdapter` refuses an `unreachable` runner with `runner_unreachable` and §8's message ("Runner "X" is unreachable: <the health reason>"), which names the integration, or the missing default template. A `degraded` runner is admitted.

## 11. The failure paths of §8 on `coder`

`Runners::Reconciler` (`app/services/runners/reconciler.rb`) runs every minute, as a new activity in `runner_health_check_workflow` after the health check. Each rule works on one provisioned environment and is idempotent; one that fails is logged and does not stop the others. Its first act is to renew every live hold (§4.2).

| Condition | Detected by | Outcome |
| --- | --- | --- |
| **Provisioning fails** (template refused, build failed) | `provision`/`prepare` raise `ProvisionError` | `mark_failed` with Coder's message. A session holding it fails with that message. The reconciler tears the environment down |
| **The workspace is a container or a pod, or gives no root or sudo** | The checks of §8.2 | `mark_failed` with the message of §8.2. The streak of §7.3 rule 6 counts it. A session holding it fails with that message |
| **Build times out** | `boot_started_at + bootstrap_timeout`, in `advance!` and in the reconciler for an environment no session is advancing | `mark_failed`, teardown; the session fails with the message below |
| **No check-in within `bootstrap_timeout`** | Same rule, `booting` | "Workspace started but aixle-runner did not check in within 15 min. Check that the workspace can reach <platform host>:443." plus the install script's last output (§8.2). `failed`, then teardown |
| **Workspace stopped or gone under a session** (a spot reclaim, as `DeadWorkspaceReaper` describes: the build is a succeeded start and every agent is `disconnected`) | `ScanDeadContainersActivity` calls `observe` for a machine it does not hear. `:stopped`/`:missing` now count as dead: the scan's two-sighting `confirm_or_mark` fails the session with "Workspace stopped or deleted by Coder (a spot reclaim, or a template autostop)" | The session fails after the scan's confirmation (about 3 minutes), not the 15-minute grace. The environment is `failed`, then torn down. `observe` returning `:running` changes nothing: it falls to the grace (`ContactLoss`), the evidence the reaper's doctrine asks for |
| **Runner service down, workspace up** | An `idle` or `busy` environment not heard for 5 minutes with `observe` `:running` | The reconciler revives it (§8.5), once every 5 minutes. A session's container keeps running on the VM (DESIGN.md §6.7), so a restarted service picks it up. If it is still not heard after `ContactLoss::GRACE`, the session fails by the grace and the environment is `failed` |
| **A hold was lost** (`touch` returns false: expired or reclaimed by another consumer) | The reconciler's renewal | The reconciler re-takes it if the workspace is unlocked (`acquire` again). If another holder has it, the environment is `failed` with "The workspace was taken by another consumer of the integration", torn down without a delete (the workspace is not ours any more), and a session holding it fails |
| **The integration's token is revoked** | `check_health` (§7.3) every 5 minutes; any adapter call that gets 401/403 calls `IntegrationService#test` | The integration is `error`, the runner `unreachable`, launches are refused with the integration named. Running sessions continue: the runner talks to the platform, not to Coder. A session waiting in provisioning fails with "Coder integration "X" rejected its token. Replace the token." Teardowns that cannot reach Coder stay `tearing_down`, retried every minute, and count toward `max_environments` until the token is replaced |
| **The provider is out of capacity** | A create refused for quota: `QuotaError`. A build that fails for lack of instances: Coder reports a failed job | The refusal is `capacity_wait` with `runner_capacity` and "Waiting for capacity on runner "X"." (§10, row 9 of §8). The failed build is a diagnosed failure of that session, and it counts in the streak that makes the runner `degraded` (§7.3 rule 6). Parsing provider errors for "out of capacity" is deferred |
| **Runner revoked or deleted** | `Runner`'s `after_save` already ends its sessions (`Revocation.end_sessions!`) | It also `begin_teardown`s every environment that is not `gone`, best effort. The reconciler finishes them. The runner page lists any that Coder would not delete ("must be removed by the customer", §9.3) |
| **Disabled** | | No new sessions; environments are left. Running sessions finish |
| **Environment revoked from the runner page** | `Registration.revoke!` | Credential family revoked, `begin_teardown` first for a provisioned environment, `gone` when the workspace is deleted or handed back |

The reconciler never acts on: an environment held by a session that has not ended and is heard; any workspace that is not an environment's `external_id`; and, per the reaper's cap, more than `Settings.runners.max_teardowns_per_run` (default 3) workspace deletions in one pass. A provider outage that fails every build at once must not empty a pool in a single sweep.

## 12. UI and API surface

Behind `external_runners`, with no new flag (DESIGN.md §12.2 phase 5). `Runners::Adapter::REGISTRY` gains `"coder"` in the last task, not before: until the form, health, allocator and sessions all exist, the type must not be creatable.

- **Form.** Step 2 for `coder`, generated from `ConfigSchema.for_type("coder")` as for `manual`: **the integration select** (the project's visible active Coder integrations, DESIGN.md §2.6), `on_release`, the `container` options, `reuse_policy` (all three, with DESIGN.md §7.1's wording), and `max_environments` (step 3). No template, version or parameter fields. Beside the select, the integration's default template is shown read-only, with "Change it in the integration's settings"; an integration with none is shown with a warning. "Connect" runs the config checks and `Runners::HealthCheck.check!` inline, as §11 says. `Runners::Save` and the controllers already refuse a type with no adapter; adding the adapter lifts "not available yet". No templates endpoint is needed.
- **Runner page.** The Machines section becomes **Environments** for `coder`: key, state (`requested`…`gone`, with the reason), the session it holds (link), last heard, runner version, workspace link to Coder, and the actions Rebuild (`begin_teardown`) and per-environment Revoke. The overview adds the integration and its template. A `manual` runner's page is unchanged. The runners list shows "environments busy/total" with `Runner#machine_counts` extended to a provisioned runner, counting every environment not `gone`.
- **Integration removal.** `IntegrationsController#destroy` keeps refusing while a runner references the integration (`dependent: :restrict_with_error`), and its message names the runners. Delete the runner first, which revokes and tears down.
- **Docs.** The user guide and its portal mirror (`docs/user-guide/` and `app/frontend/pages/Docs/data/pages/`): that a coder runner builds from the integration's default template; the requirements on it (a virtual machine, root or passwordless sudo, systemd, Docker); that `on_release: stop` hands a cleaned workspace to the integration's pool; and the egress the workspace needs.

## 13. Testing approach

Tests follow the area's conventions: Minitest and FactoryBot, no fixtures, sequences in factories (`test/factories/runners.rb` and `runner_environments.rb` get `:coder` and `:allocated` traits). Coder is stubbed at the HTTP layer with WebMock, as `test/services/coder/` does. `SshRunner` is passed to the adapter as a dependency (as `Coder::HealthCheck` takes one), never stubbed with a block returning a fake object. Concurrency tests copy `machines_concurrency_test.rb`. The `Runners::Allocator` public contract is tested for a `manual` runner too, so the move is covered before any Coder code exists. The per-task tests are in §14.

## 14. The split of item 17

Each task is cut when the one before has merged, against the code as it is then, as §15 says. All are behind `external_runners`. The `coder` type becomes creatable only in 17h. 17b and 17c do not depend on each other and may be cut in either order. The runner (Go) does not change in any of them.

| Row | Delivers | Tests | Staging check | Item 18 (DESIGN.md §12.5) needs from it |
| --- | --- | --- | --- | --- |
| **17b** The Coder services for a second consumer | `LockService::Holder` and `holder:` in `LockService` and `Allocator` (§4.1), the three tools passing `Holder.session`. `Coder::WorkspaceStatus` extracted from `Allocator` and `DeadWorkspaceReaper`. `WorkspaceService#status`, `ensure_started_async`, `QuotaError`. `Allocator#provision` (create-only, no `await_build`). The hold's expiry setting and renewal call. No runner code | The hosted suites (`allocator_test`, `lock_service_test`, the tool tests, `dead_workspace_reaper_test`) pass **unchanged in behaviour**. New: an environment holder's lock is not released by `release_all_for_session`, not reclaimed while live, skipped by `allocate` and by the reaper (held), renewed by `touch`, released by `release_owned`. `Allocator#provision` against WebMock: returns without a build wait, finds an existing name, `LockNotAcquired` on a lost lock. `WorkspaceStatus` for every build state and agent state, from the reaper's and the allocator's old fixtures. `QuotaError` for a recorded refusal | A `bin/rails runner` script on staging: `Allocator#provision` with an environment holder, `status` until running, `delete`. The hosted pool's next allocation and the next reaper sweep leave the workspace alone while it is held. The quota refusal's status and body recorded (§15, "To check") | A workspace the platform created and holds, with no runner code |
| **17c** `Runners::Allocator` and the provisioned states, no Coder | `Runners::Allocator` (`acquire!`, `release!`, `let_go!`, `fail!`) replacing the `Machines` calls in `RunnerRuntime`, `Revocation`, `ContactLoss`, `CheckIn`. The provisioned arm of `RunnerEnvironmentStateMachine` and the migration (§6). `Runners::Provisioning.advance!`. `Adapter#launch_refusal`, `RunnerEnvironment#in_service?`, the `runner_provisioning` wait reason (model, `launchStatus.ts`). `Settings.runners.bootstrap_timeout` | Model and state-machine tests for every event and refusal. Allocator tests with a fake provisionable adapter registered in the test only: steps 1 to 4, the `max_environments` count including `tearing_down`, two sessions racing one idle environment, a retried acquire, revoke vs acquire lock order. A `CapacityError` and a `Pending` through `AdmittedPhaseActivity` end as `capacity_wait` with the reservation kept. The `manual` suites (`machines_test`, `runner_session_launch_test`, `runner_failed_machine_test`) pass unchanged | The DESIGN.md §12.4 `manual` run: a session, two in parallel with one machine (`runner_capacity`), a reset. Nothing visible changes | The `capacity_wait` path of step 4 |
| **17d** Registering into an allocated environment | `Credentials.mint_registration!(…, environment:)` for `coder`. `Registration.register!` filling the row (§8.4). `CheckIn.check_in!` firing `check_in` and failing an allocated environment through `Allocator.fail!`. The gateway refusing the states of §8.4. A `PROTOCOL.md` note on register for an allocated environment (no schema change: the request and response are the same) | Credentials tests (a bound token, one live token per environment, expiry, runner lock order). `register!` tests: fills the row, refuses another runner's environment, a `gone` one and a wrong state, spends the token once under two racing registrations. `check_in!` for `booting → idle` and for a failed preflight. The conformance fixtures of `register` pass unchanged | Run `aixle-runner configure --token` by hand against staging with a token bound to a row made in the console: the row fills and reaches `idle` | A machine that registers into a row the platform made |
| **17e** `CoderAdapter` and the reconciler's provider side | `CoderAdapter`: `capabilities`, `provision`, `prepare`, `inject_bootstrap` (the checks and the install over `SshRunner`, §8.2), `teardown` with the cleanup of §9.3, `observe`, `check_health`, `launch_refusal`. `Runners::Reconciler`: hold renewal, teardown, boot timeout. `ConfigSchema` without the template keys. Not in `REGISTRY` | Adapter tests for each health outcome in §7.3 (integration state, no default template, token refused, template 404, name too long, streak). `provision` idempotent on a retried name, a quota refusal as `CapacityError`. `inject_bootstrap` with a recording `SshRunner`: the container, no-sudo and no-systemd exits, the token placement, a spent token not re-sent. `teardown`: `delete`; `stop` with a clean workspace, a failed cleanup deleting it, an unreachable one deleting it. `ConfigSchema` tests for the removed keys | A script on staging: a `coder` runner row by the factory path against the staging integration, `check_health`, `provision`, `prepare` to `:ready`, `inject_bootstrap`, the environment reaches `idle`, an op round-trips (`status`), `teardown` with `delete` and with `stop` (the stopped workspace has no service and is allocatable by the hosted pool). A tampered pin refuses the install | A template that builds, recorded, and the answers to DESIGN.md §12.5's three questions (Docker daemon, disk, pruning) |
| **17f** Sessions on `coder` | `RunnerRuntime` calling the allocator for a provisioned runner end to end: `create_container` (`Pending`, `ProvisionError`), `cleanup_session` by `reuse_policy` (`reuse`, `reset`, `fresh`, never started), `on_release`, failed-environment replacement, `Resolver` through `launch_refusal`, the bootstrap-timeout failure and message. Not creatable from the UI: the runner is created from the console | `runner_session_launch_test`-style integration tests on a provisioned runner with the provider stubbed: one session, two in parallel, a third waiting (`runner_capacity`), reuse gets the warm environment, `fresh` ends `gone`, a failed scrub replaces the environment, a booting environment whose session is cancelled, `Sessions::Lifecycle.finalize` ordering, the admission slot not held by a deleting machine | One non-interactive session and an interactive one (the tunnel) on a staging `coder` runner created from the console; parallel and queued cases | DESIGN.md §12.5 steps 3 to 5 (run, two parallel plus a queued third, warm reuse) |
| **17g** Failure paths | `Runners::Reconciler` complete (dead workspace, runner service down and revival §8.5, lost hold, teardown pacing and cap), `ScanDeadContainersActivity` for `:stopped`/`:missing`, `Revocation` and per-environment Revoke tearing down, the integration-token paths of §11, the runner page's list of workspaces left behind | One test per row of §11, with time travel for the 5 and 15 minute rules. The scan's two-sighting rule on a `:stopped` workspace. A teardown that Coder refuses, retried. A deletion cap. A revival re-registering into the same row | Stop a workspace under a session in the Coder UI: the session fails within about 3 minutes and the environment is replaced. Revoke the integration token: `unreachable` with the integration named, then replace it | DESIGN.md §12.5 steps 2, 7 to 9: the token revoke, the lost connection, the runner restart, the runner revoke |
| **17h** The type, the form and the page | `coder` in `REGISTRY`, the form (integration, default template shown), the Environments section, Rebuild, per-environment Revoke, the runners list column, the integration-removal message, the user guide and its mirror, DESIGN.md's built-state notes | Frontend tests for the form, schema errors at their fields, the page for each state. Controller and policy tests (company and project, scope rules of DESIGN.md §2.6). The user-guide mirror pair check | The whole of DESIGN.md §12.5 by hand, without the console | The type creatable from the UI, which is what DESIGN.md §12.5 step 1 starts from |

Row 18 stays the QA task of DESIGN.md §12.5 and is cut after 17h. Its steps 10 and 11 (a second project's refusal, hosted unchanged) need no code from item 17 and are the existing selection and DESIGN.md §12.3 regression tests.

## 15. Edge cases and risks

- **The 30 s retry interval is a floor on start latency.** A workspace that is ready 5 s after a retry waits up to 25 s more. Accepted: a cold build takes minutes. Lowering `CAPACITY_RETRY_INTERVAL` would affect every runtime.
- **`coder` CLI in the worker.** `SshRunner` needs the CLI in the process that runs the activity. The Dockerfile installs it for the hosted tools; 17e confirms the container-workflow worker runs that image and says so in its PR if not.
- **Coder's quota error shape is unverified.** 17b confirms the status and message on staging and records them; until then a refusal that is not recognised is an `OperationError`, which becomes a `ProvisionError`: the session fails with Coder's message and the failure feeds the streak, not silent.
- **Two callers advance one environment** (the session's phase and the reconciler). The row lock and idempotent steps make a repeat a no-op; the one non-idempotent step, minting a token, revokes the previous unused one and is skipped when the token is spent (§8.2).
- **The token is in argv on the workspace for the few seconds before it is spent.** Single use and spent at once (accepted). It is never logged: the adapter redacts it from the output it keeps.
- **A platform outage longer than the hold's expiry** exposes the runners' workspaces to the hosted pool (§4.2). The window is 60 minutes by default and the setting is `workspace_hold_minutes`.
- **An integration shared by hosted sessions and runners shares Coder's quota and provider limits.** Documented in the user guide. The runner page does not show it.
- **A default template that cannot serve a runner** (a container template, no sudo, required parameters, no Docker) fails at the first environment with the message of §8.2 or Coder's, and the streak makes the runner `degraded`. Because the hosted pool uses the same template, a template that suits the pool and not the runner needs a second integration, which the form's read-only template line makes visible before Connect.
- **A `fresh` session on a workspace that is slow to delete.** The session is finished, the admission slot is free, and the machine counts toward `max_environments` until `gone`: the next session may wait in `runner_capacity` while the pool is at its limit with deleting machines. This is D12.
- **A stopped workspace that kept `aixle-runner` and was handed back by something other than §9.3** (a template autostop, a customer's `coder stop`) is not cleaned: it stays held by its environment row, so the hosted pool cannot take it. Its revival is §8.5.
- **Nested-Docker workspaces** (sysbox, envbox) are containers by `systemd-detect-virt` and are refused (§8.2).
- **No production identifiers** appear in this document. The spot-reclaim and quota events are described in general terms.

## 16. Decisions and assumptions

| # | Decision | Source |
| --- | --- | --- |
| D1 | **Superseded.** A `coder` runner is one more consumer of the Coder integration. It reuses the allocator, the locks, `WorkspaceService`, `SshRunner`, the health probe and the integration and token services. Quarantine has no reader on the runner path and is unchanged. The reaper is unchanged and does not see a held workspace | Alex, 2026-11-26 (comment 115468); code reading in §2 |
| D2 | `busy` is not a state: `idle` with a hold | `RunnerEnvironment#busy?`, patterns "Model Predicates" |
| D3 | **Accepted.** Provisioning advances one step per `capacity_wait` retry through a `CapacityError` subclass and the wait reason `runner_provisioning`; no new workflow | Alex, 2026-11-26 (115468) |
| D4 | **Accepted.** Rebuild is retire-and-replace. `Adapter#reset(level: :rebuild)` is not built | Alex, 2026-11-26 (115468) |
| D5 | One `bootstrap_timeout` setting, 900 s | `coder` is the only provisioning type for now; amends §8's "10 min, 15 for `coder`" |
| D6 | **Accepted.** There is no `GET /runner/v1/install.sh`. The workspace is installed with `machine-install.sh` (`Runners::MachineInstallScript`), and there is no second renderer | Alex, 2026-11-26 (115468) |
| D7 | **Dropped.** A revival re-runs the install with a new bound registration token (§8.5); there is no bootstrap exchange | Alex, 2026-11-26 (115499) |
| D8 | `on_release` applies to teardown only; an idle-stop timer is not built | DESIGN.md §2.7's definition ("what `teardown` does") |
| D9 | `check_health` calls Coder at most every 5 minutes; the integration's state is read on every run | DESIGN.md §2.5 ("passed within the last 5 minutes") |
| D10 | A quota refusal at create is a wait; a failed build is a failure that feeds a `degraded` streak | Two different facts: the platform may retry the first, not the second |
| D11 | **Changed.** The VM-only rule is a command the platform runs on the workspace through the integration before installing. The runner does not change. Decision 4 of 8b stands | Alex, 2026-11-26 (115499) |
| D12 | **Accepted.** Concurrency counts running sessions. A machine being deleted holds no admission slot. `max_environments` limits the runner's machines, not concurrency. An unreachable machine keeps its slot until it is heard and reset | Alex, 2026-11-26 (115499) |
| D13 | Launch refusal is an adapter method, not a type check in `Resolver` | The patterns' "one decision, one factory or polymorphism" |
| D14 | The integration's removal stays refused while a runner references it | The existing `restrict_with_error` |
| D15 | A failed provisioned environment is torn down and replaced; Return to service stays `manual`-only | §5.2 |
| D16 | A `coder` runner names an integration and nothing about templates. The integration's `default_template` is the template. `template_id`, `template_version_policy`, `template_version_id` and `parameters` are removed from the config, the form and the health check | Alex, 2026-11-26 (115499) |
| D17 | **Asked of the reviewer.** A runner with an integration that has no default template is `unreachable`, with the integration named, and creates nothing | Decided here; the task left it to the design |
| D18 | **Asked of the reviewer.** A runner creates its own workspaces and never takes a free one from the pool | Decided here (§4.6); the task left it to the design |
| D19 | **Asked of the reviewer.** `on_release: stop` cleans the workspace (service, unit, state), verifies it, stops it and releases the hold, so it goes back to the pool without `aixle-runner`. A failed cleanup deletes it. `delete` and `fresh` leave nothing | Decided here (§9.3); the task left it to the design |
| D20 | A lock's holder is a `Holder` (session or environment). The hold's expiry is `runners.workspace_hold_minutes` (60), renewed by the reconciler each minute | Alex's list of what the services lack (115468); the values are decided here |
| D21 | The table-match rule is dropped. The lock already hides a held workspace from the allocator and the reaper | Alex, 2026-11-26 (115468: "reconsider"), §4.5 |
| D22 | The token of a `coder` runner is the ordinary registration token, bound to the environment row. `register` fills the row; `booting → idle` happens at the first check-in | Alex, 2026-11-26 (115499) |
| D23 | The runner on a workspace is a system service. Root or passwordless sudo is required | Alex, 2026-11-26 (115499), option (a) |
| D24 | The runner binary does not change for item 17, so no runner release is cut for it | Alex, 2026-11-26 (115499) |

**The reviewer is asked to check** D17, D18 and D19, which the task left to the design, D20's numbers, and the new split of §14 (17b to 17h), which replaces round 1's.

## 17. Deferred, and what to check

- **An idle-stop timer** for `reuse` environments (cost). Cut when a customer's bill shows it.
- **Classifying provider capacity errors in a failed build** (EC2 instance-type exhaustion and its like). It needs a per-provider reading of the build's error; the streak makes it visible until then.
- **Nested-Docker workspaces** (sysbox, envbox) as a supported shape. Refused by §8.2 until someone needs it.
- **A pool floor** (a minimum number of warm environments), **taking a free pool workspace** (D18) and **warm-disk affinity** (out of the plan, Alex 2026-11-13).
- **A runner-level template or parameters.** Removed by decision. If a customer needs two templates, they use two integrations.
- **The `host` execution mode** (row 20), Kubernetes (row 19) and the relay rows 24 to 27: out of scope, as the task says.
- **To check in 17b on staging:** the quota error's status and body, and the workspace-status fields of `GET /workspaces/{id}` for a stopped and a reclaimed workspace.
- **To check in 17d and 17e:** that `machine-install.sh` re-runs on a machine that already has the service (§8.5), and that the container-workflow worker image has the `coder` CLI.
- **To check in 17e on staging:** the template's Docker daemon, disk and image pruning (DESIGN.md §12.5's three questions).
