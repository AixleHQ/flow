# RFC: Unified OAuth for Integrations, MCP Servers, and Agent Credentials

**Status:** Draft
**Date:** 2026-07-05
**Scope:** Full OAuth token lifecycle (acquire via browser → store → refresh → deliver → revoke) for third-party providers (Sentry, Railway, …), user-added MCP servers, and agent CLI credentials.

---

## 1. Problem

The number of OAuth-gated dependencies is growing: remote MCP servers (Sentry, Railway) and agent CLIs all require interactive browser consent, and each new one is wired up ad-hoc. There is no shared machinery for:

- initiating a browser consent flow and handling the callback,
- storing tokens securely in one canonical shape,
- refreshing tokens proactively before expiry,
- delivering fresh tokens into running agent workspaces,
- surfacing "re-connect needed" state to users.

## 2. Current state (audit)

Credentials live in **four disjoint silos**, each with its own storage, flow, and (mostly absent) refresh story:

| Silo | Scope | Acquire | Storage | Refresh | Revoke |
|---|---|---|---|---|---|
| `AgentCredential` | per user + agent CLI | in-container CLI login, files scraped at cleanup (`AgentAuthStrategy#before_cleanup`) | encrypted blob (`Encryptable`, `credentials_key`) | opportunistic only: Cursor/Codex on 401 in `fetch_available_models`; Claude never (CLI self-refresh + post-session re-scrape) | none |
| `Integration.credentials` | company / project | Slack: hand-rolled OAuth v2 (hardened); GitHub App: install callback with **plaintext state**; GitLab/Coder: paste-a-token | encrypted blob (`integrations_key`) | none (GitHub mints installation tokens on demand — inherently fresh) | none |
| `ConfigItem` | company / project | manual paste | encrypted value (`config_items_key`) | n/a (static secrets) | none |
| `users.google_token` / `google_refresh_token` | per user | OmniAuth login | **plaintext columns**, never read | none | none |

MCP-specific findings:

- `mcp_servers.headers` / `env` are **plaintext jsonb**, serialized unmasked to the browser by `MCPServerResource`.
- The only secret mechanism is `config_item:NAME` indirection, resolved at container provisioning in `SessionContextService#resolve_server_secrets` — **the single choke point where secrets enter MCP configs**.
- Zero OAuth concepts anywhere in the MCP path (no client_id, authorization/token URLs, expiry, refresh).
- Resolved plaintext secrets leak into `/var/log/context.log` (collected as a session artifact) and into world-readable `.mcp.json` inside `/workspace` (committable by the agent).

Runtime constraints:

- Credentials enter a container exactly twice: env vars frozen at `create_container`, config files written once in `before_exec`. **No mechanism updates a token in a live session.**
- There is no persistent job backend (ActiveJob runs on in-process `:async`). The sanctioned recurring mechanism is **Temporal Schedules** (`app/temporal/schedules.yml`). Caveat: `TemporalService.sync_schedules` wipes *all* schedules at worker boot and recreates only the yml entries — per-record dynamic schedules are unreliable, so recurring work must be a **sweep over expiring rows**, which requires expiry in a plain queryable column.
- `agent_credentials.expires_at` exists but is never populated; the `.active` scope is a no-op.
- Slack's OAuth state handling (signed via `message_verifier` + 10 min TTL + single-use cache-backed nonce + user pinning) is the only hardened implementation and is Slack-specific.

## 3. Goals

1. One flow engine for every browser-consent OAuth acquisition.
2. One canonical, encrypted token store with queryable expiry.
3. Proactive refresh before expiry (background sweep) + on-demand refresh at use time.
4. Arbitrary user-pasted MCP server URLs "just work" via the MCP OAuth 2.1 spec (discovery + dynamic client registration).
5. Clear re-auth UX: status per connection, one-click reconnect, session-start preflight.
6. A path to tokens never touching agent containers (proxy/broker, optional later phase).

Non-goals (for now): replacing the in-container agent-CLI login flow; provider-side revocation on delete (tracked as follow-up).

## 4. Design

### 4.1 Data model — two tables

