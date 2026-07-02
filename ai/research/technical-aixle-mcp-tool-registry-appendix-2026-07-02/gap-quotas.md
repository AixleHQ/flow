CONFIDENCE: high on Temporal/Sidekiq/SolidQueue documented facts (all verified against primary docs); medium-high on the recommended architecture, which is a synthesis — the queue-vs-reject depth numbers and timeout values are judgment calls to tune to actual workload.

# Per-Tenant Fairness for Docker-Tool Executions on Temporal — Research

## 1. Temporal-native mechanisms

### 1a. Task Queue Priority & Fairness (the headline feature for this problem)
- Temporal now ships **Task Queue Fairness**: tasks get a **fairness key** (e.g. `company_id`) and a **weight** (default 1.0). Each key becomes a virtual queue with round-robin/weighted dispatch, so one company's backlog cannot monopolize worker slots. Weight 2.0 dispatches 2x as often as 1.0. ([docs: task-queue-priority-fairness](https://docs.temporal.io/develop/task-queue-priority-fairness))
- **Per-fairness-key rate limits** (dispatches/sec per key, scaled by weight) can coexist with a whole-queue rate limit; the stricter applies. This gives per-company throughput caps without per-company infrastructure.
- Availability: **Temporal Cloud — paid feature, enable in UI; self-hosted — dynamic config `matching.enableFairness: true`**. Priority is enabled by default everywhere.
- Caveats: fairness is *dispatch ordering + rate*, **not a hard concurrent-execution cap**; accuracy degrades with very many keys and across imbalanced task-queue partitions; weights apply at schedule time (existing backlog isn't retroactively rebalanced).

### 1b. Official multi-tenant patterns (Temporal's own ranking)
([docs: multi-tenant-patterns](https://docs.temporal.io/production-deployment/multi-tenant-patterns))
1. **Task queue per tenant** (recommended): workers poll multiple tenant queues; strong isolation, but worker config management overhead.
2. **Single task queue + Fairness**: simplest to onboard new tenants; per-key rate limits available. Best fit for "thousands of tenants" tiered SaaS.
3. **Shared workflow queue, per-tenant activity queues**: for heavy activities needing isolation (your docker-run activity qualifies).
4. **Namespace per tenant**: full isolation incl. independent quotas, but "practical for fewer than ~50 high-value tenants" (separate workers/credentials per tenant). Not for general SaaS fairness.

### 1c. Worker slot suppliers / resource-based tuning (global capacity, not per-tenant)
- Concurrency at the worker is governed by **task slots**; legacy `maxConcurrentActivityExecutionSize` is superseded by **Worker Tuners with slot suppliers**: `FixedSizeSlotSupplier`, `ResourceBasedSlotSupplier` (targets CPU/mem %), or fully **custom slot suppliers** (you could write one that consults tenant counters, but it's per-worker-process, so a cluster-wide per-tenant cap via custom slots is awkward). ([docs: worker-performance](https://docs.temporal.io/develop/worker-performance), [blog: resource-based auto-tuning](https://temporal.io/blog/resource-based-auto-tuning-for-workers))
- Rate limits: `maxTaskQueueActivitiesPerSecond` is **server-enforced across all workers on the queue**; `maxWorkerActivitiesPerSecond` is per-process. Both are global, not tenant-keyed.

### 1d. Per-namespace quotas
- Self-hosted dynamic config exposes `frontend.namespaceRPS` (per frontend instance) and `frontend.globalNamespaceRPS` (cluster-wide per-namespace RPC limit); these throttle **API calls, not container concurrency** — useful as a blast-radius guard, not as tenant fairness (unless namespace-per-tenant). ([dynamic config reference](https://docs.temporal.io/references/dynamic-configuration), [forum: rate limiting by namespace](https://community.temporal.io/t/rate-limiting-by-namespace/1335), [Cloud limits](https://docs.temporal.io/cloud/limits))

### 1e. Workflow-level semaphore / mutex patterns
- **No built-in per-workflow-type or per-tenant concurrency limit exists**; feature request [temporalio/temporal#7666](https://github.com/temporalio/temporal/issues/7666) is open (enhancement, no committed plan) — it explicitly calls dispatcher-workflow/external-semaphore workarounds "complex, fragile, operationally heavy."
- Canonical patterns:
  - **Mutex/semaphore workflow**: a long-lived per-resource (here: per-company) workflow holding lock state; requesters `SignalWithStart` it and block until granted. Samples: [samples-go/mutex](https://github.com/temporalio/samples-go/tree/main/mutex), [samples-typescript/mutex](https://github.com/temporalio/samples-typescript/tree/main/mutex).
  - **Sliding-window batch parent** ([samples-python `batch_sliding_window`](https://github.com/temporalio/samples-python)) — a parent workflow that keeps at most N children running; recommended in [forum thread on limiting concurrent workflow instances](https://community.temporal.io/t/how-to-limit-concurrent-workflow-instances-workflow-level-semaphore/19144), along with signal-queueing via `SignalWithStart`.
  - Caveats of semaphore workflows: event-history growth forces Continue-As-New, single semaphore workflow becomes a throughput bottleneck and single point of contention per tenant; fine at "≤ tens of acquisitions/sec/tenant" scale, which tool executions likely satisfy.

## 2. Rails-land fairness patterns (prior art worth copying)

- **Sidekiq Enterprise limiters** ([wiki: Ent Rate Limiting](https://github.com/sidekiq/sidekiq/wiki/Ent-Rate-Limiting)): `Sidekiq::Limiter.concurrent("tool-exec-#{company_id}", N, wait_timeout:, lock_timeout:)` — Redis-backed, shared across all processes; **dynamic per-tenant limiter names** are the standard per-tenant recipe (real-world example: ERP SaaS capping each customer at 50 concurrent ops). Over-limit raises `Sidekiq::Limiter::OverLimit`, and middleware **reschedules the job with linear backoff (~5 min/attempt, ~20 attempts ≈ 1 day) before treating it as failed** — i.e. "queue by retry," not reject. Known weakness: blocked threads still occupy workers, so one saturated tenant can starve thread capacity.
- **SolidQueue** ([README](https://github.com/rails/solid_queue)): `limits_concurrency to: N, key: ->(args) { company }, duration:` — semaphore rows in the DB; over-limit jobs are parked as *blocked* and released FIFO when a slot frees (queue, not reject). Caveat: blocked-job release doesn't respect queue priority ([issue #237](https://github.com/rails/solid_queue/issues/237)); one key per job ([issue #182](https://github.com/rails/solid_queue/issues/182)).
- **GoodJob** ([README](https://github.com/bensheldon/good_job)): concurrency controls with `key` (string/proc from job args) enforcing limits **at enqueue time and/or perform time** — enqueue-time limits give you "reject at submission," perform-time gives "queue."
- Design inspiration outside Rails: [Inngest's fair multi-tenant queue](https://www.inngest.com/blog/building-the-inngest-queue-pt-i-fairness-multi-tenancy) (per-tenant virtual queues + weighted-random worker peeking) and [AWS Builders' Library: Fairness in multi-tenant systems](https://aws.amazon.com/builders-library/fairness-in-multi-tenant-systems/) (throttle-per-tenant + admission control as the core primitives).

## 3. Recommended shape

**Enforce in three layers (they solve different failure modes):**

1. **Per-company concurrency cap → dispatch-time DB counter in Rails (primary).** Before `start_workflow`, atomically claim a slot in Postgres (e.g. `UPDATE company_execution_quotas SET running = running + 1 WHERE company_id = ? AND running < cap` returning rows-affected, or count `tool_executions WHERE status='running'` under an advisory lock; release in a workflow-completion callback/activity with a reconciler for crashes). Rationale: the cap is business policy; Rails/Postgres is where you already have the tenant model, it's inspectable, and it matches the proven SolidQueue/Sidekiq-Ent semaphore approach. A per-company **semaphore workflow** (mutex sample) is the Temporal-idiomatic alternative and is crash-consistent for free, but adds a long-lived workflow per company, Continue-As-New management, and harder observability — only worth it if you can't tolerate the DB counter's reconciliation edge cases (#7666 confirms there's no built-in).
2. **Task Queue Fairness with `fairness key = company_id` (backstop).** Even with a dispatch-time cap, backlogs form when global worker capacity is the bottleneck; fairness keys stop a big tenant's queued tasks from starving others, and per-key rate limits cap runaway schedulers. Requires `matching.enableFairness` (self-hosted) or the paid Cloud feature.
3. **Worker tuner (fixed or resource-based slot supplier) as the global cap** sized to what the container host(s) can actually run — protects infrastructure regardless of tenant math.

**At the cap — bounded queue with position feedback, then reject:**
- Accept-and-queue up to a small per-company depth (e.g. cap 5 running + 10 queued): create the `ToolExecution` row in `queued` state and report position (`COUNT(*) queued before me for this company`) — SolidQueue-style semantics. Queued items dispatch on slot release.
- Beyond the bound, **reject with HTTP 429 + `Retry-After`** (Sidekiq-Ent's "retry later with backoff" semantics, surfaced to the caller instead of hidden). For **agent-facing synchronous calls specifically, prefer fast rejection over deep queueing** — an LLM agent blocking on a tool call degrades badly with unbounded latency; a structured "at capacity, retry in ~Ns, position X" error lets the agent re-plan.

**Timeouts** ([workflow timeouts](https://docs.temporal.io/encyclopedia/detecting-workflow-failures), [activity timeouts](https://docs.temporal.io/encyclopedia/detecting-activity-failures)):
- The docker-run **activity**: `StartToCloseTimeout` is effectively required (server can't detect crashed workers without it) — set it to the max tool runtime (e.g. 5–10 min for agent tools) **plus heartbeats** (short `HeartbeatTimeout`, heartbeat from the container-polling loop) so a dead runner is detected in seconds, not at timeout expiry. Enforce a matching hard timeout in the container runner itself (kill the container) so the activity timeout is the backstop, not the mechanism.
- The **workflow**: set `WorkflowExecutionTimeout` as an overall guardrail (tool runtime + queue allowance, e.g. 15–30 min). Temporal advises against workflow timeouts for long-running business workflows, but a one-shot tool execution is exactly the bounded case where it's appropriate. Leave `WorkflowTaskTimeout` at default (10s).
- Prefer *shorter* interactive-tool timeouts (agents give up long before 10 min); consider a per-tool configurable timeout column with a platform max.

## Sources
- https://docs.temporal.io/develop/task-queue-priority-fairness
- https://docs.temporal.io/production-deployment/multi-tenant-patterns
- https://docs.temporal.io/develop/worker-performance
- https://temporal.io/blog/resource-based-auto-tuning-for-workers
- https://docs.temporal.io/references/dynamic-configuration
- https://docs.temporal.io/cloud/limits
- https://community.temporal.io/t/rate-limiting-by-namespace/1335
- https://github.com/temporalio/temporal/issues/7666
- https://community.temporal.io/t/how-to-limit-concurrent-workflow-instances-workflow-level-semaphore/19144
- https://github.com/temporalio/samples-go/tree/main/mutex
- https://github.com/temporalio/samples-typescript/tree/main/mutex
- https://github.com/sidekiq/sidekiq/wiki/Ent-Rate-Limiting
- https://github.com/rails/solid_queue
- https://github.com/rails/solid_queue/issues/237
- https://github.com/rails/solid_queue/issues/182
- https://github.com/bensheldon/good_job
- https://www.inngest.com/blog/building-the-inngest-queue-pt-i-fairness-multi-tenancy
- https://aws.amazon.com/builders-library/fairness-in-multi-tenant-systems/
- https://docs.temporal.io/encyclopedia/detecting-workflow-failures
- https://docs.temporal.io/encyclopedia/detecting-activity-failures