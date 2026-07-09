# OAuth — how it works (implementation guide)

**Status:** As-built
**Companion to:** [oauth-unification.md](./oauth-unification.md) (the RFC / design rationale). This doc
describes the *shipped* system: the runtime flows, the security guards, and the file map. Read the RFC
for *why*; read this for *what runs*.

---

## 1. Two credential stores (don't conflate them)

| Store | For | Model | Where tokens live | Refresh |
|---|---|---|---|---|
| **OAuth broker** | third-party providers (Sentry, Railway) + user-added MCP servers | `OauthCredential` (+ `OauthClient`) | encrypted columns, DB | on-demand at use + Temporal sweep |
| **Agent-CLI login** | the agent CLIs' own auth (Claude / Codex / Cursor / Gemini) | `AgentCredential` | encrypted `config_data` blob, DB | Temporal sweep + reactive-on-401 |

They are deliberately separate: the broker is *the app acting as an OAuth client against someone else's
authorization server*; the agent-CLI store is *the coding agent's own login captured from its container*.

---

## 2. Data model (broker)

- **`oauth_clients`** — "how to talk to an authorization server": `issuer`, `authorization_endpoint`,
  `token_endpoint`, `registration_endpoint`, `client_id`, encrypted `client_secret` (nil = public/PKCE),
  `scopes`, `source`, `metadata` (raw RFC 8414/7591 responses). `source ∈`:
  - `static` — materialized from the `Oauth::Providers` registry (Settings-backed).
  - `dcr` — RFC 7591 Dynamic Client Registration.
  - `cimd` — RFC "Client ID Metadata Document": our hosted metadata-doc URL *is* the client_id.
  `OauthClient::DISCOVERED_SOURCES = %w[dcr cimd]` (the callback constrains signed client ids to these).
- **`oauth_credentials`** — the tokens: polymorphic **`owner`** (User | Company | Project = *whose identity
  the agent acts as*), `oauth_client`, nullable `mcp_server`, `provider` (`"sentry"`, `"mcp:<host>"`),
  encrypted `access_token`/`refresh_token`, `token_type`, `scopes`, **plaintext `expires_at`** (so the sweep
  can query it), `status` (`pending|active|error|revoked`), `refresh_failure_count`, `last_refreshed_at`,
  jsonb `metadata` (only non-secret account fields — never `id_token`). Encryption via `Encryptable` +
  `Settings.encryption.oauth_key`.

Unique/idempotency key for a credential: `(owner, oauth_client, provider, mcp_server)`.

---

## 3. Acquiring a client

**Static providers** (`app/services/oauth/providers.rb`): a registry declares Sentry/Railway (endpoints +
scopes in code, `client_id`/`client_secret` from `Settings`). `client_for` reconciles a `source:static`
`OauthClient` row.

**MCP servers** (`app/services/mcp/oauth_discovery_service.rb`) — any pasted URL, per the MCP auth spec:
1. Probe the MCP URL; on 401 read `WWW-Authenticate` → RFC 9728 protected-resource metadata → authorization
   server list.
2. Fetch RFC 8414 / OIDC authorization-server metadata → endpoints.
3. Register the client:
   - **CIMD preferred** — if the AS advertises `client_id_metadata_document_supported`, use our hosted
     `/oauth/client-metadata.json` as the client_id (no network registration). `source:cimd`.
   - **DCR otherwise** — POST `registration_endpoint` (`client_name: "Aixle Flow"`, single callback), persist
     `source:dcr`.
4. Authorize with PKCE + `resource=<mcp url>` (RFC 8707).

### SSRF doctrine (discovery only — every URL here is attacker-influenced)
`#guard!` runs `UrlSafetyValidator.errors_for(url, require_https: true)` before **every** fetch (MCP URL,
PRM URL, each authorization_servers entry, ASM metadata, authorize/token/registration endpoints, DCR-echoed
`redirect_uris`/`client_uri`). Redirects are followed manually and **re-guarded per hop** (cap 3). Public
IPv4 is DNS-pinned to beat TOCTOU. Bodies/timeouts capped. The `token_endpoint` is **re-guarded at
time-of-use** in both the callback and the refresh path — a persisted `dcr` endpoint is no more trusted than
a freshly discovered one.

---

## 4. The flow engine (`app/controllers/web/oauth_controller.rb`)

One controller, **one deployment-wide redirect URI** (`/oauth/callback`).

- `GET /oauth/:provider/authorize` (static) / `GET /oauth/mcp/:mcp_server_id/connect` (MCP): build the
  provider authorize URL with **mandatory PKCE (S256)** and a signed `Oauth::State`.
- `GET /oauth/callback`: verify state, exchange the code at `token_endpoint`, `upsert_from_token!`, redirect
  to `return_to`.
- `GET /oauth/client-metadata.json`: public (no auth) RFC CIMD document. Its `client_id` **must equal** the
  URL it is served at — both are built from `Settings` so they are byte-identical.

