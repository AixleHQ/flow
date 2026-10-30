# External runners for agent sessions — design

**Status:** proposed, revision 5 (design only, no implementation in this change)
**Created:** 2026-10-20 · **Revised:** 2026-10-30
**Task:** #163 "Tech design: external agent runtimes (pluggable runners)"
**Baseline:** `origin/develop` @ `a837d6fd` (the feature flag chain #166–#172 is in)

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
| **`aixle-runner`** | The binary that lives in an environment and speaks the runner protocol. It runs in three modes: `host` (on a `manual` machine or a Coder workspace, owns the environment and its session containers), `session` (PID 1 of an agent container) and `controller` (in a customer cluster, provisioning pods). |
| **Execution mode** | Where the agent CLI runs inside an environment. v1 has one: `container`, the CLI in the stock agent image with `aixle-runner --mode session` as PID 1, on every type. The second value, `host` (services in containers, the CLI on the environment's host), is the last implementation phase (§6.8). Not to be confused with `aixle-runner --mode host`, the process that owns the environment in either execution mode. |
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
`Encryptable` with a new `encryption_key :runners_key` (`Settings.encryption.runners_key`,
with rotation through `runners_key_previous` and `bin/rails encryption:reencrypt`), added
with the first encrypted column (`runner_operations.encrypted_payload`, §15 task 5b). No
secret is ever stored on a workflow, a workflow version, a run or a step.

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
| `max_concurrency` | integer, not null | Pool limit for admission (§10). Must be > 0. |
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
| `project_id` | **Bound project**. Set on first assignment and never changed afterwards (§9.4). |
| `key` | Adapter idempotency key, unique per runner, e.g. `aixle-r12-e7f3a`. It is the Coder workspace name or the pod name. For `manual` it is generated at registration. |
| `external_id` | Coder workspace UUID or pod UID. Null for `manual`. |
| `display_name` | `manual`: the name the operator gave in `aixle-runner configure --name` (default: the hostname). Shown on the runner page. Null for the other types. |
| `origin` | `allocated` (created by `Runners::Allocator`, `coder` and `kubernetes`) or `registered` (created by `POST /runner/v1/register`, `manual`). Decides the entry path into the state machine (§5.2). |
| `ephemeral` | boolean, default false. Reserved for an ephemeral registration (one session, then the runner exits, §6.3). Always false in v1. |
| `state` | §5.2. |
| `reusable` | Copied from the runner's reuse policy when the environment was created. |
| `runner_version`, `protocol_version`, `os`, `arch` | Reported at check-in or registration. |
| `facts` | jsonb: prerequisites found, disk free, the Docker daemon version and agent images present. |
| `auto_update` | `manual`: copied from the runner's `config.auto_update`, overridable per machine with `aixle-runner configure --no-auto-update` (§14.4). |
| `current_session_id` | The `terminal_sessions` row it is executing. At most one (§7.3). |
| `last_workflow_id` | Affinity for warm-cache reuse (§7.3). |
| `last_heartbeat_at`, `checked_in_at`, `sessions_count`, `consecutive_failures` | |
| `reset_requested` | `none`, `reset` or `rebuild` (§7.2). |

**What v1 has so far (§15 task 5a).** `db/migrate/20261030140000_create_runner_environments_and_credentials.rb`
creates `runner_environments` with the columns registration writes: `runner_id`,
`company_id`, `key` (unique per runner, `aixle-r<runner id>-<8 hex>` for a registered
machine), `origin`, `display_name`, `ephemeral` (default false, and `RunnerEnvironment`
refuses true), `state`, `state_reason`, `os`, `arch`, `facts` (jsonb, an object),
`runner_version` and `protocol_version`. Both company and runner keys cascade, and the §2
composite key `(runner_id, company_id) → runners (id, company_id)` ties the environment's
company to its runner's. `origin` has one value so far, `registered`, and `state` has the
two this task sets, `registered` and `gone`; `RunnerEnvironment` keeps them as enumerize
values, and the §5.2 state machine replaces that with task 11. `state_reason` holds
"credential reuse detected" (§9.2). The machine is not marked `failed` yet, because `failed`
arrives with that state machine. The revoked credentials keep it out until then.
`project_id`, `external_id`, `reusable`, `auto_update`, `current_session_id`,
`last_workflow_id`, the heartbeat and check-in columns and `reset_requested` land with their
first reader.

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
`runner_operations` is task 5b.

`runner_operations`: the durable queue between Temporal activities and `aixle-runner`.

| Column | Notes |
| --- | --- |
| `runner_environment_id` or `runner_id` | Environment ops, or controller ops (provision/teardown on `kubernetes`). |
| `terminal_session_id` | Null for environment-lifecycle ops (reset). |
| `sequence` | Monotonic per environment. The runner acks by sequence. |
| `op` | §6.4. |
| `encrypted_payload` | `Encryptable`. Payloads carry credentials (the same data `write_file` carries to a hosted pod today), so they are encrypted at rest and **nulled on completion**. |
| `state` | `pending`, `delivered`, `completed`, `failed` or `expired`. |
| `result` | jsonb, without secrets. Large outputs go to Active Storage and are referenced here. |
| `deadline_at`, `delivered_at`, `completed_at` | |

Completed rows are pruned after 7 days by a sweep in the style of
`ContainerSweepOrphanedResourcesWorkflow`.

`session_live_log_chunks`: `terminal_session_id`, `offset`, `bytes` (redacted with
`Sessions::SecretRedactor` on ingest). These are what `Sessions::LogTail` reads for live
runner sessions (§6.5). They are pruned once cleanup has written the final `SessionLog`.

### 2.4 References from existing tables (all nullable, no default, no backfill)

| Table | Column | Meaning |
| --- | --- | --- |
| `workflows` | `runner_id` | The workflow's declared runner. `NULL` means hosted. It is a real foreign key, not a key in `workflows.config`, so referential checks and "workflows using this runner" are queries rather than JSON scans. It goes into the workflow version snapshot like the other workflow attributes (`docs/design/entity-versioning.md`). |
| `workflow_runs` | `runner_id` | The runner this run resolved to, **frozen at run creation** (§3.3). |
| `terminal_sessions` | `runner_id`, `runner_environment_id` | Which runner and environment the session used. Standalone sessions store the user's pick here directly. |
| `session_admissions` | (existing) `runtime_kind`, `runtime_id` | Already runtime-agnostic. `runtime_kind = "ContainerRuntime::RunnerRuntime"` and `runtime_id = <environment key>` for external sessions. |

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
(§3.3). A runner leaves the database only with its project or company, and
`has_many … dependent: :nullify` clears the references first so that delete is not blocked.
`terminal_sessions.runner_environment_id` waits for its first reader, `RunnerRuntime` (task 8)
or `Runners::Allocator` (task 11), whichever lands first:

```ruby
add_reference :terminal_sessions, :runner_environment, foreign_key: true   # task 8 or 11
```

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
  machine has heartbeated within the last 90 s.
- `degraded`: reachable, but something is wrong: a template parameter is invalid, the
  controller reports missing RBAC, the controller version is below the recommended one, or
  some (not all) of a manual runner's machines are offline. New sessions are still
  admitted, and the reason is shown.
- `unreachable`: the health check failed, the controller has been silent for more than
  3 minutes, or every machine of a manual runner has been offline for more than 3 minutes.
  New sessions fail at launch (§8). Running sessions follow §6.7.

For `manual`, the UI also shows each machine as **online** (connected and running a
session, environment `busy`), **idle** (connected, no session, environment `idle`) or
**offline** (no heartbeat for 90 s, the `unreachable` overlay of §5.2), in the spirit of
GitHub's self-hosted runner list.
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

### 2.7 Runner configuration: the authoritative schema

This is the single list of what a runner can be configured with. Other sections explain
*why* a key exists and link here; when they disagree, this table wins. It is what
`Runners::Adapter.config_schema` (§5.1, §15 task 2) encodes per type.

In the code the table is `Runners::ConfigSchema` (`app/services/runners/config_schema.rb`):
every key below, with its JSON Schema, default, types and whether it arrives later.
`Runners::ConfigSchema.for_type(type)` is the JSON Schema of one type, the one the form
renders from, and `Runner` validates `config` against it for all three types (§15 task 2).
A key that a type requires (`template_id`, `namespace`) is required by that type's schema.
`ephemeral` is refused with "not a config key: it is set per machine at registration".
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
| `reconnect_grace` | integer, seconds, 60–7200 | `900` (15 min) | all | §6.7 |
| `auto_update` | boolean | `true` | `manual`; overridable per machine with `aixle-runner configure --no-auto-update` (`runner_environments.auto_update`) | §14.4 |
| `container.image_override` | string, image reference | null (the stock image of `AgentRuntime`) | all; must be built `FROM` our base image, checked at check-in | §6.8 |
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
| `ephemeral` | boolean | `false` | `manual`. **Not a `config` key**: it is per machine, sent in the `register` body and stored in `runner_environments.ephemeral` | Ephemeral registration (§6.3), not scheduled |

**Not runner configuration, listed so nobody looks for them in `config`:**

- **Helm values of the controller chart** (`rbac.events`, default on; `networkPolicy.enabled`,
  default off; §9.6). The customer sets them at `helm install`; the platform never stores
  them and sees their effect only through the controller's RBAC report.
- **Platform settings** under `Settings.runners` (`bootstrap_timeout`,
  `max_consecutive_failures`, `op_output_limit`, `release`). They are the same for every
  runner and are not editable per runner.

---

## 3. Scope resolution and precedence

### 3.1 Visibility

A project can see its own runners plus its company's non-deleted runners:
`Runner.visible_for_project(project)`, the same shape as `Integration.visible_for_project`.
A runner is never visible across companies. System workflows (`scope_type: "System"`, e.g.
Aixle Builder) have no project, so they can only use `hosted`.

### 3.2 Who may do what

| Action | Company runner | Project runner |
| --- | --- | --- |
| List and view status | Any active company member | Anyone with `project_accessible?` |
| Create, edit, rotate token, disable, delete, revoke | Company `admin?` | Company `admin?` **or the project owner** |
| Reset or rebuild an environment | Company `admin?` | Company `admin?` or the project owner |
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
writes, `project_accessible?` for reads). Unlike the integrations controller's
`project_id.nil?` check, the company-scope rule lives in the policy.

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
| `provisionable` | true | **false**: the platform cannot create a machine | true | true | Allocator step 4 (§7.3), admission copy (§10) |
| `rebuildable` | n/a | **false**: we do not own the machine | true | n/a (ephemeral) | Reset escalation (§7.2), cross-project rebinding (§9.4) |
| `reusable` | false | true | true | false (v1) | Lifecycle (§7), affinity, scrub |
| `persistent_disk` | false | true | true (mounted volumes only) | false (a PVC option is later) | Reset semantics, UI copy |
| `human_accessible` | false | true (it is the operator's machine; there is no link to open) | true (Coder's own SSH, web terminal, IDE) | false | "Open in Coder" link on the session, when there is a link |
| `interactive_terminal` | true | false until the tunnel (§12.2, phase 4), then true | same | same | Not declared or read in v1. Its first reader comes with the tunnel (§15 task 16); until then interactive standalone sessions refuse every external runner unconditionally (below) |
| `max_concurrency` | admission pools | `runners.max_concurrency` | `runners.max_concurrency` | `runners.max_concurrency` | Admission (§10) |
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
    def self.config_schema                           # => JSON schema the form and #validate_config use
    def capabilities(runner)                         # => Runners::Capabilities

    # Runner-level
    def validate_config(runner)                      # => [errors] — template exists, namespace valid, …
    def check_health(runner)                         # => Runners::Health(status:, reason:, facts:)

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

**What v1 has so far** (§15 task 2): `Runners::Adapter` with `type`, `config_schema`,
`capabilities` and `validate_config`, and a registry that holds `Runners::ManualAdapter`
only. A type without an adapter cannot be created: `Runners::Adapter.for` raises
`Runners::Adapter::UnavailableType`, and the controllers refuse a `coder` or `kubernetes`
runner as "not available yet" until task 17 and phase 6. `ManualAdapter#validate_config`
checks the `config.container` rules one key's schema cannot express: `home_mount.path`,
the acknowledgement of every writable host mount, and `docker_socket` behind
`allow_privileged_mounts`. `Runners::Save` runs it on create and update and saves nothing
when it returns errors. `check_health` is not there yet: on `manual` health comes from
machine heartbeats, so it lands with task 12. The environment lifecycle methods land with
the tasks that call them.

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
| `validate_config` | `config.container` options only (§2.7, §6.8) | Template exists, parameters valid, integration visible, `config.container` options | Namespace, `config.container.resources` and `image_override` valid |
| `check_health` | Derived from machine heartbeats (§2.5). No outbound call | Coder API reachable, template valid | Controller heartbeat and its RBAC report |
| `provision` | **No-op.** Never called: `provisionable: false` | `WorkspaceService` create from `config.template_id` with `config.parameters`, name = `key` | `controller.provision {key, image, resources, labels}`. The controller creates Pod, ServiceAccount and Secret (bootstrap) in its namespace |
| `prepare` | **No-op**, returns `:ready`: the machine is the operator's and is already running | Await build. Start the workspace if it is stopped | Await pod `Ready` (controller reports) |
| `inject_bootstrap` | **No-op**: the operator installed the runner (§14.4) | `Coder::SshRunner`-style `coder ssh <ws> -- sh -s` with the install script **on stdin**, so the token never appears in argv or `ps`. It installs and starts `aixle-runner --mode host` (§6.8) | No-op: the controller mounts the bootstrap Secret and the pod's init container installs the runner (§9.6) |
| `reset :reset` | Runner op `env.reset`: **scrub ops only**, the full wipe of §7.2 | Runner op `env.reset` (§7.2) | n/a (ephemeral) |
| `reset :rebuild` | **Does not exist** (`rebuildable: false`) | Delete and recreate the workspace from the template | n/a |
| `teardown` | **No-op** on the machine. Removing a machine is `aixle-runner unregister` or Revoke (§9.3); the platform side only marks the row `gone` | Delete the workspace (or stop it, per `config.on_release`) | `controller.teardown {key}` |
| `observe` | **Heartbeat-based**: `:running` while heartbeats arrive, `:unknown` after 90 s, never `:missing` (we cannot tell a powered-off machine from a removed one) | Workspace build status | Controller's pod list |

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
                    scrub/reset │ fails                                              │ release (ephemeral)
                                │                                                    │ or reset_requested=rebuild
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
`manual` environment always takes the `resetting`/scrub arm, never the ephemeral
teardown arm, whatever `reuse_policy` says (§7.1). The one future exception is an
`ephemeral` registration (§6.3), which goes from release straight to `gone`.

- One session at a time per environment (`concurrency_per_environment = 1`). `busy` holds
  `current_session_id`.
- `failed` environments are torn down by the reconciler and never reused, except on
  `manual`: a failed machine cannot be torn down by us, so it stays `failed`, out of
  rotation, until the operator fixes it and presses **Return to service**, which runs a
  reset (§7.2), or unregisters it.
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
# => session.runner_id ? ContainerRuntime::RunnerRuntime.new(session) : ContainerRuntime.build
```

The hosted branch is the existing expression, character for character.

| Phase | Hosted (unchanged) | `RunnerRuntime` |
| --- | --- | --- |
| `pull_image` | Pull the image | Once an environment is assigned: `image.ensure`, the host runner pulls the agent image by digest (`manual`, `coder`). On `kubernetes` it is a no-op, because the kubelet pulls |
| `create_container` | Create the pod | `Runners::Allocator.acquire(session)`: assign an idle environment (§7.3), or, on a `provisionable` type, create a `requested` row and call `provision` + `inject_bootstrap` for it. Raises `ContainerRuntime::CapacityError` when at `max_environments` (or, on `manual`, when every registered machine is busy), so the **existing** `capacity_wait` loop in V2 handles it |
| `start_container` | Service, IngressRoute, wait ready | `prepare`, then wait for check-in with activity heartbeats (immediate on `manual`, whose machine is already checked in). Raises a diagnosed failure on `bootstrap_timeout`. On `manual` and `coder` the host runner then gets `container.start` (§6.8) and the activity waits for the session runner inside the container to report ready |
| `exec` | `before_exec` context assembly + tmux launch via `runtime.exec`/`write_file` | Same strategy code. Each primitive is a runner op |
| (await `container_finished`) | Unchanged | Unchanged. `finish_session` reaches the platform through the runner's proxy (§6.6) |
| `cleanup` | Collect logs and outputs, remove the pod | Same collection via `read_file`, then `Runners::Allocator.release(environment, outcome)`, which scrubs, resets or tears down (§7) |

`SessionRuntimeOperation` (AD-5) keeps its meaning. `create_container`/`start_container`
stay replayable because `provision` is idempotent on `key`. `exec` stays non-replayable
because it launches the agent.

---

## 6. Runner protocol (v1)

### 6.1 Transport

**Decision:** HTTPS long-poll plus HTTPS POST, JSON bodies, on port 443 to the platform's
gateway. There is no WebSocket in v1.

GitHub's self-hosted runner works the same way, for the same reasons. It goes through
corporate HTTP proxies (`HTTPS_PROXY` is honoured) and TLS-inspecting middleboxes. The
gateway stays stateless: any gateway process can serve any runner because the queue is
`runner_operations` in PostgreSQL. A WebSocket would pin an environment to one process and
need a fan-out layer to deliver an op from a Temporal worker to whichever process holds the
socket. Latency is still adequate: a poll returns the moment an op is enqueued, woken by
PostgreSQL `LISTEN/NOTIFY` on `runner_env_<id>`. WebSockets come in only for the
interactive tunnel (§12.2, phase 4), where they are unavoidable.

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

The gateway's Puma caps request bodies at 64 KB (`http_content_length_limit`). It answers
a plain `413` before it reads a body over the cap, chunked bodies included, so an oversized
body never reaches Rails.

The controllers are `RunnerGateway::V1::*` (`app/controllers/runner_gateway/v1/`),
`ActionController::API` with no cookie session and no CSRF. Before anything else, every
request is checked for:
- **the protocol header:** `X-Aixle-Runner-Protocol: 1`, otherwise
  `400 unsupported_protocol`, with a message that names the version the gateway speaks;
- **the version header:** a semver `X-Aixle-Runner-Version`, otherwise
  `400 invalid_runner_version`.

Rack::Attack throttles `/runner/v1/*` at 600 requests a minute per bearer token (keyed on
its digest) and at 3000 a minute per IP, so a client that sends a new bearer value on every
request is still bounded, and `register` at 30 a minute per IP (§9.5).

### 6.2 Endpoints

All requests are `Authorization: Bearer <token>`,
`X-Aixle-Runner-Protocol: 1`, `X-Aixle-Runner-Version: <semver>`.

| Endpoint | Caller | Purpose |
| --- | --- | --- |
| `POST /runner/v1/register` | controller, `manual` host runner | Exchange a registration token for long-lived credentials: controller credentials (`kubernetes`), or environment credentials for the environment the call creates (`manual`). Body: `{name, os, arch, facts, ephemeral: false}`. `ephemeral: true` is defined and refused in v1 with `ephemeral_not_supported` (§6.3). |
| `DELETE /runner/v1/registration` | `manual` host runner | `aixle-runner unregister`: marks the environment `gone` and revokes its credential family. Refused with `409 busy` while a session runs, unless `--force`, which fails that session. |
| `POST /runner/v1/check-in` | host runner (`coder`, and `manual` after every start), session runner (`kubernetes` pod) | Coder and Kubernetes: exchange the bootstrap token for environment credentials. `manual`: authenticated with the environment credential, no token exchanged. All: report version, os/arch and facts. The response carries config (heartbeat interval, proxy routes, log limits) and `update` (§14.4). |
| `POST /runner/v1/token` | both | Refresh-token rotation. |
| `GET  /runner/v1/ops?after=<seq>&wait=25` | both | Long-poll. Returns ops with `sequence > after`, batched. An empty 200 after `wait` doubles as the heartbeat. |
| `POST /runner/v1/ops/:id/result` | both | Op outcome. Idempotent on op id. |
| `POST /runner/v1/sessions/:id/log` | session runner | Append live log chunk `{offset, bytes}`. |
| `POST /runner/v1/sessions/:id/events` | session runner | `agent_exited {code}`, `agent_started`, `disk_low`, … |
| `POST /runner/v1/heartbeat` | both | Only when no poll is outstanding, e.g. while uploading. Includes the running-session summary. |
| `ANY  /runner/v1/proxy/:route/*` | session runner | The callback proxy (§6.6). |
| `GET  /runner/v1/releases/:version/:os-:arch` | both | The binary's documented, stable URL. It answers `302` to the GitHub Release asset and sends the expected SHA-256 in `X-Aixle-Runner-Sha256` (§14.3). |
| `GET  /runner/v1/releases/:version/checksums` | both | The `sha256  file` list for that version, from `config/runner_release.yml`. |
| `GET  /runner/v1/install.sh` | bootstrap | Install script used by `inject_bootstrap` (`coder`). `manual` operators download the binary directly (§6.3). |

**What v1 has so far (§15 task 5a):** `register` for a `manual` machine,
`DELETE registration` and `token`. Every authenticated request then checks, in order:
1. the bearer token, which must be of the endpoint's kind (`registration` for `register`,
   `refresh` for `token`, `access` otherwise), unrevoked, not of a `gone` environment and,
   for a registration token, unused. It must also be unexpired, except that a spent refresh
   token passes even past its own expiry, so that `token` can detect its reuse. Anything
   else is `401 invalid_token`, before the runner or the flag is looked at;
2. the runner's status. A revoked or deleted runner is `401 runner_revoked`. The check is
   cached for 5 s in `Rails.cache` (§9.2);
3. the `external_runners` flag for the runner's company. Off is `403 runners_disabled`, and
   the credentials stay valid (§9.3).

Refusals are `{error, message}`, with `error` the machine-readable code, and the protocol's
bodies are snake_case.
- **`register`** takes the registration token. It answers `201` with
  `{environment: {id, key, display_name, state}, access_token, access_token_expires_at,
  refresh_token, refresh_token_expires_at}` and `Cache-Control: no-store`.
  - `ephemeral: true` is refused with `422 ephemeral_not_supported`, and an invalid body
    (a blank `name`, `facts` that is not an object) with `422 invalid_registration`. Neither
    spends the token.
  - The token is spent under a row lock, so two machines racing on one token create one
    environment.
- **`token`** takes the refresh token as the bearer and answers `200` with the same token
  fields. A second use of a spent refresh token answers `401 credential_reuse_detected`
  (§9.2), even after that token's own 30-day expiry, because the family it was rotated
  into may still be live.
- **`DELETE registration`** takes the access token and answers `204`. It refuses nothing
  else yet. The `409 busy` refusal and `--force` come with the first task that assigns a
  session to an environment, because no session can run on one before that.

The other rows of the table are later tasks: `ops` and op results in 5b, `check-in`,
`heartbeat`, session logs and events and the proxy in task 8 and later, and the releases
endpoints and `install.sh` in tasks 10 and 17.

### 6.3 Registration and tokens (summary; full model in §9.2)

- **Kubernetes:** an admin creates the runner, the UI shows a one-time **registration
  token** and a ready-to-paste `helm install` command. The controller calls `register`, the
  token is consumed, and the controller gets an access/refresh pair.
- **Manual**, modelled on GitHub self-hosted runners, and the same `register` call and
  credential lineage as the Kubernetes controller. Only the operator-facing instructions
  differ. "Add machine" on the runner page mints a **short-lived, single-use** registration
  token (1 h) and shows a copy-paste sequence:

  ```sh
  # 1. Download and verify (the digest is from config/runner_release.yml, §14.3)
  curl -fsSLo aixle-runner https://flow.aixle.com/runner/v1/releases/1.4.0/linux-amd64
  echo "<sha256>  aixle-runner" | sha256sum -c -
  sudo install -m 0755 aixle-runner /usr/local/bin/aixle-runner

  # 2. Register this machine (consumes the token)
  sudo aixle-runner configure --url https://flow.aixle.com --token <registration token> --name build-01

  # 3. Run as a service that survives logout and reboot
  sudo aixle-runner service install && sudo aixle-runner service start
  ```

  `configure` calls `register`, which consumes the token, creates the environment row
  (§5.2) and returns an environment access/refresh pair that the runner stores locally
  (`/var/lib/aixle-runner/credentials`, mode `0600`, owned by the runner's own user).
  `service install` writes a systemd unit running `aixle-runner --mode host` as a
  dedicated `aixle-runner` system user, which it creates and adds to the `docker` group
  (§9.7). A machine needs one token each; a token that leaked after use opens nothing.
  Removal is `aixle-runner unregister` on the machine, or Revoke on the runner page (§9.3).
- **Ephemeral registration, defined but not in v1.** `register` takes
  `ephemeral: true` (`configure --ephemeral`, GitHub's `--ephemeral`): the environment
  takes one session, then the platform marks it `gone`, revokes its credentials, and the
  runner exits. That lets a customer script their own scaling (a VM per session from
  their own autoscaler). v1 refuses the flag, but the field, the `ephemeral` column (§2.2)
  and the release arm in §5.2 are there, so adding it needs no protocol bump.
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
development call it. There is no endpoint and no UI: "Add machine" and its endpoint are
task 12. Tokens carry a prefix by kind (`arreg_`, `aracc_`, `arref_`), so a leaked one is
recognisable. Only SHA-256 digests are stored. The plaintext appears only in the call or
response that issues it, and the tokens travel in the `Authorization` header, which is never
logged. `Runners::Registration` (`app/services/runners/registration.rb`) creates the
environment on `register` and, on unregister, marks it `gone` and revokes every credential
of that environment.

### 6.4 Operations

Each op is `{id, sequence, op, session_id?, deadline_at, payload}`. Results are
`{status: ok|error, exit_code?, stdout?, stderr?, data?, error?: {class, message}}`.

| Op | Maps to | Notes |
| --- | --- | --- |
| `exec` | `BaseRuntime#exec` | `{cmd: [..], env, cwd, user, timeout, stdin?}`. Output is capped at `Settings.runners.op_output_limit` (default 1 MiB). Anything larger is uploaded and referenced. |
| `write_file` | `#write_file` | `{path, content(b64), mode, uid, gid}`. Credentials travel this way, as they do to hosted pods today. |
| `read_file` | `#read_file` | Small files inline. Large files are uploaded by the runner to a signed upload URL in the result. |
| `batch` | (new, internal) | An ordered list of the above, executed until the first failure. `RunnerRuntime` coalesces consecutive `write_file`s from `SessionContextService` into one batch, which removes most round trips. |
| `status` | `#container_status` | `running`, `starting`, `terminated` or `missing` for the session's agent process. |
| `logs` | `#container_logs` | Tail of the terminal-output file. |
| `session.start` / `session.stop` | The tmux launch and kill done through `exec` today | v1 keeps the strategy's tmux commands (through `exec`). These ops are reserved for when the strategy stops shelling out. |
| `image.ensure` | `pull_image` | Host-runner op (`manual`, `coder`): `{image, digest}`. The host runner pulls the agent image by digest. |
| `container.start` / `container.stop` | `create_container` + `start_container` / `cleanup` | Host-runner ops (`manual`, `coder`): `{image, digest, name, env, mounts, network, pid, resources}`. The runner starts the agent container with `aixle-runner --mode session` as PID 1, or stops and removes it (§6.8). |
| `env.scrub` / `env.reset` | §7.2 | Host-runner ops. On `manual` these are the whole reset story, since there is no rebuild. |
| `provision` / `teardown` / `observe` | Kubernetes adapter | Controller-only ops. |

`toolcache.ensure` (revision 3, for `native` mode) is removed. If the `host` mode needs it,
it comes back in phase 7 under a protocol minor addition, which `[N-1, N]` support absorbs
(§14.4).

The `deadline_at` of an op is the activity's start-to-close timeout. A runner that receives
an op after its deadline reports `expired` and does not execute it.

### 6.5 Logs and output

- **Live:** the runner tails the terminal-output file (the `pipe-pane` file hosted pods
  already write, `/tmp/terminal_output.log`) and POSTs chunks every 2 s or 64 KiB. For
  runner sessions, `Sessions::LiveLogReader` reads `session_live_log_chunks` instead of
  `exec`-ing `tmux capture-pane`, so polling the live log costs the environment nothing.
  `Sessions::NoOutputWatchdog` reads the same chunks.
- **Final:** unchanged. `before_cleanup` runs `collect_logs`, `collect_terminal_output` and
  `collect_outputs` (`find /workspace/outputs`, `read_file`) through `RunnerRuntime`.

### 6.6 The callback proxy

Today the agent calls back to `internal_base`. That covers `/action_mcp` (MCP with
`X-Session-Key`), `/agents/credentials{,/refresh}`, `/agents/git/credentials`,
`/azure/git/credentials`, `/cloud/aws/credentials`, container asset downloads and OTLP
ingest. None of these are reachable from a customer network, and they should not become
public.

**Decision:** the session runner listens on `127.0.0.1:<port>` next to the agent (inside
the agent container, on every type) and forwards an
**allow-list of routes** through `ANY /runner/v1/proxy/:route/*`. The env vars
the strategy sets (`Settings.mcp.server_url`, `CREDENTIAL_SYNC_URL`,
`AIXLE_GIT_CREDENTIALS_URL`, …) are rewritten to `http://127.0.0.1:<port>/<route>/…` by
`RunnerRuntime`. That is a `RunnerRuntime` concern, so no strategy change is needed. The
gateway:

1. authenticates the environment credential,
2. checks that the session key in the forwarded request (`X-Session-Key`, `AIXLE_GIT_KEY`,
   …) belongs to the session **currently assigned to this environment**,
3. forwards to the internal endpoint with the request unchanged plus
   `X-Aixle-Runner-Environment`, so those endpoints keep working as they do now.

A session key copied out of an environment is therefore useless anywhere except through
that environment's credential, and only while that session runs there.

### 6.7 Heartbeat, reconnect and resume

- A long-poll or heartbeat every ≤ 25 s counts as a heartbeat. After 90 s without one the
  environment is flagged `unreachable`, and the session page shows "runner connection lost,
  agent still running".
- **The agent keeps running while disconnected.** Its process tree belongs to
  `aixle-runner`, not to a request. The runner buffers log chunks locally (up to 64 MiB,
  oldest dropped first and marked with a gap) and queues events.
- **Op execution is at-most-once:** the runner that holds the environment credential keeps a
  local journal (`~/.aixle-runner/journal`) of the op ids it has executed and their results
  for 24 h. That is the host runner on `manual` and `coder`, and the session runner in a
  `kubernetes` pod. A redelivered op returns the
  journalled result without re-executing it. This closes the ambiguous "did my exec run?"
  case that kube-exec has.
- **Resume:** on reconnect the runner refreshes its token if needed, polls with
  `after=<last acked seq>`, flushes buffered logs from their offsets (the gateway
  de-duplicates by offset), and posts the session summary (agent running or exited with a
  code). The platform reconciles: an exit the platform did not know about is handled like a
  dead container today (`DeadContainerScan` semantics) and fails the session with "agent
  exited (code N)" unless `finish_session` already ran.
- **Grace:** after `config.reconnect_grace` (default 15 min, configurable per runner up to
  2 h, §2.7) without contact, the session fails with *"Runner environment lost contact for 15
  minutes"*, and the environment is marked `failed` and torn down if the adapter can still
  reach it. The admission slot stays held until the adapter confirms teardown or `observe`
  returns `missing`, per AD-4 "unknown creation retains capacity", and is otherwise released
  by the reconciliation sweep. On `manual` there is no teardown and `observe` never says
  `missing`: the slot is released when the machine reconnects and reports the session's
  container gone (it then gets the automatic reset of §7.2 before it is `idle` again), or
  when an admin presses Force release on the runner page.
- `finish_session`/`fail_session` go through the proxy (§6.6). If the proxy is down at that
  moment, the MCP call fails, the agent retries as it does on any network error, and the
  runner keeps the agent alive until the call lands or the grace expires.

### 6.8 What runs inside the environment: container mode only in v1

**Decision:** in v1 the agent runs in **the stock agent image**
(`AgentRuntime.fetch(agent_type).image`) on every type, `manual`, `coder` and `kubernetes`
alike. `aixle-runner --mode session` is PID 1 and supervises the image's `entrypoint.sh`.
This is **container mode**, and it is the only execution mode in v1. A Docker daemon is a
prerequisite on `manual` and `coder`, reported at check-in (§8) rather than discovered
mid-session. Revision 3's Coder `native` mode is dropped (see "Dropped" below).

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

- **Kubernetes:** session pods run the stock image with `aixle-runner` as PID 1. The kubelet
  is the container runtime. Of the `config.container` options, `resources` and
  `image_override` apply (§2.7); `image_override` is allowed only for images built `FROM`
  our base image. The host-access options do not exist on this type: a pod has no machine
  of the customer's to share.
- **`manual` and `coder`: a host runner and a session runner.**
  - The **host runner** (`aixle-runner --mode host`) is installed by the operator
    (`manual`, §6.3) or by `inject_bootstrap` (`coder`). It holds the environment credential
    and the journal, and polls the environment's ops. It executes `image.ensure`,
    `container.start` / `container.stop`, `env.scrub` and `env.reset` itself. Per session it
    starts one container named `aixle-<environment key>-<session id>`, labelled
    `aixle.com/environment=<key>` and `aixle.com/session=<id>`, from the agent image pinned
    by digest. Its own binary is bind-mounted read-only as the container's PID 1 in
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
| `image_override` | none | An image built `FROM` our base image instead of the stock one, prerequisites checked at check-in. |

The container receives the same environment variables the hosted pod spec sets for the
image, with the callback URLs rewritten to the session runner's local proxy (§6.6). How
that env is assembled is a `RunnerRuntime` concern, so there is no strategy change.

**Image size.** Agent images are pulled from GHCR on the machine (or through the customer's
registry mirror) and kept on its disk between sessions, so only the first session on an
environment pays for the pull. `image.ensure` reports the pull time, and the bootstrap
timeout counts it. If a Coder template prunes Docker images on a schedule, the warm-image
check of §12.5 is read with that counted.

#### Deferred to the last phase (7): the `host` execution mode

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

---

## 7. Lifecycle and reset

### 7.1 Fresh vs. reused, and what `reuse_policy` means per type

The agent container (or pod) is **fresh per session on every type**. `reuse_policy` decides
what survives around it, and that differs per type:

| Type | `reuse` | `fresh` |
| --- | --- | --- |
| `kubernetes` | Not offered | Always: a new pod per session. The image provides the warm state. |
| `coder` | Default. The workspace is kept: the pulled agent image, the `aixle-ws-<key>` volume with its repository clones, and any cache mounts stay warm. | A new workspace is created per session and destroyed after it, for hosted-like isolation with the cold start accepted. |
| `manual` | Default. The machine keeps the pulled images, the workspace volume and the cache volumes. Scrub after every session. | **Cannot mean a new machine.** It means the full wipe scope per session: a new container (always), a **Reset** of the workspace and cache volumes after every session instead of a scrub (§7.2), and, once host-side execution exists (phase 7), a new OS user. Pulled images stay; they are public, pinned by digest and identical for every session. The form says: "Fresh on a manual runner wipes everything Aixle put on the machine after every session. It does not give you a new machine." |

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
| **Reset** (`env.reset`) | Scrub, plus the `aixle-ws-<key>` volume and every `aixle-cache-<key>-*` volume, including repository checkouts | Pulled images. On `manual`, everything on the machine that Aixle did not create | Manually ("Reset" on an environment); forced for one run ("Start from a clean workspace" on the run drawer or session form, sets `reset_requested=reset` on the assigned environment before `exec`); **automatically after a failed session** on that environment; on `manual` with `reuse_policy: fresh`, after every session |
| **Rebuild** (adapter `reset level: :rebuild`, `coder` only) | Everything: the workspace is deleted and re-created from the template | Nothing | Manually; automatically when a scrub or reset fails, after `runners.max_consecutive_failures` (default 3) failed sessions in a row on one environment, or when the environment is needed by another project (§9.4) |

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

### 7.3 Allocation and concurrency on reused environments

`Runners::Allocator.acquire(session)`, under a `FOR UPDATE SKIP LOCKED` lock on candidate
rows:

1. An `idle` environment of this runner bound to the session's project with
   `last_workflow_id = session.workflow_id` (warm-cache affinity).
2. Otherwise any `idle` environment bound to this project.
3. Otherwise any `idle` unbound environment.
4. Otherwise, **only if the runner is `provisionable`** and
   `count(non-gone environments) < max_environments`, insert a new `runner_environments`
   row in `requested`, bound to the session's project, in the same transaction. After
   commit, call `adapter.provision` for it (§5.1).
5. Otherwise raise `CapacityError`, and the session waits in the existing admission
   capacity wait.

**On `manual`, step 4 does not exist.** The allocator cannot create a machine, so when
every registered machine bound to (or available to) the project is busy, offline or
`failed`, the session **queues** in step 5 until one comes back to `idle`. Capacity is
exactly the machines the operator connected (§10).

**Two overlapping runs of the same workflow:** the second one gets **another environment**
(step 2–4), never the same one. If the pool is full it **queues**. It is never refused, and
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
| Runner `unreachable` (health or controller silent) | Launch | Fails, `runner_unreachable` | "Runner "X" is unreachable since 14:02: controller has not connected for 6 min." |
| Session mode not supported by the runner (an interactive standalone session, §4) | Selection | Refused | "Runner "X" can't run interactive sessions yet." |
| At `max_concurrency` | Admission | Queued, wait reason `runner_limit` | Shown as queued with the runner named |
| At `max_environments`, or provider capacity (Coder quota, unschedulable pod) | `create_container` | `capacity_wait`, wait reason `runner_capacity`, reservation kept (session-admission §7) | "Waiting for capacity on runner "X"." |
| `provision` fails (template error, image pull, RBAC) | `create_container` | Diagnosed failure, environment `failed` | Provider message, e.g. "Coder: template parameter `instance_type` invalid" |
| Runner never checks in | `start_container` after `runners.bootstrap_timeout` (default 10 min, 15 for `coder`) | Fails, environment `failed`, teardown | "Environment started but aixle-runner did not check in within 10 min. Check egress to flow.aixle.com:443." plus the last bootstrap output the adapter captured |
| Prerequisites missing | Registration (`manual`) or check-in | Refused or fails, environment `failed` | "Machine build-01 has no reachable Docker daemon (aixle-runner needs Docker API ≥ 1.41)." |
| External runners not enabled for the company (no `external_runners` override, §12.1) | Selection, launch, every gateway request | Refused; launches fail with `runner_unavailable`; the gateway answers `403 runners_disabled` | "External runners are not enabled for this company." |
| `manual`: no machine registered yet, or every machine offline | Launch | Fails, `runner_unreachable` | "Runner "X" has no machine online. Last seen: build-01 at 14:02." |
| `manual`: every machine busy | `create_container` | `capacity_wait`, wait reason `runner_capacity` | "Waiting for a free machine on runner "X" (2 of 2 busy)." |
| `manual`: registration token expired or already used | `register` | Refused, `401 registration_token_invalid` | Printed by `aixle-runner configure`: "This registration token has expired or was already used. Create a new one on the runner page." |
| `manual`: reset fails on a machine | Release | Environment `failed`, out of rotation | Runner page: "build-01 failed to reset: <reason>. Fix the machine and press Return to service." |
| Agent image cannot be pulled | `pull_image` (`image.ensure`) | Diagnosed failure, environment stays `idle` | "Could not pull ghcr.io/aixlehq/…@sha256:…: <registry error>. The workspace needs to reach ghcr.io or a configured mirror." |
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
| Registration (Kubernetes) | Runner creation, or "Rotate" in the UI. Shown once | Single use, expires in 24 h if unused (a GitOps `helm install` can take a review cycle) | Calling `register` once for this runner | Digest only |
| Registration (`manual`) | "Add machine" on the runner page. Shown once, inside the copy-paste command | **Single use, expires in 1 h** if unused | Calling `register` once, which creates **one** environment of this runner | Digest only. One token per machine |
| Controller access / refresh | `register` | Access 1 h. Refresh rotates on every use and becomes invalid after 30 days idle | Polling **controller ops of this runner** (provision, teardown, observe); posting results; minting nothing | Digest only. Refresh-token reuse detection revokes the whole family and marks the runner `degraded` ("credential reuse detected") |
| Bootstrap | Per environment, at `provision` | Single use, 30 min (or `bootstrap_timeout`, whichever is longer) | Calling `check-in` for **this environment** | Digest only. Delivered by Coder SSH stdin or by a k8s Secret the controller deletes after check-in |
| Environment access / refresh | `check-in` (`coder`, `kubernetes`), `register` (`manual`) | Access 1 h, rotating refresh. Invalid the moment the environment becomes `gone` or the runner is revoked. On `coder` and `kubernetes` also when it leaves `idle`/`busy`/`resetting`; a `failed` `manual` machine keeps its credential so it can be returned to service. A `manual` refresh token becomes invalid after 30 days without use, like the controller's | Polling **this environment's ops**; posting logs, events and results for the session **currently assigned** to it; the proxy for that session only | Digest only. On `manual`, stored by the runner in `/var/lib/aixle-runner/credentials` (`0600`, the runner's own user). Reuse detection revokes the family and marks the machine `failed` ("credential reuse detected") |

Every request re-checks the runner's status (cached for ≤ 5 s), so revocation takes effect
within seconds and does not wait for tokens to expire.

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
on its next request, stops its session containers, removes the Aixle-labelled containers
and volumes it created (§7.2), and exits; the systemd unit is left installed and disabled.
The runner page tells the operator to finish with `aixle-runner service uninstall`.
Revoke also works **per machine** (the machines table on the runner page), which revokes
that environment's credential family only. `aixle-runner unregister` is the same thing
initiated from the machine.

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
3. **Assignment:** `Allocator` only assigns an environment whose `project_id` is null or
   equal to the session's project. When it binds an unbound environment it sets
   `project_id`, which never changes afterwards. The gateway authorises every op, log and
   proxy call against `environment.current_session_id`, and that session's project must
   equal the environment's bound project. A database check constraint ties
   `terminal_sessions.runner_environment_id` to the same company.

**The company-scope case:** a company runner is shared by projects, but **its environments
are not**. A reusable workspace carries repository checkouts, caches and possibly leftover
files. Project B's run must never land on a disk project A used, even after a scrub, so
environments are partitioned by bound project. An environment bound to A is never handed
to B. If B needs capacity and A's environments are idle at `max_environments`, the
allocator rebuilds A's least-recently-used idle environment (wipe and unbind) and binds it
to B. Capacity is shared at the runner level. Disks are not.

**On `manual` there is no rebuild, so there is no automatic rebinding.** A reset wipes
what Aixle created, not the machine, and that is not enough to hand a disk from one
project to another. A machine on a company `manual` runner is bound to the first project
that uses it. Moving it is an explicit admin action, **Release to company**, which runs a
reset, clears the binding, and asks for confirmation that says the rest of the machine is
not wiped. If B needs capacity while every machine is bound to A, B queues. The runner form
recommends project scope for `manual` runners for this reason.

### 9.5 Network surface

The guarantee this design makes is about **inbound** connections. That is what carries the
network and security axes: the customer opens nothing towards their network, and the
platform holds no credential that reaches into it.

- **Inbound to the customer:** nothing. This is a commitment.
- **Outbound from the environment:** not restricted by this design, and there is no goal to
  narrow it to one host. The runner page documents what the runner and the agent need to
  reach, so customers who filter egress can allow it. **This list is documentation, not a
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

### 9.7 A `manual` machine: what the operator takes on

The platform holds nothing into the machine, so the trust questions move to the operator,
and the runner page and the user documentation say so plainly:

- **Agent sessions are a persistent tenant on that machine.** Every session assigned to it
  runs there, with its repository checkouts on the workspace volume between sessions.
- **The launching user's agent login lands there** (§9.1), as on every external type. The
  §3.2 permissions and the §11 disclosure on the run drawer and session form apply
  unchanged.
- **Environments stay bound to one project** (§9.4), and there is no automatic rebinding.
- **The `docker` group is root-equivalent.** `service install` puts the `aixle-runner`
  system user in it, because the host runner starts containers. Anyone who controls that
  user controls the machine.
- **Recommendation:** a dedicated machine for the runner, not a shared developer box; or,
  once it exists, the ephemeral mode (§6.3), with one fresh VM per session from the
  customer's own automation.

---

## 10. Session admission

The invariants in `session-admission-queue/ARCHITECTURE-SPINE.md` hold unchanged. What
changes is the pool an external session belongs to:

- `SessionAdmissionService.pool_configuration` gains one branch ahead of the existing
  logic: `return ["runner:#{session.runner_id}", runner.max_concurrency] if session.runner_id`.
  Hosted sessions take the existing lines. **Exactly one applicable pool** (AD-1) still
  holds.
- **The company ceiling is not applied to `runner:*` pools.** The company limit
  (`SessionConcurrencyLimit` scope Company) is hosted capacity that is sold and metered.
  Capacity on the customer's runner is theirs to count, so `max_concurrency` is the only
  cap. Whether external sessions are billed, and how, is a product decision outside this
  design. Usage rows record `runner_id`, so either answer can be implemented. External
  sessions do not draw down `CompanyCapacityUsage`.
- **Two levels of waiting, both existing mechanisms:**
  - `runner_limit`: the admission queue, FIFO in the `runner:<id>` pool.
  - `runner_capacity`: the V2 `capacity_wait` after `CapacityError` from the allocator or
    the provider, with the reservation kept, as for `namespace_quota` today.

  The session page shows which one applies.
- **`manual` capacity is a physical fact, not elastic.** There is no provisioning step, so
  `runner_capacity` on a `manual` runner means "every connected machine is busy", and it
  ends only when one frees up or the operator connects another machine. Nothing the
  platform or a setting does raises it. The effective concurrency is
  `min(max_concurrency, machines idle or busy)`. `max_concurrency` stays a ceiling the
  operator can set lower than the machine count. The runner page and the queued-session
  message say "2 of 2 machines busy" rather than suggesting that capacity is being created.
- **Release** follows AD-4 and the confirmed-release rule. The slot is freed when cleanup
  completes (scrub ok and the environment back to `idle`, or teardown confirmed). An
  environment the platform lost contact with keeps the slot until `observe` says `missing`
  or an admin forces release from the runner page. That is the external equivalent of
  "unknown creation retains capacity".
- **Reconciliation:** `SessionAdmissionReconciliationWorkflow` gains a runner pass that
  compares `runner_environments` with `adapter.observe` and with heartbeats. The hosted
  scanners (`DeadContainerScan`, the orphan sweeper) skip sessions with a `runner_id`.
  Their hosted query is untouched, with one `WHERE runner_id IS NULL` added.

---

## 11. UI surface

| Where | What |
| --- | --- |
| **Company → Settings → Runners** (new tab in `pages/Company/Settings/SettingsTabs.tsx`) | List of company runners: name, type, status pill with reason, environments busy/total, last seen. "New runner" for admins. |
| **Project → Runners** (new page next to Integrations, in the Resources group of the project sidebar) | Two sections: "From your company" (read-only, link to the company page for admins) and "This project". "New runner" for admins and the owner. |
| **New runner form** | Step 1: pick a type (cards; the type list comes from the adapter registry filtered by the flags, so a new type shows up without UI work, and the Kubernetes card only with `external_runners_kubernetes`). Step 2: the type's form generated from `config_schema`. Manual: the `container` options from §6.8, offered first as "give the agent your toolchain", with the acknowledgement for writable host mounts (§7.2), reuse policy with the per-type wording of §7.1, auto-update. Coder: integration select (visible ones), template, parameters, the `container` options, reuse policy, max environments. Kubernetes: namespace, and the `container` resources and image override. The fields per type are exactly the keys of §2.7. Step 3: limits. Then **Connect**: Manual shows the GitHub-style sequence of §6.3 (download, **SHA-256 verification**, `aixle-runner configure --url … --token …`, `aixle-runner service install`) with a one-time token, and waits for the first machine with a live status; Coder runs `validate_config` + `check_health` inline; Kubernetes shows the one-time registration token and `helm install` command, and waits for the controller. |
| **Runner page** | Status and health facts, capabilities, the container options that widen access (§6.8), the documented egress list (§9.5), runner version against `recommended_version` (§14.2), environments table (state, bound project, current session link, last used, version; actions Reset / Rebuild where `rebuildable` / Force release), Disable / Revoke / Rotate token / Delete. For `manual` the table is **Machines**: name, online / idle / offline, os/arch, Docker version, first-seen IP, runner version and auto-update; actions Reset, Return to service, Release to company (§9.4), Revoke; and "Add machine", which mints a new registration token. The §9.7 disclosure sits above the table. |
| **Workflow builder → Base Resources** (`BaseResourcesTab.tsx`) | "Runner" select: `Hosted (default)` + visible runners with status. Inline warning when the referenced runner is not usable (§3.4). No warning for an interactive step on a runner without `interactive_terminal`: it is not built, for the reason in §4. |
| **Run drawer** (`RunWorkflowDrawer.tsx`) | "Runs on" select defaulting to the workflow's runner. For an external runner a one-line note: "Your agent login is used on this runner, which is operated by *Company/Project*." |
| **New session form** (`SessionNewForm.tsx`) | Same select and note. Interactive mode greys out every external runner until the tunnel (§4, §15 task 16). |
| **Session page, run page, step list, board task run history** | A "Runs on" badge: `Hosted`, or `Prod VPC · coder`, linking to the runner and environment. "Open in Coder" when `human_accessible`. A connection-lost banner (§6.7). This is where users see where a run actually executed. |
| **Admin (Administrate)** | Runners and environments dashboards for support. |

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
  its leading key names, anything else above the form. No Connect step yet (task 12): a
  created runner opens its page.
- **Runner page.** Name, type, status and reason, scope, creator, last seen, limits, reuse
  policy, capabilities, the keys the config sets, and the §6.8 options that widen access
  called out above them. Edit (the same form without the type step), Disable, Enable,
  Revoke and Delete (the soft delete) only with `canManage`; a company runner seen from a
  project is read-only there and links a company admin to company settings. Machines,
  environments, tokens, the runner version and the egress list are not there yet (tasks 5,
  12 and 13).

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
  the `TenantScope` rule checked on the preloaded row). A stale `runner_id` that names another
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
- **`config/runner_release.yml` stays a `Settings` file** (§14.2). It holds the runner
  version pins, which are a pin, not a toggle, and it never becomes a flag.

### 12.2 Delivery order, as flag states

Each phase leaves `develop` releasable and the hosted path untouched. "Test company" is our
own staging test company; "named companies" are companies given an override from `/admin`,
one at a time, each with a reason. The flags never go `default: true` before removal.

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

- The protocol is written down as a specification, `runner-protocol/PROTOCOL.md`.
- **The conformance fixtures are committed in this phase** (`runner-protocol/fixtures/v1/`,
  §14.1), and the gateway's Rails tests run them from the first PR. They are the contract
  the Go implementation is written against, and what makes the later extract safe.
- Separate CI lanes for the Go code (`go test`, lint, the Go side of conformance) **may be
  deferred**. Until they exist, `runner/` is built and tested locally and in the release
  lane only.
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
- one line in `pool_configuration` (§10);
- `WHERE runner_id IS NULL` on the two hosted scanners;
- the env-var rewrite, which lives in `RunnerRuntime`;
- nullable columns.

Phase 1 adds a regression test that runs the existing hosted admission and launch tests
with `external_runners` **enabled for the test's company**, through the helpers in
`test/support/feature_flags_helper.rb`
(`with_feature(:external_runners, true, company: company) { ... }`), and asserts that the
same Kubernetes calls are made as with the flag off. "Unchanged" is then checked by a test
and not assumed. It is `test/integration/hosted_runtime_unchanged_test.rb` (task 4): a
standalone session and a workflow step go through the real admission and launch relay and the
container phases on the runtime seam, once with the flag off and once on, and the runtime
calls, the admission and the outcome must match. In phase 6 the same test runs with `external_runners_kubernetes` enabled
for that company too.

**Tech debt this creates, with its exit condition.** Leaving hosted untouched means **two
execution models live side by side for an open-ended period**: outside-in for hosted
(`KubernetesRuntime` / `DockerRuntime` exec into a pod), and inside-out for external
runners (`RunnerRuntime` over the protocol). Until that ends, every change to a
`ContainerRuntime::BaseRuntime` primitive (`exec`, `write_file`, `read_file`,
`container_status`, `container_logs`) or to a `ContainerWorkflowV2` phase has to be
reasoned about, and tested, twice: once for each model, including the ways each one fails.

- **Recorded as:** a `tech-debt` board task created with the phase 3 tasks, linked from
  this section, and a note in `app/services/container_runtime/base_runtime.rb` that names
  both implementations.
- **Mitigation while it lasts:** the conformance fixtures (§14.1) cover the `RunnerRuntime`
  side of every primitive, and the "hosted unchanged" regression test covers the hosted
  side. A change to a primitive must touch both suites in the same PR.
- **Exit condition:** §13 step A (hosted routed through `Runners::Allocator`, no behaviour
  change), then step B (hosted pods run `aixle-runner` as PID 1 and exec over the
  protocol). **The debt is closed when step B ships and `KubernetesRuntime#exec` has no
  caller left in the session path.**
- **Trigger to schedule step A:** the protocol is declared stable (the same trigger as the
  runner extract, §14.1), and one full release has passed with no protocol-breaking
  change. Step B follows once step A has run in production for one release. The debt task
  carries this trigger, so it is reviewed when the protocol is declared stable and not left
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
12. Remove the `external_runners` override for the test company mid-session from `/admin`:
    the session fails at the next poll, the Runners pages disappear, and a new launch of a
    workflow that names the runner fails with the §8 message, without falling back to
    `hosted`. Put the override back: the machine reconnects without re-registering.
13. `aixle-runner unregister`: the machine disappears from the list and its credential
    gets `401`. Register again and Revoke from the UI: the runner on the machine stops and
    cleans up its containers and volumes.
14. Point a run from a second project at the project runner by id through the API: 403.
15. Selecting `hosted` or nothing on the same project behaves exactly as before. The hosted
    pods are created as before, verified on the cluster.

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
5. Run it again: it lands on the warm workspace (affinity), the agent image is not
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
- The protocol is a **specification document**, `runner-protocol/PROTOCOL.md`, and the
  **conformance fixtures** are in `runner-protocol/fixtures/v1/` (request and response
  pairs, op payloads and results, error cases, resume sequences). This is a neutral
  directory, owned by neither the Rails tests nor the Go tests, and both read it from
  there. They are committed in phase 2 (§12.2).
- The extract is `git filter-repo --path runner/ --path runner-protocol/`, which keeps
  history. Afterwards `flow` keeps a pinned copy of `runner-protocol/` that only changes
  by a PR, and the Rails side keeps running the fixtures against the gateway.

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

### 14.2 Versions and release lanes, independent of the application release

There are **three distinct versions**, and none of them is the application version:

| Version | Example | What it versions | Where it is set |
| --- | --- | --- | --- |
| **Runner version** | `1.4.0` | The `aixle-runner` binary and `ghcr.io/aixlehq/aixle-runner:1.4.0` | The `runner-v1.4.0` tag |
| **Chart version** | `0.3.2` | The Helm chart's packaging (templates, values, defaults) | `Chart.yaml` `version`, the `runner-chart-v0.3.2` tag |
| **Chart `appVersion`** | `1.4.0` | The runner version the chart installs by default | `Chart.yaml` `appVersion` |
| **Protocol version** | `1` | The wire contract (`X-Aixle-Runner-Protocol`) | `runner-protocol/PROTOCOL.md`, an integer bumped only on breaking changes |

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

**The platform's pins are a committed file, not derived from the release.**
`config/runner_release.yml`, read through `Settings` (`Settings.runners.release`, per the
`NoEnvInApp` cop), holds:

```yaml
# Illustrative values.
protocol_supported: [1]           # becomes [N-1, N] after the first bump
min_version: "1.2.0"              # check-in / register refused below this
recommended_version: "1.4.0"      # what new environments install; "update available" below this
binaries:
  "1.4.0":
    linux-amd64: { sha256: "…" }
    linux-arm64: { sha256: "…" }
```

Changing what the platform recommends is an **application PR** that edits this file, and
it is independent of a runner release. Publishing `runner-v1.5.0` changes nothing until a PR
moves `recommended_version`. The "update available" banner on the runner page then compares
against `recommended_version`, so it no longer fires on every application release.

**Compatibility statement.** `docs/operations/releasing.md`, whose version contract only
covers the application today, gains a "Runner compatibility" section: *platform `X.Y`
supports runner protocol versions `[N-1, N]` and runners at or above `min_version`, both as
declared in `config/runner_release.yml` at that release.* The application changelog
mentions any change to that file.

### 14.3 Binary distribution and integrity

- **Binaries are served from GitHub Release assets** of the `runner-v*` release.
- **The documented URL is the platform's**: `GET /runner/v1/releases/:version/:os-:arch`
  answers `302` to the asset. The installer and the runner only ever know this one URL. A
  self-hosted or air-gapped deployment can later serve the bytes from the platform, or
  from a mirror, without changing the runner or the script.
- **`install.sh` verifies SHA-256** against the digest the platform serves (the
  `X-Aixle-Runner-Sha256` header, and the checksums endpoint for the self-update path).
  Both come from `config/runner_release.yml`, not from the asset host, so a tampered asset
  fails verification. The script keeps a **`verify` hook**, a function called with the
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
  because a newer runner came out.**
- **Self-update:**
  - **Runners on reusable environments self-update by default.** That means the host
    runner on `manual` machines and on Coder workspaces. When the check-in response or
    an idle poll carries `update: {version, url, sha256}`, the runner downloads from the
    release URL, verifies the digest, and re-execs. This happens only while the
    environment is `idle`, never during a session, and only towards
    `recommended_version`. The session runner inside a session container is the host
    runner's own binary, so it is updated with it. Ephemeral pods never need an update,
    because the platform picks their version (§9.6).
  - **`manual` opt-out.** Customers who manage the machine through their own configuration
    management (Ansible, Puppet, a golden image) turn self-update off, per runner
    (`config.auto_update: false`) or per machine (`configure --no-auto-update`). Such a
    runner reports its version like the controller does: "update available" and `degraded`
    below `recommended_version` on the runner page, and refused below `min_version`, so an unmanaged skew still surfaces at check-in and never mid-session.
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
    `service install` (§6.3). The systemd unit runs as the `aixle-runner` system user and
    survives logout and reboot. Self-update replaces the binary in place and restarts the
    unit while the machine is idle.
  - **Kubernetes:** the init container and image as in §9.6.
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
| 2 | 1 | **Done.** Policies and controllers: `Web::Company::RunnersPolicy` and `Web::Company::Projects::RunnersPolicy` with the §3.2 rules (the project policy refuses writes on a company runner, from the record), company runners CRUD at `/company/settings/runners` and project runners at `/company/projects/:project_id/runners` (`index`, `show`, `create`, `update`, `destroy` as the soft delete that revokes, `disable`, `enable`, `revoke`), each a `404` without the flag, declared with `requires_feature :external_runners` (`FeatureGated`, docs/architecture/feature-flags.md). `RunnerResource` for the pages. `Runners::ConfigSchema` encoding §2.7 for every type (refusing unknown, inapplicable and later keys and `ephemeral`; defaults never written), the `Runners::Adapter` registry with `ManualAdapter` only (`coder` and `kubernetes` are refused as not available yet), capabilities `provisionable` and `rebuildable` stored on save, and `ManualAdapter#validate_config`. The other §4 flags wait for their first reader, and `check_health` moved to task 12. `IntegrationsController#destroy` shows the error when `Integration`'s `has_many :runners, dependent: :restrict_with_error` refuses the removal, instead of ignoring `destroy`'s result and saying "Integration removed" (until task 17 decides what disconnecting does to runners). Needs 1a (the flag) and 1b. |
| 3 | 1 | **Done.** Frontend behind `useFeatureFlag('externalRunners')` (needs 1a): the Company Settings → Runners tab and the Project → Runners page (sidebar entry next to Integrations, "From your company" and "This project"), the new-runner form generated from the type's `configSchema` by an in-house renderer (Manual card; the writable-mount acknowledgement and the Docker-socket rule as form widgets; only the keys the user set are sent, verbatim; the server's errors shown at their fields), and the runner page without machines (capabilities, config with the options that widen access, limits, Edit, Disable, Enable, Revoke, Delete), as §11 "What v1 has so far" describes. |
| 4 | 1 | **Done.** Selection: the nullable `workflows.runner_id`, `workflow_runs.runner_id` and `terminal_sessions.runner_id` references (§2.4), with how `runner_id` is snapshotted and restored in a workflow version, including a runner that is gone (§3.4); `workflows.runner_id` in the builder (Base Resources) and the version snapshot, run-drawer and new-session selects, `Runners::Resolver` with launch-time checks (status, visibility, flag) and the §8 failure messages, `runner_id` frozen on `workflow_runs`, "Runs on" badges. A reference is checked by the project's tenant rule (`TenantScope.owned(Runner, …)`). The runner pages do not list where a runner is used. A project move blocks on the project's own runners, switches its workflows that name a runner to Hosted (archived ones included, listed in the preflight), clears `runner_id` on its runs and sessions and on its workflows' version snapshots; a revert to a version whose runner is gone or no longer reachable restores Hosted (§3.4). Without the flag, a workflow can still be switched back to Hosted. The badges serialize only a runner in the record's tenant. The "hosted unchanged with the flag enabled" regression test of §12.3. |
| 5a | 2 | **Done.** The gateway process type (`config/puma_runner_gateway.rb`, `runner_gateway` in `Procfile.dev`; its deployment is an `aixle-infra` task) and `/runner/v1/*` as `RunnerGateway::V1` (§6.1). The `runner_environments` and `runner_credentials` tables, with only the columns this task reads and writes (§2.2, §2.3). Token issuance and rotation in `Runners::Credentials` (§9.2): registration tokens minted by the service, with no endpoint or UI, single-use and valid for 1 h; access tokens valid for 1 h; refresh tokens that rotate on every use, expire after 30 days unused, and revoke the family on reuse, a spent one past its own expiry included. `register` creates one `registered` `manual` environment, and `ephemeral` is refused. `DELETE registration` marks it `gone` and revokes its credentials, without `409 busy`, which waits for the first task that assigns a session to an environment. Every request checks the protocol header, the token (a refresh token that is revoked, of a `gone` environment, or expired without being spent is refused before anything else), the runner status (cached 5 s) and the flag; the gateway's Puma caps bodies at 64 KB. Only the gateway process draws the `/runner/v1` routes (`AIXLE_PROCESS_MODE`, set by its Puma config), and every other process draws everything else. Revoking a runner revokes its credentials in the same transaction, serialized against every issuer, registration-token minting included, by a lock on the runner's row (§9.3), and credentials of a `gone` environment are refused (§9.2). Rack::Attack throttles per token, per IP on all of `/runner/v1/*`, and per IP on `register`. `terminal_sessions.runner_environment_id` moved to its first reader (task 8 or 11). |
| 5b | 2 | The `runner_operations` queue (§2.3) with `Encryptable :runners_key` for its `encrypted_payload`, the `GET /runner/v1/ops` long-poll woken by LISTEN/NOTIFY, and `POST /runner/v1/ops/:id/result` (§6.2, §6.4). |
| 6 | 2 | `aixle-runner` (Go, self-contained `runner/` with its own `go.mod`, §14.1). `session` mode: poll and execute (`exec`, `write_file`, `read_file`, `batch`, `status`, `logs`), log shipping, heartbeat, reconnect and resume, the local proxy. `host` mode: `configure`, `service install`/`uninstall`, `unregister`, environment credential and journal, `image.ensure`, `container.start`/`stop` with labels, the Unix-socket relay for the in-container session runner, scrub and reset by label, self-update with the opt-out. |
| 7 | 2 | `runner-protocol/PROTOCOL.md` and the conformance fixtures in `runner-protocol/fixtures/v1/`, **committed in this phase** and run by the gateway's Rails tests, including registration, unregistration and the refused `ephemeral` case. The Go side of conformance and the Go CI lanes may follow later (§12.2). |
| 8 | 2 | `ContainerRuntime::RunnerRuntime` + `ContainerRuntime.for_session`, env-var rewrite for proxied routes, live-log chunks for `LiveLogReader`/`NoOutputWatchdog`, dev `local` adapter and Compose service. |
| 9 | 2 | Admission: `runner:<id>` pools, company ceiling exclusion, `runner_limit`/`runner_capacity` wait reasons, hosted scanners skip runner sessions; the §12.3 regression test extended to admission. |
| 10 | 2 | Runner release lane: `runner-release.yml` for `runner-v*` (binaries, `checksums.txt`, GHCR image). `config/runner_release.yml` read through `Settings.runners.release`. The `/runner/v1/releases` redirect and checksums endpoints. The "Runner compatibility" section in `docs/operations/releasing.md` (§14.2). |
| 11 | 3 | `Runners::Allocator` and environment state machine, including the self-registering entry path (§5.2): affinity, project binding, no step 4 on non-`provisionable` types, scrub and reset escalation without rebuild, Return to service, Release to company (§9.4), reconciliation pass. |
| 12 | 3 | `manual` end to end: `ManualAdapter#check_health` derived from machine heartbeats (§2.5), heartbeat-based `observe`, the Machines table (online / idle / offline, facts, first-seen IP), "Add machine" with the GitHub-style instructions and the SHA-256 step, per-machine Revoke, `reuse_policy` per §7.1, the writable-mount acknowledgement, the §9.7 disclosure, and user docs for `manual` (dedicated machine recommended). |
| 13 | 3 | Runner page actions (Reset, Force release), connection-lost banner, the revoke flow, Administrate dashboards. |
| 14 | 3 | Staging validation per §12.4 (QA task). Record the machine used in the result. |
| 15 | 3 | Tech-debt task for the two execution models, with the exit condition and trigger from §12.3, and the note in `base_runtime.rb`. |
| 16 | 4 | Interactive tunnel: a session-runner WebSocket relay for ttyd (both instances), the IDE and the watcher through the host runner, plus session page routing. Developed against the `local` adapter. Lifts `interactive_terminal: false` on every type. Once it is done, named companies can get the `external_runners` override (§12.2). |
| 17 | 5 | `CoderAdapter` provision, prepare, inject_bootstrap, reset, rebuild, teardown, observe over `Coder::Api`/`WorkspaceService`; the `coder` keys of §2.7 (template, `config.container`) and their validation (§6.8); `install.sh` with SHA-256 verify and the `verify` hook; pooling, `max_environments`, warm-disk affinity; `reuse_policy: fresh` as a new workspace per session. |
| 18 | 5 | Staging validation per §12.5 (QA task), on the staging Coder integration configured on the test project and a template it offers at test time. Record the template used and the §12.5 checks (Docker daemon, disk, pruning) in the result. |
| 19 | 6 | Kubernetes: declare `external_runners_kubernetes` (§12.1); `aixle-runner` controller mode, the Helm chart and its `runner-chart-v*` OCI lane in `AixleHQ/aixle-runner` (§14.1), `KubernetesAdapter` over controller ops, registration-token UX, documented agent image sizes. Preceded by the runner extract if it has not happened yet. |
| 20 | 7 | `host` execution mode (§6.8): `config.execution_mode: host` and `config.host.cli_source` declared in the §2.7 schema, the host-side CLI with `cli_source` (prototype `docker create` + `docker cp` first), the host-generated CA trusted in three stores and passed into the MITM container, the `NODE_OPTIONS` instrumentation, host-side ttyd/IDE/watcher for the tunnel, the redaction path, the per-session OS user and its scrub (§7.2), toolcache session kits, P2. Likely several tasks when it is cut. |

---

## 16. Open items and what would settle them

- **P1, latency of op-per-primitive context assembly.** Recommendation: `batch` coalescing
  (§6.4). Settled by measuring a real `before_exec` against the `local` adapter in task 8
  and against the staging `manual` machine in task 14: the target is under 5 s added over
  hosted. If it misses, move
  `SessionContextService` writes to one tarball op. The protocol already allows that.
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
- **Ephemeral registration for `manual`.** Defined in the protocol and refused in v1
  (§6.3). Settled by the first customer who wants to script their own scaling; adding it
  needs no protocol bump.
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
  - external sessions do not draw down `CompanyCapacityUsage` (§10).

  What would settle it is the pricing decision for the first non-staging customer. It has
  to be made before trigger 2 of §14.1, and nothing earlier depends on it.

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
session container keeps running, the session runner buffers, and the host runner
reattaches to it by name (§6.8); §12.4 step 10 tests it. A reboot **while idle** comes back
as an idle machine (§12.4 step 11).

What is not described: a **reboot of the machine during a session**, which on a long-lived
machine happens regularly (kernel updates, power, maintenance). A full version has to
decide:

- **The session container's restart policy.** Today's implied answer is "no restart": an
  agent process cannot resume mid-turn, and a container that restarts would replay
  `entrypoint.sh` against a half-written workspace. That has to be stated, and the host
  runner has to create the container with it explicitly instead of relying on the daemon's
  default.
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
  nothing in this design says what it does.

A full version needs, scoped by the same ownership rule as scrub (only what Aixle itself
created, selected by label and name, §7.2):

- **retention and garbage collection** for images outside the current pins and a cap on
  the cache volumes, run while the environment is `idle`, never during a session;
- **a defined reaction to `disk_low`**: the runner goes `degraded` with a reason the
  operator can act on ("build-01 has 3 GiB free; Aixle images and caches use 41 GiB"),
  the prerequisite check at check-in (§6.8) refuses new sessions below the 20 GiB floor
  with the same message, and optionally a prune of what Aixle created, offered as an action
  on the Machines table rather than run silently.
