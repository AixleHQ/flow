# Review: concurrency, fencing and state ownership

Date: 2026-09-05. This records review of the original architecture draft and its corrections. It is a design review, not approval of the implementation or live deployment.

**Initial verdict: changes required.** PostgreSQL admission, durable launch intent and retaining permits under uncertainty form a suitable architecture. Four local gaps required clarification without adding another infrastructure component.

## INV-1: Policy changes and grants need one atomic boundary

Affected: AD-1, AD-3, AD-10; technical design sections 3.1, 3.3 and 4.1-4.2.

The original draft made DB policy authoritative but also cached limit and policy_revision in pools without specifying synchronization. A pool at cap 10 with occupancy 4 could issue six more grants after deployment committed cap 4. A stale resolver could similarly enqueue into the old pool after a mode change.

Correction: define one policy-first lock order. Admission holds a compatible policy lock through commit; policy/default/override/pause writers take UPDATE and increment revision. Refresh derived pool limits under lock before granting. The implementation's policy UPDATE serialization is a conservative specialization of this contract.

Verification: use separate DB connections to lower the cap while granting/enqueuing. No new grant after policy commit may use the old cap. Cover a stale resolver during mode changes.

## INV-2: Run cancellation needs a durable gate shared with new steps

Affected: AD-3, AD-7; sections 4.2 and 6.

The original cancellation flow signalled the parent, visited current children and only then changed run state. A concurrent step launch could arrive after fan-out and receive a permit before cancellation became visible.

Correction: persist a WorkflowRun stop marker under the shared lock protocol. Enqueue, grant, relay and runtime-operation registration check that marker. Perform external signals and idempotent child cancellation after commit, with reconciliation repairing interrupted fan-out. Previously registered external attempts remain subject to uncertainty and cleanup rules.

Verification: interleave cancellation with step creation/retry, grant and runtime registration. No operation may register after the stop commit; no child may escape recovered fan-out.

## INV-3: Fencing must cover every resource-creating operation

Affected: AD-5, AD-6; sections 4.1 and 4.4.

Protecting only initial Pod creation leaves later Docker start or Service/Middleware/IngressRoute creation able to finish after release. A DB permit check cannot atomically fence an external request.

Correction: record durable runtime-operation envelopes and stable identities, retain unknown attempts, and establish quiescence before cleanup/release. Include routing creation and readiness repair. Verify ownership during adoption and UID during deletion. Neither a missing object nor a closed workflow proves a delayed publisher is unable to act.

Verification: delay Pod, Service, Middleware, IngressRoute and Docker-start responses separately, then cancel. Release remains blocked until their outcomes are established; no session resource may appear after confirmed release.

## INV-4: Pool-local immutable tickets conflict with merging queues

Affected: AD-3, AD-10; sections 3.3 and 4.1.

Two project pools can both contain ticket 1. Reassigning those immutable tickets to one installation pool would violate uniqueness and leave their cross-pool order undefined.

Correction: allocate immutable globally unique ordinals from a DB sequence under the queue lock. Gaps are allowed. Any supported remap preserves that ordinal rather than using HTTP arrival time or ambiguous timestamps. The initial implementation requires a complete drain for mode changes.

Verification: cover identical timestamps and multiple queues when testing future remap support.

## Recheck

**Final design verdict: PASS.** The revised spine/design addressed policy serialization, a shared durable run stop marker, runtime-operation tracking and a global immutable FIFO ordinal. This does not establish implementation correctness or production capacity. The installation-versus-company choice was still open at initial review and was subsequently resolved by the single-company Marketplace requirement.
