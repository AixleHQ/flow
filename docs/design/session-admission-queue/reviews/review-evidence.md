# Evidence and technology-fit review

Date: 2026-09-05. Reviewer: review_code_evidence.

Scope: architecture spine, technical design, application checkout and sibling aixle-infra checkout. This was read-only design review. No production database, Kubernetes cluster or secret files were inspected.

**Initial verdict: two corrections required.** PostgreSQL admission and Temporal fit the stack. Namespace scope and effective-quota arithmetic were supported by source evidence. The installation-versus-company choice was explicitly open at this review stage; the later Marketplace requirement resolved it.

## E1: Runtime capacity waiting still matched the 30-minute reaper

Affected: section 6, section 7/A5 and AD-7/AD-8.

After admission, provisioning changes the session to running. Namespace quota and cluster capacity waits use wait_reason, so merely exempting queued leaves them eligible for the age-only reaper. A node becoming available after 40 minutes would arrive after the reaper had failed the session, despite the proposed 24-hour capacity-wait budget.

Evidence: [CleanupStaleActivity](../../../../app/temporal/activities/session/cleanup_stale_activity.rb) uses a 30-minute running threshold and originally cancelled/cleaned matching sessions without Temporal liveness checks. Kubernetes Pending maps to runtime status starting, not a separate session state.

Correction: exempt capacity waits from ordinary age-only provisioning cleanup; use phase deadlines and liveness. Unknown Temporal responses are not proof of expiry. Test a wait longer than 30 minutes followed by successful startup, and execution-budget expiry separately.

## E2: Quota deletion needs namespace ownership and an audited UID

Affected: sections 9-10 and AD-10.

Legacy aixle-resource-quota objects have only name/namespace metadata. Ownership labels belong to their Namespace. Applying a runtime-origin selector directly to quotas would find nothing; weakening it to a prefix alone could delete an operator-owned quota.

Evidence: [KubernetesRuntime](../../../../app/services/container_runtime/kubernetes_runtime.rb), especially quota creation, resource labels and namespace-label construction. Existing namespaces are not necessarily retroactively labelled by the ensure path.

Correction: inventory namespaces by verified origin/scope and expected name, GET the exact quota, and record namespace/name/UID/spec in a reviewed manifest. Delete only the reviewed UID with a precondition. Unlabelled namespaces or changed objects require another review, not a weaker selector.

## Source-backed findings

| Concern | Evidence and implication |
|---|---|
| Pool precedence | Current namespace selection uses project before user; these limits do not stack |
| Capacity unit | Agent/auth/workflow sessions have strategies; standalone tools are separate and could deadlock if they shared their caller's slot |
| Concurrency | Production web/MCP and worker replicas scale independently; a process-local semaphore cannot enforce a shared cap |
| Delivery | Existing outbox/reconciliation patterns and Temporal schedules support periodic recovery without another broker |
| Cleanup | Callbacks clear container_id, and cleanup may suppress errors; neither session state nor accepted deletion proves absence |
| Parent clocks | Parent waits are 23 hours and the stale-run reaper is age-only at 4 hours; both need queue-aware behavior |
| Cutover | Runtime creates quotas, so a YAML edit alone cannot remove them; cleanup requires appropriate RBAC |

Project/User defaults are 100 Pods, 4000m CPU limits and 8Gi memory limits. Homogeneous agent Pod limits are 1000m/1Gi by default, 2Gi memory in staging and 3Gi in production. In an empty namespace with no other policy, the resulting estimates are 4, 4 and 2 Pods. These are declaration-based estimates, not production inventory. Nil override fields inherit defaults.

Web and workers consume the app ConfigMap through envFrom. Inspected production ResourceQuota permissions were create/get/update; audited cleanup needs list/delete on an appropriate migration identity. Namespace networking and per-Pod limits remain independent of business admission.

Official references: [Kubernetes quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/), [PostgreSQL 18 locking](https://www.postgresql.org/docs/18/explicit-locking.html) and [Temporal Ruby Client](https://ruby.temporal.io/Temporalio/Client.html). They do not replace tests against pinned Temporal SDK 1.7.0 or live-version verification.

## Recheck and limitations

**Final evidence-review verdict: PASS.** E1 was addressed by explicit capacity-wait exclusion and a separate deadline/liveness contract. E2 was addressed by namespace ownership checks and an exact reviewed quota UID allowlist. Original findings remain above as review history.

The recheck covered these design corrections only. It did not validate runtime recovery, concurrency implementation, deployed versions, production N or existing scope overrides.
