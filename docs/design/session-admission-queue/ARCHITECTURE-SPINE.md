---
name: session-admission-queue
type: architecture-spine
purpose: build-substrate
altitude: feature
paradigm: transactional admission control with outbox and reconciliation
scope: TerminalSession concurrency and queued execution in app and aixle-infra
status: final
decision_status: proposed
created: 2026-09-05
updated: 2026-09-05
sources:
  - app@32efafaa
  - aixle-infra@c4bff01
companions:
  - TECH-DESIGN.md
---

# Session admission architecture contract

**Status:** Built 2026-09-05 (#201). Where the build departs from this contract as first written: the budget is the company's, not the installation's (#297), so `SESSION_CONCURRENCY_LIMIT` is read by nothing; admission is always on and cannot be paused (#325); a session without a project queues in a per-user pool (#325); and a pinned reservation is released once absence has been proven for a confirmation window (#286). AD-1, AD-5 and AD-10 below say so. Operations are in [ROLLOUT.md](ROLLOUT.md).

Decisions A1-A5 and their rationale are in the [technical design](TECH-DESIGN.md). A1, an installation-wide pool for AWS Marketplace, was replaced by the per-company budget.

## Design paradigm

PostgreSQL owns the queue, policy and permits. Temporal owns execution. The runtime supplies resource facts. Relay and reconciliation recover delivery and consistency.

```mermaid
flowchart LR
  Callers[API / workflow steps] --> Admission[SessionAdmissionService]
  Admission --> DB[(PostgreSQL)]
  Relay[SessionLaunchRelay] --> DB
  Relay --> Temporal[ContainerWorkflowV2]
  Temporal --> Activities[Activities / strategies]
  Activities --> Admission
  Activities --> Runtime[Kubernetes / Docker]
  Reconcile[Reconciler] --> Admission
  Reconcile --> Runtime
```

## Invariants and rules

### AD-1: One applicable pool, one company budget over a company's pools

- **Binds:** policy resolver, enqueue and administration.
- **Prevents:** inconsistent combinations of company and project limits across launch paths.
- **Rule:** a session belongs to exactly one pool: its project's (`project:<id>`), or, for a session with no project — in practice an agent login — its user's (`user:<id>`), two at a time (`SessionAdmissionService::AUTH_POOL_LIMIT`), which draws on no company's limit. A company's limit (a `SessionConcurrencyLimit` row with scope `Company`; none means unbounded) is a ceiling over that company's project pools at once rather than a pool of its own, and an explicit project limit is a **reservation** drawn from it: the project can always reach that number, because nothing else may occupy it. Every project of the company without one shares the remainder — the company limit less its reservations and the occupancy of its unreserved projects — bounded individually by the scope default (`SESSION_PROJECT_CONCURRENCY_DEFAULT`). A reservation is validated against its company's limit when it is saved. A company limit may be lowered beneath its reservations, so that a downgrade is never blocked; the drain then clamps every pool of the company, reserved ones included, to the company's headroom, the reservations compete, and `QueueHealthCheck` reports the over-commitment. There is no installation ceiling: `SESSION_CONCURRENCY_LIMIT` is read by nothing (#297). Admission is always on and has no pause (#325). **Superseded twice:** first the original rule, under which the ENV selected installation-wide pooling *instead of* per-project pools; then the installation ceiling over project pools (#278), which could not express an installation running several organisations. DB policy and revision are authoritative; every limit change bumps the revision and drains. The proposed protocol uses policy SHARE for admission and UPDATE for mutations; the implementation conservatively uses UPDATE for all short admission transactions. Refresh derived pool limits before issuing grants.

### AD-2: Capacity unit and ownership

- **Binds:** SessionService, workflow-step launch, runtime and quota migration.
- **Prevents:** bypass through another session type or web replica.
- **Rule:** agent_session, workflow_step and auth_setup each consume one slot. Standalone tools are excluded. Every supported new session has one unique admission. After cutover, session runtime creation requires a valid admission/token. Resolve company ownership through SessionCompany; never guess from memberships. A whole WorkflowRun does not hold a slot.

### AD-3: Atomic FIFO

- **Binds:** enqueue, drain, cancel, release and limit updates.
- **Prevents:** exceeding capacity or bypassing the queue under concurrent requests.
- **Rule:** the proposed lock order is policy SHARE, optional WorkflowRun, optional StepRun, pool, admission, session and runtime operation; writers begin with policy UPDATE. The implementation serializes short decisions with policy UPDATE. Allocate a globally unique immutable FIFO ordinal from a DB sequence under the admission lock. Recheck the head and eligibility before granting. Occupancy is admitted/unreleased rows. A grant requires occupancy below the locked cap; decreases do not evict existing sessions. Keep network calls and external callbacks outside these transactions.

### AD-4: Durable launch intent

- **Binds:** SessionService, relay, TemporalService and container workflow v2.
- **Prevents:** losing a launch between DB commit and Temporal, or executing an agent twice.
- **Rule:** granting atomically stores an immutable permit and pending launch intent. Relay claims are durable; claim expiry never releases the slot. Use `agent-session-<id>` as workflow identity. Recover an existing execution; do not restart a closed one. Closed admissions never dispatch. Initial/create activities validate the permit and stop marker. Preserve errors for reconciliation.

### AD-5: Unknown creation retains capacity

- **Binds:** runtime create/start/exec, cancellation, cleanup and reconciliation.
- **Prevents:** a late Pod appearing after its slot was reassigned.
- **Rule:** persist a runtime-operation envelope before side effects. Cover Pod/Docker creation and startup as well as session routing resources and readiness repairs. Verify stable identity and ownership when adopting resources; use UID preconditions on deletion. Stop markers prevent new attempts but cannot revoke an already sent RPC. Unresolved operations that could still materialize a workload — creation and startup — block release until completion or quiescence is established. An unresolved operation that can only act inside a container whose absence is already confirmed (exec) is recorded and reported, but retains no slot: it has nothing left to bring into existence, so holding capacity for it only leaks the slot. A DB token is not Kubernetes fencing. GET 404, timeout and a closed Temporal execution do not prove that a late create is impossible. Unresolvable uncertainty retains the slot. Since #286 the reconciler releases it once absence has been proven on every pass for `SESSION_PINNED_RELEASE_CONFIRMATION_MINUTES` (default 5), marking the operations `abandoned`; with `SESSION_PINNED_RELEASE_ENABLED=false` it requires operator evidence.

### AD-6: Confirmed release

- **Binds:** finish/cancel/fail, cleanup strategies and stale/orphan sweepers.
- **Prevents:** treating terminal UI state or accepted DELETE as proof of free capacity.
- **Rule:** only the admission service sets released_at, idempotently, after stopping possible creators and confirming absence of the workload and its session routing resources. Keep runtime identity outside the session's cleared container_id. Unknown runtime/node state, pending deletion and cleanup errors retain capacity. Permits have no TTL. Common namespace resources are preserved. Missed release wakeups are recovered by periodic drain.

### AD-7: Separate waiting and execution clocks

- **Binds:** state machine, API/UI/MCP, parent workflows, watchdogs and analytics.
- **Prevents:** classifying queued work as crashed execution or consuming its execution budget.
- **Rule:** queued_at starts queue time; started_at starts admitted provisioning; ready_at marks readiness. Before admission there is no container workflow or Pod. API create remains 201. Parent waits exclude queue time and reconcile durable child state. StepRun launch retries return the existing session. Cancelling a queued workflow-step session cancels its parent and marks the step cancelled without automatic failure retry; the UI labels the action accordingly. A durable run stop marker gates subsequent enqueue/grant/launch/operation registration, and reconciliation repairs cancellation fan-out. Queue waiting has no TTL. Queued sessions use active-session privacy rules; do not expose other tenants' queue details.

### AD-8: Runtime capacity is a separate wait reason

- **Binds:** KubernetesRuntime, phase activities and ContainerWorkflowV2.
- **Prevents:** turning temporary capacity pressure into immediate failure, or hiding RBAC errors behind endless retry.
- **Rule:** typed quota-capacity and Unschedulable results wait while retaining admission. Use bounded probes and Temporal timers. Exempt explicit capacity waiting from the ordinary 30-minute running reaper and use its execution deadline/liveness instead. Unknown transport outcomes follow AD-5. Diagnose RBAC, image, configuration and authentication failures separately. Runtime waiting consumes the admitted container's 24-hour budget; pre-admission waiting does not. Do not automatically return an already executed agent to the business queue.

### AD-9: Recovery does not require another request

- **Binds:** relay, reconciler, schedules and observability.
- **Prevents:** permanently stalled queues after lost wakeups or restarts.
- **Rule:** a registered minutely schedule repeats bounded drain, relay and reconciliation. Durable claims and DB locks provide correctness across replicas; schedule overlap settings alone do not. Recover lost start acknowledgments using stable workflow identity. Unexpected resources without permits require reconciliation rather than being counted as free. Diagnostics should cover queue age, uncertain operations, cleanup lag and policy/occupancy mismatches.

### AD-10: One migration gate

- **Binds:** application deployment, aixle-infra, quota migration and operators.
- **Prevents:** legacy workers bypassing admission or old quotas remaining an accidental business limit.
- **Rule:** deploy compatible states/APIs and v2 workflows, stop legacy producers/workers, drain executions and resources, then activate. Derive fallback limits from effective CPU/memory/Pod quotas, not max_pods alone. Disable old quota creation before audited deletion. Preserve per-Pod limits and namespace isolation. Retire quota RBAC only after cleanup. Mode changes and rollback require pause/drain. Version or drain parent histories too. This gate was the one-time cutover to admission; since #325 admission is always on, so there is no pause and no mode to change.

## Stack

Versions were checked in source; live cluster versions were not measured.

| Component | Version |
|---|---|
| Ruby | 4.0.6 |
| Rails | 8.1.3.1 |
| Temporal Ruby SDK | 1.7.0 |
| PostgreSQL, production Terraform default | 18.2 |

## Consistency conventions

| Concern | Convention |
|---|---|
| Permit ownership | One admission per session; unreleased admissions prevent deletion |
| Policy precedence | DB revision; the company's limit over its project pools; no pause |
| Runtime identity | Stable kind/name/namespace and verified ownership; UID preconditions for deletion |
| Launch recovery | pending/claimed/acknowledged/closed; repeated delivery does not repeat execution |
| Waiting UI | concurrency_limit, dispatch_pending, namespace_quota, cluster_capacity |
| Capacity guarantee | New grants do not exceed the cap; uncertainty reduces availability, never creates free slots |

## Deferred

- Multi-company pools within one shared SaaS deployment. No longer deferred: built in #297 (AD-1).
- Exact existing-scope overrides until deployment inventory is reviewed; proposed new-installation defaults are 2.
- Priority, weighted CPU/RAM scheduling, inter-company fairness and standalone-tool limits.
- Queue TTL and an expanded operational dashboard.
- A ceiling for sessions launched outside a project. No longer deferred: they queue per user, two at a time (#325, AD-1).
