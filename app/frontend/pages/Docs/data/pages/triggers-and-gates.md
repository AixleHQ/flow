# Triggers and Gates

A **trigger** answers one question: *when should a workflow run start?* A **gate**
answers the opposite: *what must hold before a started run is allowed to proceed?*
Triggers start runs; gates defer them. Aixle
Flow funnels every source — a card moving columns, a timer, a Slack message,
an inbound webhook, a manual click — through one pipeline:

```
event  →  normalize  →  dedup  →  match a trigger  →  start a WorkflowRun
```

Adding a new source means emitting a normalized **event**, never editing the
dispatch logic. This page explains the model end to end.

> **info** Two primitives, not one. **Triggers start runs. Gates defer them.** A CI check is a *gate*, not a trigger — see [Gates](#gates) below. Keeping the two apart is the key to the whole model.

## The trigger pipeline

Every happening becomes a row in `trigger_events` (a normalized envelope:
`event_type`, `source`, `subject`, `data`, `dedup_key`). The matcher loads the
triggers for that event's project and event type, evaluates each trigger's
filter, and — for every match — starts one `WorkflowRun` through the single
shared path (`WorkflowService.start`). A `trigger_dispatches` ledger records
*which event, matched by which trigger, started which run*, and its unique
`dedup_key` guarantees an at-least-once event never launches the same run twice.

## Trigger sources

| Source | Fires when | Where it's configured |
| ------ | ---------- | --------------------- |
| **Column binding** | a card enters a bound column (`auto`) | Board settings, per column |
| **Manual** | you press *Run* on a task or workflow | the UI / API |
| **Schedule** *(planned)* | a timer fires (interval / cron / calendar) | the workflow's Triggers |
| **Slack message** | a message / mention / reaction matches | the workflow's Triggers |
| **Inbound webhook** | an external system POSTs to the endpoint | the workflow's Triggers |

Column binding and manual are **board-native** — the task already exists.
Schedule, Slack and webhook originate **off the board** and must therefore
answer "what task, if any, is this run about?" — that is [`subject_policy`](#subjectpolicy).

> **tip** Column bindings stay configured on the Board (one workflow per column, see [Board](/docs/board)). The other sources live on the workflow, so a workflow declares how it launches — like `on:` in CI.

## subject_policy

Because a `WorkflowRun` may or may not be about a board task (its
`board_task_id` is nullable), every off-board trigger carries a **subject
policy** — the single field that decides the run's board context:

| Policy | What happens | The run is about | Typical use |
| ------ | ------------ | ---------------- | ----------- |
| `existing_task` | attaches to the task from context | an existing card | column binding, manual |
| `none` | runs with no card | nothing (`board_task_id` is null) | a scheduled background job |
| `create_task` | creates a card first, then runs on it | a fresh card | a schedule/Slack/webhook that should appear on the board |

A scheduled trigger therefore **starts a workflow, not a task** by default
(`subject_policy: none`) — a project-level run you'll find under Workflow Runs,
not on the board. Choose `create_task` (with a target column and a title
template) when you want a visible card for comments, assets, or human handoff.

> **warning** A workflow that reads board context (task description, comments, the linked PR) is **useless run with `none`** — the context is simply empty. The run won't crash, but it won't have anything to work on. Use `create_task`, or only point task-less triggers at task-agnostic workflows.

## Filters — run only when…

A trigger can carry a **filter** over the event payload, so it fires only on
matching events:

```
Slack:   channel = #deploys   AND   text = "ship it"
Webhook: ref = refs/heads/main AND   repository.name = my-app
```

Filters are stored as `filter_predicate` and matched by exact key/value
containment against the event data. Conditions are AND-ed.

> **info** v1 matching is **exact equality**. Richer operators (`contains`, regex, comparisons) are a planned extension — until then the editor shows them disabled.

## Gates

A **gate** is not a trigger — it is a runtime precondition attached
to a single task that **holds the column auto-trigger** until an external
condition clears.

A gate is created **by a running workflow**, via the `board_create_gate` tool —
for example, an agent opens a pull request and then parks the task until CI is
green. While any gate is pending, the column auto-trigger will not start the
next run for that task. When the matching CI event arrives
(GitHub checks / GitHub Actions / GitLab pipeline), the gate resolves and the
auto-trigger re-evaluates — firing only once the **last** gate clears.

| | Trigger | Gate |
| --- | ------- | ----------- |
| **Effect** | starts a run | defers the auto-start |
| **Lifetime** | standing config | runtime, one-shot, per task, TTL-bounded |
| **Created by** | a person, in config | a workflow step (`board_create_gate`) |
| **Cleared by** | — | a matching CI event, or reconciliation (see below) |

### TTL and reconciliation

A gate must not be able to park a card forever. Every CI gate therefore carries a
**TTL** (`gates.ttl_hours`, 12h by default) alongside the repository and
run/check/pipeline identifiers it was created with, and a scheduled sweep
reconciles the gates whose webhook never arrived:

1. Ten minutes after a gate is created (`gates.reconcile_after_minutes`) it
   becomes eligible for reconciliation, and is re-checked at most that often
   afterwards. The webhook stays the fast path — reconciliation only ever sees
   what it missed.
2. The sweep asks the provider what happened to that exact run. If the provider
   has a verdict, the gate resolves **with that verdict** — a failed check
   resolves as failed, never as a pass.
3. If the run, pull request, pipeline or repository cannot be read at all (deleted
   run, repository detached from the project, integration disconnected), no
   webhook can ever resolve the gate, so it is marked **stale** immediately with a
   diagnostic reason.
4. If the provider says the run is still going — or cannot be reached — the gate
   keeps waiting until its TTL runs out, and is then marked **stale** too.

Whoever gets there first wins, once. If the real webhook arrives while the sweep is
still asking the provider, the webhook's verdict stands and the late answer is
discarded (recorded in the gate's log as `superseded`) — a reported CI failure is
never overwritten by "no verdict", and the card's automation is never released
twice.

A stale gate stops blocking the column auto-trigger (that is the point: the card
moves again) but is never recorded as a success. It keeps a `diagnostic_reason`, a
`reconciliation_log` of everything the sweep saw, and it raises a board activity
event. So the four CI states are always distinguishable on the card:

| Card says | Meaning |
| --- | --- |
| **CI pending** | still waiting on the provider, with the age of the wait |
| **CI passed** | provider reported success |
| **CI failed** | provider reported a failure — nothing bypassed it |
| **CI stale** | no verdict was ever obtained; the reason says why |

`list_gates` returns the same fields (age, TTL, source, diagnostic reason,
reconciliation log) for an agent, and `delete_gate` still clears a gate by hand.

So the same CI webhook can do one of two things: **resolve a gate** on a
waiting task (today's path), or — if you bind a workflow to a `ci.completed`
event — **start a run** directly. Wait-resolution is the special case;
event-to-workflow matching is the general one.

> **tip** A card "stuck" in a bound column almost always has a pending gate. Open it: the CI gates panel names the run it is waiting on and how long it has been waiting, and clearing the gate re-evaluates the binding. A gate marked **CI stale** has already stopped blocking the column — read its reason before re-running anything.

## Inbound webhooks = a start API

The generic gateway turns any external system into a workflow launcher:

```bash
curl -X POST https://<host>/webhooks/in/<endpoint-slug> \
  -H 'Content-Type: application/json' \
  -H 'X-Idempotency-Key: build-7f3a' \
  -d '{ "ref": "refs/heads/main", "repository": { "name": "my-app" } }'
```

The gateway verifies the signature on the raw body (per the endpoint's
strategy), de-duplicates on a stable delivery id, returns `2xx` immediately,
then normalizes the payload into a `webhook.received` event that the matcher
routes to your workflow. In effect, **a webhook endpoint is a small, signed,
idempotent API for starting a workflow** — the groundwork for an
`aixle flow` CLI.

### Scope: per project

Triggers are **project-scoped**. Every `WorkflowRun` belongs to a project (even
a company-shared workflow runs *within* a project), so a webhook endpoint
belongs to a project and its triggers start runs there. There is no
"company-wide start" — that would still have to pick a project. Each project
gets its own endpoints and trigger URLs, which is exactly the granularity a CLI
wants: `aixle flow run <workflow> --project <id>`.

### Verification strategies

| Strategy | Header | Notes |
| -------- | ------ | ----- |
| `slack_v0` | `X-Slack-Signature` | HMAC-SHA256 over `v0:{ts}:{body}`, 5-min replay window |
| `hmac_sha256` | `X-Hub-Signature-256` (configurable) | GitHub-style `sha256=…` |
| `shared_token` | `X-Webhook-Token` (configurable) | constant-time token compare |
| `none` | — | for trusted, network-isolated sources only |

Secrets are stored encrypted per endpoint and verified on the **raw** request
body. Slack endpoints also answer the `url_verification` handshake automatically.

## Idempotency & guards

- **Ingestion dedup** — a re-delivered webhook (same delivery id) is accepted
  with `2xx` but processed once (`received_webhooks` unique index).
- **Dispatch dedup** — the `trigger_dispatches` ledger suppresses a duplicate
  launch for the same `(event, trigger)`.
- **Cooldown** — a per-trigger minimum gap (throttling, *not* dedup).
- **Auto-trigger guards** — the column auto-trigger is additionally skipped
  while the task has pending **gates**, or after a `quota_exceeded` failure.

> **warning** The cooldown is rate-limiting, not correctness. Idempotency comes from the delivery-id dedup and the dispatch ledger.

## Delivery guarantees (transactional outbox)

Board-native triggers (a task entering a column, a gate resolving, the manual
**Run** button) face a classic dual-write hazard: the task move commits, then the
process dies before the workflow is launched, and the trigger is lost. To prevent
that, those producers record the `trigger_event` **in the same database
transaction as the move/gate change** (`relay_state: pending`), then dispatch it
inline. Either both commit or neither does.

A **relay** — a Temporal cron (`outbox_relay_workflow`, every minute, SKIP-overlap)
— sweeps any event left `pending` past a short grace window (a crash victim) and
dispatches it. So delivery is **at-least-once**, and the dispatch ledger keeps it
to a single launch. The happy path is still the inline dispatch; the relay only
recovers from a crash, so a restart never drops a trigger.

> **note** A workflow can, in rare crash windows, be *started* twice (the relay re-launches what a dying process may have already begun). The dispatch ledger collapses this to one run in the common case; design long-running side effects to tolerate at-least-once.

## Data model

| Table | Role |
| ----- | ---- |
| `trigger_events` | the normalized event envelope + audit/replay log; also the transactional **outbox** (`relay_state`) |
| `trigger_bindings` | off-board standing triggers (schedule / Slack / webhook) |
| `trigger_dispatches` | audit + idempotency ledger (`event → trigger → run`) |
| `webhook_endpoints` | a registered inbound source (slug, provider, verification, secret) |
| `received_webhooks` | raw inbound deliveries + idempotency store |
| `column_workflow_bindings` | board-native column → workflow binding |
| `gates` | runtime CI gates on a task |

The pipeline is unified; the storage is not. Board bindings and gates keep
their own tables and semantics — the engine just reads them through the same
match-and-dispatch path. See the [domain model reference](/docs/reference).
