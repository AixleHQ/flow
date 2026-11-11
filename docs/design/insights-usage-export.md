# Insights usage export — technical design

**Status:** Proposal.
**Date:** 2026-11-11
**Code baseline:** `30d8f1aec`
**Audience:** Engineers building the Flow side of the Aixle Insights integration; the Insights engineers who own the receiving side (§9 is their part).
**Related:** [architecture/agent-runtime-registry.md](../architecture/agent-runtime-registry.md) (the runtimes and how their usage arrives), PR #217 (`llm_calls`, open), PR #478 (an earlier attempt, closed).

## 1. Request and decisions

Aixle Insights reports AI usage per organization, project and person. Companies that run
agents in Flow want that usage in Insights too: which models ran, how many tokens, what it
cost, for whom and in which project.

Proposed decisions:

1. **Export from Flow's own usage store, not a relay of raw agent telemetry.** Flow already
   turns every runtime's telemetry into usage; the export reads that result. The OTLP relay
   (`docker/otlp-ingest`) is not involved.
2. **One canonical record: the LLM call.** `llm_calls` (PR #217) becomes the one normalized
   record that every runtime writes and every consumer reads — the session and run pages,
   cost analytics and this export. Vendor formats stop at the adapter.
3. **The record states its own quality.** Tokens may be unknown, cost may be reported by the
   vendor, priced by Flow or converted from credits, and a row may be one request or a batch.
   Fields say which; nothing pretends every runtime is equally detailed (§3).
4. **Claude Code usage moves from OTLP metrics to OTLP logs** — `api_request` events, one per
   model request, with the CLI's own cost. Flow needs this whether or not Insights is
   connected (§4).
5. **Each connection has its own credential.** Insights issues it when the connection is
   made; it writes usage into that one organization and nothing else. No Insights token per
   user, no organization-wide ingest token, no sending secret shared by every connection of
   a Flow deployment, and nothing Insights-related reaches an agent container (§5, §8).
6. **A connection is made by an Insights organization owner** through a one-time pairing
   code that only a registered Flow deployment can redeem for the connection's credential —
   never by pasting a long-lived identifier or token (§5).
7. **Usage, prompts and tool calls — never replies or outputs.** Every prompt an agent
   receives (a person's, or a workflow step's instructions) and every tool call — name,
   arguments, success, duration — is recorded and exported, so prompts can be analyzed in
   Insights. Assistant replies and tool outputs are not collected. Content is collected only
   in projects that share it, masked against the session's known secrets and size-capped
   (§3a, §8). Insights is not connected on client projects.
8. **At-least-once delivery, idempotent on the call.** A transactional outbox row per
   finished session, sent right after commit with a Temporal schedule as the safety net;
   Insights upserts on the call's id (§6).
9. **Opt-in per project, twice.** A company connects once; each project is enabled
   explicitly for usage, and prompt sharing is a second switch of its own (§5).

## 2. What exists

### Flow

| Piece | Today | Gap |
| --- | --- | --- |
| Usage collection | Each adapter (`app/services/agents/*_adapter.rb`) turns OTLP, MITM logs, a vendor usage API or the CLI's result stream into one event shape — `model`, `timestamp`, `tokenUsage{inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, totalCents}`, `source` — accumulated into `usage_statistics`, one row per terminal session, the events in `events_data`. | Per-call detail sits in a JSON array. Cost is `0` where the runtime reports none and Flow does not price it (Codex, Grok, Gemini when its log carries no cost). |
| Per-call table | PR #217: `llm_calls`, materialized from `events_data` when a session finishes, with `workflow_run_id` and `step_run_id`. | Not merged. It also carries a raw OTLP forwarder that this design drops (§11). |
| OTLP relay | `docker/otlp-ingest` (Go): OTLP protobuf or JSON in, JSON out to `POST /api/v1/internal/usage_statistics`. A batch proves its session with `terminal_session_key` (`UsageStatistics::SessionKey`). | Unchanged. |
| Claude Code telemetry | Metrics only (`OTEL_METRICS_EXPORTER=otlp`, two-second deltas). | No per-request rows, no API errors or retries. |
| Integrations | `Integration`: company, optional project, encrypted `credentials`. | No `insights` provider. |
| Periodic work | `app/temporal/schedules.yml`. | — |

### Insights

Capabilities on its current development line, as the receiving side sees them:

| Capability | State |
| --- | --- |
| OTLP/HTTP JSON log ingest, with a per-tool record builder chosen by `service.name` | Exists |
| A usage event upserted on an id it carries, so a re-send updates instead of duplicating | Exists |
| Server-side pricing when an event carries tokens but no cost | Exists |
| A person matched to an organization member by email; a project matched by a linked repository's remote | Exists (the email match runs as a periodic job) |
| An event type for one model request (`api_request`) | Exists |
| Registered Flow deployments; connections bound to one organization, each with its own write credential; a pairing flow; a builder for Flow's records | Missing — §9 |

## 3. The canonical record: `llm_calls`

PR #217's table, with the changes below made before it merges. Agent type, user, project and
company come from the session; they are not copied onto the row.

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | bigint | |
| `uid` | uuid, not null, random (new) | The call's id outside Flow and the export's idempotency key (§6). Random, so unique across Flow deployments and across re-pairings. |
| `terminal_session_id` | bigint, not null | |
| `event_index` | integer, not null (new) | The event's position in the session's `events_data`; unique with `terminal_session_id`, so materializing again only adds the rows that are missing. |
| `workflow_run_id`, `step_run_id` | bigint, null | Set for workflow step sessions. |
| `occurred_at` | datetime, not null | The request's time; for a batch, the end of the batch. |
| `model` | string, not null | Canonical model id: provider prefixes and Bedrock region prefixes removed by one shared normalizer. |
| `provider` | string, not null (new) | Who bills the call: `anthropic`, `aws_bedrock`, `openai`, `google`, `xai`, `cursor`, `kiro`, `github_copilot` — from the runtime, and for Claude Code from the model id (a Bedrock inference profile). |
| `input_tokens` | integer, **null** (was not null, default 0) | Uncached input. `null` = the runtime does not report it; `0` = reported as zero. |
| `output_tokens`, `cache_read_tokens`, `cache_write_tokens` | integer, **null** (same change) | |
| `total_cents_precise` | decimal(12,8), **null** (same change) | `null` = unknown, never `0` for unknown. |
| `cost_basis` | string, not null (new) | `reported` (vendor or CLI), `priced` (an estimate from list prices — Flow's price table, or Grok's xAI catalogue), `credits` (Kiro or Copilot credits × the configured rate), `unknown`. |
| `granularity` | string, not null (new) | `request`, `turn`, `batch`, `session`. |
| `source` | string, not null | One vocabulary: `otlp_log`, `otlp_metric`, `otlp_span`, `otlp_credits`, `mitm`, `vendor_api`, `cli_result`. |
| `duration_ms` | integer, null (new) | When the runtime reports it. |

What each runtime yields (confirmed in phase 0; `BaseAdapter#llm_call_traits` maps each
adapter's own event tags onto this vocabulary):

| Runtime | Source | Granularity | Tokens | Cost basis |
| --- | --- | --- | --- | --- |
| Claude Code | OTLP metrics (two-second deltas); `api_request` logs after §4 | batch; request after §4 | yes | reported |
| Codex | OTLP logs (`response.completed`); MITM fallback | request; session for the fallback's metric totals | yes | priced |
| Gemini CLI | OTLP logs | request | yes | reported when the log has it, else priced |
| Kiro CLI | OTLP credit metrics; MITM or the credit counter as fallback | turn; request, turn or session for the fallbacks | no | credits |
| Cursor CLI | Cursor usage API, matched to MITM windows | request | yes | reported |
| Grok | MITM | request | yes | priced, from the xAI catalogue |
| Antigravity CLI | stream-json result | turn | yes | priced |
| Copilot CLI | OTLP `chat` spans | request | yes | credits; unknown when the span carries none |

OpenAI, Gemini, xAI and Antigravity count cached input inside the input count; their
adapters subtract it, so `input_tokens` is uncached input everywhere.

Rows are materialized whenever a session ends — including the cleanup activity's direct
state write, which runs no state-machine callback — and again by `llm_calls:backfill`.
Events written before adapters stamped `costBasis` are read by their old conventions: a
zero cost is unknown, and cached input is subtracted where it used to be included.

Rules that keep it uniform:

- **One price table, for estimates only.** Only Claude Code and Cursor report a cost; Kiro
  and Copilot report credits; Codex, Gemini CLI, Grok and Antigravity report tokens alone.
  For those, `LlmCalls::Pricing` estimates a cost from `config/llm_prices.yml` — the
  vendors' public list prices at the standard tier, with long-context rates and dated
  changes. That is not what an account was billed (subscriptions, discounts, batch and
  priority tiers differ), which is why such a call says `priced`, never `reported`.
  Antigravity's in-adapter table moved into it; Grok feeds it from the model catalogue it
  already reads; Codex and Gemini use it. A call with no price for its model stays
  `cost_basis: unknown` with a null cost — it is never written as free.
- **The table is kept current by a weekly check.** `bin/llm-prices-report` compares it with
  LiteLLM's public price list; `.github/workflows/llm-prices.yml` keeps one issue open while
  a rate differs or the last review (`reviewed_on`) is over 90 days old. A difference is a
  prompt to read the vendor's page, which stays the source. The fallback model catalogues
  of Codex, Gemini CLI and Antigravity must all be priced (a unit test), and a model with
  no price is logged once per process.
- **One model normalizer.** `LlmCalls::ModelName` removes routing and Bedrock prefixes, for
  the stored model and the price lookup alike.
- **Rows are immutable once the session is finished.** Re-materialization (the backfill task)
  only adds missing rows, keyed by `(terminal_session_id, event_index)`, so an id never
  changes after it may have been exported.
- **The contract test covers the record.** `test/services/agents/otlp_contract_test.rb`
  already parses each captured CLI fixture with the real adapter; it gains the expected
  `llm_calls` rows, so a vendor's format change breaks CI rather than numbers downstream.

## 3a. Agent activity: prompts and tool calls

Two more canonical records, exported beside the calls. Adapters write them as the runtime's
telemetry arrives (`AgentActivity::Recorder`), keyed by the runtime's own id for the prompt
or the tool call, so a batch delivered twice is written once and a row never changes. They
exist only for sessions of projects with prompt sharing on.

`agent_prompts`, one per prompt an agent received:

| Column | Type | Meaning |
| --- | --- | --- |
| `uid` | uuid, not null | Id outside Flow; the export's idempotency key. |
| `terminal_session_id`, `workflow_run_id`, `step_run_id` | bigint | As on `llm_calls`. |
| `source_key` | string, not null | The runtime's id for the prompt (`prompt:<prompt.id>`), or `initial_prompt`; unique with the session. |
| `occurred_at` | datetime, not null | |
| `text` | text, not null | Masked (§8), at most 64 KB. |
| `text_length`, `truncated` | integer, boolean | The length before masking and the cap; whether the cap cut it. |
| `prompt_ref` | string, null | The runtime's own prompt id (Claude Code's `prompt.id`), which joins a prompt to the calls and tool calls it led to; `llm_calls.prompt_ref` carries it too. |
| `source` | string, not null | `otlp_log` or `transcript` (the runtime reported it), `flow` (the session's initial prompt as Flow rendered it — a workflow step's instructions — for a runtime that reports no prompts). |

`agent_tool_calls`, one per tool call:

| Column | Type | Meaning |
| --- | --- | --- |
| `uid`, `terminal_session_id`, `workflow_run_id`, `step_run_id`, `occurred_at`, `prompt_ref`, `source` | | As above. |
| `source_key` | string, not null | The runtime's id for the call (`tool:<tool_use_id>`); unique with the session. |
| `tool_name` | string, not null | As the runtime names it: `Bash`, `Edit`, `mcp__github__create_issue`. |
| `mcp_server` | string, null | For a tool an MCP server provides. |
| `arguments` | jsonb, null | Masked; each string at most 8 KB, the whole at most 32 KB. |
| `success` | boolean, null | |
| `error` | string, null | The first 500 characters of an error. |
| `duration_ms` | integer, null | |

Where it comes from (to confirm per runtime when its fixture is captured):

| Runtime | Prompts | Tool calls | Set in the container, only when sharing is on |
| --- | --- | --- | --- |
| Claude Code | OTLP log `user_prompt` (confirmed, 2.1.318) | OTLP log `tool_result`: name, `tool_use_id`, input, success, duration — the output only as a size (confirmed) | `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_TOOL_DETAILS=1` |
| Codex | OTLP log `codex.user_prompt` (confirmed, 0.166.0); no prompt id, so keyed by conversation and time and not joined to calls | OTLP log `codex.tool_result`: name, `call_id`, arguments, success, duration; its `output` dropped (confirmed) | `[otel] log_user_prompt = true` |
| Gemini CLI | OTLP log `gemini_cli.user_prompt` with `prompt_id`, which `api_response` carries too (confirmed, 0.60.0) | OTLP log `gemini_cli.tool_call`: name, arguments, success, duration, `prompt_id`; no call id, so keyed by prompt and time (confirmed) | `telemetry.logPrompts: true` |
| Copilot CLI | `user.message` in the transcript `events.jsonl` Flow already collects, read at cleanup (confirmed, 1.0.108) | `tool.execution_start` / `_complete` in the same transcript, the result dropped; `assistant.message` ties a call to its prompt (confirmed) | — |
| Kiro, Cursor, Grok, Antigravity | the session's initial prompt — a workflow step's instructions — recorded by Flow | — | — |

Rules:

- **Nothing is collected where nothing is shared.** The container switches above are set
  only for sessions of projects with prompt sharing on, so elsewhere no prompt reaches Flow
  beyond what it already keeps in session logs.
- **Replies and tool outputs are dropped in the adapter**, never stored. They still travel
  through `otlp-ingest` where a runtime sends them: Claude Code logs an `assistant_response`
  record with the reply once prompts are on, Codex puts a tool's output in its
  `tool_result`. The relay may strip them later if that traffic matters.
- **Masked before it is stored**, with `Sessions::SecretRedactor` and the session's known
  secrets — the values it was handed through config items.

## 4. Claude Code: logs instead of metrics

- The container gets `OTEL_LOGS_EXPORTER=otlp` with the existing endpoint and protocol, and a
  short `OTEL_LOGS_EXPORT_INTERVAL` (2 s, as metrics today) so usage lands before the
  container stops. `OTEL_LOG_USER_PROMPTS` and `OTEL_LOG_TOOL_DETAILS` are set only for a
  project with prompt sharing on (§3a); the same records then also carry `user_prompt` and
  `tool_result` events.
- `Agents::ClaudeCodeAdapter` reads `api_request` log records — `model`, `input_tokens`,
  `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `cost_usd`, `duration_ms` —
  one usage event per record, `source: otlp_log`, `granularity: request`. The Codex adapter's
  log path is the precedent.
- **Metrics stop counting.** Counting both doubles the usage, and exporting both from every
  container in production would double Claude Code's telemetry traffic. New containers
  export logs only. The two are compared offline instead: the fixture is captured with both
  exporters on, and the contract test asserts the log-derived totals equal the metric-derived
  ones. The metric parser stays one release for containers started before the deploy — each
  container sends one or the other, never both — and is removed after.
- The session-key check is unchanged: logs carry the same resource attributes.
- `bin/capture-agent-otlp claude_code` re-captures the fixture with logs.

`api_error` and `api_retries_exhausted` arrive on the same path; recording them (for the
session page, not for this export) is a separate change.

## 5. Connection model

### Principals

- **Deployment** — one Flow deployment: the hosted Flow is one, each self-hosted Flow is
  another. Insights registers it and issues an id and a secret, which Flow reads from
  deployment configuration — `INSIGHTS_URL`, `INSIGHTS_DEPLOYMENT_ID`,
  `INSIGHTS_DEPLOYMENT_SECRET` — hiding the integration while they are unset. The deployment
  secret is accepted **only** by the claim endpoint and only together with an owner's code:
  it sends no usage and reaches no organization by itself. It is never stored in the
  database, shown in the UI or written to a log. Insights keeps two active during its
  rotation and can disable a deployment outright.
- **Connection** — one Insights organization × one Flow company of one deployment. On the
  Flow side it is `Integration(provider: "insights", company:, project: nil)`; its encrypted
  `credentials` hold the connection's id and secret, and it shows the organization's name.
  The connection secret is issued once, at pairing, and Insights keeps only its hash. It
  authorizes writing usage into that one organization and listing that organization's
  projects — nothing else.

Neither credential is enough alone: a stolen pairing code is useless without a registered
deployment's secret, a leaked deployment secret is useless without an owner's code, and a
leaked connection secret reaches one organization.

### Pairing

1. An owner of the Insights organization chooses *Connect Aixle Flow* and gets a one-time
   code: single use, valid for 15 minutes, bound to the organization.
2. A Flow company admin opens Integrations → Insights and enters the code.
3. Flow's server redeems it: `POST {INSIGHTS_URL}/partner/v1/connections/claim`,
   authenticated with the deployment credential, with `{ code, company: { id, name } }`, and
   receives `{ connection_id, secret, organization: { id, name } }`. Insights refuses a claim
   that lacks either the code or a registered deployment's credential.
4. Flow stores the connection; Insights shows it, with the Flow company and the deployment,
   in the organization's integrations.

If the same deployment and Flow company already have a connection to that organization, the
claim replaces it in the same transaction: the earlier secret is revoked as the new one is
issued. This is the recovery path when a connection secret is lost or revoked.

A code rather than a pasted token: a token a person copies between two screens ends up in
chats, tickets and screenshots, and lives until somebody rotates it. A code is short-lived,
single use and worthless once redeemed; the secret it yields travels only between the two
servers.

### Rotation and revocation

- **Rotation** — `POST /partner/v1/connection/rotate`, authenticated with the current secret,
  returns a new one. In the same transaction Insights sets the old secret to expire after a
  grace period of one hour; nothing depends on a second call. If the response is lost, Flow
  still holds the old secret and rotates again, and the secret it never received is
  invalidated by that rotation. Flow rotates on demand from the integration page.
- **Revocation** — the organization's owner revokes in Insights. A Flow admin who disconnects
  makes Flow call `DELETE /partner/v1/connection`; Flow keeps the secret and retries until
  Insights confirms, and only then erases it, so a failed call cannot leave a live secret
  that nobody tracks. Revoking one connection leaves every other untouched.

### Projects

- A project is exported only after a project owner or company admin enables it.
- **Prompt sharing** is a second switch on an enabled project, off by default. Its help text
  says that prompts and tool arguments leave Flow for Insights, and that only the session's
  known secrets are masked.
- The project can be mapped to one Insights project, picked from
  `GET /partner/v1/connection/projects` (active projects only). Without a mapping, Flow
  sends the remote of the project's repository when it has exactly one, and Insights matches
  it to a linked repository; otherwise the project is left for Insights to assign.

### People

- The person is the session's `user`. For a workflow step that is `workflow_run.user` — whose
  agent credential the step runs on (`SessionService`) — so the usage lands on the person
  whose seat or key paid for it.
- Flow sends the user's email. Insights accepts it only when it belongs to a member of the
  connected organization; anything else is stored unattributed.

## 6. Export pipeline

### Outbox

`insights_session_exports`, one row per exported session:

| Column | |
| --- | --- |
| `terminal_session_id` | unique |
| `integration_id` | the company connection |
| `state` | `pending`, `delivered`, `rejected`, `failed`, `skipped` |
| `attempts`, `next_attempt_at`, `last_error` | `last_error` names the chunk (`chunk 3/5: 503 …`) |
| `record_count` | records in the whole session — calls, prompts, tool calls — across chunks |
| `rejected_count`, `delivered_at` | |

The row is written in the transaction that materializes the session's `llm_calls`, and only
when the project is enabled and the connection active. After commit the send is enqueued at
once; `insights_export_workflow` in `app/temporal/schedules.yml` (every five minutes,
`overlap: skip`) sends whatever is due — the shape `TriggerEngine`'s outbox and
`OutboxRelay` already use: dispatch inline, sweep on a cron.

### Sending

- **A session is the unit of delivery.** Its records go in chunks of at most 1,000, one
  request each, every chunk carrying the same session context (person, project,
  repository), so nothing on the receiving side has to join requests.
- **Late rows are sent too.** Telemetry can land after a session ended; when the
  materializer adds rows to a session already delivered, its outbox row goes back to
  `pending` and the session is sent again — upserts make the repeat harmless.
- **`delivered` only when every chunk was accepted in full.** A failed attempt re-sends every
  chunk; upserts make that safe, and it keeps the outbox free of per-chunk progress.
- gzip, 10-second timeout.

| Response (per chunk) | Effect |
| --- | --- |
| 2xx, no `partialSuccess` or `rejectedLogRecords` of `0` | Chunk accepted. An `errorMessage` without rejections is a warning: logged, nothing more. |
| 2xx, `partialSuccess.rejectedLogRecords` > 0 | The chunk's other records are stored. The remaining chunks are still sent; the row ends `rejected` with the summed count and the message, reported to Sentry and shown on the integration. Not retried automatically — the OTLP specification forbids retrying a partial success, and the same records would be rejected again; re-sent by hand once the cause is fixed. The count is an int64, which proto JSON writes as a string. |
| 401 / 403 | The connection's secret is revoked or rejected: this integration's sends stop and it asks for a new code; its pending rows wait, are sent after a re-pair and `skipped` if the integration is removed. Other connections are unaffected. |
| 413 / 422 | The chunk is refused whole: `rejected` as above, counting all its records. |
| 429 | `next_attempt_at` from `Retry-After`. |
| 5xx, network | Exponential backoff from one minute to six hours; `failed` after seven days. |

Re-sending a session is safe: each call carries its `uid`, and Insights upserts on
`(organization, uid)`.

## 7. Payload

`POST {INSIGHTS_URL}/partner/v1/aixle_flow/logs` — an OTLP/HTTP JSON
`ExportLogsServiceRequest`, one `ResourceLogs` per request.

Headers: `Authorization: Bearer <connection secret>`, `Content-Encoding: gzip`. The secret
identifies the connection, and through it the organization; no other identifier is sent.

Resource attributes (the session):

| Key | Value |
| --- | --- |
| `service.name` | `aixle-flow` |
| `service.version` | Flow's version |
| `aixle_flow.company.id` | |
| `aixle_flow.project.id`, `aixle_flow.project.name` | |
| `aixle_flow.session.id`, `aixle_flow.session.type` | terminal session id; `workflow_step`, `agent_session`, … |
| `aixle_flow.workflow_run.id` | workflow step sessions |
| `aixle_flow.agent.type` | `claude_code`, `codex`, `gemini_cli`, `kiro_cli`, `cursor_cli`, `grok`, `antigravity_cli` |
| `user.email` | the session user's email |
| `insights.project.id` | the mapped project, when set |
| `vcs.repository.url.full` | when the project has exactly one repository and no mapping |

Log record (one per `llm_calls` row): `timeUnixNano` = `occurred_at`, no body, and

| Attribute | Value |
| --- | --- |
| `event.name` | `aixle_flow.llm_call` |
| `aixle_flow.llm_call.id` | the row's `uid` |
| `aixle_flow.step_run.id` | when set |
| `gen_ai.provider.name` | `provider` |
| `gen_ai.request.model` | `model` |
| `aixle_flow.usage.input_tokens` | uncached input; omitted when unknown |
| `aixle_flow.usage.output_tokens`, `aixle_flow.usage.cache_read_tokens`, `aixle_flow.usage.cache_write_tokens` | omitted when unknown |
| `aixle_flow.cost.usd` | omitted when unknown |
| `aixle_flow.cost.basis`, `aixle_flow.granularity`, `aixle_flow.source` | §3 |
| `aixle_flow.duration_ms` | when known |
| `aixle_flow.credential.kind` | `subscription`, `api_key` or `cloud`, when known |

Token counts use Flow's own names rather than `gen_ai.usage.*`: whether the semantic
convention's input count includes cached tokens differs between producers, and the receiver
must not have to guess. Provider and model use the convention.

Two more record kinds, from projects with prompt sharing on (§3a), carry the same resource
attributes:

| `event.name` | Body | Attributes |
| --- | --- | --- |
| `aixle_flow.prompt` | the prompt text | `aixle_flow.prompt.id` (`uid`), `aixle_flow.prompt.origin`, `aixle_flow.prompt.length`, `aixle_flow.prompt.truncated`, `aixle_flow.prompt.ref`, `aixle_flow.step_run.id` |
| `aixle_flow.tool_call` | none | `aixle_flow.tool_call.id` (`uid`), `gen_ai.tool.name`, `aixle_flow.tool.mcp_server`, `aixle_flow.tool.arguments` (a JSON string), `aixle_flow.tool.success`, `aixle_flow.tool.error`, `aixle_flow.duration_ms`, `aixle_flow.prompt.ref`, `aixle_flow.step_run.id` |

Never sent: assistant replies, tool outputs, and any repository or file content beyond what a
prompt or a tool's arguments carry.

## 8. Security and privacy

- **Agent containers are untouched.** No Insights URL, id or secret reaches their
  environment; the export reads the database. A relay would have to trust attributes the
  agent itself controls (§11).
- **The connection secret** is stored encrypted in the integration's `credentials`, read
  only by the sender, and never shown in the UI or written to a log.
- **Scope.** A connection secret writes usage into one organization — the one whose owner
  issued the code — and reads nothing beyond that organization's project list. It cannot
  create connections.
- **The deployment secret** only redeems codes. Leaked, it creates nothing without an
  owner's code; Insights rotates it or disables the deployment, and existing connections
  keep working.
- **If a secret leaks,** its holder can write usage into that one organization — not read
  it, not reach any other. The owner or Flow's admin revokes the connection and pairs again;
  other connections are untouched. Flow's records are marked as Flow's on the Insights side,
  so they cannot pass as a developer's own tool telemetry.
- **What it does not protect against.** Whoever controls Flow's server and its encryption
  key can read every connection's secret, as with every integration credential Flow already
  stores (GitHub, Slack, trackers). Per-connection secrets limit what one leaked value can do
  — a log line, an environment dump, a support ticket — not a compromise of the server.
- **Personal data.** The user's email and usage leave Flow. The project switch's help text
  says so.
- **Prompts and tool arguments** leave Flow only for projects with prompt sharing on. They
  can hold code, customer data and credentials Flow never handed out — a token read from a
  file, pasted into a prompt, passed to `curl` — which masking cannot catch: it knows only
  the session's own secrets. That is why sharing is its own switch and why Insights is not
  connected on client projects. Insights holds them as sensitive content (§9).

## 9. What Insights builds

1. **Registered Flow deployments.** An id and a secret per deployment, accepted only by the
   claim; two active secrets during rotation; disable switch. Registration for self-hosted
   Flow (§12).
2. **Connections with their own credential.** A connection binds one organization to one
   Flow company of one deployment. It is made by redeeming an owner-issued one-time code
   with the deployment's credential (`POST /partner/v1/connections/claim`), which returns the
   connection's secret once and atomically replaces an earlier connection of the same
   deployment, company and organization. Insights stores only the secret's hash; the secret
   carries a recognizable prefix (`aixle_flow_…`) so secret scanners catch a leaked one.
   Rotation with a one-hour grace period (§5). Listed and revocable in the organization's
   integrations, with last-seen.
3. **Partner endpoints**, authenticated by the connection secret alone and scoped to its
   organization: `POST /partner/v1/aixle_flow/logs` (§7), which reports refused records in
   OTLP `partialSuccess`; `GET /partner/v1/connection/projects`;
   `POST /partner/v1/connection/rotate`; `DELETE /partner/v1/connection`.
4. **A builder for Flow records**, chosen by `service.name: aixle-flow`: one usage event per
   record, the event's tool taken from `aixle_flow.agent.type`, a provenance marker saying
   the event came from Aixle Flow, cost from `aixle_flow.cost.usd` when present and the
   existing server-side pricing when not, and the upsert key `aixle_flow:<uid>` within the
   organization. A generic OTLP builder is not enough: it would record no cost, no tool and
   no Flow identifiers.
5. **Tool names** for runtimes Insights does not list yet (Grok, Antigravity), or a mapping
   onto existing ones.
6. **Attribution at ingest, per request.** Resolve `user.email` to a member and the project
   (`insights.project.id`, else `vcs.repository.url.full`) when the request arrives, rather
   than leaving the record unattributed until a periodic job.
7. **Reconciliation with provider-synced usage.** When an organization also syncs usage from
   a provider account whose key a Flow agent used, the same calls arrive twice. Insights
   decides which source wins; `aixle_flow.credential.kind` is there to help.
8. **Prompts and tool calls.** Accept `aixle_flow.prompt` and `aixle_flow.tool_call`
   records (the contract accepts `aixle_flow.llm_call` only), upserted on their ids like
   calls; store them as sensitive content — who in the organization may read them, how long
   they are kept, and their deletion when a connection is revoked (§12).
9. **Limits.** How Flow's traffic counts against an organization's ingest quota, and a
   per-connection rate limit.

Of the stronger credentials proposed on the Insights side, request signing fits behind
item 3 unchanged, keyed by the connection secret. Mutual TLS fits less well: one client
certificate per Flow deployment is again a credential that reaches every connected
organization.

## 10. Flow work, in phases

| Phase | Work |
| --- | --- |
| 0 — canonical record | Land PR #217 without its OTLP forwarder or the extra resource attribute; the §3 column changes; one pricing service and model normalizer; immutable rows; contract test rows. |
| 1 — Claude Code logs | §4. |
| 2 — agent activity | §3a: `agent_prompts` and `agent_tool_calls`, the activity events of Claude Code, Codex, Gemini CLI and Copilot CLI, step instructions, the container switches, masking, the prompt-sharing project setting. |
| 3 — connection | `Integration` provider `insights`, the pairing screen, the project switches and mapping, deployment settings (`INSIGHTS_URL`, deployment id and secret). |
| 4 — export | `insights_session_exports`, the sender, `insights_export_workflow`, delivery state on the integration page. |
| 5 — backfill | Optional export of a project's past sessions when it is enabled (§12). |

Phases 0 and 1 stand on their own: they fix cost and per-call detail in Flow itself.

## 11. Alternatives considered

- **Relay raw agent OTLP through `otlp-ingest`** (PR #478's final form, and the forwarder in
  PR #217). Only runtimes that emit OTLP logs would be covered; delivery is best-effort with
  nothing stored to retry; Insights maintains one parser per vendor format; raw logs can
  carry content. And whatever names the target organization or person sits in the container's
  environment, which the agent controls — the relay would have to verify a signed binding,
  or one company's agent could write into another's organization.
- **An organization ingest token held by Flow** (PR #478). One organization-wide write
  credential per company, used for every user, with the person named by a header: whoever
  holds it writes as anyone in the organization.
- **One sending secret per Flow deployment, connections named by id** (this document's
  first draft). The secret never leaves Flow's server, but it writes into every
  organization connected to that deployment — for the hosted Flow, every customer's. A
  secret per connection costs Flow nothing more than the encrypted `credentials` it already
  has, and a leaked value exposes one organization. The deployment secret that remains only
  redeems codes.
- **A token per user** (each person links their Insights account). Identity is proven, but
  every person has to link, and usage of those who do not is lost. Can be added later for
  people who want it.
- **Plain JSON instead of OTLP.** Equally workable; OTLP reuses Insights' existing parsing.
  Insights may choose.
- **Usage only** (this document's first draft). The safest export, but prompt analysis is a
  goal of the integration.
- **Full transcripts** — replies and tool outputs as well. The largest and most sensitive
  content (file contents, command output), and complete only where a runtime keeps a
  transcript (Claude Code, Copilot CLI).

## 12. Open questions

1. Long-running interactive sessions export only when they finish. Materialize and export
   them incrementally instead?
2. Usage of workflow runs lands on the person whose credential ran them. Should Insights
   show it apart from that person's own interactive use?
3. Backfill when a project is enabled: none, or a window (30 days)?
4. Is an explicit project mapping required, or is the repository remote enough by default?
5. Kiro reports credits, never tokens. Are cost-only rows acceptable in Insights?
6. Which side owns reconciliation with provider-synced usage (§9, item 7)?
7. How a self-hosted Flow registers its deployment with Insights: self-serve in Insights,
   or on request. Until it does, it cannot connect.
8. A person deleted in Flow: does anything propagate, or do Insights' retention rules govern?
9. How long Flow keeps `agent_prompts` and `agent_tool_calls` — as long as session logs, or
   only until they are delivered?
10. Who in an Insights organization may read prompts: every member, or owners only?
