---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Event-driven workflow trigger system'
research_goals: 'Design a unified event-driven trigger system for launching workflows/tasks (timer/schedule, Slack message, arbitrary webhook, plus the existing column-move and wait-resolution triggers). Evaluate competitors (Kestra, Cursor automations, and adjacent orchestration/automation tools). Decide whether to adopt an external engine or build a native trigger layer on top of the existing Temporal-based workflow engine.'
user_name: 'Artem_Petrov'
date: '2026-06-22'
web_research_enabled: true
source_verification: true
---

# From Three Hard-Coded Hooks to One Event Bus: A Technical Research Report on a Unified Event-Driven Trigger Layer

**Date:** 2026-06-22
**Author:** Artem_Petrov
**Research Type:** technical
**Source verification:** Every load-bearing competitor claim was independently re-checked by an adversarial fact-checker against primary/official sources (net confidence: high across all 10 tools).

---

## Research Overview

This report answers a single architectural question for the app: **how to launch workflows from heterogeneous events — a timer/schedule, a Slack message, an arbitrary inbound webhook — in addition to today's column-move and GitHub/GitLab wait-resolution triggers, without hard-coding a new controller + job + dispatch branch for every new source.** The current system funnels all three existing trigger paths through one method, `TaskService.check_auto_trigger → WorkflowService.start → Temporal`, but the routing logic is hard-coded per source, there is no normalized "event," no generic webhook gateway, no user-facing scheduler, and no Slack integration.