```ruby
# oauth_clients — "how to talk to an authorization server"
create_table :oauth_clients do |t|
  t.string  :issuer, null: false             # authorization server identity
  t.string  :authorization_endpoint, null: false
  t.string  :token_endpoint, null: false
  t.string  :registration_endpoint           # present when DCR was used
  t.string  :client_id, null: false
  t.text    :encrypted_client_secret         # Encryptable; null for public clients (PKCE-only)
  t.string  :scopes
  t.string  :source, null: false             # static (Settings-backed provider) | dcr
  t.jsonb   :metadata, default: {}           # raw RFC 8414 / RFC 7591 responses
  t.timestamps
end

# oauth_credentials — tokens
create_table :oauth_credentials do |t|
  t.references :owner, polymorphic: true, null: false   # User | Company | Project
  t.references :oauth_client, null: false
  t.references :mcp_server                                # nullable; set for MCP-attached creds
  t.string   :provider, null: false                       # "sentry", "railway", "mcp:<host>", …
  t.text     :encrypted_access_token
  t.text     :encrypted_refresh_token
  t.string   :token_type, default: "Bearer"
  t.string   :scopes
  t.datetime :expires_at                                  # PLAIN column — sweep must query it
  t.string   :status, null: false, default: "pending"     # pending|active|error|revoked
  t.string   :refresh_error
  t.datetime :last_refreshed_at
  t.jsonb    :metadata, default: {}                       # account info from token response
  t.timestamps
  t.index [:owner_type, :owner_id, :provider]
  t.index [:status, :expires_at]                          # sweep scope
end
```

Encryption via the existing `Encryptable` concern with a dedicated key (`Settings.encryption.oauth_key`), consistent with `AgentCredential` / `Integration` / `ConfigItem`. (Migrating the app to Rails Active Record Encryption is a separate, orthogonal improvement.)

The polymorphic `owner` answers "whose identity does the agent act as":

