# Flow ↔ Aixle Insights sharing

Date: 2026-09-17. Status: implemented (Flow side).

First-party integration so Aixle Insights can pull completed agent-session usage
from Flow and show it next to Copilot, Cursor, Claude, and other tools. Data
leaves Flow only when a project admin opts in. Insights never invents usage —
it receives what Flow already stores on `usage_statistics`.

Insights connector work lives in [AixleHQ/insights](https://github.com/AixleHQ/insights)
and is out of scope for this document's implementation notes; the contract below
is what that connector must call.

## Product gates

- **Default off.** `projects.share_usage_with_insights` defaults to `false`.
- **Project-level only** — not company-wide, not per-user.
- Toggle and connection-token management: **company admin or project owner**
  (same bar as project integrations).
- Turning sharing off clears the connection-token digest immediately. A still-held
  Insights secret then gets `403 insights_sharing_disabled`.

## Auth

Project-scoped service credential:

- Prefix `afli_` (Aixle Flow Insights).
- Plaintext shown once after generate/regenerate; only SHA256 digest stored
  (`insights_connection_token_digest`).
- Insights stores the plaintext as `OrganizationConnector#access_token`.
- Do **not** reuse a user session cookie or personal MCP (`amcp_`) token.

## Pull API

Namespace: `Api::V1::Insights`. Auth: `Authorization: Bearer afli_…`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/insights/project` | Probe: id, name, slug, company_id, sharing flag |
| GET | `/api/v1/insights/members` | id, email, name for user mapping |
| GET | `/api/v1/insights/session_usages` | Paginated completed session usage |

Errors:

1. Missing/invalid token → `401`
2. Valid token, sharing off → `403` `{ "error": "insights_sharing_disabled", "code": "insights_sharing_disabled" }`

Never returned: prompts, transcripts, `events_data`, route/mcp keys, config-item
values, session metadata blobs.

### Session selection

`terminal_sessions` joined to `usage_statistics`:

- Same `project_id` as the credential
- `state IN ('finished', 'failed')`
- `session_type != 'auth_setup'`
- Has a `usage_statistic` row (no-usage sessions omitted quietly)
- Cursor: `since` (ISO8601 on `finished_at`) + `after_id` + `limit` (default 100, max 500)
- Order: `finished_at, id`

### Payload item

```json
{
  "external_id": "123",
  "occurred_at": "2026-09-17T10:00:00.000Z",
  "started_at": "...",
  "finished_at": "...",
  "user": { "id": 1, "email": "a@b.co", "name": "..." },
  "project": { "id": 9, "slug": "foo", "name": "Foo" },
  "agent_type": "claude_code",
  "session_type": "agent_session",
  "models": ["claude-sonnet-4"],
  "tokens_in": 100,
  "tokens_out": 50,
  "cache_write_tokens": 0,
  "cache_read_tokens": 10,
  "tokens_total": 160,
  "cost_usd": 0.0123
}
```

`cost_usd` from `usage_statistics.total_cents_precise / 100` (fallback `cost_cents / 100.0`).
Token fields from `usage_statistics`, not denormalized session columns.

Insights mapping (follow-up): `tool_name: aixle_flow`, dedup on `external_id`,
cache + `agent_type` in `metadata`.

## Flow UI

Project Settings → Aixle Insights: switch + generate/regenerate connection token
(plaintext once). Props include `canManageInsightsSharing`; non-managers see the
switch disabled.

## Non-goals

- Public usage API for arbitrary third parties / company API keys (#202)
- Webhooks / push from Flow
- Transcripts, prompts, secret config values
- Backfill of sessions finished before the feature ships
- Per-user opt-in on Flow
- Insights connector implementation in this repo
