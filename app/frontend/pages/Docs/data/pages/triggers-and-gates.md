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

> **info** Two primitives, not one. **Triggers start runs. Gates defer them.** A CI "wait" is a *gate*, not a trigger — see [Gates & waits](#gates-and-waits) below. Keeping the two apart is the key to the whole model.

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
answer "what task, if any, is this run about?" — that is [`subject_policy`](#subject-policy).

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
Webhook: ref = refs/heads/main AND   repository.name = palad-app
```

Filters are stored as `filter_predicate` and matched by exact key/value
containment against the event data. Conditions are AND-ed.

> **info** v1 matching is **exact equality**. Richer operators (`contains`, regex, comparisons) are a planned extension — until then the editor shows them disabled.

## Gates and waits

A **wait** is not a trigger — it is a *gate*: a runtime precondition attached
to a single task that **holds the column auto-trigger** until an external
condition clears.

A wait is created **by a running workflow**, via the `board_create_wait` tool —
for example, an agent opens a pull request and then parks the task until CI is
green. While any wait is pending, the column auto-trigger will not start the
next run for that task. When the matching CI event arrives
(GitHub checks / GitHub Actions / GitLab pipeline), the wait resolves and the
auto-trigger re-evaluates — firing only once the **last** wait clears.

| | Trigger | Gate (wait) |
| --- | ------- | ----------- |
| **Effect** | starts a run | defers the auto-start |
| **Lifetime** | standing config | runtime, one-shot, per task |
| **Created by** | a person, in config | a workflow step (`board_create_wait`) |
| **Cleared by** | — | a matching CI event (resolve once) |

So the same CI webhook can do one of two things: **resolve a gate** on a
waiting task (today's path), or — if you bind a workflow to a `ci.completed`
event — **start a run** directly. Wait-resolution is the special case;
event-to-workflow matching is the general one.

> **tip** A card "stuck" in a bound column almost always has a pending wait. Open it and clear the wait, and the binding re-evaluates.

## Inbound webhooks = a start API

The generic gateway turns any external system into a workflow launcher:

```bash
curl -X POST https://<host>/webhooks/in/<endpoint-slug> \
  -H 'Content-Type: application/json' \
  -H 'X-Idempotency-Key: build-7f3a' \
  -d '{ "ref": "refs/heads/main", "repository": { "name": "palad-app" } }'
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
  while the task has pending **waits**, or after a `quota_exceeded` failure.

> **warning** The cooldown is rate-limiting, not correctness. Idempotency comes from the delivery-id dedup and the dispatch ledger.

## Data model

| Table | Role |
| ----- | ---- |
| `trigger_events` | the normalized event envelope + audit/replay log |
| `trigger_bindings` | off-board standing triggers (schedule / Slack / webhook) |
| `trigger_dispatches` | audit + idempotency ledger (`event → trigger → run`) |
| `webhook_endpoints` | a registered inbound source (slug, provider, verification, secret) |
| `received_webhooks` | raw inbound deliveries + idempotency store |
| `column_workflow_bindings` | board-native column → workflow binding (unchanged) |
| `task_waits` | runtime CI gates on a task (unchanged) |

The pipeline is unified; the storage is not. Board bindings and waits keep
their own tables and semantics — the engine just reads them through the same
match-and-dispatch path. See the [domain model reference](/docs/reference).
