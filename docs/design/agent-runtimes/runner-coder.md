# Coder runners: provisioned environments, `Runners::Allocator` and `CoderAdapter`

**Status:** proposed (task #284, "Runners 17a"). Written against `origin/develop` after the interactive runner sessions of #277 (16g) and the session lifecycle service of #273. #283 (lifecycle effects in `Sessions::Lifecycle.transition!`) is open; this design calls only `Sessions::Lifecycle.fail_if` and `finalize`, which #283 leaves in place.
**Parent:** [`DESIGN.md`](DESIGN.md) §15 row 17. It refines §2.2, §2.6, §5, §7.3, §8, §9.2, §10 and §11 for the `coder` type, and replaces row 17 with rows 17b to 17g (§12 below), as `runner-relay.md` did for row 16.
**Scope:** design only. This pull request changes this document, `DESIGN.md` and `docs/index.md`.

_A section number with `DESIGN.md` in front of it is the parent document's; a bare one is this document's._

## 1. Overview

A `coder` runner creates Coder workspaces for its sessions itself, through the company's existing Coder integration. Each workspace is a virtual machine that runs `aixle-runner --mode host` and takes one session at a time in container mode, exactly as a `manual` machine does. What is new is everything before the session: the platform allocates, builds, boots and bootstraps the machine, and tears it down.

Today the type cannot be created. `Runners::Adapter::REGISTRY` holds `manual` only, and the controllers refuse `coder` as "not available yet". The pieces item 17 needs and the code lacks:

| Piece | In the code today | Target |
| --- | --- | --- |
| Allocator | `Runners::Machines.acquire!` takes a free registered machine (§7.3 as 8a built it). No step 4 | `Runners::Allocator` (§4) |
| Provisioned states | `RunnerEnvironmentStateMachine` has `registered`, `resetting`, `failed`, `gone` | The provisioned arm (§5) |
| Bootstrap token | Only registration, access and refresh credentials | A `bootstrap` credential and its exchange at check-in (§7) |
| `CoderAdapter` | None | §6 |
| `reuse_policy`, `on_release` | `reuse` and `reset` on `manual`, in `RunnerRuntime#cleanup_session` | `fresh` and `on_release` on `coder` (§8) |
| Template checks | `ConfigSchema` has the keys, with no IO | `check_health` (§6.3) |
| Integration state | Not read by any runner | An `inactive` or `error` integration makes its runners `unreachable` (§6.3) |
| VM-only rule | A sentence in §2.6 | A preflight in the runner's bootstrap command (§7.4) |
| Form and page | `manual` only | §11 |

## 2. What exists, and what of the hosted Coder pool is reused

The hosted pool is a set of workspaces that the platform *leases* to sessions and drives over `coder ssh`. A runner environment is a machine that *calls the platform*. The two share a Coder user and an API, and nothing else.

| Piece (`app/services/coder/`) | Reused? | Why |
| --- | --- | --- |
| `Api` | **Yes, extended.** It is our own client, because no Ruby gem covers Coder's API (the `Gemfile` has none; the implementation-patterns rule on clients is met by extending the one we have) | New calls in §6.1 |
| `WorkspaceService` | **Yes, extended.** `start`, `stop`, `delete`, `find_by_name` and the error mapping stay. `await_build` is **not** used: it sleeps up to 240 s inside one call | A non-blocking build status (§6.1). The activity polls across retries |
| `TokenService`, `IntegrationService` | **Yes.** The token, URL, redaction and the `test` method that marks a rejected token `error` | The health check calls `IntegrationService#test` |
| `SshRunner` | **Yes**, `exec` with `stdin_data:` only | `inject_bootstrap` pipes the script over stdin (§7.3). The detached-job machinery is not used |
| `Allocator`, `LockService`, `QuarantineService`, `HealthCheck` | **No** | They lease a shared pool with a lock row and probe it over SSH. A runner environment is held by `runner_environments.current_session_id` (a unique index) and its health is its host runner's heartbeat |
| `DeadWorkspaceReaper` | **No, and it must not see runner workspaces** | Its doctrine is kept (§9), its code is not. See the exclusion rule below |
| `RepoBootstrap` | **No** | `SessionContextService` clones the repositories inside the session container, as on every runner |

**The two pools must not see each other's workspaces.** The hosted allocator lists the token owner's workspaces under the integration's `machine_prefix`, and with a blank prefix lists all of them. The reaper deletes workspaces under that prefix. A runner workspace named `aixle-r<runner id>-<8 hex>` could be handed to a hosted session, or reaped, by either. The rule: `WorkspaceService#list` drops every workspace whose name is the `key` of a `runner_environments` row of this integration's runners (a scope on `RunnerEnvironment`, `provisioned_on(integration)`, read in the same call). The row exists before the workspace does (§4), so there is no window. A name match against the table is used, not a name pattern, so a customer prefix that happens to look like ours is not misread. This lands first (17c), before any workspace is created.

## 3. Approach

**Chosen.** Keep the state in `runner_environments` and advance it one idempotent step per call, from the places that already retry: the `create_container` and `start_container` phases of `ContainerWorkflowV2`, and a minutely reconciler. No step holds a long wait.

Alternatives considered:

| Alternative | Rejected because |
| --- | --- |
| Provision, build and boot inside one activity (`create_container` waits for check-in) | A cold build plus Docker image pull takes longer than the phase's 300 s `start_to_close_timeout`, and the activity's retry would repeat the work. The platform already has a better wait: `capacity_wait` |
| A Temporal workflow per environment | A second orchestration layer for state that is a row plus a few API calls. The reconciler and the phase retries already give durability |
| Reuse the hosted `Coder::Allocator` and add a "runner" mode | Its lock rows, SSH probe and quarantine have no meaning when the machine reports itself. The reused part would be the name generator |
| `busy` as a state of its own (§5.2 as drawn) | `manual` already derives it from the hold (`RunnerEnvironment#busy?`), and the patterns document names exactly that predicate. A second source of truth would drift |

## 4. `Runners::Allocator`

`app/services/runners/allocator.rb`. It owns the environment row and the hold, for every type. `Runners::Machines` keeps what is specific to `manual`: `return_to_service!`, `settle_resets!`, the launch availability and its messages.

```ruby
Runners::Allocator.acquire!(session)            # => RunnerEnvironment (held, ready), or raises
Runners::Allocator.release!(environment, session, failed:)
Runners::Allocator.let_go!(session)             # the runner is revoked: the hold goes, no outcome counted
Runners::Allocator.fail!(environment, reason, holder: nil)
```

`RunnerRuntime`, `Revocation`, `ContactLoss` and `CheckIn` call these instead of the same methods on `Machines`. 17b moves them; the `manual` behaviour and its tests do not change.

### 4.1 `acquire!`

Idempotent for a session: a session that holds an environment gets it back (a retried `create_container`), as `Machines.acquire!` does. Otherwise, in one transaction that first locks the runner row `FOR UPDATE` (the order is runner, then environment, as every issuer and the revoker use; `Machines` takes it `FOR SHARE`, and the allocator needs the count to be serial):

1. **An idle, heard environment** of this runner, lowest id first, `FOR UPDATE SKIP LOCKED`. The hold (`current_session_id`) is set. (Affinity and project binding are out of the plan, §7.3 steps 1 to 3.)
2. **On a `provisionable` runner, an idle environment that is not heard** and is held by no session, taken under the same lock: its workspace was stopped (a template autostop) or its host runner is down. The hold is set and the environment is revived (`restart`, §5). This is what keeps a warm workspace useful after the template stopped it.
3. **On a `provisionable` runner, with `count(environments not gone) < max_environments`** (null means `max_concurrency`): insert a row in `requested`, `origin: allocated`, `key: aixle-r<runner id>-<8 hex>`, held by the session. `tearing_down` and `failed` rows count until they are `gone`, so a slow delete cannot let the pool grow past its limit.
4. Otherwise raise `ContainerRuntime::CapacityError` with `reason: "runner_capacity"` (§10). On `manual` only steps 1, 4 and the offline rules of §7.3 exist, unchanged.

After the transaction commits, a row that is not `idle` is advanced once (`Runners::Provisioning.advance!`, §4.2), and `acquire!` raises `Runners::Allocator::Pending`, a `CapacityError` subclass with `reason: "runner_provisioning"`, until the environment is `idle` and checked in. The activity treats it as it treats any `CapacityError` (`AdmittedPhaseActivity`, `capacity_wait`): it keeps the reservation, records the wait reason and message on the admission, and the workflow tries again 30 s later (`CAPACITY_RETRY_INTERVAL`). No new workflow code.

`runner_provisioning` is a new wait reason, next to `runner_capacity`: it joins `SessionAdmission::WAIT_REASONS` and `LAUNCH_WAITS`, and `launchStatus.ts` shows "Starting a workspace" with the message beneath. It is not `runner_capacity` because the session page would then say "Waiting for a free machine" while the platform is building one for it.

### 4.2 `Runners::Provisioning.advance!(environment)`

One step per call, under the environment's row lock, decided by its state. Each step is idempotent, because Temporal retries and two callers (the session's phase and the reconciler) may race:

