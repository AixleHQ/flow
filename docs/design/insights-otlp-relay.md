# Aixle Insights: relaying agent telemetry

Status: implemented (the relay); the receiving side is Aixle Insights' to build (§7).

Aixle Insights reports AI usage per organization, project and person. Companies that run
agents in Flow want those agents in Insights too. Flow already receives each agent's
OpenTelemetry through `docker/otlp-ingest`; this design forwards that stream — as the agent
wrote it — to the company's Insights organization, with Flow's knowledge of who ran it and
where attached.

## 1. Decisions

1. **The agents' own OTLP, not a Flow-made record.** Insights receives the logs, metrics and
   traces each CLI emits, unchanged except for §4. Insights parses each vendor's format; a new
   runtime in Flow is a new format for Insights.
2. **Flow names the person, the project and the session.** The container sets its own
   resource attributes and the agent controls its environment, so identity is never taken
   from there. Flow attaches it after the batch has proven its session (§4).
3. **Everything the agents report is forwarded,** prompts, replies, tool arguments and tool
   output included. Only the session's own secrets — the `secret` config items it was handed —
   are masked. A project is forwarded only when its export switch is on.
4. **Each connection has its own credential,** issued by Insights when an owner's one-time
   pairing code is redeemed (§3). A deployment credential exists only to redeem codes.
5. **At-least-once, through an outbox.** The ingest writes; a sender on a one-minute cron
   delivers, retries and gives up after a week (§5). There is no history to replay: a project
   switched on starts with the activity that follows.

## 2. The path of one batch

```
agent CLI ──OTLP──▶ otlp-ingest (Go) ──JSON──▶ POST /api/v1/internal/usage_statistics
                                                   │  UsageStatisticsService proves each
                                                   │  resource's session (token + key)
                                                   ├─▶ Flow's own usage (unchanged)
                                                   └─▶ Insights::Relay.capture
                                                         project exported? ─ no ─▶ nothing
                                                         │ yes
                                                         ▼
                                                   Insights::OtlpEnvelope (§4)
                                                         ▼
                                                   insights_otlp_batches (gzip, pending)
                                                         ▼  insights_relay_workflow, every minute
                                                   Insights::Relay.drain ──▶ Insights
                                                         POST {INSIGHTS_URL}/partner/v1/otlp/v1/{logs|metrics|traces}
```

The capture never fails the ingest: Flow records its own usage either way, and an error in
the relay is reported and dropped.

## 3. Connection and project switch

- **Pairing.** An Insights owner creates a one-time code (eight characters, fifteen minutes).
  A company admin enters it on any project's Integrations page; Flow redeems it with the
  deployment's id and secret (`INSIGHTS_URL`, `INSIGHTS_DEPLOYMENT_ID`,
  `INSIGHTS_DEPLOYMENT_SECRET`) and receives the connection's own secret, stored encrypted
  in the integration's credentials. One connection per company (`Integration`, provider
  `insights`, no project).
- **Rotate** swaps the secret in one call; **disconnect** revokes it at Insights first and
  forgets it only then. A 401 or 403 on any call marks the integration `error`; the card asks
  for a new code and pending batches wait for it.
- **Per project:** an export switch, and optionally the Insights project to attribute to
  (`projects.settings["insights"]`). Without a mapping Insights matches by repository.

## 4. What Flow changes in a batch

`Insights::OtlpEnvelope` splits a request by the session each resource proves it belongs to —
the same token-and-key check as the usage ingest, on the resource's attributes or, when the
resource has none, on its records' (Kiro and others put them on data points). A resource that
proves no session is dropped. Then, per resource:

| Change | Why |
| --- | --- |
| `terminal_session_token` and `terminal_session_key` removed at every depth | The key proves a batch to Flow; outside Flow it is a credential for that session's usage. |
| Session's `secret` config items masked in every string (`Sessions::SecretRedactor`) | The one set of values Flow knows are secret. A token typed into a prompt or read from a file is not known, and is sent as it is. |
| Resource attributes `user.email`, `insights.project.id`, `vcs.repository.url.full` and `aixle_flow.*` replaced with Flow's | Identity comes from Flow's records, never the container. |
| `aixle_flow.record.id` added to each log record | A hash of the record's content: a re-send (Flow's, or the agent SDK's own retry) carries the same id, so Insights can drop the duplicate. Spans already carry `traceId` + `spanId`; metric points are keyed by series and time. |

The resource attributes Flow sets (`Insights::Metadata`), each left out when unknown:

