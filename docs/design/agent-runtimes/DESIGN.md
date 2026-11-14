# External runners for agent sessions — design

**Status:** accepted, revision 5; implementation in progress. The §15 tasks marked
**Done.** are built, and the sections they touch carry "What v1 has so far" notes. The rest
of phase 2 (§15 tasks 6b and 8–10) and phases 3 to 7 are still pending: what this document
says about them is design, not code yet.
**Created:** 2026-10-20 · **Revised:** 2026-11-06
**Task:** #163 "Tech design: external agent runtimes (pluggable runners)"
**Baseline:** `origin/develop` @ `a837d6fd` (the feature flag chain #166–#172 is in)

**Decisions of 2026-11-13: the plan is trimmed** (Alex, task #243). They amend revision 5 in
place and are not a new numbered revision:

- **No compatibility with earlier versions of the runner feature until it has users** (§12.2).
  Nobody outside our test company has the `external_runners` flag, and nobody will until
  phase 4. Until then a change to runner data or behaviour keeps no shims: a migration may
  rewrite or drop runner rows, and the only such data is on staging.
- **Removed from the plan:**
  - "Start from a clean workspace" for one run, on the run drawer and the session form (§7.2);
  - the facts (Docker version, free disk, images present) in the Machines list; check-in
    still collects them, as built (§2.2, §11);
  - the Reset action on a machine (§7.2, §11);
  - Force release: per-machine Revoke takes its place, and also frees the slot held by a lost
    machine's session (§6.7, §9.3);
  - the "runner connection lost, agent still running" banner on the session page (§6.7, §11);
  - the machine's own cleanup of its containers and volumes on Revoke: credentials are revoked
    at once and the operator removes what is left (§9.3);
  - the runners and environments dashboards in Administrate (§11);
  - the runner version against `recommended_version` on the runner page (§11, §14.2);
  - Rotate token on the runner page (§3.2, §9.2, §11);
  - `config.reconnect_grace` as a runner setting: the grace is fixed at 15 minutes, and
    reconciliation (task 11b) uses that constant (§2.7, §6.7);
  - the ephemeral registration (§6.3), with its column and its refusal; a register request
    that still sends `ephemeral` registers, because the schema ignores unknown fields;
  - task 15 of §15 as a task of its own (§12.3 keeps the exit condition and the trigger), and
    §12.4 step 12 (removing the flag mid-session).
- **In the docs only, not on the runner page:** the §9.7 disclosure and the egress list (§9.5).
- **Kept in task 12's remaining part:** per-machine Revoke, the first-seen IP and
  `created_by_id` in the Machines list, "machines busy/total" in the runners list, and the
  `manual` user docs with the §9.7 disclosure and the egress list. `max_concurrency` stays on
  the runner, not enforced while task 9 is deferred (§10).
- **Task 11 is split:** 11a is #242 (scrub, `reuse_policy`, the reset escalation, Return to
  service); 11b is reconciliation (the running-session summary in the heartbeat,
  heartbeat-based `observe`, the fixed 15-minute grace and the slot release on reconnect).
  Task 13 is empty after this, so its row is gone (§15).

**Decisions of 2026-10-30, after task 4** (#193, PR #614). They amend revision 5 in place
and are not a new numbered revision:

- **Interactive work on runners waits for the tunnel, with no interim checks.** Named
  companies get the `external_runners` override only after phase 4 (§12.2, §15 task 16);
  until then the flag stays on for the test company only. The run-override and publish
  `interactive_terminal` checks and the Base Resources interactive-step warning are not
  built (§4, §11).
- **Project-move edge cases are accepted, not fixed:** a queued manual launch naming a
  runner, the lock order against a concurrent workflow save, and a project that owns a
  runner (§3.4, "Known limitations of the move").

**Decisions of 2026-11-05 and 2026-11-06, task #205** (Alex). §6.9 works out where the
session ops, the callback proxy, the live log and the tunnel run on each type, with the
research in [`prior-art.md`](prior-art.md). The sections each decision changes carry a short
"Decided (§6.9)" note; their full rewrite is left to the task that implements them (§6.9.6):

- **Nothing of the runner in the agent container on any type.** The environment's owner (the
  host runner on `manual` and `coder`, the controller on `kubernetes`) does everything that
  needs the environment credential, from outside the container.
- **`kubernetes`:** the controller runs the session ops through the Kubernetes API, as the host
  runner does through the Docker API on `manual` (§6.9.2).
- **The callback proxy** is a sidecar in the agent's network namespace, on `127.0.0.1`,
  relaying to the owner (§6.9.3).
- **The live log** was to be the container's own log, followed by the owner (§6.9.4). **Not
  built (Alex, 2026-11-11):** a runner session's terminal is read as a hosted one's, through
  `exec` and `tmux capture-pane` (§6.5). A runner
  session ends as a hosted one does: by `finish_session`, by the no-output check (`Sessions::Checks::NoOutput`), or by a dead
  container.
- **The tunnel** is relayed by the owner (§6.9.5).
- **No complexity for rare, non-critical cases.** Each case is weighed by its harm and
  likelihood (§6.9.7).
- **Coder (2026-11-06):** v1 supports only Coder workspaces that are virtual machines. Container
  mode runs one session per workspace (§15 row 17); the `host` execution mode is for Coder only
  (§6.8, §15 row 20).

**Revision 5** applies the six edits of the revision 4 review. Revision 4 (`2d5532f3`)
stands where this list does not touch it; the delivery order, the flag design and the
container-mode decision are unchanged:

- **The future execution mode is `host`, not `split`.** The axis is named by what a user
  chooses, where the agent CLI runs: `container` or `host`. The key is still not declared
  in v1 (§1.1, §6.8, §15 task 20).
- **`config.docker` is `config.container`**, because the options belong to container mode
  and the same concepts (resources, the image) exist on `kubernetes`, where there is no
  Docker. `image_override` moves into it for the same reason (§2.1, §5.1, §6.8, §7, §11,
  §15).
- **One authoritative runner configuration table** (§2.7): every key, its type, default,
  the types it applies to, and the keys that arrive later. The scattered mentions now point
  at it.
- **§15 task 1 is split** into 1a (the flag and the platform-wide `FeaturesResource`
  switch) and 1b (migrations and models), so each can be cut and reviewed on its own.
- **`remove_by` is a checkpoint, not a schedule** (§12.1).
- **A new §17 records two operational gaps** a full version needs, machine reboot
  semantics and disk lifecycle, deliberately outside the seven phases and without a task.

**Revision 4** applies the decisions of 2026-10-26. Revision 3 (`a7c44d1f`) stands where
this list does not touch it:

- **Real feature flags.** `Settings.runners.enabled`, `companies.runners_enabled` and
  `Settings.runners.types` are gone. Two declared flags, `external_runners` and
  `external_runners_kubernetes`, checked with `Feature.enabled?(..., company:)`, rolled out
  by per-company overrides from `/admin`. No ENV lock and no kill-switch path are designed;
  removing a company override is the stop button (§12.1, §12.2 as flag states, §11, §12.3).
- **A `manual` runner type.** The operator runs `aixle-runner` on a machine they already
  have, registered with a one-time token, modelled on GitHub self-hosted runners. The
  platform holds no credential into that machine. It replaces the planned SSH "machine"
  type, which this design no longer has (§1, §2, §4, §5, §6.3, §7, §9, §10, §11).
- **Container mode is the only execution mode in v1**, on every type. The finding that
  drives it is written down in §6.8: the stock image starts five services, and half of the
  MITM stack has to live in the CLI's own process. Coder `native` mode is dropped. The host
  execution mode (services in containers, CLI on the host) moves to the last phase with its
  cost spelled out, and the CLI-source question goes with it (§6.8, §15).
- **Setup and cleanup.** Customer pre/post session hooks are not in v1, by decision. Our
  own per-session preparation and cleanup stays. On `manual`, scrub uses a throwaway OS
  user per session in host-side execution and the session container in container mode, and
  `reuse_policy` is defined per type (§7).
- **Delivery order.** `manual` is the first type (phase 3), the interactive tunnel
  follows (phase 4), then Coder, Kubernetes and the host execution mode (§12.2, §15).
  The breakdown is a map: tasks are cut one at a time (§15).

**Revision 3** applies the correction to the revision 2 review. The design no longer
depends on `aixle-infra`, the infrastructure of our own production and staging
deployment, which is not part of the product:

- Staging validation names no Coder template. It uses the staging Coder integration
  configured on the test project and whatever template it offers at test time (§12.5,
  task 14).
- The Kubernetes controller's RBAC is derived from least privilege for what the controller
  does in one namespace, not from our runtime ClusterRole (§9.6).
- The `aixle-infra` open item is dropped (§16), along with the staging-template citation
  in §6.8.

**Revision 2** applied the design review of revision 1 (`967aed2d`):

- Coder runs the agent in Docker by default, as a runner setting `execution_mode` (§6.8).
- The "single egress host" promise is dropped. Only the inbound guarantee stays (§9.5).
- Binaries are served from GitHub Release assets behind a platform redirect, checked
  with SHA-256. cosign is deferred (§14.3).
- The runner stays in the monorepo, and the intent and triggers for extracting it are
  written down (§14.1).
- Runner and chart versions are independent of the application release (§14.2).
- `provision` does not create the environment row (§5.1).
- Hosted-untouched is written down as tech debt with an exit condition (§12.3).
- Conformance fixtures are committed in phase 2 (§12.2).
- Interactive sessions are decided (§12.2).

Everything else in revision 1 was accepted as designed.

Agents run today in one platform-managed runtime: `ContainerRuntime.build` picks Docker or
Kubernetes from a deployment setting, and every session lands there. This document
introduces a **Runner**: a connectable execution target with an adapter per type. A
workflow or a session declares where it runs, and `hosted`, meaning where it runs today,
stays the default. The model is GitHub Actions: there is a hosted runner, and users can
connect their own.

Three runner types are designed: `manual` (a machine the customer already runs, with
`aixle-runner` installed by the operator), `coder` (workspaces provisioned from a Coder
template) and `kubernetes` (pods in the customer's cluster, created by an in-cluster
controller).

The four reasons are network (the agent runs inside the customer's VPC or VPN),
environment (the customer's image, template and warm disk), load (the customer's capacity
and bill), and security (code, data and secrets stay inside the customer's perimeter).
There is also a structural reason: Coder alone would be a dead end, so the integration
point is an adapter interface, not a Coder branch.

Section 1 settles the naming and the execution model, because every later section depends
on them. Sections 2–15 cover what the task asks for. Section 16 lists what this design
could not close on paper, and section 17 records operational gaps that are deliberately
left outside the delivery plan.

---

## 1. Decisions that shape everything else

### 1.1 Naming: **Runner**

**Decision:** the entity is a **Runner** with a `type` of `hosted`, `manual`, `coder` or
`kubernetes`. The workflow and session setting is `runner`.

"Runtime" is not just ambiguous here, it is already taken. In this codebase `AgentRuntime`
(`app/models/agent_runtime.rb`, `config/agent_runtimes.json`) is the agent CLI kind
(`claude_code`, `kiro_cli`, …). `workflow_runs.agent_runtime` and
`steps.required_agent_runtime` select it, and `SessionConfigResolver` resolves it.
Calling an execution target a "runtime" would give one word two meanings across the
schema, the resolver and the UI. Two near-misses were rejected for the same reason:
"Executor" collides with Temporal and Ruby executors, and "Environment" is needed below for
something narrower.

The terms used throughout:

| Term | Meaning |
| --- | --- |
| **Runner** | The connected target a user creates, names and selects, e.g. "Prod VPC Coder (EC2 large)". One row in `runners`. |
| **Runner type** | `hosted`, `manual`, `coder` or `kubernetes`. Each type has one platform-side **adapter**. |
| **Environment** | One concrete place where sessions execute: a machine registered to a `manual` runner, a Coder workspace, or a pod in the customer's cluster. Belongs to a Runner and has its own state machine (§5.2). |
| **`aixle-runner`** | The binary that lives in an environment and speaks the runner protocol. It runs in three modes: `host` (on a `manual` machine or a Coder workspace, owns the environment and its session containers), `session` (PID 1 of an agent container) and `controller` (in a customer cluster, provisioning pods). **Decided (§6.9):** the modes become `host`, `controller` and `proxy` (the session's proxy sidecar); `session` mode is not built. |
| **Execution mode** | Where the agent CLI runs inside an environment. v1 has one: `container`, the CLI in the stock agent image, on every type (with `aixle-runner --mode session` as PID 1 in the original design; on `manual`, since task 6b, the image's own entrypoint with no runner inside, §6.8). The second value, `host` (services in containers, the CLI on the environment's host), is the last implementation phase (§6.8). Not to be confused with `aixle-runner --mode host`, the process that owns the environment in either execution mode. **Decided (§6.9):** in `container` mode the image's `entrypoint.sh` is PID 1 and nothing of `aixle-runner` is in the container; `host` mode is for Coder workspaces only. |
| **Gateway** | The platform endpoint (`/runner/v1/*`) that `aixle-runner` connects to, always outbound from the customer side. |

`hosted` is not a row. It is the absence of a runner reference (`runner_id IS NULL`), so
no existing record needs a value written into it (§2.4).

### 1.2 Execution model: the hybrid is confirmed, with one refinement for Kubernetes

**Decision:** provisioning goes through a per-type adapter, and execution happens inside
the environment over one runner protocol. On top of that, **the Kubernetes adapter
provisions from inside the cluster too**, through `aixle-runner --mode controller`, which
the customer installs with a Helm chart. The platform never holds a kubeconfig.

The reasons the hybrid holds:

1. **The network and security axes need outbound-only execution.** A customer who puts the
   agent in a private VPC to reach internal services will not open an inbound path for our
   kube-exec or SSH. With inside-out execution nothing is inbound to the customer network.
   The environment only makes outbound connections (§9.5).
2. **A second adapter is only cheap if exec, files, logs and liveness are written once.**
   Today `KubernetesRuntime` alone is about 1,900 lines, and most of that is websocket exec,
   tar copy and readiness. Rewriting it over the Coder API and then over SSH is where
   behaviour diverges.
3. **A dropped connection must not kill the agent.** The agent's process tree is local to
   `aixle-runner`. A disconnect becomes a reconnect-and-resume (§6.7) instead of an
   ambiguous dead exec stream.

**Decided (§6.9.6):** reason 2 holds on the platform side (one `RunnerRuntime`, one
protocol), while the runner gets two backends of one model for the session ops, the Docker
Engine API and the Kubernetes API, both run by the environment's owner. Reason 3 holds with
the container runtime on the customer's side (the Docker daemon, the kubelet) as the owner of
the agent's process tree, instead of `aixle-runner`.

The refinement for Kubernetes: outside-in provisioning would need a kubeconfig or service
account that can create pods and secrets in the customer's cluster, plus reachability to
the customer's API server. That is the most powerful credential the security axis asks us
not to hold. A controller inside the cluster needs only a least-privilege namespaced Role
for session pods, secrets and service accounts (§9.6). The customer installs, scopes and
audits it, and it connects out. This answers the open question: **the user installs
something into their cluster themselves**. We do not take a kubeconfig.

**`manual` has no provisioning at all**, which is the purest form of the security axis.
The operator already runs the machine. They install `aixle-runner` on it, register it with
a one-time token, and it connects out. The platform holds no SSH key, no kubeconfig and no
provider token for it, and it never creates or destroys the machine. The adapter's
lifecycle methods are no-ops (§5.1), and the environment row is created by registration
(§5.2). This type replaces the SSH "machine" type (a VM reached over SSH and bootstrapped
from outside) that the task's idea implied. `manual` serves the same need without a key and
without inbound access, so there is no SSH-driven type in this design.

Coder keeps outside provisioning. The Coder API is built to be called remotely, a Coder API
token is limited by Coder's own RBAC to one Coder user's workspaces, and the platform
already holds exactly that token through the Coder integration (`Integration` provider
`:coder`, `Coder::Api`). A Coder control plane reachable only inside a VPN is not served in
v1. It is handled later by running the controller mode with a Coder backend (§16).

The adapter contract (§5) is the same in all three cases. It is a platform-side Ruby
interface, and only its transport differs: the Coder API for `coder`, the controller's
channel for `kubernetes`, and nothing at all for `manual`, whose machines arrive by
registration.

### 1.3 Reuse what already works: `RunnerRuntime < ContainerRuntime::BaseRuntime`

**Decision:** during a run, the platform keeps orchestrating sessions exactly as it does
now. That means `ContainerWorkflowV2` phases, `ContainerService`, the strategies, and
`SessionContextService` writing credentials, MCP config, skills, assets and repository
clones. What changes is that the `ContainerRuntime::BaseRuntime` primitives (`exec`,
`write_file`, `read_file`, `container_status`, `container_logs`) are implemented by a new
`ContainerRuntime::RunnerRuntime`. That runtime sends them as operations over the runner
protocol, and `aixle-runner` executes them locally.

This is still execution from inside. The agent process and its tmux session are children
of `aixle-runner`, not of a remote exec. Short operations are requested by the platform but
run in the environment, and nothing is pushed inbound. It also means the dozen strategy and
context-assembly paths, which carry most of the product behaviour (credential preflight,
`@` references, tracker files, output collection), need no second implementation.

Rejected alternative: a declarative job manifest that the runner applies by itself. That
would mean rewriting `SessionContextService` and every `before_exec` hook as a manifest
builder, for a latency gain the batching in §6.4 mostly delivers anyway. It stays possible
later because the protocol is versioned.

---

## 2. Data model

Runner tables carry `company_id` and, where they have one, a nullable `project_id`
directly, like `integrations`. They have no polymorphic `scope_type`/`scope_id` pair, so
they do not use `TenantColumns`. Tenant integrity comes from the composite foreign keys of
`AddTenantColumnsToScopedResources`: `(project_id, company_id) → projects (id, company_id)`
ties a row's company to its project's, and `(integration_id, company_id) → integrations
(id, company_id)` ties a Coder runner's integration to the same company. Secrets use
`Encryptable` with `encryption_key :runners_key` (`Settings.encryption.runners_key` from
`RUNNERS_SECRET_KEY`, with rotation through `runners_key_previous` from
`RUNNERS_SECRET_KEY_PREVIOUS` and `bin/rails encryption:reencrypt`). Its first encrypted
columns are `runner_operations.encrypted_payload` and `runner_operations.encrypted_result`
(§15 task 5b). The key is **not required at boot**: `config/initializers/required_env.rb`
does not check it, so an app without it boots and serves everything else, and only
encrypting or decrypting a payload or result fails, with
Encryptable's `encryption key is not set` error. No secret is ever stored on a workflow, a
workflow version, a run or a step.

### 2.1 `runners`

| Column | Type | Notes |
| --- | --- | --- |
| `company_id` | bigint, not null | Tenant. |
| `project_id` | bigint, null | `NULL` means company runner; set means project runner. Same convention as `integrations` (`company_wide`, `visible_for_project`). |
| `name` | string, not null | Unique per scope among non-deleted rows: `(company_id, coalesce(project_id, 0), lower(name)) WHERE deleted_at IS NULL`. |
| `runner_type` | string, not null | `manual`, `coder` or `kubernetes`, enumerize. `type` is avoided as a column name so Rails does not turn this into STI. The params, errors, `RunnerResource` and the UI call the field `runner_type` too (`runnerType` once camelized). |
| `status` | string, not null | §2.5. |
| `status_reason` | string, null | Human-readable, shown in the UI and in run failures. |
| `integration_id` | bigint, null | `coder` only: the Coder integration the runner provisions through (§2.6). Check constraint: required when `runner_type = 'coder'`, null otherwise. |
| `config` | jsonb, not null, default `{}` | Non-secret, per-type schema validated by the adapter's `config_schema`. Every key, its default and the types it applies to are in **§2.7**, the authoritative table. There is no `execution_mode` key in v1: container mode is the only one, and the key arrives with the `host` mode (§6.8). |
| `max_concurrency` | integer, not null | The runner's concurrency limit. Not enforced by admission while row 9 is deferred (§10). Must be > 0. |
| `max_environments` | integer, null | `coder`: environment pool size, null means equal to `max_concurrency`. `manual`: always null. Its capacity is the number of registered machines, a physical fact and not a setting (§7.3, §10). Check constraints: null when `runner_type = 'manual'`, and > 0 when set. |
| `reuse_policy` | string, not null | `reuse` or `fresh`. What each value does depends on the type (§7.1). Until the adapters exist, `Runner` defaults it by type: `reuse` on `manual` and `coder`, `fresh` (the only allowed value) on `kubernetes` (§2.7). |
| `capabilities` | jsonb, not null, default `{}` | Computed by the adapter from type and config (§4), cached for the UI. |
| `health` | jsonb, not null, default `{}` | Last health-check facts and timestamp. |
| `last_seen_at` | datetime, null | Last controller heartbeat (`kubernetes`), last heartbeat of any registered machine (`manual`), or last successful health check (`coder`). |
| `created_by_id` | bigint, null | Required when the runner is created. Nullable with `ON DELETE SET NULL`, like every other authorship column, so permanently deleting the user who created a runner leaves the runner in place (`Users::PermanentDeletionService`). |
| `disabled_at`, `revoked_at`, `deleted_at` | datetime, null | Soft lifecycle. Rows are never hard-deleted while anything references them. |

There is no `encrypted_secrets` column: no v1 type has a secret (`manual` has none by
design, and `coder` uses the integration's token). It is added, as an `Encryptable` column,
with the first runner type that needs one.

### 2.2 `runner_environments`

| Column | Notes |
| --- | --- |
| `runner_id`, `company_id` | |
| `key` | Adapter idempotency key, unique per runner, e.g. `aixle-r12-e7f3a`. It is the Coder workspace name or the pod name. For `manual` it is generated at registration. |
| `external_id` | Coder workspace UUID or pod UID. Null for `manual`. |
| `display_name` | `manual`: the name the operator gave in `aixle-runner configure --name` (default: the hostname). Shown on the runner page. Null for the other types. |
| `origin` | `allocated` (created by `Runners::Allocator`, `coder` and `kubernetes`) or `registered` (created by `POST /runner/v1/register`, `manual`). Decides the entry path into the state machine (§5.2). |
| `state` | §5.2. |
| `reusable` | Copied from the runner's reuse policy when the environment was created. |
| `runner_version`, `protocol_version`, `os`, `arch` | Reported at check-in or registration. |
| `facts` | jsonb: prerequisites found, disk free, the Docker daemon version and agent images present. Check-in collects them, as built; the Machines list does not show them (§11). |
| `auto_update` | `manual`: copied from the runner's `config.auto_update`, overridable per machine with `aixle-runner configure --no-auto-update` (§14.4). |
| `current_session_id` | The `terminal_sessions` row it is executing. At most one (§7.3). |
| `last_heartbeat_at` | The last time the platform heard from the machine: any authenticated request (a poll, a heartbeat, an op result, `check-in`, a token refresh, `register`), written at most once every 15 s (`Runners::Liveness.record!`). Null until the machine is first heard. Task 12c (below). |
| `checked_in_at`, `sessions_count`, `consecutive_failures` | |
| `reset_requested` | `none`, `reset` or `rebuild` (§7.2). |

**Removed from the plan (Alex, 2026-11-13): affinity and project binding.** The table had a bound `project_id` (set on first assignment, never changed) and `last_workflow_id` (warm-cache affinity). They are not needed for now, so neither column is planned, and §7.3 steps 1 to 3, §9.4's bound project with Release to company and their mention in §15 task 11 are gone with them.

**What v1 has so far (§15 task 5a).** `db/migrate/20261030140000_create_runner_environments_and_credentials.rb`
creates `runner_environments` with the columns registration writes: `runner_id`,
`company_id`, `key` (unique per runner, `aixle-r<runner id>-<8 hex>` for a registered
machine), `origin`, `display_name`, `state`, `state_reason`, `os`, `arch`, `facts` (jsonb, an object),
`runner_version` and `protocol_version`. Both company and runner keys cascade, and the §2
composite key `(runner_id, company_id) → runners (id, company_id)` ties the environment's
company to its runner's. `origin` has one value so far, `registered`, and `state` has the
two this task sets, `registered` and `gone`; `RunnerEnvironment` keeps them as enumerize
values, and the §5.2 state machine replaces that with task 11. `state_reason` holds
"credential reuse detected" (§9.2). Since task 8a the machine is also `failed`
(`Runners::Credentials.rotate!` through `Runners::Machines.fail!`), held by no session, so it is
given no session, besides its revoked credentials keeping it out.
`external_id`, `reusable`, `auto_update`, `current_session_id`,
`checked_in_at`, the other counters and `reset_requested` land with their
first reader. `last_heartbeat_at` landed with task 12c: every authenticated request of a
machine records its time (`Runners::Liveness.record!`, from the gateway's `authenticate` and
from `Runners::Registration.register!`), and `runners.last_seen_at` is raised to it, so a
runner's last seen is the latest of its machines'. Both are plain writes that leave
`updated_at` alone, and a machine is written at most once every 15 s. `auto_update` landed with task 10 (boolean, default true; false for a machine
registered with `configure --no-auto-update`, which is then never offered an update, §14.4).

### 2.3 `runner_credentials` and `runner_operations`

`runner_credentials`: `runner_id`, `runner_environment_id` (null for controller-level
credentials and for unused `manual` registration tokens), `kind` (`registration`,
`controller`, `bootstrap`, `environment`),
`token_digest` (SHA-256, never the token), `family_id` (rotation lineage),
`expires_at`, `used_at`, `revoked_at`, `last_used_at`, `last_used_ip`, `created_by_id`.
Token semantics are in §9.2.

**What v1 has so far (§15 task 5a).** `runner_credentials` has `runner_id`, `company_id`,
`runner_environment_id`, `kind`, `token_digest` (unique), `family_id` (uuid),
`expires_at`, `used_at` and `revoked_at`. `kind` is `registration`, `access` or `refresh`:
an access/refresh pair is told apart by kind, and an environment pair from a controller
pair (task 19) by `runner_environment_id`. `bootstrap` joins the list with tasks 17 and 19.
A registration token has no family. Once used, it names the environment it created. The
§2 key `(runner_id, company_id) → runners` ties the company, and
`(runner_environment_id, runner_id) → runner_environments (id, runner_id)` ties a
credential's environment to its runner. `last_used_at`, `last_used_ip` (the runner page's
first-seen IP) and `created_by_id` come with the Machines table and "Add machine" (task 12).

`runner_operations`: the durable queue between Temporal activities and `aixle-runner`.

| Column | Notes |
| --- | --- |
| `runner_environment_id` or `runner_id` | Environment ops, or controller ops (provision/teardown on `kubernetes`). |
| `terminal_session_id` | Null for environment-lifecycle ops (reset). |
| `sequence` | Monotonic per environment. The runner acks by sequence. |
| `op` | §6.4. |
| `encrypted_payload` | `Encryptable`. Payloads carry credentials (the same data `write_file` carries to a hosted pod today), so they are encrypted at rest and **nulled on completion**. |
| `state` | `pending`, `delivered`, `completed`, `failed` or `expired`. |
| `encrypted_result` | `Encryptable`, like the payload. A result carries command output and file contents, which can hold the same credentials, so it is encrypted at rest. Large outputs go to Active Storage and are referenced here. |
| `deadline_at`, `delivered_at`, `completed_at` | |

Completed rows are pruned after 7 days by a sweep in the style of
`ContainerSweepOrphanedResourcesWorkflow`.

**What v1 has so far (§15 task 5b).** `db/migrate/20261030150000_create_runner_operations.rb`
creates `runner_operations` with the columns the queue, the long-poll and the results read
and write: `runner_id`, `company_id`, `runner_environment_id` (not null: every op so far is
an environment op), `sequence`, `op`, `encrypted_payload`, `state`, `encrypted_result`,
`deadline_at`, `delivered_at` and `completed_at`. As on `runner_credentials`, the §2 key
`(runner_id, company_id) → runners (id, company_id)` ties the company, and
`(runner_environment_id, runner_id) → runner_environments (id, runner_id)` ties the
environment to the same runner; all keys cascade. `(runner_environment_id, sequence)` is
unique. `RunnerOperation` keeps `op` (the environment ops of §6.4) and `state` as enumerize
values. `payload` is a JSON object, encrypted through `Encryptable` with `runners_key`, and
`Runners::Operations.record_result!` nulls it in the same update that stores the result.
`result` is a JSON object too, encrypted the same way in `encrypted_result`.
`Runners::Operations.enqueue!(environment, op:, payload:, deadline_at:)` is the only writer:
it locks the environment's row, takes the next sequence and creates a `pending` op. Its
producer is `ContainerRuntime::RunnerRuntime` through the Temporal activities (task 8a).
Controller ops (a `runner_id` with no environment) come with task 19.

**What v1 has so far (§15 task 8a).** `runner_operations.terminal_session_id`: a session op names
its session, and the envelope carries it as `session_id` (§6.4); an environment op (`env.scrub`,
`env.reset`) names none. `enqueue!` takes the session every op is for, environment ops included,
and creates the op only while that session holds the environment
(`runner_environments.current_session_id`), checked under the environment's row lock; otherwise
it creates nothing (Fix CR round 4). The key `(terminal_session_id, company_id) →
terminal_sessions (id, company_id)` ties the session to the op's company, and a deleted
session's ops are deleted with it (`ON DELETE CASCADE`). An op still
without a result is expired by the platform with its payload nulled: at its `deadline_at` by the
wait that sent it (`Runners::Operations.await`), and, 10 s past its `deadline_at`, `pending` or
`delivered`, every 5 minutes by `RunnerOperationsSweepWorkflow`
(`Runners::Operations.expire_overdue!`) for an op nobody waits for. The same sweep prunes `completed`, `failed` and `expired` ops older than 7
days (`Runners::Operations.prune!`). The sequence is a counter on the environment's row,
`runner_environments.op_sequence`, which `enqueue!` increments under the lock it already takes,
so neither the prune nor a session's deletion can hand out a sequence the runner has
acknowledged (Fix CR round 4; it replaced `MAX(sequence) + 1`, which made the prune keep each
environment's newest op and broke when a session's deletion removed it).

~~`session_live_log_chunks`~~ is **not built** (Alex, 2026-11-11, §6.5): the live log of a
runner session is read with `exec`, as a hosted one's, so the platform stores no chunk.

### 2.4 References from existing tables (all nullable, no default, no backfill)

| Table | Column | Meaning |
| --- | --- | --- |
| `workflows` | `runner_id` | The workflow's declared runner. `NULL` means hosted. It is a real foreign key, not a key in `workflows.config`, so referential checks and "workflows using this runner" are queries rather than JSON scans. It goes into the workflow version snapshot like the other workflow attributes (`docs/design/entity-versioning.md`). |
| `workflow_runs` | `runner_id` | The runner this run resolved to, **frozen at run creation** (§3.3). |
| `terminal_sessions` | `runner_id`, `runner_environment_id` | Which runner and environment the session used. Standalone sessions store the user's pick here directly. |
| `session_admissions` | (existing) `runtime_kind`, `runtime_id` | Already runtime-agnostic. `runtime_kind = "ContainerRuntime::RunnerRuntime"` and `runtime_id = runner-session-<session id>` for external sessions, written before `create_container`, as for every runtime, so a failure or a stop in that phase, where the machine is taken and the image pulled, still reaches the cleanup (task 8a). |

The `runners` table is `db/migrate/20261027100000_create_runners.rb` (§15 task 1b): the
§2.1 columns, the unique name index, the check constraints `max_concurrency > 0`,
`(runner_type = 'coder') = (integration_id IS NOT NULL)`,
`runner_type <> 'manual' OR max_environments IS NULL` and
`max_environments IS NULL OR max_environments > 0`, and the two composite keys of §2. The
company and project keys cascade, as in the tenant migration. The integration keys are
restrictive: what disconnecting a Coder integration does to its runners is decided with
the Coder adapter (task 17).

**What v1 has so far (§15 task 4).** `db/migrate/20261029100000_add_runner_references.rb`
adds the nullable `runner_id` to `workflows`, `workflow_runs` and `terminal_sessions`, each
with an index and a foreign key to `runners`. `workflows` and `terminal_sessions` carry
`company_id`, so they also get the §2 composite key `(runner_id, company_id) → runners (id,
company_id)` (on the new unique index `runners (id, company_id)`); `workflow_runs` has no
company column and relies on the model. The models share `RunnerReference`
(`app/models/concerns/runner_reference.rb`): on write, a runner must belong to the record's
project's tenant, the company's runners or the project's own, deleted or not. The check is the
project's tenant-reference rule, `TenantScope.owned(Runner, project:)`, declared as
`validates :runner_id, tenant_ids: { model: Runner, … }` like the other tenant references. The
resolver's `runner_forbidden` check and the version revert use the same rule. A version restore
or a frozen run therefore keeps naming a runner that went away, and a System workflow, which has
no project, refuses any runner. What a person may *pick* (the flag, a runner that is not deleted,
`Runner.visible_for_project`) is `Runners::Selection`, checked at the endpoints that take a pick
(§3.3).

**The rule is written once, in `Runner` (task #209).** `Runner.of_tenant(company_id:,
project_id:)` is the runners of a tenant: the company's company-level runners plus the
project's own, deleted ones included, because a stored reference to a runner deleted since
stays valid (§3.4), the launch (`Runners::Resolver`) finds it and refuses it by name, and the
version history shows its name. `Runner#of_tenant?` is the same rule for a row already loaded.
`TenantScope.owned(Runner)` calls the scope, `Runner.visible_for_project` is the scope plus
`not_deleted`, and `RunnerReference#owned_runner` calls the instance method on the preloaded
`runner`: the lists that show the "Runs on" badge preload it and can mix projects, and a stored
`runner_id` can be stale, for example after a project moved to another company. A runner leaves the database only with its project or company, and
`has_many … dependent: :nullify` clears the references first so that delete is not blocked.
**What v1 has so far (§15 task 8a).** `db/migrate/20261107100000_add_runner_session_references.rb`
adds `terminal_sessions.runner_environment_id`, the machine the session ran on, kept after the
session. Its key `(runner_environment_id, runner_id) → runner_environments (id, runner_id)` ties
the machine to the session's own runner, whose company `fk_terminal_sessions_runner_company`
already ties to the session's. It also adds `runner_environments.current_session_id` (§2.2),
unique, the session that holds the machine now: `Runners::Machines` sets it under the machine's
row lock and clears it after the session's `env.reset` succeeded, so a machine without one is
free. Both are written by `ContainerRuntime::RunnerRuntime`'s first phase that needs a machine,
until `Runners::Allocator` (task 11). Following the "Database keys" rule of
`docs/project/context.md`, `20261108100000_add_runner_op_sequence_and_session_company_keys.rb`
adds a unique index on `terminal_sessions (id, company_id)` and the keys
`runner_operations (terminal_session_id, company_id)` and `runner_environments
(current_session_id, company_id)` → `terminal_sessions (id, company_id)`. The single-column keys
stay for their delete actions; the machine's company key is deferred to the commit, because its
`SET NULL` comes from the single-column key. No key ties a session to the machine it holds:
`Runners::Operations.enqueue!` enforces that relation.

The migrations only add nullable columns and new tables. Every existing row reads as
`hosted`, and no hosted code reads the new columns (§12.3).

### 2.5 Runner status

```
pending ──health ok──▶ connected ◀──recovers── degraded / unreachable
   │  │                   │  ▲
   │  └─first check fails─┼──┼──────────────▶ degraded / unreachable
   │                      ▼  │ enable (to pending)
   │                   disabled
   └──────────────▶ revoked (terminal)       deleted_at set ⇒ hidden; revoked
```

The transitions, as `RunnerStateMachine` (`app/state_machines/runner_state_machine.rb`)
implements them:

- Health results: `connected` from `pending`, `degraded` or `unreachable`; `degraded` and
  `unreachable` from `pending`, from `connected`, or from each other. A failed **first**
  check moves `pending` straight to `degraded` or `unreachable`. A health result stores its
  reason in `status_reason`; reaching `connected` clears it.
- `disable` works from any of the four health states and sets `disabled_at`. `enable`
  returns to **`pending`**, not to `connected`, and clears `disabled_at`: nothing checked
  the runner while it was disabled, so the next health check decides.
- `revoke` works from any state except `revoked` and sets `revoked_at`. `revoked` is
  terminal.
- Deleting a runner is a soft delete that revokes it in the same write: `deleted_at` and
  `revoked` are set together, so a deleted runner is revoked in the data, not only in reads.

- `pending`: created, never verified. Coder: the integration token and template have not
  been checked yet. Kubernetes: the controller has not connected yet. Manual: no machine
  has registered yet.
- `connected`: health check passed within the last 5 minutes. For Kubernetes this also
  requires a controller heartbeat within the last 60 s. For Manual, every registered
  machine was heard within the last 90 s and none has failed.
- `degraded`: reachable, but something is wrong: a template parameter is invalid, the
  controller reports missing RBAC, the controller version is below the recommended one, or
  some (not all) of a manual runner's machines are offline or `failed`. New sessions are
  still admitted, and the reason, which names those machines, is shown.
- `unreachable`: the health check failed, the controller has been silent for more than
  3 minutes, or no registered machine of a manual runner has been heard for more than
  3 minutes, or no machine of a manual runner can take a session: every one is `failed`
  (the failures are the reason), or every one is `gone` ("No machine registered."). A
  manual runner whose first machine has never registered stays `pending`. New sessions
  fail at launch (§8). Running sessions follow §6.7.

For `manual`, the UI also shows each machine as **online** (connected and running a
session, environment `busy`), **idle** (connected, no session, environment `idle`) or
**offline** (no heartbeat for 90 s, the `unreachable` overlay of §5.2), in the spirit of
GitHub's self-hosted runner list.

**Built in task 12c.** The machine's display state (`RunnerEnvironment#display_state`) is:

- **online**: heard within 90 s (`RunnerEnvironment::ONLINE_WINDOW`) and holding a session;
- **idle**: heard within 90 s, no session;
- **offline**: not heard for 90 s, or never heard;
- `failed` and `gone` machines show as such, whatever their last heartbeat.

**The op-deadline exception is removed (Alex, 2026-11-13).** Task 12c counted a machine
executing a delivered op as heard until the op's deadline, because the host runner is
silent while it runs one (§6.7). With `POST /runner/v1/heartbeat` (task 12d) it is not: the
host runner sends a heartbeat at least every 25 s while an op runs, so a machine is
reachable when it was heard within 90 s, and nothing else. `RunnerEnvironment.executing_op`,
`#executing_op?`, `.reachable` and the `delivered_operations` association are gone. A machine
on an older `aixle-runner` shows offline during a long op until it updates itself.

**Placement.** A machine that was not heard within 90 s (`RunnerEnvironment.heard`) is given
no new session: `Runners::Machines.take!` skips it, and a launch against a runner whose every
registered machine is offline is refused as `runner_unreachable` with
"Runner \"X\" has no machine online: every machine is offline (…). Start aixle-runner on one
of them, or pick another runner" (`Runners::Resolver`, and `NoMachine` where the machine is
taken), as it is when every machine has failed. A runner whose heard machines are all
busy is not refused: its session waits for a free one (§10). **The launch refusal stays on the
machines' availability** (`Runners::Resolver#resolve!` and `Runners::Machines.take!`, through
`Runners::Machines.availability`): the runner's health status below is for display and
refuses nothing.

**Built in task 12d: the runner's status from its machines' health.**
`Runners::ManualAdapter#check_health(runner)` returns a status and a reason from the runner's
machines alone, with no outbound call:

- `pending`: no machine has ever registered. The runner keeps its status;
- `connected`: every registered machine was heard within 90 s, and none has `failed`;
- `degraded`: some registered machines are offline or `failed`. The reason names them
  ("Offline: build-02. Failed: build-03 (refresh token reused)."). This includes every
  registered machine silent for more than 90 s but not for 3 minutes;
- `unreachable`: no registered machine was heard for more than 3 minutes, or no machine can
  take a session: every machine is `failed` (the failures are the reason), or every one is
  `gone` ("No machine registered.").

One periodic check sets the status (`runner_health_check_workflow` in
`app/temporal/schedules.yml`, every minute, `Runners::HealthCheck`): it calls the adapter for
every live runner (`Runner.live`: not disabled, revoked or deleted) and applies the result
through `RunnerStateMachine` (`mark_connected`, `mark_degraded`, `mark_unreachable`), storing
`status_reason`. **Nothing else sets it**: not the gateway when a heartbeat arrives, and not
a machine's registration. So the status may lag a machine by up to a minute: a runner whose
first machine registers is `pending` until the next check, then `connected`. The status is
applied under the runner's row lock, on the row as it is then, so a runner disabled or revoked
meanwhile is left alone, and a status and reason that did not change write nothing. A runner
page and the runners list already show the status and its reason.
- `disabled`: switched off by a user. No new sessions. Running sessions are left to finish.
- `revoked`: every credential is invalidated immediately and running sessions fail (§9.3).
  This is terminal: to get it back, create a new runner.

### 2.6 Coder: through the Coder integration, templates on the runner

**Decision:** a `coder` runner references an existing Coder `Integration` for the
connection (URL and token, already encrypted in `integrations.credentials`). The template
and its parameters live in `runners.config`. Several runners can point at one integration,
so several templates can be used side by side in one project, e.g. "EC2 small" and
"EC2 GPU", each with its own concurrency limit.

Why not configure the connection on the runner itself: the integration already handles the
token lifecycle (`Coder::TokenService`), scoping (`visible_for_project`), revocation and the
existing Coder MCP tools. A second copy of the same token would rotate and expire
independently. Scoping rule: a project runner can use a company-wide Coder integration or
one of its own project's. A company runner can only use a company-wide one. When the
integration becomes `inactive` or `error`, every runner on it goes `unreachable`, with a
reason that names the integration. The template keys are in §2.7.

**Decided (§6.9, Alex, 2026-11-06): v1 supports only Coder workspaces that are virtual
machines.** A workspace that is a container on a shared server, or a pod, is not supported.
The host runner's start check refuses it with a clear message (§6.9.7). A workspace runs one
session at a time, in container mode by default (§6.8, §15 row 17) or in the `host` execution
mode, which is for Coder only (§6.8, §15 row 20).

### 2.7 Runner configuration: the authoritative schema

This is the single list of what a runner can be configured with. Other sections explain
*why* a key exists and link here; when they disagree, this table wins. It is what
`Runners::Adapter.config_schema` (§5.1, §15 task 2) encodes per type.

In the code the table is `Runners::ConfigSchema` (`app/services/runners/config_schema.rb`):
every key below, with its JSON Schema, default, types and whether it arrives later.
`Runners::ConfigSchema.for_type(type)` is the JSON Schema of one type, the one the form
renders from, and `Runner` validates `config` against it for all three types (§15 task 2).
A key that a type requires (`template_id`, `namespace`) is required by that type's schema.
An `ephemeral` key is refused like any other unknown key: there is no ephemeral registration (§6.3).
`Runners::ConfigSchema.value(config, key)` reads a key with its default applied.

**Validation rules, for every type:**

- An unknown key is refused, not ignored.
- A key that does not apply to the runner's type is refused with the types it applies to
  (a `namespace` on a `coder` runner is an error, not a silent no-op).
- A key from the "arrives later" table is refused in v1 with "not supported yet". Keys are
  declared when what they control is built, never ahead of it.
- Defaults are applied by the schema at read time and are not written into `config`, so
  a later change of a default reaches existing runners unless they set the key.

**Settings that are columns, not `config` keys** (§2.1), because they are queried or
constrained in SQL:

| Setting | Type | Default | Applies to | Defined in |
| --- | --- | --- | --- | --- |
| `integration_id` | Coder `Integration` id | required | `coder` | §2.6 |
| `max_concurrency` | integer > 0 | required | all | §10 |
| `max_environments` | integer > 0, or null | null (= `max_concurrency`) | `coder`; always null on `manual` (check constraint); unused on `kubernetes` | §7.3 |
| `reuse_policy` | `reuse` \| `fresh` | `reuse` on `manual` and `coder`; `fresh` (the only value) on `kubernetes` | all, with per-type meaning | §7.1 |

**`config` keys in v1:**

| Key | Type | Default | Applies to | Defined in |
| --- | --- | --- | --- | --- |
| `template_id` | string, Coder template UUID | required | `coder` | §2.6 |
| `template_version_policy` | `active` \| `pinned` | `active` (the template's active version at provision time) | `coder` | §2.6 |
| `template_version_id` | string, Coder template version UUID | null; required when `template_version_policy: pinned` | `coder` | §2.6 |
| `parameters` | object, string → string | `{}` | `coder`; validated against the template's parameters | §2.6, §5.1 |
| `on_release` | `delete` \| `stop` | `delete` | `coder`; what `teardown` does to the workspace | §5.1 |
| `namespace` | string | required | `kubernetes`; must equal the namespace the controller reports at registration | §5.1, §9.6 |
| `auto_update` | boolean | `true` | `manual`; overridable per machine with `aixle-runner configure --no-auto-update` (`runner_environments.auto_update`) | §14.4 |
| `container.image_override` | string, image reference; `{agent}` is replaced at launch with the image name of the session's runtime (`config/agent_runtimes.json`), so `ghcr.io/aixlehq/flow-{agent}:develop` serves every agent; any other placeholder is refused, and so is a value that is no image reference once replaced | null (the runner default image of the session's runtime, §6.8) | all; must be built `FROM` our base image, checked at check-in | §6.8 |
| `container.resources` | `{cpus, memory}` | from the hosted pod spec | all; `--cpus`/`--memory` on `manual` and `coder`, pod requests and limits on `kubernetes` | §6.8 |
| `container.workspace_volume` | boolean | `true` | `manual`, `coder` | §6.8, §7.1 |
| `container.cache_mounts` | array of `{name}` (named volume `aixle-cache-<key>-<name>`) or `{host_path}`, each with `target` | `[]` | `manual`, `coder` | §6.8, §7.2 |
| `container.home_mount` | `{path, writable}`, or null | null (off). `path` required on `manual`, the workspace user's `$HOME` on `coder`; `writable: false` | `manual`, `coder` | §6.8 |
| `container.extra_mounts` | array of `{source, target, writable}`; the form accepts `src:dst[:rw]` | `[]`; `writable: false` | `manual`, `coder`; absolute paths only | §6.8 |
| `container.acknowledged_writable_mounts` | array of target paths | `[]` | `manual`; every writable host mount (`home_mount`, `extra_mounts`, host-path `cache_mounts`) must be listed, or the config is refused. `home_mount` has no target of its own and is listed by its `path` | §7.2 |
| `container.network` | `bridge` \| `host` | `bridge` | `manual`, `coder` | §6.8 |
| `container.pid` | `private` \| `host` | `private` | `manual`, `coder` | §6.8 |
| `container.allow_privileged_mounts` | boolean | `false` | `manual`, `coder`; the gate for `docker_socket` | §6.8 |
| `container.docker_socket` | boolean | `false` | `manual`, `coder`; refused unless `allow_privileged_mounts` | §6.8 |

**Keys that arrive later, refused in v1:**

| Key | Type | Default when it arrives | Applies to | Arrives with |
| --- | --- | --- | --- | --- |
| `execution_mode` | `container` \| `host` | `container` | `manual`, `coder` (a pod has no host to run a CLI on) | Phase 7, the `host` mode (§6.8, §15 task 20) |
| `host.cli_source` | `managed` \| `template` | `managed` | `manual`, `coder`, only with `execution_mode: host` | Phase 7 (§6.8) |

**Not runner configuration, listed so nobody looks for them in `config`:**

- **Helm values of the controller chart** (`rbac.events`, default on; `networkPolicy.enabled`,
  default off; §9.6). The customer sets them at `helm install`; the platform never stores
  them and sees their effect only through the controller's RBAC report.
- **Platform settings** under `Settings.runners` (`bootstrap_timeout`,
  `max_consecutive_failures`, `release`). They are the same for every
  runner and are not editable per runner.

---

## 3. Scope resolution and precedence

### 3.1 Visibility

A project can see its own runners plus its company's non-deleted runners:
`Runner.visible_for_project(project)`, the same shape as `Integration.visible_for_project`, and
`Runner.of_tenant` plus `not_deleted` (§2.4).
A runner is never visible across companies. System workflows (`scope_type: "System"`, e.g.
Aixle Builder) have no project, so they can only use `hosted`.

### 3.2 Who may do what

| Action | Company runner | Project runner |
| --- | --- | --- |
| List and view status | Any active company member | Anyone with `project_accessible?` |
| Create, edit, disable, delete, revoke | Company `admin?` | Company `admin?` **or the project owner** |
| Rebuild an environment | Company `admin?` | Company `admin?` or the project owner |
| Select on a workflow, run or session | `project_writable?` in a project that can see it | `project_writable?` |

This is stricter than project integrations, where any non-viewer can connect them, and the
difference is deliberate. A session sends **the launching user's agent credential** (their
Claude, Codex or Kiro login) to wherever it runs. If any collaborator could connect a
runner, user A could point a workflow at a machine A controls, user B could launch it, and
A would receive B's login. So only people who already have authority over the project's
trust boundary can connect a runner. Members only choose among runners that someone with
that authority vetted. The run drawer and the new-session form also tell the launching user
where their credential is going (§11).

Policies: `Web::Company::RunnersPolicy` (company, `admin?`) and
`Web::Company::Projects::RunnersPolicy` (`admin? || project.owner_id == user.id` for
writes, `project_accessible?` for reads). As every policy does through `dynamic_authorize!`,
they authorize the action only (task #209). Which runner a request may touch is decided by
the controller's lookup, as in the integrations controllers: on the project page, update,
destroy, `disable`, `enable` and `revoke` find the runner among the project's own runners,
and in company settings among the company-level ones; index and show find it among the
runners the page lists. A company runner is then not found (`404`) by a write from a project
page. The show page's `can_manage` is the policy's answer for the action and whether the
runner is one of the page's own. The actions live in the two controllers
(`Web::Company::RunnersController`, `Web::Company::Projects::RunnersController`), and what
they share, the form's attributes and its runner types, is `Runners::Form`.

### 3.3 Precedence

For a workflow run, resolved once in `WorkflowRun` creation:

1. `workflow_runs.runner_id` given explicitly at launch (run drawer, API, `trigger_*` tool
   argument)
2. `workflows.runner_id`
3. `hosted`

For a standalone session: the runner picked on the new-session form or the API, otherwise
`hosted`.

**The session/run choice beats the workflow's**, because it is the more specific act and it
is made by a person at launch. The drawer pre-selects the workflow's runner, so the default
is the workflow's. Automated launches (board-column bindings, tracker and chat triggers)
carry no override, so they use the workflow's runner.

**There is no step-level runner.** Every step of a run runs on the run's runner. A step that
needs a different network than its siblings is a different workflow. Step-level choice is
left for later (§16) because it multiplies the cross-project and credential reasoning in
§9 by the number of steps.

**There is no project- or company-level default runner in this iteration.** User story 5
requires that anything without an explicit choice keeps running where it runs today, and a
project default would silently move every existing workflow in that project. It can come
later as an explicit "default runner" setting, and that setting would still have to be
chosen deliberately.

**The run's runner is frozen** at run creation into `workflow_runs.runner_id`. Retries and
later steps use it. Changing the workflow's runner mid-run does not move a running run,
which matches how `agent_runtime` is frozen per run.

**What v1 has so far (§15 task 4).** `WorkflowService.enqueue(runner_id:)` freezes the runner
on the run: a pick given at launch (an id, or `nil` for hosted), otherwise the runner of the
run it retries, otherwise `workflows.runner_id`. A pick is refused, with no run created, unless
`Runners::Selection` allows it: the flag is on for the company (a `nil` pick included, since it
would move a run off its workflow's runner) and the runner is visible to the project and not
deleted. The picks come from the run drawer (`workflow_runs#create`, sent only when it differs
from the workflow's runner), `POST …/board/tasks/:id/trigger_workflow`, and the `trigger_workflow`
and `trigger_task_workflow` tools; a manual task trigger records the pick on its
`TriggerEvent`. Column bindings, tracker and chat triggers pass none
(`TriggerEngine.fire_workflow`). A standalone session takes `runner_id` from
`POST /api/v1/terminal_sessions`, refused the same way and, for an interactive session,
refused for every external runner until the tunnel (§4, §15 task 16); a workflow-step
session copies its run's runner.

### 3.4 When the referenced runner is gone, disabled or revoked

A reference is never cleared automatically and never falls back to `hosted`. The one
exception is a project move, which clears it on the rows that move (below).

- **Workflow builder:** the runner field shows "Runner *X* is disabled / revoked / deleted",
  with a link to pick another. Publishing a workflow whose runner is not
  `connected`/`degraded` is allowed, because the runner may come back, but it shows a
  warning.
- **Launch** (`SessionService.create_for_workflow_step`, the standalone create, and run
  creation): `Runners::Resolver.resolve!(session)` re-checks visibility (§9.4) and status.
  If the runner is `disabled`, `revoked`, deleted, `unreachable`, or no longer visible
  to the project, the run or session fails before admission with
  `failure_reason: "runner_unavailable"` and a message like *"Runner "Prod VPC" is
  disabled. Pick another runner on the workflow or re-enable it."* The board task gets the
  same message through the existing failure-comment path.
- **Deletion** is a soft delete, so workflows and past sessions can still name what they
  used. Deleting a runner asks for an ordinary confirmation; the runner pages do not list
  the workflows that name it. Hard deletion (by a later purge) only happens once no `workflows` or
  `workflow_runs` rows reference it.

**What v1 has so far (§15 task 4).** `Runners::Resolver.resolve!` (`app/services/runners/resolver.rb`)
runs at three points, each before admission:

- **Run creation:** `WorkflowService.dispatch!`, the one path every launcher and the relay take
  to Temporal. A refused run goes `pending → failed` (`fail_before_start`), with no execution
  and no session. Its `failure_reason` is the refusal's reason, every step carries the message,
  and the board task gets a system comment, "Run #N of workflow "X" failed: <message>", next
  to the `workflow_failed` activity. The tracker and chat reporters read the step's message.
- **A workflow step:** `SessionService.create_for_workflow_step`, before the session is built.
  `LaunchStepSessionActivity` fails the step with the message, sets the run's reason, comments
  on the task, and raises non-retryable (`RunnerRefused`).
- **A standalone session:** `SessionService.create_and_start`, after the save. The session is
  failed with the message as its `error_message` and never admitted.

A record without a runner returns `nil` before anything is read, the flag included (§12.3).
Otherwise it checks the flag for the project's company (`runner_unavailable`, "External runners
are not enabled for this company."), that the runner is in the project's scope
(`runner_forbidden`; the runner is found through `TenantScope.owned(Runner, project:)`, never
through `record.runner`, so the message names only the id), and its status
(`runner_unavailable`: deleted, revoked, disabled, with §8's wording). A runner that passes all three is refused with `runner_execution_not_enabled`,
"Runner "X" can't take sessions yet: runner execution not enabled." (§12.2, phase 1).
`runner_unreachable` and the capacity waits come with tasks 9 and 12.

The workflow version snapshot holds `runner_id` (`Versions::Snapshots::Workflow`), left out while
it is null so a hosted workflow's snapshot is the one it had before runners. A revert restores
a runner the project still owns (`TenantScope.owned(Runner, project:)`) as it was, a deleted,
disabled or revoked one included, and the builder warns. A snapshot runner whose row is gone,
or one the project can no longer use, restores Hosted rather than refuse, so that version can
still be reverted to. The version diff names a snapshot's runner through the same tenant rule
(`Versions::ReferenceNames`), so another tenant's runner shows only as its id.

A project move (`ProjectMove`) cannot take a runner reference into another company: a runner
stays with its company, and `fk_workflows_runner_company`, `fk_terminal_sessions_runner_company`
and `fk_runners_project_company` hold the rows to it. So `ProjectMove::Preflight` blocks the move
while the project owns a runner, a deleted one included ("Runner *X* belongs to this project, and
a runner cannot move to another company."). The project's workflows that name a runner, archived
ones included, do not block it: the move switches them to Hosted, and the preflight and the
move report list them (`workflows_switched_to_hosted`) so the admin can pick a runner of the
target company afterwards. The project's runs and sessions are history by then (a live session
blocks the move, and work that has not started is cancelled), so the move clears their
`runner_id` too and the report counts them (`cleared_runner_references`). The move also drops
`runner_id` from the snapshots of the moved workflows' versions (Hosted is the absent key, as in
`Snapshot.dump`), so no version of a moved project names a runner of its old company. This is a
deliberate exception to "history is never rewritten" (`docs/design/entity-versioning.md`, D3).
Otherwise the move writes no workflow version, as with the other references it rewrites.

**Known limitations of the move, accepted (decided 2026-10-30).** A project move is a rare
super-admin operation, so these cases stay as they are and are not fixed:

- **A queued manual launch.** A manual task trigger that is still queued in the trigger
  outbox when the project moves, and that names a runner (the pick recorded on its
  `TriggerEvent`), is dropped by the relay: after the move the runner is not in the
  project's tenant any more, so the pick is refused. The `TriggerDispatch` is left
  `skipped` with the refusal as its reason, and no run or comment is created.
- **Lock order.** The move and a concurrent workflow save take their locks in opposite
  order, so they can deadlock. The admin then gets an error and retries the move. This
  existed before task 4.
- **A project that owns a runner**, a deleted one included, cannot be moved (the preflight
  blocker above). A way out is to be decided later.

---

## 4. Capability flags

The platform reasons about a runner through `Runners::Capabilities`, never through its
type. Each adapter returns them from `type + config`.

**What v1 has so far** (§15 task 2): `Runners::Capabilities` declares `provisionable` and
`rebuildable` only, both `false` on `manual`. The runners controllers store them in
`runners.capabilities` on every create and update. Each other flag of the table is added
with the first code that reads it. Flags that depend on how the agent
runs come from **the execution mode** (§6.8), not from the type. In v1 every type runs
container mode, so they are the same across the three external types; the `host` mode
(phase 7) will derive its own.

| Flag | `hosted` (today) | `manual` | `coder` | `kubernetes` | Used by |
| --- | --- | --- | --- | --- | --- |
| `provisionable` | true | **false**: the platform cannot create a machine | true | true | Allocator step 4 (§7.3), waiting-session copy (§10) |
| `rebuildable` | n/a | **false**: we do not own the machine | true | n/a (ephemeral) | Reset escalation (§7.2) |
| `reusable` | false | true | true | false (v1) | Lifecycle (§7), scrub |
| `persistent_disk` | false | true | true (mounted volumes only) | false (a PVC option is later) | Reset semantics, UI copy |
| `human_accessible` | false | true (it is the operator's machine; there is no link to open) | true (Coder's own SSH, web terminal, IDE) | false | "Open in Coder" link on the session, when there is a link |
| `interactive_terminal` | true | false until the tunnel (§12.2, phase 4), then true | same | same | Not declared or read in v1. Its first reader comes with the tunnel (§15 task 16); until then interactive standalone sessions refuse every external runner unconditionally (below) |
| `max_concurrency` | not enforced by admission while row 9 is deferred | `runners.max_concurrency` | `runners.max_concurrency` | `runners.max_concurrency` | Admission (§10) |
| `max_environments` | n/a | number of registered machines (a fact) | `runners.max_environments` (a setting) | `runners.max_concurrency` | Allocation (§7.3) |
| `concurrency_per_environment` | 1 | 1 | 1 | 1 | Allocation (§7.3) |
| `agent_runtimes` | all | all | all | all | Not read in v1. Validation at selection and launch once a type narrows it (below) |
| `provisioning_seconds_p50` | n/a | n/a | from history | from history | UI hint, bootstrap timeout |

The agent runs in the same image hosted uses on every type, so `agent_runtimes: all`
follows from container mode, and it would hold for any future type that runs the stock
image. `interactive_terminal` is the same flag on every type because the tunnel (phase 4)
relays ports the image already serves, so it lifts on all types at once.

Validation that uses these flags:

- **Built (§15 task 4), and not a capability check:** an interactive standalone session
  cannot pick any external runner before the tunnel. `Runners::Selection.error` refuses
  every runner when `interactive: true`, so `POST /api/v1/terminal_sessions` refuses the
  pick (§3.3), and the runner select disables every runner with the reason. No
  `interactive_terminal` capability is declared or read today. It gets its first reader
  with the tunnel (§15 task 16), which replaces this unconditional refusal.
- **Not built, by decision (2026-10-30):** refusing a run launched with an override to a
  runner without `interactive_terminal`, and refusing to publish a workflow that has an
  interactive step on such a runner. No real user has `external_runners` before the
  tunnel (§12.2, phase 4), and the tunnel gives every type `interactive_terminal`, so
  these checks would guard a state no customer reaches. No interim stub is built for them.
- `agent_runtimes` is `all` on every type in v1 (container mode, above), so no check reads
  it yet. A type or execution mode that narrows it adds the refusal at selection and
  launch with it.

---

## 5. Adapter contract

### 5.1 Interface

```ruby
module Runners
  # One subclass per runner type. Stateless; every method is idempotent on
  # environment.key, because Temporal retries activities.
  class Adapter
    # Registration
    def self.type                                    # => :coder
    def self.config_schema                           # => the type's JSON schema (Runners::ConfigSchema), for the form
    def capabilities(runner)                         # => Runners::Capabilities

    # Runner-level
    def check_health(runner)                         # => Runners::Health(status:, reason:, facts:); may call the provider

    # Environment lifecycle — the whole contract; nothing here runs during a session
    def provision(environment)                       # create; => {external_id:}; raises CapacityError / ProvisionError
    def prepare(environment)                         # ensure started/booted; => :ready | :pending; raises ProvisionError
    def inject_bootstrap(environment, bootstrap)     # deliver aixle-runner + Bootstrap(token:, gateway_url:, version:, sha256:)
    def reset(environment, level:)                   # level: :reset | :rebuild; idempotent. :rebuild only when capabilities.rebuildable
    def teardown(environment)                        # delete; => :gone | :pending
    def observe(environment)                         # => :running | :stopped | :missing | :unknown (provider fact, for reconciliation)
  end
end
```

**What v1 has so far** (§15 task 2, reworked by task #209): `Runners::Adapter` with `type`,
`config_schema` and `capabilities`, and a registry that holds `Runners::ManualAdapter`
only. A type without an adapter cannot be created: `Runners::Adapter.for` raises
`Runners::Adapter::UnavailableType`, and the controllers refuse a `coder` or `kubernetes`
runner as "not available yet" until task 17 and phase 6. `check_health` is not there yet:
on `manual` health comes from machine heartbeats, so it lands with task 12. The
environment lifecycle methods land with the tasks that call them.

**Config checks do no IO (task #209).** The adapter is the behaviour layer, which for
`coder` and `kubernetes` calls their APIs, so the model never calls it. A runner's `config`
is checked by `Runner`'s own validation, which calls only `Runners::ConfigSchema`: the
type's JSON Schema, then the type's rules one key's schema cannot express, as pure
functions of the config hash (`ConfigSchema::TYPE_RULES`). On `manual` those are
`home_mount.path`, the acknowledgement of every writable host mount, and `docker_socket`
behind `allow_privileged_mounts`. The rule for every check of this kind:

- A model validation has no side effects, no IO and no dependency on services or higher
  layers. It may read the model's own associations, query for uniqueness, and call pure data
  and rule code.
- A check that needs an external call, such as whether a Coder template exists, belongs in a
  service or the health check (`check_health`), never in a model validation.
- The config checks run only when `config` or `runner_type` changes, so a stored config
  that a later, tighter schema refuses does not block the runner's revoke or delete, which
  save with `whiny_persistence`.

`Runners::Save` stays thin: it stores the capabilities the adapter derives, turns an
unavailable type and the unique-name race into errors, and saves with a plain `save`, which
runs the model's validations.

`Runners::Adapter.for(runner)` is a registry keyed by type
(`Runners::ManualAdapter`, `Runners::CoderAdapter`, `Runners::KubernetesAdapter`). Adding a
type means adding a class, a config schema, and a row in §4. Nothing in sessions,
strategies or Temporal changes. A type that cannot do something says so through a
capability (`provisionable`, `rebuildable`), and the callers branch on the capability, never
on the type. `reset(level: :rebuild)` on a non-rebuildable type raises
`Runners::UnsupportedOperation`; the allocator never asks, because it reads `rebuildable`
first.

**Who owns what: the allocator owns the row, the adapter owns the provider object.**
`Runners::Allocator` (§7.3) decides that a new environment is needed. It creates the
`runner_environments` row in `requested`, with its `key`, `runner_id`, `company_id` and
bound `project_id`, inside the same locked transaction that counts the pool against
`max_environments`. **`provision` never creates the row.** It receives the persisted
environment and creates the provider-side object under it: the Coder workspace named
after `environment.key`, or the controller's pod. It returns `external_id`, and the
allocator writes that back to the row and moves it to `provisioning`. Every other adapter
method also takes an existing row and does not write to `runner_environments`. State
transitions belong to the allocator and the reconciler. This split is what keeps
`provision` idempotent on `key` under Temporal retries. A retried `provision` finds the
workspace named `key` and returns it, and there is never a second row to reconcile.

**The exception is `manual`: registration owns the row.** There is no provider object to
create, so the allocator never inserts a `manual` environment. `Runners::Registration`,
behind `POST /runner/v1/register`, creates the row (`origin: registered`) in the same
transaction that consumes the registration token, and the row enters the state machine
directly at check-in (§5.2).

The per-type mapping:

| Method | `manual` (nothing to call) | `coder` (outside, Coder API via `Coder::Api`) | `kubernetes` (via controller ops) |
| --- | --- | --- | --- |
| Config checks (`Runners::ConfigSchema`, no IO) | `config.container` options only (§2.7, §6.8) | Parameters valid, `config.container` options; the integration usable is `Runner`'s own validation | Namespace, `config.container.resources` and `image_override` valid |
| `check_health` | Derived from the machines' last heartbeats and states (§2.5, built in task 12d). No outbound call | Coder API reachable, template exists and is valid | Controller heartbeat and its RBAC report |
| `provision` | **No-op.** Never called: `provisionable: false` | `WorkspaceService` create from `config.template_id` with `config.parameters`, name = `key` | `controller.provision {key, image, resources, labels}`. The controller creates Pod, ServiceAccount and Secret (bootstrap) in its namespace |
| `prepare` | **No-op**, returns `:ready`: the machine is the operator's and is already running | Await build. Start the workspace if it is stopped | Await pod `Ready` (controller reports) |
| `inject_bootstrap` | **No-op**: the operator installed the runner (§14.4) | `Coder::SshRunner`-style `coder ssh <ws> -- sh -s` with the install script **on stdin**, so the token never appears in argv or `ps`. It installs and starts `aixle-runner --mode host` (§6.8) | No-op: the controller mounts the bootstrap Secret and the pod's init container installs the runner (§9.6) |
| `reset :reset` | Runner op `env.reset`: **scrub ops only**, the full wipe of §7.2 | Runner op `env.reset` (§7.2) | n/a |
| `reset :rebuild` | **Does not exist** (`rebuildable: false`) | Delete and recreate the workspace from the template | n/a |
| `teardown` | **No-op** on the machine. Removing a machine is `aixle-runner unregister` or Revoke (§9.3); the platform side only marks the row `gone` | Delete the workspace (or stop it, per `config.on_release`) | `controller.teardown {key}` |
| `observe` | **Heartbeat-based** (task 11): `:running` while heartbeats arrive, `:unknown` after 90 s, never `:missing` (we cannot tell a powered-off machine from a removed one) | Workspace build status | Controller's pod list |

**Decided (§6.9.2):** `inject_bootstrap` on `kubernetes` mounts no bootstrap Secret and runs
no init container. The bootstrap token travels in the `provision` op to the controller, which
does the pod's check-in itself (§9.2).

### 5.2 Environment state machine

```
                 provision           prepare           check-in (bootstrap token exchanged)
  requested ──────────────▶ provisioning ──────▶ booting ─────────────────────────────▶ idle
      │                         │                   │                                    │  ▲
      │ CapacityError           │ ProvisionError    │ no check-in within                 │  │ release (reusable)
      ▼                         ▼                   │ runners.bootstrap_timeout          │  │ + scrub ok
  (admission capacity wait)   failed ◀──────────────┘                                    ▼  │
                                ▲                                       assign ──▶   busy ──┘
                                │                                                    │
                    scrub/reset │ fails                                              │ reset_requested=rebuild
                                │                                                    │
                            resetting ◀── release with reset_requested=reset ───────┤
                                │ ok ──▶ idle                                        ▼
                                                                                tearing_down ──▶ gone
                                                    unreachable (heartbeat lost) ⇄ idle/busy (§6.7)
```

**The self-registering entry path (`manual`).** A registered environment has no
`requested`, `provisioning` or `booting` state, because nothing is provisioned:

```
   register (registration token consumed, row created, origin: registered)
  ─────────────────────────────────────────▶ registered ──check-in: prerequisites ok──▶ idle
                                                 │
                                                 └──check-in: prerequisites missing──▶ failed
   idle ── unregister / Revoke ──▶ gone          (no tearing_down: there is nothing to delete)
   failed ── operator "Return to service" ──▶ resetting ──ok──▶ idle
```

`registered` lasts as long as it takes the host runner to report its facts, normally
seconds. A `manual` environment never goes through `tearing_down`: `gone` is set by
`unregister` or revocation, and the machine itself is left as it is. Release on a
`manual` environment always takes the `resetting`/scrub arm, never the teardown arm,
whatever `reuse_policy` says (§7.1).

- One session at a time per environment (`concurrency_per_environment = 1`). `busy` holds
  `current_session_id`.
- `failed` environments are torn down by the reconciler and never reused, except on
  `manual`: a failed machine cannot be torn down by us, so it stays `failed`, out of
  rotation, until the operator fixes it and presses **Return to service**, which runs a
  reset (§7.2), or unregisters it.
- **What 8a built.** Of this machine, 8a has `registered`, `failed` and `gone`, with no
  transitions recorded yet. A machine whose `env.reset` failed after a session, an unanswered
  one included, goes `registered → failed`, its `current_session_id` cleared and the reason in
  `state_reason`, as text for people only (`Runners::Machines.fail!`). A free machine is
  `registered` with no session, so a `failed` one is excluded by its state, and nothing that
  happens to the session, its deletion included, returns it to rotation. The gateway keeps
  accepting its credentials (only `gone` is refused), so that Return to service (task 11) can
  reach it. Until then the machine is brought back by running `aixle-runner unregister` on it,
  then `configure` again, which registers a new environment.
- `unreachable` is an overlay on `idle` or `busy`, not a separate lifecycle. It is entered
  when heartbeats are missed and left on reconnect (§6.7).
- The state machine is a `state_machines/` class like the others, and transitions are
  recorded.

### 5.3 How it plugs into today's phases

External sessions go through the same `ContainerWorkflowV2` and `AdmittedPhaseActivity`.
The only branch is the runtime the strategy gets. `BaseStrategy#runtime` and the other
`ContainerRuntime.build` call sites (`AdmittedPhaseActivity`, `Sessions::LiveLogReader`,
the scanners) go through one helper:

```ruby
ContainerRuntime.for_session(session)
# => session&.runner_id ? ContainerRuntime::RunnerRuntime.new : ContainerRuntime.build
```

`RunnerRuntime`, like `DockerRuntime`, is not bound to a session: one object serves any
session, and each call finds its session from its own argument (the spec's `aixle.session_id`
label in `create_container`; the admission whose `runtime_id` a container id or cleanup
identity is, for every other call).

The hosted branch is the existing expression, character for character.

| Phase | Hosted (unchanged) | `RunnerRuntime` |
| --- | --- | --- |
| `pull_image` | Pull the image | A no-op on every type, as on hosted Kubernetes: the host runner pulls the agent image in `container.start`, by the reference it is given, a tag or a digest (`manual`, `coder`), and the kubelet pulls on `kubernetes` |
| `create_container` | Create the pod | `Runners::Allocator.acquire(session)`: assign an idle environment (§7.3), or, on a `provisionable` type, create a `requested` row and call `provision` + `inject_bootstrap` for it. Raises `ContainerRuntime::CapacityError` when at `max_environments` (or, on `manual`, when every registered machine is busy), so the **existing** `capacity_wait` loop in V2 handles it |
| `start_container` | Service, IngressRoute, wait ready | `prepare`, then wait for check-in with activity heartbeats (immediate on `manual`, whose machine is already checked in). Raises a diagnosed failure on `bootstrap_timeout`. On `manual` and `coder` the host runner then gets `container.start` (§6.8) and the activity waits for the session runner inside the container to report ready. **Decided (§6.9.4):** nothing inside reports ready; `container.start` starts the container and waits for nothing more, as `ContainerRuntime::DockerRuntime#start_container` does |
| `exec` | `before_exec` context assembly + tmux launch via `runtime.exec`/`write_file` | Same strategy code. Each primitive is a runner op |
| (await `container_finished`) | Unchanged | Unchanged. `finish_session` reaches the platform through the runner's proxy (§6.6) |
| `cleanup` | Collect logs and outputs, remove the pod | Same collection via `read_file`, then `Runners::Allocator.release(environment, outcome)`, which scrubs, resets or tears down (§7) |

`SessionRuntimeOperation` (AD-5) keeps its meaning. `create_container`/`start_container`
stay replayable because `provision` is idempotent on `key`. `exec` stays non-replayable
because it launches the agent.

**What 8a built (§15 row 8a), on `manual`.** `ContainerRuntime.for_session` is as above, and
every call site that acts on one session goes through it (the list is in row 8a); the hosted
arm is `ContainerRuntime.build`. `ContainerRuntime::RunnerRuntime` sends one op per runtime
call and waits for its result. Until `Runners::Allocator` (task 11), the machine is
`Runners::Machines`' simplest rule: a free `registered` machine of the session's runner, one
session per machine.

| Phase | What `RunnerRuntime` does in 8a |
| --- | --- |
| `pull_image` | Nothing, as `KubernetesRuntime#pull_image` (Fix CR round 3) |
| `create_container` | Takes a free machine, the first phase that needs one (every machine busy is a `CapacityError`, so the session waits in `capacity_wait`; no machine registered, or every machine `failed`, is refused at launch by `Runners::Resolver` and fails the phase with a message that names the machines and how to bring one back), then `container.start`, with the image reference as the user gave it, a tag or a digest, `container.image_override` included, the strategy's env and the runner's `config.container`. The runner always pulls the image, then creates and starts the container (Docker's create API does not pull); a failed pull is the op's `image_pull_failed`. The runner pulls with the Docker credentials of the user it runs as, credential helpers included, Docker Hub's under `https://index.docker.io/v1/` as the Docker CLI looks them up, so an operator runs `docker login`, or configures a credential helper, as that user; the platform never contacts a registry. The pull, the volumes, the create and the start run until the op's `deadline_at` at most, and past it the runner creates nothing. A refusal the runner answered is a `ContainerRuntime::CreateRefusedError`, which pins no reservation; an expired or unanswered start stays uncertain (AD-5). The container's env carries the session's secrets and exists only in this phase (`ContainerService::CREATE_ONLY_KEYS`), so the runner creates and starts the container in this one op, as a Kubernetes pod is created running. A retry that finds its own container running adopts it. The container's name, which becomes the admission's `runtime_id`, is the platform's, `aixle-<machine key>-<session id>`: an answer that names another container is an error, and the create stays uncertain. The admission's identity (`runner-session-<id>`) is persisted before this phase, as for every runtime, so a failure or a stop in it, the pull included, still runs the cleanup below. The agent session's budget for this phase is 600 s, since the pull runs in it (§12.3) |
| `start_container` | `status` until the container runs, as `DockerRuntime#start_container` and `#wait_for_ready` wait for nothing more |
| `exec` | The same strategy code; each `exec`, `write_file` and `read_file` is an op |
| `cleanup` | Nothing while any op is unfinished (`pending` or `delivered`) on the machine the session holds, a `container.start` a stop cut short or an `env.reset` of an earlier attempt for one (the session holds the machine, so every op on it is the session's): the runner runs a machine's ops in order, so a cleanup op would wait behind it and expire. The cleanup answers `cleanup_pending` and the existing timer retries it, until the op is answered or expires (`BaseRuntime#cleanup_ready?`). Then the same collection through `read_file` and `exec`, `container.stop` (a failure is logged, and the reset still runs) and `env.reset`, and the machine is free again. A machine whose reset failed, or was not answered, is `failed` (§5.2) and held by no session, and takes no session until it is returned to service (task 11a); the failure applies only while the session still holds the machine (`Runners::Machines.fail!(…, holder:)`) |

The live log and the scanners read a runner session through `exec` and `status` ops, as hosted
reads through `exec`, and they keep doing so (Alex, 2026-11-11, §6.5). A session's ops go to its machine only while the
session holds it (`runner_environments.current_session_id`): `Runners::Operations.enqueue!`
checks the hold under the machine's row lock and creates nothing otherwise, and `RunnerRuntime`
then answers `no_session_container`. So a late op of a finished session never reaches the next
session's machine, its `env.reset` included, and the runner's `session_mismatch` is the safety
net on the machine. A machine unregistered during a session stops holding it
(`Runners::Registration.unregister!`): the session's next ops answer `no_session_container`, the
session fails as one whose container is gone, and its cleanup finds it absent and releases its
admission. The container itself keeps running on the machine: nothing can stop it, because the
runner is unregistered and its credentials are revoked, so the operator removes it by hand
until scrub and return to service (tasks 11 and 13). `CleanupStaleActivity` sends nothing to a runner: a stale runner session
should hold no machine, since its admission is released only once the machine is free or
`failed`, and one that still holds one moves it to `failed` ("held by stale session <id>"). A
reset under the scanners' 15 s cap could fail a healthy machine, and without the cap one silent
machine would hold up the sweep.

The wait for an op (`Runners::Operations.await`) polls the database. Between two looks it
heartbeats the activity and checks its cancellation, as `ToolStrategy#wait_with_heartbeat`
does, so a stopped session stops waiting at once; the op itself is left to its deadline. Polling
is to be revisited with P1 (§16), for example with a wake-up on the pub/sub the long-poll
already uses.

---

## 6. Runner protocol (v1)

This section keeps the design and its rationale. The wire contract as built (headers, limits,
refusals, token rules, endpoints and the op envelope) is specified in
[`runner/protocol/PROTOCOL.md`](../../../runner/protocol/PROTOCOL.md), and pinned by the
conformance fixtures in `runner/protocol/fixtures/v1/` (§14.1), which the gateway's Rails tests
run. Where the two say the same thing, `PROTOCOL.md` is the source of truth.

### 6.1 Transport

**Decision:** HTTPS long-poll plus HTTPS POST, JSON bodies, on port 443 to the platform's
gateway. There is no WebSocket in v1.

GitHub's self-hosted runner works the same way, for the same reasons. It goes through
corporate HTTP proxies (`HTTPS_PROXY` is honoured) and TLS-inspecting middleboxes. The
gateway stays stateless: any gateway process can serve any runner because the queue is
`runner_operations` in PostgreSQL. A WebSocket would pin an environment to one process and
need a fan-out layer to deliver an op from a Temporal worker to whichever process holds the
socket. Latency is still adequate: a poll returns the moment an op is enqueued, woken by a Redis
pub/sub message on `runner_env_<id>`, through `ActionCable.server.pubsub`, which already
runs on Redis (`config/cable.yml`). WebSockets come in only for the interactive tunnel
(§12.2, phase 4), where they are unavoidable.

The gateway is the same Rails codebase served by a **separate process type**
(`runner_gateway` in the Procfile and Helm). Held long-polls then never take Puma threads
from the UI, and the gateway can be scaled and rate-limited on its own.

**What v1 has so far (§15 task 5a).** `config/puma_runner_gateway.rb` serves the app the
way `config/puma_mcp.rb` serves MCP: `RUNNER_GATEWAY_PORT` (default 4003),
`RUNNER_GATEWAY_MAX_THREADS` and `RUNNER_GATEWAY_MIN_THREADS` falling back to
`RAILS_MAX_THREADS`, and `RUNNER_GATEWAY_PIDFILE`. `Procfile.dev` runs it as
`runner_gateway`, and Compose publishes the port.

Each process draws only the routes it serves. `config/routes.rb` draws `/up` in every
process, and the rest by `AIXLE_PROCESS_MODE`, which `config/puma_runner_gateway.rb` sets
to `runner_gateway` before the app loads, so the deployment sets nothing of its own:
- the gateway draws `config/routes/runner_gateway.rb`, the `/runner/v1` scope, and nothing
  else. `config/application.rb` also leaves Action Cable's own `/cable` mount out of it;
- every other process draws `config/routes/mcp.rb` (`/mcp` and `/action_mcp`) and
  `config/routes/web.rb` (everything else), and answers `404` on `/runner/v1/*`. MCP is
  still served by the web and MCP processes alike; a mode of its own for the MCP process
  is later work.

The ingress sends `/runner/v1` to the gateway workload. That workload, its Helm values and
the ingress route are a separate `aixle-infra` task, needed before the phase 3 staging
validation (§12.4). Until then the gateway runs locally and in tests only (§12.2).

The gateway's Puma caps request bodies (`http_content_length_limit`, at the size `PROTOCOL.md`
§2 states), enough for an op result with up to 1 MiB of output (§6.4, the output cap of `PROTOCOL.md` §6). It
answers `413` before it reads a body over the cap, chunked bodies included, so an oversized body
never reaches Rails.

**The long-poll's wake-up (§15 task 5b).** `Runners::Operations` (`app/services/runners/operations.rb`):
- **The channel's messages (task #209).** `runner_env_<id>` carries JSON objects told apart
  by their `type`: `{"type": "op_enqueued", "sequence": 42}`, an enqueue's wake-up, and
  `{"type": "poll_waiting", "poll_id": "<uuid>"}`, a waiting poll's announcement. A message
  that is not a JSON object, or of another type, makes a waiting poll read the queue again
  and ends nothing.
- **Publishing.** `enqueue!` publishes an `op_enqueued` message with the op's sequence on
  `runner_env_<id>` through `ActionCable.server.pubsub` once its transaction commits
  (`ActiveRecord.after_all_transactions_commit`). A rolled-back enqueue wakes nothing. A
  failed publish is logged and does not undo the op, which the next read delivers.
- **No missed wake-up.** `poll` subscribes to the channel and waits up to 2 s for Redis to
  confirm the subscription before it reads the queue. An op enqueued while the poll starts
  is then either seen by the read or announced on the subscription, and is returned at
  once. A wake-up that arrives between an empty read and the wait stays queued and ends the
  wait at once. After the wait, or a wake-up, the poll reads again, uncached, so the
  request's query cache cannot answer from the empty read before it.
- **No database connection while waiting.** `poll` returns the thread's Active Record
  connection to the pool before it subscribes and before every wait, and takes one again
  to read. A waiting poll holds a Puma thread but no connection.
- **One waiting poll per environment (task #206, §16).** A poll that is going to wait
  (`wait` above 0) publishes a `poll_waiting` announcement with its own `poll_id` on the same
  `runner_env_<id>` once it is subscribed, and ignores its own. A waiting poll of the
  environment that hears another poll's announcement stops waiting and answers `{"ops": []}`
  at once, freeing its gateway thread, and the newer poll waits. The two kinds of message are
  told apart by their `type`. A `wait=0` poll does not announce, so it ends no other poll. Of two polls
  that start together at least the later announcement reaches the earlier poll, so at most
  one keeps waiting; both may answer empty. No op is lost, since an op stays deliverable
  until `after` acknowledges it, and the replaced poll goes through the controller's check
  after the wait like any poll that waited. The channel is in Redis, so the rule holds
  across gateway processes. The poller is the environment on every type (§6.9.1), so the
  rule is per environment.

What this means for `RUNNER_GATEWAY_MAX_THREADS`: each thread of the gateway holds at most
one waiting poll, and each environment at most one waiting poll, so the thread count is the number of machines one gateway process can
hold waiting at once (a machine waits up to 25 s per poll). The pool (`DB_POOL`, by default
`RAILS_MAX_THREADS + 3`) only has to cover the requests that read or write at the same
moment: the token and flag checks, the queue reads and the results, each a few queries.
So a deployment can raise `RUNNER_GATEWAY_MAX_THREADS` well above the pool to hold more
machines per process; a burst of results beyond the pool then waits for a connection, up to
Active Record's 5 s checkout timeout. The default still falls back to `RAILS_MAX_THREADS`.

**Proxied calls hold threads too (task 8b).** Each call in flight through the callback proxy
(§6.6) holds a gateway thread for as long as its answer streams: up to
`ProxiesController::READ_TIMEOUT`, 900 s with no data, for an MCP tool call that runs that
long; an answer that sends nothing for 900 s is cut (`PROTOCOL.md` §5.8). Like a
waiting poll, it holds no database connection while it forwards (the controller releases it
first). So the thread count has to cover, per process, one waiting poll per machine plus the
proxied calls in flight at once: roughly one per running runner session at a time, more while
an agent runs tools in parallel or holds an MCP GET stream open. When the threads run out, the
next polls queue behind the proxied calls, and ops such as `container.stop` arrive late. There
is no per-environment cap on concurrent proxied calls (Alex, Fix CR round 1 of 8b).

Sizing it, and providing `RUNNERS_SECRET_KEY`, belong to the `aixle-infra` gateway
deployment task.

The controllers are `RunnerGateway::V1::*` (`app/controllers/runner_gateway/v1/`),
`ActionController::API` with no cookie session and no CSRF. Before anything else, every
request is checked for the protocol and version headers (`PROTOCOL.md` §1 and §3).

**Request schemas (task #209).** Each gateway request body, and the long-poll's query, has a
JSON Schema in `runner/protocol/schemas/v1/`, next to the protocol it belongs to
(`PROTOCOL.md` §5). The gateway is layered as `docs/architecture/implementation-patterns.md`
("Error Handling") says: transport in the controllers, the domain in the services, which take
named parameters and never see the request.
- **The controller** checks the headers (`X-Aixle-Runner-Protocol`, the form of
  `X-Aixle-Runner-Version`, and for `register` a version over 255 characters or below
  `min_version`), the token, and the shape of the body or query against its schema with one
  shared helper, `Runners::ProtocolSchema.valid?(name, document)`, through `json_schemer`, the
  way `Templates::Package` checks `template.yaml` against `config/templates/template.v1.json`.
  A failure is the endpoint's own refusal (`invalid_registration`, `invalid_result`,
  `invalid_request`). It then maps the body to the service's named parameters by the
  protocol's wire rules (an absent `os` or `arch` `nil`, `facts` `{}` and `auto_update` true
  when absent, `exit_code` an Integer), and
  maps a service's refusal, `Runners::Credentials::Refused`, to its status through
  `REFUSAL_STATUS`. The schemas are strict about types: `os` and `arch` are strings
  and `auto_update` a JSON boolean, and any other value is the endpoint's refusal, not cast. A field a schema does not know
  is ignored, so `aixle-runner` 0.2.0, which still sends `"ephemeral": false`, registers.
- **The service** (`Runners::Registration.register!`, `Runners::Operations.record_result!`)
  makes the domain refusals and raises `Runners::Credentials::Refused`.

A rule that needs the value itself stays where it is: a `name` blank once trimmed, and a value
over its column, are `RunnerEnvironment`'s validations, as is the shape of `facts`. Every new
gateway endpoint that takes a body or parameters, in 8b and 8c, adds its schema there and
follows the same layering.

Rack::Attack throttles `/runner/v1/*` per bearer token (keyed on its digest) and per IP, so a
client that sends a new bearer value on every request is still bounded, and `register` per IP
(§9.5). The limits are in `PROTOCOL.md` §2.

### 6.2 Endpoints

All requests are `Authorization: Bearer <token>`,
`X-Aixle-Runner-Protocol: 1`, `X-Aixle-Runner-Version: <semver>`.

| Endpoint | Caller | Purpose |
| --- | --- | --- |
| `POST /runner/v1/register` | controller, `manual` host runner | Exchange a registration token for long-lived credentials: controller credentials (`kubernetes`), or environment credentials for the environment the call creates (`manual`). Body: `{name, os, arch, facts, auto_update}`; fields it does not know are ignored (§6.3). |
| `DELETE /runner/v1/registration` | `manual` host runner | `aixle-runner unregister`: marks the environment `gone` and revokes its credential family. Refused with `409 busy` while a session runs, unless `--force`, which fails that session. |
| `POST /runner/v1/check-in` | host runner (`coder`, and `manual` after every start), session runner (`kubernetes` pod) | Coder and Kubernetes: exchange the bootstrap token for environment credentials. `manual`: authenticated with the environment credential, no token exchanged. All: report os/arch and facts, and the version in `X-Aixle-Runner-Version`. The response carries the environment, config (so far the upload limit; there are no log limits, since there is no log endpoint) and `update` (§14.4). **Built for `manual` (task 8c)**, below. |
| `POST /runner/v1/token` | both | Refresh-token rotation. |
| `GET  /runner/v1/ops?after=<seq>&wait=25` | both | Long-poll. Returns ops with `sequence > after`, batched. An empty 200 after `wait` doubles as the heartbeat. |
| `POST /runner/v1/ops/:id/result` | both | Op outcome. Idempotent on op id. |
| ~~`POST /runner/v1/sessions/:id/log`~~ | | **Not built (Alex, 2026-11-11):** a runner session's terminal is read through `exec` (§6.5). |
| `POST /runner/v1/sessions/:id/events` | session runner | `agent_exited {code}`, `agent_started`, `disk_low`, … |
| `POST /runner/v1/heartbeat` | both | Only when no poll is outstanding, e.g. while an op runs. Empty body, `204`. **Built for `manual` (task 12d)**, below. The running-session summary it was to carry moves to task 11, together with reconciliation, which reads it. |
| `ANY  /runner/v1/proxy/:route/*` | session runner | The callback proxy (§6.6). |
| `GET  /runner/v1/releases/:version/:os-:arch` | both | The binary's documented, stable URL. It answers `302` to the GitHub Release asset and sends the expected SHA-256 in `X-Aixle-Runner-Sha256` (§14.3). |
| `GET  /runner/v1/releases/:version/checksums` | both | The `sha256  file` list for that version, from the platform's pins (`runners.release` in `config/settings.yml`). |
| `GET  /runner/v1/install.sh` | bootstrap | Install script used by `inject_bootstrap` (`coder`). `manual` operators download the binary directly (§6.3). |

**What v1 has so far (§15 tasks 5a and 5b):** `register` for a `manual` machine,
`DELETE registration` and `token` (5a), and `ops` and op results (5b). What each one takes
and answers, every refusal and the order of the checks are specified in
[`runner/protocol/PROTOCOL.md`](../../../runner/protocol/PROTOCOL.md) §3 to §5. The
implementation choices behind them:
- **The checks.** The runner's status is cached for 5 s in `Rails.cache` (§9.2), and the
  flag refusal leaves the credentials valid (§9.3).
- **`register`** spends the token under a row lock, so two machines racing on one token
  create one environment.
- **`token`** treats a second use of a spent refresh token as reuse (§9.2) even after that
  token's own 30-day expiry, because the family it was rotated into may still be live.
- **`DELETE registration`** refuses nothing of its own yet: the `409 busy` refusal and
  `--force` are not built (`PROTOCOL.md` §8). Since task 8a it also ends the machine's hold on
  a session, whose next ops then answer `no_session_container`, so that session fails as one
  whose container is gone (§5.3).
- **`GET ops`** (§15 task 5b) selects the ops and marks them `delivered` in one transaction,
  with their rows locked `FOR UPDATE`, the lock a result takes: a result that holds an op's
  row first is committed before the poll reads it, so an op with a result is never returned.
  After a positive `wait` the access checks run again, read past the request's query cache
  and its local copy of `Rails.cache`, so a revocation or the flag turned off during the wait
  answers the refusal without the payload. Since task 12c every authenticated request of a
  machine, the poll and its empty answer included, is recorded as a heartbeat (§2.2,
  `Runners::Liveness.record!`), at most once every 15 s per machine.
- **`POST ops/:id/result`** (§15 task 5b) stores the fields other than `status` in `result`,
  encrypted with `runners_key` (§2.3), and the same update nulls the payload. No
  `/runner/v1/*` request has its params in the request log (`config/application.rb`), as
  for the credential endpoints, nor in Sentry's breadcrumbs (`before_breadcrumb` in
  `config/initializers/sentry.rb` drops them for `RunnerGateway::` controllers): a result
  carries command output and file contents, and no gateway body needs logging.

**What v1 has (§15 task 8c): `check-in` for a `manual` machine.** The host runner calls it after
every start, once the callback proxies of the sessions already running are served again and
before its first op, authenticated with the environment's access token (no token is
exchanged). `Runners::CheckIn.check_in!` writes the `X-Aixle-Runner-Version` and
`X-Aixle-Runner-Protocol` of the request to `runner_environments.runner_version` and
`protocol_version`, over the ones the machine registered with, so a machine that updated itself
(§14.4) shows its new version once it restarted, and `os`, `arch` and `facts` when the body has
them. The answer carries the environment, `config` (`upload_max_bytes`) and `update`, under the
rule of the empty `GET ops` answer (`Runners::Release.update_for`, §14.4), read after the report
is recorded. A runner below `min_version` is refused with `400 runner_version_unsupported`, as
at `register` (§14.4). The host runner reports the preflight's os, arch and facts, and a machine
that no longer passes the preflight still checks in, with the failure in `facts.preflight_error`.
A check-in that fails in a way the runner can wait out is tried five times at most with backoff;
then the runner logs it and starts its ops loop without one (the next start tries again), so a
failing check-in route does not stop a machine that can work. A refusal that ends its work
(`runner_version_unsupported`) still stops the runner.
What the wire does is `runner/protocol/PROTOCOL.md` §5.9. The bootstrap-token exchange comes
with the `coder` and `kubernetes` types.

**What v1 has (§15 task 12d): `heartbeat` for a `manual` machine.** `POST /runner/v1/heartbeat` is
authenticated like the other machine endpoints, with an empty body, and answers `204`. It records
liveness through `Runners::Liveness.record!`, as every authenticated request already does, and
nothing else. The host runner sends one at least every 25 s (it sends one every 20 s) while an op
runs and its result is posted, when it makes no poll; a heartbeat that fails is not retried. The
wire is `runner/protocol/PROTOCOL.md` §5.10, with fixtures in `heartbeat/`.

The other rows of the table are later tasks: session events and the
proxy in task 8 and later, and the releases endpoints and `install.sh` in tasks 10 and 17.

**Decided (§6.9.6), the callers.** No endpoint is called from the agent container. The
environment's owner, the host runner on `manual` and `coder` and the controller on
`kubernetes`, calls `check-in` (the controller once for each of its pods), `ops`, results,
`heartbeat`, session logs and events, and the proxy, which it relays for the session's proxy
sidecar (§6.9.3). The events endpoint carries no `agent_started` or `agent_exited`: a session
ends as on hosted (§6.9.4).

### 6.3 Registration and tokens (summary; full model in §9.2)

- **Kubernetes:** an admin creates the runner, the UI shows a one-time **registration
  token** and a ready-to-paste `helm install` command. The controller calls `register`, the
  token is consumed, and the controller gets an access/refresh pair.
- **Manual**, modelled on GitHub self-hosted runners, and the same `register` call and
  credential lineage as the Kubernetes controller. Only the operator-facing instructions
  differ. "Add machine" on the runner page mints a **short-lived, single-use** registration
  token (1 h) and shows a copy-paste sequence:

  ```sh
  # 1. Download and verify (the digest is from the platform's pins, §14.3)
  curl -fsSLo aixle-runner https://flow.aixle.com/runner/v1/releases/1.4.0/linux-amd64
  echo "<sha256>  aixle-runner" | sha256sum -c -
  chmod 0755 aixle-runner

  # 2. Register this machine (consumes the token); --no-auto-update turns self-update off (§14.4)
  sudo ./aixle-runner configure --url https://flow.aixle.com --token <registration token> --name build-01

  # 3. Run as a service that survives logout and reboot; install copies the binary into
  #    /var/lib/aixle-runner/bin, which the service runs and updates (§14.4)
  sudo ./aixle-runner service install && sudo ./aixle-runner service start
  ```

  `configure` calls `register`, which consumes the token, creates the environment row
  (§5.2) and returns an environment access/refresh pair that the runner stores locally
  (`/var/lib/aixle-runner/credentials`, mode `0600`, owned by the runner's own user).
  `service install` writes a systemd unit running `aixle-runner --mode host` as a
  dedicated `aixle-runner` system user, which it creates and adds to the `docker` group
  (§9.7). A machine needs one token each; a token that leaked after use opens nothing.
  Removal is `aixle-runner unregister` on the machine, or Revoke on the runner page (§9.3).
- **No ephemeral registration.** Removed from the plan (Alex, 2026-11-13): there is no
  `ephemeral` field in `register`, no `ephemeral` column and no release arm for it in §5.2.
  A body that still carries `ephemeral` registers, because the schema ignores fields it does not know.
- **No labels or runner groups.** Selection is explicit on the workflow or session (§3.3),
  and the company/project scope already does what runner groups do. The os/arch/facts
  report at registration and every check-in stays, so a machine that cannot run the agent
  image (no Docker daemon, wrong arch) is refused at connection time and not mid-session.
- **Every environment:** the platform mints a single-use **bootstrap token** bound to that
  environment and hands it to `inject_bootstrap` (Coder) or to the controller (Kubernetes).
  The runner calls `check-in`, the token is consumed, and the runner gets an environment
  access/refresh pair that is valid for that environment only.

**What v1 has so far (§15 task 5a).** `manual` registration only.
`Runners::Credentials.mint_registration!(runner)` (`app/services/runners/credentials.rb`)
mints a registration token for a live `manual` runner and returns it once; a revoked or
deleted runner is refused with `runner_revoked` (§9.3). Tests and local
development call it, and since task 12a so does "Add machine". Tokens carry a prefix by kind, so a leaked one is recognisable (the kinds, their
lifetimes and what a runner does on each refusal are in `PROTOCOL.md` §3 and §4). Only SHA-256 digests are stored. The plaintext appears only in the call or
response that issues it, and the tokens travel in the `Authorization` header, which is never
logged. `Runners::Registration` (`app/services/runners/registration.rb`) creates the
environment on `register` and, on unregister, marks it `gone` and revokes every credential
of that environment.

**What v1 has so far (§15 task 12a).** "Add machine" is on the page of every live `manual`
runner, the company's (`Web::Company::RunnersController#registration_token`) and the project's
own (`Web::Company::Projects::RunnersController#registration_token`), offered to whoever the
runner's policy lets update it (`registration_token?`, the same rule as update and revoke: a
company admin, and for a project runner also the project's owner). `Runners::MachineRegistration.issue!`
mints the token through `Credentials.mint_registration!` and returns it with the expiry (1 h),
the recommended version and, for each pinned platform (`linux-amd64`, `linux-arm64`), the URL
`<this host>/runner/v1/releases/<version>/<platform>` and its SHA-256 from the pins. The answer
is `201` with `Cache-Control: no-store`; the token is in no page prop and is held in the
browser only until the dialog closes. The dialog builds the sequence above with a machine name
(a plain `[A-Za-z0-9._-]` name, checked before it is put into a command) and an option that adds
`--no-auto-update` (§14.4). A revoked runner shows no button and is refused with `runner_revoked`
(`409`), a runner that is not `manual` with `runner_not_manual`, and a platform that recommends
no version with `no_runner_release` (both `422`).

**What v1 has so far (§15 task 12b).** The dialog has a **Docker** choice next to the platforms
(Alex, 2026-11-12). It runs `ghcr.io/aixlehq/aixle-runner:<recommended version>` (multi-arch)
and the machine needs neither systemd nor a service user: `configure` is run in a throwaway
container, then the runner in a container with `--restart unless-stopped`, the Docker socket and
the volume of §14.4. The runner's directory is `/var/lib/aixle-runner` on Linux and
`$HOME/aixle-runner` on macOS (OrbStack, and Docker Desktop as far as checked), a directory
Docker shares. The image does not update itself, so the dialog has no self-update option for
it. Removal is: stop and remove the container, run `unregister`, delete the directory and the
volume. A rootless Docker or Podman (another socket path) and Windows are not covered.

### 6.4 Operations

Each op is `{id, sequence, op, session_id?, deadline_at, payload}`. Results are
`{status: ok|error|expired, exit_code?, stdout?, stderr?, data?, error?: {class, message}}`,
`expired` for an op received after its deadline (below).

| Op | Maps to | Notes |
| --- | --- | --- |
| `exec` | `BaseRuntime#exec` | `{cmd: [..], env, cwd, user, timeout, stdin?}`. Each output stream is capped at 1 MiB inline, a constant of `PROTOCOL.md` §6, and a capped stream is marked. **Larger output comes back through an upload to a signed URL (task 8c, below).** |
| `write_file` | `#write_file` | `{path, content(b64), mode, uid, gid}`. Credentials travel this way, as they do to hosted pods today. |
| `read_file` | `#read_file` | Files up to 1 MiB inline; a larger file comes back through an upload to a signed URL (task 8c, below), and is refused only without a slot or past the upload limit. |
| `batch` | (new, internal) | An ordered list of the above, executed until the first failure. The runner implements it (`PROTOCOL.md` §6.3), and `RunnerRuntime` does not send it: 8a groups nothing (decision 5, P1 deferred). Grouping, when it comes, comes only through an explicit runtime method that every runtime implements, hosted included. |
| `status` | `#container_status` | `running`, `starting`, `terminated` or `missing` for the session's agent process. |
| `logs` | `#container_logs` | Tail of the terminal-output file. |
| `session.start` / `session.stop` | The tmux launch and kill done through `exec` today | v1 keeps the strategy's tmux commands (through `exec`). These ops are reserved for when the strategy stops shelling out. |
| `container.start` / `container.stop` | `create_container` + `start_container` / `cleanup` | Host-runner ops (`manual`, `coder`): `{image, env, workspace_volume, mounts, network, pid, resources, privilege_escalation}` and `{}`. The session's identity is only in the envelope's `session_id`. `container.start` always pulls `image`, the reference as the user gave it, a tag or a digest (Docker downloads only the layers it lacks, and no digest is returned; a failed pull is `image_pull_failed`), then starts the agent container with the image's own entrypoint, as a hosted pod runs; `container.stop` stops and removes it (§6.8). There is no op that only pulls: `pull_image` does nothing on a runner, as on Kubernetes (8a, Fix CR round 3). |
| `env.scrub` / `env.reset` | §7.2 | Host-runner ops. On `manual` these are the whole reset story, since there is no rebuild. |
| `provision` / `teardown` / `observe` | Kubernetes adapter | Controller-only ops. |

`toolcache.ensure` (revision 3, for `native` mode) is removed. If the `host` mode needs it,
it comes back in phase 7 under a protocol minor addition, which `[N-1, N]` support absorbs
(§14.4).

The `deadline_at` of an op is the activity's start-to-close timeout. A runner that receives
an op after its deadline reports `expired` and does not execute it.

**What v1 has so far (§15 task 8a).** `session_id` is in the envelope: a session op carries the
session it is for, and an environment op has no `session_id` key. It left the payloads of
`container.start` and `container.stop`. Every session op checks the container's
`aixle.com/session` label against it and answers `session_mismatch` on a mismatch, and a session
op without one answers `session_required` (`PROTOCOL.md` §6); `container.start` and
`container.stop` answer it too, and `container.stop` without any session container answers
`no_session_container`. The platform sends a session op only while the session holds its
machine. An op's `deadline_at` is its own budget and, at most, the end of the activity that
sends it less 5 s (§15 row 8a). The wait that sent it stops at its deadline and expires it, so
the activity learns the outcome before it ends; the sweep expires an op nobody waits for 10 s
past its deadline (§2.3).

**What v1 has so far (§15 task 5b).** The queue, the long-poll and the results carry every
environment op of the table above (`exec` to `env.scrub`/`env.reset`) as an opaque payload:
`enqueue!` checks that the payload is an object and `RunnerOperation` that the op is one of
these names. `session_id?` comes with `terminal_session_id` (task 8), and the controller
ops with task 19. The gateway caps nothing beyond its 2 MiB body limit (§6.1).
The op envelope and the result as built are in `PROTOCOL.md` §5.5 and §6. Each op's payload
and result schema, with its fixtures, is added there by the task that first implements the op
(6a, 6b, 8).

**What v1 has so far (§15 task 6b).** On `manual`, the host runner executes every op of the
table but `session.start` / `session.stop` (still reserved, answered `unsupported_op`) and the
controller ops, with their schemas in `PROTOCOL.md` §6.1 to §6.4. **The output cap is 1 MiB, a
constant of `PROTOCOL.md` §6** (Alex, 2026-11-05), because the runner reads no `Settings`:
`exec` keeps the first 1 MiB of `stdout` and of `stderr` and marks a capped stream
(`data.stdout_truncated` / `data.stderr_truncated`), and `read_file` of a file over 1 MiB
answers `file_too_large`. `Settings.runners.op_output_limit` is not declared, and how larger
output and files come back is decided in task 8, where they are first needed. Until then a
result whose encoded body is over the gateway's 2 MiB body cap (an `exec` near the cap on both
streams, or a `batch` of large steps) is answered `result_too_large` instead, so the op still gets
its one result (`PROTOCOL.md` §6). An `exec` is bounded by the op's `deadline_at`, whether it
has no `timeout` or a longer one (8a, Fix CR round 7), and answers `exec_timeout` past it, so one command that never ends cannot block the
serial ops loop (`PROTOCOL.md` §6.3).

**What v1 has so far (§15 task 8c): output and files over the 1 MiB cap come back through an
upload to a signed URL** (decision 3, Alex 2026-11-07; the specification is `PROTOCOL.md` §6.5).
The decisions:

- **Who issues the URL, and when.** The platform, with the op: `RunnerRuntime` gives every
  `exec` a slot for `stdout` and one for `stderr`, and every `read_file` a slot for `content`
  (`Runners::ResultUploads.issue`), as `uploads` in the payload. Signing is local, so a slot that
  is not used costs nothing. The runner reads no platform setting and calls no endpoint to get
  a URL.
- **Where the bytes go.** Into Shrine's `cache` storage under a key the platform minted
  (`Uploads::CacheUpload`, the slot a browser upload uses too), never through the gateway, whose
  2 MiB body cap and rate limits stay as they are. **S3:** a presigned `PUT` URL of the bucket.
  The platform reads the object from its storage, never through the URL.
- **Known limitation: uploads need a storage that presigns (S3)** (Alex, 2026-11-12). With the
  filesystem storage (development; the one whose files the proxy's `assets` route serves, §6.6)
  the platform issues no slots, and there is no stand-in endpoint: the only one the application
  has (`Api::V1::AssetsController#upload`) needs a browser session, which a runner has not, and
  an anonymous one would be a write endpoint open to the network. Output over 1 MiB then comes
  back as it did before 8c: an `exec` answers the first 1 MiB of a stream, marked truncated, and
  `read_file` answers `file_too_large`. The reason is stated where it shows: the cleanup's
  `log-collection-report.txt` names the files and outputs that were not collected whole and says
  that uploads over 1 MiB need S3-compatible storage, and the log has a warning. The runtime says
  it at the call: `ContainerRuntime::BaseRuntime#read_file_result` answers the content, whether
  it came back whole and why not (the base default is `read_file` and "whole"; `RunnerRuntime`
  fills it from the op's outcome). The cleanup (`AgentSessionStrategy#before_cleanup`) collects
  the answers of its own reads and `Sessions::LogCollector` reports what its read brought back
  cut, from the sizes its listing gives; the runtime keeps no state of a session for it. An
  `exec` cut at 1 MiB outside the cleanup is logged and nothing collects it.
- **One deadline.** The runner never uploads past the op's `deadline_at`, and the platform
  settles the op there. So an op that carries slots is given, on top of its own time, a budget
  that fits an upload of the largest size (`Runners::ResultUploads.budget`: 32 MiB at 1 MiB/s,
  and 30 s for the last request and the result posted, 62 s). The caller's `op_timeout` caps the
  sum, so a scan-capped call (the monitor's snapshot, the dead-container and stale scans) keeps
  exactly `scan_op_timeout` (15 s) with slots offered. The URL's extra five minutes are
  only a margin for clocks that differ. An upload that cannot finish before the deadline falls
  back as a failed upload does (below).
- **Lifetime and size.** A URL lives until the op's `deadline_at` plus 5 minutes (at least one).
  The largest upload is `Settings.runners.upload_limit`, 32 MiB, sent in each slot as
  `max_bytes` and told in `check-in`'s `config.upload_max_bytes`. A presigned `PUT` cannot carry
  a size limit, so both sides keep it: the runner cuts an `exec` stream there (marked
  `truncated`) and refuses a file over it (`file_too_large`), and the platform refuses an object
  over it, having read at most one byte more (`Uploads::CacheUpload#read`). The number comes from
  production data: of the 61 thousand `terminal_output.log` files since 2026-03-06 the largest
  is 18 MB and none is over 20 MiB, and session outputs are at most 144 kB; the large agent logs
  (up to 869 MB) never pass through `read_file`, since `Sessions::LogCollector` has the container
  upload them itself. A claim keeps one copy of the bytes (re-encoded and scrubbed in place),
  sized against worker-ruby's 2 GiB memory limit (the comment in `config/settings.yml`).
- **How the result names the upload.** `data.uploads.<name> = {id, size}`: the slot's own `id` and
  the bytes sent. The platform takes it only when the `id` is the one it issued for that output and
  the object has that many bytes; an upload that is missing, over the limit or of another size
  is no output, and an `exec` says so in its stderr. The runner leaves the inline text of an
  uploaded stream out. When its upload fails (after two retries of a network error or a `5xx`) the
  op still has its one result: an `exec` answers the first 1 MiB and `data.upload_errors`, a
  `read_file` answers `file_too_large` with the cause.
- **An upload no result claims.** `RunnerRuntime` removes the object of every upload a result
  names once it has read it, and every slot of an op that ended with no usable result (expired).
  What that cannot reach (an upload that landed after the platform stopped waiting, or whose
  result was never posted) stays in the `cache/` prefix, as an abandoned browser upload does. It
  is unreferenced, and its key cannot be guessed. **It relies on an expiry rule on the `cache/`
  prefix of the bucket** (for example one day), which an abandoned browser upload needs as well;
  the platform adds no sweep of its own, and the application repository declares no bucket
  configuration, so the rule is an infrastructure item to confirm in `aixle-infra`.
- **Nothing else changes for the strategy.** `RunnerRuntime#read_file` and `#exec` answer what they
  answered, with the whole content, so the cleanup's `collect_terminal_output`, `collect_logs`
  and `collect_outputs` store a terminal log, session logs and outputs over 1 MiB whole, as on
  hosted. The `logs` tail that the cleanup stored for a terminal log over 1 MiB (8a, Fix CR
  round 7) is no longer needed for a log of a live container; `container_logs` stays for a
  container that cannot be read (killed), as on hosted.
- **On the machine** the runner keeps the output it uploads in a temporary file, removed when the
  op ends, and a file of the container is copied out through the archive API into one. The upload
  is a `PUT` with the exact `Content-Length`, no `Authorization` and no redirect followed.

### 6.5 Logs and output

**Decided (Alex, 2026-11-11): no live-log chunks.** A runner session's terminal is read exactly
as a hosted one's: through `exec` and `tmux capture-pane`, which on a runner is one `exec` op, as
it has been since 8a. `Sessions::LiveLogReader`, `get_session_log`, the session monitor's
snapshot (`Sessions::Snapshot::ExecSource`) and `AuthErrorDetector` stay as they are, and so
does `NoOutput`, which is fed by that `exec` snapshot (§6.9.4).

- **Not built:** the `local` log driver and the follow of the container's log by the host runner,
  `POST /runner/v1/sessions/:id/log`, `session_live_log_chunks`, and the readers' switch to
  chunks. With the screen read through `capture-pane`, the chunks' only use would be a live view
  on a runner session's page until the interactive tunnel (§15 task 16) brings the terminal
  itself; a stopgap that would then be removed is not worth building.
- **The live view** on a runner session's page comes with the tunnel (task 16).
- **Final:** unchanged. `before_cleanup` runs `collect_logs`, `collect_terminal_output` and
  `collect_outputs` (`find /workspace/outputs`, `read_file`) through `RunnerRuntime`. A terminal
  log, session logs and outputs over 1 MiB are collected whole, through the upload of §6.4
  (task 8c).

### 6.6 The callback proxy

Today the agent calls back to `internal_base`. That covers `/action_mcp` (MCP with
`X-Session-Key`), `/agents/credentials{,/refresh}`, `/agents/git/credentials`,
`/azure/git/credentials`, `/cloud/aws/credentials`, container asset downloads and OTLP
ingest. None of these are reachable from a customer network, and they should not become
public.

**Decision:** the session runner listens on `127.0.0.1:<port>` next to the agent (inside
the agent container, on every type) and forwards an
**allow-list of routes** through `ANY /runner/v1/proxy/:route/*`. A session's callback
addresses (`Settings.mcp.server_url`, `CREDENTIAL_SYNC_URL`, `AIXLE_GIT_CREDENTIALS_URL`, …)
are resolved through its runtime, `ContainerRuntime.callback_url(:mcp, session)` (or
`runtime.callback_url(:mcp, session)` where the caller already holds the runtime): a hosted runtime
answers the `Settings` value unchanged, and `RunnerRuntime` answers
`http://127.0.0.1:<port>/<route>`. Every place that hands the container an address reads it
there, and nothing rewrites a string afterwards (task 8b, decision 6). The
gateway:

1. authenticates the environment credential,
2. checks that the session key in the forwarded request (`X-Session-Key`, `AIXLE_GIT_KEY`,
   …) belongs to the session **currently assigned to this environment**,
3. forwards to the internal endpoint with the request unchanged plus
   `X-Aixle-Runner-Environment`, so those endpoints keep working as they do now.

A session key copied out of an environment is therefore useless anywhere except through
that environment's credential, and only while that session runs there.

**Decided (§6.9.3):** the listener on `127.0.0.1:<port>` is a proxy sidecar
(`aixle-runner --mode proxy`) that shares the agent's network namespace, not a process in
the agent container. It holds no environment credential and relays to the environment's
owner: the host runner over a Unix socket mounted into the sidecar only (`manual`, `coder`),
or the controller with a per-session proxy key (`kubernetes`, §6.9.7). The owner adds the
environment credential, so steps 1 to 3 above, the per-endpoint session-key checks included,
are unchanged. With `network: host` the host runner listens itself.

**As built (§15 task 8b), on `manual`.** The wire is `PROTOCOL.md` §5.8.

- **The seam** is `ContainerRuntime::CallbackUrls`: the names `:mcp`, `:agent_credential_sync`,
  `:agent_credential_refresh`, `:git_credentials`, `:azure_git_credentials`,
  `:cloud_credentials`, `:container_assets` and `:otel`, and `BaseRuntime#callback_url`, whose
  hosted arm is the `Settings` value. `RunnerRuntime#callback_url` answers `Runners::Proxy`'s
  address. `ContainerRuntime.callback_url(name, session)` builds the session's runtime and asks
  it, a nil session getting the hosted runtime, for the callers that need only the address
  (`read_tool_result`, `Trackers::Workspace`). The readers: the strategy's env vars (`AgentBaseStrategy#build_env_vars`, which hands
  the adapters' `default_env_vars` the session's addresses, and the git setups'
  `container_env`), the MCP config (`SessionContextService#build_internal_mcp`), the asset URLs
  of the context, the step's assets and the tracker files (`ContainerAssetUrl`, which now puts a
  URL's path below a host that has one), `read_tool_result`'s output, and the OTLP endpoint of
  the Codex and Gemini config files (`credential_workflow_config`).
- **The allow-list** (decision 7) is `Runners::Proxy::ROUTES`: `mcp`, `agent-credentials`,
  `agent-credentials-refresh`, `git-credentials` (GitHub, GitLab, Bitbucket),
  `azure-git-credentials`, `cloud-credentials` and `assets` (`GET` and `HEAD` under `store/`,
  the filesystem storage's files; a presigned S3 URL is never rewritten). Each route names the
  methods it takes, and only `assets` takes a path below it.
- **The session check** (step 2) is `Runners::Proxy.holder(route, environment, session_id:, key:)`; the controller reads the headers and passes their values, and the service never receives the request (§6.1): the MCP key in `X-Session-Key`
  must resolve to the session that holds the machine (`current_session_id`); a credential route
  needs that session's id in `X-Session-Id` and its own key for that endpoint (`X-Agent-Key`,
  `X-Git-Key`, `X-Azure-Git-Key`, `X-Cloud-Key`). `assets` carries no key, on the internal
  address either, so it needs only a session on the machine.
- **The forward** (decision 8) is `RunnerGateway::V1::ProxiesController`: an HTTP request to the
  route's hosted address inside the platform, the agent's request unchanged, the bearer and the
  gateway's headers left out, `X-Aixle-Runner-Environment` added, and the answer streamed back
  with `ActionController::Live`, chunk by chunk. No body schema (decision 9). Every refusal of
  the route carries `X-Aixle-Runner-Refusal`, so the runner tells it from the endpoint's own
  answer.
- **No OTLP route yet** (decision 7): `RunnerRuntime#callback_url(:otel)` is nil, so a runner
  session gets no OTLP variable. Claude Code and Gemini CLI then have telemetry off, Codex no
  `[otel]` block, and Kiro CLI `KIRO_DISABLE_TELEMETRY`, since its export would otherwise fall
  back to the vendor's collector. The route comes with a later task.

### 6.7 Heartbeat, reconnect and resume

- A long-poll or heartbeat every ≤ 25 s counts as a heartbeat; the host runner sends a
  `POST /runner/v1/heartbeat` whenever no poll is outstanding, which is while it runs an op
  (task 12d). After 90 s without one the environment is flagged `unreachable`. The session page
  shows no banner for it (removed from the plan, Alex 2026-11-13).
- **The agent keeps running while disconnected.** Its process tree belongs to
  `aixle-runner`, not to a request. The runner queues events. There is no log buffer: the log
  is not shipped as chunks (§6.5, Alex 2026-11-11).
- **Op execution is at-most-once:** the runner that holds the environment credential keeps a
  local journal (`journal.json` in its state directory, `/var/lib/aixle-runner` on `manual`)
  of the op ids it has executed and their results
  for 24 h. That is the host runner on `manual` and `coder`, and the session runner in a
  `kubernetes` pod. A redelivered op returns the
  journalled result without re-executing it. This closes the ambiguous "did my exec run?"
  case that kube-exec has.
- **Resume:** on reconnect the runner refreshes its token if needed, polls with
  `after=<last acked seq>`, and posts the session summary (agent running or exited with a
  code; the summary rides on the heartbeat, which task 11 adds together with reconciliation,
  and the heartbeat's body is empty until then). The platform reconciles: an exit the platform did not know about is handled like a
  dead container today (`DeadContainerScan` semantics) and fails the session with "agent
  exited (code N)" unless `finish_session` already ran.
- **Grace:** after a fixed 15 minutes without contact (a constant: `reconnect_grace` is not a
  runner setting, Alex 2026-11-13, and reconciliation, task 11b, uses the constant), the session fails with *"Runner environment lost contact for 15
  minutes"*, and the environment is marked `failed` and torn down if the adapter can still
  reach it. The admission slot stays held until the adapter confirms teardown or `observe`
  returns `missing`, per AD-4 "unknown creation retains capacity", and is otherwise released
  by the reconciliation sweep. On `manual` there is no teardown and `observe` never says
  `missing`: the slot is released when the machine reconnects and reports the session's
  container gone (it then gets the automatic reset of §7.2 before it is `idle` again), or
  when an admin revokes the machine (per-machine Revoke, §9.3, which also frees the slot
  held by a lost machine's session; there is no Force release).
- `finish_session`/`fail_session` go through the proxy (§6.6). If the proxy is down at that
  moment, the MCP call fails, the agent retries as it does on any network error, and the
  runner keeps the agent alive until the call lands or the 15-minute grace expires.

**Decided (§6.9.6):** the journal belongs to the environment's owner on
every type, the controller on `kubernetes` instead of a session runner in the pod. The agent's
process tree belongs to the container runtime (the Docker daemon, the kubelet). The owner
ships no log, so a restart has none to re-read (§6.9.4, Alex 2026-11-11). There is no session summary
from inside: an exited container is read from its status by the owner and handled with
`DeadContainerScan` semantics.

### 6.8 What runs inside the environment: container mode only in v1

**Decision:** in v1 the agent runs in **the stock agent image**
(`AgentRuntime.fetch(agent_type).image`) on every type, `manual`, `coder` and `kubernetes`
alike. `aixle-runner --mode session` is PID 1 and supervises the image's `entrypoint.sh`.
On `manual` this changed with task 6b: the image's own entrypoint is PID 1 and no runner runs
inside the container (decision 1 below; the other types are task #205).
This is **container mode**, and it is the only execution mode in v1. A Docker daemon is a
prerequisite on `manual` and `coder`, reported at check-in (§8) rather than discovered
mid-session. Revision 3's Coder `native` mode is dropped (see "Dropped" below).

**Which image a runner session gets (Alex, 2026-11-12, #229).** A session on a runner gets
its own default agent images, set apart from the hosted ones: the hosted prefix
(`AGENT_IMAGE_PREFIX`) is a private registry on staging and production, which a customer's
machine cannot pull from (`image_pull_failed`). The defaults are the public images,
`ghcr.io/aixlehq/flow-<image>`. `Settings.runners.agent_image_prefix`
(`RUNNER_AGENT_IMAGE_PREFIX`) and `Settings.runners.agent_images.<runtime>`
(`RUNNER_AGENT_IMAGE_<RUNTIME>`) change them, as `agents.image_prefix` and `agents.images`
do for hosted sessions; the tag is `Settings.runners.agent_image_tag`
(`RUNNER_AGENT_IMAGE_TAG`, default `latest`), not the hosted `agents.image_tag`, which can be
a build tag (`sha-…`) that GHCR does not carry (QA, #229). The runner's
`container.image_override` wins over the default; hosted sessions are unchanged. The choice
is made in one place, `ContainerRuntime::RunnerRuntime#runner_image`, next to the override:
`container.image_override` (with `{agent}`), else `runners.agent_images.<runtime>`, else the
prefix, the runtime's image name and the tag. The strategy's (hosted) image is not used for a
session on a runner. A private
image needs `docker login` on the machine: no registry credentials are sent to it.

**Decided (§6.9):** `aixle-runner` is not PID 1 on any type, and nothing of it is in the
agent container. The image's `entrypoint.sh` is PID 1, as in a hosted pod. The session ops,
the live log and the tunnel's relay are the environment owner's (the host runner on `manual`
and `coder`, as #204 builds it, and the controller on `kubernetes`), and the callback proxy is
a sidecar in the agent's network namespace.

**Decided (Alex, 2026-11-06), container mode on Coder (§15 row 17).** v1 supports only Coder
workspaces that are virtual machines (§2.6). A workspace runs one session at a time; a second
concurrent session gets another workspace, up to the runner's limit. `reuse` (the default)
keeps the workspace warm between sessions, and `fresh` gives each session a new workspace and
deletes it afterwards (§7.1). The reason for the type: it moves load from our cluster to the
customer's machines, and the customer can run the machines in their own subnet, with access to
private resources that are never exposed.

#### The finding behind it

A session environment is not "an agent CLI plus a proxy". From the stock image,
`docker/base/entrypoint.sh` starts **five** things:

1. **ttyd, twice**, both attached to the `agent` tmux session: a writable instance
   (`ttyd -W`) for the session owner, and a read-only one (`ttyd -R`, `tmux attach -r`) for
   everyone else;
2. **openvscode-server**, the IDE;
3. **the file watcher** (`/opt/watcher`, WebSocket + HTTP);
4. **the tmux session** with `pipe-pane`, which writes the replayable terminal log;
5. **the MITM stack**, sourced from `/opt/mitm/start-mitm.sh` (`docker/base/logger/`).

And the MITM stack is only half a daemon:

1. `mitmdump` on a port. That part is a service and can live in a container of its own.
2. A **per-session CA**, deliberately not baked into the image, which must be trusted in
   **three** stores: Node through `NODE_EXTRA_CA_CERTS`, OpenSSL/curl/git/Python through the
   rebuilt combined bundle, and the NSS database through `certutil`.
3. **`http2-logger.js`, loaded into the CLI process** through `NODE_OPTIONS --require`,
   because some CLIs speak HTTP/2 directly and a forward proxy cannot see that traffic.
4. **Pane-log redaction**: `redact-stream.py` in the `pipe-pane` sink.

Items 2–4 must live wherever the CLI lives. So "service containers plus the CLI on the
host" does not remove the host-side burden. It splits it in an unexpected place: the host
still needs the three CA stores, `certutil`, the HTTP/2 logger inside the CLI's own process,
and a redaction path.

The second consequence decides it, given that the interactive tunnel is phase 4 (§12.2).
ttyd, the IDE and the watcher come from the image, so **in container mode the tunnel is a
pure relay** of ports that already exist inside the container. With the CLI on the host,
all three would have to be installed and supervised on the host, on a machine we do not
control.

#### What container mode gives, and what it costs

- **Parity with hosted out of the box.** The five services come with the image exactly as
  in a hosted pod. They do not have to be re-proved on every customer machine.
- **Every agent runtime works** (`agent_runtimes: all`, §4), including usage accounting for
  `cursor_cli` and `grok`, which reads the MITM log.
- **One prerequisite:** a Docker daemon and disk.
- **Cheap, reliable scrub.** Credentials, the prompt, the MITM CA and the agent's home live
  in the container layer, so removing the container removes them (§7.2).

**The trade-off, stated plainly:** the machine's or the template's own tools (compilers,
CLIs, a VPN client, a pre-warmed cache) reach the agent **only through what is mounted into
the container**. The image decides the agent's userland.

**Steer customers to mounts first.** This is the cheap answer to the environment axis, and
the runner form, the runner page and the docs offer it before anything else. The
`config.container` options below cover most of "the agent must see my toolchain":

- `extra_mounts` for a toolchain directory (`/opt/toolchains:/opt/toolchains:ro`);
- `home_mount` for dotfiles and user-installed tools;
- `cache_mounts` for package caches;
- `network: host` for a VPN client or an interface on the machine;
- `pid: host` for the rare tool that has to see host processes.

The second answer is an image built `FROM` ours (`config.container.image_override`, on
every type, prerequisites checked at check-in). The `host` mode is the third, and it is not
in v1.

#### Per type

**Decided (§6.9):** on `kubernetes`, session pods run the stock image with the proxy
sidecar and no init container, and the controller runs the session ops through the
Kubernetes API (§6.9.2). On `manual` and `coder` the session runner below is replaced by the
host runner itself (#204) and the proxy sidecar (§6.9.3); the Unix socket goes into the
sidecar, never into the agent container.

- **Kubernetes:** session pods run the stock image with `aixle-runner` as PID 1. The kubelet
  is the container runtime. Of the `config.container` options, `resources` and
  `image_override` apply (§2.7); `image_override` is allowed only for images built `FROM`
  our base image. The host-access options do not exist on this type: a pod has no machine
  of the customer's to share.
- **`manual` and `coder`: a host runner and a session runner.** On `manual` this is
  superseded by decision 1 of task 6b (below): there is no session runner, and the host runner
  runs the session ops itself through the Docker API. The three bullets that follow are the
  original design, kept for `coder` and for task #205.
  - The **host runner** (`aixle-runner --mode host`) is installed by the operator
    (`manual`, §6.3) or by `inject_bootstrap` (`coder`). It holds the environment credential
    and the journal, and polls the environment's ops. It executes `container.start` (which
    pulls the image) / `container.stop`, `env.scrub` and `env.reset` itself. Per session it
    starts one container named `aixle-<environment key>-<session id>`, labelled
    `aixle.com/environment=<key>` and `aixle.com/session=<id>`, from the agent image
    reference it is given. Its own binary is bind-mounted read-only as the container's PID 1 in
    `session` mode.
  - The **session runner** in the container runs the session ops (`exec`, `write_file`,
    `read_file`, `status`, `logs`), the live-log tail and the callback proxy (§6.6). It
    reaches the gateway **through the host runner** over a Unix socket mounted into the
    container. The host runner forwards the protocol unchanged and adds the environment
    credential. So the environment credential never enters the container, and an agent that
    reads its own filesystem cannot take the runner's identity.
  - Restarting the host runner (self-update, crash, `systemctl restart`) does not stop the
    agent. The container keeps running, the session runner buffers, and the host runner
    reattaches to the socket by container name.
  - Prerequisites checked at registration (`manual`) and at every check-in: Linux
    amd64/arm64, a reachable Docker daemon (`docker version` API ≥ 1.41), and 20 GiB free
    for images plus the workspace volume. A missing prerequisite makes the environment
    `failed`, with the reason.

**What v1 has so far (§15 task 6a).** The host runner's core, on `manual` only, with no
session mode yet (task 6b):

- **`aixle-runner configure`** runs the local preflight first: Linux on `amd64` or `arm64`,
  the Docker daemon's API at 1.41 or later (read with the SDK's `ServerVersion`), and 20 GiB
  free under the daemon's `DockerRootDir`. A failed check is listed and no `register` call is
  made. It then calls `register` with the os, the arch and the preflight results as `facts`
  (`docker`, `docker_api`, `docker_root_dir`, `disk_free_bytes`), and stores the platform URL,
  the environment and the token pair in `/var/lib/aixle-runner/credentials`, mode `0600`
  (`--state-dir` moves the directory for `configure`, `unregister` and `--mode host`; the
  `service` commands take no `--state-dir` and always use `/var/lib/aixle-runner`). A
  machine that is registered already is refused until it is unregistered. Before the
  preflight, `configure` stops if it cannot tell whether a credentials file exists (any
  error but a missing file) or cannot write the state directory (it creates the directory,
  then writes and removes a probe file), so a non-root run cannot spend the token and then
  fail to store the pair. With no credentials file, it deletes a stale `journal.json`
  before it spends the token, so a new environment starts at `after=0`. `unregister` calls
  `DELETE /registration`, then deletes the credentials and the journal; if the platform no
  longer accepts the credentials, it deletes them anyway.
- **The state directory's lock.** `--mode host` takes an exclusive `flock` on the state
  directory itself (not a lock file, which a root `configure` would create and the
  `aixle-runner` user could not open) and holds it while it runs; a second host runner
  refuses at once. `configure` and `unregister` take the same lock and, while a host runner
  runs, refuse and say to run `aixle-runner service stop` first.
- **`aixle-runner service install`** creates the `aixle-runner` system user, adds it to the
  `docker` group, and gives it the state directory (mode `0700`) and the binary's directory
  `/var/lib/aixle-runner/bin` (mode `0755`, task 10, decision 3). It then copies the running
  binary to `/var/lib/aixle-runner/bin/aixle-runner`, atomically, owned by that user with mode
  `0755`, so the runner can replace it when it updates itself (§14.4), as the GitHub Actions
  runner lives in its own user's directory. It opens the running binary once, through
  `/proc/self/exe`, before anything else, and both decides and copies from that descriptor,
  so a swap of the path it was started from cannot change what it installs. It skips the copy
  only when that path, read without following a link, already is the running binary as a
  regular file owned by the service user with mode `0755`, what the copy would make. In every
  other case it copies, and the rename replaces a symlink there itself, not its target. The
  unit always runs that copy, so a binary started from a directory another user can write
  cannot be replaced under the service. The service user itself can replace it: it is
  root-equivalent through the `docker` group anyway (§9.7). Until task 10 the copy was
  `/usr/local/bin/aixle-runner`, owned by root. `install` then installs and enables
  `/etc/systemd/system/aixle-runner.service`, which runs
  `/var/lib/aixle-runner/bin/aixle-runner --mode host` as that user, with `Restart=always`. `uninstall` disables and removes
  the unit and keeps the user, the binary and the credentials. `start` and `stop` drive the
  unit. A host runner stopped by a refusal that needs an operator, or started with a missing
  or invalid credentials file or a `journal.json` that is not valid JSON, exits `3`, which
  the unit does not restart. For the journal, the message names the file and says to run
  `aixle-runner unregister`, then `configure` with a new token; both work with the corrupt
  file in place. The journal's values are not validated beyond that: the runner writes the
  file atomically, so impossible values only come from a hand edit.
- **The service user's lookup** in `configure` (run as root after `service install`) runs
  before `register`, next to the state directory's probe. Only a user that does not exist
  yet is skipped; any other lookup failure, or a uid or gid that is not a number, stops
  `configure` before the token is spent. The files are handed to the user after they are
  stored.
- **`--mode host`** long-polls `GET /runner/v1/ops?after=<after>&wait=25`, one poll at a time.
  The access token is refreshed 5 minutes before it expires and on an access `invalid_token`;
  every new pair is written atomically before it is used. Each refusal is handled as
  `PROTOCOL.md` §3 says, with backoff from 1 s doubling to 60 s and jitter in the upper half
  of each delay. No token reaches a log line or an error message.
- **The journal** is `journal.json` in the state directory. An op is journalled before it
  runs and its result before it is posted; `after` moves past an op only once its result is
  settled (accepted, or dropped on a `404` or a runner-bug refusal), and is persisted there.
  A redelivered op is answered from the journal, and an op that a restart interrupted is
  answered `interrupted` without running again. A graceful stop (SIGTERM) during an op leaves
  its entry begun instead of journalling the handler's cancellation, so it is answered
  `interrupted` too. Accepted entries are kept for 24 h; an entry whose result was never
  accepted is kept until it is. Every write syncs the file and its directory, and a failed
  directory sync is an error. An op received
  after its `deadline_at` is answered `expired`, and an op this version does not implement
  `unsupported_op` (`PROTOCOL.md` §6).
- **The image is pulled by `container.start`.** 6a had an `image.ensure` op that pulled
  `image@digest` when the daemon did not have it. 8a removed the digest (Fix CR round 1), then
  the op itself (Fix CR round 3): `container.start` always pulls the reference as the user gave
  it, a tag or a digest, before it creates the container, since Docker's create API does not
  pull, so a moved tag is followed and Docker downloads only the layers it lacks. A failed pull
  is the op's `image_pull_failed`, with the registry's message (`PROTOCOL.md` §6.1).

**Decision 1 of task 6b (Alex, 2026-11-05): no runner inside the agent container on
`manual`.** The host runner runs the session ops itself, through the Docker Engine API, against
the session's container: exec, the archive API for files (what `docker cp` does), inspect for
the status. That is how `ContainerRuntime::DockerRuntime` works in development. The agent
container runs the stock image with its own entrypoint, as a hosted pod does. So the host
runner is the environment's only poller, with one `after` and one journal (§16, "Concurrent
long-polls per environment"). The in-container session runner (`--mode session` as PID 1) and
its Unix-socket relay are not built. Where the callback proxy (§6.6), the live log (§6.5) and
the tunnel run, and how `kubernetes` runs the session ops, is worked out in task #205, before
task 8.

**What v1 has so far (§15 task 6b).** On `manual`, `--mode host` runs every op but
`session.start` / `session.stop`, which stay reserved and are answered `unsupported_op`
(`internal/docker` in `runner/`; the schemas are `PROTOCOL.md` §6.2 to §6.4):

- **`container.start`** creates and starts `aixle-<key>-<session_id>`, labelled
  `aixle.com/environment=<key>` and `aixle.com/session=<session_id>`, from the image reference
  (`image@digest` in 6b; 8a removed the digest), with the image's own entrypoint and command,
  unchanged. The session is the envelope's `session_id` (8a; 6b carried it in the payload). The
  payload carries `image`, `env`,
  `workspace_volume` (default on: `aixle-ws-<key>` at `/workspace`), `mounts` (`cache`, the
  volume `aixle-cache-<key>-<name>`, or `bind`, read-only unless `writable`), `network`
  (`bridge` | `host`), `pid` (`private` | `host`), `resources` (`cpus`, `memory_bytes`,
  `pids_limit`) and `privilege_escalation`, so that task 8 can fill it from `config.container`
  (§2.7) and the strategy's env. As on the hosted pod, `NET_RAW` is dropped and
  `no-new-privileges` is set unless `privilege_escalation`; the restart policy is `no`
  (§17.1). The volumes are created with the environment's label first. Nothing of the runner
  goes in: no binary, no socket, no token, and a `bind` whose source (symlinks resolved) is,
  contains or is inside the state directory is refused with `forbidden_mount`. An environment
  that already has a container is refused with `container_exists`, or `session_mismatch` when
  it is another session's (8a), so it has at most one session container. A container that was
  created but did not start is removed, under a 30 s timeout of its own, so a stalled daemon does
  not hold up the serial ops loop. A removal that fails is logged, the answer stays
  `container_start_failed`, and the cleanup's `env.reset` removes what is left.
- **`container.stop`** stops the container (SIGTERM, SIGKILL 10 s later) and removes it with
  its anonymous volumes; the named volumes stay. In 6b a container already gone was `removed:
  false`; since 8a the op without this session's container answers an error and touches
  nothing: `session_mismatch` when the environment's session container is another session's,
  `no_session_container` when there is none.
- **The session ops** act on the environment's container labelled `aixle.com/session`, found by
  label for every op, so nothing about it lives in the runner's memory or state. `exec` creates
  an exec without a TTY with its `user`, `env` and `cwd`, writes `stdin` and closes it, and
  reads the multiplexed stream; each stream keeps its first 1 MiB and is marked when capped
  (§6.4). A `timeout` runs the command under coreutils `timeout -k 5`, which the agent images
  have, since the daemon cannot end an exec; one that ran past it is an `exec_timeout` error.
  `write_file` and `read_file` use the archive API, with the mode and owner in the tar header;
  `read_file` follows one symlink and refuses a file over 1 MiB. `batch` checks every step
  first and runs `exec`, `write_file` and `read_file` steps until the first failure, an exec's
  non-zero exit code included. `status` maps the inspect as `DockerRuntime#container_status`
  does, with the exit code of a terminated container. `logs` returns the tail of
  `/tmp/terminal_output.log`. Without a session container a session op answers
  `no_session_container`: `exec` needs it running, the file ops and `logs` only need it to
  exist, so the output of an agent that ended can still be collected.
- **A host-runner restart does not stop the agent.** The container belongs to the daemon. A
  restarted host runner finds it again by its labels; an op that the restart cut off is answered
  `interrupted` on redelivery and does not run again, as for host ops (the command an `exec`
  started keeps running in the container).
- **The journal drops a result once it is settled.** Session ops return up to 1 MiB per
  stream, and a `read_file` can return a credential, so `journal.json` keeps a result only until
  the gateway accepts it; an accepted entry keeps its id, sequence and the `accepted` mark.
- **`env.scrub` and `env.reset`** are described in §7.2, "As built".

#### Container options (`config.container`)

Access from the container to the machine is **explicit**. Nothing is shared unless the
runner's config says so. The adapter validates these options, and the runner page lists
them, because each one widens what the agent can touch. The table explains what each
option does; types, defaults and per-type applicability are in §2.7. All of them apply to
`manual` and `coder`; on `kubernetes` only `resources` and `image_override` do.

| Option | Default | Effect |
| --- | --- | --- |
| `workspace_volume` | on | A per-environment named volume `aixle-ws-<key>` mounted at `/workspace`. This is what keeps repository checkouts warm across sessions (§7.1). |
| `cache_mounts` | `[]` | Extra named volumes (`aixle-cache-<key>-<name>`) or host paths for package caches, e.g. `~/.cache/pip:/home/agent/.cache/pip`. |
| `home_mount` | off | Bind-mounts a home directory of the machine (`path`; on `coder` the workspace user's `$HOME` by default, on `manual` required) read-only by default, to give the agent its dotfiles and tools. |
| `docker_socket` | off | Mounts `/var/run/docker.sock`. This **gives the agent root on the machine**. The form says so, and it is refused unless the runner is explicitly flagged `container.allow_privileged_mounts`. |
| `network` | `bridge` | `host` drops network isolation, for customers who need the agent on the machine's own interfaces (a VPN client on the host). |
| `pid` | `private` | `host` drops PID isolation. |
| `extra_mounts` | `[]` | Arbitrary `src:dst[:ro]` bind mounts, validated as absolute paths. Read-only unless `:rw` is written out. |
| `resources` | from the hosted pod spec | `--cpus` / `--memory`, so a session cannot starve the machine. Pod requests and limits on `kubernetes`. |
| `image_override` | none | An image built `FROM` our base image instead of the stock one, prerequisites checked at check-in. It is one image for every session on the runner, unless it contains `{agent}`, which is replaced at launch with the session agent's image name (`claude-code`, `codex`, …): `ghcr.io/aixlehq/flow-{agent}:develop` starts each agent in its own image. `{agent}` is the only placeholder; `Runners::ConfigSchema` refuses an unknown one, or a value that is not an image reference once replaced, when the runner is saved. |

The container receives the same environment variables the hosted pod spec sets for the
image, with the callback addresses of the session's local proxy (§6.6). On
`manual` there is no session runner (task 6b, decision 1): where the proxy runs is task #205.
**Decided (§6.9.3):** the addresses are the proxy sidecar's on `127.0.0.1:<port>`, or the host
runner's own listener with `network: host`. **As built (task 8b):** the strategy reads them
through the session's runtime (`callback_url`, §6.6), so the strategy code is the same on both,
and `RunnerRuntime` rewrites nothing.

**Image size.** Agent images are pulled from GHCR on the machine (or through the customer's
registry mirror) and kept on its disk between sessions, so only the first session on an
environment pays for the pull. `container.start` pulls, and the bootstrap timeout counts
it. If a Coder template prunes Docker images on a schedule, the warm-image
check of §12.5 is read with that counted.

#### Deferred to the last phase (7): the `host` execution mode

**Decided (Alex, 2026-11-06): the `host` mode is for Coder only, with one session per
workspace (§15 row 20).** The agent CLI runs on the workspace's machine. The services that can
run in Docker (`mitmdump`, the callback proxy and the others) run in containers, with
their ports published on the machine, so that the runner and the agent reach them. The reason:
a full development machine with no container around the agent, for example to run `docker
compose up` as a developer would. The workspace is the unit of isolation, so the per-session OS
user and the airtight scrub of §7.2, written for `manual`, are not needed for it: `fresh`
deletes the workspace, and `reuse` keeps it for the next session of the same runner, as in
container mode. The `host` mode is not planned for `manual`. The text below predates this
decision; task 20 rewrites it for Coder.

The axis is **where the agent CLI runs**: in the session container (`container`, v1) or on
the environment's host (`host`). In `host` mode the services stay in containers and the CLI
runs on the machine. It is what a customer needs when the agent has to run the machine's
own toolchain *as installed* and mounts are not enough. Its cost, written out:

- the agent CLI installed and supervised on the host;
- CA trust in the three stores on the host (Node, the OpenSSL bundle, NSS through
  `certutil`), with the CA **generated by the host runner and passed into the MITM
  container**, the reverse of today, where the container makes its own;
- the `NODE_OPTIONS --require http2-logger.js` instrumentation in the host CLI process;
- host-side ttyd (both instances), openvscode-server and the watcher, so the tunnel has
  something to relay;
- a redaction path for the host pane log;
- a throwaway OS user per session (`aixle-s<session_id>`, §7.2) for isolation and scrub.

It is **a second execution path through everything a session does, not a configuration
switch**: every `BaseRuntime` primitive, scrub, the tunnel and usage accounting get a second
implementation and a second test matrix, the same reasoning as the hosted debt in §12.3.
`config.execution_mode` (`container` | `host`, §2.7) arrives with it; until then there is no
setting. What would bring it forward: a customer whose toolchain cannot be mounted or baked
into an image `FROM` ours.

**Dropped: pure `native` mode** (everything on the host, no Docker), revision 3's Coder
opt-in. The `host` mode dominates it: the same host access, with usage accounting still
working for every runtime because `mitmdump` stays in a container. Reinstate it only if a
customer turns up with no Docker daemon.

#### The CLI-source question, deferred with the `host` mode

In container mode the CLI comes from the image, pinned by `config/agent_runtimes.json`, so
the question does not arise. That is one of the reasons for deferring the `host` mode. When
it arrives:

- `config.host.cli_source: managed | template`, default **`managed`**: kits built on the
  `config/agent_runtimes.json` pins, because a silent version drift is the failure that is
  hardest to debug;
- `template` as an opt-in, with a check-in report of the version found against the pin;
- **prototype first** extracting the CLI from the stock image onto the host
  (`docker create` + `docker cp`), the option that reuses the existing pins with no second
  publish lane.

The toolcache session kits and prototype P2 (§16) move to phase 7 with it.

### 6.9 Where the session-side pieces run on each type (decided, task #205)

**Status: decided (Alex, 2026-11-05).** Alex accepted the shared rule of §6.9.1 and the
recommendations of §6.9.2 to §6.9.5, with the agent's completion as on hosted (§6.9.4) and the
cases of §6.9.7. The sections they change carry a short "Decided (§6.9)" note; the full rewrite
of each is left to the task that implements it (§6.9.6). The research behind it, a section per
comparable service with links to the documents and the source read, is in
[`prior-art.md`](prior-art.md); "prior art §N" below points into it.

**Why this section exists.** §6.8 puts `aixle-runner --mode session` in the agent container,
as PID 1, on every type, running the session ops (§6.4), the callback proxy (§6.6) and the
live log (§6.5), and later the tunnel's relay (§15 task 16). Task 6b (#204) builds `manual`
without it, by decision of 2026-11-05: the host runner runs the session ops itself, through
the Docker Engine API, against the session's container, as `ContainerRuntime::DockerRuntime`
does in development, and the agent container runs the stock image with its own entrypoint,
with nothing of the runner in it. That left four pieces without a settled place: the session
ops on `kubernetes`, the callback proxy, the live log with the session's end, and the
tunnel. The subsections below take them one at a time, with the options, what each costs and
a recommendation, and §6.9.6 lists what the recommendations change elsewhere.

#### 6.9.1 The rule the decisions share

**The environment's owner does everything that needs the environment credential, from
outside the agent container. The agent container stays the stock image, unchanged.**

- **The owner** is the runner process that holds the environment credential and the
  journal, and the only one that talks to the gateway. On `manual` and `coder` it is the host
  runner (`aixle-runner --mode host`), running on the machine or the workspace next to the
  Docker daemon. On `kubernetes` it is the controller (`aixle-runner --mode controller`),
  running in the customer's cluster next to the session pods (§6.9.2). Being the only process
  that talks to the gateway, it is the environment's only poller on every type, which extends
  #204's answer for `manual` to the §16 question "what counts as one poller". The rest of this
  section says "the owner" for whichever of the two it is on a type.
- **The agent container** gets nothing of the runner: no binary, no socket, no token and
  nothing of the state directory, on every type. This is #204's rule for `manual`, applied to
  the other types.
- **One helper container per session,** the proxy sidecar of §6.9.3, shares the agent's
  network namespace and holds no environment credential (on `kubernetes` it holds a
  per-session proxy key, §6.9.7). It is the only part of the runner that the agent can reach
  over the network.

The prior art supports this shape. Services that run an image the user chose, unmodified,
execute from outside through the runtime's API (GitHub Actions, ARC, GitLab, Jenkins; prior
art §1–§4, §8). The services that protect a runner credential keep it away from the job in
another container or process (Argo's `wait` sidecar, Buildkite's `agent` container, the GitHub
and GitLab runners on the host; prior art §17, pattern 5), and many run their privileged
helpers in another container that shares the job's network (prior art §17, pattern 4). The
counterexamples are the systems whose job or sandbox belongs to the user: GitHub's checkout
and cache actions run in the job container, and Coder puts its agent token in the workspace.
Our agent container is not trusted with the environment credential, so we follow the first
group. The services that put their own
binary into the job's container do it because they need a contract inside it, and our image
already has one: `docker/base/entrypoint.sh` starts the services, the tmux session and the
redacted pane sink, exactly as in a hosted pod.

Summary of the decisions:

| Piece | `manual` and `coder` | `kubernetes` |
| --- | --- | --- |
| Session ops (§6.4) | The host runner, through the Docker Engine API (#204) | The controller, through the Kubernetes API (§6.9.2) |
| Callback proxy (§6.6) | A proxy sidecar in the agent's network namespace, on `127.0.0.1`, relaying to the host runner over a Unix socket mounted into the sidecar only (§6.9.3) | A proxy sidecar in the pod, on `127.0.0.1`, relaying to the controller with a per-session proxy key mounted into the sidecar only |
| Live log (§6.5) and the session's end | ~~The container's own log, followed by the host runner~~ Not built (2026-11-11): `exec` and `capture-pane`, as hosted; a dead container read from its status (§6.9.4) | The pod log API, followed by the controller; a dead container read from the pod watch |
| Tunnel (§15 task 16) | The host runner relays over one outbound WebSocket and reaches the ports through the proxy sidecar (§6.9.5) | The controller relays and dials the pod's IP |

#### 6.9.2 Question 1: the session ops on `kubernetes` (task 19)

**The options.**

- **A. An in-pod session runner, as §6.8 has it.** An init container copies `aixle-runner`
  into an `emptyDir`; the agent container runs `aixle-runner --mode session` as PID 1, which
  supervises `entrypoint.sh`, checks in with the bootstrap token from a mounted Secret, holds
  the environment credential and the journal, polls the gateway and runs the ops as local
  processes. This is Tekton's, Argo's and CircleCI's (since 3.1) shape (prior art §7, §9, §10),
  and Gitpod's `supervisor` (prior art §15).
- **A′. A split pod.** As A, but the credential and the journal sit in a sidecar container of
  the pod, and an injected executor in the agent container takes the ops over a Unix socket on
  a shared `emptyDir`. This is Buildkite's `agent-stack-k8s` shape (prior art §6).
- **B. The controller runs them through the Kubernetes API,** as `ContainerRuntime::KubernetesRuntime`
  does for hosted pods today: `exec` over the API server's exec endpoint, `write_file` and
  `read_file` as `tar` over exec, `status` from the pod watch it already keeps, `logs` from the
  pod log API. The controller also does the environment's check-in, with the bootstrap token
  it receives in the `provision` op, so it holds the environment credential and the journal.
  This is the shape of ARC's container hooks, GitLab's Kubernetes executor and Jenkins' Kubernetes
  plugin (prior art §2, §4, §8), and the same model #204 builds on `manual` with the Docker API.

**Against §1.2 (outbound only, no kubeconfig held by the platform).** All three hold. In each,
the only process that talks to the gateway runs in the customer's namespace and connects out,
and the platform holds no Kubernetes credential. B gives the controller `pods/exec` in its
namespace, which §9.6 does not grant today; that is the customer's controller holding a right
in the customer's namespace, not the platform reaching in.

**Against §6.7 (at-most-once, and "did my exec run?").**

- **A and A′** are the strongest: an op is a local fork next to the journal, so the outcome is
  unknown only when the pod itself dies, and then the session is lost anyway.
- **B keeps at-most-once, with a bounded form of the "did my exec run?" case.** The controller
  journals an op before it starts the exec, as the host runner does (§6.8, "What v1 has so far").
  If the exec stream between the controller and the API server breaks (a controller restart,
  an API server restart, a dropped connection), the outcome is unknown, and the op is answered
  `interrupted`, never run twice. What §6.7 set out to close does stay closed: the exec no
  longer crosses the link between the platform and the customer's network, as hosted exec does
  today, so a lost gateway connection does not touch it. What stays open is an in-cluster stream
  breaking mid-op. CircleCI left the exec API over this and over API-server load, and GitLab
  reads output from a file in the pod to survive it (prior art §4, §7).
  `interrupted` means "the outcome is unknown", not "it did not run": neither Kubernetes nor
  Docker kills the process an exec started when the client goes away, so the command may keep
  running in the pod, for example a half-done `tar -xf` of a `write_file`. Nothing re-runs the
  op, so at-most-once holds; the platform's handling of `interrupted` assumes the op may still
  be running. That case is rare and accepted (§6.9.7); a durable-task wrapper as Jenkins has
  (prior art §8, pattern 7) is an option for task 19 if it turns out not to be.
  A session sends tens of ops (a few batched context writes, the tmux launch, the final
  collection), and under §6.9.4 neither the live log nor the status uses exec.

**What each costs.**

| | A. In-pod session runner | A′. Split pod | B. Controller through the API |
| --- | --- | --- | --- |
| Environment credential | **In the agent container**, in the session runner's memory and state, readable by an agent that runs as the same user or has `sudo`. The agent can then poll ops, post results and logs, and spend the refresh token, which revokes the family on reuse | In a sidecar; the agent cannot read it | In the controller; nothing in the pod |
| Something of the runner in the agent container | Binary as PID 1, its state | Executor binary, a socket | Nothing |
| New moving parts | Init container, PID 1 duties (signals, reaping), the bootstrap Secret, the runner image in every pod | All of A's, a sidecar and an IPC protocol between the two | `pods/exec`, a stateful controller (below) |
| Runner code | A third implementation of the session ops, next to #204's Docker one: local processes | The same, split over a socket | A second backend behind #204's session-op handlers: `client-go` exec, `tar` over exec (as `kubectl cp`), the pod watch and the log API |
| Controller restart | No effect on running ops | No effect | In-flight ops answered `interrupted`, and the command may still run; the agent keeps running |
| RBAC (§9.6) | Unchanged | Unchanged | Adds `pods/exec` (`create`); a dedicated namespace becomes a requirement, as CircleCI assumes (prior art §7) |
| API server load | None for ops | None | One exec per op; the live log is one log stream per session |
| Hosted step B (§13) | Hosted pods change their PID 1 | Hosted pods gain a sidecar and an executor | The same controller can run in our cluster; the hosted pod spec stays as it is |

**The stateful controller under B.** The controller already needs somewhere to keep its own
rotating credential pair across restarts, which §9.6 does not say today. Under B it also keeps
an environment credential per running pod and the journal, whose pending results can be as
large as an op's output. A `Secret` is capped at 1 MiB, so the state is a small
`PersistentVolumeClaim` mounted into the controller, with `replicas: 1` and the `Recreate`
strategy. Those two do not fence a second live controller: a second replica started by
mistake, or a hung controller still alive after Kubernetes started a new one, would poll the
same environments. So the controller also takes leader election with a Kubernetes `Lease`,
and carries a controller generation that the gateway checks, so a stale controller's calls are
refused. This gives the exclusivity the host runner's `flock` gives (§6.8), across nodes; task
19 defines the takeover order (§6.9.7).

**How the controller polls under B.** The simplest form keeps §9.2 unchanged: one environment
credential per pod, from the check-in the controller does itself, and one long-poll per
running environment, exactly like N `manual` machines. Multiplexing every environment's ops
into the controller's own poll would save gateway threads (§16, "Concurrent long-polls"), but
widens the controller credential and changes the gateway's authorisation, so it is left to
task 19 as an optimisation.

**Decision (Alex, 2026-11-05): B.** It is the only option that keeps the environment credential
out of the pod without adding a container and an IPC protocol, it puts nothing of ours into
the agent container on any type, and it gives the runner two backends of one model (the
Docker API on a host, the Kubernetes API in a cluster) instead of one backend and a second
model. Its weak spot, an exec stream that breaks in the cluster, is bounded to `interrupted`
by the journal, and our op volume is low.

**What would change the decision.** If task 19's validation shows ops answered
`interrupted` often enough to fail sessions, move to A′: the ops and the protocol stay the
same, only who runs them changes. A is not recommended in any case, because it puts the
environment credential where the agent can read it.

#### 6.9.3 Question 2: the callback proxy (§6.6, task 8)

**What the proxy can do, and what must not leak.** The proxy forwards allow-listed routes
(MCP, credential sync and refresh, git and cloud credentials, assets, OTLP) for the session
currently assigned to the environment, adding the environment credential. Anyone who can reach
the proxy can therefore do what the agent can already do with its own session keys, and no
more. So the question is not whether the agent can reach the proxy (it must), but **where the
environment credential sits** and **who else can reach the proxy**.

**How the agent's traffic is routed today.** `docker/base/logger/start-mitm.sh` exports
`HTTP_PROXY` and `HTTPS_PROXY` pointing at `mitmdump`, and `NO_PROXY=localhost,127.0.0.1,::1`.
A proxy on `127.0.0.1` is reached directly by every client. A proxy on any other address is
sent through `mitmdump` by the clients that honour `HTTP_PROXY`, as hosted callbacks to
`http://web:<port>` already are; `mitm_logger.py` logs only `MITM_TRACKED_DOMAINS` and redacts
credential headers, so that is a detour, not a leak. Adding an address to `NO_PROXY` is a
change to `start-mitm.sh`, which overwrites the variable.

**The options.**

- **a. A proxy sidecar in the agent's network namespace.** A second container per session,
  running `aixle-runner --mode proxy`, holding no environment credential.
  - On `manual` and `coder` it relays to the host runner over a Unix socket that the host runner
    bind-mounts into the sidecar only. The host runner adds the environment credential and
    serves only `/runner/v1/proxy/*` for the environment's current session on that socket: never
    `ops`, results, `token` or `check-in`.
  - On `kubernetes` it is a sidecar container of the pod (a native sidecar, which requires
    Kubernetes 1.29 or later, §6.9.7). It relays to the controller over the pod network, over
    TLS, authenticated by a per-session proxy key that the controller puts in a Secret mounted
    into the sidecar container only; the controller maps the key to the environment and its
    current session and adds the environment credential. The key opens the proxy routes for
    that one session and nothing else, and is revoked when the session ends (§6.9.7).
  - The agent reaches it on `127.0.0.1:<port>`, so `NO_PROXY` and the MITM stack need no change.
  - This is the helper-container shape of GitLab, Argo, Buildkite and CircleCI (prior art §17,
    pattern 4).
- **b. A listener of the host runner or the controller.**
  - On `manual` and `coder` the host runner listens on the gateway address of a per-environment
    Docker network (`aixle-net-<key>`), so only that environment's containers and the machine's
    own processes can reach it.
  - On `kubernetes` the controller listens behind a cluster Service, and identifies the pod by a
    per-session key embedded in the rewritten URL or by its source IP.
  - The agent reaches it on a non-loopback address: through `mitmdump`, or with a `NO_PROXY`
    addition in the image.
- **c. A process inside the agent container** (§6.6 as written). It needs the runner's binary in
  the agent container, and either the environment credential there or a socket to the host
  runner there. Both contradict #204's rule for `manual` and the rule of §6.9.1.

**What each costs.**

| | a. Proxy sidecar | b. Owner's listener | c. In the agent container |
| --- | --- | --- | --- |
| Agent reaches it on | `127.0.0.1:<port>` | Network gateway IP or Service DNS name | `127.0.0.1:<port>` |
| `NO_PROXY` and MITM | Unchanged | Through `mitmdump`, or an image change to `start-mitm.sh` | Unchanged |
| Environment credential | In the owner; the sidecar holds no environment credential, only a socket (`manual`, `coder`) or a per-session proxy key that only opens the proxy routes for that session (`kubernetes`) | In the owner | In the container, or a socket there |
| Who else can reach the proxy | Nobody outside the agent's network namespace | The machine's processes; on `kubernetes`, the cluster unless a NetworkPolicy narrows it | Nobody outside the container |
| Depends on the host's setup | On the filesystem, not the network: the Docker daemon must resolve the host runner's paths for the bind mounts (socket and binary). A remote `DOCKER_HOST`, or a Coder workspace that uses its server's Docker, breaks it; the first session then fails with `docker_files_not_visible`, which names the cause (decision 4, §6.9.7) | On the network: a host firewall that drops traffic from containers to the host (ufw's default), rootless Docker, or Docker inside a Coder workspace container break or change the path to the gateway address | No |
| Moving parts | A second container per session, created, stopped and scrubbed with the agent's by label (§7.2) | A Docker network per environment; a Service and a listener in the controller | The binary in the agent container |
| Survives an owner restart | Calls fail until the owner is back, and the agent retries (§6.7) | Same | Same, if it relays through the owner |

**`network: host` (§6.8, "Container options").** The agent then shares the machine's network
namespace, so there is no namespace for a sidecar to share. The host runner itself is in that
namespace already, so with `network: host` it listens on `127.0.0.1:<port>` of the machine,
with a port per environment, and no sidecar is created. Every process on the machine can then
reach the proxy, with the agent's own power and no more. This is part of what `network: host`
already gives up, and the form's wording for it should say so.

**Decision (Alex, 2026-11-05): a, the proxy sidecar, on every type.** It keeps the agent on
`127.0.0.1`, with no image change and no change to how the MITM stack routes traffic, keeps the
environment credential with the owner, and does not depend on firewall rules on machines we do
not control. It does need a Docker daemon that sees the host runner's files; the session runner
of §6.8 needed the same. There is no start check for it: the first session's error names the
cause (decision 4, §6.9.7). Its cost is a
second container per session, which the label scheme of §6.8 and the scrub of §7.2 already
cover.

The details task 8 fills in:

- **Who owns the network namespace.** The sidecar is created first and the agent container
  joins it (`NetworkMode: container:<sidecar>`), the way a Kubernetes pod's pause container
  holds the pod's namespace. The proxy then outlives the agent's last call, `finish_session`
  included, and the `network` option of §6.8 applies to the sidecar's creation. Unlike a pause
  container, the sidecar runs code: if it exits, Docker removes the namespace's network and
  never reattaches the agent, so the agent loses its network. The host runner then fails the
  session; there is no pause container (§6.9.7).
- **The sidecar's image on `manual` and `coder`.** The agent image, already pulled by
  `container.start`, with the host runner's own binary bind-mounted read-only and set as the entrypoint.
  No second image to pull, and the proxy is the host runner's version by construction. On
  `kubernetes` it is the runner image the chart already names (§9.6).
- **The port** is the platform's setting, outside the image's ports (7681, 7682, 4040, 4041,
  8443, 8888). `RunnerRuntime#callback_url` answers it (§6.6), and `container.start` sends it,
  so the host runner has no port of its own.

**As built (§15 task 8b), on `manual`.**

- **The port is 7690** by default. With `network: host` the session's port on the machine is
  `20000 + session id mod 10000` by default (`Runners::Proxy.host_port`). All three numbers are
  `Settings.runners.proxy` (`port`, `host_port_base`, `host_port_span`), which
  `RUNNER_PROXY_PORT`, `RUNNER_PROXY_HOST_PORT_BASE` and `RUNNER_PROXY_HOST_PORT_SPAN` override
  (Alex, 2026-11-10). `container.start`'s payload always carries the session's port as
  `proxy_port`, the sidecar's or the machine's, and the host runner listens where it says, so the
  Rails app is the one place to configure it. It is a port per session, not per environment: the strategy builds
  the container's environment before the session takes a machine (`create_container`), so the
  address cannot depend on the machine. Two `network: host` sessions on one machine whose ids
  collide on it are rare, and the second one fails with `proxy_port_in_use`.
- **The sidecar** is `aixle-<key>-<session>-proxy`, labelled with the environment, the session
  and `aixle.com/role=proxy`, so no session op takes it for the session container. It runs as
  `65534:65534`, with every capability dropped, `no-new-privileges`, a read-only root
  filesystem and no environment of the session's. Its mounts are the host runner's binary
  (`/aixle-runner`) and the session's socket directory (`<state dir>/proxy/<session>`, at
  `/run/aixle-proxy`), both read-only. The directory, not the socket, is mounted, so that a
  restarted host runner re-creates the socket in it and a running sidecar reaches the new one
  (`Environment.Resume`). The host runner keeps the directory itself across a restart and
  replaces only `relay.sock`: a bind mount follows the directory's inode, so a new directory at
  the same path would not reach the sidecar. When a relay, or a `network: host` listener, can't
  be served again after a restart, the host runner stops the session's agent container, so the
  session fails through the dead-container path as with a sidecar that exits; nothing retries
  (Fix CR round 1). When the host runner can't list the environment's containers at its start,
  it doesn't poll: it exits with a plain failure, and the service manager restarts it
  (`Restart=always`), which retries `Environment.Resume` until Docker answers (Fix CR round 4).
  The state directory is `0700`, so only the runner's user reaches the
  socket on the machine. The host runner narrows a wider state directory to `0700` when it
  starts, and exits with `ExitStop`, naming the directory and its mode, when it can't
  (Fix CR round 5).
- **The relay** (`proxy.Relay`) serves `/runner/v1/proxy/*` only, and answers anything else
  `404 not_proxied`, a path with an empty, `.` or `..` segment after percent-decoding, or an
  encoded `/` or a `\`, included. It drops the agent's `Authorization`, its `X-Aixle-Runner-*`
  headers, the hop-by-hop ones and the ones `Connection` names, adds the environment's access
  token, refreshes once on an `invalid_token`, and streams the answer back with a flush per
  chunk. The sidecar (`aixle-runner --mode proxy`) is a reverse proxy to the socket that adds no
  header. Both read a request's body within 30 s (`408 body_timeout`); the answer has no time
  limit, and there is no limit on concurrent calls.
- **The lifecycle.** `container.start` opens the relay, then starts the sidecar, then the agent
  in its namespace; a failure removes what was started. `container.stop` removes the agent's
  container, then the sidecar, and closes the relay. `env.scrub` and `env.reset` remove the
  sidecars with every container of the environment, and close every relay.
- **A sidecar that exits** (decision 10): the host runner watches each sidecar
  (`ContainerWait`). When one it did not remove itself stops, it logs the exit code and the
  last 50 lines of the sidecar's log, and stops the agent's container, which stays, so the
  session fails through the existing dead-container path with its generic message. When
  Docker's wait stream breaks while the sidecar runs, the watcher inspects the sidecar: one that
  has stopped or is gone is handled as an exit, and one that runs is waited for again, after a
  pause that doubles from 1 s up to 30 s. Only the sidecar's removal by the host runner, or the
  host runner stopping, ends the watch.
- **A Docker daemon that does not see the host runner's files** (decision 4): the daemon refuses
  the sidecar's bind mount with "bind source path does not exist", and `container.start` answers
  `docker_files_not_visible`, whose message names the paths and the cause (a remote
  `DOCKER_HOST`, or a daemon that runs elsewhere). The session fails with it. There is no start
  check. The dev `local` adapter keeps its binary and state in `RUNNER_LOCAL_DIR`, a directory
  of the machine mounted at the same path, for this reason, and so does the published image
  when it is run as a host runner (§14.4).
- **A daemon on arm64** (task 12b, Alex, 2026-11-12): the agent images are OCI indexes with
  `linux/amd64` only (native arm64 images are task #226). The pull and the creation of the
  agent container, of the proxy sidecar (the same image) and of the scrub container ask for
  `linux/amd64`, so an arm64 daemon runs them under emulation: built into OrbStack and Docker
  Desktop, `binfmt` on ARM Linux. Without emulation the container fails to start with the
  daemon's own words. The sidecar's entrypoint is the runner's native binary, which the kernel
  runs natively.

#### 6.9.4 Question 3: the live log and how a session ends (§6.5, task 8)

> **Superseded for the live log (Alex, 2026-11-11, task 8c).** The decision below to ship the
> container's own log as `POST /runner/v1/sessions/:id/log` chunks is **not built**. A runner
> session's terminal is read as a hosted one's: through `exec` and `tmux capture-pane`, which on
> a runner is one `exec` op, as it has been since 8a. `Sessions::LiveLogReader`,
> `get_session_log`, the session monitor's snapshot (`Sessions::Snapshot::ExecSource`) and
> `AuthErrorDetector` stay as they are, and `NoOutput` is fed by that `exec` snapshot. The live
> view on a runner session's page comes with the interactive tunnel (§15 task 16), so the
> `local` log driver, the follow of the container's log, the chunk endpoint and
> `session_live_log_chunks` are not built, and the rotation limitation and the rendering
> question below do not arise. What stays of this section is how a session ends (below), which
> never depended on the chunks.

**What the image already does.** The `pipe-pane` sink in `entrypoint.sh` writes the agent pane,
after `redact-stream.py`, to two places: `/tmp/terminal_output.log`, collected at cleanup, and
`/proc/1/fd/1`, the container's own stdout. So the container's log already carries the
redacted pane output, as the hosted pod's log does today.

**The options.**

- **The container's own log.** The host runner follows it through the Docker API (what
  `docker logs -f` does), and the controller through the pod log API (`follow=true`). This is
  how Tekton, Argo and CircleCI's logging sidecar read output (prior art §7, §9, §10).
- **A tail of the file from outside.** The owner runs `tail -c +<offset> -F
  /tmp/terminal_output.log` as a long-lived exec and resumes it from the last offset after a
  break. This is GitLab's `read-logs` (prior art §4).
- **A tail inside the container.** It needs a process of ours in the agent container, which
  §6.9.1 rules out.

**What each costs.**

| | Container log | Tail of the file by exec | Tail inside |
| --- | --- | --- | --- |
| Exec per session | None | One long-lived exec | None |
| Anything needed in the container | Nothing | `tail` (in the stock image) | Our binary |
| Offsets for the gateway's de-duplication (§6.7) | Bytes of stdout since the container started, counted by the owner | Byte offsets of the file itself | Byte offsets of the file |
| After an owner restart | Re-read from the start and skip to the last acknowledged offset. Docker's `local` driver (with its size cap) and the kubelet (10 MiB by default) rotate the log, so after a long session the start may be gone and a part of the live log is skipped. Accepted as a known limitation (§6.9.7); the final log is not affected | Resume from the offset | Not affected |
| What it depends on | The log driver on `manual` and `coder`; the kubelet's rotation on `kubernetes` | A long exec through the API server on `kubernetes` | — |

**Decision (Alex, 2026-11-05): the container's own log**, with stdout only, followed by the
host runner and the controller and shipped as `POST /runner/v1/sessions/:id/log` chunks with
the owner's byte count as the offset. It needs no exec and nothing in the container, and the
same reader works for every session on a type. Two details make it dependable:

- **The log driver is set per container on `manual` and `coder`.** The host runner creates the
  agent container with Docker's `local` log driver and a size cap, so following the log does not
  depend on the daemon's default driver, which a customer may have set to one Docker cannot read
  back.
- **The final log does not change.** `before_cleanup` still collects `/tmp/terminal_output.log`
  through `read_file` (§6.5), so the stored log is the same file it is on hosted. The live
  chunks only feed `LiveLogReader` and the session monitor's snapshot.

The chunks are the raw pane stream, ANSI sequences included, while `LiveLogReader` returns
`capture-pane`'s rendered text today. How a runner session's live text is rendered for the
`get_session_log` tool and `AuthErrorDetector` is part of task 8 whichever source is chosen.

**How a runner session ends: exactly as a hosted one (decided, Alex, 2026-11-05).** There is
no agent-process contract and no event derived from the CLI; `agent_started` and
`agent_exited` are not built. The CLI runs in the image's persistent tmux shell, so the
container's state says nothing about the CLI itself, and hosted sessions do not need it to:

- **The session ends when the agent calls `finish_session`** (or `fail_session`), which goes
  through the proxy sidecar (§6.9.3) to the platform, as on hosted.
- **A silent session is reaped by `Sessions::Checks::NoOutput`** after 30 minutes without
  output (`NO_OUTPUT_THRESHOLD`), fed by the `exec` snapshot of the session monitor
  (`Sessions::Snapshot::ExecSource`, 2026-11-11), on its pass, every minute. For Kiro, output means a change on its rendered screen: bytes that only
  repaint the same screen do not count (task #208, `SCREEN_RULE_RUNTIMES`). A CLI that exited back to the
  shell falls silent, and this is what catches it, as on hosted.
- **A dead container fails the session with `DeadContainerScan` semantics,** from the
  container's status as the owner reads it (`wait` and the event stream on Docker, the pod
  watch on Kubernetes).
- **`start_container` waits for nothing more** than the container running, as
  `ContainerRuntime::DockerRuntime#start_container` does today: nothing inside reports ready.
- `disk_low` comes from the host runner's own check of the daemon's disk (§17.2); on
  Kubernetes the kubelet's eviction shows up as a dead container.

#### 6.9.5 Question 4: the tunnel (task 16)

**Why the owner connects to the ports, and not the other way round.** ttyd, the IDE and the
watcher are servers: they wait for connections on their ports and never connect out. The
browser is on the internet, and the platform has no inbound path into the customer's network
(§1.2, §9.5). So the connection has to start from the customer's side: the owner keeps an
outbound WebSocket to the gateway, the browser's connection arrives over it, and the owner
opens the connection to the port for it.

**The options.**

- **The owner relays.** The host runner or the controller keeps one outbound WebSocket to the
  gateway's tunnel endpoint and opens a stream per browser connection to one of the session's
  ports: the writable ttyd (7681), the read-only ttyd (7682), the watcher (4040) and its upload
  port (4041), and the IDE (8443). This is the shape of Coder's agent and Daytona's proxy
  (prior art §13, §14): interactive traffic arrives through a connection the environment opened.
- **A relay inside the container.** Our binary in the agent container, which §6.9.1 rules out.
- **An inbound session server,** as GitLab Runner and CircleCI's SSH reruns have it (prior art
  §5, §7). It needs an inbound path to the customer, which §1.2 and §9.5 rule out.

**Decision (Alex, 2026-11-05): the owner relays.**

- **How it reaches the ports.** On `manual` and `coder` the host runner reaches them through the
  proxy sidecar, which is in the agent's network namespace and dials `127.0.0.1:<port>`, over
  the same Unix socket as §6.9.3. That works on every Docker setup the start check of §6.9.7
  accepts, rootless Docker included, where a container's IP is not reachable from the
  machine's own namespace. With `network: host` there is no sidecar, and the host runner dials
  the ports on the machine's `127.0.0.1` itself. On `kubernetes` the controller dials the
  pod's IP. The writable ttyd (7681) has no password of its own, so a NetworkPolicy that lets
  the controller, and only the controller, reach those ports is required, not optional, and
  the Kubernetes validation checks that it is enforced (§6.9.7).
- **Who may open what stays on the platform.** The gateway authenticates the browser exactly as
  Traefik with `ws_auth` does for hosted pods (the session owner to 7681 and 4041, everyone else
  to 7682), and the relay accepts only the five ports above for the environment's current
  session.
- **`network: host`.** The image's ports then bind on the machine, so two sessions on one
  machine would collide. `entrypoint.sh` and the watcher take every port from the environment
  (`TTYD_PORT`, `VIEW_PORT`, `WATCHER_PORT`, `UPLOAD_PORT`, `VSCODE_PORT`, `MITM_PROXY_PORT`), so
  the host runner assigns free ports per session and the relay uses them.

This is still "a relay of ports that already exist inside the container" (§6.8), with the relay
moved from the container to its owner.

**What task 16 defines for the relay protocol.** One WebSocket carries several streams with
very different traffic (a terminal, the IDE, uploads), so task 16 specifies: stream ids with
open, close and reset frames, and half-close; an independent flow-control window and a bounded
buffer per stream, so one stalled or busy stream cannot block the others; the maximum frame
size and the cap on concurrent streams; heartbeat, reconnect and what happens to open streams
on a reconnect; cleanup when the browser disconnects; and revocation, closing every stream at
once when the environment's current session changes or the viewer's authorization does. The
gateway stays the browser's authorization point, and each open request names the current
session and one of the five ports (§15 row 16).

#### 6.9.6 What follows for the rest of the design

These sections change with the decisions. Each carries a short "Decided (§6.9)" note now. The
full rewrite of each is left to the task that implements it: task 8 (the host runner's
session-side pieces on `manual`), 16 (the tunnel), 17 (Coder), 19 (Kubernetes) and 20 (the
`host` mode on Coder). Until then, where a section's own text and its note disagree, the note
and this section win.

- **§1.1, the `aixle-runner` term.** The modes become `host`, `controller` and `proxy` (the
  sidecar of §6.9.3). `session` mode is not built.
- **§1.1, the "Execution mode" term.** `container` mode has the image's `entrypoint.sh` as PID
  1, not `aixle-runner --mode session`. The `host` mode is for Coder only.
- **§1.2, reasons 2 and 3.**
  - Reason 2 (one implementation of exec, files and logs) holds on the platform side: one
    `RunnerRuntime` and one protocol, with no exec over the Coder API or SSH. In the runner,
    the session ops get two backends of the same model, the Docker Engine API (`manual`,
    `coder`) and the Kubernetes API (`kubernetes`), behind the same op handlers and journal.
  - Reason 3 (a dropped connection must not kill the agent) holds with a different owner: the
    agent's process tree belongs to the container runtime on the customer's side (the Docker
    daemon, the kubelet), not to `aixle-runner` and not to a request from the platform.
- **§2.6, Coder.** v1 supports only Coder workspaces that are virtual machines, with one
  session per workspace.
- **§5, the adapter table.**
  - `inject_bootstrap` on `kubernetes` mounts no bootstrap Secret and runs no init container:
    the controller gets the bootstrap token in the `provision` op.
  - `start_container` waits for nothing more than the container running, as
    `ContainerRuntime::DockerRuntime#start_container` does (§6.9.4). Nothing inside reports
    ready.
- **§6.2, the callers.** `check-in`: the host runner (`manual`, `coder`) and the controller for
  each of its pods (`kubernetes`). `ops`, results and `heartbeat`: the owner. Session logs: the
  owner. The proxy: the owner, relaying the proxy sidecar. No endpoint is called from the agent
  container. The events endpoint carries no `agent_started` or `agent_exited`.
- **§6.5.** ~~The live log is the container's log, followed by the owner (§6.9.4).~~ Superseded
  (2026-11-11): the terminal is read through `exec` and `capture-pane`, as on hosted.
- **§6.6.** The proxy is the sidecar of §6.9.3, not a listener of a session runner. It holds no
  environment credential; on `kubernetes` it holds a per-session proxy key. The per-endpoint
  session-key checks stay as they are.
- **§6.7.** The journal is the owner's on every type, the controller's on `kubernetes`. While
  disconnected, the owner buffers nothing (the log chunks are not built, 2026-11-11).
  There is no session summary from inside the container: the owner reads the container's
  status.
- **§6.8.** The decision paragraph and "Per type" no longer have `aixle-runner --mode session`
  as PID 1 on any type. On `kubernetes`, session pods run the stock image with the proxy sidecar
  and no init container. The callback URLs are rewritten to the proxy sidecar, not to a session
  runner's proxy. Container mode on Coder runs one session per workspace, and the `host` mode is
  for Coder only, with no per-session OS user.
- **§7.1.** On `coder`, `reuse` keeps the workspace warm and `fresh` gives each session a new
  workspace, in both execution modes.
- **§9.2, tokens.** On `kubernetes` the bootstrap token travels in the `provision` op to the
  controller, which does the check-in itself; no bootstrap Secret is mounted into a pod. The
  environment credential of a pod is held by the controller.
- **§9.6, the controller's footprint.**
  - The Role gains `pods/exec` (`create`), and leaves the "not granted" list.
  - `pods/log` (`get`) also serves the live log of running sessions, not only diagnosis.
  - `secrets` serve the per-session proxy key instead of the bootstrap Secret.
  - A dedicated namespace becomes a requirement of the chart, not a recommendation, because
    `pods/exec` reaches every pod in the namespace.
  - The chart gains the controller's `PersistentVolumeClaim`, `replicas: 1`, the `Recreate`
    strategy, a `Lease` for leader election, and `kubeVersion: ">=1.29.0"`.
  - The controller gains an in-cluster listener for the proxy relay, over TLS, with a Service.
  - The NetworkPolicy becomes required: ingress to the controller only from session pods, and
    ingress to the session pods' ports only from the controller.
  - Session pods get the proxy sidecar and the proxy-key Secret mounted into it only, instead of
    the init container and the bootstrap Secret.
- **§13, step B.** Hosted sessions are run by a controller we operate in our cluster, which
  executes the session ops through the Kubernetes API as on a customer's cluster. Hosted pods
  keep their pod spec; they gain the proxy sidecar only if hosted moves its callbacks behind the
  proxy, which step B does not need. `pods/exec` leaves the Rails application's ClusterRole for
  the controller's namespaced Role. The §12.3 exit condition stays as written:
  `KubernetesRuntime#exec` has no caller left in the session path.
- **§14.4, where the runner lands.** The proxy sidecar runs the host runner's own binary, so it
  is updated with it; there is no session runner. On `kubernetes` there is no init container:
  the sidecar's image is the runner image named in the `provision` op.
- **§15, rows 8, 16, 17, 19 and 20.**
  - Row 8: the host runner's `check-in`, heartbeat and log shipping from the container's log;
    the proxy sidecar with the host runner's socket relay; the URL rewrite to `127.0.0.1:<port>`;
    the start check that the Docker daemon sees the host runner's files.
  - Row 16: the relay in the host runner and the controller, through the proxy sidecar on
    `manual` and `coder`; per-session ports with `network: host`; the relay protocol of §6.9.5.
  - Row 17: container mode on Coder virtual machines, one session per workspace; the start check
    that refuses a workspace that is not a virtual machine.
  - Row 19: the controller's Kubernetes backend for the session ops, the check-in on behalf of
    its pods, the pod log follow, the proxy sidecar and its key, the state volume, leader
    election, the required NetworkPolicy, Kubernetes 1.29, the RBAC above.
  - Row 20: the `host` mode on Coder only.
- **§16.** The "Concurrent long-polls per environment" item is settled on every type: the owner
  is the environment's only poller, so the gateway's replace rule is per environment. New open
  items: the `interrupted` rate on `kubernetes` and the move to A′ it could trigger; multiplexing
  a controller's polls; rendering the live text of a runner session.
- **§17.1 and §17.2.** "The session runner buffers" becomes "the owner buffers", and `disk_low`
  is sent by the host runner, not by a session runner.

#### 6.9.7 Cases and decisions

Alex's rule for this design and the tasks that follow: **no complexity for rare, non-critical
cases.** Each case is weighed on two scales.

- **Harm:**
  - **H1** is security, data loss or double execution;
  - **H2** is a session that fails or hangs with no recovery;
  - **H3** is degraded with a workaround;
  - **H4** is cosmetic.
- **Likelihood:** often, sometimes or rare.
- **What is covered:** H1 always. H2 unless it is rare, and then with a clear error. H3 and H4
  are accepted as documented limitations unless the fix is trivial.

| Case | Harm | Likelihood | Decision |
| --- | --- | --- | --- |
| Two controllers run at once, for example a second replica started by mistake, or a hung one still alive after Kubernetes started a new one, so both poll for the same environments. | H1 | rare | Covered: leader election with a Kubernetes `Lease`, and a controller generation that the gateway checks (task 19). |
| The controller's inbound listener for the proxy relay, and its connections to the session pods' ports (ttyd 7681 has no password), are reachable from other pods. | H1 | — | Covered: TLS on the relay, and a NetworkPolicy that is required, not optional: ingress to the controller only from session pods, and ingress to the session pods' ports only from the controller. The Kubernetes validation checks that it is enforced (task 19). |
| Someone in the cluster reads a pod's Secret and calls the proxy as that session, with the agent's own rights. | H1 | rare | Covered minimally: one key per session, revoked when the session ends. Task 19 may identify the pod by its IP behind the NetworkPolicy instead. |
| The Docker daemon can't see the host runner's files, so the sidecar's socket mount fails: a remote `DOCKER_HOST`, or a Coder workspace that uses its server's Docker. | H2 | sometimes | Not supported. **Decision 4 (Alex, 2026-11-07):** no start check. Docker refuses a bind mount whose source path does not exist ("bind source path does not exist"), and 6b mounts through the Mounts API, so task 8b turns that refusal into a clear error when it starts the proxy sidecar. Operators learn of an unsupported setup from the first session's error, and the operator docs (task 12) state the limitation. |
| The proxy sidecar crashes during a session, and the agent loses its network. | H2 | rare | The session fails. No pause container (task 8). |
| ~~The host runner restarts during a long session after the container log has rotated, so a part of the live log is skipped.~~ | H3 | | Does not arise: the live log is not followed (2026-11-11, §6.5). The final log is collected from the file at cleanup. |
| The cluster runs Kubernetes older than 1.29, without native sidecars. | H3 | rare | Required: Kubernetes 1.29 or later (task 19). |
| The controller restarts during an exec on `kubernetes`: the op is answered `interrupted`, but the command keeps running in the pod. | H3 | rare | Accepted; a note for task 19. |

---

## 7. Lifecycle and reset

### 7.1 Fresh vs. reused, and what `reuse_policy` means per type

The agent container (or pod) is **fresh per session on every type**. `reuse_policy` decides
what survives around it, and that differs per type:

| Type | `reuse` | `fresh` |
| --- | --- | --- |
| `kubernetes` | Not offered | Always: a new pod per session. The image provides the warm state. |
| `coder` | Default. The workspace is kept: the pulled agent image, the `aixle-ws-<key>` volume with its repository clones, and any cache mounts stay warm. | A new workspace is created per session and destroyed after it, for hosted-like isolation with the cold start accepted. |
| `manual` | Default. The machine keeps the pulled images, the workspace volume and the cache volumes. Scrub after every session. | **Cannot mean a new machine.** It means the full wipe scope per session: a new container (always), a **Reset** of the workspace and cache volumes after every session instead of a scrub (§7.2), and, once host-side execution exists (phase 7), a new OS user. Pulled images stay; they are public, the same for every session, and every session pulls its image reference again before it starts. The form says: "Fresh on a manual runner wipes everything Aixle put on the machine after every session. It does not give you a new machine." |

**Decided (§6.9, Alex, 2026-11-06), `coder`.** v1 supports only Coder workspaces that are
virtual machines, and a workspace runs one session at a time; a second concurrent session gets
another workspace, up to the runner's limit. `reuse` and `fresh` mean the same in both
execution modes: in the `host` mode the workspace is the unit of isolation, so `fresh` deletes
it after the session and there is no per-session OS user (§6.8).

### 7.2 Setup, cleanup, scrub, reset, rebuild

**Decision: customer-defined pre/post session hooks are not in v1.** Customers prepare the
machine through what they already own (the Coder template, their configuration management
on a `manual` machine, an image `FROM` ours) and steer the rest through agent instructions
(skills, step prompts). The absence is deliberate. A hook runs customer code with a
session's credentials in scope, at a point where its failure semantics (fail the session,
retry, skip) and its place relative to scrub would need a design of their own. Revisit when a
customer shows a preparation step that neither the image or template nor the instructions
can express.

**Our own per-session preparation and cleanup is not deferrable.** Preparation is
`SessionContextService`, unchanged (§1.3). Cleanup is the levels below. Between them they
cover credentials, prompt and context, MCP config, outputs, the workspace, MITM state (the
per-session CA and its logs), the session's processes and its tmux server.

| Level | What it wipes | What it keeps | When |
| --- | --- | --- | --- |
| **Scrub** (`env.scrub`) | The session container, removed with `docker rm -f`, which takes the agent home, credential files, MCP config, prompt, context files, `/tmp`, the MITM CA and logs, the tmux server and every process with it; then a check by label that no container of the session is left. `/workspace/outputs` on the volume. Anything the strategy itself wrote to a writable cache or home mount. On `kubernetes`, deleting the pod is the scrub | Repository checkouts, package caches, pulled images | **After every session on a reusable environment, always**, before it returns to `idle`. Not optional: it is what makes reuse safe. A failed scrub leads to a rebuild where the type is `rebuildable`, and to a reset on `manual` |
| **Reset** (`env.reset`) | Scrub, plus the `aixle-ws-<key>` volume and every `aixle-cache-<key>-*` volume, including repository checkouts | Pulled images. On `manual`, everything on the machine that Aixle did not create | Not started by a user: there is no Reset action on a machine and no "Start from a clean workspace" for one run (removed, Alex 2026-11-13); **automatically after a failed session** on that environment; on `manual` with `reuse_policy: fresh`, after every session |
| **Rebuild** (adapter `reset level: :rebuild`, `coder` only) | Everything: the workspace is deleted and re-created from the template | Nothing | Manually; automatically when a scrub or reset fails, after `runners.max_consecutive_failures` (default 3) failed sessions in a row on one environment |

The repository bootstrap that `SessionContextService` already does (clone, or fetch and
repair) is what makes a kept checkout safe to reuse: an existing clone is fetched and reset
to the requested ref, not trusted as-is. `Coder::RepoBootstrap` exists for the same reason
on the MCP-tool path.

#### `manual`: an airtight scrub without a rebuild

On a machine we do not own, `rebuild` does not exist, so scrub and reset carry the whole
guarantee. The mechanism:

- **Scope by ownership, never by enumeration.** Scrub and reset act only on what Aixle
  created, selected by label and name: containers labelled `aixle.com/environment=<key>`,
  volumes `aixle-ws-<key>` and `aixle-cache-<key>-*`. They never walk the filesystem
  looking for what an agent might have written.
- **Container mode (v1): the session container is the unit.** Everything a session does
  happens inside it, so `docker rm -f` is the scrub, and the label check confirms it.
- **Decided (§6.9, Alex, 2026-11-06):** the `host` mode is for Coder only, where the
  workspace is the unit of isolation, and is not planned for `manual`. The per-session OS user
  below is therefore not needed and not built; the bullet is kept as the record of what
  `host` mode on `manual` would cost.
- **Host-side execution (`host` mode, phase 7): a throwaway OS user per session**,
  `aixle-s<session_id>`, with its own `$HOME`. The host-side CLI, ttyd, IDE and watcher
  run as that user, in a transient systemd scope with a private `/tmp`. Cleanup kills that
  user's process tree (`pkill -KILL -u`, repeated until `pgrep -u` is empty), stops the
  scope, and deletes the user and its home (`userdel -r`). The user can write only to its
  home, its private `/tmp` and the workspace we hand it, so deleting those three is
  complete without enumerating files. It also isolates credentials: the host runner keeps
  its own `aixle-runner` user and its `0600` credential file, which the session user cannot
  read. That is the host-side equivalent of the Unix-socket relay in container mode (§6.8).
- **Writable host mounts are outside the guarantee**, and the form says so. A writable
  `home_mount`, an `extra_mounts` entry with `:rw` or a host-path `cache_mounts` entry lets
  the agent write to the machine outside Aixle's labels. Scrub removes what the strategy
  wrote there, not what the agent wrote. The defaults are off or read-only, and on `manual`
  the form requires an explicit acknowledgement for each writable host mount.
- **Escalation stops at reset.** A failed scrub triggers a reset. A failed reset, or
  `runners.max_consecutive_failures` failed sessions in a row, takes the machine out of
  rotation (`failed`, §5.2) with the reason. The runner page asks the operator to look at
  the machine and press **Return to service**, which runs a reset first.

**As built (§15 task 6b), on `manual`.** The host runner implements both ops
(`PROTOCOL.md` §6.4); who decides between them, and when, is the allocator's job (task 11).

- **Ownership.** Containers are selected by the label `aixle.com/environment=<key>`. Volumes
  are selected by name (`aixle-ws-<key>`, `aixle-cache-<key>-*`) **and** by that label, which
  `container.start` puts on every volume it creates, so the cache volumes of an environment
  whose key starts with this one's are never matched. Nothing else is listed or removed. A
  name is not proof on its own: `container.start` refuses an existing volume with the
  environment's name and without its label (`volume_not_owned`), and `container.stop` refuses a
  container with the session's name and without both labels (`container_not_owned`).
- **`env.scrub`** removes every container of the environment with `docker rm -f` (with its
  anonymous volumes), checks by label that none is left, then empties `/workspace/outputs` on
  the workspace volume, if there is one, with a short-lived container of the agent image (the
  payload's `{image}`, by tag or by digest since 8a) that runs as root with no network and only that volume mounted,
  runs `find /workspace/outputs -mindepth 1 -delete` (a symlinked `outputs` is not followed),
  and is removed. It is labelled with the environment and `aixle.com/role=scrub`, never with a
  session, and a last check by label confirms that nothing is left. Repository checkouts, cache
  volumes and images stay. A container left, or an emptying that fails, is `scrub_failed`, and
  so is a workspace volume without the environment's label, which is not mounted or emptied.
- **`env.reset`** removes the containers and checks as the scrub does, then removes the
  workspace volume and every cache volume of the environment and checks that none is left. A
  volume another container still uses fails it with `reset_failed`. So does a volume named like
  the environment's that is not its own; then no volume is removed. Images stay.
- **Not built:** removing "anything the strategy itself wrote to a writable cache or home
  mount" of the table above. Neither op walks a host mount; writable host mounts stay outside
  the guarantee.

### 7.3 Allocation and concurrency on reused environments

`Runners::Allocator.acquire(session)`, under a `FOR UPDATE SKIP LOCKED` lock on candidate
rows:

1. to 3. **Removed (Alex, 2026-11-13).** Warm-cache affinity through `last_workflow_id`, then
   the project's own bound environment, then an unbound one: affinity and project binding are
   not needed for now (§9.4). The first step is any `idle` environment of this runner.
4. Otherwise, **only if the runner is `provisionable`** and
   `count(non-gone environments) < max_environments`, insert a new `runner_environments`
   row in `requested` in the same transaction. After
   commit, call `adapter.provision` for it (§5.1).
5. Otherwise raise `CapacityError`, and the session waits in the existing admission
   capacity wait.

**On `manual`, step 4 does not exist.** The allocator cannot create a machine, so when
every registered machine is busy, offline or
`failed`, the session **queues** in step 5 until one comes back to `idle`. Capacity is
exactly the machines the operator connected (§10).

**Two overlapping runs of the same workflow:** the second one gets **another environment**
(step 4), never the same one. If the pool is full it **queues**. It is never refused, and
it never falls back to `hosted`. That answers the open question with "fall back to a fresh
environment while there is room, then queue". On `manual` "room" means another idle
machine. Refusing would turn a capacity condition into a user-visible error. Sharing one
disk between two agents would corrupt checkouts. Hosted fallback is ruled out by §8.

---

## 8. Failure paths

The rule: **every failure names the runner and what to do, and nothing falls back to
`hosted`.** A silent fallback would run code that was meant for a private network on shared
infrastructure, with credentials the customer meant to keep inside their perimeter.

| Condition | Detected at | Outcome | Message (to the run, session and board comment) |
| --- | --- | --- | --- |
| Runner deleted, disabled or revoked | Launch (`Runners::Resolver`) | Fails before admission, `runner_unavailable` | "Runner "X" is disabled. Re-enable it or pick another runner on the workflow." |
| Runner not visible to the project | Launch | Fails, `runner_forbidden` | "Runner 12 is not available to project P." (by id: the runner is looked up through `TenantScope.owned`, so a foreign runner's name is never read) |
| Runner `unreachable` (`kubernetes`: controller silent; `coder`: health) | Launch | Fails, `runner_unreachable` | "Runner "X" is unreachable since 14:02: controller has not connected for 6 min." For `manual` the launch does not read the runner's status: it refuses on the machines (the two `manual` rows below), and the `unreachable` status, set by the periodic check (§2.5), is only shown. |
| Session mode not supported by the runner (an interactive standalone session, §4) | Selection | Refused | "Runner "X" can't run interactive sessions yet." |
| At `max_concurrency` | n/a | Not enforced: admission is unchanged for runner sessions, row 9 is deferred (§10) | n/a |
| At `max_environments`, or provider capacity (Coder quota, unschedulable pod) | `create_container` | `capacity_wait`, wait reason `runner_capacity`, reservation kept (session-admission §7) | "Waiting for capacity on runner "X"." |
| `provision` fails (template error, image pull, RBAC) | `create_container` | Diagnosed failure, environment `failed` | Provider message, e.g. "Coder: template parameter `instance_type` invalid" |
| Runner never checks in | `start_container` after `runners.bootstrap_timeout` (default 10 min, 15 for `coder`) | Fails, environment `failed`, teardown | "Environment started but aixle-runner did not check in within 10 min. Check egress to flow.aixle.com:443." plus the last bootstrap output the adapter captured |
| Prerequisites missing | Registration (`manual`) or check-in | Refused or fails, environment `failed` | "Machine build-01 has no reachable Docker daemon (aixle-runner needs Docker API ≥ 1.41)." |
| External runners not enabled for the company (no `external_runners` override, §12.1) | Selection, launch, every gateway request | Refused; launches fail with `runner_unavailable`; the gateway answers `403 runners_disabled` | "External runners are not enabled for this company." |
| `manual`: no machine registered yet, or every machine offline | Launch | Fails, `runner_unreachable` | "Runner "X" has no machine online. Last seen: build-01 at 14:02." |
| `manual`: every machine busy | `create_container` | `capacity_wait`, wait reason `runner_capacity` | "Waiting for a free machine on runner "X" (2 of 2 busy)." |
| `manual`: registration token expired or already used | `register` | Refused, `401 registration_token_invalid` | Printed by `aixle-runner configure`: "This registration token has expired or was already used. Create a new one on the runner page." |
| `manual`: reset fails on a machine | Release | Environment `failed`, out of rotation | Runner page: "build-01 failed to reset: <reason>. Fix the machine and press Return to service." |
| Agent image cannot be pulled | `create_container` (`container.start`, `image_pull_failed`) | Diagnosed failure, environment stays `idle` | "Could not pull ghcr.io/aixlehq/…@sha256:…: <registry error>. The workspace needs to reach ghcr.io or a configured mirror." |
| Runner protocol or version unsupported | Check-in | Refused, environment `failed` | "aixle-runner 1.2.0 is no longer supported (minimum 1.4.0)." |
| Connection lost mid-session | Heartbeat | Grace, then fails (§6.7) | "Runner environment lost contact for 15 minutes." |
| Agent exits without `finish_session` | Runner event | Fails, then automatic reset | "Agent exited with code 137." |
| Runner revoked mid-session | Revocation | Fails immediately | "Runner "X" was revoked by A at 14:10." |

---

## 9. Security model

### 9.1 What the platform sends to an environment

Exactly what a hosted pod receives today. Nothing is added:

- the session prompt, context files, skills, MCP config, and input and tracker files;
- **the launching user's agent credential** (CLI login). This is the most sensitive item,
  and the reason for the §3.2 permissions and the §11 disclosure;
- repository access through the git credential helper. Tokens are minted per request
  through the proxy and are short-lived, so no long-lived git token sits on the environment
  disk;
- session-bound keys (MCP `X-Session-Key`, git key, credential-sync key). These are HMAC
  session keys that die with the session, and with §6.6 they are only usable through the
  assigned environment.

Not sent: integration tokens (the Coder token stays on the platform), other users'
credentials, config items not attached to the session (still only through
`get_config_item`, still audited in `ConfigItemAccess`), or anything about other sessions.

### 9.2 Tokens

| Token | Issued | Lifetime | Grants | Storage |
| --- | --- | --- | --- | --- |
| Registration (Kubernetes) | Runner creation (there is no Rotate token, removed from the plan, Alex 2026-11-13). Shown once | Single use, expires in 24 h if unused (a GitOps `helm install` can take a review cycle) | Calling `register` once for this runner | Digest only |
| Registration (`manual`) | "Add machine" on the runner page. Shown once, inside the copy-paste command | **Single use, expires in 1 h** if unused | Calling `register` once, which creates **one** environment of this runner | Digest only. One token per machine |
| Controller access / refresh | `register` | Access 1 h. Refresh rotates on every use and becomes invalid after 30 days idle | Polling **controller ops of this runner** (provision, teardown, observe); posting results; minting nothing | Digest only. Refresh-token reuse detection revokes the whole family and marks the runner `degraded` ("credential reuse detected") |
| Bootstrap | Per environment, at `provision` | Single use, 30 min (or `bootstrap_timeout`, whichever is longer) | Calling `check-in` for **this environment** | Digest only. Delivered by Coder SSH stdin or by a k8s Secret the controller deletes after check-in |
| Environment access / refresh | `check-in` (`coder`, `kubernetes`), `register` (`manual`) | Access 1 h, rotating refresh. Invalid the moment the environment becomes `gone` or the runner is revoked. On `coder` and `kubernetes` also when it leaves `idle`/`busy`/`resetting`; a `failed` `manual` machine keeps its credential so it can be returned to service. A `manual` refresh token becomes invalid after 30 days without use, like the controller's | Polling **this environment's ops**; posting logs, events and results for the session **currently assigned** to it; the proxy for that session only | Digest only. On `manual`, stored by the runner in `/var/lib/aixle-runner/credentials` (`0600`, the runner's own user). Reuse detection revokes the family and marks the machine `failed` ("credential reuse detected") |

Every request re-checks the runner's status (cached for ≤ 5 s), so revocation takes effect
within seconds and does not wait for tokens to expire.

**Reuse detection and a retry after a lost response (task #206).** The gateway commits a
rotation before it answers, so a runner whose `POST /runner/v1/token` response was lost
retries with the refresh token that was just spent. That retry is not counted as reuse
when both hold:

- the token was spent less than 60 s ago, by its `used_at`
  (`Runners::Credentials::RETRY_WINDOW`);
- the pair the spend issued is unrevoked and unused. Each issued credential names the
  refresh credential whose spend issued it (`runner_credentials.rotated_from_id`). A refresh
  token is used once it is spent, and an access token once the gateway first accepts it,
  which the gateway records in its `used_at`: one write per token, not one per request.

On a retry, `Credentials.rotate!` revokes the unused pair and issues a fresh pair of the
same family, answering `200` as a rotation does, and logs the environment and the family
(no token). The window counts from the first spend, so a retry does not extend it, and a
second retry within it revokes the first retry's pair.
Anything else is reuse, as before: a retry after 60 s, a retry after the new pair was used,
and a refresh token two or more rotations old revoke the family, and the environment
records `credential reuse detected` as its `state_reason`.

An access token's first use and a retry of the refresh that issued it are serialized on
the access token's row. The gateway records the first use only on an unrevoked row
(`Credentials.record_use!`), and `rotate!` locks the issued pair before it reads it. If the
retry revokes the pair first, the use is not recorded and the request answers
`401 invalid_token`. If the use commits first, `rotate!` sees it and treats the spent token
as reuse.

What it costs:
- **A dropped connection longer than the window.** The runner retries about 1, 3, 7, 15 and
  31 s after the first failure (`runner/internal/backoff`), so the window covers a dropped
  connection of up to about 30 s. One that starts right after the gateway commits the
  rotation and lasts longer still ends in a re-registration (H2, rare).
- **A stolen spent token inside the window.** A second holder who presents the spent token
  within 60 s, before the legitimate runner has used its new pair, gets a pair, and the
  legitimate runner's pair is revoked. The runner then gets `invalid_token`, stops and asks
  for re-registration, rather than the family being revoked as reuse. Presenting a spent
  token needs the token itself, which the runner keeps in a `0600` file and never logs.

The alternatives were an idempotency key on `POST /runner/v1/token` with a replayable
response, for which the gateway would have to keep the issued pair encrypted, and a runner
that stops on a network error with an "outcome unknown" error, which still needs a
re-registration after every dropped connection.

**Decided (§6.9.2):** on `kubernetes` the bootstrap token travels in the `provision` op to
the controller, which calls `check-in` for the pod itself, so no bootstrap Secret is mounted
into a pod and the pod's environment credential is held by the controller.

**What a compromised runner can reach:**

- **An environment credential:** the data of the sessions that run on that environment
  (unavoidable, since it is the customer's machine), and the MCP tools of the session
  currently assigned, while it is live. It **cannot** pull work. Ops are pushed by
  assignment, and there is no "give me any job" call. It cannot address another
  environment's ops, read other sessions, or mint tokens.
- **A `manual` machine's credential** is an environment credential and reaches exactly
  the above. A leaked, unused registration token opens one new environment of that runner
  for up to an hour, which then only receives sessions an admin's runner selection sends
  it, in the scope the runner already has. The runner page lists every registered machine
  with its first-seen IP, so an unexpected one is visible and revocable.
- **A controller credential:** it can see provision requests for its runner and fake
  results. The bootstrap tokens it handles each open one environment's check-in, and those
  environments still only get ops assigned to them. Controller compromise is equivalent to
  compromise of the customer's cluster namespace, which they own.

### 9.3 Revocation

"Revoke" on a runner, in one transaction:

- sets `revoked_at` and status `revoked`;
- revokes every `runner_credentials` row of the runner;
- fails running sessions with the revoked message;
- marks queued ones `runner_unavailable`.

After commit, adapter `teardown` is attempted best-effort for every environment. The UI
says plainly that Coder workspaces and pods the platform cannot reach must be removed by
the customer, and lists them. "Disable" is the soft version: no new work, running sessions
finish, credentials stay valid.

On `manual` there is nothing for us to tear down. A revoked machine's runner gets `401`
on its next request and stops. **The machine does not clean up after itself on Revoke** (Alex,
2026-11-13): credentials are revoked at once, and the operator removes what is left, i.e. the
Aixle-labelled containers and volumes (§7.2) and the service, with `aixle-runner service
uninstall`. The user documentation says so.
Revoke also works **per machine** (the machines table on the runner page), which revokes
that environment's credential family only. It takes the place of Force release: it also
frees the admission slot held by a lost machine's session (§6.7). `aixle-runner unregister`
is the same thing initiated from the machine.

**What v1 has so far (§15 task 5a).** Revoke and Delete (a soft delete that revokes, §2.5)
set the status and revoke every `runner_credentials` row of the runner in one transaction
(`Runner#revoke_credentials`, after the status `UPDATE` has locked the runner's row). Every
issuer locks that row first, `FOR SHARE`, and re-checks the runner under it
(`Runners::Credentials.lock_live_runner!`, called by `Credentials.mint_registration!`,
`Registration.register!` and `Credentials.rotate!`). So a token or pair issued while a
revocation runs is either revoked with the rest or refused with `runner_revoked`; no
unrevoked credential survives. The lock order is
runner, then environment, then credential: `rotate!` also locks the environment that
`unregister!` locks to mark it `gone`, and `unregister!` takes the runner's lock first too,
so it cannot deadlock with a Revoke over the credential rows both revoke. Failing and
dequeuing sessions, and the teardown, come with the tasks that first run sessions on a
runner. Per-machine Revoke is task 12.

Removing the `external_runners` override for a company (§12.1) is not a revocation.
Credentials stay valid, the gateway refuses every request of that company's runners with
`403 runners_disabled`, running sessions fail at their next poll, and runners back off and
retry. Putting the override back lets them reconnect with no re-registration.

A user who leaves the company does not revoke runners they created. Runners belong to the
company or the project, like integrations, and `created_by` is audit only.

### 9.4 One project's runner is never used by another project's run

The check runs at three points, and the third one is what makes it a guarantee rather than
a convention:

1. **Selection:** the select only lists `Runner.visible_for_project(project)`. The
   controller validates the submitted `runner_id` against the same scope (no IDOR by id).
2. **Launch:** `Runners::Resolver.resolve!` re-checks
   `runner.company_id == session.company_id && (runner.project_id.nil? || runner.project_id == session.project_id)`
   on the session itself, because workflows can be copied, templated or moved, and a stored
   `runner_id` proves nothing on its own.
3. **Assignment:** the gateway authorises every op, log and proxy call against
   `environment.current_session_id`. A database check constraint ties
   `terminal_sessions.runner_environment_id` to the same company.

**Removed from the plan (Alex, 2026-11-13): the bound project.** An environment was to be bound
to the first project that used it, partitioned by project, handed from one project to another
only by an explicit **Release to company** that wipes and unbinds it. That, and the `project_id`
column of §2.2, are not needed for now.

**The company-scope case, as it is built:** a company runner's machines are reused across
projects, with no special handling. Without binding, a machine of a company runner takes
sessions of every project that can use the runner. Once scrub exists (task 11), what a scrub
keeps under `reuse_policy: reuse` (repository checkouts, package caches, pulled images) is
there for the next session, which may be another project's. The project scope is the way to
keep a machine to one project: a project runner's machines take that project's sessions only.

### 9.5 Network surface

The guarantee this design makes is about **inbound** connections. That is what carries the
network and security axes: the customer opens nothing towards their network, and the
platform holds no credential that reaches into it.

- **Inbound to the customer:** nothing. This is a commitment.
- **Outbound from the environment:** not restricted by this design, and there is no goal to
  narrow it to one host. The runner page documents what the runner and the agent need to
  reach, so customers who filter egress can allow it. It is in the user documentation only,
  **not on the runner page** (Alex, 2026-11-13). **This list is documentation, not a
  constraint we commit to keeping short:**
  - the platform host on 443 (gateway, proxy, the release redirect);
  - `github.com` / `objects.githubusercontent.com` for runner binaries (§14.3);
  - `ghcr.io` for agent images and the runner image (every type);
  - the git hosts of attached repositories;
  - the model provider, or the customer's Bedrock through their cloud connection;
  - whatever the agent's own work needs.
- **Inbound to the platform:** `/runner/v1/*` on the public ingress, rate-limited per token
  and per IP, with request bodies capped. The internal endpoints the proxy reaches stay
  internal.

### 9.6 The Kubernetes controller's footprint

The Helm chart (`aixle-runner`, published as an OCI artifact to
`ghcr.io/aixlehq/charts/aixle-runner` from the runner's repository, §14.1–14.2) installs
into one namespace:

- a Deployment of `aixle-runner --mode controller` with the registration token Secret;
- a ServiceAccount for the controller, bound to one namespaced Role (below) by a
  RoleBinding — nothing cluster-scoped;
- an optional NetworkPolicy (`networkPolicy.enabled`, default off). It is a convenience for
  customers who filter egress, prefilled from the documented list in §9.5. It is not a
  platform requirement.

**RBAC, derived from what the controller does.** This is not taken from the RBAC of our
hosted deployment, which serves a different installation with different constraints. The
controller does four things in its namespace and nothing else (the `provision`, `teardown`
and `observe` ops of §6.4, and the reconciliation pass of §10): it creates a session pod,
it gives that pod a bootstrap Secret and its own ServiceAccount, it watches the pod, and it
deletes all three afterwards. Each rule is the least verb set for one of those, and the
chart grants nothing else:

| Resource | Verbs | Why |
| --- | --- | --- |
| `pods` | `create`, `get`, `list`, `watch`, `delete` | Create the session pod on `provision`, watch it to report `observe` and to reconcile after a controller restart, delete it on `teardown`. No `update`/`patch`: a pod is never changed after creation. |
| `pods/log` | `get` | Diagnose a pod that failed before its session runner checked in (`bootstrap_timeout`, image pull errors). After check-in, logs come through the protocol. |
| `secrets` | `create`, `get`, `delete` | Create the per-environment bootstrap Secret, delete it after check-in and on `teardown`. `get` checks whether it is still there during reconciliation. No `list`/`watch`, so the controller cannot enumerate other Secrets in the namespace. |
| `serviceaccounts` | `create`, `get`, `delete` | One ServiceAccount per session pod, with `automountServiceAccountToken: false`, so pods never share an identity a customer may have bound elsewhere. Same reasoning as Secrets for no `list`/`watch`. |
| `events` | `create` | Optional (`rbac.events`, default on). Lets the controller record why it rejected or deleted a pod where `kubectl describe` shows it. |

Not granted, on purpose:

- `pods/exec`, `pods/attach`, `pods/portforward`: execution is inside-out (§1.2), so nothing
  ever needs to enter a pod;
- `rolebindings`, `roles` and any `escalate`/`bind`: session ServiceAccounts get no
  permissions at all, so the controller never has to grant any;
- anything cluster-scoped, including `nodes` and `namespaces`: the controller is installed
  into a namespace the customer chose, and it is not allowed to create one.

The labels the controller sets (`aixle.com/runner`, `aixle.com/environment`) scope what it
deletes. A `teardown` for an environment it did not create is refused by the controller,
even though the Role would let it delete other pods in the namespace. Customers who want the
API server to enforce that too install the chart into a dedicated namespace, which the chart
README recommends.

Session pods get:

- an init container that copies `aixle-runner` from `ghcr.io/aixlehq/aixle-runner:<version>`
  into an `emptyDir`;
- the bootstrap Secret mounted read-only;
- `automountServiceAccountToken: false`;
- the same non-root and privilege settings the hosted pod spec uses today.

The `<version>` comes from the platform in the `provision` op, so pods always run the
platform-recommended runner whatever version the controller is.

**Decided (§6.9.2, §6.9.3, §6.9.7), the footprint with the controller as the session pods'
owner:**

- the Role gains `pods/exec` (`create`), which leaves the "not granted" list above. `pods/log`
  (`get`) also serves the live log of running sessions (§6.9.4), and `secrets` hold the
  per-session proxy key instead of the bootstrap Secret; `leases` (`coordination.k8s.io`) serve
  leader election;
- a dedicated namespace becomes a requirement of the chart, not a recommendation, because
  `pods/exec` reaches every pod in the namespace;
- the controller keeps its credential pair, the environment credentials of its pods and the
  journal on a `PersistentVolumeClaim` the chart creates, with `replicas: 1` and the
  `Recreate` strategy, and takes leader election with a `Lease`; a controller generation that
  the gateway checks refuses a stale controller's calls;
- the controller gains an in-cluster listener for the proxy relay, over TLS, behind a Service;
- the NetworkPolicy becomes required, not optional: ingress to the controller only from
  session pods, and ingress to the session pods' ports only from the controller (ttyd 7681
  has no password). The Kubernetes validation of task 19 checks that the cluster's CNI
  enforces it;
- the chart requires Kubernetes 1.29 or later (`kubeVersion`), for native sidecars;
- session pods get the proxy sidecar from the runner image, with the proxy key mounted into
  the sidecar only, instead of the init container and the bootstrap Secret. The `<version>` in
  the `provision` op then names the sidecar's image.

### 9.7 A `manual` machine: what the operator takes on

The platform holds nothing into the machine, so the trust questions move to the operator,
and the user documentation says so plainly. This disclosure is in the docs only, not on the
runner page (Alex, 2026-11-13):

- **Agent sessions are a persistent tenant on that machine.** Every session assigned to it
  runs there, with its repository checkouts on the workspace volume between sessions.
- **The launching user's agent login lands there** (§9.1), as on every external type. The
  §3.2 permissions and the §11 disclosure on the run drawer and session form apply
  unchanged.
- **On a company runner a machine is reused across projects** (§9.4): what a scrub keeps is there for the next session, whichever project it belongs to. A project runner keeps it within the project.
- **The `docker` group is root-equivalent.** `service install` puts the `aixle-runner`
  system user in it, because the host runner starts containers. Anyone who controls that
  user controls the machine.
- **The runner replaces its own binary** (§14.4), which that user owns, with a binary whose
  SHA-256 the platform pins. An operator who wants no software change they did not make turns
  self-update off with `configure --no-auto-update`, or `config.auto_update: false` for the
  whole runner.
- **Recommendation:** a dedicated machine for the runner, not a shared developer box.

---

## 10. Session admission

**Decided (Alex, 2026-11-11): runners don't change session admission or its limits, for
now.** A session on a runner is admitted exactly like any other session: through its
project's pool and the company limit, as today. This phase only makes sessions run on
runners. The limit logic may be revisited later (task row 9 of §15 is deferred).

- **No change to admission.** `SessionAdmissionService.pool_configuration` has no runner
  branch, the invariants in `session-admission-queue/ARCHITECTURE-SPINE.md` hold unchanged
  (**exactly one applicable pool**, AD-1, included), and there is no pool of its own per
  runner, no exclusion from the company limit and no admission wait reason for a runner.
- **Runner sessions draw down `CompanyCapacityUsage`** like hosted ones, since they take
  the same company limit. Whether external sessions are billed, and how, stays an open
  product decision (§16).
- **`max_concurrency` stays on the runner** (§2.1, §2.7) but admission does not enforce it
  while row 9 is deferred. What bounds the sessions on one runner today is its own
  capacity, below.
- **A runner's own capacity is not an admission limit.** It is the allocator's concern
  (row 11) and, for `manual`, the end-to-end behaviour of row 12:
  - `runner_capacity` is the V2 `capacity_wait` after `CapacityError` from the allocator or
    the provider, with the reservation kept, as for `namespace_quota` today. The session
    page shows it (§11).
  - **`manual` capacity is a physical fact, not elastic.** There is no provisioning step, so
    `runner_capacity` on a `manual` runner means "every connected machine is busy", and it
    ends only when one frees up or the operator connects another machine. Nothing the
    platform or a setting does raises it. The runner page and the waiting-session message
    say "2 of 2 machines busy" rather than suggesting that capacity is being created.
  - **Built in task 12d.** `Runners::Machines.take!` raises `ContainerRuntime::CapacityError`
    with the reason `runner_capacity` (`Runners::Machines::RUNNER_CAPACITY`) when every machine
    that can take a session is busy: "Waiting for a free machine on runner \"X\" (1 of 1
    busy)." Machines that are offline or failed are not counted. `runner_capacity` is a wait
    reason like `cluster_capacity`: in `SessionAdmission::WAIT_REASONS` (so the reapers leave
    the reservation alone) and in `SessionAdmission#launch_phase`, and `launchStatus.ts` turns
    it into "Waiting for a free machine" on the session page, with the message under it.
    Nothing that reports cluster capacity counts a runner wait: `isWaitingForCluster` is false
    for it.
- **Release** follows AD-4 and the confirmed-release rule. The slot is freed when cleanup
  completes (scrub ok and the environment back to `idle`, or teardown confirmed). An
  environment the platform lost contact with keeps the slot until `observe` says `missing`
  or an admin forces release from the runner page. That is the external equivalent of
  "unknown creation retains capacity".
- **Reconciliation and the scanners.** The hosted scanners are not changed to skip runner
  sessions. Since row 8a, `ScanDeadContainersActivity` asks the session's own runtime
  (`ContainerRuntime.for_session`), so a runner session is checked through its runner.
  Comparing `runner_environments` with `adapter.observe` and with heartbeats belongs to
  the allocator (row 11).

---

## 11. UI surface

| Where | What |
| --- | --- |
| **Company → Settings → Runners** (new tab in `pages/Company/Settings/SettingsTabs.tsx`) | List of company runners: name, type, status pill with reason, machines busy/total, last seen. "New runner" for admins. |
| **Project → Runners** (new page next to Integrations, in the Resources group of the project sidebar) | Two sections: "From your company" (read-only, link to the company page for admins) and "This project". "New runner" for admins and the owner. |
| **New runner form** | Step 1: pick a type (cards; the type list comes from the adapter registry filtered by the flags, so a new type shows up without UI work, and the Kubernetes card only with `external_runners_kubernetes`). Step 2: the type's form generated from `config_schema`. Manual: the `container` options from §6.8, offered first as "give the agent your toolchain", with the acknowledgement for writable host mounts (§7.2), reuse policy with the per-type wording of §7.1, auto-update. Coder: integration select (visible ones), template, parameters, the `container` options, reuse policy, max environments. Kubernetes: namespace, and the `container` resources and image override. The fields per type are exactly the keys of §2.7. Step 3: limits. Then **Connect**: Manual shows the GitHub-style sequence of §6.3 (download, **SHA-256 verification**, `aixle-runner configure --url … --token …`, `aixle-runner service install`) with a one-time token, and waits for the first machine with a live status; Coder runs the config checks + `check_health` inline; Kubernetes shows the one-time registration token and `helm install` command, and waits for the controller. |
| **Runner page** | Status and health facts, capabilities, the container options that widen access (§6.8), environments table (state, current session link, last used, version; action Rebuild where `rebuildable`), Disable / Revoke / Delete. For `manual` the table is **Machines**: name, online / idle / offline, os/arch, first-seen IP, created by (`created_by_id`), runner version and auto-update; actions Return to service, per-machine Revoke; and "Add machine", which mints a new registration token. The runner page does not show the runner version against `recommended_version` (§14.2), the egress list (§9.5) or the §9.7 disclosure: those two are in the user documentation only. It has no Rotate token, no Reset, no Force release, and no machine facts (Docker version, free disk, images present; check-in still collects them, §2.2). |
| **Workflow builder → Base Resources** (`BaseResourcesTab.tsx`) | "Runner" select: `Hosted (default)` + visible runners with status. Inline warning when the referenced runner is not usable (§3.4). No warning for an interactive step on a runner without `interactive_terminal`: it is not built, for the reason in §4. |
| **Run drawer** (`RunWorkflowDrawer.tsx`) | "Runs on" select defaulting to the workflow's runner. For an external runner a one-line note: "Your agent login is used on this runner, which is operated by *Company/Project*." |
| **New session form** (`SessionNewForm.tsx`) | Same select and note. Interactive mode greys out every external runner until the tunnel (§4, §15 task 16). |
| **Session page, run page, step list, board task run history** | A "Runs on" badge: `Hosted`, or `Prod VPC · coder`, linking to the runner and environment. "Open in Coder" when `human_accessible`. There is no connection-lost banner (§6.7). This is where users see where a run actually executed. |
| **Admin (Administrate)** | No runners or environments dashboards (removed from the plan, Alex 2026-11-13). |

**What v1 has so far (§15 task 3).** The two lists, the new-runner form and the runner page,
all behind `useFeatureFlag('externalRunners')`, in `app/frontend/shared/resources/runners/`
and the pages `Company/Settings/RunnersPage`, `Company/Settings/RunnerPage`,
`Projects/Runners/RunnersPage` and `Projects/Runners/RunnerPage`:

- **Lists.** Company → Settings → Runners: name, type, status pill with `status_reason`, last
  seen; "environments busy/total" waits for the allocator's states (task 11). Project → Runners: "From
  your company" (read-only, with "Manage in company settings" for a company admin) and "This
  project", told apart by `scope`. "New runner" only with `canManage`.
- **New runner form**, a modal on the list: the type cards come from `runnerTypes` (only
  Manual today); step 2 is rendered from the type's `configSchema` by an in-house renderer
  (`SchemaFields`), with the `container` options first, mounts before the rest; step 3 holds
  the name, `max_concurrency` and, only on a `provisionable` type, `max_environments`. Each
  field shows the schema's `default` until it is set, and the form sends only the keys the
  user set, with their §2.7 names. Two §2.7/§6.8 rules are form widgets rather than schema
  keywords: each writable host mount gets an acknowledgement checkbox that writes
  `container.acknowledged_writable_mounts` (by target, `home_mount` by its `path`), and
  `docker_socket` is enabled only with `allow_privileged_mounts`, with a warning. The reuse
  policy carries the §7.1 wording and is sent only when chosen, so the server's per-type
  default applies. The server's errors land at their field: a `config` message at the field
  its leading key names, anything else above the form. The "Add machine" button is on a live `manual` runner's page since task 12a;
  the read-only Machines section is since task 12c (below), and the Machines table's actions are tasks 11a and 12. A created runner opens its page.
- **Session page, wait reasons.** A runner session waits for the same reasons as any other
  session (§10). The only runner-specific one is `runner_capacity` (the runner's own
  capacity, rows 11 and 12); there is no `runner_limit`.
- **Runner page.** Name, type, status and reason, scope, creator, last seen, limits, reuse
  policy, capabilities, the keys the config sets, and the §6.8 options that widen access
  called out above them. Edit (the same form without the type step), Disable, Enable,
  Revoke and Delete (the soft delete) only with `canManage`; a company runner seen from a
  project is read-only there and links a company admin to company settings. Environments
  and tokens are not there yet (tasks 5 and 12). The runner version against `recommended_version`,
  the egress list and the §9.7 disclosure are never on the page: the last two are in the user
  documentation only.
- **Machines section (task 12c).** On the page of a `manual` runner, company and project alike
  (`machines` prop, `RunnerMachineResource`; `RunnerMachines.tsx`), read-only: for each
  machine its name (`display_name`) and key, its state (online, idle or offline, or failed or
  gone with the reason, §2.5), its runner version and os/arch (from `register`, and from
  `check-in`), when it registered and its last seen (`last_heartbeat_at`). Machines are listed
  in registration order, `gone` ones included. The page asks for `runner` and `machines` again
  every 15 s while the tab is visible, so states and last seen move without a reload. The
  Overview's "Last seen" is the runner's `last_seen_at`. The first-seen IP and `created_by_id`
  and per-machine Revoke are task 12's remaining part; Return to service is task 11a. The
  facts (Docker version, free disk, images present) are not shown in the list, and there is
  no Reset action (removed, Alex 2026-11-13).

**What v1 has so far (§15 task 4).** Behind the same flag, the selects and the badges, built from
`shared/resources/runners/runnerChoice.tsx`. The selects are fed by `RunnerSummaryResource` (name,
type, status, `deleted`, `operatedBy`). The badges are fed by the slimmer `RunnerBadgeResource`
(name, type, `deleted`), which the session and run lists load with a plain `preload(:runner)`:

- **Base Resources** has a "Runner" select, `Hosted (default)` plus the visible runners with their
  status. The builder's list also holds the workflow's own runner once deleted, so the select can
  keep it, and an inline warning names a disabled, revoked or deleted runner. Saving is allowed
  with it. There is no interactive-step warning, and none is planned: it is not built, for the
  same reason as the §4 publish check.
- **The run drawer** (`shared/components/RunWorkflowDrawer.tsx`, used by the builder, the workflows
  page and Sessions & Runs) has "Runs on", starting from the workflow's runner, with the §11 note
  naming who operates it. **The new-session form** has the same select and note; in interactive
  mode every runner is disabled with "can't run interactive sessions yet".
- **"Runs on"** shows `Hosted` or "name · type", linking to the runner, in the session and run
  headers, on each session card of the run page, and on the board task's run tiles. The badge
  serializes a runner only when it is in the record's tenant (`RunnerReference#owned_runner`,
  `Runner#of_tenant?` checked on the preloaded row). A stale `runner_id` that names another
  project's or company's runner sends no name or type, and the badge reads "Runner not
  available" rather than `Hosted`.
- **The runner page** does not show where the runner is used: no "Workflows using it" list,
  and the delete confirmation is the ordinary one.

**Everything ships behind `external_runners` (§12.1).** For a company without the flag
none of these surfaces render, the controllers answer `404`, and the API refuses
`runner_id`. The server decides every write; the frontend only hides. One write is let through
without the flag: switching a **workflow's own** runner back to Hosted (`runner_id` blank on the
builder save, `Runners::Selection.workflow_error`). Turning the flag off for a company whose
workflows still name a runner makes every run of them fail with "External runners are not
enabled for this company."; Base Resources then shows that warning with a "Switch to Hosted"
action instead of the select. A hosted pick on a run or a session stays refused.

- **How the frontend reads it.** Both flags are `client: true`. They reach the browser
  resolved server-side, through the `features` shared prop (`FeaturesResource`, each value
  resolved by `FeatureFlags.client_value`), and components read them with `useFeatureFlag` (`externalRunners`,
  `externalRunnersKubernetes`). The Runners tab, the Project → Runners page, the three
  selects and the "Runs on" badge are wrapped in `useFeatureFlag('externalRunners')`.
- **Known consequence, owned by the task that adds the flag (done in 1a).** `external_runners`
  is the **first** `client: true` flag in the registry. Per the comment on the `client:` line of
  `config/feature_flags.yml`, the comment above `FeatureFlagName` in
  `app/frontend/shared/ui/types.ts`, and "When the first client flag exists, prefer a
  resource" in `docs/architecture/feature-flags.md`, that is the trigger to replace the
  hand-written `FeatureFlagName` union with an Alba `FeaturesResource` that declares the
  client flags as `typelize :boolean` attributes, so Typelizer generates `Features` and
  `useFeatureFlag(name: keyof Features)` needs neither the list nor
  `test/config/feature_flag_name_test.rb`. **That switch is part of task 1a (§15), the task
  that declares the flag.** It is not a later discovery, and the flag does not land with a
  hand-edited `FeatureFlagName` first. It is platform cleanup triggered by the first client
  flag, not runner work, so it is reviewed on its own, apart from the runner models (1b).
  Task 1a made that switch: `FeatureFlagName` and its test are gone, and `Features` is
  generated from `FeaturesResource`.

---

## 12. Rollout

### 12.1 Flags

Two declared flags in `config/feature_flags.yml`, in the registry's format. Nothing else
gates the feature: there is no `Settings` toggle, no `companies` column and no type list
in settings.

```yaml
external_runners:
  description: External agent runners — connect a machine, Coder or Kubernetes and run agent sessions there.
  owner: "@AixleHQ/platform"
  kind: release
  scope: company
  default: false
  client: true
  introduced: 2026-11-02   # placeholder: the date the first implementation PR (task 1a) is opened
  remove_by: 2027-06-30    # a review checkpoint, not a planned removal date (see below)

external_runners_kubernetes:
  description: The kubernetes runner type, shipped dark after the other types.
  owner: "@AixleHQ/platform"
  kind: release
  scope: company
  default: false
  client: true
  remove_by: 2027-08-31    # a review checkpoint, not a planned removal date (see below)
```

- **The check** is `Feature.enabled?(:external_runners, company:)`, always with the
  runner's or the session's company, in the literal shape docs/architecture/feature-flags.md asks for:
  - the company and project Runners controllers (`requires_feature :external_runners`, which
    reads it for the current company), and every controller or API endpoint that
    accepts `runner_id` (a company without the flag gets `404` or the field refused);
  - `Runners::Resolver.resolve!` at launch, so a workflow that still names a runner fails
    with the §8 message and never falls back to `hosted`;
  - the gateway, on every `/runner/v1/*` request, together with the runner status check
    (§9.2) and with the same ≤ 5 s cache;
  - the adapter registry's type list.
- **`external_runners_kubernetes`** is checked only where the `kubernetes` type itself is
  involved: the type list, creating a `kubernetes` runner, and `register` from a
  controller. It is declared in phase 6, not before (§12.2).
- **No hosted code path reads either flag.** `ContainerRuntime.for_session` branches on
  `session.runner_id`, which can only be set while the flag is on (§12.3).
- **`remove_by` is a checkpoint, not a schedule.** We do not know how long these flags
  will live: they guard a seven-phase delivery whose pace depends on the named companies,
  not a single PR, so the guide's "about eight weeks out" does not fit and no date here is
  a plan to remove them. The registry needs a date, so the date is a **review point**:
  - it is reviewed at every phase boundary of §12.2, by the task that closes the phase;
  - moving it is a PR that edits `config/feature_flags.yml` and says why in its
    description (what is still behind the flag, and what the next checkpoint waits for);
  - reaching it does not remove the flag; it means the review is overdue.

  The initial dates are only a first checkpoint, placed after the phase that completes each
  flag's scope: `external_runners` after phase 5 (Coder), `external_runners_kubernetes`
  after phase 6.
- **`kind: release` stays** for both. `ops` is for permanent operational switches, and
  these are rollout gates that are meant to be removed at GA, whenever that is.
- **No ENV mechanism.** The design does not rely on `FEATURE_<KEY>` and builds nothing
  around it. The rollout is `default: false` plus company overrides set from
  `/admin/feature_flags` (super admins only, a reason required, an `Audit` row per change).
- **No incident kill-switch path.** This feature is used by our own people in a controlled
  environment. Removing a company's override is the stop button: launches fail, the gateway
  refuses that company's runners, and running sessions end at their next poll (§9.3).
- **Ownership composes with §3.2 as it is.** The flag decides whether external runners
  exist for a company at all, a platform decision made from `/admin`. Inside a company where
  it is on, §3.2 decides who may create and edit a runner.
- **The runner pins stay in `Settings`** (§14.2): the `runners.release` block of
  `config/settings.yml`. They are a pin, not a toggle, and they never become a flag.

### 12.2 Delivery order, as flag states

Each phase leaves `develop` releasable and the hosted path untouched. "Test company" is our
own staging test company; "named companies" are companies given an override from `/admin`,
one at a time, each with a reason. The flags never go `default: true` before removal.

**No compatibility with earlier versions of the runner feature until it has users (decided,
Alex, 2026-11-13).** Nobody outside our test company has the `external_runners` flag, and
nobody will until phase 4. Until then, a change to runner data or behaviour keeps no shims
for earlier states: a migration may rewrite or drop runner rows, and the only such data is on
staging. The first phase that gives the flag to a named company (phase 4) ends this rule.

| Phase | Content | `external_runners` | `external_runners_kubernetes` | Who sees the client-side surfaces |
| --- | --- | --- | --- | --- |
| 1 | Model and CRUD, no execution. A run with an external runner fails with "runner execution not enabled". This validates scopes, permissions and failure messages before any code runs remotely | Declared. `default: false`. Override **on for the test company only** | Not declared | Members of the test company: the Runners pages (Manual type card only), the builder, drawer and session-form selects, the badge |
| 2 | Protocol, gateway, `aixle-runner` (`host` and `session` modes), the conformance fixtures, the dev `local` adapter | Unchanged: test company only | Not declared | Test company. Developers locally, through the `local` adapter and the test helpers |
| 3 | **`manual` type, container mode, end to end**, non-interactive. Validated on staging (§12.4); not yet given to customers | Unchanged: test company only | Not declared | Test company. Type cards: Manual |
| 4 | **Interactive tunnel**: ttyd, the IDE and the watcher relayed through the runner. UX parity with hosted. Lifts `interactive_terminal: false`. **The first customer-usable slice** | `default: false`. Overrides: test company, then **named companies** that need a `manual` runner, only once this phase is done | Not declared | Members of those companies. Type cards: Manual. Interactive sessions and steps are selectable on runners from the start |
| 5 | **Coder adapter**: provisioning, pooling, warm disk. Staging validation (§12.5) | Unchanged. Coder becomes available to every company that already has the override; no new flag | Not declared | Same companies. Type cards: Manual, Coder |
| 6 | **Kubernetes controller, Helm chart**, the second flag | Unchanged | **Declared.** `default: false`. Override on for the test company, then named companies | Kubernetes card only for companies with both overrides |
| 7 | **`host` execution mode** (services in containers, CLI on the host), toolcache kits, P2 (§6.8) | Unchanged | Unchanged | The `execution_mode` option appears on `manual` and `coder` runner forms of companies with the override |
| GA, then removal | Docs, then the flags are removed | Global on from `/admin`, then a removal PR (§ "Removing a flag" in `docs/architecture/feature-flags.md`); `remove_by` is moved to the GA checkpoint until that PR lands (§12.1) | Same, after its own GA | Everyone |
| later | Hosted onto the same interface (§13) | Gone | Gone | — |

Phase 2 details that stay from revision 3:

- The protocol is written down as a specification, `runner/protocol/PROTOCOL.md`. It lives
  with the runner under `runner/`, so the extract takes it along (§14.1).
- **The conformance fixtures are committed in this phase** (`runner/protocol/fixtures/v1/`,
  §14.1), and the gateway's Rails tests run them from the first PR. They are the contract
  the Go implementation is written against, and what makes the later extract safe.
- The Go code has its own CI job, `Runner (Go)` in `.github/workflows/ci.yml` (`gofmt`,
  `go vet`, `go test -race` with the Go side of conformance, and the builds for both
  arches), with no path filter and part of the required `Checks` status (task 6a).
- A dev-only `local` adapter starts a host runner as a container on the Compose network,
  with the Docker socket of the dev machine. The whole path is then testable in Docker, with
  no machine and no Coder needed. It is a `manual`-like adapter (registration, no
  provisioning) with a scripted `configure`, so phase 3 starts from a working path.

**Why `manual` is the first type.** It has no provisioning, so phase 3 is only the runner,
the protocol and container mode, the parts every later type reuses. It is also the purest
form of the security axis: the platform holds nothing into the customer's machine. Coder
adds provisioning, pooling and warm disks on top of a path that already works.

**Why the tunnel is phase 4.** Runners have to give the same user experience as hosted, and
that is only true once the live terminal, the IDE and the watcher work. In container mode
it is a relay of ports the image already serves (§6.8), so it does not depend on the runner
type and is built once for all of them. It is developed against the `local` adapter from
phase 2, so it does not wait on a provider.

- **Why real users wait for it (decided 2026-10-30).** Named companies get the override
  only after phase 4, and until then `external_runners` stays on for the test company only.
  Phase 3 is complete as a non-interactive path and is validated on staging (§12.4), but
  without the tunnel a runner cannot run the interactive sessions and steps hosted runs.
  So no interim checks are built for the gap: the publish check, the run-override check
  and the builder's interactive-step warning are dropped (§4, §11), because no real user
  has the flag before the tunnel and the tunnel lifts the restriction. The standalone
  session check stays as task 4 built it.
- **Why it still comes right after phase 3.** It is what lets the first named company in,
  so it comes before any second type.
- **What would change this order.** If the first named company needs Coder before it needs
  interactive sessions, swap phases 4 and 5. They are independent, so the swap costs
  nothing. Either way, named companies get the override only once the tunnel is done.

### 12.3 The hosted runtime is not touched

Every change to a shared file is a guarded branch whose hosted arm is today's code:

- `ContainerRuntime.for_session` (§5.3);
- admission is not touched at all while row 9 is deferred (§10);
- the callback-URL seam (`runtime.callback_url`, §6.6, task 8b), whose hosted arm answers the
  `Settings` values unchanged;
- nullable columns.

**One deliberate change to hosted (task 8a).** `DockerRuntime#exec!`, the development
runtime, now raises `ContainerUnreachableError` for a container the daemon does not know, as
`KubernetesRuntime#exec!` does for a pod it cannot reach; before, it raised `NoMethodError`.
The callers that rescue `ContainerUnreachableError` (the quota and no-output scans,
`Sessions::LiveLogReader`) now skip such a session on Docker as they do on Kubernetes, and the
contract test (§15 row 8a) needs both runtimes to answer `exec!` without a container the same.
Production runs Kubernetes, whose behaviour is unchanged.

**A second deliberate change to hosted (task 8a, Fix CR round 3): a larger timeout only.** The
agent session's `create_container` budget (`AgentSessionStrategy#phase_config`) goes from 300 s
to 600 s, because a runner pulls the image in that phase (`container.start`). Hosted does the
same work in it as before; it only gets longer before Temporal times the phase out. The
admission's identity was already persisted before `create_container` for every runtime, and
the runner-only persistence before `pull_image` is gone.

Phase 1 adds a regression test that runs the existing hosted admission and launch tests
with `external_runners` **enabled for the test's company**, through the helpers in
`test/support/feature_flags_helper.rb`
(`with_feature(:external_runners, true, company: company) { ... }`), and asserts that the
same Kubernetes calls are made as with the flag off. "Unchanged" is then checked by a test
and not assumed. It is `test/integration/hosted_runtime_unchanged_test.rb` (task 4): a
standalone session and a workflow step go through the real admission and launch relay and the
container phases on the runtime seam, once with the flag off and once on, and the runtime
calls, the admission and the outcome must match. In phase 6 the same test runs with `external_runners_kubernetes` enabled
for that company too. Task 8b extends it: the callback addresses the hosted container is created
with must be the same with the flag on, and the `Settings` values (`callback_env`).

**Tech debt this creates, with its exit condition.** Leaving hosted untouched means **two
execution models live side by side for an open-ended period**: outside-in for hosted
(`KubernetesRuntime` / `DockerRuntime` exec into a pod), and inside-out for external
runners (`RunnerRuntime` over the protocol). Until that ends, every change to a
`ContainerRuntime::BaseRuntime` primitive (`exec`, `write_file`, `read_file`,
`container_status`, `container_logs`) or to a `ContainerWorkflowV2` phase has to be
reasoned about, and tested, twice: once for each model, including the ways each one fails.

- **Recorded as:** this section, and a note in `app/services/container_runtime/base_runtime.rb`
  that names both implementations. It is not a task of its own in §15 (Alex, 2026-11-13).
- **Mitigation while it lasts:** the conformance fixtures (§14.1) cover the `RunnerRuntime`
  side of every primitive, and the "hosted unchanged" regression test covers the hosted
  side. A change to a primitive must touch both suites in the same PR.
- **Exit condition:** §13 step A (hosted routed through `Runners::Allocator`, no behaviour
  change), then step B (hosted pods run `aixle-runner` as PID 1 and exec over the
  protocol). **The debt is closed when step B ships and `KubernetesRuntime#exec` has no
  caller left in the session path.**
- **Trigger to schedule step A:** the protocol is declared stable (the same trigger as the
  runner extract, §14.1), and one full release has passed with no protocol-breaking
  change. Step B follows once step A has run in production for one release. This section
  carries the trigger, so it is reviewed when the protocol is declared stable and not left
  open-ended.

### 12.4 Validating the first `manual` runner on staging (phase 3)

Precondition: the `external_runners` override is on for the staging test company (§12.2,
phase 1). The machine is any Linux host with Docker that we control and that can reach the
staging platform host outbound. A workspace from the staging Coder integration is a
convenient choice, used here as a plain machine: nothing is provisioned through Coder, and
the operator steps are done by hand in its terminal, exactly as a customer would. The
machine used is recorded in the validation task's result.

1. Create a project runner of type `manual` on the staging test project. "Add machine"
   shows the download, the SHA-256 line, `configure` and `service install`. Follow them:
   the checksum verifies, `configure` registers, the machine appears **idle** within
   seconds, and the runner goes `connected`.
2. Reuse the same registration token on a second machine: refused with the §8 message.
   Wait an hour with an unused token: refused as expired.
3. A one-step non-interactive workflow (`claude_code`, a repository attached) runs on the
   runner. The machine shows **online**; the session page shows the runner badge, the live
   log streams, `finish_session` completes the step, outputs and logs are collected, cost
   is recorded.
4. Run it again: same machine, the agent image is not re-pulled, the clone on the
   workspace volume is fetched rather than re-cloned, and no `aixle.com/session`-labelled
   container is left (`docker ps -a --filter label=aixle.com/environment=<key>`).
5. Start two runs at once with one machine: the second **queues** with `runner_capacity`
   ("1 of 1 machines busy") and runs when the first finishes. Nothing is provisioned.
6. Set `reuse_policy: fresh`: after a session the workspace volume is gone and recreated
   empty for the next one; the pulled image stays.
7. Repeat step 3 with `cursor_cli` and with `grok`: usage is recorded from the MITM log
   exactly as on hosted.
8. Stop the Docker daemon and restart the runner: the machine goes `failed` at check-in
   with the Docker message. Start Docker, press Return to service: it resets and goes idle.
9. Block outbound traffic to the platform host for 2 min mid-session: the agent continues
   and the logs back-fill. For 20 min: the session fails with the grace message, and the
   machine resets on reconnect.
10. `sudo systemctl restart aixle-runner` mid-session: the session container keeps running
    and the session completes.
11. Reboot the machine while idle: the service comes back and the machine is idle again
    with no operator action.
12. `aixle-runner unregister`: the machine disappears from the list and its credential
    gets `401`. Register again and Revoke from the UI: the runner on the machine stops. Its
    containers and volumes are left, and the operator removes them (§9.3).
13. Point a run from a second project at the project runner by id through the API: 403.
14. Selecting `hosted` or nothing on the same project behaves exactly as before. The hosted
    pods are created as before, verified on the cluster.
15. The long-poll wake-up through the real Redis adapter (CI runs the `test` cable adapter
    only, §6.1): with the machine idle in a `GET /runner/v1/ops` with `wait=25`, enqueue an
    op for its environment through `Runners::Operations.enqueue!` from a Rails console on
    staging. The poll answers with the op well before its 25 s end (within about a second).

### 12.5 Validating the first Coder runner on staging (phase 5)

Validation runs against **the staging Coder integration already configured on the test
project**, with whatever workspace template that integration offers at the time of
testing. This design names no template and no template version on purpose: the template is
a property of our staging environment and will drift, and the runner has to work on a
template the design never saw, which is also the customer case. What the validation needs
from the chosen template is checked at test time, not assumed here:

- it can run a Docker daemon, which is the only container-mode prerequisite (§6.8). If it
  cannot, the runner reports that at check-in, which is itself a check of the §8 message;
- its disk covers an agent image plus the workspace volume (§6.8);
- if it prunes images or build cache on a schedule, the warm-image result of step 5 is
  read with that counted.

The template used, and the answers to these three, are recorded in the validation task's
result, so a later re-run knows what it is comparing against.

1. Create a project runner on the staging test project over its existing Coder
   integration: one of the templates the integration offers, `max_environments: 2`.
   The steps of §12.4 already proved the runner, the protocol and container mode, so this
   validation concentrates on what Coder adds: provisioning, pooling and the warm disk.
2. Health goes `connected`. Revoking the integration token turns it `unreachable` with the
   integration named.
3. A one-step non-interactive workflow (`claude_code`, a repository attached) runs. Check:
   - the session page shows the runner badge;
   - the live log streams;
   - `finish_session` completes the step;
   - outputs and logs are collected;
   - cost is recorded.
4. Run it twice in parallel: the second run gets the second workspace, and a third run
   queues with `runner_capacity`.
5. Run it again: it lands on a warm workspace (the machine's), the agent image is not
   re-pulled, the clone on the `/workspace` volume is fetched rather than re-cloned, and
   the scrub left no session container and no credential files on the volume (check over
   Coder SSH with `docker ps -a` and a file search).
6. Repeat step 3 with `cursor_cli` and with `grok`: usage is recorded from the MITM log
   exactly as on hosted, which confirms `agent_runtimes: all` on a provisioned type.
7. Kill the runner's connection (block the workspace's outbound traffic to the platform
   host, for example with a firewall rule on the workspace) for 2 min
   mid-session: the agent continues and the logs back-fill on reconnect. Block it for 20
   min: the session fails with the grace message.
8. Restart the host runner mid-session (`systemctl --user restart aixle-runner`): the
   session container keeps running and the session completes.
9. Revoke the runner mid-session: the session fails within seconds and old tokens get 401.
10. Point a run from a second project at the project runner by id through the API: 403.
    Make it a company runner and run both projects: environments are bound and not shared.
11. Selecting `hosted` or nothing on the same project behaves exactly as before. The hosted
    pods are created as before, verified on the cluster.

---

## 13. How `hosted` moves onto the same interface later

Not proposed now. Shown so that nothing in the contract excludes it.

| Contract | `Runners::HostedAdapter` (future) |
| --- | --- |
| `provision` | `KubernetesRuntime#create_container`, the same pod spec |
| `prepare` | `start_container` + `wait_for_ready` |
| `inject_bootstrap` | Step A: no-op, keep exec through `KubernetesRuntime`. Step B: the pod gets `aixle-runner` as PID 1, as on customer Kubernetes and on `manual` and `coder`, and connects to the gateway from inside the cluster |
| `reset` | n/a (ephemeral) |
| `teardown` | `cleanup_session` |
| `observe` | `container_status` |
| capabilities | `reusable: false`, `interactive_terminal: true`, pools = today's admission pools |

Step A changes no behaviour. It just routes hosted sessions through `Runners::Allocator`.
Step B makes hosted inside-out as well, which would let us drop pod `exec` RBAC from our
own runtime ClusterRole. `hosted` would then become a seeded built-in runner that cannot be
deleted, and `runner_id IS NULL` would keep meaning it, so no data migration is needed.

**Decided (§6.9.6), step B without a PID 1 change.** Hosted sessions are run by an
`aixle-runner --mode controller` we operate in our cluster, which runs the session ops through
the Kubernetes API, as on a customer's cluster (§6.9.2). Hosted pods keep their pod spec, and
`inject_bootstrap` stays a no-op. `pods/exec` moves from the Rails application's ClusterRole to
that controller's namespaced Role, instead of disappearing. The exit condition of §12.3 stays
as written: `KubernetesRuntime#exec` has no caller left in the session path.

---

## 14. Runner distribution and versioning

### 14.1 Repository layout: the monorepo for now, and the extract as a stated intent

**Decision:** `aixle-runner` is written in Go (one static binary for `linux/amd64` and
`linux/arm64`, plus the image `ghcr.io/aixlehq/aixle-runner`) and lives **in the `flow`
monorepo under `runner/`** for now. This is a decision, not a default. It is chosen
because while the protocol is still moving, the gateway and the runner change together
almost every week, and one repository makes that cheaper to author and review.

**Intent: extract it into `AixleHQ/aixle-runner`.** It is extracted when the first of
these happens:

1. the protocol is declared stable (protocol `1` frozen, changes only through `N+1`);
2. the first non-staging customer connects a runner;
3. binary signing is introduced (§14.3), since keys and the release process belong with
   the artifact.

**What keeps the extract cheap.** These rules apply from the first commit:

- `runner/` is self-contained, with its own `go.mod`, following the `docker/otlp-ingest/`
  precedent (its own `go.mod`, `go.sum` and `Dockerfile`). It builds with
  `cd runner && go build ./...` and needs nothing outside the directory.
- `runner/` has no dependency on Rails code, configuration or generated files. It never
  reads `config/`, `app/` or `Settings`. Everything it needs comes over the protocol.
- The protocol is a **specification document**, `runner/protocol/PROTOCOL.md`, and the
  **conformance fixtures** are in `runner/protocol/fixtures/v1/` (request and response
  pairs, op payloads and results, error cases, resume sequences). The protocol lives with
  the runner, under `runner/`, so everything about the runner is in one directory. It
  belongs to neither the Rails tests nor the Go tests: the Go code reads it inside
  `runner/`, and the Rails tests read it from there too. They are committed in phase 2
  (§12.2).
- The extract is `git filter-repo --path runner/`, which keeps history and takes the
  protocol with it. Afterwards `flow` keeps a pinned copy of `runner/protocol/` that only
  changes by a PR, and the Rails side keeps running the fixtures against the gateway.

**Where the Helm chart lives.** The chart belongs with the runner. Trigger 2 is expected
right after phase 4, the first customer-usable slice, so **the extract is expected before
the Kubernetes adapter ships in phase 6**. So the chart lane is built in
`AixleHQ/aixle-runner` from the start, and **`charts/` is never created in `flow`**. If the
extract slips past the start of phase 6 after all, the chart goes under `runner/chart/`.
That is inside the extract path, so it moves with the runner and still never becomes a
top-level directory of the application.

**Why the monorepo's main benefit is narrower than it looks.** "A protocol change and its
gateway counterpart in one PR" is an authoring convenience, **not atomic deployment**. A
runner in a customer's VPC is old by definition: it updates when it is idle (session
mode), or when the customer runs `helm upgrade` (controller). So the protocol is a
published contract under any repository layout. What protects it is `[N-1, N]` support
plus the conformance fixtures, and both work the same across two repositories.

For comparison:

- GitHub keeps `actions/runner` in its own repository. That is partly structural, because
  the server is closed source.
- GitLab keeps `gitlab-org/gitlab-runner` and its Helm chart as separate projects. Their
  versions are aligned by convention but released independently.
- Buildkite keeps `buildkite/agent` in its own repository.
- Woodpecker keeps server and agent in one repository, because the same operator deploys
  both together.

The pattern follows who deploys the artifact and on whose schedule. It does not follow
language or code style. Our runner is deployed by the customer on their schedule, which is
why the extract is the intent.

**What v1 has so far (§15 task 6a).** `runner/` is the Go module
`github.com/aixlehq/aixle-runner`, the import path the extracted repository keeps. `go.mod`
pins the Go version on its `go` line, and CI installs that version from it. It builds with
`cd runner && go build ./...` and reaches Docker through
the official SDK, `github.com/moby/moby/client`. The binary is `./cmd/aixle-runner`, built
statically (`CGO_ENABLED=0`) for `linux/amd64` and `linux/arm64`. Its version is
`internal/version.Version`, set at build time with
`-ldflags "-X github.com/aixlehq/aixle-runner/internal/version.Version=<version>"`; a local
build reports `0.0.0-dev`. The packages are under `runner/internal/`: `protocol` (the client
and the refusal table of `PROTOCOL.md` §3), `tokens`, `credentials`, `journal`, `host` (the
ops loop), `docker` (the session's container and its image), `preflight`, `service` and `cli`. The `Runner (Go)` job of
`.github/workflows/ci.yml` runs `gofmt`, `go vet`, `go test -race` (the conformance tests
against `runner/protocol/fixtures/v1/` included) and both builds on every pull request, with
no path filter, as part of `Checks`. Task 10 added the release lane, the image and
self-update (§14.2 to §14.4).

### 14.2 Versions and release lanes, independent of the application release

There are **three distinct versions**, and none of them is the application version:

| Version | Example | What it versions | Where it is set |
| --- | --- | --- | --- |
| **Runner version** | `1.4.0` | The `aixle-runner` binary and `ghcr.io/aixlehq/aixle-runner:1.4.0` | The `runner-v1.4.0` tag |
| **Chart version** | `0.3.2` | The Helm chart's packaging (templates, values, defaults) | `Chart.yaml` `version`, the `runner-chart-v0.3.2` tag |
| **Chart `appVersion`** | `1.4.0` | The runner version the chart installs by default | `Chart.yaml` `appVersion` |
| **Protocol version** | `1` | The wire contract (`X-Aixle-Runner-Protocol`) | `runner/protocol/PROTOCOL.md`, an integer bumped only on breaking changes |

**Release lanes:**

- **`runner-v*`** builds the binaries, attaches them and a `checksums.txt` to a GitHub
  Release, and pushes `ghcr.io/aixlehq/aixle-runner:X.Y.Z`.
- **`runner-chart-v*`** packages the chart and pushes it as an **OCI artifact** to
  `ghcr.io/aixlehq/charts/aixle-runner`. Customers install it with
  `helm install oci://ghcr.io/aixlehq/charts/aixle-runner --version X.Y.Z`. There is no
  chart repository and no `index.yaml` to host.
- Both lanes are one new workflow (`runner-release.yml`, in `flow` until the extract, then
  in `aixle-runner`). The application lanes are untouched. The `v*` tag filters on
  `images.yml` and `release.yml` are prefix-anchored globs, so they do not match
  `runner-v*` or `runner-chart-v*`. An application release never builds a runner, and the
  reverse is also true.

**The platform's pins are committed configuration, not derived from the release.** The
`runners.release` block of `config/settings.yml`, read through `Settings`
(`Settings.runners.release`, per the `NoEnvInApp` cop), holds plain values, no ENV:

```yaml
# Illustrative values.
runners:
  release:
    protocol_supported: [1]           # becomes [N-1, N] after the first bump
    min_version: "1.2.0"              # check-in / register refused below this
    recommended_version: "1.4.0"      # what new environments install; "update available" below this
    binaries:
      "1.4.0":
        linux-amd64: { sha256: "…" }
        linux-arm64: { sha256: "…" }
```

Changing what the platform recommends is an **application PR** that edits this block, and
it is independent of a runner release. Publishing `runner-v1.5.0` changes nothing until a PR
moves `recommended_version`. The "update available" banner on the runner page then compares
against `recommended_version`, so it no longer fires on every application release.

**Compatibility statement.** `docs/operations/releasing.md`, whose version contract only
covers the application today, gains a "Runner compatibility" section: *platform `X.Y`
supports runner protocol versions `[N-1, N]` and runners at or above `min_version`, both as
declared in the `runners.release` block of `config/settings.yml` at that release.* The
application changelog mentions any change to that block.

**What v1 has (§15 task 10).** The first runner version is `0.1.0` (`runner-v0.1.0`, decision 1,
Alex 2026-11-09): `1.0.0` comes with the extract or the first customer (§14.1).

- **The lane** is `.github/workflows/runner-release.yml`. A `runner-v*` tag on `develop` runs
  `go vet` and `go test -race`, builds both static binaries with the tag's version stamped in,
  writes `checksums.txt` (`sha256sum` format), checks that each binary is static and reports its
  version (`aixle-runner version`), and builds `ghcr.io/aixlehq/aixle-runner:X.Y.Z` for both
  platforms from those same binaries with `docker/runner/Dockerfile` (no build from source in
  the image, a non-root user, nothing run at build time). It pushes the image and creates the
  GitHub Release with the two binaries and `checksums.txt`, never marked the repository's
  latest, so `latest` stays the application's. Run by hand (`workflow_dispatch`, decision 4) it
  takes a version and does everything except push and release: the dry run the verification
  round uses, without a public tag.
- **The pins** are the `runners.release` block of `config/settings.yml`, read as
  `Settings.runners.release` and checked by `Runners::Release` once the app is loaded
  (`config/initializers/runner_release.rb`): an invalid block fails boot. Task 10 kept them in a
  YAML file of their own, loaded with `add_source!`; its follow-up (task #220) moved them into
  `settings.yml`, the one loading mechanism, next to the other `runners:` settings. Besides the
  four keys above the block holds `download_url`, the template of the asset URL the release
  endpoint redirects to (`%{version}`, `%{platform}`), so a mirror is one edit. It pins
  `protocol_supported: [1]`, no minimum, and `recommended_version: "0.3.0"` with the
  `linux-amd64` and `linux-arm64` digests of `runner-v0.1.0`'s, `runner-v0.2.0`'s
  and `runner-v0.3.0`'s `checksums.txt` (task #220; `0.2.0` pinned by task #232,
  `0.3.0`, the heartbeat release, by task #244; `0.1.0` and `0.2.0` kept so
  machines on them still download and verify). The
  gateway's `X-Aixle-Runner-Protocol` check reads `protocol_supported`, and
  `X-Aixle-Runner-Version` is strict SemVer 2.0 from task 10 on, so versions compare by SemVer
  precedence (`Runners::Version`).
- **The endpoints** are `GET /runner/v1/releases/:version/:os-:arch`, a `302` to the pinned
  asset with `X-Aixle-Runner-Sha256`, and `GET /runner/v1/releases/:version/checksums`, the
  same digests as JSON. Both are public, take no protocol header, and answer `404 not_found`
  for anything unpinned and `400 invalid_request` for a malformed version or platform
  (`schemas/v1/releases.params.json`). `PROTOCOL.md` §5.6, §5.7.

### 14.3 Binary distribution and integrity

- **Binaries are served from GitHub Release assets** of the `runner-v*` release.
- **The documented URL is the platform's**: `GET /runner/v1/releases/:version/:os-:arch`
  answers `302` to the asset. The installer and the runner only ever know this one URL. A
  self-hosted or air-gapped deployment can later serve the bytes from the platform, or
  from a mirror, without changing the runner or the script.
- **`install.sh` verifies SHA-256** against the digest the platform serves (the
  `X-Aixle-Runner-Sha256` header, and the checksums endpoint for the self-update path).
  Both come from the platform's pins (`runners.release` in `config/settings.yml`), not from
  the asset host, so a tampered asset fails verification. The script keeps a **`verify` hook**, a function called with the
  file and its metadata, which today checks the digest only. Signature checking can be
  added there later without a contract change.
- **cosign signing is deferred.** It is not part of the first iteration. Introducing it is
  one of the extract triggers (§14.1).
- The agent images and the runner image are pulled from GHCR by the customer's Docker
  daemon or kubelet. That is documented on the runner page (§9.5), and it needs no
  special story beyond that. Agent image size is a phase 6 prerequisite for Kubernetes
  (§12.2).

### 14.4 Skew, self-update and where the runner lands

- **Skew policy:** the platform supports **the current and previous protocol version** and
  any runner ≥ `min_version`. Below that, `check-in`/`register` is refused with the upgrade
  message (§8). **A run never starts on an unsupported runner, and it is never killed
  because a newer runner came out.** Task 10 built the refusal at `register`
  (`400 runner_version_unsupported`, whose message names the minimum; the registration token
  is not spent); task 8c built the check-in's.
  **Known limitation (Alex, 2026-11-12): no drain-safe mode.** A host that restarts while its
  session container is still running, after `min_version` was raised, stops at check-in, before
  its ops loop: the platform can issue no ops for that session until the runner is updated and
  starts again, when the session continues. `min_version` is raised deliberately and only for a
  protocol break, and there is none today; the runbook for raising it
  (`docs/operations/releasing.md`) says to update the machines first.
- **Self-update:**
  - **Runners on reusable environments self-update by default.** That means the host
    runner on `manual` machines and on Coder workspaces. When the check-in response or
    an idle poll carries `update: {version, sha256}`, the runner downloads through the
    release URL of its own platform, verifies the digest, and re-execs. This happens only while the
    environment is `idle`, never during a session, and only towards
    `recommended_version`. The session runner inside a session container is the host
    runner's own binary, so it is updated with it. Ephemeral pods never need an update,
    because the platform picks their version (§9.6).
  - **`manual` opt-out.** Customers who manage the machine through their own configuration
    management (Ansible, Puppet, a golden image) turn self-update off, per runner
    (`config.auto_update: false`) or per machine (`configure --no-auto-update`). Such a
    runner reports its version like the controller does: "update available" and `degraded`
    below `recommended_version` on the runner page, and refused below `min_version`, so an unmanaged skew still surfaces at check-in and never mid-session.
  - **What v1 has (task 10).** A runner learns of an update from the answer of its
    long-poll that has no ops (decision 2, Alex 2026-11-09): `GET /runner/v1/ops` then
    carries `update: {version, sha256}`, read after the wait, only while the machine is
    `registered` and holds no session, the request's `X-Aixle-Runner-Version` is below
    `recommended_version` and the binary for the machine's `os` and `arch` is pinned, and
    never when the runner's `config.auto_update` is false or the machine registered with
    `auto_update: false` (`runner_environments.auto_update`, which `configure
    --no-auto-update` sends at `register`; `Runners::Release.update_for`). 8c's `check-in`
    adds the same field. The host runner (`internal/update`) takes it only while the machine
    has no session container, only towards a version above its own, and never with the
    machine's opt-out, which it keeps in its credentials file as well. It reads the release's
    checksums and the redirect of the release URL, both from the platform URL it was
    configured with (the offer names no URL), refuses the update unless the three digests agree, downloads the asset
    into the directory of its running binary, and checks it with `update.Verify`, the
    `verify` hook that checks the SHA-256 only until releases are signed. Only then does it
    rename the download over its binary, atomically, and exit with code `4`, which the unit's
    `Restart=always` (and the `local` adapter's Compose `on-failure`) restarts on the new
    binary. A download whose digest does not match is deleted, the running binary stays, and
    the same version is tried again an hour later at the earliest. A download has 2 minutes
    (`update.DownloadTimeout`), well under the 600 s of a lifecycle op. **The update takes no
    reservation** (Fix CR round 1, Alex 2026-11-10): the platform may give the machine a
    session after the empty answer that offered the update, so a session assigned while its
    machine updates has its `container.start` queued, and it starts after the runner has
    restarted and polled again. The race only delays that start by the download and the
    restart, and it happens at most once per release per machine.
  - **Not in a container.** In a container the image tag is the version, so a runner started
    from the published image (`docker/runner/Dockerfile`) does not update itself: the image
    sets `AIXLE_RUNNER_NO_SELF_UPDATE=1`, which turns the updater off (`Updater.Disabled`)
    whatever the credentials say. Its binary is root-owned there, and a container recreated
    from the image would bring the old binary back anyway. Such a runner reports its version
    like one that opted out.
  - **The controller does not self-update.** It is Helm-managed, and customers running
    GitOps would see that as drift. It reports its version, and the runner page shows
    "update available" (`degraded` if below `recommended`, refused if below `min`). A
    protocol bump is announced one release ahead because the previous protocol stays
    supported.
- **Where it lands:**
  - **Coder:** `inject_bootstrap` pipes `install.sh` over `coder ssh` stdin. The script
    fetches the binary through the platform's release URL (302 to the GitHub asset),
    verifies its SHA-256, installs it to `~/.aixle-runner/bin`, and starts it detached in
    `host` mode. It uses `setsid`, and a systemd user
    unit where available, so the runner survives the SSH session. On a reused workspace a
    live runner is detected and not re-installed.
  - **`manual`:** the operator downloads the binary from the platform's release URL,
    verifies the SHA-256 shown next to it, and installs it with `configure` and
    `service install` (§6.3). The binary lives in `/var/lib/aixle-runner/bin`, a directory
    the runner's own `aixle-runner` user owns, as the GitHub Actions runner lives in its
    user's directory (task 10, decision 3): `service install` creates it and copies the
    binary there, and the unit's `ExecStart` runs it. The systemd unit runs as that user,
    survives logout and reboot, and has `Restart=always`. Self-update replaces the binary in
    place while the machine is idle and exits, and systemd starts the new binary. There is no
    root helper and no package manager: operators who manage the machine themselves turn
    self-update off.
  - **`manual` in Docker (task 12b):** the published image runs as a host runner
    (`docker/runner/Dockerfile`). The proxy sidecar bind-mounts the runner's own binary and
    its relay socket, and the daemon resolves those paths on the machine, so with
    `AIXLE_RUNNER_DIR` set the entrypoint copies the binary into that directory, a directory
    of the machine mounted at the same path, and `configure`, `unregister` and `--mode host`
    keep the state in `$AIXLE_RUNNER_DIR/state`. Without it the entrypoint is the binary, as
    before. The container runs as `--user 0:0`: the image's user 10001 can reach neither the
    Docker socket nor the machine's directory, and a process with the Docker socket is root
    on the machine anyway. A volume mounted read-only at `/var/lib/docker` lets the
    preflight's disk check measure the daemon's filesystem, as `runner-local` does. The image
    does not update itself (the tag is the version): update it by running the new version's
    image over the same directory.
  - **Kubernetes:** the init container and image as in §9.6.
  - **Decided (§6.9.6):** there is no session runner. The proxy sidecar on `manual` and
    `coder` runs the host runner's own binary, bind-mounted, so it is updated with it. On
    `kubernetes` there is no init container: the proxy sidecar's image is the runner image
    named in the `provision` op.
  - **New type:** its adapter implements `inject_bootstrap` with whatever "run this script
    once" primitive the provider has. That is the only per-type part of distribution.

---

## 15. Implementation breakdown

**This is a map, not a batch of tickets.** Implementation tasks are cut one at a time from
this list, and each is taken to a merge in `develop` before the next one is written, so
every task is written against the code as it actually is. Each item is independently
reviewable and lands behind the flags. The number in the second column is the phase from
§12.2.

| # | Phase | Task |
| --- | --- | --- |
| 1a | 1 | **Flag and the client-flag resource.** Declare `external_runners` in `config/feature_flags.yml` exactly as in §12.1 (`introduced` set to the PR's date). Replace the hand-written `FeatureFlagName` with an Alba `FeaturesResource` and `useFeatureFlag(name: keyof Features)`, which touches every existing `useFeatureFlag` consumer, and retire `test/config/feature_flag_name_test.rb` (§11). Override on for the test company from `/admin`. Platform cleanup triggered by the first client flag, not runner-specific: a prerequisite for task 3, not for 1b, and reviewed on its own. |
| 1b | 1 | **The `runners` table and the `Runner` model**, only what task 2 reads and writes. The `runners` migration (§2.1, without `encrypted_secrets`): the unique name index, the four check constraints and the two composite tenant keys (§2, §2.4). `Runner` with enumerize `runner_type` and `reuse_policy` (defaulted by type, §2.7), validations mirroring the database, the §2.6 integration rule, `visible_for_project` (§3.1), and the status state machine with soft delete (§2.5). No flag check here: nothing reaches the model until task 2's controllers, which check it. Every other table and column of §2 lands with the first task that reads or writes it. |
| 2 | 1 | **Done.** Policies and controllers: `Web::Company::RunnersPolicy` and `Web::Company::Projects::RunnersPolicy` with the §3.2 rules (the project policy refused writes on a company runner, from the record; task #209 moved that to the controllers' lookup, §3.2), company runners CRUD at `/company/settings/runners` and project runners at `/company/projects/:project_id/runners` (`index`, `show`, `create`, `update`, `destroy` as the soft delete that revokes, `disable`, `enable`, `revoke`), each a `404` without the flag, declared with `requires_feature :external_runners` (`FeatureGated`, docs/architecture/feature-flags.md). `RunnerResource` for the pages. `Runners::ConfigSchema` encoding §2.7 for every type (refusing unknown, inapplicable and later keys; defaults never written), the `Runners::Adapter` registry with `ManualAdapter` only (`coder` and `kubernetes` are refused as not available yet), capabilities `provisionable` and `rebuildable` stored on save, and `ManualAdapter#validate_config` (task #209 moved its rules to `Runners::ConfigSchema`, §5.1). The other §4 flags wait for their first reader, and `check_health` moved to task 12. `IntegrationsController#destroy` shows the error when `Integration`'s `has_many :runners, dependent: :restrict_with_error` refuses the removal, instead of ignoring `destroy`'s result and saying "Integration removed" (until task 17 decides what disconnecting does to runners). Needs 1a (the flag) and 1b. |
| 3 | 1 | **Done.** Frontend behind `useFeatureFlag('externalRunners')` (needs 1a): the Company Settings → Runners tab and the Project → Runners page (sidebar entry next to Integrations, "From your company" and "This project"), the new-runner form generated from the type's `configSchema` by an in-house renderer (Manual card; the writable-mount acknowledgement and the Docker-socket rule as form widgets; only the keys the user set are sent, verbatim; the server's errors shown at their fields), and the runner page without machines (capabilities, config with the options that widen access, limits, Edit, Disable, Enable, Revoke, Delete), as §11 "What v1 has so far" describes. |
| 4 | 1 | **Done.** Selection: the nullable `workflows.runner_id`, `workflow_runs.runner_id` and `terminal_sessions.runner_id` references (§2.4), with how `runner_id` is snapshotted and restored in a workflow version, including a runner that is gone (§3.4); `workflows.runner_id` in the builder (Base Resources) and the version snapshot, run-drawer and new-session selects, `Runners::Resolver` with launch-time checks (status, visibility, flag) and the §8 failure messages, `runner_id` frozen on `workflow_runs`, "Runs on" badges. A reference is checked by the project's tenant rule (`TenantScope.owned(Runner, …)`). The runner pages do not list where a runner is used. A project move blocks on the project's own runners, switches its workflows that name a runner to Hosted (archived ones included, listed in the preflight), clears `runner_id` on its runs and sessions and on its workflows' version snapshots; a revert to a version whose runner is gone or no longer reachable restores Hosted (§3.4). Without the flag, a workflow can still be switched back to Hosted. The badges serialize only a runner in the record's tenant. The "hosted unchanged with the flag enabled" regression test of §12.3. |
| 5a | 2 | **Done.** The gateway process type (`config/puma_runner_gateway.rb`, `runner_gateway` in `Procfile.dev`; its deployment is an `aixle-infra` task) and `/runner/v1/*` as `RunnerGateway::V1` (§6.1). The `runner_environments` and `runner_credentials` tables, with only the columns this task reads and writes (§2.2, §2.3). Token issuance and rotation in `Runners::Credentials` (§9.2): registration tokens minted by the service, with no endpoint or UI, single-use and valid for 1 h; access tokens valid for 1 h; refresh tokens that rotate on every use, expire after 30 days unused, and revoke the family on reuse, a spent one past its own expiry included. `register` creates one `registered` `manual` environment. `DELETE registration` marks it `gone` and revokes its credentials, without `409 busy`, which waits for the first task that assigns a session to an environment. Every request checks the protocol header, the token (a refresh token that is revoked, of a `gone` environment, or expired without being spent is refused before anything else), the runner status (cached 5 s) and the flag; the gateway's Puma caps bodies at 64 KB (2 MiB since 5b). Only the gateway process draws the `/runner/v1` routes (`AIXLE_PROCESS_MODE`, set by its Puma config), and every other process draws everything else. Revoking a runner revokes its credentials in the same transaction, serialized against every issuer, registration-token minting included, by a lock on the runner's row (§9.3), and credentials of a `gone` environment are refused (§9.2). Rack::Attack throttles per token, per IP on all of `/runner/v1/*`, and per IP on `register`. `terminal_sessions.runner_environment_id` moved to its first reader (task 8 or 11). |
| 5b | 2 | **Done.** The `runner_operations` queue (§2.3), with only the columns this task reads and writes, and `Encryptable` with `runners_key` (`RUNNERS_SECRET_KEY`, not required at boot) for its `encrypted_payload`, nulled when the op completes, fails or expires, and its `encrypted_result`. `Runners::Operations.enqueue!` as a service only, taking the environment's next sequence. The `GET /runner/v1/ops` long-poll (§6.2, §6.7): the token's environment's ops past `after`, batched, marked `delivered`, waiting up to 25 s and checking access again after the wait, woken through Redis pub/sub (`ActionCable.server.pubsub` on `runner_env_<id>`, published after commit) and subscribed before it reads so no wake-up is missed, holding no Active Record connection while it waits (§6.1). `POST /runner/v1/ops/:id/result` (§6.4): `ok`, `error` and `expired` complete, fail and expire the op, the first result wins, and another environment's op is `404`. The gateway's Puma caps bodies at 2 MiB. |
| 6a | 2 | **Done.** `aixle-runner` in Go: the self-contained module `runner/` with its own `go.mod` and the Go version pinned (§14.1), one static binary for `linux/amd64` and `linux/arm64` with its version set at build time (`0.0.0-dev` for a local build), written against `runner/protocol/` (task 7). Docker is reached through the official Docker Engine SDK for Go (`github.com/moby/moby/client`). `configure` with its local preflight (Linux amd64/arm64, Docker API ≥ 1.41, 20 GiB free; a failed check registers nothing) and the credentials file (§6.3); `unregister`; `service install`/`uninstall`/`start`/`stop` with the systemd unit and the `aixle-runner` system user in the `docker` group (§9.7), the unit running the root-owned copy `/usr/local/bin/aixle-runner` that `install` makes. `--mode host`: refresh before expiry and on an access `invalid_token`, every rotation stored atomically before use, every refusal handled as `PROTOCOL.md` §3 says, no token in a log line; the ops loop, one long-poll at a time, `after` moved only past an accepted result; ops past `deadline_at` answered `expired`; the at-most-once journal (§6.7), with a graceful stop during an op answered `interrupted`; an exclusive `flock` on the state directory, held by `--mode host` and taken by `configure` and `unregister`; results retried until accepted, a `404` dropped; an op the runner does not implement answered `unsupported_op`; the `image.ensure` op, specified in `PROTOCOL.md` §6.1 with its fixture (by digest; 8a removed the digest, then the op: `container.start` always pulls the reference it is given). The Go side of conformance (a fake gateway built from the fixtures) and the `Runner (Go)` CI job (`gofmt`, `go vet`, `go test -race`, both builds), part of `Checks`. |
| 6b | 2 | **Done.** The agent container on `manual`, with the session ops run by the host runner through the Docker API (decision 1, Alex 2026-11-05: no runner inside the agent container; the host runner is the environment's only poller, §16). `container.start` creates and starts `aixle-<key>-<session_id>`, labelled `aixle.com/environment` and `aixle.com/session`, from the image pinned by digest (8a removed the digest: the image is the reference as given, which the runner always pulls) with its own entrypoint, with the payload's env, workspace and cache volumes (created with the environment's label), read-only-by-default binds, network, pid, resources and `no-new-privileges`, restart policy `no`, nothing of the runner inside (a bind that would expose the state directory is `forbidden_mount`), and at most one container per environment (`container_exists`); `container.stop` stops and removes it. The session ops `exec` (user, env, cwd, `timeout` through coreutils `timeout`, stdin), `write_file` (mode, owner), `read_file`, `batch` (until the first failure), `status` (as `DockerRuntime#container_status`) and `logs` (the tail of `/tmp/terminal_output.log`), found by label for every op, answering `no_session_container` without one; output and files capped at 1 MiB, a constant of `PROTOCOL.md` (decision 2), with larger output moved to task 8. A host-runner restart leaves the container running, and a cut-off op is answered `interrupted`. The journal drops a result once it is accepted. `env.scrub` and `env.reset` by label and name (§7.2, "As built"). `session.start`/`session.stop` stay reserved (`unsupported_op`). Each op's schema and fixtures are in `PROTOCOL.md` §6.2 to §6.4. The in-container session runner (`--mode session` as PID 1) and its Unix-socket relay moved to task #205, with the callback proxy, the live log, the tunnel and how `kubernetes` runs the session ops. Fix CR round 1 (Alex, 2026-11-06) added: a result over the gateway's body cap answered `result_too_large`; an `exec` without a `timeout` bounded by the op's `deadline_at`; ownership checks before acting on a name (`volume_not_owned` in `container.start`, `container_not_owned` in `container.stop`, and `scrub_failed`/`reset_failed` for a volume with the environment's name and without its label); and `write_file` refusing an absent or `null` `content`. |
| 7 | 2 | **Done.** `runner/protocol/PROTOCOL.md`, protocol `1` as built: the transport and its three headers, the limits (the 2 MiB body cap, the three throttles, `no-store`), every refusal with its status, endpoints and check order and what a runner does on each, the token kinds and rules, the five endpoints of 5a and 5b, the op envelope and names (payload schemas left to 6a, 6b and 8), versioning, and what is not in protocol 1 yet. The conformance fixtures in `runner/protocol/fixtures/v1/` (register, token, unregister, headers, refusals and ops scenarios, and the registration, access-token, spent-refresh and batch boundaries), in the JSON format of `runner/protocol/fixtures/README.md`: named setup steps, request/response exchanges, captured variables and type matchers. `RunnerProtocolConformanceTest` runs every fixture file against the gateway's routes, its setup steps calling the real services, in the normal Rails CI shards. The fixtures README lists the clauses verified outside the portable suite (`413`, `429`, the unserved-path `404`, `runner_revoked`) with the Rails tests that cover them. The protocol lives under `runner/protocol/`, with the runner (§14.1). §6 links to `PROTOCOL.md` for the wire details. The Go side of conformance and the Go CI lane came with 6a (§12.2). |
| 8a | 2 | **Done.** `ContainerRuntime::RunnerRuntime` and the op path (Alex, 2026-11-07: row 8 is three tasks, 8a, 8b and 8c, each written against the code the one before merged). `ContainerRuntime.for_session(session)` gives a session with a runner `RunnerRuntime` and every other session `ContainerRuntime.build`, unchanged, and every call site that acts on one session goes through it: `BaseStrategy#runtime`, `AdmittedPhaseActivity`, `SessionContextService` (and the credential write it makes), `Sessions::LiveLogReader`, `Sessions::AuthPause`, `Sessions::SecretRegistry`, `Trackers::Workspace`, `Agents::CredentialDelivery`, the internal tools that read a session's files, and the scanners (`ScanDeadContainersActivity`, `ScanQuotaErrorsActivity`, `ScanNoOutputSessionsActivity`, `CleanupStaleActivity`); `ContainerSweepOrphanedResourcesActivity` sweeps the hosted runtime's own objects and stays as it was. `for_session` is the only place that picks a runtime (Alex, Fix CR round 2): the runtime reaches the code that uses it as an argument or a constructor dependency, never through `Thread.current`, a global or class-level state, and `SessionContextService` assembles a session's context through one object per assembly that holds the session, its runtime and the context log. **One runtime call of a strategy is one runner op** (requirement 2): `RunnerRuntime` enqueues it with `Runners::Operations.enqueue!`, waits for its result (`Runners::Operations.await`, heartbeating the activity) and answers what `DockerRuntime` answers; an op that ends `error` or `expired` answers as a hosted failure does (`ContainerUnreachableError` from `exec!` without the session's container, exit code 1 from `exec`, `false` from `write_file`, `nil` from `read_file`, `:missing` from `container_status`). No `batch` grouping (decision 5). An op's `deadline_at` is its own budget, and at most the end of the activity that sends it less 5 s (`RunnerRuntime::ACTIVITY_MARGIN`), and the wait stops at it and expires the op, so the strategy gets the expired outcome before Temporal times the activity out. The budgets: an `exec`'s `timeout` plus 30 s, `Settings.runners.op_timeout` (60 s, what `DockerRuntime#exec` waits by default) for the other session ops, `Settings.runners.lifecycle_op_timeout` (600 s) for `container.start`, `container.stop` and `env.reset`; the scanners cap theirs at `Settings.runners.scan_op_timeout` (15 s), so a machine that does not answer reads as unknown, never as dead or idle, and costs a scanner exactly that cap. The phases (§5.3, "What 8a built"). **Fix CR round 3 (Alex, 2026-11-07):** `RunnerRuntime#pull_image` does nothing, as `KubernetesRuntime#pull_image`, and the machine is taken in `create_container`; `container.start` always pulls the image reference, then creates and starts the container, and a failed pull is its `image_pull_failed`; the `image.ensure` op is removed from the platform, `PROTOCOL.md`, the fixtures and the Go runner, and with it `identity_before_pull?`, since the admission's identity is persisted before `create_container` for every runtime; the agent session's `create_container` budget is 600 s (§12.3). `RunnerRuntime` is not bound to a session, like `DockerRuntime`: `create_container` finds the session from the spec's `aixle.session_id` label, and every other call from the admission whose `runtime_id` its container id or cleanup identity is (a partial index on `session_admissions.runtime_id` for runner admissions); `op_timeout` stays the caller's budget. The wait for an op checks the activity's cancellation on every look, as `ToolStrategy#wait_with_heartbeat` does. A reused refresh token moves the machine to `failed` (§9.2), so it is given no session. **No digest** (Alex, Fix CR round 1): `container.start` and the helper container of `env.scrub` take the image reference as the user gave it, a tag or a digest, `container.image_override` included; the runner always pulls it, and no op returns a digest. The platform never contacts a registry, which it may not reach when a customer runs the runner in their own network. The dev `local` adapter therefore needs agent images from a registry: a pull always happens. The container's options come from the runner's `config.container` (§2.7), its resources from the hosted container's limits unless `container.resources` sets them. `Runners::Resolver` no longer refuses a `manual` runner with `runner_execution_not_enabled`: a runner without a registered machine, or whose every machine is `failed`, is refused `runner_unreachable` at launch, with a message that names it (and the failed machines, their reasons and how to bring one back). **Which machine takes a session** (decision 2): `Runners::Machines`, a free `registered` machine of the session's runner, one session per machine, taken under its row lock (`FOR UPDATE SKIP LOCKED`) and recorded in `runner_environments.current_session_id` and `terminal_sessions.runner_environment_id`; every machine busy raises `ContainerRuntime::CapacityError`, so the session waits in `capacity_wait`; the machine is taken in `create_container`, the first phase that needs it, and the admission's identity is persisted before that phase, as for every runtime, so a failure or a stop in it, the pull included, still runs the cleanup; after the session the machine gets `env.reset` and is free again, and a machine whose reset failed, or was not answered, moves to `failed` (§5.2), held by no session, with the reason in `state_reason`, so nothing that happens to the session, its deletion included, returns it to rotation (Return to service stays task 11a). A session's ops reach its machine only while it holds it. `CleanupStaleActivity` sends a runner nothing, and moves a machine a stale session still holds to `failed`. **`session_id` in the op envelope** (requirement 1): `runner_operations.terminal_session_id`; a session op must name its session, an environment op names none, and every op is created only while its session holds the machine, checked by `enqueue!` under the machine's lock; `session_id` left the payloads of `container.start` and `container.stop`; the host runner refuses a session op without one (`session_required`) and one whose container is labelled with another session (`session_mismatch`), `container.start` and `container.stop` included, `container.stop` answers `no_session_container` without any session container, and `container.start` names and labels the container from the envelope (`PROTOCOL.md` §6, with the fixtures and the new `session_on_machine` setup step). **The queue's housekeeping**: an op still without a result is expired by the platform, with its payload nulled: at its `deadline_at` by the wait that sent it, and 10 s past it, `pending` or `delivered`, by `RunnerOperationsSweepWorkflow` every 5 minutes for the ops nobody waits for; the same sweep prunes finished ops older than 7 days. The sequence is a counter on the environment's row, `runner_environments.op_sequence` (Fix CR round 4: chosen over keeping each environment's newest op for `MAX(sequence) + 1`, which a session's deletion, taking its ops with it, broke), so the prune and that deletion remove any finished op. **The dev `local` adapter** (§12.2): the `runner-local` Compose service (profile `runners`), `aixle-runner` built from `runner/` with `docker/runner/local/Dockerfile` (the runner images live under `docker/runner/`), image `${RUNNER_IMAGE:-runner}`, and run in web's network namespace with this machine's Docker socket, and `bin/runner-local register <runner id>`, which mints a registration token and runs `configure`. **Fix CR round 4 (Alex, 2026-11-08):** `enqueue!` takes the session of every op and checks its hold under the machine's lock, which replaced the model's check that the session ran on the machine; `Machines.acquire!` no longer touches the caller's session and is idempotent for one session; `Machines.fail!(…, holder:)` is a compare-and-set, as `release!`; unregistering a machine ends its hold; `Machines.availability` answers `:available`, `:none_registered` or `:all_failed`, and one method words the refusal; the company keys of the session references; the cleanup sends nothing while an op of the session is unfinished, and `container.start` stops at its `deadline_at`; an answered `container.start` refusal is a `ContainerRuntime::CreateRefusedError` and pins no reservation; the runner pulls with the Docker credentials of the user it runs as; the Go session handlers take the envelope's `session_id` as a parameter (`SessionHandler`). **Fix CR round 5 (Alex, 2026-11-08):** Docker Hub's credentials are looked up under `https://index.docker.io/v1/`, as the Docker CLI's `getAuthConfigKey` maps them; a runner stopped during `ContainerCreate` removes what the daemon may have created and answers `container_start_failed`; a runtime call is external I/O and is never made inside a database transaction, on any runtime (`BaseRuntime`), which a test-time check enforces, and `Sessions::SecretRegistry#publish!` serializes a session's publications with a connection-level advisory lock instead of a transaction's; the cleanup waits for any unfinished op on the machine the session holds, an `env.reset` included; `create_container` returns the platform's container name, never the runner's. **Fix CR round 7 (Alex, 2026-11-08):** the host runner cuts an `exec`'s positive `timeout` to the seconds left until the op's `deadline_at`, as it bounds an `exec` without one, so an `exec` never holds the serial ops loop past its op's deadline. Tests: the contract test (`test/services/container_runtime/runner_runtime_contract_test.rb`) runs the same scenarios on `DockerRuntime`, against the Docker Engine API served by WebMock from an in-memory machine, and on `RunnerRuntime`, whose ops `ContainerRuntime::FakeHostRunner` answers from that machine with the results of `PROTOCOL.md` §6. |
| 8b | 2 | **Done.** The callback proxy (§6.6, §6.9.3; `PROTOCOL.md` §5.8). An agent on a `manual` runner reaches MCP, `finish_session` included, the agent credential sync and refresh, git credentials (GitHub, GitLab, Bitbucket, Azure DevOps), cloud credentials and stored files through a local proxy. **The Go side:** `aixle-runner --mode proxy`, the sidecar (`internal/proxy.RunSidecar`), a reverse proxy on `127.0.0.1:7690` to the host runner's relay socket; the relay (`proxy.Relay`), served by `proxy.Host` on a Unix socket per session under the state directory (mounted read-only into the sidecar only), or with `network: host` on the session's port of the machine's `127.0.0.1`, which serves `/runner/v1/proxy/*` only and adds the environment credential; `container.start` creates the sidecar first, from the agent image with the host runner's binary bind-mounted read-only as its entrypoint, and the agent joins its network namespace; `container.stop`, `env.scrub` and `env.reset` remove it with the agent's container and close the relay; a restarted host runner serves the running sidecars again (`Environment.Resume`). **Decision 10:** a sidecar that exits stops the agent's container, so the session fails through the dead-container path, and its exit code and log tail are logged. **Decision 4:** a daemon that refuses the sidecar's bind mount ("bind source path does not exist") gives `docker_files_not_visible`, naming the cause. **The platform:** the gateway route `ANY /runner/v1/proxy/:route/*` (`RunnerGateway::V1::ProxiesController`): the environment credential, the allow-list (`Runners::Proxy::ROUTES`, **decision 7**: no OTLP route, deferred, so a runner session gets no OTLP endpoint), the key of the session that holds the environment (`Runners::Proxy.holder`), then an HTTP forward to the internal endpoint with `X-Aixle-Runner-Environment`, streamed back (**decision 8**), with no body schema (**decision 9**), and `X-Aixle-Runner-Refusal` on every refusal of the route. **Decision 6:** the callback-URL seam, `runtime.callback_url(name, session)` (`ContainerRuntime::CallbackUrls`), the `Settings` value on hosted and `http://127.0.0.1:<port>/<route>` on a runner, read by the env vars, the MCP config, the asset URLs of the context and the instructions, `read_tool_result` and the OTLP endpoint of the agent configs; `RunnerRuntime` rewrites no string. **An implementation decision for review:** with `network: host` the port is per session (`20000 + id mod 10000`), sent as `container.start`'s `proxy_port`, not per environment, because the container's environment is built before the session takes a machine (§6.9.3). `PROTOCOL.md` §5.8 and §6.2 describe the proxy, the port, the socket, the headers, the refusals (`route_not_allowed`, `session_not_on_environment`, `upstream_unavailable`; on the runner `not_proxied`, `relay_failed`, `body_too_large`) and the changed `container.start` (`proxy_port`, `docker_files_not_visible`, `proxy_port_in_use`, `proxy_start_failed`), with the fixtures in `fixtures/v1/proxy/` and the setup steps `session_holds_machine` and `upstream_answers`. The Go conformance test fails for a fixture that drives no exchange unless it is on its `gatewayOnly` list (none is). The dev `local` adapter keeps its binary and state in `RUNNER_LOCAL_DIR`, a directory of the machine mounted at the same path, so the daemon sees them. Tests: `test/integration/runner_gateway_proxy_test.rb`, `test/services/runners/proxy_test.rb`, `test/services/container_runtime/callback_urls_test.rb`, the §12.3 test extended, and on the Go side `internal/proxy` and `internal/docker/proxy_test.go`. Fix CR round 1 (Alex, 2026-11-10) added: a re-opened relay socket keeps its directory and replaces only `relay.sock`, so a running sidecar's bind mount still reaches it after a restart; the relay refuses a path with an empty, `.` or `..` segment after percent-decoding, or an encoded `/` or a `\`, as `not_proxied`; a relay or a `network: host` listener that can't be served again after a restart stops the session's agent container (no retry); the gateway drops the headers a `Connection` header names, both ways, releases its database connection before the forward, and logs a runner that disconnects mid-answer at info; the sidecar and the relay read a request body within 30 s (`408 body_timeout`), with no limit on the answer or on concurrent calls; the adapters take the callback addresses only from the session's runtime (`callbacks:` and `otel_endpoint:` required, no hosted fallback); `MCP::SessionKey.lookup` resolves an MCP key for both `MCPController` and `Runners::Proxy`, and each key's header is its `SessionKey` module's `HEADER`. The `network: host` port per session is accepted (Alex, 2026-11-10). Fix CR round 2 (Alex, 2026-11-10) added: `ContainerRuntime.callback_url(name, session)`, one call for a callback address; the proxy's ports in `Settings.runners.proxy`, overridable by environment variables, with the sidecar's port sent in `container.start`'s `proxy_port` too, so the host runner has no port setting; the gateway's 900 s read timeout kept and stated in `PROTOCOL.md` §5.8 (an answer silent that long is cut); a sidecar watcher that re-subscribes to Docker's wait with a backoff from 1 s to 30 s after a broken stream, and inspects the sidecar in between; `Route#allows?` refuses a decoded `\` as the relay does; the relay passes one trailing slash (`/mcp/`), as hosted does; `CallbackUrls.hosted_all` removed, and no `workflow_config = {}` default on the paths that need `:otel_endpoint`. Fix CR round 4 (Alex, 2026-11-10) added: a host runner whose `Environment.Resume` can't list the containers exits before polling, with a failure the service manager restarts; a sidecar that exits stops the agent before its log tail is read, under `SidecarLogTimeout`, and a stopped sidecar found by `Resume` is logged with its real exit code; `Runners::Proxy` decodes path segments strictly, so a malformed `%` escape or octets that aren't UTF-8 are `route_not_allowed`, not a 500. Fix CR round 5 (Alex, 2026-11-11) added: a Docker wait result that carries an error is treated as a failed wait, not a sidecar exit, so the sidecar is inspected and waited for again; the host runner narrows its state directory to `0700` at start, and needs an operator when it can't; the relay takes the logged route before the query and logs a transport failure without its URL; `Runners::Proxy.settings_problems` refuses a `network: host` port range that includes an image port; a raw octet outside ASCII in the path is `route_not_allowed`. Go's transports adding `Accept-Encoding: gzip` and a `User-Agent` is kept: the agent gets the same content, and nothing breaks today. |
| 8c | 2 | **`check-in`, and output, files and the terminal log over 1 MiB through an upload to a signed URL (Alex, 2026-11-11).** The live-log chunks are not built (§6.5, §6.9.4): a runner session's terminal is read through `exec` and `capture-pane`, as hosted; `Sessions::LiveLogReader`, `get_session_log`, the monitor's snapshot (`Sessions::Snapshot::ExecSource`) and `AuthErrorDetector` stay as they are, and the live view comes with the tunnel (row 16). Not built: the `local` log driver, the follow of the container's log, `POST /runner/v1/sessions/:id/log` and `session_live_log_chunks`. `POST /runner/v1/heartbeat` moved to row 12, which records heartbeats and derives machine health from them: nothing reads one before. **Built:** (1) `POST /runner/v1/check-in` for `manual` (§6.2): the host runner calls it after every start; `Runners::CheckIn` writes the `X-Aixle-Runner-Version` (and protocol) it is sent to `runner_environments.runner_version`, which until then kept the version the machine registered with, so a machine that updated itself (row 10) shows its new version, and the os, arch and facts it reports; the answer carries the environment, the config (`upload_max_bytes`) and `update` under row 10's rule, and a runner below `min_version` is refused at it (§14.4). (2) Uploads to a signed URL (§6.4, `PROTOCOL.md` §6.5): the platform issues a slot per output with the `exec` and `read_file` ops (`Runners::ResultUploads`, into the `cache` storage, S3 presigned; the filesystem storage issues none, a known limitation that the cleanup's report names), with a budget that fits the largest upload added to the op's deadline, up to `Settings.runners.upload_limit` (32 MiB); the result names the upload; the platform reads it, removes it, and leaves what no result claims to the `cache/` lifecycle rule. With them, on S3, the cleanup collects whole, as on hosted, a terminal log (replacing the `logs` tail fallback of 8a, Fix CR round 7), the agent's session logs and the outputs over 1 MiB. (3) `PROTOCOL.md` §5.9 and §6.5 with their fixtures (`check_in/`, `ops/exec_upload*`, `ops/read_file_upload`), and the Go conformance test requires a driven exchange per fixture, unless the fixture is on its `gatewayOnly` list with a reason (from row 8; the list is empty). The bootstrap-token exchange of `check-in` comes with `coder` and `kubernetes`. |
| 9 | 2 | **Deferred (Alex, 2026-11-11): runners don't change session admission for now; see §10.** Runner sessions are admitted like any other session. |
| 10 | 2 | **Done.** Runner release lane: `runner-release.yml` for `runner-v*` (binaries, `checksums.txt`, GHCR image, from `docker/runner/Dockerfile`), applied by Alex from the task's patch since agents cannot push `.github/workflows/`. The pins file read through `Settings.runners.release` and checked by `Runners::Release` at boot (since task #220 the `runners.release` block of `config/settings.yml`). The `/runner/v1/releases` redirect and checksums endpoints, public and with `schemas/v1/releases.params.json`. The `min_version` refusal at `register` (`400 runner_version_unsupported`), strict SemVer 2.0 for `X-Aixle-Runner-Version` and `protocol_supported` for `X-Aixle-Runner-Protocol`. The "Runner compatibility" and "Releasing the runner" sections in `docs/operations/releasing.md` (§14.2). Self-update with the opt-out (`config.auto_update: false`, `configure --no-auto-update` as `runner_environments.auto_update`, §14.4), moved from task 6. **Decisions (Alex, 2026-11-09):** (1) the first runner version is `0.1.0`, and `1.0.0` comes with the extract or the first customer; (2) a runner learns of an update from the answer of `GET /runner/v1/ops` without ops, which carries `update: {version, sha256}` only while the machine holds no session and runs below `recommended_version`, unless it opted out, and 8c's `check-in` adds the same field; (3) the binary lives in `/var/lib/aixle-runner/bin`, owned by the `aixle-runner` user, `service install` installs it there and points `ExecStart` at it, and an update downloads there, verifies the SHA-256, switches atomically and exits for systemd to restart (`Restart=always`), with no root helper and no package manager; (4) `runner-release.yml` also runs by `workflow_dispatch` as a dry run that builds and checks the binaries and the image and pushes and releases nothing. As built: §14.2 "What v1 has", §14.4 "What v1 has", §6.3. Alex tags `runner-v0.1.0` after this merges, and a follow-up PR pins `0.1.0` and its digests (task #220: done, with the pins moved into `config/settings.yml`). **Fix CR round 1 (Alex, 2026-11-10):** no update reservation, and `update.DownloadTimeout` is 2 minutes, so a `container.start` queued during an update outlives it (§14.4); the release requests carry neither protocol header, and the Go conformance harness checks each fixture header's presence or absence; a `download_url` template that `format` cannot fill in fails boot; a runner version over 255 characters is `invalid_registration` before the `min_version` refusal; the published image sets `AIXLE_RUNNER_NO_SELF_UPDATE=1` and does not update itself (§14.4); the parsed pins are memoized. **Fix CR round 2 (Alex, 2026-11-10):** every answer of the release endpoints, the `400` and `404` refusals included, has `Cache-Control: no-store`; the `update` offer drops `url` and is `{version, sha256}`, since the runner builds its release requests from its own configured platform URL (protocol 1 is unreleased, so nothing is kept for compatibility); `configure` treats `AIXLE_RUNNER_NO_SELF_UPDATE` as `--no-auto-update`, so a machine configured from the published image registers `auto_update: false`; the host runner computes its effective self-update setting once, for the start line and the updater. |
| 11a | 3 | (#242 is its scrub, `reuse_policy`, reset escalation and Return to service.) `Runners::Allocator` and environment state machine, including the self-registering entry path (§5.2): no step 4 on non-`provisionable` types, `reuse_policy` per §7.1, scrub and reset escalation without rebuild, Return to service, and, when scrub lands, the user docs and runner-form copy of §9.4 about what scrub keeps on a company runner (affinity, project binding and Release to company are removed from the plan, Alex 2026-11-13), and the capacity path of §10: a `ContainerRuntime::CapacityError` from the allocator (the runner at `max_environments`, or the provider out of capacity) becomes `capacity_wait` with the wait reason `runner_capacity`, reservation kept. When `env.scrub` is first sent, the removal of its helper container in `runner/internal/docker/scrub.go` gets a bounded timeout under a fresh context, as `container.start`'s removal on failure did in 8a's Fix CR round 6; in 8a its code is unchanged, because `env.scrub` is not sent yet (Alex, Fix CR round 7). |
| 11b | 3 | **Reconciliation.** The running-session summary in the heartbeat (§6.2, §6.7), heartbeat-based `observe` (§5.1), the fixed 15-minute grace (a constant; `reconnect_grace` is not a runner setting, §6.7) and the release of the admission slot when the machine reconnects, or when the machine is revoked (§9.3). Split from task 11 (Alex, 2026-11-13). |
| 12a | 3 | **Done.** "Add machine", brought forward from row 12 on its own (Alex, 2026-11-12, task #225) so that QA can register a staging machine and exercise the runner paths that need a machine's credentials (8c and after). The button on a live `manual` runner's page, company and project, offered under the policy that guards update and revoke (`registration_token?`); `POST .../runners/:id/registration_token` mints a single-use token (1 h) through `Runners::Credentials.mint_registration!` (`Runners::MachineRegistration.issue!`) and returns it once, with the recommended version and, per platform, the binary's URL on the platform's own host and its SHA-256 from the pins; the dialog shows the §6.3 sequence (download and verify, `configure --url --token --name`, `service install` and `service start`) with a choice of `linux-amd64` or `linux-arm64`, a machine name and `--no-auto-update`. A revoked runner offers no button and is refused with `runner_revoked`. The "Adding a machine" section of `docs/user-guide/runners.md`. As built: §6.3. Row 12 keeps the rest. |
| 12b | 3 | **Done.** A Docker choice in "Add machine" (the published image as a host runner: its entrypoint keeps the binary and the state in `AIXLE_RUNNER_DIR`, a directory of the machine mounted at the same path; restart policy `unless-stopped` and the Docker socket; removal by `unregister`) and machines on arm64: the agent container, the sidecar and the scrub container are pulled and created for `linux/amd64`, so an arm64 daemon runs them under emulation until native images (#226). User guide: "Adding a machine". As built: §6.3, §6.9.3, §14.4. Decided by Alex, 2026-11-12. |
| 12c | 3 | **Done.** What 12's Machines table needed to be useful, brought forward on its own (Alex, 2026-11-12, task #231): (1) **liveness**: `runner_environments.last_heartbeat_at` (§2.2) is written by every authenticated request of a machine (polls, op results, `check-in`, token refresh and `register`) at most once every 15 s (`Runners::Liveness.record!`), and `runners.last_seen_at` is raised to it; (2) **the machine's state** for display, online / idle / offline (§2.5), with the op-deadline exception (a machine executing a delivered op is not offline before its deadline) and `failed` / `gone` shown as such; (3) **placement**: `Runners::Machines.take!` skips an offline machine, and a runner whose every registered machine is offline is refused at launch as `runner_unreachable` with a message that names the runner and says its machines are offline; (4) **the Machines section** on the runner page, company and project, read-only (§11). Row 12d took the runner's status from health, `POST /runner/v1/heartbeat` and the `runner_capacity` wait. Row 12 keeps the rest: per-machine Revoke, the first-seen IP in the list, `created_by_id`, the writable-mount acknowledgement, and the `manual` user docs with the §9.7 disclosure and the egress list. `reuse_policy` is task 11a; heartbeat-based `observe` is task 11b. |
| 12d | 3 | **Done.** Cut on its own after 12c (Alex, 2026-11-13, task #241): (1) **`POST /runner/v1/heartbeat`** (§6.2, §6.7): empty body, `204`, recorded through `Runners::Liveness.record!`; the host runner sends one at least every 25 s while an op runs; `PROTOCOL.md` §5.10, the `heartbeat/` fixtures and a driven exchange in the Go conformance test; **the op-deadline exception of 12c is removed** (`RunnerEnvironment.executing_op`, `#executing_op?`, `.reachable`, `delivered_operations`), so a machine is reachable when heard within 90 s; (2) **the runner's status from its machines' health** (§2.5): `ManualAdapter#check_health`, and one periodic check every 60 s (`runner_health_check_workflow`, `Runners::HealthCheck`) that is the only thing setting the status, which is display only: the launch refusal stays on machine availability; (3) **waiting for a free machine** (§10): `take!`'s `CapacityError` carries `runner_capacity`, a wait reason like `cluster_capacity`; (4) docs. Moved to task 11: the running-session summary in the heartbeat and heartbeat-based `observe`. Removed from the plan: affinity and project binding (§7.3, §9.4). |
| 12 | 3 | `manual` end to end: the Machines table (online / idle / offline, first-seen IP, created by; "machines busy/total" in the runners list), per-machine Revoke (which also frees the slot held by a lost machine's session), the writable-mount acknowledgement, and user docs for `manual` (dedicated machine recommended), with the §9.7 disclosure and the egress list (§9.5): in the docs only, not on the runner page. `max_concurrency` stays on the runner, and is not enforced while row 9 is deferred. Not in the plan (Alex, 2026-11-13): the Reset action, Force release, the connection-lost banner, the Administrate dashboards, machine facts in the Machines list, Rotate token and the runner version against `recommended_version` on the runner page, "Start from a clean workspace" for one run, the machine's own cleanup on Revoke, and the ephemeral registration. The operator docs must say that a bind source can't be under the machine's `/tmp` or `/var/tmp` when the runner runs as the service: the unit has `PrivateTmp=true`, so the runner doesn't see those directories and refuses such a bind with `forbidden_mount` (verification round 1 of 6b; accepted as a known limitation, Alex 2026-11-06). From 8b, for `network: host` (Alex, 2026-11-10): **port collisions**: a session's proxy port is `20000 + session id mod 10000`, so two sessions on one machine whose ids are congruent mod 10000, or any other service in 20000 to 29999, can take it, and the session then fails with `proxy_port_in_use`, which is not retryable on that machine; **local access**: the listener is on the machine's own `127.0.0.1`, so any local user or process can reach it, and the host runner adds the environment credential to what it sends. A session key is still required, but the exposure is wider than the sidecar's private network namespace. |
| 14 | 3 | Staging validation per §12.4 (QA task). Record the machine used in the result. |
| 16 | 4 | Interactive tunnel: a session-runner WebSocket relay for ttyd (both instances), the IDE and the watcher through the host runner, plus session page routing. **It also brings the live view of a runner session's terminal** (Alex, 2026-11-11: row 8c builds no live-log chunks, so until the tunnel a runner session's page shows no live log of its own, and the terminal is read through `exec` and `capture-pane` as hosted). Developed against the `local` adapter. Lifts `interactive_terminal: false` on every type. Once it is done, named companies can get the `external_runners` override (§12.2). **Decided (§6.9.5):** the relay is the host runner's and the controller's, not a session runner's: on `manual` and `coder` it reaches the ports through the proxy sidecar, on `kubernetes` the controller dials the pod's IP; per-session ports with `network: host`. **Requirement for this task:** the relay protocol's framing (stream ids, open, close and reset frames, half-close), per-stream flow control with bounded buffers, limits (frame size, concurrent streams), heartbeat and reconnect, cleanup on a browser disconnect, and revocation of every stream when the current session or the viewer's authorization changes (§6.9.5). |
| 17 | 5 | `CoderAdapter` provision, prepare, inject_bootstrap, reset, rebuild, teardown, observe over `Coder::Api`/`WorkspaceService`; the `coder` keys of §2.7 (template, `config.container`) and their validation (§6.8); `install.sh` with SHA-256 verify and the `verify` hook; pooling, `max_environments`, warm-disk affinity; `reuse_policy: fresh` as a new workspace per session. **Decided (§6.9, Alex, 2026-11-06): mode 1, container mode.** v1 supports only Coder workspaces that are virtual machines; the host runner's start check refuses a workspace that is a container on a shared server or a pod, with a clear message, and a Docker daemon that does not see its files (§6.9.7). A workspace runs one session at a time, and a second concurrent session gets another workspace, up to the runner's limit. `reuse` (the default) keeps the workspace warm; `fresh` gives each session a new workspace and deletes it afterwards. The session-side pieces are the host runner's, as on `manual`. |
| 18 | 5 | Staging validation per §12.5 (QA task), on the staging Coder integration configured on the test project and a template it offers at test time. Record the template used and the §12.5 checks (Docker daemon, disk, pruning) in the result. |
| 19 | 6 | Kubernetes: declare `external_runners_kubernetes` (§12.1); `aixle-runner` controller mode, the Helm chart and its `runner-chart-v*` OCI lane in `AixleHQ/aixle-runner` (§14.1), `KubernetesAdapter` over controller ops, registration-token UX, documented agent image sizes. Preceded by the runner extract if it has not happened yet. **Decided (§6.9.2):** the controller runs the session ops through the Kubernetes API (`client-go` exec, `tar` over exec, the pod watch and the log API) behind the session-op handlers of #204, does the check-in for each pod with the bootstrap token from the `provision` op, follows the pod log, creates the proxy sidecar and its per-session proxy key (TLS on the relay, revoked when the session ends), keeps its state on a `PersistentVolumeClaim`, takes leader election with a `Lease` and a controller generation the gateway checks, requires Kubernetes 1.29 and an enforced NetworkPolicy (checked by the validation), and gets the RBAC of §9.6's decided footprint. An `interrupted` op may still run in the pod (§6.9.7). |
| 20 | 7 | `host` execution mode (§6.8): `config.execution_mode: host` and `config.host.cli_source` declared in the §2.7 schema, the host-side CLI with `cli_source` (prototype `docker create` + `docker cp` first), the host-generated CA trusted in three stores and passed into the MITM container, the `NODE_OPTIONS` instrumentation, host-side ttyd/IDE/watcher for the tunnel, the redaction path, the per-session OS user and its scrub (§7.2), toolcache session kits, P2. Likely several tasks when it is cut. **Decided (§6.9, Alex, 2026-11-06): mode 2, on Coder only, with one session per workspace.** The agent CLI runs on the workspace's machine; the services that can run in Docker (`mitmdump`, the callback proxy and the others) run in containers with their ports published on the machine, so that the runner and the agent reach them. The reason: a full development machine with no container around the agent, for example to run `docker compose up`. The workspace is the unit of isolation, so the per-session OS user and the airtight scrub of §7.2, written for `manual`, are not needed. The `host` mode is not planned for `manual`. |
| 21 | 5 | **Runner sessions' default agent images (#229, Alex, 2026-11-12).** `Settings.runners.agent_image_prefix` (default `ghcr.io/aixlehq/flow-`) and `agent_images.<runtime>`, from `RUNNER_AGENT_IMAGE_*`; `ContainerRuntime::RunnerRuntime#runner_image` chooses them (the override, then `agent_images.<runtime>`, then prefix, runtime image and tag), and `AgentBaseStrategy#resolve_image` is unchanged for hosted `agents.*`; the tag is `runners.agent_image_tag` (`RUNNER_AGENT_IMAGE_TAG`, default `latest`; GHCR has no `sha-*` tags); `container.image_override` still wins (§2.7, §6.8). Docs: configuration reference, runners user guide. |
| 22 | 7 | **`{agent}` in `container.image_override` (Alex, 2026-11-12).** `Runners::ConfigSchema` accepts the placeholder `{agent}` and refuses any other, and a value that is not an image reference once replaced; `RunnerRuntime#runner_image` replaces it with `AgentRuntime.fetch(session.agent_type).image` at `container.start`; an override without a placeholder works as before. The runner form's help text says what `{agent}` is replaced with. Default images for runner sessions are not part of it. |

---

## 16. Open items and what would settle them

- **P1, latency of op-per-primitive context assembly. Deferred (Alex, 2026-11-07, decision 5
  of task 8a), with no fixed target.** Task 8a sends one op per runtime call and groups none
  (§15 row 8, requirement 2). The latency is measured much later, once real sessions run. If it
  needs grouping then, it comes only through an explicit runtime method that every runtime
  implements, hosted included, stopping at the first failure; `batch` (§6.4) is that method's
  op, and a tarball op of the `SessionContextService` writes stays possible.
- **P2, usage parity for a CLI on the host.** Not a v1 question: container mode carries the
  image's MITM stack, so every agent runtime is accounted for as on hosted (§6.8, checked in
  §12.4 step 7). It returns with the `host` mode, where `mitmdump` stays in a container but
  the CA trust, the HTTP/2 logger and redaction move to the host. Settled by a prototype in
  task 20.
- **The CLI source in the `host` mode.** Deferred with it (§6.8). Recommendation:
  `host.cli_source: managed` by default. Settled by the `docker create` + `docker cp` prototype in
  task 20: if extracting the pinned CLI from the stock image works across the runtimes,
  there is no second publish lane.
- **Customer pre/post session hooks.** Not in v1, by decision (§7.2). Revisit when a
  customer shows a preparation step that neither the image or template nor the agent
  instructions can express.
- **Coder control planes not reachable from the platform.** Not served in v1.
  Recommendation: the controller mode with a Coder backend (provisioning from inside, the
  same adapter contract). Settled by the first customer who asks for it.
- **Step-level runner.** Deliberately out of scope (§3.3). Revisit if users split
  workflows only to change network.
- **Interactive sessions in the first slice.** Decided in §12.2: the `manual` type
  (phase 3) is non-interactive only, and the tunnel is phase 4, ahead of every second type.
  Named companies get the override only after phase 4, so the first customer-usable slice
  includes interactive sessions (decided 2026-10-30).
- **Billing for external sessions.** Still an open product decision, not a design one.
  The design keeps every answer possible:
  - `runner_id` is recorded on sessions and usage rows;
  - runner sessions draw down `CompanyCapacityUsage` like hosted ones (§10); billing itself stays open.

  What would settle it is the pricing decision for the first non-staging customer. It has
  to be made before trigger 2 of §14.1, and nothing earlier depends on it.
- **Done (task #206): concurrent long-polls per environment.** Each waiting
  `GET /runner/v1/ops` holds a gateway thread for up to 25 s (§6.1), and the per-token
  throttle bounds requests per minute, not outstanding polls, so one buggy or leaked access
  token could have occupied every gateway thread with overlapping polls.
  - **Decided (Alex, 2026-11-02): a newer poll replaces the older poll of the same
    poller.** The older one is answered at once with an empty batch, so its gateway thread
    is freed, and the newer one waits. This suits a runner that polls again after a restart
    or a dropped connection while the gateway still holds its old poll. Refusing the newer
    poll (`409` or `429`) would keep such a runner out until the old poll timed out.
  - **One poller per environment** on every type (§6.9.1, and on `manual` decision 1 of
    6b, Alex 2026-11-05), so the rule is per environment.
  - **What was built:** in `Runners::Operations.poll`, on the existing wake-up channel
    `runner_env_<id>` of 5b, with no lease key in Redis. A poll that is going to wait
    announces itself there once subscribed, and an older waiting poll of the environment
    that hears it answers `{"ops": []}`. A `wait=0` poll announces nothing. Two polls that
    start together may both answer empty; at most one keeps waiting. §6.1 has the details,
    `PROTOCOL.md` §5.4 the wire rule, and `test/integration/runner_gateway_operations_test.rb`
    the tests, since the fixture format cannot hold two requests at once.
  - **The runner never overlaps its own polls** (task 6a): the host runner sends a new
    `GET /runner/v1/ops` only after the previous one has answered, so it does not change.
  - **Known limitation: two pollers with the same credentials.** Two processes that poll with
    one environment's access token, for example a machine whose credentials file was copied to
    another, end each other's polls. Each re-polls at once after an empty answer, so they send
    polls back to back until the per-token rate limit answers `429` and they back off. Ops are
    still delivered, and reuse detection revokes the family at the next refresh. H3, rare: it
    needs a duplicated machine, which is already an error state.
- **Done (task #206): a lost `POST /runner/v1/token` response.** The gateway commits a
  rotation before it answers, so a runner whose response was lost retries with the refresh
  token that was just spent, which `PROTOCOL.md` §4 counted as reuse: the whole family was
  revoked and the machine had to be registered again.
  - **Decided (Alex, 2026-11-06): a 60 s grace window.** Within 60 s of the spend, while
    the pair it issued is unused, presenting the spent token again is a retry: the gateway
    revokes that pair and issues a fresh one of the same family. Anything else is reuse.
    The runner does not change: it already retries a failed refresh with the same refresh
    token (`runner/internal/tokens`, `runner/internal/backoff`).
  - **What was built:** `Runners::Credentials.rotate!` and `retry?`, with
    `runner_credentials.rotated_from_id` naming the refresh credential whose spend issued a
    pair, and an access token's first accepted use recorded in its `used_at`
    (`Credentials.record_use!`, one write per token). §9.2 has the rule and what it costs,
    `PROTOCOL.md` §4 and §5.3 the wire rule, and `fixtures/v1/token/` the scenarios.
  - **Known limitation:** a dropped connection that starts right after the gateway commits
    the rotation and lasts longer than about 30 s still ends in a re-registration (H2,
    rare; §9.2).
  - **Not chosen:** an idempotency key on `POST /runner/v1/token` with a replayable
    response, for which the gateway must keep the issued pair, encrypted; or a runner that
    stops on a network error of `POST /runner/v1/token` with an "outcome unknown" error,
    which still needs a re-registration after a dropped connection.
- **Decided (§6.9), still open:**
  - **Exec through the Kubernetes API on customer clusters.** Settled by task 19's
    validation: the share of ops answered `interrupted` because an in-cluster exec stream
    broke. If it fails sessions, the session ops move into the pod in the split shape A′ of
    §6.9.2, with the same ops and protocol.
  - **Multiplexing a controller's polls.** One long-poll per running pod keeps §9.2 as it is
    and costs a gateway thread each. Folding them into the controller's own poll is an
    optimisation for task 19, with a wider controller credential.
  - **The live text of a runner session.** Settled (Alex, 2026-11-11): `capture-pane`, as on
    hosted. There are no chunks (§6.5), so `LiveLogReader` and `get_session_log` return the
    rendered text they return today, and `AuthErrorDetector` reads it. The live view comes with
    the tunnel (task 16).

---

## 17. Operational gaps a full version needs (outside the seven phases)

Two things are missing for a machine in heavy, long-lived use. Both are **deliberately not
in scope** of this design: they have no phase in §12.2 and no task in §15. They are written
down so the gap reads as a decision, not an oversight, and so the task that eventually
takes them starts from a stated problem.

**Why they are deferred.** The scope of the seven phases is already large, and neither gap
blocks the first proofs of concept. Those run on machines we control and watch (the staging
validations of §12.4 and §12.5, then a few named companies with an override, §12.2), where
an operator notices a rebooted machine or a full disk and acts on it by hand. Both become
necessary before a customer runs a `manual` or reused `coder` environment unattended for
months, so they belong to the GA criteria, not to any one phase. What would bring them
forward: the first named company that runs a machine without someone from our side
watching it.

### 17.1 Machine reboot semantics

What is covered: a **host-runner restart** (self-update, crash, `systemctl restart`). The
session container keeps running, and the restarted host runner finds it again by its labels
(§6.8; on `manual` there is no session runner since task 6b); §12.4 step 10 tests it.
**Decided (§6.9.6):** there is no session runner; the container keeps running, and the host
runner finds the container again by its labels and serves its callback proxy again (§6.8); it
follows no log (§6.5). A reboot **while idle** comes back
as an idle machine (§12.4 step 11).

What is not described: a **reboot of the machine during a session**, which on a long-lived
machine happens regularly (kernel updates, power, maintenance). A full version has to
decide:

- **The session container's restart policy.** Today's implied answer is "no restart": an
  agent process cannot resume mid-turn, and a container that restarts would replay
  `entrypoint.sh` against a half-written workspace. That has to be stated. The host runner
  creates the container with the restart policy `no` explicitly (task 6b) instead of relying
  on the daemon's default.
- **What the interrupted session reports.** It must fail with a clear message ("Machine
  build-01 restarted during the session"), detected when the host runner comes back and
  finds its session container exited by a daemon restart, not left to the reconnect grace
  of §6.7, which would hold the slot and then report a misleading "lost contact".
- **A scrub before `idle`.** The leftover container, the credentials in its layer and the
  outputs on the volume must go through the scrub (§7.2) or, after a failed session, the
  automatic reset, before the machine takes another session. The open part is the order at
  boot: the host runner must not poll for new work until that cleanup has completed.

### 17.2 Disk lifecycle on a long-lived machine

Between sessions a reused environment keeps the pulled agent images, the `aixle-ws-<key>`
volume and the `aixle-cache-<key>-*` volumes (§7.1). Over months:

- **Images accumulate** as the pins in `config/agent_runtimes.json` and
  `container.image_override` move. Nothing removes an image that no current pin references.
- **Caches grow** without a bound. Reset (§7.2) empties them, but nothing triggers it for
  size.
- **`disk_low` is an event with no reaction.** The session runner can send it (§6.2), and
  nothing in this design says what it does. **Decided (§6.9.6):** the host runner sends it,
  from its own check of the daemon's disk; there is no session runner.

A full version needs, scoped by the same ownership rule as scrub (only what Aixle itself
created, selected by label and name, §7.2):

- **retention and garbage collection** for images outside the current pins and a cap on
  the cache volumes, run while the environment is `idle`, never during a session;
- **a defined reaction to `disk_low`**: the runner goes `degraded` with a reason the
  operator can act on ("build-01 has 3 GiB free; Aixle images and caches use 41 GiB"),
  the prerequisite check at check-in (§6.8) refuses new sessions below the 20 GiB floor
  with the same message, and optionally a prune of what Aixle created, offered as an action
  on the Machines table rather than run silently.