| State | Step |
| --- | --- |
| `requested` | `adapter.provision(env)` (a create that finds a workspace named `key` returns it). Writes `external_id`, `boot_started_at`, fires `begin_provision` |
| `provisioning` | `adapter.prepare(env)`: `:pending` while the build runs or the workspace is starting; on `:ready`, mints a bootstrap token, calls `adapter.inject_bootstrap`, fires `finish_build` (`booting`) |
| `booting` | Nothing to do: check-in moves it (§7). If `boot_started_at + Settings.runners.bootstrap_timeout` has passed, `mark_failed` with the message of §10 and raise `Runners::ProvisionError` |
| any other | none |

The HTTP calls of `provision`, `prepare` and `inject_bootstrap` run outside the allocator's runner lock, and the row is re-read and saved under its own lock after each. A `ProvisionError` from `provision` or `prepare` (the template refused, the build failed) fires `mark_failed` with the provider's message and propagates. `RunnerRuntime#create_container` turns it into a `CreateRefusedError`, so the phase fails with the diagnosis and the cleanup frees the hold (§8).

`Settings.runners.bootstrap_timeout` is one setting, 900 s. §8 says "10 min, 15 for `coder`"; `coder` is the only type that provisions until Kubernetes arrives, and the Kubernetes task can add its own then.

## 5. The provisioned arm of the environment state machine

`RunnerEnvironmentStateMachine` gains the states and events below. It stays AASM with `whiny_persistence`, and nothing writes `state` past it (implementation-patterns, Anti-Patterns).

```
requested ─begin_provision─▶ provisioning ─finish_build─▶ booting ─check_in─▶ idle ◀─finish_reset─ resetting
                                                             ▲                │  ▲                     ▲
                                                             └──── restart ───┘  └── begin_reset ─────┘
 any state but gone ── mark_failed ──▶ failed ── begin_teardown ──▶ tearing_down ─finish_teardown─▶ gone
 idle | resetting | booting | provisioning | requested ── begin_teardown ──▶ tearing_down
 unregister (per-machine Revoke, runner Revoke) ──▶ gone                          (as on manual)
```