The headline finding is **BUILD, not buy**: a native, in-app event-driven trigger layer on Postgres plus the **Temporal engine you already run**, not an external orchestration/automation engine. Every full engine evaluated (Kestra, Inngest, Trigger.dev, n8n, Windmill, Hatchet) bundles a workflow *execution* plane that duplicates and competes with Temporal; none is an embeddable Ruby library; several carry license friction (n8n SUL, Inngest SSPL, Windmill AGPLv3+EE gating exactly the bus triggers you'd want); and the repo's open-source/self-host trajectory makes hard SaaS dependencies (Cursor, Zapier/Make, managed EventBridge/Svix/Inngest) a poor fit. Temporal natively closes two of the three gaps — **Schedules** (cron/interval/calendar, timezone, overlap policy, catchup, jitter, pause/backfill) for the scheduler, and **Signal-with-Start** for launch-or-resume on any event. The genuine gap to build is the *event-normalization + matching/binding + generic-ingestion* layer that none of these tools will hand you embeddable in Ruby.

The full executive summary, a verified competitor comparison, the proposed data model and dispatch path mapped onto the existing code, and a phased implementation roadmap with the security/multi-tenancy/observability/migration topics the completeness critic flagged, follow in the **Research Synthesis** section below.

---

## Technical Research Scope Confirmation

**Research Topic:** Event-driven workflow trigger system
**Research Goals:** Design a unified event-driven trigger system (timer/schedule, Slack message, arbitrary webhook, plus existing column-move and wait-resolution triggers); evaluate competitors; decide adopt-vs-build relative to the existing Temporal engine.

**Technical Research Scope:**

- Trigger taxonomy and event modeling (sources → matching/routing → action; the normalized event envelope; CloudEvents)
- Competitor analysis — trigger/event model of Kestra, Cursor Automations, Temporal, Inngest, Trigger.dev, n8n, Windmill, Hatchet, GitHub Actions, Zapier/Make
- Integration patterns — generic inbound webhook gateway, Slack as an event source, signature verification, idempotency/dedup
- Architectural patterns — transactional outbox, in-process event bus, generalized Trigger/Subscription model, layering on Temporal (signal-with-start, signals)
- Build vs Buy vs Hybrid decision, with a concrete design mapped onto the existing codebase
- Implementation roadmap, security, multi-tenancy, observability, migration, testing

**Research Methodology:** Current web data with rigorous source verification; an adversarial fact-checker re-checked each tool's load-bearing claims against official docs; confidence levels applied; grounded in a thorough read of the existing codebase.

**Scope Confirmed:** 2026-06-22

---

## Table of Contents

1. Technical Research Introduction and Methodology
2. The Current System (Baseline)
3. Trigger Taxonomy and Event Modeling
4. Competitor Landscape — Trigger/Event Models (verified)
5. Integration Patterns: Generic Webhook Gateway + Slack
6. Schedule / Timer Triggers (Temporal Schedules)
7. Architectural Patterns for the Trigger Layer
8. Strategic Decision: Build vs Buy vs Hybrid
9. Proposed Design for This System
10. Implementation Roadmap and Risk Assessment
11. Cross-Cutting Concerns (Security, Multi-Tenancy, Observability, Testing, Migration)
12. Open Questions
13. Research Methodology and Source Verification

---

## 1. Technical Research Introduction and Methodology

Triggering is the quiet half of every workflow system. The engine that *runs* a workflow gets the attention, but what decides *when* a workflow runs determines how much of the product can be automated. This system has a capable execution engine (Temporal) and a deliberately narrow trigger surface: a task entering a bound column, a GitHub/GitLab check/pipeline resolving a wait, and a manual button. Each was built as a vertical slice — its own controller or hook, its own job, its own branch inside `TaskService.check_auto_trigger`. That design is correct for three sources and actively hostile to the fourth, fifth, and sixth. Adding "run on a schedule," "run when a Slack message arrives," or "run on any webhook" under the current pattern means another bespoke controller + job + dispatch branch each time.

The research goal is therefore not "add a Slack trigger" but "introduce a **trigger layer** so that adding a source is adding a *producer of normalized events*, never editing the routing logic." This report establishes the vocabulary and patterns for that layer, benchmarks ten relevant products on exactly one axis — *how they get triggered* — and converts the findings into a concrete build plan grounded in the existing models (`column_workflow_bindings`, `task_waits`, `Integration`, `WorkflowService.start`, `TemporalService`).

**Methodology.** A multi-agent research pass ran four conceptual investigations (taxonomy, webhook/Slack, scheduling, architecture) in parallel, then ten per-competitor deep dives, each followed by an **adversarial verification agent** that independently searched primary sources to refute the researcher's claims. All ten tools returned net confidence *high*; the specific corrections that verification produced are folded into Section 4 and flagged inline (e.g. Inngest's "3-year" license window is unverified; GitHub Actions' IANA-timezone cron is new as of March 2026; Cursor Automations *launched* rather than "GA'd" on 2026-03-05). A completeness critic then audited coverage and surfaced the gaps now addressed in Sections 8 and 11 (notably: the existing Redis cooldown is *throttling, not deduplication*, and any "buy" recommendation must reconcile with the repo's open-source/self-host direction).

---

## 2. The Current System (Baseline)

All three of today's trigger paths converge on `TaskService.check_auto_trigger` (`app/services/task_service.rb:139`) → `WorkflowService.start` → `TemporalWorkflowRegistry.start_workflow_execution`, but the *routing* is hard-coded per source.

| Trigger source today | Mechanism | Convergence |
|---|---|---|
| **Task moved into a bound column** | `column_workflow_bindings` (`trigger_mode: auto\|manual`, `cooldown_seconds`); `TaskService.move` records a `ColumnTransition`, then calls `check_auto_trigger` | `check_auto_trigger` inlines the rule (auto binding, no pending waits, no quota block) |
| **GitHub/GitLab wait resolves** | `task_waits` (`wait_type` enum: `github_checks_completed` / `github_workflow_completed` / `gitlab_pipeline_completed`); bespoke `Webhooks::GithubController` (HMAC `X-Hub-Signature-256`) & `Webhooks::GitlabController` (per-repo `X-Gitlab-Token`) → `ResolveGithub*/Gitlab*Job` → `WaitService` → `TaskService.resolve_wait` | `resolve_wait` updates the wait, then calls `check_auto_trigger` |
| **Manual button** | `POST .../tasks/:id/trigger_workflow` → `TaskService.trigger_workflow` | calls `WorkflowService.start` directly |

**Structural facts that shape the design:**

- **Temporal is already the engine.** `TemporalService` (`app/services/temporal_service.rb`) connects via the Ruby SDK, and `sync_schedules` already calls `Temporalio::Client.create_schedule` from a *static* `app/temporal/schedules.yml` (three internal cleanup workflows, cron, `OverlapPolicy::BUFFER_ONE`). The scheduling primitive is in place but is config-file-only, not multi-tenant, destructively reconciled (delete-all-then-recreate), and disconnected from the user-facing workflow path.
- **Webhook ingestion is provider-specific.** Two bespoke controllers share the same *shape* (verify → `head :ok` → `perform_later` → `WaitService` → `resolve_wait`) but zero shared infrastructure.
- **There is no generic event/pub-sub layer.** `BoardActivity` is an append-only activity log written ad-hoc in `rescue` blocks, not a routable event store. The "event" exists only as a Ruby stack frame.
- **`task_waits` already hand-rolls content-based routing** via JSONB scopes (`metadata->>'pr_number'`, `for_github_workflow_run_id`, …) and `column_workflow_bindings` is already a "binding" — the single concrete instance of source→workflow mapping.
- **No Slack.** `Integration.provider` enum is `github | gitlab | linear | coder`.
- **The existing cooldown is throttling, not dedup.** A ~5-second per-`(task, column)` Redis cooldown (`CooldownService`) prevents rapid re-fires; it does **not** deduplicate at-least-once webhook retries and must not be relied on for idempotency.

The single-action property is a gift: the only action the layer ever takes is "start a workflow." That keeps this far simpler than a general-purpose event bus — you are building a *fan-in router to one action*, not a pub/sub platform.

---

## 3. Trigger Taxonomy and Event Modeling

### The pipeline: trigger → matching/routing → action

A unified trigger layer is three stages. A **trigger** *produces* an occurrence (a schedule fires, a webhook lands, a card moves, a prior run finishes). A **matching/routing** stage decides *which* workflows care. An **action** stage *launches* the run. Today the system collapses all three into bespoke call chains; the unified layer extracts the middle stage into an explicit, data-driven dispatcher.

### Vocabulary (pin these down before building)

- **Event** — an immutable record that *something happened* (past tense, no addressee: `task.moved`, `schedule.fired`). Data, not a command.
- **Trigger** — the *source/producer* that emits events.
- **Subscription** — a consumer-side filter predicate ("I care about events matching X"), decoupled from any event instance.
- **Binding** — the concrete link: "events matching X start workflow Y with input mapping Z." `column_workflow_bindings` is exactly this for one source.
- **Action** — the side effect: `WorkflowService.start`. The only action you have.

### Categories of event sources (covering the goal)

1. **Schedule/timer** — time is the cause. Temporal [Schedules](https://docs.temporal.io/schedule) provide this natively.
2. **Inbound webhook** — external HTTP push (today: bespoke GitHub/GitLab).
3. **Message/queue** — Slack Events API (HTTP or Socket Mode), or an internal queue.
4. **Polling/pull** — periodically ask "what changed?" (e.g. Linear without webhooks); implemented as a schedule whose action emits synthetic events.
5. **Internal domain event** — column-move; `check_auto_trigger` is this category.
6. **Manual** — `TaskService.trigger_workflow`.
7. **Completion-of-prior-run** — a finished `workflow_run` or resolved `task_wait` emits an event that chains the next workflow.

### The normalized event envelope (the core idea)

The whole value of a fan-in layer is that heterogeneous sources collapse into *one* internal shape the matcher and action stage understand — without it, every source needs its own routing code (exactly today's GitHub-vs-GitLab duplication). The canonical reliable-ingestion pattern is consistent across the industry: verify the signature at the edge, dedupe on a stable event id, persist the raw event durably, return 2xx fast, then process asynchronously ([Hookdeck webhook infrastructure guide](https://hookdeck.com/webhooks/guides/webhook-infrastructure-guide)). The persisted normalized record *is* your envelope, and it doubles as an audit log and a replay source.

### CloudEvents — adopt the attribute model, skip the ceremony

[CloudEvents v1.0.2](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md) (CNCF) standardizes a vendor-neutral envelope. REQUIRED: `id`, `source`, `specversion`, `type`. OPTIONAL: `subject` (the specific entity within the source — designed so middleware can filter *without* parsing `data`), `time`, `datacontenttype`, `dataschema`, `data`, plus extension attributes. Critically, producers MUST keep **`source` + `id` unique per event**, and consumers MAY treat identical `source`+`id` as duplicates — i.e. **a built-in dedupe key**. An official [Ruby SDK](https://github.com/cloudevents/sdk-ruby) exists (v0.9.0, March 2026, zero runtime deps).

**Recommendation:** adopt the CloudEvents *attribute model* as your envelope schema; don't over-invest in the SDK or wire format. For a single app the win isn't on-the-wire interoperability — it's a battle-tested field taxonomy and dedupe semantics for free. Map your sources: `type` = `board.task.moved` / `vcs.checks.completed` / `schedule.fired` / `slack.message.posted`; `source` = the integration/board URI; `subject` = the task or PR id; `data` = raw payload.

### Matching/routing strategies (cheapest-first)

- **Type-based (topic):** match on `type` alone — your current column-binding model, lifted to event types. Covers most cases.
- **Attribute filters:** `type` AND `subject` prefix AND `source` — filter on metadata without parsing the body (why CloudEvents promotes `subject`).
- **Content-based:** predicates over `data` (`data.conclusion == "success"`). Most expressive, most expensive. Your `TaskWait` JSONB scopes are already a hand-rolled content router.

A subscription is `{type, attribute_filters, content_predicate}`, evaluated cheapest-first, stored as data so the dispatcher is one generic query replacing every bespoke `resolve_*` method.

---

## 4. Competitor Landscape — Trigger/Event Models (verified)

All ten were analyzed on **how they trigger**, then adversarially fact-checked (net confidence **high** for all). The single most important pattern: **the tools closest to your goal (Hatchet, Inngest) treat the event as first-class and decouple producers from consumers; the workflow engines (Kestra, Windmill, Trigger.dev, n8n) bind a trigger directly to one workflow; and all of them except Temporal would have you run a second execution engine.**

### Comparison matrix

| Tool | What it is | Event = first-class? | Generic webhook gateway | Schedule capability | Custom/Slack events | Deploy / License | Verdict |
|---|---|---|---|---|---|---|---|
| **Temporal** | Durable-execution engine (incumbent) | No — routes by explicit Workflow ID | No (you build the receiver) | **Native & strong**: cron/interval/calendar, TZ, 6 overlap policies, catchup, jitter, pause/backfill | Only as raw Signals/Updates against a known Workflow ID | Self-host, **MIT**, Go server + Ruby SDK | **ADOPT** for schedule + signal-with-start; build the rest |
| **Hatchet** | Postgres-backed orchestrator w/ first-class events | **Yes** — named events + CEL filters + scope | **Yes** — built-in, URL-per-webhook, presets (Stripe/GitHub/**Slack**) or generic HMAC/API-key/Basic | cron 5/6-field, UTC-only, **no backfill** | Strong: `event.push` + webhook gateway + wildcards + CEL | Self-host, **MIT**, Go + (Py/TS/Go/**Ruby** SDKs) | **LEARN** — closest design; but it's a competing engine |
| **Inngest** | Event-driven durable functions | **Yes** — name→many-functions fan-out | **Yes** — per-source URL + server-side JS transform | unix-cron + TZ prefix + jitter; dedupe per second; **no backfill** | Strong: named JSON event (`name`+`data`+`id` 24h dedup), CEL `if`, wildcards | Self-host **SSPL→Apache** (delay unverified); Go; no Ruby SDK | **LEARN** — best envelope model |
| **Kestra** | Declarative YAML orchestrator | No — triggers are per-flow declarative objects | Yes but URL-per-trigger, **key-only auth, no HMAC/dedup** | Strong: cron+`L`+shortcuts, TZ, no-overlap, `recoverMissedSchedules` ALL/LAST/NONE, Backfill | Plugin model (webhook or realtime bus triggers); no native Slack | Self-host **Apache-2.0** core (multi-tenancy/RBAC = Enterprise); JVM | **LEARN** — best declarative trigger schema |
| **Windmill** | "Simplified Temporal" (Postgres + Rust) | No, but **normalized `event.kind` envelope + preprocessor adapter** | Autogenerated webhooks (Bearer) + **custom HTTP routes w/ pluggable auth incl. HMAC Stripe/GitHub** | croner 6-field + `L/#/W`; TZ/catchup/jitter/overlap under-documented | Kafka/NATS/SQS/MQTT/PubSub/CDC (**EE-gated**); Slack = HTTP route + signature | Self-host **AGPLv3 + proprietary EE**; Rust | **LEARN** — best envelope/preprocessor seam |
| **Trigger.dev** | TS durable-jobs platform (v3/v4) | **No** — TASK is first-class; v3 removed v2's events | **No native** webhook trigger (open issue [#3353](https://github.com/triggerdotdev/trigger.dev/issues/3353)) | Strong: declarative + **imperative `schedules.create` w/ `externalId`+`deduplicationKey`**, IANA TZ, no seconds; no documented catchup/overlap/jitter | None native; you call `tasks.trigger()` from your own handler | Self-host **Apache-2.0**; Node containers | **LEARN** — per-tenant schedule API + idempotencyKey |
| **n8n** | Low-code node-graph automation | No — trigger is the first *node* | **Yes** — generic Webhook node, UUID path, test/prod URLs, None/Basic/Header/JWT auth, 16MB | interval+cron, multiple rules, TZ; **no backfill** (skips missed) | Webhook escape hatch + 400+ app triggers incl. **Slack Trigger** (Events API, named events) | Self-host **Sustainable Use License** (not OSI; reselling restricted); Node | **LEARN** — Slack trigger UX + webhook design |
| **GitHub Actions** | CI/CD w/ declarative `on:` | No — implicit fan-out by matching `on:` | No generic URL; **`repository_dispatch`** = one API endpoint keyed by `event_type` + free-form `client_payload` | `on: schedule` POSIX cron, min 5 min, default branch; **IANA TZ new ~Mar 2026** | `repository_dispatch` for arbitrary events; no native Slack/queue | Closed SaaS / GHES; not embeddable | **LEARN** — `on:` filters, dispatch, `workflow_run` chaining (3-level cap) |
| **Cursor Automations** | Closed AI-agent automation (launched 2026-03-05) | No — typed connectors attached to an Automation | **Yes** — private URL + minted API key on save (bearer, no HMAC) | preset/cron; "may run with delay"; no TZ/catchup/overlap/jitter surfaced | **Slack/Linear/Sentry/PagerDuty/GitHub** typed triggers + webhook; "run when ANY trigger fires" | **Closed proprietary cloud SaaS**; not embeddable | **LEARN** — "Automation owns N triggers" + Slack keyword filters |
| **Zapier / Make** | No-code iPaaS | No — one trigger per flow, no shared bus | **Yes** — Catch Hook / Custom webhook, URL-per-trigger, payload→variable mapping | user-facing intervals (1–15 min by plan); no raw cron/catchup | Connector-native (Slack instant triggers) or generic catch-hook; REST Hook subscribe/unsubscribe | **Cloud-only, closed**; no self-host/Ruby | **LEARN** — instant-vs-poll taxonomy, subscribe lifecycle, dropdown binding UX |

### Per-tool notes that matter for the design

- **Temporal (ADOPT for two of three gaps).** A Schedule is a first-class object independent of any execution, with six overlap policies (Skip default, BufferOne, BufferAll, CancelOther, TerminateOther, AllowAll), a catchup window (default one year, min 10s), jitter, and pause/backfill ([docs](https://docs.temporal.io/schedule)); the Ruby SDK exposes `create_schedule`/`list_schedules`/handle `trigger`/`pause`/`backfill`/`update`/`delete`. **Signal-with-Start** signals a running workflow by ID or starts a new one and delivers the signal ([message passing](https://docs.temporal.io/develop/ruby/message-passing)) — the right primitive for launch-or-resume. What Temporal does **not** provide: a generic inbound-webhook gateway, a normalized event envelope, or an event→workflow *matching* layer (it always routes by explicit Workflow ID). Nexus is cross-namespace service RPC, **not** a webhook/event bus.
- **Hatchet (closest to the goal).** `on_events` (wildcards since v0.65.0) + Filters (CEL + scope + payload), a built-in URL-per-webhook gateway with **Slack/Stripe/GitHub presets or generic HMAC/API-key/Basic**, an **Event Key Expression** (CEL over payload+headers) to map arbitrary payloads to event keys, and a clean split between `on_events` (start a run) and `ctx.wait_for` (resume a run — the generic form of your `task_wait`). Caveat: events arriving before a subscriber exists do **not** replay; filter behaviour is scope-gated.
- **Inngest (best envelope).** Event = `{name, data, id (24h dedup), ts (future-schedules), user, v}`; one event fans out to every matching function (name + wildcard + CEL `if`); producers never name consumers. Per-source webhook URL + server-side `Transform(evt, headers, queryParams, raw)`; provider id → event `id` for dedup. Flow control (debounce 1s–7d, throttle, rateLimit, batch ≤100) is a generalization of `cooldown_seconds`. *Verification note:* SSPL→Apache conversion is real but the specific "3-year" window is unverified.
- **Windmill (best adapter seam).** A per-runnable **preprocessor** receives a normalized `event` with a `kind` discriminator (`http`/`webhook`/`kafka`/…) and returns `main()`'s args — decoupling source format from workflow input. Custom HTTP routes carry pluggable auth incl. HMAC (Stripe/GitHub formats). *Verification note:* the `webhook` kind carries `query`/`headers` rather than `trigger_path`; bus triggers are EE-gated.
- **Kestra (best declarative schema).** Triggers are first-class declarative objects co-located with the flow (`id` + `type` + conditions + inputs), exposed as `{{ trigger.* }}` variables. `recoverMissedSchedules` ALL/LAST/NONE + explicit Backfill is a clean catchup model. Webhook auth is just a secret key (no HMAC/dedup) + instance-wide Basic Auth since 0.24. *Verification note:* encryption of SECRET inputs is available in OSS; multi-tenancy/RBAC/audit are Enterprise.
- **Trigger.dev (per-tenant schedules).** `schedules.create({ task, cron, timezone, externalId, deduplicationKey })` cleanly models per-tenant cron without redeploys, and `idempotencyKey` (default 30-day TTL) dedupes triggers — both worth copying onto a Temporal-Schedule wrapper. But there is **no** native webhook trigger and **no** event bus (v3 deliberately removed v2's events).
- **GitHub Actions (best declarative binding reference).** One `on:` key lists heterogeneous triggers with attribute filters (`types`, `branches`/`paths` and their `-ignore` variants); **`repository_dispatch`** (POST `/dispatches`, `event_type` ≤100 chars + `client_payload` ≤10 props/<64KB) is the precise pattern for "arbitrary external event via one generic endpoint keyed by a type string"; `workflow_dispatch` models typed manual inputs; `workflow_run` models completion-chaining with a **3-level cap** to prevent loops. *Verification note:* IANA-timezone cron shipped ~late March 2026; historically UTC-only.
- **Cursor Automations (validates the unified model).** "An Automation owns N triggers and runs when ANY fires"; generic webhook = private URL + API key minted on save; Slack message/emoji/channel triggers with optional keyword/regex filter. Entirely closed cloud SaaS — adoption is impossible; the *model* is the takeaway.
- **Zapier/Make (UX + taxonomy reference).** The **instant(push/webhook) vs polling(pull/interval)** two-mode taxonomy maps cleanly onto normalizing schedule+Slack+webhook+column-move+wait-resolution; the generic Catch Hook (URL-per-trigger + payload→variable mapping) and the REST Hook subscribe/unsubscribe lifecycle are good binding-activation patterns. Both are strictly one-trigger-per-flow with no shared bus — the part iPaaS does *not* give you.

### Adjacent "buy" candidates the original set missed (critic-flagged)

These are the genuine *buy* options for the **gateway** specifically — distinct from the workflow engines above:

- **AWS EventBridge** — the canonical managed event-bus (rules with content-pattern matching, EventBridge Scheduler, Pipes); the closest architectural mirror of "normalize → match → fan out." *But* it is managed AWS SaaS, conflicting with self-host. (General knowledge; not independently deep-verified in this pass — treat as medium confidence.)
- **Svix / Hookdeck** — webhook-infrastructure-as-a-product: HMAC signing, `svix-id` idempotency keys, retry/backoff, replay, delivery logs ([Svix security](https://docs.svix.com/security), [Hookdeck vs Svix Ingest](https://hookdeck.com/webhooks/platforms/hookdeck-event-gateway-vs-svix-ingest-webhook-receiving-comparison)). The real buy candidate for the gateway — and **Svix is self-hostable**, so it's the one external option compatible with the open-source trajectory if you'd rather not build ingestion. Note Svix Ingest does **not** dedupe — that stays your responsibility.
- **CloudEvents** — not a tool, the envelope standard (Section 3). Adopt the attribute model.
- **Linear webhooks** — already an `Integration.provider`; its `Linear-Signature` HMAC-SHA256 + issue/comment/state-change taxonomy is a concrete near-term source to design the gateway against.

---

## 5. Integration Patterns: Generic Webhook Gateway + Slack

### Generic gateway vs bespoke per-provider controllers

Replace the two bespoke controllers with **one ingress endpoint** (`POST /webhooks/in/:source_slug`) that routes by a path token to a registered `WebhookSource` carrying everything provider-specific as *data*: verification strategy, secret(s), and a payload-mapping spec. This is the model managed services converged on (Hookdeck, Svix Ingest expose a stable URL per *source* and treat provider quirks as configuration). A new source becomes a row + a small verifier strategy, not a new controller/route/job triple. Keep the existing GitHub/GitLab controllers as registered sources (or legacy adapters) during migration.

### Signature verification (per-source strategy, on the raw body)

Verification runs on the **raw request body** before parsing (signatures are byte-sensitive). The codebase already does this correctly for GitHub (`OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)` + `ActiveSupport::SecurityUtils.secure_compare`). Generalize into strategies:

- **HMAC-hex header** — GitHub `X-Hub-Signature-256` (`sha256=<hex>`) ([GitHub best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)).
- **Signed `timestamp.body`** — Stripe `Stripe-Signature: t=…,v1=…` over `"{t}.{raw_body}"`, 5-min tolerance, 24h secret-rollover overlap ([Stripe](https://docs.stripe.com/webhooks)).
- **Slack v0** — `X-Slack-Signature: v0=<hmac>` over `"v0:{ts}:{raw_body}"`, **reject timestamps older than 5 min** ([Slack verification](https://docs.slack.dev/authentication/verifying-requests-from-slack/)).
- **Shared-secret token** — GitLab `X-Gitlab-Token` (today's plaintext `secure_compare`).
- **Linear-Signature** — HMAC-SHA256 ([Linear webhooks](https://linear.app/developers/webhooks)).

Secrets live encrypted per source (the `Integration#credentials_data` `encrypt_and_sign` precedent). Support secret rotation with multiple valid secrets during a grace window. **Generalizing "webhook signature verification" as one mechanism is a trap** — GitHub/GitLab/Linear/Slack each differ materially; model it as a per-source strategy, not a single code path.

### Idempotency, dedup, replay (the part the current cooldown does NOT cover)

Providers guarantee **at-least-once**, never exactly-once. Every well-designed source emits a retry-stable delivery ID: GitHub `X-GitHub-Delivery`, Stripe event `id`, Svix `webhook-id`, Slack `event_id`. Persist a `received_webhooks` row with a **unique index on `(source_id, idempotency_key)`**; on conflict, return 2xx and do nothing ([webhook idempotency](https://www.hooklistener.com/learn/webhook-idempotency-and-deduplication)). Where no key exists, derive one from `hash(source, raw_body)` or a content key. **This is not the existing 5-second Redis cooldown** — that is per-`(task, column)` throttling and will not stop a redelivered webhook from double-launching a workflow.

### Fast-ack-then-process

Persist raw payload, return **2xx immediately**, enqueue the real work — exactly what the controllers do today (`head :ok` then `*Job.perform_later`). Budgets: Stripe expects fast 2xx, GitHub within 10s, **Slack within 3s** (or it retries immediate/+1m/+5m, sending `X-Slack-Retry-Num`; >95% failures in 60 min auto-disables the subscription) ([Slack Events API](https://docs.slack.dev/apis/events-api/)).

### Slack as an event source

Three hard rules. (1) **URL verification handshake** — on configuring the Request URL, Slack POSTs `{type:"url_verification", challenge:"…"}`; echo `challenge` back ([Slack URLs](https://docs.slack.dev/apis/events-api/using-http-request-urls/)). (2) **Signing-secret verification** (above). (3) **3-second 2xx ack** then async. **Slash commands and interactivity** (`block_actions`) are separate request types with their own 3s ack + `response_url`, sharing the signing secret. **Socket Mode** (outbound WebSocket, no public URL) is for dev/firewalled networks and needs a long-running worker; Slack recommends **HTTP for production** ([HTTP vs Socket](https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/)). For a Rails app already terminating HTTPS, route Slack through the generic gateway. Add `slack` to the `Integration.provider` enum.

---

## 6. Schedule / Timer Triggers (Temporal Schedules)

**Recommendation: build user-facing scheduled triggers directly on Temporal Schedules** — the stack already runs Temporal and already calls `create_schedule`. A Schedule is a first-class, durable entity (not a row your own poller scans) giving you, in one place, what the Ruby-ecosystem cron tools (sidekiq-cron / Solid Queue recurring / GoodJob / whenever) cannot match combined:

- **Spec:** `calendars` + `intervals` + `cron_expressions` + `skip` exclusions + `start_at`/`end_at` + `jitter` + `time_zone_name`; fire times are the **union** of specs minus exclusions ([Ruby Spec API](https://ruby.temporal.io/Temporalio/Client/Schedule/Spec.html)). Calendar specs are strictly more expressive than cron (named months/weekdays, ranges, "last").
- **Timezone & DST:** UTC by default; pass an IANA `time_zone_name`. Temporal documents the DST sharp edge (a daily local time can be **skipped** on spring-forward and **run twice** on fall-back) and recommends UTC where double/skip-fire is unacceptable ([Schedule docs](https://docs.temporal.io/schedule)). Always make the started workflow idempotent on `TemporalScheduledStartTime`.
- **Overlap policy:** Skip (default), BufferOne (the codebase's current choice), BufferAll, CancelOther, TerminateOther, AllowAll.
- **Catchup window:** default one year, min 10s; missed actions inside the window are taken on recovery, older ones discarded.
- **Jitter:** random `[0, jitter]` offset — de-correlate "0 * * * *" cleanups across projects so they don't stampede the container pool.
- **Operations:** `trigger`, `pause/unpause`, `backfill`, `update`, `describe`, `delete`; `pause_on_failure` auto-pauses on failure. Durable timers survive deploys/crashes without a polling loop.

**Recommended shape:** add a `ScheduleTrigger` model (`project_id`, `workflow_id`, optional `board_task_id`, `spec_kind` cron/interval/calendar, raw spec, `time_zone`, `overlap_policy`, `catchup_window_seconds`, `jitter_seconds`, `paused`, `temporal_schedule_id`). Reconcile 1:1 onto a stable Temporal Schedule (`schedule-trigger-#{id}`) using `update`/`pause`/`delete` — **not** the current destructive delete-all-then-recreate. The Schedule's Action starts a thin `ScheduledTriggerWorkflow` that emits a normalized `schedule.fired` event into the unified layer, so scheduled triggers flow through the same match → `WorkflowService.start` path as everything else. *Verify the pinned Temporal Ruby SDK version exposes `Schedule::Spec::Calendar`/`Policy(catchup_window:, pause_on_failure:)` before designing the calendar UI.*

---

## 7. Architectural Patterns for the Trigger Layer

### The root problem: today there is no event, only a function call

Every trigger converges on a synchronous Ruby call chain ending in `start_workflow_execution`. There is no durable, queryable record that "something happened" — and `check_auto_trigger` swallows dispatch failures in a `rescue StandardError`. The design must introduce a first-class **event** that is (a) persisted in the *same transaction* as the state change, (b) matched against a generic Trigger registry, and (c) dispatched where the three paths already converge.

### Transactional Outbox (so the event is never lost)

The classic **dual-write** failure: you commit the task move, then call out to start a workflow, and the process crashes in between. A distributed transaction across Postgres and Temporal "is not viable" ([microservices.io](https://microservices.io/patterns/data/transactional-outbox.html)). The Outbox reduces it to one local write — `INSERT` the event into `outbox_events` *inside the same `ActiveRecord::Base.transaction`* that moves the task; either both commit or both roll back. A **relay** (`SELECT … FOR UPDATE SKIP LOCKED` in a worker, or a Temporal cron workflow) then dispatches. Because the relay can crash after dispatch but before marking done, delivery is **at-least-once and consumers must be idempotent**. Preserve **ordering** with a monotonic sequence, optionally partitioned by `aggregate_id`. Mature Rails gems exist (`outboxer`, `rails-transactional-outbox`) to seed the design.

### Pub/sub vs internal event bus — you do NOT need Kafka

For a single app, Postgres-as-outbox + ActiveJob is sufficient ([RorVsWild](https://www.rorvswild.com/blog/2026/advanced-domain-modeling-global-message-bus-event-reporter)). Spectrum: `ActiveSupport::Notifications` is synchronous/in-process with no crash survival (fine for instrumentation, *wrong* as the backbone); `ActiveSupport::EventReporter` (`Rails.event`, Rails 8.1) is a built-in global message bus — an excellent in-process fan-out *API* on top of the durable outbox, but not itself durable; **Rails Event Store** combines durable event storage + after-commit dispatch (an outbox + pub/sub in one library), the strongest single-app choice if you want event history for free ([RES subscribe docs](https://railseventstore.org/docs/v2/subscribe/)). External brokers are justified only at extreme throughput or for cross-service sync.

### The generalized Trigger / Subscription model

Generalize `column_workflow_bindings` and `task_waits` into one table:

```
triggers
  id, tenant_id (company_id / project_id)
  event_type            # "task.column_changed" | "wait.resolved" | "schedule.fired" | "slack.message" | "webhook.received"
  filter_predicate jsonb # {"to_column_id": 42} or {"repo_full_name": "...", "conclusion": "success"}
  target_workflow_id
  trigger_mode           # auto | manual   (from column_workflow_bindings)
  enabled boolean
  dedup_strategy         # cooldown_seconds + dedup_key template
  created_by_id
```

`task_waits` becomes a *waiting-instance* of a trigger whose `filter_predicate` is the JSONB matching already in scopes like `for_github_pr_number`. The matcher is one method: `Trigger.where(tenant, event_type, enabled: true)` then evaluate `filter_predicate` against `payload` (start with simple JSONB key-equality — it covers every current case).

### Idempotency, ordering, and how it lands on Temporal

Layer idempotency at three points: (1) **event `dedup_key`** unique index on the outbox; (2) a **`trigger_dispatches` ledger** keyed `(trigger_id, event_dedup_key)` with a unique constraint — the principled generalization of `cooldown_seconds` and the `workflow_runs.where(state: %w[pending running paused]).exists?` guard; (3) **Temporal Workflow ID as the final idempotency key** — "the Workflow ID acts as an idempotency key, and the Server will return a duplicate error instead of creating the second Workflow" ([Temporal](https://docs.temporal.io/handling-messages)). For ordering, rely on the outbox sequence (producer) + Temporal (per-workflow); promise only per-aggregate ordering.

**Keep matching in-app** (it needs DB access and changes more often than workflow logic; Temporal workflows must stay deterministic). The dispatcher then hits Temporal two ways: **`signal_with_start`** for "launch, or if a run already exists for this task just deliver a signal" (replacing the race-prone "active run exists" rejection), and a plain **signal** to resume a workflow parked on `wait_condition` (the generic form of wait-resolution). Signals are at-least-once, so the **workflow must dedupe by an idempotency key in the signal payload**.

### Recommended layered architecture

1. **Producers** (column-move in `TaskService.move`, `WaitService`, schedule firings, Slack/webhook gateway) write an `OutboxEvent` in the same transaction as their state change.
2. **Relay** (Sidekiq loop or Temporal cron) reads ordered, at-least-once, marks dispatched.
3. **Matcher** loads tenant-scoped `Trigger`s, evaluates `filter_predicate`, writes a dedup-guarded `trigger_dispatches` audit row.
4. **Dispatcher** = thin shim over `WorkflowService.start` / `TemporalService.send_signal`, using `signal_with_start` and deterministic Workflow IDs.
5. **Temporal** owns durable execution and per-workflow ordering.

---

## 8. Strategic Decision: Build vs Buy vs Hybrid

### Verdict: BUILD a native trigger layer on Postgres + the existing Temporal engine. Adopt nothing as the trigger layer.

**Why not buy a full engine (Kestra / Inngest / Trigger.dev / n8n / Windmill / Hatchet):**

1. **Engine overlap.** Each bundles a workflow *execution* plane that duplicates and competes with Temporal. Adopting one means running two orchestrators, two retry/state systems, and an awkward "their trigger → start my Temporal workflow" seam. You need a trigger *layer*, not a second engine.
2. **Not embeddable in Ruby.** Every one is a standalone service (JVM / Go / Node / Rust) integrated over HTTP/gRPC. None is a Ruby library you call in-process from `TaskService`; all add real operational weight (extra service, its own datastore, dashboard, upgrades).
3. **Open-source / self-host trajectory.** The repo is being open-sourced. A hard dependency on a closed cloud (Cursor, Zapier/Make) or a managed bus (EventBridge, Svix-cloud, Inngest-cloud) breaks self-host. This is the single most decision-shaping constraint, and it rules out the cloud-only options outright.
4. **License friction.** n8n's Sustainable Use License restricts reselling-as-a-service; Inngest's server is SSPL (with an unverified DOSP→Apache window); Windmill is AGPLv3 + proprietary EE that **gates exactly the bus triggers (Kafka/WebSocket) you'd most want**. Temporal is MIT and already in place.
5. **Multi-tenancy.** None map onto your per-tenant Rails models; you'd build tenant scoping and authz regardless.

**Why Temporal is the exception (ADOPT what you already run):** it closes two of the three gaps natively at **zero new infra** — Schedules for the user-facing scheduler, and Signal-with-Start for launch-or-resume. It does *not* provide the normalization/matching/ingestion layer — that's the build.

**Why build is tractable here:** the single-action property ("only ever start a workflow") means you are building a fan-in router, not a general pub/sub platform; the matching logic for every current case is JSONB key-equality you already hand-roll in `TaskWait`; and the convergence point (`WorkflowService.start`) stays intact.

**The one defensible "buy" is narrow and self-host-compatible:** if you don't want to build *ingestion*, **self-hosted Svix** (HMAC, idempotency, retry, replay, delivery logs) can front the gateway — but you still build the normalized-event model, the trigger registry, and the matcher in-app, and you still own dedup (Svix Ingest doesn't dedupe). Recommendation: build the gateway too (it's a controller + a `WebhookSource` strategy + a dedup table), and keep Svix as a fallback if inbound volume or delivery-reliability needs outgrow a single Rails endpoint.

### What to steal from each (design, not code)

| Pattern | Source | Maps onto |
|---|---|---|
| Named-event + CEL filter + scope + generic webhook gateway w/ preset/HMAC auth + Event Key Expression | **Hatchet** | the `triggers` table + `WebhookSource` + matcher |
| Normalized event envelope (`name`+`data`+`id` dedup), name→many fan-out, server-side transform, flow control as cooldown | **Inngest** | the event envelope + `dedup_strategy` |
| `event.kind` discriminator + per-binding **preprocessor** adapter; HTTP routes w/ pluggable auth | **Windmill** | payload→workflow-input mapping seam |
| Trigger-as-first-class declarative object; `recoverMissedSchedules` ALL/LAST/NONE + Backfill | **Kestra** | `ScheduleTrigger` catchup policy |
| `repository_dispatch` (one endpoint keyed by type + free payload); `on:` attribute filters; `workflow_run` chaining w/ loop cap | **GitHub Actions** | generic custom-event ingestion + filter predicates + safe chaining |
| Imperative `schedules.create` w/ `externalId` + `deduplicationKey`; `idempotencyKey` + TTL | **Trigger.dev** | per-tenant `ScheduleTrigger` + dispatch dedup |
| "Automation owns N triggers, runs when ANY fires"; webhook URL + minted key; Slack keyword/regex filter | **Cursor** | many-triggers-per-workflow binding + Slack filter |
| instant-vs-poll taxonomy; Catch Hook URL + payload mapping; REST Hook subscribe/unsubscribe lifecycle | **Zapier/Make** | source taxonomy + binding activation UX |

---

## 9. Proposed Design for This System

### New/changed data model

- **`events`** (normalized envelope, CloudEvents attribute model): `id`, `event_type`, `source`, `subject`, `tenant_id`, `data jsonb`, `dedup_key` (unique), `occurred_at`, `received_at`. Doubles as audit + replay log.
- **`outbox_events`**: written in-transaction by internal producers (column-move, wait-resolution, completion); a monotonic `seq`; relay marks `dispatched_at`.
- **`triggers`** (generalizes `column_workflow_bindings` + `task_waits`): `tenant_id`, `event_type`, `filter_predicate jsonb`, `target_workflow_id`, `trigger_mode`, `enabled`, `dedup_strategy` (`cooldown_seconds` + `dedup_key` template), `created_by_id`.
- **`trigger_dispatches`** (audit + dedup ledger): `event_id` → `trigger_id` → `workflow_run_id`, matched-predicate snapshot, unique `(trigger_id, event_dedup_key)`.
- **`webhook_sources`**: `slug`, `provider`, `verification_strategy`, encrypted `secret(s)`, `mapping_spec jsonb`, scope (company/project).
- **`received_webhooks`**: `source_id`, `idempotency_key` (unique with `source_id`), `raw_payload`, `status`.
- **`schedule_triggers`**: per Section 6, reconciled 1:1 onto a Temporal Schedule.
- **`Integration.provider`**: add `slack`.

### End-to-end dispatch path (replaces every `resolve_*`)

```
PRODUCE (in same DB transaction as the state change):
  TaskService.move / WaitService / ScheduledTriggerWorkflow / Webhooks::IngressController
    └─> write OutboxEvent (or insert Event directly for external sources)

RELAY (Sidekiq SKIP-LOCKED loop or Temporal cron):
  OutboxEvent -> normalized Event (dedup on source+id)

MATCH (in-app, tenant-scoped):
  Trigger.where(tenant_id:, event_type:, enabled: true)
    .select { |t| matches?(t.filter_predicate, event.data) }
    -> dedup-guarded trigger_dispatches insert

DISPATCH (thin shim over existing services):
  new run     -> client.signal_with_start_workflow(deterministic_id, ...)  (launch-or-deliver)
  resume wait -> TemporalService.send_signal(workflow_id, name, payload)   (workflow dedupes by key)
```

The five sources — column-move, wait-resolution, schedule, Slack, arbitrary webhook — all become *producers of normalized events*; `check_auto_trigger` stops being the sole convergence point and is replaced by the generic matcher.

### Ingress controller (one endpoint for all webhooks + Slack)

`Webhooks::IngressController#receive(:slug)`: look up `WebhookSource` → verify raw body per strategy (5-min timestamp tolerance) → handle Slack `url_verification` challenge inline → insert `ReceivedWebhook` (unique-index dedup) → `head :ok` → `ProcessWebhookJob.perform_later`. The job maps payload→`data` via `mapping_spec`, builds a normalized `Event`, and enters the matcher.

---

## 10. Implementation Roadmap and Risk Assessment

**Phase 0 — De-risk the scheduler (small, high value).** Make `sync_schedules` non-destructive (`update`/`pause` instead of delete-all-recreate) before adding dynamic schedules; verify the pinned Temporal Ruby SDK exposes calendar/catchup/pause-on-failure. *Risk: destructive reconcile drops in-flight buffered actions on deploy.*

**Phase 1 — Event + outbox + matcher (no new sources yet).** Introduce `events`, `outbox_events`, `triggers`, `trigger_dispatches`. Make `column_workflow_bindings` and `task_waits` emit/consume through the new path behind a feature flag; run dual-write/shadow to compare old vs new dispatch. *Risk: behavior drift; mitigate with shadow comparison + the `trigger_dispatches` audit.*

**Phase 2 — Generic webhook gateway.** Add `webhook_sources` + `received_webhooks` + `Webhooks::IngressController`; migrate GitHub/GitLab to registered sources (keep old controllers as fallback). Real dedup replaces reliance on the Redis cooldown.

**Phase 3 — Slack.** Add `slack` provider + v0 verification strategy + `url_verification` handshake + Events API ingestion via the gateway; map workspace/channel → project/board.

**Phase 4 — Schedule triggers (user-facing).** `ScheduleTrigger` reconciled onto Temporal Schedules; `ScheduledTriggerWorkflow` emits `schedule.fired`.

**Phase 5 — Decommission** the bespoke `resolve_*` methods and the legacy controllers once the new path is proven.

**Top risks:** (1) treating the existing cooldown as dedup — it isn't; (2) any buy decision that breaks self-host; (3) effort/timeline estimates for a native build — the least-grounded numbers here, flag as low confidence until scoped against the real implementation epic; (4) cross-tenant event injection on a shared ingress URL (Section 11); (5) fan-out storms (one webhook → many bindings → N launches).

---

## 11. Cross-Cutting Concerns

- **Security (per-source, unified in the gateway):** raw-body HMAC/signature verification per strategy (GitHub/GitLab/Linear/Slack differ), 5-min timestamp tolerance for replay, Slack `url_verification` challenge, encrypted rotating secrets. Do **not** flatten these into one "HMAC" code path.
- **Idempotency/dedup:** stable dedupe key + `received_webhooks`/`trigger_dispatches` store + TTL ≥ provider retry window. Explicitly *replaces* the 5-second Redis cooldown for correctness (the cooldown stays only as user-facing rate-limiting).
- **Multi-tenant authz:** stamp every `event`/`trigger` with `tenant_id`; the matcher filters by tenant *before* predicate evaluation (never match across companies); authorize trigger creation with the same `Workflow.visible_for_project` check `ColumnWorkflowBinding` already enforces; map shared ingress URLs (Slack `team_id`/channel) to a scope to prevent cross-tenant injection.
- **Observability:** the `trigger_dispatches` row (`event → trigger → workflow_run` + predicate snapshot) answers "why did/didn't this workflow fire," replacing the opaque `BoardActivity :workflow_started`. Add a dead-letter for unmatched/unparseable events and ingestion/delivery logs.
- **Rate-limiting & fan-out:** generalize `cooldown_seconds` into Inngest-style flow control (debounce/throttle keyed by expression); bound completion-chaining like GitHub Actions' 3-level cap to prevent loops.
- **Testing:** replay captured provider payloads; signature-fixture tests; Temporal test-env clock simulation for schedules; end-to-end "event → match → Temporal start" integration tests.
- **Migration:** backward-compatible dual-write/shadow period; reconcile `cooldown_seconds` + `wait_type` enum semantics with the generic matcher before decommissioning `resolve_*`.

---

## 12. Open Questions

1. Persist **every** event (full audit/replay, grows unbounded) or only matched events (cheaper, loses the trail)? Likely: persist all with a retention policy.
2. Should the matcher run in ActiveJob (as today) or as a Temporal activity (durable, retryable end-to-end)?
3. How exactly does the CloudEvents `source`+`id` dedupe key feed Temporal's deterministic Workflow ID and `WorkflowIdReusePolicy` (RejectDuplicate vs AllowDuplicateFailedOnly) to preserve "one active run per task"?
4. Predicate language: fixed indexed attribute filters (`type` + `subject` + a few known fields) vs an expressive JSONB/CEL-ish mini-DSL? Start fixed; JSONB content queries are the most expensive tier.
5. Do scheduled triggers operate on an existing `board_task` or create a new task on fire? The `ScheduleTrigger → event` contract must define this.
6. Multi-tenancy of Temporal Schedules: single namespace (so `schedule_id` encodes project) vs per-namespace isolation — affects list/describe scoping.
7. Slack as inbound-webhook (Events API) vs message/queue (Socket Mode)? HTTP gateway is the default; Socket Mode only for firewalled customers (needs a long-running worker).

---

## 13. Research Methodology and Source Verification

**Approach:** parallel multi-agent research — 4 conceptual sections + 10 per-competitor deep dives, each competitor followed by an independent adversarial fact-checker that re-searched primary sources to refute claims, plus a final completeness critic. 25 agents total; all 10 competitors returned **net confidence: high**.

**Primary sources (selected, all fetched live):**

- Standards/patterns: [CloudEvents v1.0.2 spec](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md), [CloudEvents Ruby SDK](https://github.com/cloudevents/sdk-ruby), [Transactional Outbox](https://microservices.io/patterns/data/transactional-outbox.html), [Rails Event Store](https://railseventstore.org/docs/v2/subscribe/), [Rails 8.1 EventReporter](https://www.rorvswild.com/blog/2026/advanced-domain-modeling-global-message-bus-event-reporter).
- Webhooks/Slack: [Slack verification](https://docs.slack.dev/authentication/verifying-requests-from-slack/), [Slack Events API](https://docs.slack.dev/apis/events-api/), [Slack HTTP vs Socket](https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/), [Stripe webhooks](https://docs.stripe.com/webhooks), [GitHub webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks), [Svix security](https://docs.svix.com/security), [Hookdeck infra guide](https://hookdeck.com/webhooks/guides/webhook-infrastructure-guide), [Linear webhooks](https://linear.app/developers/webhooks).
- Scheduling: [Temporal Schedules](https://docs.temporal.io/schedule), [Ruby Schedule::Spec](https://ruby.temporal.io/Temporalio/Client/Schedule/Spec.html), [Temporal Ruby schedules](https://docs.temporal.io/develop/ruby/workflows/schedules), [Solid Queue](https://github.com/rails/solid_queue), [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron).
- Competitors: [Kestra triggers](https://kestra.io/docs/workflow-components/triggers), [Cursor Automations](https://cursor.com/docs/cloud-agent/automations), [Temporal messages](https://docs.temporal.io/sending-messages), [Inngest events & triggers](https://www.inngest.com/docs/features/events-triggers), [Trigger.dev triggering](https://trigger.dev/docs/triggering), [n8n Webhook node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/), [Windmill triggers](https://www.windmill.dev/docs/getting_started/triggers) & [preprocessors](https://www.windmill.dev/docs/core_concepts/preprocessors), [Hatchet events](https://docs.hatchet.run/v1/events) & [webhooks](https://docs.hatchet.run/v1/webhooks), [GitHub Actions events](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows), [Zapier triggers](https://help.zapier.com/hc/en-us/articles/8496244568589-How-Zap-triggers-work), [Make webhooks](https://help.make.com/webhooks).

**Verification corrections folded in:** Inngest SSPL→Apache "3-year" window unverified; GitHub Actions IANA-timezone cron new ~March 2026 (historically UTC-only); Cursor Automations *launched* 2026-03-05 (not "GA"); Kestra OSS *does* support SECRET-input encryption (only governance features are Enterprise); n8n no-backfill behavior is real but not on the cited common-issues page; Windmill `webhook` event kind lacks `trigger_path`; the existing 5-second Redis cooldown is throttling, not deduplication.

**Limitations:** AWS EventBridge included from general knowledge (medium confidence, not independently deep-verified this pass); build effort/timeline estimates are deliberately unquantified pending scoping against the real implementation epic.

---

## Technical Research Conclusion

**Build a native, in-app event-driven trigger layer on Postgres + the Temporal engine you already run.** Introduce a normalized event (CloudEvents attribute model), a transactional outbox for internal producers, a generic webhook gateway (one ingress endpoint + per-source verification strategies + a dedup table) that subsumes the bespoke GitHub/GitLab controllers and admits Slack and arbitrary webhooks, and a generalized `triggers` registry that subsumes `column_workflow_bindings` and `task_waits`. Use Temporal **Schedules** for the user-facing scheduler and **Signal-with-Start** for launch-or-resume. Adopt none of the ten competitors as the layer — they either duplicate Temporal, can't be embedded in Ruby, or break the open-source/self-host direction — but steal their best trigger *abstractions* (Hatchet's gateway + CEL matching, Inngest's envelope, Windmill's preprocessor, Kestra's declarative triggers, GitHub Actions' `repository_dispatch`, Trigger.dev's per-tenant schedules). The result is that adding a new trigger source becomes adding a *producer of normalized events* — never editing the routing logic again.

---

**Technical Research Completion Date:** 2026-06-22
**Source Verification:** All competitor claims adversarially re-checked against primary sources (net confidence: high).
**Technical Confidence Level:** High for the trigger-model findings and the build-vs-buy reasoning; medium where flagged (EventBridge depth, effort estimates).