- `Company` / `Project` owner → shared service identity (today's `config_item` semantics).
- `User` owner → per-user identity; resolved against `session.user` at provisioning time.

### 4.2 Flow engine — generalize the Slack pattern

Extract Slack's state machinery into `Oauth::State` (signed `Rails.application.message_verifier(:oauth)` payload + 10 min TTL + single-use nonce in `Rails.cache` + `user_id` pinning) and build **one endpoint pair for everything**:

- `GET /oauth/:provider/authorize` — builds the authorization URL: PKCE (mandatory, OAuth 2.1), `state` carrying `{owner_type, owner_id, user_id, mcp_server_id, return_to, nonce}`. PKCE `code_verifier` lives in the state cache entry, server-side only.
- `GET /oauth/callback` — **single deployment-wide redirect URI**. Verifies state, exchanges the code at `token_endpoint` (PKCE verifier + client auth), upserts `OauthCredential`, redirects to `return_to`.

Known providers (Sentry, Railway, Google, Slack, …) are declared in an `Oauth::Providers` registry — endpoints/scopes/client credentials from `Settings`, materialized as `oauth_clients` rows with `source: static`.

"Opening the browser" needs nothing special: it is a normal redirect from the web UI. A **Connect** button → provider consent → callback → back to `return_to`.

### 4.3 MCP OAuth 2.1 — any pasted URL works

`Mcp::OauthDiscoveryService`, per the MCP authorization spec:

1. Probe the MCP URL; on 401 read `WWW-Authenticate` → protected-resource metadata (RFC 9728, `/.well-known/oauth-protected-resource`) → authorization server list.
2. Fetch authorization-server metadata (RFC 8414 / OIDC discovery) → endpoints.
3. Dynamic client registration (RFC 7591): POST to `registration_endpoint` (`client_name: "Aixle"`, our single callback URL) → persist `client_id`/`client_secret` as an `oauth_clients` row with `source: dcr`.
4. Authorize with PKCE + `resource=<mcp url>` (RFC 8707 resource indicators).

**Every discovery/token/DCR request must pass `UrlSafetyValidator`** — DCR metadata and endpoint URLs are attacker-controlled input (SSRF).

Model/UI changes:

- `mcp_servers.auth_type` enum: `none | static | oauth` (static = today's headers/env path, unchanged).
- `mcp_servers.credential_scope` enum: `shared | per_user`.
  - `shared`: one credential owned by the server's Company/Project scope.
  - `per_user`: each user connects their own account; provisioning resolves by `session.user`. Missing credential → session-start preflight shows "Connect Sentry" with the authorize link.
- `McpServerFormModal`: auth type selector; for `oauth` a **Connect** button that triggers discovery + flow and then shows connection status.

### 4.4 Delivery into agents — the existing seam

`SessionContextService#resolve_server_secrets` is already the single point where secrets enter MCP configs. For `auth_type: oauth` servers it calls:

```ruby
Oauth::TokenService.access_token_for(server, user: session.user)
# - picks the credential by credential_scope (shared owner vs session.user)
# - if expires_at < 10.minutes.from_now: refresh NOW under with_lock
# - returns a fresh access token or raises Oauth::ReauthRequired
```

The token is injected as `Authorization: Bearer <token>` into the rendered per-CLI config. Adapters (`claude_code`, `gemini_cli`, `codex`, `cursor_cli`) need **zero changes** — they receive a ready header exactly like a resolved `config_item:` today.

### 4.5 Proactive refresh — Temporal sweep

Mirrors the `coder_sweep_expired_locks` recipe:

- `Activities::Oauth::RefreshExpiringTokensActivity` — scope:
  `OauthCredential.where(status: :active).where("expires_at < ?", 15.minutes.from_now).where.not(encrypted_refresh_token: nil)`, `find_each` with per-record rescue/log, returns a counts hash.
- `Workflows::OauthTokenRefreshWorkflow < Workflows::Base` — thin `run`, `start_to_close_timeout: 300`, `max_attempts: 2`.
- Register in `app/temporal/workflows.yml`; add to `app/temporal/schedules.yml`: cron `*/5 * * * *`, `overlap: skip`.

Refresh-token rotation safety (single-flight):

- Row lock (`with_lock`) around every refresh; compare `expires_at` before persisting so a concurrent fresher token is never clobbered — the exact pattern already proven in `AgentSessionStrategy#persist_refreshed_credentials` + `BaseAdapter#merge_refreshed_credentials` (rotation guard; `ClaudeCodeAdapter` merges `claudeAiOauth`/`designOauth` blocks independently by expiry).
- Never discard the old refresh token until the new pair is committed.
- N consecutive failures → `status: :error` + `refresh_error`, UI badge, user notification → one-click reconnect (same authorize endpoint).

Same sweep covers agent CLIs: start populating `agent_credentials.expires_at` (Claude's `token_expires_at` is already implemented), lift `refresh_access_token!` (Codex) / `refresh_cursor_token!` (Cursor) into a shared `BaseAdapter#refresh!` hook, and Codex/Cursor tokens get refreshed **before** a session launches instead of after a 401.

### 4.6 Re-auth UX

- Connection status (active / expiring / error) on the integrations page and per MCP server row; for `per_user` servers, status is per current user.
- Session-start preflight: required OAuth credentials missing or unrefreshable → block launch with "Connect …" links instead of launching a session that fails silently.
- Refresh failure notifications (badge + optional email), pointing at the same authorize URL.

### 4.7 Long sessions — MCP proxy (optional, phase 4)

Configs are written once in `before_exec`; a token expiring mid-session breaks that MCP server silently. The radical fix: agent configs point at
`https://<web>/mcp-proxy/<server_id>` with `X-Session-Key: <session.mcp_key>` (the same inbound auth contract as the internal `aixle-tools` endpoint — `MCPController` resolving the `TerminalSession` by `mcp_key`). Rails streams the request to the real server, injecting a fresh `Authorization` header server-side.

Wins: restart-free rotation; **tokens never touch the container** — also closes the `/var/log/context.log` and committable-`.mcp.json` leaks. Cost: streaming `streamable-http`/SSE through Rack needs care (`ActionController::Live` or a thin Rack proxy). Build only if mid-session expiry is an observed pain.

## 5. Evaluation: 1MCP (`1mcp-app/agent`) as the proxy

[1MCP](https://github.com/1mcp-app/agent) is a Node/TypeScript MCP aggregator: many downstream MCP servers behind one endpoint, with downstream OAuth handled via the official MCP SDK.

**What it genuinely has** (verified in source, `src/auth/sdkOAuthClientProvider.ts`, `src/transport/transportFactory.ts`, `src/transport/http/routes/oauthRoutes.ts`):

- Full OAuth 2.1 client to downstream servers via the SDK's `OAuthClientProvider`: discovery, **dynamic client registration** (`autoRegister: true`), PKCE, `authorization_code` + `refresh_token` grants.
- Per-server callback (`/oauth/callback/:serverName`) and an authorization dashboard (`/oauth`) listing servers with an **Authorize** button; reconnects the transport after callback.
- Refresh handled by the SDK transport lazily (on connect / 401). Acceptable server-side, since the broker is always on.
- Inbound auth optional (`--enable-auth`, OAuth 2.1 with tag-based scopes); deployable via npm/Docker.

**Why it does not fit as Flow's production proxy:**

1. **Single identity per downstream server.** Tokens are keyed by server name only — no per-user, per-project, or per-company credential separation. All Flow users would share one Sentry/Railway identity per 1MCP instance. Our `credential_scope: per_user` requirement is unimplementable without one 1MCP instance per user/tenant — operational sprawl.
2. **Token storage = JSON files on local disk** (`FileStorageService`, `clientSessions/`), unencrypted at rest. Fails our bar (encrypted DB storage, auditability, backup story); needs a PVC per instance in k8s.
3. **Separate auth/consent surface.** The `/oauth` dashboard is its own UI with its own (optional) inbound auth — not tied to Flow's users, policies (`manage_integrations?`), or state-signing. Anyone reaching the dashboard can authorize or re-authorize any server.
4. **No proactive refresh** — lazy only; our Temporal sweep + preflight semantics (block session start on dead credentials, notify users) would still have to be built around it.
5. **Another runtime to operate** per environment, in front of servers we already gate through `SessionContextService` and the internal MCP endpoint (official `mcp` gem, stateless `MCP::Server` per request in `MCPController` / `Tools::MCPRequestHandler`).

**Verdict:** great fit for its intended use (single developer aggregating personal MCP servers), and a useful **reference implementation** — its `SDKOAuthClientProvider` is a 1:1 blueprint for our Phase 3 discovery/DCR service. But as Flow's multi-tenant proxy it fails on identity separation, storage, and UI integration. The Rails-owned broker (§4) keeps tokens in our encrypted store, our policies, and our UX; the optional Phase 4 proxy reuses infrastructure we already have (`mcp_key` inbound auth, `UrlSafetyValidator`).

A pragmatic middle option, if Phase 4 urgency arrives before we can build the Rails proxy: run 1MCP **per-tenant** for `shared`-scope servers only, treating it as disposable infrastructure. Not recommended as the target state.

## 6. Phasing

| Phase | Deliverable | Estimate |
|---|---|---|
| 1 | `oauth_clients` + `oauth_credentials`, `Oauth::State` (generalized from Slack), authorize/callback endpoints, `Oauth::Providers` registry (Sentry, Railway), injection in `resolve_server_secrets`, on-demand refresh at provisioning | 1–2 wk |
| 2 | Temporal refresh sweep, status/re-auth UI, session-start preflight, populate `agent_credentials.expires_at`, shared `BaseAdapter#refresh!` | ~1 wk |
| 3 | MCP OAuth 2.1 discovery + DCR + `per_user` credential scope | 1–2 wk |
| 4 (optional) | MCP proxy: tokens never leave Rails, restart-free rotation | by observed pain |

## 7. Security quick wins (independent of the phases)

- Sign GitHub App setup `state` with `Oauth::State` (today: plaintext, replayable, no TTL).
- Redact resolved secrets from `/var/log/context.log` (currently collected as a session artifact with plaintext tokens).
- Mask `mcp_servers.headers` values in `MCPServerResource` (currently round-trip unmasked to the browser).
- Drop dead plaintext `users.google_token` / `google_refresh_token` columns.
- Escape values when rendering Codex TOML MCP config (token with a quote corrupts the file).

## 8. Key references (code)

- `app/services/session_context_service.rb` — `resolve_server_secrets` (injection seam), context assembly.
- `app/services/slack/oauth.rb`, `app/controllers/web/integrations/slack_oauth_controller.rb` — hardened state pattern to generalize.
- `app/services/container_strategies/agent_auth_strategy.rb`, `agent_session_strategy.rb` — acquisition + `persist_refreshed_credentials` locking pattern; `BaseAdapter#merge_refreshed_credentials` — per-block rotation-guarded merge.
- `app/controllers/mcp_controller.rb`, `Tools::MCPRequestHandler` — inbound MCP via the official `mcp` gem (stateless server per request), `mcp_key` session auth.
- `app/services/agents/base_adapter.rb` (+ codex/cursor adapters) — existing refresh flows to unify.
- `app/temporal/schedules.yml`, `Workflows::CoderSweepExpiredLocksWorkflow` — recurring sweep recipe.
- `app/models/concerns/encryptable.rb` — storage encryption concern.
- MCP authorization spec: RFC 8414, RFC 9728, RFC 7591, RFC 8707, PKCE (RFC 7636).