- `idle` is free when no session holds it and busy when one does. `RunnerEnvironment` gets `in_service?` (`registered` or `idle`) and the `free` scope reads it, so `Allocator`, `Resolver`'s availability and the `manual` code share one definition of "can take a session". (Checked: `RunnerEnvironment.new.respond_to?(:in_service?)` is false.)
- `registered` stays the `manual` state. The two arms never mix: a `manual` environment is created `registered`, an allocated one `requested`, chosen by `origin`.
- `failed` on a provisioned environment is not a resting state. The reconciler (§9) tears it down, and the allocator creates a replacement on demand. This is the **rebuild**: DESIGN.md §5.1 and §7.2 described `reset(level: :rebuild)` as delete-and-recreate of the same environment. It is simpler as retire-and-replace (a new key, a new row), because it reuses `begin_teardown` and the lazy step 3 above and needs no in-place recreation state. The `rebuildable` capability stays `true` for `coder`, and the runner page's Rebuild action (17g) calls `begin_teardown`. `Adapter#reset(level: :rebuild)` is not built, and DESIGN.md §5.1 is amended.
- `restart` (`idle → booting`) revives a stopped or silent workspace: it mints a fresh bootstrap token and returns to `booting`. Every boot, the first or a revival, ends with a bootstrap exchange (§7), so a host runner never depends on a credentials file that a stopped workspace may have lost.
- `unreachable` stays an overlay (§5.2): a silent `idle` or `busy` environment is shown offline and skipped by the allocator.

**Schema (17b).** `bin/rails generate migration` (never by hand, per the patterns): `runner_environments.external_id` (string, null; unique per runner where not null), `runner_environments.boot_started_at` (datetime, null), and `origin` accepts `allocated`. `reusable` of §2.2 is **not** added: `reuse_policy` is read from the runner at release, so an edit of the policy applies from the next release. The two new columns have their first reader in this task, as the plan's rule of "a column lands with its first reader" asks. No backfill: nothing allocated exists.

## 6. `Runners::CoderAdapter`

`app/services/runners/coder_adapter.rb`, `Adapter` subclass. Stateless; every method is idempotent on `environment.key`.

### 6.1 The Coder calls it needs (`Coder::Api`, `Coder::WorkspaceService`)

Verified against Coder's API reference:

| Need | Call |
| --- | --- |
| The template and its active version | `GET /api/v2/templates/{id}` (`active_version_id`) |
| The template's parameters | `GET /api/v2/templateversions/{id}/rich-parameters` |
| Create | `POST /api/v2/users/{user}/workspaces` with `name`, `template_id` **or** `template_version_id` (not both), `rich_parameter_values: [{name, value}]`. `Api.create_workspace` today sends `name` and `template_id` only |
| One workspace's status | `GET /api/v2/workspaces/{id}`: `latest_build.transition`, `latest_build.job.status` and `error`, and the agents' `status` in `latest_build.resources[].agents[]` |

`WorkspaceService` gains `create_runner_workspace(name:, template_id:, version_id:, parameters:)`, `status(workspace_id)` returning `Coder::WorkspaceService::Status` (`state`: `building`, `running`, `stopped`, `deleting`, `deleted`, `failed`; `agent`: `connected`, `disconnected`, `none`; `error`) and `find_by_name`. Errors keep mapping to `OperationError` with the token redacted, which the adapter maps to its own errors.

### 6.2 The methods

| Method | Behaviour |
| --- | --- |
| `capabilities` | `provisionable: true`, `rebuildable: true` |
| `provision(env)` | Resolves the version: `active` reads the template's active version now, `pinned` uses `template_version_id`. Creates the workspace named `env.key` with `config.parameters`; if one with that name exists, returns it. Returns `external_id`. A quota refusal raises `CapacityError` (§10); any other refusal raises `ProvisionError` with Coder's `message (detail)` text |
| `prepare(env)` | `status`: `building` → `:pending`; `stopped` → starts it and `:pending`; `running` with agent `connected` → `:ready`; `running` with the agent still `connecting` → `:pending`; `failed` → `ProvisionError` with the build's error |
| `inject_bootstrap(env, bootstrap)` | §7.3 |
| `reset(env, level: :reset)` | The `env.reset` runner op (`Runners::Operations.enqueue_reset!`), as `Machines.return_to_service!` does. `level: :rebuild` raises `Runners::UnsupportedOperation` (§5) |
| `teardown(env)` | By `config.on_release`: `delete` issues a delete build, `stop` a stop build, once. Returns `:pending` until Coder reports `deleted` (or `stopped`), then `:gone`. A workspace Coder no longer knows is `:gone` |
| `observe(env)` | `:running` while the environment is heard, with **no call**, as `ManualAdapter#observe`. Not heard: one `status` call → `:stopped`, `:missing` (404 or `deleted`), `:running` with the agent `disconnected` or `connected` (the host runner is down), `:unknown` when Coder cannot be asked |
| `check_health(runner)` | §6.3 |
| `availability(runner)` | The launch's own checks, on the adapter (§8) |

`on_release: stop` keeps the stopped workspace for inspection after a `fresh` session; its row is `gone`, so it no longer counts against `max_environments`, and the platform does not delete it. The runner page says so. A reused (`reuse`, `reset`) environment is not stopped when idle: an idle-stop timer is deferred (§14).

### 6.3 `check_health`

`Runners::HealthCheck` already runs every minute for every live runner and applies the adapter's `Health` (status, reason). The coder adapter returns, in order:

1. The integration is `inactive` or `error` (a column, no IO): `unreachable`, `Coder integration "<name>" is <inactive | in error: <settings.error>>. Reconnect it, or pick another runner.` This is §2.6's rule, and it needs no Coder call.
2. Otherwise, **at most once every 5 minutes** (the stamp is `runners.health["checked_at"]`; in between the last result is returned unchanged, so a minute-by-minute sweep does not become a minute-by-minute call per runner): `IntegrationService#test` (the token). Refused: the integration becomes `error` and the runner `unreachable` as in 1. Coder unreachable: `unreachable` with the reason. The token being refused is the only thing that marks the integration.
3. The template exists and the version resolves: `GET templates/{id}`. A 404 is `unreachable`: `Coder template <id> was not found on integration "<name>".` (the check task #209 moved out of the model).
4. `config.parameters` against the version's rich parameters: a name the template does not have, a value its `validation_regex` or `options` refuse, or a required parameter with no default and no value, is `degraded`, naming each. New sessions are still admitted, per §2.5, and a provision with a bad parameter fails with Coder's own message.
5. The last `Settings.runners.max_consecutive_failures` allocated environments all `failed` while provisioning or booting: `degraded`, `Provisioning has failed N times in a row: <last reason>`. This is the signal for a template that cannot build or a host runner that cannot start, and the one place a provider that is out of capacity at build time becomes visible (§10).
6. Otherwise `connected`.

`status_reason` is capped at 255 characters, as `ManualAdapter` caps it.

## 7. The bootstrap token, its exchange, and delivery of `aixle-runner`

### 7.1 The token

`RunnerCredential` gets `kind: bootstrap` (enumerize; `arboot_` prefix in `Runners::Credentials::PREFIXES`). It is minted by `Credentials.mint_bootstrap!(environment)` under the runner's `FOR SHARE` lock like the other issuers, stored as a digest only, **single use**, with `expires_at = now + max(30 minutes, bootstrap_timeout)` (§9.2). Minting for an environment revokes its earlier unused bootstrap tokens, so a revival leaves one live token. `runner_credentials.kind` has no database check, so there is no constraint to change.

### 7.2 The exchange

`POST /runner/v1/check-in` already exists for `manual`, authenticated with the access token. It accepts the bootstrap token too (`authenticate(:access, :bootstrap)` in `CheckInsController`). With a bootstrap token:

1. The token is spent under the environment's row lock (`used_at`), as a registration token is spent at `register`. A second use is `401 invalid_token`.
2. The environment must be `booting`; otherwise `401 invalid_token`.
3. Any earlier credential family of the environment is revoked (a revival), and `Credentials.issue_pair!` issues a new pair.
4. `booting → idle` (`check_in`). The os, arch and facts of the report are recorded, and a failed preflight (§7.4) moves it to `failed` instead, with the failure as the reason, exactly as `Runners::CheckIn.fail_for_preflight!` does for `manual`.
5. The response is `manual` check-in's, plus `credentials` in the shape `register` answers.

The code is `Runners::CheckIn.exchange!(environment, token:, …)` beside `check_in!`, taking named parameters as the patterns require; the controller maps the body and the header. `PROTOCOL.md` §5.9 gains the bootstrap form, with `check_in.request.json`/`check_in.response.json` schema changes and conformance fixtures (17d). A bootstrap token is refused on every other endpoint (`authenticate(:access)`), and the gateway keeps checking the runner's status on each request.

Credential validity for provisioned environments follows §9.2: invalid when the environment becomes `gone`, and now also when it leaves `idle`/`resetting` for `tearing_down` or `failed`. `RunnerGateway::V1::ApplicationController` refuses those states for these environments (a `failed` `manual` machine keeps its credentials so Return to service can reach it; a `failed` provisioned one never needs to).

### 7.3 Delivery: `inject_bootstrap`

`Runners::Bootstrap::Script.render(environment, token:)` builds a POSIX `sh` script and `CoderAdapter#inject_bootstrap` runs it with `Coder::SshRunner#exec(workspace_name:, command: "sh -s", stdin_data: script)`. The token is in the script, so it travels on stdin, never in argv or `ps`, as §5.1 says.

The script:

1. Takes the version and the SHA-256 for the workspace's `uname -m` from `Runners::Release` (the pins, §14.3), written into the script by Rails. **The script is rendered and piped, not fetched.** DESIGN.md's `GET /runner/v1/install.sh` row is dropped: an endpoint that serves a script the workspace then pipes into `sh` is a second place to get the hash wrong, and the platform already knows the pins. The binary itself is fetched from the existing `/runner/v1/releases/:version/:platform` (302 to the release asset).
2. Downloads to a temp file, **verifies the SHA-256, and stops with a distinct exit code on a mismatch**, then installs to `~/.aixle-runner/bin/aixle-runner`. Nothing is installed from an unverified download.
3. If a live host runner exists for this state directory (the runner holds an exclusive `flock` on it), runs `bootstrap` against it only when the platform is reviving; otherwise stops it first so the new credentials are the ones in use.
4. Runs `aixle-runner bootstrap --url <platform> --state-dir ~/.aixle-runner/state --token-stdin <<'EOF'` with the token as a here-document (a shell builtin, so not argv). `bootstrap` calls the exchange, stores the credentials atomically in the state directory (`0600`), and exits.
5. Starts `aixle-runner --mode host --state-dir …` detached: a `systemd --user` unit when `systemctl --user` works, else `setsid nohup`. It survives the SSH session, and `Restart=always` on the unit restarts it. Without `linger` a user unit stops at logout; the script runs `loginctl enable-linger` when it can and says so otherwise, and the reconciler's re-inject (§9) is the fallback.
6. Prints a one-line result and the last lines of the runner's log, which the adapter keeps as the bootstrap output for the `bootstrap_timeout` message (§10).

The workspace's user runs the runner, not a dedicated one: Coder's convention is one non-root user who is in the `docker` group per the template. The runner's preflight (Docker API ≥ 1.41, free disk) is the existing one and is reported at check-in.

### 7.4 The VM-only rule

DESIGN.md §2.6 and §6.9.7 say the host runner's start check refuses a workspace that is a container or a pod, while decision 4 of 8b says there is no start check for a Docker daemon that cannot see the runner's files. They are different cases and both stand:

- **Decision 4 stays** for a daemon that cannot see the files (a remote `DOCKER_HOST`, the host's Docker shared into a container). It is found by Docker's refusal of the sidecar's bind mount, as built.
- **`aixle-runner bootstrap` adds a preflight** that the machine is not a container or a pod: a `/.dockerenv` file, a container cgroup, `KUBERNETES_SERVICE_HOST` in the environment. If it is, `bootstrap` exchanges the token and reports `facts.preflight_error` ("This workspace is a container or a pod. Aixle coder runners support virtual-machine workspaces only"), so the platform records it as `failed` with that reason. The existing `fail_for_preflight!` carries it to the runner page and to the session as the §8 message. It is not run by `configure` or `--mode host`, so a `manual` runner started from the published image is unaffected.

The false positive is a nested-Docker workspace (sysbox, envbox) that is a container on purpose. It is refused too, and §2.6's limit says so. A customer who needs it is a case for a later decision (§14).

## 8. Sessions: how the allocator and the release fit `Sessions::Lifecycle`

**`create_container`** (`RunnerRuntime`): `Allocator.acquire!(session)`, then `container.start` once the environment is ready, as today. The `Pending` and `CapacityError` waits above reach `capacity_wait`. A `ProvisionError` becomes a `CreateRefusedError`: the phase fails with the provider's message and the session ends through the usual path. The admission's `runtime_id` is persisted before the phase (`AdmittedPhaseActivity`), so the cleanup always runs.

**`start_container`**: unchanged, a `status` loop. The environment is already checked in.

**Cleanup** (`cleanup_session`, then `Allocator.release!`):

| Environment when the session ends | What happens |
| --- | --- |
| `requested`, `provisioning`, `booting` (never started) | The hold is cleared; no op is sent. The environment keeps booting as a warm one (`reuse`, `reset`), or is torn down (`fresh`) |
| `idle`, `reuse` | `container.stop`, `env.scrub`, hold cleared. A failed scrub is followed by `env.reset`, as on `manual` |
| `idle`, `reset` | `container.stop`, `env.reset`, hold cleared (container mode only; §7.1) |
| `idle`, `fresh` | `container.stop` (best effort), hold cleared, `begin_teardown`. No scrub: the workspace is deleted |
| Any, and the scrub or reset failed, or the session is the `max_consecutive_failures`th failed one in a row | `mark_failed`, hold cleared. The reconciler tears it down and the next acquire creates a replacement. Unlike `manual`, a `coder` environment does not stay `failed`: nobody can fix a machine we created, and Return to service is `manual`-only (`Machines::NotManual`, as built) |

**The admission slot.** `Allocator.release!` clears the hold at the end of cleanup, and the session's admission is released as today, after `Sessions::Lifecycle.finalize`. A teardown that is `tearing_down` does not hold the admission slot: the slot is the company's concurrency, and the pool's own bound is `max_environments`, which counts `tearing_down` rows until they are `gone`. This is a change from §10's "or teardown confirmed", which assumed the teardown was what the slot protected.

**Lifecycle rules.** The allocator and provisioning never write a session's state. Where an environment fails under a live session (§9) the caller is the reconciler or the dead-container scan, and it uses `Sessions::Lifecycle.fail_if(session, error_message:)`, as `Runners::ContactLoss` and `Runners::Revocation` do; the slot then follows the existing cleanup. The `terminal_sessions.runner_environment_id` write stays the one `Machines.take!` makes today (a column with no owner method and no side effect). Nothing here depends on #283's `transition!` signature.

**Interactive sessions** (#277) work as on `manual`: the host runner on the workspace opens the tunnel, the relay maps the session to the environment through the hold (`RunnerEnvironment`'s `after_save` signal), and the browser path is unchanged. The one coder-specific requirement is egress from the workspace to the relay host, which §12.5 already lists.

**Launch refusals** become polymorphic. `Runners::Resolver` calls `Machines.availability(runner)`, which is `manual`'s. `Adapter` gets `launch_refusal(runner)` (nil, or `Refusal(reason, message)`), declared on the base with no default implementation. `ManualAdapter` delegates to the existing availability code; `CoderAdapter` refuses an `unreachable` runner with `runner_unreachable` and §8's message ("Runner "X" is unreachable: <the health reason>"). A `degraded` runner is admitted.

## 9. The failure paths of §8 on `coder`

`Runners::Reconciler` (`app/services/runners/reconciler.rb`), run every minute by a new activity in `runner_health_check_workflow` (one place for the runner sweeps; it runs after the health check). Each rule works on one provisioned environment and is idempotent; one that fails is logged and does not stop the others, as `HealthCheck.run!` does.

| Condition | Detected by | Outcome |
| --- | --- | --- |
| **Provisioning fails** (template refused, build failed) | `provision`/`prepare` raise `ProvisionError` | `mark_failed` with Coder's message. A session holding it fails with that message ("Coder: template parameter `instance_type` invalid", or the build's error). The reconciler tears the environment down |
| **Build times out** | `boot_started_at + bootstrap_timeout`, in `advance!` and in the reconciler for an environment no session is advancing | `mark_failed`, teardown; the session fails with the `bootstrap_timeout` message below |
| **No check-in within `bootstrap_timeout`** | Same rule, `booting` | "Workspace started but aixle-runner did not check in within 15 min. Check that the workspace can reach <platform host>:443." plus the last lines the script printed (§7.3). `failed`, then teardown |
| **Workspace stopped or gone under a session** (a spot reclaim, as `DeadWorkspaceReaper` describes: the build is a succeeded start and every agent is `disconnected`) | `ScanDeadContainersActivity` calls `observe` for a machine it does not hear. `:stopped`/`:missing` now count as dead: the scan's existing two-sighting `confirm_or_mark` fails the session with "Workspace stopped or deleted by Coder (a spot reclaim, or a template autostop)" | The session fails after the scan's confirmation (about 3 minutes), not the 15-minute grace. The environment is `failed`, then torn down. `observe` returning `:running` with a disconnected agent changes nothing: it falls to the grace (`ContactLoss`), which is the evidence the reaper's doctrine asks for, and the environment is failed only after that |
| **Host runner down, workspace up** | An `idle` or `busy` environment not heard for 5 minutes with `observe` `:running` and the agent `connected` | The reconciler re-runs `inject_bootstrap` through `restart`, once every 5 minutes. A session's container keeps running on the VM (§6.7), so a restarted runner picks it up. If it is still not heard after `ContactLoss::GRACE` the session fails by the grace and the environment is `failed` |
| **The integration's token is revoked** | `check_health` (§6.3) every 5 minutes; any adapter call that gets 401/403 calls `IntegrationService#test` | The integration is `error`, the runner `unreachable`, launches are refused with the integration named. Running sessions continue: the host runner talks to the platform, not to Coder. A session waiting in provisioning fails with "Coder integration "X" rejected its token. Replace the token." Teardowns that cannot reach Coder stay `tearing_down`, retried every minute, and count toward `max_environments` until the token is replaced. The Revoke of the runner (not of the token) is a different path, below |
| **The provider is out of capacity** | Two cases. A create refused for quota (Coder's error body names it): `CapacityError`. A build that fails for lack of instances: Coder reports a failed job | The refusal is `capacity_wait` with `runner_capacity` and the message "Waiting for capacity on runner "X"." (§10, row 9 of §8). The failed build is a diagnosed failure of that session, and it counts in the streak that makes the runner `degraded` (§6.3 rule 5), which a person sees. Parsing provider errors for "out of capacity" is deferred (§14) |
| **Runner revoked or deleted** | `Runner`'s `after_save` already ends its sessions (`Revocation.end_sessions!`) | It now also `begin_teardown`s every environment that is not `gone`, best effort. The reconciler finishes them. The runner page lists any that Coder would not delete, which is §9.3's "must be removed by the customer" |
| **Disabled** | | No new sessions; environments are left. Running sessions finish |
| **Environment revoked from the runner page** | `Registration.revoke!` | Credential family revoked, `gone` for `manual`; for a provisioned environment `begin_teardown` first, `gone` when the workspace is deleted |

The conditions the reconciler must never act on: an environment held by a session that has not ended and is heard; any workspace not named by a `runner_environments` row (§2); and, per the reaper's cap, more than `Settings.runners.max_teardowns_per_run` (default 3) workspace deletions in one pass. A provider outage that fails every build at once must not empty a pool in a single sweep.

## 10. Admission, and the §8 rows that change

No change to admission (§10): a `coder` session is admitted by its project's pool and the company limit, and `max_concurrency` is not enforced. The runner's own capacity is the allocator's:

- At `max_environments`, or the provider refusing a create for quota: `CapacityError`, `reason: "runner_capacity"`, message "Waiting for capacity on runner "X" (2 of 2 environments busy)." The session keeps its reservation in `capacity_wait`.
- A new or reviving environment: `Pending`, `reason: "runner_provisioning"`, message "Starting a workspace on runner "X" (building)." / "(waiting for aixle-runner)."

Both are wait reasons the reapers leave alone, so a long cold build does not lose the reservation. The session page and the runner page's environments table show the same states.

## 11. UI and API surface

17g, behind `external_runners`, with no new flag (§12.2 phase 5). `Runners::Adapter::REGISTRY` gains `"coder"` in that task, not before: until the form, health, allocator and sessions all exist, the type must not be creatable.

- **Form.** Step 2 for `coder`, generated from `ConfigSchema.for_type("coder")` as for `manual`: the integration select (the project's visible active Coder integrations, §2.6), `template_id`, `template_version_policy`/`template_version_id`, `parameters` as name/value rows, `on_release`, the `container` options, `reuse_policy` (all three, with §7.1's wording), and `max_environments` (step 3, already shown for a `provisionable` type). A template picker backed by `GET .../runners/coder_templates?integration_id=` (a service call through `Coder::Api.list_templates`, returning name, id, active version and its parameters) fills the id and suggests the parameter names; the plain id remains accepted. "Connect" runs the config checks and `Runners::HealthCheck.check!` inline, as §11 says. `Runners::Save` and the controllers already refuse a type with no adapter; adding the adapter lifts "not available yet".
- **Runner page.** The Machines section becomes **Environments** for `coder`: key, state (`requested`…`gone`, with the reason), the session it holds (link), last heard, runner version, workspace link to Coder, and the actions Rebuild (`begin_teardown`) and per-machine Revoke. The overview adds the integration, template and the resolved version. A `manual` runner's page is unchanged. The runners list shows "environments busy/total" with `Runner#machine_counts` extended to a provisioned runner, counting every environment not `gone`.
- **Integration removal.** `IntegrationsController#destroy` keeps refusing while a runner references the integration (`dependent: :restrict_with_error`), and its message now names the runners. Disconnecting the integration is not a way to delete a runner's environments: delete the runner first, which revokes and tears down.
- **Docs.** The user guide and its portal mirror (`docs/user-guide/` and `app/frontend/pages/Docs/data/pages/`), the VM-only limit, what `on_release: stop` leaves behind, and the egress the workspace needs.

## 12. The split of item 17

Each task is cut when the one before has merged, against the code as it is then, as §15 says. All are behind `external_runners`. The `coder` type becomes creatable only in 17g.

| Row | Delivers | Tests | Staging check | Item 18 (§12.5) needs from it |
| --- | --- | --- | --- | --- |
| **17b** The allocator and the provisioned states, no Coder | `Runners::Allocator` (`acquire!`, `release!`, `let_go!`, `fail!`) replacing the `Machines` calls in `RunnerRuntime`, `Revocation`, `ContactLoss`, `CheckIn`. The provisioned arm of `RunnerEnvironmentStateMachine` and the migration (§5). `Runners::Provisioning.advance!`. `Adapter#launch_refusal`, `RunnerEnvironment#in_service?`, the `runner_provisioning` wait reason (model, `launchStatus.ts`). `Settings.runners.bootstrap_timeout` | Model and state-machine tests for every event and refusal. Allocator tests with a fake provisionable adapter registered in the test only: steps 1 to 4, the `max_environments` count including `tearing_down`, two sessions racing one idle environment (`machines_concurrency_test.rb`'s pattern), a retried acquire, revoke vs acquire lock order. A `CapacityError` and a `Pending` through `AdmittedPhaseActivity` end as `capacity_wait` with the reservation kept. The `manual` suites (`machines_test`, `runner_session_launch_test`, `runner_failed_machine_test`) pass unchanged | The §12.4 `manual` run: a session, two in parallel with one machine (`runner_capacity`), a reset. Nothing visible changes | The `capacity_wait` path of step 4 |
| **17c** The Coder client and the adapter's provider side | `Coder::Api` and `WorkspaceService` extensions (§6.1). `CoderAdapter`: `capabilities`, `provision`, `prepare`, `teardown`, `observe`, `check_health`, `launch_refusal`. The pool exclusion (§2). The integration-state rule. `Reconciler`'s teardown and boot-timeout rules. Not registered in `REGISTRY` | `Coder::Api` request tests with WebMock, as `api_test.rb`. `WorkspaceService` status mapping for every build state. Adapter tests for each health outcome in §6.3 (token refused, template 404, bad parameter, streak), `provision` idempotent on a retried name, a quota refusal as `CapacityError`. The hosted allocator and reaper tests with a runner workspace in the listing (it is skipped) | A `bin/rails runner` script on staging: build a `coder` runner row with the factory path against the staging integration, run `check_health`, `provision`, `prepare` to `:ready`, `teardown`. The hosted pool's next allocation and the next reaper sweep ignore the workspace | A template that builds, with its parameters, recorded; the answers to §12.5's three questions (Docker daemon, disk, pruning) can be read from the workspace |
| **17d** Bootstrap and the runner | `bootstrap` credential kind and `Credentials.mint_bootstrap!`; `CheckIn.exchange!` and the gateway's bootstrap form; `Bootstrap::Script`; `CoderAdapter#inject_bootstrap`; `aixle-runner bootstrap` with `--token-stdin`, the VM-only preflight and a user-mode state directory (Go); `PROTOCOL.md` §5.9, schemas and fixtures | Credentials tests (single use, expiry, revoked earlier tokens, runner lock order). `CheckIn.exchange!` tests including a failed preflight and a refused state. A conformance fixture for the exchange, run by `RunnerProtocolConformanceTest` and the Go fake gateway. Go tests for `bootstrap`, the preflight (container, pod, VM) and the atomic credentials write. Script rendering tests: the SHA-256 and the token placement, the mismatch exit | A workspace from 17c is bootstrapped by `inject_bootstrap`, the environment reaches `idle`, and an op round-trips (a `status` op). A tampered pin refuses the install | The check-in message of §8 on a template with no Docker; the install on a template the design never saw |
| **17e** Sessions on `coder` | `RunnerRuntime` calling the allocator for a provisioned runner end to end: `create_container` (`Pending`, `ProvisionError`), `cleanup_session` by `reuse_policy` (`reuse`, `reset`, `fresh`, never-started), `on_release`, failed-environment replacement, `Resolver` through `launch_refusal`, the bootstrap-timeout failure and message. Still not creatable from the UI: the runner is created from the console, storing the capabilities the adapter derives | `runner_session_launch_test`-style integration tests on a provisioned runner with the provider stubbed: one session, two in parallel, a third waiting (`runner_capacity`), reuse gets the warm environment, `fresh` ends `gone`, a failed scrub replaces the environment, a booting environment whose session is cancelled. `cleanup` with `Sessions::Lifecycle.finalize` ordering | One non-interactive session and an interactive one (the tunnel) on a staging `coder` runner created from the console; both parallel and queued cases | §12.5 steps 3 to 5 (run, two parallel plus a queued third, warm reuse) |
| **17f** Failure paths | `Runners::Reconciler` complete (dead workspace, host runner down, re-inject, teardown pacing and cap), `ScanDeadContainersActivity` for `:stopped`/`:missing`, `Revocation` and per-machine Revoke tearing down, the integration-token paths of §9, the runner page's list of workspaces left behind | One test per row of §9, with time travel for the 5 and 15 minute rules. The scan's two-sighting rule on a `:stopped` workspace. A teardown that Coder refuses, retried. A deletion cap | Stop a workspace under a session in the Coder UI: the session fails within about 3 minutes and the environment is replaced. Revoke the integration token: `unreachable` with the integration named, then replace it | §12.5 steps 2, 7 to 9: the token revoke, the lost connection, the runner restart, the runner revoke |
| **17g** The type, the form and the page | `coder` in `REGISTRY`, the form, the templates endpoint, the Environments section, Rebuild, per-environment Revoke, the runners list column, the integration-removal message, the user guide and its mirror, DESIGN.md's built-state notes | Frontend tests for the form, schema errors at their fields, the page for each state. Controller and policy tests (company and project, scope rules of §2.6). The user-guide mirror pair check | The whole of §12.5 by hand, without the console | The type creatable from the UI, which is what §12.5 step 1 starts from |

Row 18 stays the QA task of §12.5 and is cut after 17g. Its steps 10 and 11 (a second project's refusal, hosted unchanged) need no code from item 17 and are the existing selection and §12.3 regression tests.

## 13. Testing approach

Tests follow the area's conventions: Minitest and FactoryBot, no fixtures, sequences in factories (`test/factories/runners.rb` and `runner_environments.rb` get `:coder` and `:allocated` traits). Coder is stubbed at the HTTP layer with WebMock, as `test/services/coder/` does; `SshRunner` is replaced through a dependency passed to the adapter (as `Coder::HealthCheck` takes one), never stubbed with a block returning a fake object. Concurrency tests copy `machines_concurrency_test.rb`. The Go changes run in the `Runner (Go)` job. The `Runners::Allocator` public contract is tested for a `manual` runner too, so 17b's move is covered before any Coder code exists.

## 14. Edge cases and risks

- **The 30 s retry interval is a floor on start latency.** A workspace that is ready 5 s after a retry waits up to 25 s more. Accepted: a cold build takes minutes. Lowering `CAPACITY_RETRY_INTERVAL` would affect every runtime.
- **`coder` CLI in the worker.** `SshRunner` needs the CLI in the process that runs the activity. The Coder MCP tools run it today in the web or worker image; 17d checks that the container-workflow worker has it and says so in its PR if not. The alternative, running the install through a runner-less path, does not exist: the agent is not up yet.
- **Coder's quota error shape is unverified.** §9's capacity row reads a create refusal's body. 17c confirms the status and message on staging and records them; until then a refusal that is not recognized is a `ProvisionError`, which fails the session with Coder's message and is visible in the streak, not silent.
- **Two callers advance one environment** (the session's phase and the reconciler). The row lock and idempotent steps make a repeat a no-op; the one non-idempotent step, minting a bootstrap token, revokes the previous unused one.
- **The bootstrap token is in a script on stdin.** It is single use, expires, and is never logged: `SshRunner` redacts the integration token, and `Script.render` output is excluded from logs and Sentry breadcrumbs (the gateway's existing `RunnerGateway::` rule covers the exchange). The adapter's captured output is the runner's log tail, which does not contain the token (`bootstrap` never prints it).
- **A stopped workspace restarted by `prepare`** loses processes, not its disk. The revival always runs the exchange, so a lost credentials file is irrelevant (§5).
- **Spot reclaim during `booting`** reads as no check-in, and ends at `bootstrap_timeout`. The wait is up to 15 minutes before the diagnosis, which is the same wait as any boot failure. Accepted by §6.9.7's rule (H2, with a clear error).
- **Hosted and runner workspaces on one integration share Coder quota.** A customer's Coder quota or provider limit applies to both. The runner page does not show it. Documented in the user guide.
- **A customer prefix collides with the key shape.** Excluded by table match, not by name (§2).
- **Cost.** Idle `reuse` workspaces run until the template stops them. The platform neither stops nor deletes them (§14 deferred).
- **No production identifiers** appear in this document. The spot-reclaim and quota events are described in general terms.

## 15. Decisions and assumptions

| # | Decision | Source |
| --- | --- | --- |
| D1 | The hosted pool's allocator, lock, quarantine, probe, reaper and repo bootstrap are not reused; the API client, the workspace service, the token service, the integration service and `SshRunner#exec` are. Runner workspaces are excluded from the pool by table match | Task #284 asks for this decision; the code reading in §2 |
| D2 | `busy` is not a state: `idle` with a hold | `RunnerEnvironment#busy?`, patterns "Model Predicates" |
| D3 | Provisioning advances one step per `capacity_wait` retry through a `CapacityError` subclass and a new wait reason `runner_provisioning`; no new workflow | `AdmittedPhaseActivity`, `ContainerWorkflowV2`; row 9 of §8 asks for `capacity_wait` |
| D4 | Rebuild is retire-and-replace. `Adapter#reset(level: :rebuild)` is not built | Simplicity; amends §5.1 and §7.2 |
| D5 | One `bootstrap_timeout` setting, 900 s | `coder` is the only provisioning type for now; amends §8's "10 min, 15 for `coder`" |
| D6 | The bootstrap script is rendered and piped, `GET /runner/v1/install.sh` is not built | §14.3's pins are already on the platform; amends §6.2 |
| D7 | Every boot ends in a bootstrap exchange, so a revival mints a new token and credential family | Avoids relying on a file a stopped workspace may lose |
| D8 | `on_release` applies to teardown only; an idle-stop timer is not built | §2.7's definition ("what `teardown` does") |
| D9 | `check_health` calls Coder at most every 5 minutes; the integration's state is read on every run | §2.5 ("passed within the last 5 minutes"), a column read costs nothing |
| D10 | A quota refusal at create is a wait; a failed build is a failure that feeds a `degraded` streak | Two different facts: the platform may retry the first, and not the second |
| D11 | The VM-only rule is a preflight of `aixle-runner bootstrap`, reported at check-in; the Docker-visibility check stays as decision 4 left it | §2.6, §6.9.7 and decision 4 do not conflict once the two cases are told apart |
| D12 | A tearing-down environment holds no admission slot; the pool's limit counts it until it is `gone` | Slot is the company's concurrency; `max_environments` is the pool's |
| D13 | Launch refusal is an adapter method, not a type check in `Resolver` | The patterns' "one decision, one factory or polymorphism" |
| D14 | The integration's removal stays refused while a runner references it | The existing `restrict_with_error`; `IntegrationsController#destroy` already shows it |
| D15 | A failed provisioned environment is torn down and replaced; Return to service stays `manual`-only | §5.2 ("`failed` environments are torn down by the reconciler and never reused, except on `manual`") |

**The reviewer is asked to check** D3 (the new wait reason), D4, D6 and D12, which amend DESIGN.md, and §12's order.

## 16. Deferred, and what to check

- **An idle-stop timer** for `reuse` environments (cost). Cut when a customer's bill shows it.
- **Classifying provider capacity errors in a failed build** (EC2 instance-type exhaustion and its like). It needs a per-provider reading of the build's error; the streak makes it visible until then.
- **Nested-Docker workspaces** (sysbox, envbox) as a supported shape. Refused by §7.4 until someone needs it.
- **A pool floor** (a minimum number of warm environments) and **warm-disk affinity**. The second is out of the plan (Alex, 2026-11-13).
- **The `host` execution mode** (row 20), Kubernetes (row 19) and the relay rows 24 to 27: out of scope, as the task says.
- **To check in 17c on staging:** the quota error's status and body, the workspace-status fields of `GET /workspaces/{id}` for a stopped and a reclaimed workspace, and the template's Docker daemon, disk and image pruning (§12.5's three questions).
- **To check in 17d:** that the worker image has the `coder` CLI, and `systemd --user` availability on the staging template.