### `Oauth::State` (`app/services/oauth/state.rb`) — the security core
Generalized from the old hardened Slack flow. Signed `Rails.application.message_verifier("oauth")` payload
+ **10-min TTL** + **single-use nonce** (in `Rails.cache`, deleted on first `consume`) + **double user
pinning** (`user_id` signed AND cached). The PKCE `code_verifier` **never leaves the server** — it lives in
the cache entry under the nonce and is handed back exactly once. The signed payload carries
`{owner_type, owner_id, user_id, provider, mcp_server_id, resource, oauth_client_id, return_to, nonce}`.

Callback guards, in order: (1) signature + TTL, (2) single-use nonce, (3) double user-pin,
(4) mandatory PKCE, (5) owner authorization (what the current user may act for), (6) open-redirect-safe
`return_to`, (7) token-free error logging, (8) cancel handled before the nonce is consumed (retry within TTL).

The **GitHub App setup** callback reuses `Oauth::State` too (`IntegrationsController#github_app_install`
mints it; `GithubSetupController` verifies) — replacing the old plaintext, replayable `project:<id>` state.

---

## 5. Delivery into agent sessions

`SessionContextService#resolve_server_secrets` is the single point where secrets enter an MCP config.
For an `auth_type: oauth` server it calls `inject_oauth_token! → Oauth::TokenService.access_token_for`:

- **`pick_credential`** — for `credential_scope: per_user`, the identity is the acting `session.user`; for
  `shared`, the server's scope owner (Company/Project). Never an owner-blind fallback (confused-deputy
  guard). A missing OAuth credential raises `Oauth::ReauthRequired`.
- **`fresh`** — returns the stored token unless within `REFRESH_SKEW` (10 min) of expiry; if so, refreshes
  **under `with_lock`** with a re-check + no-downgrade guard.
- The token is injected as an `Authorization: Bearer <token>` header into the rendered per-CLI MCP config.
  **Adapters are unchanged** — they see a resolved header exactly like a `config_item:` today.

### Secret redaction in `/var/log/context.log`
The assembled context is dumped to `/var/log/context.log` (collected as a `SessionLog` artifact, readable by
the in-container agent). `ContextLog#redact` registers every resolved secret value (all MCP header/env
values incl. the injected Bearer, plus the session `mcp_key`) and `scrub_secrets` replaces each with a
fingerprint (`«redacted:sha256:xxxxxxxx»`, longest-first). Keys/structure stay for audit; the raw bytes do
not. The **container's own MCP config files still hold the real secrets** (the agent needs them) — closing
that is the optional Phase-4 proxy.

---

## 6. Refresh (broker)

Two layers, both single-flight and rotation-safe (keep the old refresh_token until the new pair commits;
never clobber a fresher token):

- **On-demand** at use time (`TokenService.fresh`, under `with_lock`).
- **Proactive** — `Workflows::OauthTokenRefreshWorkflow` (`*/5`, `overlap: skip`) runs
  `Activities::Oauth::RefreshExpiringTokensActivity`, sweeping `OauthCredential.refresh_due` (active +
  refresh_token present + expiring within 15 min) via `TokenService.refresh_credential`.

**Failure escalation**: `mark_refresh_error!` increments `refresh_failure_count`; a single blip keeps the
credential `active` (the sweep retries). After `MAX_REFRESH_FAILURES = 3` consecutive failures it escalates
to `status:error` and — for `User` owners — sends `OauthMailer#refresh_failed` (reconnect link). Any success
resets the counter.

---

## 7. Re-auth UX

- **Session-start preflight** (`Oauth::Preflight`, `SessionService.create_and_start`): before launching, if a
  selected OAuth MCP server has no usable credential for the acting user, raise `Oauth::PreflightError`. The
  API returns `422 { reauth_required: [{ mcp_server_id, name, connect_url }] }`, and `SessionNewForm`
  renders a **"Connect <server>" CTA** per entry instead of a raw error.
- **Status badges**: `MCPServerResource#oauth_status` (per current viewer: `pending|active|expiring|error`)
  drives the badge on the MCP server list row and edit modal.
- **Notifications**: the refresh-failure email above.

---

## 8. Credential scope (MCP)

`mcp_servers.credential_scope ∈ shared | per_user`, default **`shared`** (project-wide). The modal shows a
plain "shared by all project members" line; `per_user` is tucked behind an **Advanced** disclosure (only
auto-shown when editing a server that already uses it). `per_user` means each member connects their own
account and their token is resolved by `session.user`; `shared` means one project-owned credential used by
everyone.

---

## 9. Agent-CLI login (`AgentCredential`)

Auth happens in a throwaway **auth-setup container**: `AgentAuthStrategy` launches the CLI's login command
(`AUTH_COMMANDS`), an in-container **watcher** (`docker/base/watcher/index.js`) polls `AUTH_WATCH_PATH` for
`AUTH_REQUIRED_KEYS` (dot-notation, any-match), the frontend polls `${watcherUrl}/auth`, and `before_cleanup`
scrapes the auth files and saves a sliced `AgentCredential`.