| Attribute | Value |
| --- | --- |
| `aixle_flow.version` | Flow's version |
| `aixle_flow.company.id` | the session's company |
| `aixle_flow.project.id`, `aixle_flow.project.name` | the session's project |
| `aixle_flow.session.id`, `aixle_flow.session.type` | the terminal session |
| `aixle_flow.workflow_run.id`, `aixle_flow.step_run.id` | for a workflow step's session |
| `aixle_flow.agent.type` | Flow's runtime id (`claude_code`, `kiro_cli`, …) |
| `user.email` | the person the session ran for |
| `insights.project.id` | the project's mapping, when set |
| `vcs.repository.url.full` | the session's repository when it has exactly one, else the project's; userinfo removed |

Everything else — `service.name`, the scope, every record and its attributes — is the agent's.
Record-level identity an agent writes (Claude Code's `user.email` is the account its
credential belongs to, which in Flow may be a company's shared login) is left as written;
Insights must attribute by the resource's `user.email`.

## 5. Delivery

`insights_otlp_batches` holds one row per captured request: connection, project, session,
signal, gzipped payload, record count, state, attempts, next attempt, lease, last error.

`Insights::Relay.drain` runs every minute (`insights_relay_workflow`, overlap skip). Per
active connection it claims up to 500 due rows with a ten-minute lease and sends them per
signal, merged into requests of at most 1 000 records and 4 MB gzipped:

| Insights answers | Flow |
| --- | --- |
| 2xx, nothing rejected | deletes the rows |
| 2xx with `partialSuccess` rejections | marks the rows `failed` with Insights' message; never retried |
| 401 / 403 | marks the integration `error`; rows wait for a new code |
| 413 | splits the request in half; a single row too large is `failed` |
| 400 / 422 | marks the rows `failed` |
| 429 | holds the rows until `Retry-After` (else one minute); stops this connection's drain |
| anything else, or unreachable | backs off 1 min, doubling to 6 h; rows older than 7 days turn `failed` |

`failed` rows are deleted seven days after they failed. Disconnecting deletes the
connection's rows with it. The project's card shows how many batches wait, since when, how
many were not accepted, and the last error.

## 6. What the agents send

The relay forwards whatever each runtime emits to `otlp-ingest`; it neither adds nor
filters records. What each runtime emits, and the switches its adapter sets, belong to the
runtime adapters. Insights should expect the formats of every runtime in
`config/agent_runtimes.json`.

## 7. What Insights has to provide

- `POST /partner/v1/connections/claim` (deployment Basic auth), `GET /partner/v1/connection/projects`,
  `POST /partner/v1/connection/rotate`, `DELETE /partner/v1/connection` (connection Bearer).
- `POST /partner/v1/otlp/v1/{logs,metrics,traces}`: OTLP/HTTP JSON, gzip, connection Bearer;
  `partialSuccess` per the OTLP spec; 413 above its size limit; 429 with `Retry-After`.
- Persisting all three signals, attributed by the resource's `user.email`, `insights.project.id`
  or `vcs.repository.url.full` — not by record-level identity.
- Dropping a log record whose `aixle_flow.record.id` it already holds, a span whose ids it
  holds, a metric point it holds.
- Parsing every runtime Flow runs (`config/agent_runtimes.json`), each in its vendor's format.

## 8. Security and privacy

- **Content.** A switched-on project sends prompts, model replies, tool arguments and tool
  output. Only the session's known secrets are masked. The switch's description says so;
  projects run for clients should stay off.
- **The session key never leaves Flow,** and nothing in the agent container changes: no
  Insights URL, id or secret reaches it.
- **The connection secret** is stored encrypted, read only by the sender, never shown or
  logged. It writes into one organization.
- **The outbox** holds masked payloads for at most a minute in the normal case, a week while
  Insights is down, and a week after a refusal.

## 9. Alternatives considered

- **A Flow-made record per model call, prompt and tool call** (this design's first form):
  a normalized, priced record from every runtime, exported per session. Rejected in favour of
  the raw stream: Insights wanted the vendors' own telemetry, and real time over per-session
  delivery.
- **Relaying from `otlp-ingest` directly.** It forwards without storing, so every Insights
  outage loses data, and it cannot tell which company's connection a batch belongs to
  without the session lookup the Rails ingest already does.
- **An organization ingest token held by Flow:** whoever holds it writes as anyone in the
  organization. Replaced by a credential per connection.
