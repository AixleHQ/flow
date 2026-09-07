---
title: Durable session admission queue
type: feature
created: 2026-09-05
status: in-review
baseline_commit: 32efafaa
review_loop_iteration: 0
context:
  - docs/design/session-admission-queue/TECH-DESIGN.md
  - docs/design/session-admission-queue/ARCHITECTURE-SPINE.md
---

<frozen-after-approval reason="User approved implementation of the preceding technical design">

## Intent

**Problem:** Kubernetes namespace quotas fail session launches instead of queuing them. Marketplace customers have one company per installation and buy concurrent-session capacity separately.

**Approach:** Persist FIFO admission and reservations in PostgreSQL, launch through Temporal with recoverable delivery, and release slots after confirmed runtime cleanup. SESSION_CONCURRENCY_LIMIT selects one installation pool. Unset ENV selects project/user pools and defaults. Marketplace billing/license validation remains a separate integration; an absent ENV must retain the requested scoped fallback.

## Boundaries & Constraints

**Always:** One slot per agent/auth/workflow-step session; common limiter for every launch path; short DB transactions; stable workflow and runtime identities; reservations survive crashes and uncertainty; queue-aware cancellation and UI; durable recovery. Keep tools without sessions outside this limit. Use existing app conventions. Conservative rollout: existing workflows still supported, new executions gated, explicit policy sync/quota cleanup tasks.

**Ask First:** Live infrastructure deployments, stopping users' sessions, commercial Marketplace integration.

**Never:** Automatic slot expiry for a possibly live resource; counting only ready rows; workers independently resetting the policy; remote push/deploy; claiming ENV is tamper-proof licensing.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Behavior | Error Handling |
|---|---|---|---|
| Global cap | N=2, concurrent requests | Two reservations, others FIFO queued | Atomic across replicas |
| Fallback | ENV unset | Project pool if present, otherwise User | Positive defaults/overrides |
| Bad configuration | 0, negative, fractional | Configuration error | Never unlimited fallback |
| Lost launch response | Temporal accepted start | Recover same ID | No second agent execution |
| Cleanup uncertainty | Failed row, live/unknown Pod | Keep reservation | Reconcile, no TTL release |
| Queued cancel | Before/after reservation | No subsequent launch | Idempotent stop marker |
| Capacity pressure | Quota exhausted / Pending | Wait with reason | Typed non-capacity errors fail |
| Long queue | Workflow child waiting | No stale-run/30m timeout | Execution and queue clocks separated |

</frozen-after-approval>

## Code Map

- `app/services/session_service.rb`, `app/models/terminal_session.rb`, `app/state_machines/terminal_session_state_machine.rb`: all launch/lifecycle entry points.
- `app/temporal/workflows/container_workflow.rb`, `app/temporal/activities/container/phase_activity.rb`: preserve legacy histories, register new gated execution.
- `app/services/container_runtime/{kubernetes_runtime,docker_runtime,base_runtime}.rb`: identity, idempotent creation, capacity classification, cleanup confirmation.
- `app/temporal/workflows/workflow_execution_workflow.rb`, session/workflow scanners: queue-aware parent clocks/cancel.
- `app/resources/terminal_session_resource.rb`, `app/frontend/shared/components/SessionShowContent`, session status/feed/Builder/MCP: waiting and cancel presentation.
- `config/settings.yml`, `lib/tasks`, `app/temporal/{workflows,schedules}.yml`: configuration, reconciliation and rollout.

## Tasks & Acceptance

**Execution:**
- [x] `db/migrate`, `app/models/session_*`, `app/services/session_admission*`: policy, pool, FIFO, reservation and durable launch.
- [x] `app/services/session_service.rb` and lifecycle consumers: enqueue, idempotent StepRun creation, cancellation, release.
- [x] `app/temporal` and runtime strategies/adapters: gated execution, safe cleanup, runtime waiting and reconciliation.
- [x] `app/resources`, API/MCP and `app/frontend`: queued/cancelled display, privacy, cancellation and generated types.
- [x] `config/settings.yml`, `.env.example`, `lib/tasks`, deployment documentation: sync, legacy migration/quota removal and infra settings.
- [x] `test` and frontend tests: concurrent admission, failure recovery, cancellation, parent waits, UI and existing regression checks.

**Acceptance Criteria:**
- Given concurrent callers sharing cap N, when requests arrive, then at most N unreleased reservations exist and later requests wait FIFO.
- Given an absent ENV, when sessions belong to different scopes, then project/user limits apply via the same admission mechanism.
- Given crashes or ambiguous create/delete responses, when reconciliation runs, then requests recover without duplicate execution or early release.
- Given a waiting session/step, when cancelled or credentials revoked, then no later create is admitted and parent state resolves.
- Given queued work across process restart, when Temporal/DB recover, then automatic dispatch resumes without another user request.
- Given a queued session in API/UI/MCP, when viewed, then waiting is visible without terminal access or leaked private data.

## Spec Change Log

- Implementation authorized by the user. Resolve the previous document's contradictory entitlement-absent wording in favor of the original required scoped fallback. No Marketplace API integration is implied.

## Design Notes

The detailed technical design is the starting contract. Record evidence-driven implementation adjustments in this file and update the design to match. Existing live cluster state is not known: do not run cutover or delete quotas automatically.

The implementation uses one policy UPDATE lock to serialize short admission decisions, with network/runtime work outside those transactions. Runtime phases retain a durable operation envelope; unknown create/start/exec requires operator fencing before resolution. This deliberately sacrifices automatic recovery where the runtime cannot prove absence of a late publisher. See [rollout and recovery](../design/session-admission-queue/ROLLOUT.md). Parent v2 histories poll durable child state, ignore premature container completion signals, and exclude queue time from the old 23-hour/24-hour budget. Legacy producers and workers must be drained before cutover.

Configuration and runbook changes are applied locally in the sibling infra repository. No deployment, live policy sync, runtime cleanup, commit or push was performed. Only the test database was migrated.

## Verification

- Targeted Rails tests in the local web Docker environment, serialized (shared test DB).
- Focused Vitest session tests, TypeScript and relevant ESLint.
- RuboCop for changed Ruby files and whitespace/diff checks.
- Independent adversarial implementation review before handoff.

### Results (2026-09-05)

- Test database migration applied successfully; development/live database was not migrated.
- Admission/service/Temporal/feed regression batch: 97 runs, 269 assertions, passing.
- Runtime, cleanup confirmation, quota conversion, stale scanners and MCP batch: 157 runs, 452 assertions, passing.
- Concurrent PostgreSQL admission batch: 5 runs, 38 assertions, passing, including three competing connections with cap 2.
- Parent v2 25-hour wait and service regressions: 72 runs, 241 assertions, passing.
- Runtime idempotency and relay regression batch: 108 runs, 311 assertions, passing.
- Frontend: 134 tests across 6 affected suites passing. TypeScript passes. Existing React act warnings remain; ESLint reports no errors and one existing onboarding hook warning.
- RuboCop: 40 changed Ruby/rake files, no offenses. Diff whitespace checks pass in both repositories.
- Independent review is **not complete**: both requested reviewer agents failed with a service usage-limit error before returning findings. Fallback prompts: [adversarial](review-session-queue-blind.md), [edge cases](review-session-queue-edges.md). Status remains `in-review`; implementation is not approved for deployment.
