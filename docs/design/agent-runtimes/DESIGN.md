# External runners for agent sessions — design

**Status:** proposed, revision 3 (design only, no implementation in this change)
**Created:** 2026-10-20 · **Revised:** 2026-10-21
**Task:** #163 "Tech design: external agent runtimes (pluggable runners)"
**Baseline:** `origin/develop` @ `1f4ca0bd`

**Revision 3** applies the correction to the revision 2 review. The design no longer
depends on `aixle-infra`, the infrastructure of our own production and staging
deployment, which is not part of the product:

- Staging validation names no Coder template. It uses the staging Coder integration
  configured on the test project and whatever template it offers at test time (§12.4,
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

The four reasons are network (the agent runs inside the customer's VPC or VPN),
environment (the customer's image, template and warm disk), load (the customer's capacity
and bill), and security (code, data and secrets stay inside the customer's perimeter).
There is also a structural reason: Coder alone would be a dead end, so the integration
point is an adapter interface, not a Coder branch.

Section 1 settles the naming and the execution model, because every later section depends
on them. Sections 2–15 cover what the task asks for. Section 16 lists what this design
could not close on paper.

---

## 1. Decisions that shape everything else

### 1.1 Naming: **Runner**

**Decision:** the entity is a **Runner** with a `type` of `hosted`, `coder` or
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
| **Runner type** | `hosted`, `coder` or `kubernetes`. Each type has one platform-side **adapter**. |
| **Environment** | One concrete place where sessions execute: a Coder workspace, or a pod in the customer's cluster. Belongs to a Runner and has its own state machine (§5.2). |
| **`aixle-runner`** | The binary that lives in an environment and speaks the runner protocol. It runs in three modes: `host` (on a Coder workspace, owns the environment and its containers), `session` (PID 1 of an agent container, or directly on the workspace in `native` mode) and `controller` (in a customer cluster, provisioning pods). |
| **Execution mode** | How sessions run inside an environment: `docker` (the stock agent image, the default) or `native` (directly on the workspace). A runner setting, not a property of the type (§6.8). |
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

Coder keeps outside provisioning. The Coder API is built to be called remotely, a Coder API
token is limited by Coder's own RBAC to one Coder user's workspaces, and the platform
already holds exactly that token through the Coder integration (`Integration` provider
`:coder`, `Coder::Api`). A Coder control plane reachable only inside a VPN is not served in
v1. It is handled later by running the controller mode with a Coder backend (§16).

The adapter contract (§5) is the same in both cases. It is a platform-side Ruby interface,
and only its transport differs: the Coder API for `coder`, the controller's channel for
`kubernetes`.

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

All tables use `include TenantColumns` and the `<table>_tenant_columns` check-constraint
pattern. Secrets use `Encryptable` with a new `encryption_key :runners_key`
(`Settings.encryption.runners_key`, with rotation through `runners_key_previous` and
`bin/rails encryption:reencrypt`). No secret is ever stored on a workflow, a workflow
version, a run or a step.

### 2.1 `runners`

| Column | Type | Notes |
| --- | --- | --- |
| `company_id` | bigint, not null | Tenant. |
| `project_id` | bigint, null | `NULL` means company runner; set means project runner. Same convention as `integrations` (`company_wide`, `visible_for_project`). |
| `name` | string, not null | Unique per scope among non-deleted rows: `(company_id, coalesce(project_id, 0), lower(name)) WHERE deleted_at IS NULL`. |
| `runner_type` | string, not null | `coder` or `kubernetes`, enumerize. `type` is avoided as a column name so Rails does not turn this into STI. The API and UI field is still called `type`. |
| `status` | string, not null | §2.5. |
| `status_reason` | string, null | Human-readable, shown in the UI and in run failures. |
| `integration_id` | bigint, null | `coder` only: the Coder integration the runner provisions through (§2.6). Check constraint: required when `runner_type = 'coder'`, null otherwise. |
| `config` | jsonb, not null, default `{}` | Non-secret, per-type schema validated by the adapter (`template_id`, `template_version_policy`, `parameters`, `execution_mode`, `docker`, `namespace`, `image_override`, …). For `coder`, `execution_mode` is `docker` (default) or `native`, and `docker` holds the container options from §6.8. |
| `encrypted_secrets` | text, null | `Encryptable` column for any type-specific secret. Unused by the two v1 types and kept for later types. |
| `max_concurrency` | integer, not null | Pool limit for admission (§10). Must be > 0. |
| `max_environments` | integer, null | Reusable types: environment pool size. Null means equal to `max_concurrency`. |
| `reuse_policy` | string, not null | `reuse` or `fresh` (§7). The default comes from the type's capability. |
| `capabilities` | jsonb, not null | Computed by the adapter from type and config (§4), cached for the UI. |
| `health` | jsonb, not null, default `{}` | Last health-check facts and timestamp. |
| `last_seen_at` | datetime, null | Last controller heartbeat (`kubernetes`) or last successful health check (`coder`). |
| `created_by_id` | bigint, not null | |
| `disabled_at`, `revoked_at`, `deleted_at` | datetime, null | Soft lifecycle. Rows are never hard-deleted while anything references them. |

### 2.2 `runner_environments`

| Column | Notes |
| --- | --- |
| `runner_id`, `company_id` | |
| `project_id` | **Bound project**. Set on first assignment and never changed afterwards (§9.4). |
| `key` | Adapter idempotency key, unique per runner, e.g. `aixle-r12-e7f3a`. It is the Coder workspace name or the pod name. |
| `external_id` | Coder workspace UUID or pod UID. |
| `state` | §5.2. |
| `reusable` | Copied from the runner's reuse policy when the environment was created. |
| `runner_version`, `protocol_version`, `os`, `arch` | Reported at check-in. |
| `facts` | jsonb: prerequisites found, disk free, and per mode either the Docker daemon version and agent images present (`docker`) or `tmux`/`git`/`bash` versions and toolcache contents (`native`). |
| `current_session_id` | The `terminal_sessions` row it is executing. At most one (§7.3). |
| `last_workflow_id` | Affinity for warm-cache reuse (§7.3). |
| `last_heartbeat_at`, `checked_in_at`, `sessions_count`, `consecutive_failures` | |
| `reset_requested` | `none`, `reset` or `rebuild` (§7.2). |

### 2.3 `runner_credentials` and `runner_operations`

`runner_credentials`: `runner_id`, `runner_environment_id` (null for controller-level
credentials), `kind` (`registration`, `controller`, `bootstrap`, `environment`),
`token_digest` (SHA-256, never the token), `family_id` (rotation lineage),
`expires_at`, `used_at`, `revoked_at`, `last_used_at`, `last_used_ip`, `created_by_id`.
Token semantics are in §9.2.

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

Migration sketch (not written in this change):

```ruby
create_table :runners do |t|
  t.references :company, null: false, foreign_key: true
  t.references :project, foreign_key: true
  t.string :name, null: false
  t.string :runner_type, null: false
  t.string :status, null: false, default: "pending"
  t.string :status_reason
  t.references :integration, foreign_key: true
  t.jsonb :config, null: false, default: {}
  t.text :encrypted_secrets
  t.integer :max_concurrency, null: false
  t.integer :max_environments
  t.string :reuse_policy, null: false
  t.jsonb :capabilities, null: false, default: {}
  t.jsonb :health, null: false, default: {}
  t.datetime :last_seen_at, :disabled_at, :revoked_at, :deleted_at
  t.references :created_by, null: false, foreign_key: { to_table: :users }
  t.timestamps
end
add_check_constraint :runners, "max_concurrency > 0", name: "runners_max_concurrency_positive"
add_check_constraint :runners,
  "(runner_type = 'coder') = (integration_id IS NOT NULL)", name: "runners_coder_integration"

add_reference :workflows, :runner, foreign_key: true          # nullable, no default
add_reference :workflow_runs, :runner, foreign_key: true
add_reference :terminal_sessions, :runner, foreign_key: true
add_reference :terminal_sessions, :runner_environment, foreign_key: true
```

The migrations only add nullable columns and new tables. Every existing row reads as
`hosted`, and no hosted code reads the new columns (§12.3).

### 2.5 Runner status

```
pending ──health ok──▶ connected ◀──recovers── degraded / unreachable
   │                      │  ▲
   │                      ▼  │ enable
   │                   disabled
   └──────────────▶ revoked (terminal)       deleted_at set ⇒ hidden; treated as revoked
```

- `pending`: created, never verified. Coder: the integration token and template have not
  been checked yet. Kubernetes: the controller has not connected yet.
- `connected`: health check passed within the last 5 minutes. For Kubernetes this also
  requires a controller heartbeat within the last 60 s.
- `degraded`: reachable, but something is wrong: a template parameter is invalid, the
  controller reports missing RBAC, or the controller version is below the recommended one.
  New sessions are still admitted, and the reason is shown.
- `unreachable`: the health check failed, or the controller has been silent for more than
  3 minutes. New sessions fail at launch (§8). Running sessions follow §6.7.
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
reason that names the integration.

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

### 3.4 When the referenced runner is gone, disabled or revoked

A reference is never cleared automatically and never falls back to `hosted`.

- **Workflow builder:** the runner field shows "Runner *X* is disabled / revoked / deleted",
  with a link to pick another. Publishing a workflow whose runner is not
  `connected`/`degraded` is allowed, because the runner may come back, but it shows a
  warning.
- **Launch** (`SessionService.create_for_workflow_step`, the standalone create, and run
  creation): `Runners::Resolver.resolve!(session)` re-checks visibility (§9.4) and status.
  If the runner is `disabled`, `revoked`, deleted, `unreachable`, or no longer visible
  (e.g. moved project), the run or session fails before admission with
  `failure_reason: "runner_unavailable"` and a message like *"Runner "Prod VPC" is
  disabled. Pick another runner on the workflow or re-enable it."* The board task gets the
  same message through the existing failure-comment path.
- **Deletion** is a soft delete, so workflows and past sessions can still name what they
  used. Deleting a runner that workflows still reference requires confirmation listing those
  workflows. Hard deletion (by a later purge) only happens once no `workflows` or
  `workflow_runs` rows reference it.

---

## 4. Capability flags

The platform reasons about a runner through `Runners::Capabilities`, never through its
type. Each adapter returns them from `type + config`. Where a type supports more than
one execution mode (§6.8), the flags that depend on how the agent runs come from **the
mode**, not from the type:

| Flag | `hosted` (today) | `coder`, `docker` mode (default) | `coder`, `native` mode | `kubernetes` | Used by |
| --- | --- | --- | --- | --- | --- |
| `reusable` | false | true | true | false (v1) | Lifecycle (§7), affinity, scrub |
| `persistent_disk` | false | true (mounted volumes only) | true | false (a PVC option is later) | Reset semantics, UI copy |
| `human_accessible` | false | true (Coder's own SSH, web terminal, IDE) | true | false | "Open in Coder" link on the session |
| `interactive_terminal` | true | false until the tunnel (§12.2, phase 4), then true | false until the tunnel, then true | false until the tunnel, then true | Blocks interactive sessions and steps on the runner |
| `max_concurrency` | admission pools | `runners.max_concurrency` | `runners.max_concurrency` | `runners.max_concurrency` | Admission (§10) |
| `concurrency_per_environment` | 1 | 1 | 1 | 1 | Allocation (§7.3) |
| `agent_runtimes` | all | all | §6.8 allow-list | all | Validation at selection and launch |
| `provisioning_seconds_p50` | n/a | from history | from history | from history | UI hint, bootstrap timeout |

In `docker` mode the agent runs in the same image hosted uses. So `agent_runtimes: all`
follows from the mode, and it would hold for any future type that runs the stock image.
The allow-list is a property of `native` mode only.

Validation that uses these flags:

- An interactive standalone session cannot pick a runner without `interactive_terminal`.
  The select shows it disabled with the reason.
- A workflow with an interactive step cannot be **published** with such a runner.
- A run cannot be launched with an override to one.
- An agent runtime outside `agent_runtimes` is refused in the same three places.

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
    def reset(environment, level:)                   # level: :reset | :rebuild; idempotent
    def teardown(environment)                        # delete; => :gone | :pending
    def observe(environment)                         # => :running | :stopped | :missing | :unknown (provider fact, for reconciliation)
  end
end
```

`Runners::Adapter.for(runner)` is a registry keyed by type
(`Runners::CoderAdapter`, `Runners::KubernetesAdapter`). Adding a type means adding a
class, a config schema, and a row in §4. Nothing in sessions, strategies or Temporal
changes.

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

The per-type mapping:

| Method | `coder` (outside, Coder API via `Coder::Api`) | `kubernetes` (via controller ops) |
| --- | --- | --- |
| `provision` | `WorkspaceService` create from `config.template_id` with `config.parameters`, name = `key` | `controller.provision {key, image, resources, labels}`. The controller creates Pod, ServiceAccount and Secret (bootstrap) in its namespace |
| `prepare` | Await build. Start the workspace if it is stopped | Await pod `Ready` (controller reports) |
| `inject_bootstrap` | `Coder::SshRunner`-style `coder ssh <ws> -- sh -s` with the install script **on stdin**, so the token never appears in argv or `ps`. It installs and starts `aixle-runner --mode host` (§6.8) | No-op: the controller mounts the bootstrap Secret and the pod's init container installs the runner (§9.6) |
| `reset :reset` | Runner op `env.reset` (§7.2) | n/a (ephemeral) |
| `reset :rebuild` | Delete and recreate the workspace from the template | n/a |
| `teardown` | Delete the workspace (or stop it, per `config.on_release`) | `controller.teardown {key}` |
| `observe` | Workspace build status | Controller's pod list |

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

- One session at a time per environment (`concurrency_per_environment = 1`). `busy` holds
  `current_session_id`.
- `failed` environments are torn down by the reconciler and never reused.
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
| `pull_image` | Pull the image | Once an environment is assigned: `image.ensure` (`docker` mode: pull the agent image by digest) or `toolcache.ensure` (`native` mode, §6.8). On `kubernetes` it is a no-op, because the kubelet pulls |
| `create_container` | Create the pod | `Runners::Allocator.acquire(session)`: assign an idle environment (§7.3), or create a `requested` row and call `provision` + `inject_bootstrap` for it. Raises `ContainerRuntime::CapacityError` when at `max_environments`, so the **existing** `capacity_wait` loop in V2 handles it |
| `start_container` | Service, IngressRoute, wait ready | `prepare`, then wait for check-in with activity heartbeats. Raises a diagnosed failure on `bootstrap_timeout`. `docker` mode on Coder then sends `container.start` (§6.8) and waits for the session runner inside the container to report ready |
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

### 6.2 Endpoints

All requests are `Authorization: Bearer <token>`,
`X-Aixle-Runner-Protocol: 1`, `X-Aixle-Runner-Version: <semver>`.

| Endpoint | Caller | Purpose |
| --- | --- | --- |
| `POST /runner/v1/register` | controller | Exchange a registration token for controller credentials. |
| `POST /runner/v1/check-in` | session runner | Exchange the bootstrap token for environment credentials. Reports version, os/arch and facts. The response carries config (heartbeat interval, proxy routes, log limits) and `update` (§8.3). |
| `POST /runner/v1/token` | both | Refresh-token rotation. |
| `GET  /runner/v1/ops?after=<seq>&wait=25` | both | Long-poll. Returns ops with `sequence > after`, batched. An empty 200 after `wait` doubles as the heartbeat. |
| `POST /runner/v1/ops/:id/result` | both | Op outcome. Idempotent on op id. |
| `POST /runner/v1/sessions/:id/log` | session runner | Append live log chunk `{offset, bytes}`. |
| `POST /runner/v1/sessions/:id/events` | session runner | `agent_exited {code}`, `agent_started`, `disk_low`, … |
| `POST /runner/v1/heartbeat` | both | Only when no poll is outstanding, e.g. while uploading. Includes the running-session summary. |
| `ANY  /runner/v1/proxy/:route/*` | session runner | The callback proxy (§6.6). |
| `GET  /runner/v1/releases/:version/:os-:arch` | both | The binary's documented, stable URL. It answers `302` to the GitHub Release asset and sends the expected SHA-256 in `X-Aixle-Runner-Sha256` (§14.3). |
| `GET  /runner/v1/releases/:version/checksums` | both | The `sha256  file` list for that version, from `config/runner_release.yml`. |
| `GET  /runner/v1/install.sh` | bootstrap | Install script used by `inject_bootstrap`. |

### 6.3 Registration and tokens (summary; full model in §9.2)

- **Kubernetes:** an admin creates the runner, the UI shows a one-time **registration
  token** and a ready-to-paste `helm install` command. The controller calls `register`, the
  token is consumed, and the controller gets an access/refresh pair.
- **Every environment:** the platform mints a single-use **bootstrap token** bound to that
  environment and hands it to `inject_bootstrap` (Coder) or to the controller (Kubernetes).
  The runner calls `check-in`, the token is consumed, and the runner gets an environment
  access/refresh pair that is valid for that environment only.

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
| `image.ensure` | `pull_image` | `docker` mode: `{image, digest}`. The host runner pulls the agent image by digest. |
| `container.start` / `container.stop` | `create_container` + `start_container` / `cleanup` | `docker` mode, host-runner ops: `{image, digest, name, env, mounts, network, pid, resources}`. The runner starts the agent container with `aixle-runner --mode session` as PID 1, or stops and removes it (§6.8). |
| `toolcache.ensure` | `pull_image` | `native` mode only: `{agent_runtime, cli_version, sha256}` (§6.8). |
| `env.scrub` / `env.reset` | §7.2 | |
| `provision` / `teardown` / `observe` | Kubernetes adapter | Controller-only ops. |

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
the agent container in `docker` mode, on the workspace in `native` mode) and forwards an
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
  for 24 h. That is the host runner in `docker` mode on Coder, and the session runner
  elsewhere. A redelivered op returns the
  journalled result without re-executing it. This closes the ambiguous "did my exec run?"
  case that kube-exec has.
- **Resume:** on reconnect the runner refreshes its token if needed, polls with
  `after=<last acked seq>`, flushes buffered logs from their offsets (the gateway
  de-duplicates by offset), and posts the session summary (agent running or exited with a
  code). The platform reconciles: an exit the platform did not know about is handled like a
  dead container today (`DeadContainerScan` semantics) and fails the session with "agent
  exited (code N)" unless `finish_session` already ran.
- **Grace:** after `runners.reconnect_grace` (default 15 min, configurable per runner up to
  2 h) without contact, the session fails with *"Runner environment lost contact for 15
  minutes"*, and the environment is marked `failed` and torn down if the adapter can still
  reach it. The admission slot stays held until the adapter confirms teardown or `observe`
  returns `missing`, per AD-4 "unknown creation retains capacity", and is otherwise released
  by the reconciliation sweep.
- `finish_session`/`fail_session` go through the proxy (§6.6). If the proxy is down at that
  moment, the MCP call fails, the agent retries as it does on any network error, and the
  runner keeps the agent alive until the call lands or the grace expires.

### 6.8 What runs inside the environment: execution modes

**Decision:** the agent runs in **the stock agent image**
(`AgentRuntime.fetch(agent_type).image`) wherever the environment can run a container.
`aixle-runner --mode session` is PID 1 and supervises the image's `entrypoint.sh`. This is
`config.execution_mode: docker`, and it is the **default** for every type that offers a
choice. `native` mode, where the agent runs directly on the machine, is a deliberate
opt-in. The capability flags (§4) are derived from the mode, not from the type.

Why `docker` is the default:

- **Full parity with hosted out of the box.** tmux, the MITM usage proxy, the watcher and
  ttyd come with the image, the same way they come with a hosted pod. They do not have to
  be re-proved on every customer environment.
- **Every agent runtime works.** `agent_runtimes: all` in `docker` mode. Usage accounting
  for `cursor_cli` and `grok`, which reads the MITM log, works because the MITM proxy is
  in the image. The per-type allow-list, the toolcache session kits and prototype P2 drop
  out of the first iteration (they stay only for `native`).
- **One prerequisite.** The machine needs a Docker daemon and disk, instead of a glibc,
  `bash`, `git`, `tmux ≥ 3`, `curl` and `tar` checklist.
- **It works on common Coder templates as they are.** A Docker daemon is a usual part of
  a development workspace template. Where a template lacks one, adding it is a template
  change the customer owns, and the runner reports the missing daemon at check-in
  (§8) instead of failing mid-session.
- **Scrub becomes cheap and reliable.** Credentials, the prompt and the agent's home live in
  the container layer, so removing the container removes them (§7.2).

**The trade-off, stated plainly:** in `docker` mode, the template's own tools (compilers,
CLIs, the customer's VPN client, a pre-warmed cache) reach the agent **only through what is
mounted into the container**. The image decides the agent's userland. A customer whose
reason for a Coder runner is "the agent must see the tools in my template" either mounts
them, builds an image `FROM` ours, or picks `native`.

#### Per type

- **Kubernetes:** `docker` mode only. Session pods run the stock image with `aixle-runner`
  as PID 1. The kubelet is the container runtime, so the mode is a fact of the type, not a
  setting. `config.image_override` is allowed only for images built `FROM` our base image,
  and the runner checks the prerequisites at check-in.
- **Coder, `docker` mode (default):**
  - `inject_bootstrap` installs `aixle-runner --mode host` on the workspace.
  - The **host runner** holds the environment credential and the journal, and polls the
    environment's ops. It executes `image.ensure`, `container.start` / `container.stop`,
    `env.scrub` and `env.reset` itself. Per session it starts one container named
    `aixle-<environment key>-<session id>` from the agent image pinned by digest. Its own
    binary is bind-mounted read-only as the container's PID 1 in `session` mode.
  - The **session runner** in the container runs the session ops (`exec`, `write_file`,
    `read_file`, `status`, `logs`), the live-log tail and the callback proxy (§6.6). It
    reaches the gateway **through the host runner** over a Unix socket mounted into the
    container. The host runner forwards the protocol unchanged and adds the environment
    credential. So the environment credential never enters the container, and an agent
    that reads its own filesystem cannot take the runner's identity. That is stricter than
    `native` mode, where both share a user.
  - Restarting the host runner (self-update, crash) does not stop the agent. The container
    keeps running, the session runner buffers, and the host runner reattaches to the
    socket by container name.
  - Prerequisites checked at check-in: Linux amd64/arm64, a reachable Docker daemon
    (`docker version` API ≥ 1.41), and 20 GiB free for images plus the workspace volume.
    A missing prerequisite makes the environment `failed`, with the reason.
- **Coder, `native` mode (opt-in):** revision 1's model. Sessions run directly on the
  workspace under the session runner, so the agent sees the template's tools as installed.
  - Prerequisites: Linux amd64/arm64 (glibc), `bash`, `git`, `tmux ≥ 3`, `curl`, `tar`,
    5 GiB free.
  - The agent CLI comes from a **toolcache** (`~/.aixle-runner/tools/<runtime>/<cli_version>/`),
    filled from per-runtime session kits built from `config/agent_runtimes.json` pins.
  - `agent_runtimes` is limited to `claude_code`, `codex`, `gemini_cli`, `antigravity_cli`
    and `kiro_cli`. These are the runtimes whose usage accounting works without the MITM
    proxy (see the cost table in `app/frontend/pages/Docs/data/pages/runtimes.md`).
  - There is no ttyd or watcher until they are packaged for the host.
  - `native` is **not in the first customer-usable slice.** It ships after `docker` mode
    (task 18, §15).

#### Container options in `docker` mode (`config.docker`)

Access from the container to the machine is **explicit**. Nothing is shared unless the
runner's config says so. The adapter validates these options, and the runner page lists
them, because each one widens what the agent can touch:

| Option | Default | Effect |
| --- | --- | --- |
| `workspace_volume` | on | A per-environment named volume `aixle-ws-<key>` mounted at `/workspace`. This is what keeps repository checkouts warm across sessions (§7.1). |
| `cache_mounts` | `[]` | Extra named volumes or host paths for package caches, e.g. `~/.cache/pip:/home/agent/.cache/pip`. |
| `home_mount` | off | Bind-mounts the workspace user's `$HOME` (read-only by default) to give the agent the template's dotfiles and tools. |
| `docker_socket` | off | Mounts `/var/run/docker.sock`. This **gives the agent root on the workspace**. The form says so, and it is refused unless the runner is explicitly flagged `allow_privileged_mounts`. |
| `network` | `bridge` | `host` drops network isolation, for customers who need the agent on the workspace's own interfaces (a VPN client on the host). |
| `pid` | `private` | `host` drops PID isolation. |
| `extra_mounts` | `[]` | Arbitrary `src:dst[:ro]` bind mounts, validated as absolute paths. |
| `resources` | from the hosted pod spec | `--cpus` / `--memory`, so a session cannot starve the workspace. |

The container receives the same environment variables the hosted pod spec sets for the
image, with the callback URLs rewritten to the session runner's local proxy (§6.6). How
that env is assembled is a `RunnerRuntime` concern, so there is no strategy change.

**Image size.** Agent images are pulled from GHCR on the workspace (or through the
customer's registry mirror) and kept on the workspace disk between sessions, so only the
first session on an environment pays for the pull. `image.ensure` reports the pull time,
and the bootstrap timeout counts it. The staging template prunes the Docker **build**
cache. Before phase 3 it should be checked that this does not also remove pulled images
(§12.4).

---

## 7. Lifecycle and reset

### 7.1 Fresh vs. reused

- `kubernetes`: **fresh per session** (ephemeral pod). The image provides the warm state.
- `coder`: **the workspace is reused by default** (`reuse_policy: reuse`). Workspaces keep
  their disk. In `docker` mode the agent container is always fresh per session, and what
  stays warm is the pulled agent image, the `/workspace` volume with its repository clones,
  and any configured cache mounts. In `native` mode, clones, package caches and the
  toolcache stay on the workspace disk. `reuse_policy: fresh` rebuilds the workspace per
  session for customers who want hosted-like isolation and accept the cold start.

### 7.2 Scrub, reset, rebuild

| Level | What it wipes | What it keeps | When |
| --- | --- | --- | --- |
| **Scrub** (`env.scrub`) | `docker` mode: the session container (removed with `docker rm -f`, which takes the agent home, credential files, MCP config, prompt, context files, `/tmp` and every process with it), `/workspace/outputs` on the volume, and anything the strategy wrote to a writable cache or home mount. `native` mode: agent credential files and the agent home config the strategy wrote, the MCP config, the session prompt and context files, `/workspace/outputs`, `/tmp/aixle-*`, the session's tmux server and every process the session started (process group), and the env the runner exported | Repository checkouts, package caches, pulled images (`docker`), toolcache (`native`) | **After every session on a reusable environment, always**, before it returns to `idle`. Not optional: it is what makes reuse safe. A failed scrub leads to rebuild |
| **Reset** (`env.reset`) | Scrub, plus the whole workspace (`docker`: the `aixle-ws-<key>` volume and cache volumes; `native`: `/workspace`, including repository checkouts) | Pulled images or toolcache, OS-level caches outside the workspace | Manually ("Reset" on an environment); forced for one run ("Start from a clean workspace" on the run drawer or session form, sets `reset_requested=reset` on the assigned environment before `exec`); **automatically after a failed session** on that environment |
| **Rebuild** (adapter `reset level: :rebuild`) | Everything: the workspace is deleted and re-created from the template | Nothing | Manually; automatically when a scrub or reset fails, after `runners.max_consecutive_failures` (default 3) failed sessions in a row on one environment, or when the environment is needed by another project (§9.4) |

The repository bootstrap that `SessionContextService` already does (clone, or fetch and
repair) is what makes a kept checkout safe to reuse: an existing clone is fetched and reset
to the requested ref, not trusted as-is. `Coder::RepoBootstrap` exists for the same reason
on the MCP-tool path.

### 7.3 Allocation and concurrency on reused environments

`Runners::Allocator.acquire(session)`, under a `FOR UPDATE SKIP LOCKED` lock on candidate
rows:

1. An `idle` environment of this runner bound to the session's project with
   `last_workflow_id = session.workflow_id` (warm-cache affinity).
2. Otherwise any `idle` environment bound to this project.
3. Otherwise any `idle` unbound environment.
4. Otherwise, if `count(non-gone environments) < max_environments`, insert a new
   `runner_environments` row in `requested`, bound to the session's project, in the same
   transaction. After commit, call `adapter.provision` for it (§5.1).
5. Otherwise raise `CapacityError`, and the session waits in the existing admission
   capacity wait.

**Two overlapping runs of the same workflow:** the second one gets **another environment**
(step 2–4), never the same one. If the pool is full it **queues**. It is never refused, and
it never falls back to `hosted`. That answers the open question with "fall back to a fresh
environment while there is room, then queue". Refusing would turn a capacity condition into
a user-visible error. Sharing one disk between two agents would corrupt checkouts. Hosted
fallback is ruled out by §8.

---

## 8. Failure paths

The rule: **every failure names the runner and what to do, and nothing falls back to
`hosted`.** A silent fallback would run code that was meant for a private network on shared
infrastructure, with credentials the customer meant to keep inside their perimeter.

| Condition | Detected at | Outcome | Message (to the run, session and board comment) |
| --- | --- | --- | --- |
| Runner deleted, disabled or revoked | Launch (`Runners::Resolver`) | Fails before admission, `runner_unavailable` | "Runner "X" is disabled. Re-enable it or pick another runner on the workflow." |
| Runner not visible to the project | Launch | Fails, `runner_forbidden` | "Runner "X" is not available to project P." |
| Runner `unreachable` (health or controller silent) | Launch | Fails, `runner_unreachable` | "Runner "X" is unreachable since 14:02: controller has not connected for 6 min." |
| Agent runtime or session mode not supported by the runner | Selection, publish, launch | Refused or fails | "Runner "X" can't run interactive sessions yet." |
| At `max_concurrency` | Admission | Queued, wait reason `runner_limit` | Shown as queued with the runner named |
| At `max_environments`, or provider capacity (Coder quota, unschedulable pod) | `create_container` | `capacity_wait`, wait reason `runner_capacity`, reservation kept (session-admission §7) | "Waiting for capacity on runner "X"." |
| `provision` fails (template error, image pull, RBAC) | `create_container` | Diagnosed failure, environment `failed` | Provider message, e.g. "Coder: template parameter `instance_type` invalid" |
| Runner never checks in | `start_container` after `runners.bootstrap_timeout` (default 10 min, 15 for `coder`) | Fails, environment `failed`, teardown | "Environment started but aixle-runner did not check in within 10 min. Check egress to flow.aixle.com:443." plus the last bootstrap output the adapter captured |
| Prerequisites missing | Check-in | Fails, environment `failed` | `docker` mode: "Workspace has no reachable Docker daemon." `native` mode: "Workspace is missing tmux ≥ 3." |
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
| Registration (Kubernetes) | Runner creation, or "Rotate" in the UI. Shown once | Single use, expires in 24 h if unused | Calling `register` once for this runner | Digest only |
| Controller access / refresh | `register` | Access 1 h. Refresh rotates on every use and becomes invalid after 30 days idle | Polling **controller ops of this runner** (provision, teardown, observe); posting results; minting nothing | Digest only. Refresh-token reuse detection revokes the whole family and marks the runner `degraded` ("credential reuse detected") |
| Bootstrap | Per environment, at `provision` | Single use, 30 min (or `bootstrap_timeout`, whichever is longer) | Calling `check-in` for **this environment** | Digest only. Delivered by Coder SSH stdin or by a k8s Secret the controller deletes after check-in |
| Environment access / refresh | `check-in` | Access 1 h, rotating refresh. Invalid the moment the environment leaves `idle`/`busy`/`resetting` or the runner is revoked | Polling **this environment's ops**; posting logs, events and results for the session **currently assigned** to it; the proxy for that session only | Digest only |

Every request re-checks the runner's status (cached for ≤ 5 s), so revocation takes effect
within seconds and does not wait for tokens to expire.

**What a compromised runner can reach:**

- **An environment credential:** the data of the sessions that run on that environment
  (unavoidable, since it is the customer's machine), and the MCP tools of the session
  currently assigned, while it is live. It **cannot** pull work. Ops are pushed by
  assignment, and there is no "give me any job" call. It cannot address another
  environment's ops, read other sessions, or mint tokens.
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
  - `ghcr.io` for agent images and the runner image (`docker` mode and Kubernetes);
  - the git hosts of attached repositories;
  - the model provider, or the customer's Bedrock through their cloud connection;
  - whatever the agent's own work needs.
- **Inbound to the platform:** `/runner/v1/*` on the public ingress, rate-limited per token,
  with request bodies capped. The internal endpoints the proxy reaches stay internal.

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
| **Project → Settings → Runners** (new page next to Integrations) | Two sections: "From your company" (read-only, link to the company page for admins) and "This project". "New runner" for admins and the owner. |
| **New runner form** | Step 1: pick a type (cards; the type list comes from the adapter registry, so a new type shows up without UI work). Step 2: the type's form generated from `config_schema` — Coder: integration select (visible ones), template, parameters, execution mode (`docker` preselected, `native` with the trade-off spelled out) and the `docker` options from §6.8, reuse policy, max environments; Kubernetes: namespace, resources, image override. Step 3: limits. Then **Connect**: Coder runs `validate_config` + `check_health` inline; Kubernetes shows the one-time registration token and `helm install` command, and waits for the controller with a live status. |
| **Runner page** | Status and health facts, capabilities, execution mode and the container options that widen access (§6.8), the documented egress list (§9.5), runner version against `recommended_version` (§14.2), environments table (state, bound project, current session link, last used, version; actions Reset / Rebuild / Force release), workflows using it, Disable / Revoke / Rotate token / Delete. |
| **Workflow builder → Base Resources** (`BaseResourcesTab.tsx`) | "Runner" select: `Hosted (default)` + visible runners with status. Inline warning when the referenced runner is not usable (§3.4) or incompatible with an interactive step (§4). |
| **Run drawer** (`RunWorkflowDrawer.tsx`) | "Runs on" select defaulting to the workflow's runner. For an external runner a one-line note: "Your agent login is used on this runner, which is operated by *Company/Project*." |
| **New session form** (`SessionNewForm.tsx`) | Same select and note. Interactive mode greys out runners without `interactive_terminal`. |
| **Session page, run page, step list, board task run history** | A "Runs on" badge: `Hosted`, or `Prod VPC · coder`, linking to the runner and environment. "Open in Coder" when `human_accessible`. A connection-lost banner (§6.7). This is where users see where a run actually executed. |
| **Admin (Administrate)** | Runners and environments dashboards for support. |

Everything ships behind the flag (§12.1). With the flag off none of these surfaces render,
and the API refuses `runner_id`.

---

## 12. Rollout

### 12.1 Flags

- **Deployment:** `Settings.runners.enabled` (`RUNNERS_ENABLED`, default `false`), read
  through `Settings` per the `NoEnvInApp` cop. It gates the gateway routes, the UI props and
  the API fields.
- **Per company:** `companies.runners_enabled` (boolean, default `false`), following the
  per-tenant column precedent (`managed_by_aixle`, `steps.bmad_enabled`). Toggled from
  Administrate. Both flags must be on.
- **Per type:** `Settings.runners.types` (default `["coder"]`), so Kubernetes can ship dark
  after Coder.

### 12.2 Delivery order

Each phase leaves `develop` releasable and the hosted path untouched.

1. **Model and CRUD, no execution.** Tables, policies, the runners pages, the builder,
   drawer and form selects. A run with an external runner fails with "runner execution not
   enabled". This validates the scopes, permissions and failure messages before any code
   runs remotely.
2. **Protocol, gateway, `aixle-runner` (`host` and `session` modes).**
   - The protocol is written down as a specification, `runner-protocol/PROTOCOL.md`.
   - **The conformance fixtures are committed in this phase** (`runner-protocol/fixtures/v1/`,
     §14.1), and the gateway's Rails tests run them from the first PR. They are the contract
     the Go implementation is written against, and what makes the later extract safe. So
     they are not deferred, even while only the Ruby side runs them.
   - Separate CI lanes for the Go code (`go test`, lint, the Go side of conformance) **may
     be deferred**. Until they exist, `runner/` is built and tested locally and in the
     release lane only.
   - A dev-only `local` adapter starts a host runner as a container on the Compose network,
     with the Docker socket of the dev machine. The whole path is then testable in Docker,
     with no Coder needed.
3. **Coder adapter in `docker` mode, end to end**, for non-interactive workflow steps, all
   agent runtimes. Staging validation (§12.4). This is the first customer-usable slice.
4. **Interactive tunnel:** a WebSocket from the session runner, through the host runner,
   relaying ttyd, the IDE and the watcher, with the session page connecting to the platform
   instead of Traefik. `interactive_terminal: true`.
5. **Kubernetes controller and Helm chart** (in `AixleHQ/aixle-runner`, §14.1).
   Prerequisite: document the agent image sizes and pull times from GHCR for customer
   clusters, and the mirror option.
6. **Coder `native` mode:** toolcache session kits, the native allow-list, and a request
   logger for MITM-log-based usage if `cursor_cli` and `grok` are wanted natively. Then GA
   and user docs (`pages/Docs`).
7. **Later, not proposed now:** hosted onto the interface (§13).

**Interactive sessions: decided.** The first customer-usable slice (phase 3) is
**non-interactive only**, enforced by `interactive_terminal: false` (§4). The tunnel
**moves up to phase 4**, ahead of Kubernetes. In revision 1 it was phase 5, after
Kubernetes.

- **Why v1 can ship without it.** The reasons for a runner (private network, the
  customer's environment, capacity, perimeter) are about the work an agent does. Today
  that work arrives through workflow steps: board-column automation, tracker and chat
  triggers. Those are non-interactive. A customer can put its automated SDLC workflows on
  its own Coder runner without ever opening a terminal. On Coder, `human_accessible: true`
  also gives a debugging path that the platform does not need to build: Coder's own web
  terminal and SSH into the workspace, and `docker exec` into the session container.
- **Why the tunnel moves ahead of Kubernetes.**
  - In `docker` mode ttyd, the IDE server and the watcher already run inside the session
    container, exactly as in a hosted pod. The tunnel is only a relay: one WebSocket out
    from the runner, and a platform endpoint the session page connects to in place of the
    Traefik IngressRoute. It does not depend on the runner type, so building it once serves
    Coder now and Kubernetes later.
  - Kubernetes is a second type. The tunnel completes the first one. A Coder customer
    reaches parity with hosted (interactive and standalone sessions) before a second type
    is added.
  - Without the tunnel, every interactive step in a workflow blocks that workflow from
    being published on a runner (§4). Mixed workflows are common enough that this would be
    the first support question.
- **What would change this order.** If the first non-staging customer needs Kubernetes and
  not Coder, swap phases 4 and 5. The two phases are independent, so the swap costs
  nothing.

### 12.3 The hosted runtime is not touched

Every change to a shared file is a guarded branch whose hosted arm is today's code:

- `ContainerRuntime.for_session` (§5.3);
- one line in `pool_configuration` (§10);
- `WHERE runner_id IS NULL` on the two hosted scanners;
- the env-var rewrite, which lives in `RunnerRuntime`;
- nullable columns.

Phase 1 adds a test that runs the existing hosted admission and launch tests with the flag
**on** and asserts the same Kubernetes calls are made, so "unchanged" is checked by a test
and not assumed.

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

### 12.4 Validating the first Coder runner on staging

Validation runs against **the staging Coder integration already configured on the test
project**, with whatever workspace template that integration offers at the time of
testing. This design names no template and no template version on purpose: the template is
a property of our staging environment and will drift, and the runner has to work on a
template the design never saw, which is also the customer case. What the validation needs
from the chosen template is checked at test time, not assumed here:

- it can run a Docker daemon, which is the only `docker`-mode prerequisite (§6.8). If it
  cannot, the runner reports that at check-in, which is itself a check of the §8 message;
- its disk covers an agent image plus the workspace volume (§6.8);
- if it prunes images or build cache on a schedule, the warm-image result of step 5 is
  read with that counted.

The template used, and the answers to these three, are recorded in the validation task's
result, so a later re-run knows what it is comparing against.

1. Create a project runner on the staging test project over its existing Coder
   integration: one of the templates the integration offers, `execution_mode: docker`
   (the default), `max_environments: 2`.
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
   exactly as on hosted, which confirms `agent_runtimes: all` in `docker` mode.
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
| `inject_bootstrap` | Step A: no-op, keep exec through `KubernetesRuntime`. Step B: the pod gets `aixle-runner` as PID 1, as on customer Kubernetes and in Coder `docker` mode, and connects to the gateway from inside the cluster |
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
right after phase 3, the first customer-usable slice, so **the extract is expected before
the Kubernetes adapter ships in phase 5**. So the chart lane is built in
`AixleHQ/aixle-runner` from the start, and **`charts/` is never created in `flow`**. If the
extract slips past the start of phase 5 after all, the chart goes under `runner/chart/`.
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
  special story beyond that. Agent image size is a phase 5 prerequisite for Kubernetes
  (§12.2).

### 14.4 Skew, self-update and where the runner lands

- **Skew policy:** the platform supports **the current and previous protocol version** and
  any runner ≥ `min_version`. Below that, `check-in`/`register` is refused with the upgrade
  message (§8). **A run never starts on an unsupported runner, and it is never killed
  because a newer runner came out.**
- **Self-update:**
  - **Runners on reusable environments self-update.** That means the host runner in Coder
    `docker` mode, and the session runner in `native` mode. When the check-in response or
    an idle poll carries `update: {version, url, sha256}`, the runner downloads from the
    release URL, verifies the digest, and re-execs. This happens only while the
    environment is `idle`, never during a session, and only towards
    `recommended_version`. The session runner inside a `docker`-mode container is the host
    runner's own binary, so it is updated with it. Ephemeral pods never need an update,
    because the platform picks their version (§9.6).
  - **The controller does not self-update.** It is Helm-managed, and customers running
    GitOps would see that as drift. It reports its version, and the runner page shows
    "update available" (`degraded` if below `recommended`, refused if below `min`). A
    protocol bump is announced one release ahead because the previous protocol stays
    supported.
- **Where it lands:**
  - **Coder:** `inject_bootstrap` pipes `install.sh` over `coder ssh` stdin. The script
    fetches the binary through the platform's release URL (302 to the GitHub asset),
    verifies its SHA-256, installs it to `~/.aixle-runner/bin`, and starts it detached in
    `host` mode (or `session` mode for `native`). It uses `setsid`, and a systemd user
    unit where available, so the runner survives the SSH session. On a reused workspace a
    live runner is detected and not re-installed.
  - **Kubernetes:** the init container and image as in §9.6.
  - **New type:** its adapter implements `inject_bootstrap` with whatever "run this script
    once" primitive the provider has. That is the only per-type part of distribution.

---

## 15. Implementation breakdown

Each item is independently reviewable and lands behind the flags. The number is the phase
from §12.2.

| # | Phase | Task |
| --- | --- | --- |
| 1 | 1 | Migrations and models: `runners`, `runner_environments`, `runner_credentials`, nullable `runner_id` refs, `Encryptable :runners_key`, status state machine, `visible_for_project`, flags (`Settings.runners`, `companies.runners_enabled`). |
| 2 | 1 | Policies and controllers: company and project runners CRUD with §3.2 rules, `Runners::Adapter` registry + `config_schema`, `CoderAdapter#validate_config`/`check_health` only. |
| 3 | 1 | Frontend: Company Settings → Runners tab, Project → Runners page, new-runner form generated from schema, runner page (without environments). |
| 4 | 1 | Selection: `workflows.runner_id` in the builder (Base Resources) and the version snapshot, run-drawer and new-session selects, `Runners::Resolver` with launch-time checks and §8 failure messages, `runner_id` frozen on `workflow_runs`, "Runs on" badges. |
| 5 | 2 | Gateway process type, `runner_operations` queue with LISTEN/NOTIFY long-poll, token issuance and rotation (`runner_credentials`), rate limits. |
| 6 | 2 | `aixle-runner` (Go, self-contained `runner/` with its own `go.mod`, §14.1). `session` mode: check-in, poll and execute (`exec`, `write_file`, `read_file`, `batch`, `status`, `logs`), log shipping, heartbeat, reconnect and resume, the local proxy. `host` mode: environment credential and journal, `image.ensure`, `container.start`/`stop`, the Unix-socket relay for the in-container session runner, scrub and reset. |
| 7 | 2 | `runner-protocol/PROTOCOL.md` and the conformance fixtures in `runner-protocol/fixtures/v1/`, **committed in this phase** and run by the gateway's Rails tests. The Go side of conformance and the Go CI lanes may follow later (§12.2). |
| 8 | 2 | `ContainerRuntime::RunnerRuntime` + `ContainerRuntime.for_session`, env-var rewrite for proxied routes, live-log chunks for `LiveLogReader`/`NoOutputWatchdog`, dev `local` adapter and Compose service. |
| 9 | 2 | Admission: `runner:<id>` pools, company ceiling exclusion, `runner_limit`/`runner_capacity` wait reasons, hosted scanners skip runner sessions, the "hosted unchanged with flag on" regression test. |
| 10 | 3 | `Runners::Allocator` and environment state machine: affinity, project binding, `max_environments`, scrub, reset and rebuild, reconciliation pass. |
| 11 | 3 | `CoderAdapter` provision, prepare, inject_bootstrap, reset, teardown, observe over `Coder::Api`/`WorkspaceService`; `execution_mode` and `config.docker` schema and validation (§6.8), with capabilities derived from the mode; install script with SHA-256 verify and the `verify` hook; Docker prerequisite check. |
| 12 | 2 | Runner release lane: `runner-release.yml` for `runner-v*` (binaries, `checksums.txt`, GHCR image). `config/runner_release.yml` read through `Settings.runners.release`. The `/runner/v1/releases` redirect and checksums endpoints. The "Runner compatibility" section in `docs/operations/releasing.md` (§14.2). |
| 13 | 3 | Runner page environments table and actions (Reset, Rebuild, Force release), connection-lost banner, revoke flow, Administrate dashboards. |
| 14 | 3 | Staging validation per §12.4 in `docker` mode (QA task), on the staging Coder integration configured on the test project and a template it offers at test time. Record the template used and the §12.4 checks (Docker daemon, disk, pruning) in the result. |
| 15 | 3 | Tech-debt task for the two execution models, with the exit condition and trigger from §12.3, and the note in `base_runtime.rb`. |
| 16 | 4 | Interactive tunnel: a session-runner WebSocket relay for ttyd, the IDE and the watcher through the host runner, plus session page routing. Lifts `interactive_terminal: false`. |
| 17 | 5 | Kubernetes: `aixle-runner` controller mode, the Helm chart and its `runner-chart-v*` OCI lane in `AixleHQ/aixle-runner` (§14.1), `KubernetesAdapter` over controller ops, registration-token UX, documented agent image sizes. Preceded by the runner extract if it has not happened yet. |
| 18 | 6 | Coder `native` mode: toolcache session kits from `config/agent_runtimes.json` pins, the `toolcache.ensure` op, the native allow-list. Optionally a runner request logger for `cursor_cli`/`grok` natively (P2). User docs. |

---

## 16. Open items and what would settle them

- **P1, latency of op-per-primitive context assembly.** Recommendation: `batch` coalescing
  (§6.4). Settled by measuring a real `before_exec` against a staging Coder workspace in
  task 8: the target is under 5 s added over hosted. If it misses, move
  `SessionContextService` writes to one tarball op. The protocol already allows that.
- **P2, usage parity without the MITM proxy in `native` mode.** This no longer blocks the
  first iteration. `docker` mode carries the image's MITM proxy, so every agent runtime is
  accounted for as on hosted (§6.8, checked in §12.4 step 6). It matters only if
  `cursor_cli` or `grok` are wanted in `native` mode. That is settled by a prototype in
  task 18, and until then the native allow-list applies.
- **Coder control planes not reachable from the platform.** Not served in v1.
  Recommendation: the controller mode with a Coder backend (provisioning from inside, the
  same adapter contract). Settled by the first customer who asks for it.
- **Step-level runner.** Deliberately out of scope (§3.3). Revisit if users split
  workflows only to change network.
- **Interactive sessions in the first slice.** Decided in §12.2: the first slice is
  non-interactive only, and the tunnel moves up to phase 4, ahead of Kubernetes.
- **Billing for external sessions.** Still an open product decision, not a design one.
  The design keeps every answer possible:
  - `runner_id` is recorded on sessions and usage rows;
  - external sessions do not draw down `CompanyCapacityUsage` (§10).

  What would settle it is the pricing decision for the first non-staging customer. It has
  to be made before trigger 2 of §14.1, and nothing earlier depends on it.