### Claude's auth methods (they differ — don't over-generalize)
| Method | Auth | Stored | Refreshes? |
|---|---|---|---|
| **claude.ai OAuth** (subscription) | Bearer + oauth beta header | `claudeAiOauth` in `.credentials.json` | yes (`platform.claude.com/v1/oauth/token`) |
| **platform.claude.com** (Console API key) | `x-api-key` | `primaryApiKey` in `.claude.json` | no (long-lived key) |
| **`/design-login`** | OAuth, *layered on* claude.ai | `designOauth` in `.credentials.json` | yes (own `clientId`) |
| **Bedrock / Vertex** | AWS SSO / GCP ADC via **env** | **not modeled** (deferred) | — |

The interactive `claude` login already covers **both** claude.ai and platform.claude.com (the user chooses
inside Claude Code's own TUI), so the profile's **Authenticate** button simply launches `claude` — we do
NOT present our own method chooser. The login method (and, in Claude's native menu, the 3rd-party/Bedrock
option) is picked inside the terminal.

Only the OAuth blocks (`claudeAiOauth`, `designOauth`) expire and refresh — `token_expires_at` reads only
those, so API-key credentials get `expires_at = nil` (always active, never swept) and Bedrock has no stored
credential at all. `AgentCredentialResource#connection_status` (active/expiring/expired, expiry-derived)
drives the badge on the profile page.

Codex/Cursor tokens are JWTs — `token_expires_at` decodes their `exp` (`BaseAdapter#jwt_exp_ms`) so the sweep
selects them; their `refresh!` persists under `BaseAdapter#persist_refreshed!` (lock + rotation guard).

### `/design-login` (design auth)
The **"Connect Design"** button on the Claude profile card (shown only when the credential has a
`claudeAiOauth` block — API-key/Bedrock users can't design-login) opens the auth modal in `authKind: "design"`
mode. Backend (`AgentAuthStrategy`, keyed on `session.metadata["auth_kind"] == "design"`):
1. `before_exec` **injects the user's existing base credential** (minus `designOauth`) so the CLI starts
   logged in. Because the base auth container's entrypoint launches `TTYD_CMD` at container start (before
   `before_exec`), design uses `ttyd_command = "bash"` and launches `claude` in `#exec` *after* the creds are
   seeded (the session pattern — `send_tmux_command`); otherwise `claude` would race ahead of the creds and
   show a fresh login.
2. Env `AUTH_REQUIRED_KEYS = designOauth.accessToken` (the watcher needs no change — it's key-agnostic),
   because the base token is present from the start and must not be mistaken for completion.
3. The user runs `/design-login` in the terminal → `designOauth` lands in `.credentials.json`.
4. `before_cleanup` gates completion on `design_auth_complete?` and saves the merged blob (base + design).

### Bedrock / Vertex — deferred (not modeled)
Real-world corporate Bedrock (see the employee onboarding doc) is **AWS SSO** (per-dev browser login, no
static keys), with the Bedrock config — `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_PROFILE`, `AWS_REGION`, model ARNs,
guardrail headers — living in a **committed `.claude/settings.json`** (non-secret), refreshed via
`aws sso login`. That is a *project-level env config + interactive SSO*, not a per-user stored secret, so it
does **not** belong in the OAuth token engine. Deferred until needed; if built, model it on that flow
(project Bedrock config injected as env + an SSO login step in the session), NOT a static-key form.

---

## 10. File map

- Data model: `app/models/oauth_client.rb`, `app/models/oauth_credential.rb`, `app/models/mcp_server.rb`,
  `app/models/agent_credential.rb`.
- Flow engine: `app/controllers/web/oauth_controller.rb`, `app/services/oauth/state.rb`,
  `app/services/oauth/providers.rb`.
- MCP discovery: `app/services/mcp/oauth_discovery_service.rb`, `app/models/concerns/url_safety_validator.rb`.
- Delivery + refresh: `app/services/session_context_service.rb`, `app/services/oauth/token_service.rb`,
  `app/services/oauth/preflight.rb`, `app/temporal/{activities/oauth,workflows}/*`, `app/mailers/oauth_mailer.rb`.
- Agent CLIs: `app/services/agents/*_adapter.rb`, `app/services/container_strategies/agent_auth_strategy.rb`,
  `docker/base/watcher/index.js`, `docker/base/auth-check/index.js`.
- UI: `app/frontend/shared/resources/mcp-servers/McpServerFormModal.tsx` + `McpServersContent.tsx`,
  `app/frontend/shared/components/SessionNewForm.tsx`, `app/frontend/pages/Profile/Show.tsx`,
  `app/frontend/shared/resources/integrations/IntegrationsContent.tsx`.
