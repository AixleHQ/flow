# Architecture coverage and coherence review

Date: 2026-09-05. Lenses: architecture-spine quality, requirements, operations and implementability.

Reviewed the spine, technical design and existing session/run watchdogs. This is review of a proposal; assumptions were not treated as approved requirements.

**Initial verdict:** the proposal covered the goal and major operational risks, but needed two high-impact corrections and clarification of ordering across mode changes.

## COV-1: A 30-minute watchdog could terminate a valid capacity wait

Affected: sections 6-7 and AD-7/AD-8.

A session waiting for Kubernetes capacity is already admitted and running. Excluding only queued leaves it vulnerable to the ordinary 30-minute reaper even though capacity waiting may consume the 24-hour execution budget.

Correction: explicitly exclude live namespace-quota/cluster-capacity waits from ordinary age-only cleanup. Use phase deadlines and Temporal liveness; an unavailable Temporal response is not proof that execution ended.

Verification: a Pod remains Pending for more than 30 minutes and later starts successfully; repeat for quota denial before Pod creation. Truly lost executions must still reconcile.

## COV-2: Policy and cached pool limits lacked an atomic transition

Affected: sections 3.1, 3.3 and 4.1-4.2; AD-1/AD-3.

Updating authoritative policy and derived pools in separate unsynchronized steps permits grants against an old cap after a successful decrease or pause. Different lock orders can also deadlock.

Correction: define one policy-first synchronization protocol for grants and policy/default/override changes. Refresh stale pool limits under that lock before granting. Define policy commit as the boundary after which old-cap grants are forbidden. Mode changes may use pause/drain.

Verification: independent DB connections change cap/default/pause while draining or creating pools. No post-commit grant may use stale policy.

## COV-3: Immutable pool-local tickets could collide during remapping

Affected: sections 3.3 and 4.1; AD-3 and deferred mode-change behavior.

Merging two project queues containing local ticket 1 into one installation pool violates uniqueness and does not define a deterministic original order.

Correction: use an immutable global enqueue ordinal, or explicitly separate immutable original order from remappable local tickets. The revised proposal selected a global DB sequence. The implementation requires all admissions to drain before changing mode.

Verification: any future queue remapping must preserve admissions and deterministic order even when source queues share timestamps.

## Coverage assessment

| Dimension | Assessment |
|---|---|
| Installation ENV and scoped fallback | Covered with one applicable pool |
| Company meaning | Explicit product decision, subsequently resolved for single-company Marketplace installations |
| Waiting instead of failure | DB queue, durable launch and runtime-capacity waiting covered |
| Session entry points | API, Builder, workflow steps and background launches identified; standalone tools explicitly excluded |
| Concurrency and delivery | FIFO, unique admissions, StepRun idempotency and durable launch covered; policy synchronization required COV-2 |
| Cancellation and release | Terminal UI state separated from resource release; late creates and cleanup uncertainty retain capacity |
| Operations | Shared DB ownership, schedules, inventory, RBAC, pause/drain, rollback and mixed deployments covered |
| Existing application fit | Namespace defaults, resource limits, non-retryable phases, cleanup callbacks and watchdogs considered |
| Complexity | Existing PostgreSQL and Temporal suffice; strict capacity justifies tracking uncertain external operations |
| Deferred work | Priorities, weighted scheduling, tool limits and live rebalancing can remain separate |

Holding a slot until routing cleanup is an explicit availability tradeoff, not a coverage defect. Diagnostics should distinguish live workloads from delayed route removal. Operator recovery requires evidence that an unknown publisher cannot act; GET 404 alone is insufficient.

## Recheck

**Final design-coverage verdict: PASS.** COV-1 was resolved by capacity-wait exclusion/deadlines, COV-2 by policy serialization and revision refresh, and COV-3 by a global immutable queue ordinal. This approves proposal coherence, not implementation correctness or production capacity. Product assumptions and operational defaults still require the stated deployment decisions.
