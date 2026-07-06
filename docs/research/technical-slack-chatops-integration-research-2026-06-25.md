---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: ['ai/research/technical-event-driven-workflow-triggers-research-2026-06-22.md']
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Improved Slack integration for Aixle — one-time per-project bot that triggers workflows by text match, replies in-channel, and ingests message file attachments into the workflow'
research_goals: 'Design the smallest correct evolution of the existing event-driven Slack integration so that: (1) the bot is configured once per project; (2) it starts workflows by text match; (3) it replies back in the channel; (4) files attached to the triggering message are downloaded and passed into the workflow as inputs. Compare delivery surfaces (slash commands vs Events API vs Socket Mode). Output: a research/design doc to drive design + implementation.'
user_name: 'Artem_Petrov'
date: '2026-06-25'
web_research_enabled: true
source_verification: true
---

# Research Report: Improved Slack Integration (ChatOps) for Aixle Flow

**Date:** 2026-06-25
**Author:** Artem_Petrov
**Research Type:** technical
**Builds on:** `ai/research/technical-event-driven-workflow-triggers-research-2026-06-22.md` (the event-driven trigger layer / PR #262)

---

## Research Overview

This document designs the next iteration of the Slack integration on top of the existing
event-driven trigger layer. The target experience, in the requester's words (translated):

> "I configure the bot once in a project; after that it can start workflows by text match
> and reply back. I also want that, if a message has some uploaded assets attached, the bot
> can fetch them too and pass them into the workflow."

Four requirements:

1. **One-time per-project setup** — connect the Slack bot once; every trigger reuses it.
2. **Text-match → workflow** — an incoming message whose text matches a rule starts the bound workflow.
3. **Reply in-channel** — the bot acknowledges ("starting…") and reports the result ("done / failed").
4. **File ingestion** — files attached to the triggering message are downloaded and passed into the workflow as input assets.

**Methodology.** Current Slack platform mechanics were verified against Slack's official
developer docs (June 2026); each load-bearing claim is cited inline and in **Sources**.
The Aixle side is grounded in the actual code on `feature/174-event-driven-workflows`
(file:line references). Confidence is called out where the platform behaviour is
version-sensitive (file downloads, install/token model).

---

## 1. Current State (baseline on PR #262)

The Slack integration today is **inbound-only** and rides the generic webhook gateway:

| Piece | File | Behaviour |
| --- | --- | --- |
| Connect | `app/services/slack/integration_service.rb` | Stores **only** a `signing_secret` in `Integration#credentials_data`; provisions a `WebhookEndpoint` (`slug: "slack-<id>"`, `verification_strategy: slack_v0`) and computes the Request URL `https://<DOMAIN>/webhooks/in/slack-<id>`. |
| Ingress | `app/controllers/webhooks/ingress_controller.rb` | Resolves endpoint by slug → echoes the Slack `url_verification` challenge → verifies the `v0=` signature on the raw body → stores a `ReceivedWebhook` (dedup on `event_id`) → 2xx → enqueues `Webhooks::ProcessEventJob`. |
| Verify | `app/services/webhooks/signature_verifier.rb` | `slack_v0`: HMAC-SHA256 over `v0:{ts}:{raw_body}`, constant-time compare, 5-min replay window. |
| Normalize | `app/jobs/webhooks/process_event_job.rb#normalize_slack` | Emits `slack.message` with `data: { slack_event_type, channel, user, text, team }`; ignores `bot_id` (no loops). **Does not capture `ts` (message timestamp) or `files[]`.** |
| Match & fire | `app/services/trigger_engine.rb` | `publish → dispatch → TriggerBinding.for_event.matches?(data) → fire_for_binding`. The binding's `subject_policy` (none / existing_task / create_task) decides the run's task; then `WorkflowService.start(mode: :non_interactive)`. |
| Configure trigger (UI) | `WorkflowTriggersDrawer.tsx` | Slack kind exposes **channel** + **text contains** filters, written to `filter_predicate`. |

**Gaps relative to the four requirements:**

- **(1)** Connect already exists and is per-project — but it stores only the signing secret. Replies and file downloads both need a **bot token**, which is not stored today.
- **(2)** Text-match already works (one `TriggerBinding` per workflow, `filter_predicate` channel + `text contains`). The matching primitive is sufficient; what is missing is a per-project "router" mental model and richer matching.
- **(3)** No outbound capability whatsoever — `grep` finds no `chat.postMessage`, no bot token, no `response_url` usage. The bot **cannot** reply.
- **(4)** `normalize_slack` drops `files[]`; `fire_for_binding → fire_workflow → WorkflowService.start` never forwards `input_asset_ids` or the event payload into the run. No file path exists.

Two reusable Aixle primitives make the additions cheap:

- **Assets are Shrine-backed.** `AssetVersion` (`app/models/asset_version.rb`) does
  `include AssetFileUploader::Attachment(:file)` with a `source` enum
  `upload | workflow | github | session`. Shrine can attach directly from a remote IO,
  so a downloaded Slack file becomes an `Asset` + `AssetVersion(source: :slack)` with no
  extra storage plumbing. `Asset` is scoped to `Project`/`Company` and has a `created_by` user.
- **Workflows already accept input assets.** `WorkflowService.start(... input_asset_ids: [], ...)`
  (`app/services/workflow_service.rb:15`) persists them onto the `WorkflowRun`. Passing
  Slack files into a run is therefore "ingest → get asset ids → pass `input_asset_ids`".
- **`Integration#credentials_data`** is an encrypted JSON blob, so a `bot_token` can sit next
  to the `signing_secret` with no schema change.

---

## 2. Slack Platform Mechanics (verified June 2026)

### 2.1 Delivery surfaces — how a "command" reaches us

| Surface | Carries file attachments? | Needs public URL? | Notes |
| --- | --- | --- | --- |
| **Slash command** (`/aixle …`) | **No** — the payload is form-urlencoded command text + `response_url` only | Yes (Request URL) | Must ACK within 3 s; can post follow-ups via `response_url` for up to 30 min; `response_type` `ephemeral` (default) or `in_channel`. ([slash-commands](https://api.slack.com/interactivity/slash-commands)) |
| **Events API** (`app_mention`, `message.channels`) | **Yes** — message events include a `files[]` array | Yes (Request URL) | Signed with the signing secret; Slack retries on non-2xx and sends `X-Slack-Retry-Num` → must fast-ACK + dedup. This is the surface the current gateway already serves. |
| **Socket Mode** | **Yes** (same events) | **No** | App opens a WebSocket via `apps.connections.open` with an **app-level token** (`xapp-`, scope `connections:write`); "your app does not need a Request URL"; built for apps "behind a corporate firewall". ([socket-mode](https://docs.slack.dev/apis/events-api/using-socket-mode/)) Requires a persistent WS consumer process. |

> **Decision — Socket Mode is NOT used; the HTTP Events API gateway is the transport.** Slack
> positions Socket Mode as a **development / local** transport, recommends HTTP request URLs **for
> production** ("more prone to network faults because the connection is a long-lived one"), and
> **Socket-Mode apps cannot be distributed in the Slack Marketplace**.
> ([comparing-http-socket-mode](https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/),
> [connections:write](https://docs.slack.dev/reference/scopes/connections.write/)) Aixle is a
> **multi-company (multi-workspace) product**, so Socket Mode would also mean one long-lived socket
> *per customer workspace* — operationally worse and Marketplace-incompatible. We use the HTTP
> gateway (already built) for all installs.

> **Load-bearing finding:** **slash commands do not carry files.** Requirement (4) — ingesting
> message attachments — is only satisfiable via the **Events API** (or Socket Mode), where
> message/`app_mention` events include `files[]`. A slash command can *name* a workflow but
> can never *attach* the file. This eliminates "slash command only" as a complete design.

### 2.2 Replying in-channel

`chat.postMessage` with the **`chat:write`** scope; reply in-thread by passing
`thread_ts` (the triggering message's `ts`); `blocks` for Block Kit; `reply_broadcast` to
also surface a threaded reply to the channel. ([chat.postMessage](https://docs.slack.dev/reference/methods/chat.postMessage/),
[chat:write](https://docs.slack.dev/reference/scopes/chat.write/)) Replying therefore needs:
the **bot token**, the **channel id** (we have it), and the **message `ts`** (we currently drop it).

### 2.3 Downloading attached files

A file object carries `id, name, title, url_private, url_private_download, mimetype,
filetype, size, user`. **Both `url_private` and `url_private_download` require an
`Authorization: Bearer <token>` header with a token bearing at least the `files:read`
scope** — they are not public URLs. ([working-with-files](https://docs.slack.dev/messaging/working-with-files/),
[file-object](https://docs.slack.dev/reference/objects/file-object/), [files:read](https://docs.slack.dev/reference/scopes/files.read/))
So file ingestion needs the **bot token** + **`files:read`**, and is a plain authenticated GET
streamed into Shrine.

> **Confidence:** High on "Bearer token + `files:read` required". Medium on long-term URL
> stability — Slack has periodically tightened file-URL access; the design should download
> **at ingest time** (not store `url_private` for later) to avoid expiry/permission drift.

### 2.4 Auth, install & the multi-workspace model

Aixle connects **many companies' Slack workspaces** to **one** Aixle Slack app, so the install
model is **OAuth v2 distribution**, not pasted tokens.

**Two setup levels — don't conflate them:**

1. **Platform, once ever (by the Aixle operator/vendor):** register a single Slack app at
   `api.slack.com/apps`; set its scopes, Events **Request URL**, OAuth **redirect URL**, and turn on
   public distribution; put its `client_id`, `client_secret`, and `signing_secret` into Aixle's
   server config as **`Settings.slack.*` ← ENV** (`SLACK_CLIENT_ID` / `SLACK_CLIENT_SECRET` /
   `SLACK_SIGNING_SECRET`) — the **same convention as `Settings.github.*` (GitHub App) and
   `Settings.google.*` (Google OAuth)**, *not* the super-admin UI (decided 2026-06-25). This is
   **not** per-company/per-project — one time for the whole deployment. (Self-hosted = the operator
   does it for their app; hosted SaaS = Aixle the vendor does it once for everyone.)
2. **Per company/project, lightweight (by each customer):** click **"Connect Slack"** in a project →
   OAuth consent → Aixle stores that workspace's bot token. No app registration, no secrets pasted.

Details of level 1's shared config and level 2's per-workspace install:

- **One app, shared config**: a single **signing secret**, a single **Events API Request URL**, and
  a single **OAuth redirect URL** are configured once on the Slack app and shared by *all*
  workspaces. The **signing secret is app-level — one per app, not per workspace** (a common point
  of confusion); inbound verification uses that one secret regardless of which workspace sent the event.
- **Per-workspace install via OAuth v2**: a user clicks "Connect Slack" inside an Aixle project →
  redirect to `slack.com/oauth/v2/authorize` (requested scopes + a signed `state` encoding the
  project) → Slack redirects back with a `code` → exchange via `oauth.v2.access` → receive a
  **per-workspace bot token** (`xoxb-…`) plus the `team` (workspace) id.
  ([oauth-v2](https://api.slack.com/authentication/oauth-v2), [token-types](https://api.slack.com/authentication/token-types))
- **Installation store**: persist one record per workspace — `team_id → { bot_token, bot_user_id,
  scopes, enterprise_id? }` — bound to the Aixle company/project that started the install (from the
  OAuth `state`). In Aixle this is one `Integration` (provider `slack`) per `(project, team_id)`,
  bot token in `credentials_data`.
- **Inbound routing by `team_id`**: every workspace's events POST to the **same** Request URL; the
  payload's `team_id` selects the right install → its bot token + project.
  ([events-api](https://docs.slack.dev/apis/events-api/))
- **Distribution**: the app must be made publicly installable ("Activate Public Distribution");
  redirect + request URLs must be HTTPS. Marketplace listing is optional (adds review).
  ([distributing](https://api.slack.com/start/distributing))
- **Lifecycle**: subscribe to `app_uninstalled` and `tokens_revoked` to deactivate/delete an install
  when a workspace removes the app (event order is not guaranteed).
  ([app_uninstalled](https://api.slack.com/events/app_uninstalled), [tokens_revoked](https://docs.slack.dev/reference/events/tokens_revoked/))
- **Token rotation** is **optional**: off → bot tokens are long-lived; on → tokens expire in 12 h and
  need refresh-token handling. ([token-rotation](https://docs.slack.dev/authentication/using-token-rotation/))
  Recommend **off** initially.

This **changes the current per-integration model**: today `Slack::IntegrationService` provisions a
`WebhookEndpoint` with a *per-integration* slug + a *pasted* signing secret. For multi-workspace
there is **one** Slack endpoint (app-level signing secret, one Request URL) and the per-workspace
unit becomes the **bot token keyed by `team_id`** — see §3.1.

---

## 3. Recommended Architecture

**Verdict: one Aixle Slack app, HTTP Events API gateway, multi-workspace via OAuth, routed by
`team_id`.** Events from every connected workspace arrive at one Request URL, are verified with the
app's single signing secret, routed by `team_id` to the right install (bot token) + project, then
flow through the existing normalize→publish→dispatch core. **Socket Mode is rejected** (dev-
positioned, Marketplace-ineligible, and one socket-per-workspace is operationally worse for a
multi-company product, §2.1). Slash commands remain a *later, optional* convenience for explicit
`/aixle run "<name>"` with no attachments (they carry no files, §2.1).

This honours the architectural invariant from the trigger-layer research ("adding a source =
adding a producer of normalized events"): the only genuinely new inbound work is **resolving the
install by `team_id`** before normalize; everything after is shared.

### 3.1 One-time per-project connect, multi-workspace (Req 1)

- **Connect = OAuth install, not paste-token.** "Connect Slack" in a project starts the OAuth v2
  flow with `state = signed(project_id)`; the callback exchanges the `code`, stores the
  per-workspace **bot token** + `team_id` on a `slack` `Integration` bound to that project, and marks
  it `:active` (or `:error` with a repair hint — reusing the service's existing active/error pattern).
- **One shared endpoint, route by `team_id`.** Replace the per-integration `WebhookEndpoint` slug
  for Slack with a single Slack events endpoint. The ingress verifies the `v0=` signature with the
  **app signing secret** (config/ENV, one value), parses `team_id`, finds the `Integration` for that
  workspace, and proceeds. (The generic `WebhookEndpoint` gateway stays for non-Slack webhooks.)
- **Reuse across the project.** Every Slack trigger and every outbound reply in the project uses
  that install's bot token — connected once per workspace.
- **Required scopes** (shown in the connect UI): `app_mentions:read`, `channels:history`
  (+ `groups:history` for private channels), `files:read`, `chat:write`.

### 3.2 Text-match → workflow: the per-project router (Req 2)

Keep `TriggerBinding` as the matching primitive — it already supports rich matching via
`TriggerFilter` operators (`contains`, `regex`, `starts_with`, …). The "router" is simply the
set of Slack `TriggerBinding`s in a project, each `(text pattern → workflow)`:

- Today's UI exposes only `channel` + `text contains`; **add a `regex`/`equals` option and an
  optional "command keyword"** so rules read like `text matches ^run code review` → *Code Review*.
- Matching/firing is unchanged: `dispatch → matches? → fire_for_binding`. Multiple rules can
  match; each fires its workflow (dedup ledger keeps each at-most-once).
- **Optional richer model (phase 2):** a single `app_mention` subscription plus a
  `SlackCommandRoute`-style table if per-binding management becomes unwieldy. Not required for
  the MVP — N bindings already deliver "one bot, many text→workflow rules".

### 3.3 Carry Slack context + files into the run

Two payload-forwarding gaps to close in the engine:

1. **Capture more in `normalize_slack`**: add `ts` (for threaded replies), `thread_ts`, and the
   raw `files[]` (id, name, url_private, mimetype, size) to `event.data`.
2. **Forward into the run**: extend `fire_for_binding → fire_workflow → WorkflowService.start`
   to pass `input_asset_ids:` (the ingested Slack files) and a `shared_context` slice carrying
   the Slack reply coordinates (`{ slack: { endpoint_id, channel, thread_ts, team } }`). The
   run then knows *what to read* (assets) and *where to reply* (channel + thread).

### 3.4 File ingestion (Req 4)

New `Slack::FileIngestor` invoked from `ProcessEventJob` (after normalize, before
`publish`) when `data["files"]` is present and the integration has a bot token:

```
for each file in event.files:
  GET file.url_private  with  Authorization: Bearer <bot_token>     # files:read
  stream the response body into a new Asset/AssetVersion:
    scope: project, created_by: integration.connected_by,
    name: file.name, source: :slack
  collect asset.id
→ attach the asset ids to event.data["input_asset_ids"]
```

Guards: cap count/size per message; allow a per-binding mimetype allowlist (reuse
`filter_predicate`); ingest **at receive time** (URLs are short-lived). Because ingestion
happens in the async job before dispatch, a failed download can mark the `ReceivedWebhook`
`skipped` without losing the message. The asset ids then flow via §3.3 into `input_asset_ids`.

> Idempotency: key the ingested asset on `(endpoint, slack_file_id)` so a Slack retry
> (`X-Slack-Retry-Num`) re-uses the existing asset instead of creating duplicates — same
> principle as the existing `ReceivedWebhook` dedup.

### 3.5 Replying in-channel (Req 3)

- New `Slack::Notifier` (thin `chat.postMessage` client using the project's bot token).
- **Acknowledge on start**: `fire_for_binding`, when the source is Slack and a bot token
  exists, posts a threaded "▶ Starting *<workflow>*…" using `event.data.ts` as `thread_ts`.
- **Report on finish**: hook `WorkflowService.complete` / `WorkflowService.fail` — if the run's
  `shared_context["slack"]` is present, post "✅ *<workflow>* done" / "❌ failed: <reason>" in the
  same thread, optionally with Block Kit (links to the run / produced `WorkflowRunAsset`s).
- Bot self-messages are already ignored (`bot_id` skip), so replies cannot re-trigger.
- Outbound calls go through a job and are best-effort (a Slack outage must not fail the run).

### 3.6 Agent-driven replies — a platform MCP tool `slack_post_message`

The lifecycle hooks in §3.5 give *automatic* "starting / done" messages. But the richer ask —
"the bot writes back what it did" — is best served by letting the **workflow agent itself**
post to Slack mid-run. Aixle already ships a built-in MCP server for agent containers
(`action_mcp`, mounted at `/action_mcp`, `ApplicationMCPTool < ActionMCP::Tool`), and platform
actions live as `app/services/internal_tools/*` handlers registered in
`db/seeds/platform_tools.rb` with a JSON input schema and a `Tool#kind` of `system`/`internal`.

Add a platform tool **`slack_post_message`** the same way the `board_*` tools are built:

- **Handler**: `InternalTools::SlackPostMessage < Base` → resolves the run's project Slack
  integration → `Slack::Notifier.post(channel:, text:, thread_ts:, blocks:)` with the bot token.
- **Input schema**: `text` (required); `channel` (optional — defaults to the triggering channel
  from `WorkflowRun.shared_context["slack"]` when the run was Slack-triggered); `thread_ts`
  (optional — defaults to the triggering message's thread); `blocks` (optional Block Kit).
- **Gating (the user's requirement)**: if the project has **no active Slack integration**, the
  tool returns a clear error ("Slack is not connected for this project") instead of silently
  succeeding — so it "works only if the integration exists".
- **Availability**: exposed via the built-in MCP server to any workflow step whose agent is
  granted it (same attach model as the other system tools). Works for Slack-triggered runs
  (reply in the originating thread, channel inferred) *and* for any run that names a channel.

This makes the platform tool the **primary** reply mechanism (flexible, agent-controlled), with
the §3.5 completion hook kept as a lightweight automatic safety-net for "run finished/failed".

---

## 4. Requirements → Design Traceability

| Req | Satisfied by | New pieces |
| --- | --- | --- |
| 1 — configure once / project | Existing `Integration` + `WebhookEndpoint`, reused by all triggers | Store `bot_token`; `auth.test` on connect; scope checklist in UI |
| 2 — text-match → workflow | Existing `TriggerBinding` + `TriggerFilter` (`contains`/`regex`) | UI: add regex/equals + keyword; (opt) routes table |
| 3 — reply in-channel | `chat:write` + bot token + `thread_ts` | `Slack::Notifier`; **platform MCP tool `slack_post_message`** (gated on integration, §3.6); completion-hook safety-net in `WorkflowService.complete/fail`; persist Slack coords in `shared_context` |
| 4 — files → workflow | Shrine assets + `WorkflowService.start(input_asset_ids:)` | `Slack::FileIngestor` (download w/ `files:read`); capture `files[]` in normalize; forward `input_asset_ids` through dispatch |

---

## 5. Delivery-Surface Decision

```
Requirement (4) files  ─┐
                        ├─►  needs message/app_mention events  ──►  NOT slash commands
Requirement (3) reply  ─┘                                            (need bot token regardless)

Transport:  HTTP Events API gateway   (one Request URL, one app signing secret)
Install:    OAuth v2 per workspace    ──►  bot token stored per team_id
Routing:    inbound event.team_id     ──►  install (bot token) + project
Rejected:   Socket Mode               (dev-only, no Marketplace, 1 socket/workspace)
Later:      slash command /aixle run "<name>"   (explicit, attachment-free)
```

**Chosen = HTTP Events API gateway + OAuth multi-workspace, routed by `team_id`.** It reuses the
existing inbound gateway and the entire normalize→dispatch core; the only new inbound step is
**install resolution by `team_id`** (then the shared path handles matching, files, replies).

---

## 6. Security & Idempotency

- **Inbound auth**: `slack_v0` signature on the raw body (app signing secret), 5-min replay window.
- **Multi-tenant isolation**: after verifying the signature, resolve the install by `team_id` and
  **scope everything to that install's project** — a payload from workspace A must never reach
  workspace B's bindings, bot token, or assets. The OAuth `state` must be signed + single-use so an
  install can't be bound to a project the initiator doesn't own.
- **Token storage**: per-workspace `bot_token` in `Integration#credentials_data` (encrypted, same as
  existing secrets). Never log it; never echo it to the client.
- **Least privilege**: request only `app_mentions:read`, `*:history`, `files:read`, `chat:write`.
- **At-least-once**: Slack retries on slow/failed ACK (`X-Slack-Retry-Num`). The existing
  `ReceivedWebhook` dedup + `TriggerDispatch` dedup already collapse duplicate launches; extend
  the same idea to file ingestion keyed on `slack_file_id` so retries don't duplicate assets.
- **Reply loops**: ignore `bot_id` messages (already done) so the bot's own replies never trigger.
- **Abuse/limits**: per-message file count/size caps; optional channel allowlist via the binding.

---

## 7. Implementation Plan (phased)

1. **Slack app + OAuth install** — one Aixle Slack app (app signing secret + Request URL + redirect
   URL in config/ENV); OAuth v2 connect flow with `state = signed(project)`; callback stores the
   per-workspace bot token + `team_id` on a `slack` `Integration`; `auth.test` on save; scope
   checklist in the connect UI. (Req 1 + multi-workspace)
2. **Inbound routing by `team_id`** — a Slack events endpoint that verifies with the app signing
   secret, resolves the install by `team_id`, scopes to its project, and feeds
   `Webhooks::ProcessEventJob`. Subscribe to `app_uninstalled` / `tokens_revoked` to deactivate an
   install on removal. (multi-workspace)
3. **Payload forwarding** — capture `ts`/`thread_ts`/`files[]` in `normalize_slack`; thread
   `input_asset_ids` + `shared_context["slack"]` through `fire_for_binding → fire_workflow → start`. (enabler)
4. **Replies** — `Slack::Notifier` (per-install bot token); the platform MCP tool
   `slack_post_message` (gated on the integration, §3.6) as the primary agent-driven path; a
   completion-hook safety-net in `WorkflowService.complete/fail`. (Req 3)
5. **File ingestion** — `Slack::FileIngestor` (download via `files:read` with the install's bot
   token → `Asset(source: :slack)`) with `(team_id, slack_file_id)` dedup + count/size caps; wire
   ids into `input_asset_ids`. (Req 4)
6. **Matching UX** — add regex/equals + command-keyword to the Slack trigger form. (Req 2 polish)
7. **(Optional / later)** Slash command `/aixle run "<name>"` (explicit, attachment-free); token
   rotation; Enterprise Grid org-installs.

Phases 3–6 are pure additions to the shared downstream, independent of the install/routing work
(1–2). Phase 1 is the largest new surface (OAuth + install store).

---

## 8. Open Questions / Risks

- **Multi-workspace operational constraints (the chosen path):**
  - **OAuth + distribution infra**: a public OAuth redirect URL + "Activate Public Distribution",
    HTTPS on redirect + Request URLs. More one-time app setup than pasted tokens.
  - **One shared signing secret & Request URL** for all workspaces; per-workspace differentiation is
    the **bot token keyed by `team_id`** in an install store → inbound must route by `team_id`.
  - **Install → project binding** via a signed, single-use OAuth `state`, so the new install attaches
    to the project that started it and can't be forged/replayed onto another project.
  - **Lifecycle**: handle `app_uninstalled` / `tokens_revoked` to deactivate installs (events may
    arrive out of order); replies/downloads after uninstall must fail gracefully.
  - **Token rotation**: optional; if enabled, tokens expire in 12 h and need refresh-token storage +
    refresh-before-use. Recommend off initially.
  - **Scopes are app-global**: every workspace gets the same requested scopes — cannot vary per install.
  - **Enterprise Grid**: org-wide installs add `enterprise_id` + org-level tokens — treat as a later edge case.
- **Workspace ↔ project cardinality (decided)**: a Slack app installs **once per workspace** (one
  bot token per `team_id`), so **enforce 1 workspace : 1 Aixle company**. Within the company the
  **channel filter already on each Slack `TriggerBinding`** selects the workflow/project:
  `team_id` → company, then the event's `channel` → the binding(s) that named that channel. No new
  routing model is needed — the per-binding channel filter that exists today does the
  disambiguation (a project declares which channel feeds which workflow).
- **Private channels**: requires `groups:history` and the bot to be invited — surface this in the UI.
- **Large files**: stream to Shrine; enforce a size cap; consider async ingestion timeouts.
- **`url_private` longevity**: download at ingest only; never persist the URL for deferred fetch.
- **Run→reply coupling**: completion hook must be best-effort and idempotent (a workflow can
  complete/fail more than once across retries — dedup the reply or post via `chat.update`).

---

## Sources

- Slack — Slash commands: https://api.slack.com/interactivity/slash-commands
- Slack — Using Socket Mode: https://docs.slack.dev/apis/events-api/using-socket-mode/
- Slack — Comparing HTTP & Socket Mode (dev-positioning, Marketplace ineligibility): https://docs.slack.dev/apis/events-api/comparing-http-socket-mode/
- Slack — apps.connections.open: https://docs.slack.dev/reference/methods/apps.connections.open/
- Slack — connections:write scope: https://docs.slack.dev/reference/scopes/connections.write/
- Slack — chat.postMessage: https://docs.slack.dev/reference/methods/chat.postMessage/
- Slack — chat:write scope: https://docs.slack.dev/reference/scopes/chat.write/
- Slack — Working with files: https://docs.slack.dev/messaging/working-with-files/
- Slack — File object: https://docs.slack.dev/reference/objects/file-object/
- Slack — files:read scope: https://docs.slack.dev/reference/scopes/files.read/
- Slack — Installing with OAuth: https://docs.slack.dev/authentication/installing-with-oauth/
- Slack — OAuth v2: https://api.slack.com/authentication/oauth-v2
- Slack — Token types: https://api.slack.com/authentication/token-types
- Slack — Events API (single Request URL, team_id routing): https://docs.slack.dev/apis/events-api/
- Slack — Distributing apps (public distribution, HTTPS): https://api.slack.com/start/distributing
- Slack — app_uninstalled event: https://api.slack.com/events/app_uninstalled
- Slack — tokens_revoked event: https://docs.slack.dev/reference/events/tokens_revoked/
- Slack — Using token rotation: https://docs.slack.dev/authentication/using-token-rotation/
- Aixle baseline: `ai/research/technical-event-driven-workflow-triggers-research-2026-06-22.md`; code on `feature/174-event-driven-workflows` (`slack/integration_service.rb`, `webhooks/ingress_controller.rb`, `webhooks/process_event_job.rb`, `trigger_engine.rb`, `workflow_service.rb`, `asset_version.rb`).
