# OAuth — how it works (implementation guide)

**Status:** As-built
**Companion to:** [oauth-unification.md](./oauth-unification.md) (the RFC / design rationale). This doc
describes the *shipped* system: the runtime flows, the security guards, and the file map. Read the RFC
for *why*; read this for *what runs*.

---

## 1. Two credential stores (don't conflate them)

| Store | For | Model | Where tokens live | Refresh |
|---|---|---|---|---|
| **OAuth broker** | third-party providers (Sentry, Railway; a person's own GitHub, GitLab and Bitbucket account) + user-added MCP servers | `OauthCredential` (+ `OauthClient`) | encrypted columns, DB | on-demand at use + Temporal sweep |
| **Agent-CLI login** | every agent CLI's own auth (Claude / Codex / Cursor / Gemini / Antigravity / Grok / Kiro / Copilot) | `AgentCredential` | encrypted `config_data` blob, DB | Temporal sweep + reactive-on-401 |

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
  - `manual` — credentials an operator registered by hand at the provider, for an authorization server
    that will not let us register ourselves. Scoped to one MCP server (`oauth_clients.mcp_server_id`).
  `OauthClient::DISCOVERED_SOURCES = %w[dcr cimd]`; `OauthClient::MCP_SOURCES` adds `manual`. The MCP
  callback constrains signed client ids to `MCP_SOURCES`, so a `static` client can never be spent there.
- **`oauth_credentials`** — the tokens: polymorphic **`owner`** (User | Company | Project = *whose identity
  the agent acts as*), `oauth_client`, nullable `mcp_server`, `provider` (`"sentry"`, `"mcp:<host>"`),
  encrypted `access_token`/`refresh_token`, `token_type`, `scopes`, **plaintext `expires_at`** (so the sweep
  can query it), `status` (`pending|active|error|revoked`), `refresh_failure_count`, `last_refreshed_at`,
  jsonb `metadata` (only non-secret account fields — never `id_token`). Encryption via `Encryptable` +
  `Settings.encryption.oauth_key`.

Unique/idempotency key for a credential: `(owner, oauth_client, provider, mcp_server)`.

---

## 3. Acquiring a client

**Static providers** (`app/services/oauth/providers.rb`): a registry declares `sentry`, `railway`,
`github`, `gitlab` and `bitbucket`. Each entry has its endpoints and scopes in code, or an `endpoints`
callable (GitLab's follow `GITLAB_ENDPOINT`), and an `oauth_app` callable for the client id and secret
from `Settings` (through `Gitlab::AppConfig` and `Bitbucket::AppConfig` for those two).
Optional keys: `owner_types` (GitHub, GitLab and Bitbucket take only a `User`), `fetch_identity` (fetches the
connected identity with the new token, before the credential is stored), `client_auth: :basic` (Bitbucket) and `trust_endpoint_host` (GitLab, whose token call may
reach a privately resolving host). `client_for` reconciles a `source:static` `OauthClient` row.

**MCP servers** (`app/services/mcp/oauth_discovery_service.rb`) — any pasted URL, per the MCP auth spec:
1. Probe the MCP URL; on 401 read `WWW-Authenticate` → RFC 9728 protected-resource metadata → authorization
   server list.
2. Fetch RFC 8414 / OIDC authorization-server metadata → endpoints.
3. Register the client:
   - **Manual first** — a hand-registered client on the server outranks every automatic path; discovery
     fills in its endpoints and issuer. `source:manual`.
   - **CIMD next** — if the AS advertises `client_id_metadata_document_supported`, use our hosted
     `/oauth/client-metadata.json` as the client_id (no network registration). `source:cimd`.
   - **DCR otherwise** — POST `registration_endpoint` (`client_name: "Aixle Flow"`, single callback), persist
     `source:dcr`.
4. Authorize with PKCE + `resource=<mcp url>` (RFC 8707). The `scope` asked for is the challenge's
   `scope` (RFC 6750 §3), else the protected resource's `scopes_supported`, else — unlike the spec, which
   omits it — the authorization server's; `offline_access` is added whenever the authorization server
   lists it, since an OIDC-style server issues no refresh token without it.

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

- `POST /oauth/:provider/authorize` (static) / `POST /oauth/mcp/:mcp_server_id/connect` (MCP): build the
  provider authorize URL with **mandatory PKCE (S256)** and a signed `Oauth::State`. A `GET` of the MCP
  connect URL (reconnect emails, old links) starts nothing: it lands on the project's MCP servers page and
  asks the person to press Connect.
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
`return_to`, (7) token-free error logging, (8) cancel handled before the nonce is consumed (retry within TTL),
(9) RFC 9207 issuer check — an `iss` in the response must match the client's issuer. For MCP the callback
also refuses a grant whose signed `resource` origin no longer matches the server's URL (the server was
re-pointed mid-connect).

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
  under a **refresh lease** (`RefreshLease`): one refresher at a time, a re-check once the lease is held,
  the provider call outside any transaction, and only the persist under `with_lock` with a no-downgrade
  guard. A rolled-back write of a rotated refresh token would lose the only valid one. A caller that finds
  the lease taken waits for that refresh and uses its result.
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

- **On-demand** at use time (`TokenService.fresh`, under the refresh lease).
- **Proactive** — `Workflows::OauthTokenRefreshWorkflow` (`*/5`, `overlap: skip`) runs
  `Activities::Oauth::RefreshExpiringTokensActivity`, sweeping `OauthCredential.refresh_due` (active +
  expiring within 15 min) via `TokenService.refresh_credential`, which does not wait on a credential
  another refresher holds.

**Failure escalation**: `mark_refresh_error!` increments `refresh_failure_count`; a single blip keeps the
credential `active` (the sweep retries). After `MAX_REFRESH_FAILURES = 3` consecutive failures it escalates
to `status:error` and — for `User` owners — sends `OauthMailer#refresh_failed` (reconnect link). Any success
resets the counter.

A credential with **no refresh_token at all** goes down the same path: `refresh_due` deliberately does not
filter on the refresh token, and `TokenService.fresh` records the failure before raising `ReauthRequired`, so
the row escalates to `status:error` and notifies instead of sitting `active` until its access token lapses.
That is not a hypothetical — an authorization server may grant `offline_access` silently as "no", which is why
`Web::OauthController` sends `prompt=consent` whenever it requests that scope (OIDC Core §11).

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
| **Claude Platform** (Console login, CLI ≥ 2.1.281) | Bearer + oauth beta header | `platformOauth` (tokens) + `platformProfile` (org/workspace/client) — rendered to `~/.config/anthropic/{credentials,configs}/default.json`, both **0600** and agent-owned (the CLI refuses a group/world-readable credentials file) | yes (`api.anthropic.com/v1/oauth/token`, JSON body, profile's `client_id`) |
| **platform.claude.com** (Console API key, older CLIs) | `x-api-key` | `primaryApiKey` in `.claude.json` | no (long-lived key) |
| **`/design-login`** | OAuth, *layered on* claude.ai | `designOauth` in `.credentials.json` | yes (own `clientId`) |
| **Amazon Bedrock** | AWS (IAM Identity Center role credentials, or a Bedrock API key / long-term keys from Claude Code's wizard) | `awsBedrock` block (region, profile, credential source) | Identity Center: yes, server-side at vending time; keys: no |
| **Vertex** | GCP ADC via **env** | **not modeled** (deferred) | — |

The interactive `claude` login already covers **both** claude.ai and platform.claude.com (the user chooses
inside Claude Code's own TUI), so the profile's **Authenticate** button simply launches `claude` — we do
NOT present our own method chooser. The login method (and, in Claude's native menu, the 3rd-party/Bedrock
option) is picked inside the terminal.

Only the OAuth blocks (`claudeAiOauth`, `platformOauth`, `designOauth`) expire and refresh — `token_expires_at` reads only
those, so API-key and Bedrock credentials get `expires_at = nil` (always active, never swept). `AgentCredentialResource#connection_status` (active/expiring/expired, derived from the **base login's** expiry —
`metadata.login_expires_at`, written beside `expires_at` by `sync_expires_at` — never from an add-on like `designOauth`;
`expires_at` stays the soonest block expiry because it is what the sweep selects on)
drives the badge on the profile page.

Codex/Cursor tokens are JWTs — `token_expires_at` decodes their `exp` (`BaseAdapter#jwt_exp_ms`) so the sweep
selects them; their `refresh!` persists under `BaseAdapter#persist_refreshed!` (lock + rotation guard).

### `/design-login` (design auth)
The **"Connect Design"** button on the Claude profile card (shown when the credential has a base
login — `claudeAiOauth`, `platformOauth` or `primaryApiKey`; Bedrock users can't design-login) opens the auth modal in `authKind: "design"`
mode. Backend (`AgentAuthStrategy`, keyed on `session.metadata["auth_kind"] == "design"`):
1. `before_exec` **injects the user's existing base credential** (minus `designOauth`) so the CLI starts
   logged in (`auth_setup_files_for`). Because the base auth container's entrypoint launches `TTYD_CMD` at
   container start (before `before_exec`), design uses `ttyd_command = "bash"` and `#exec` launches the
   adapter's `auth_launch_commands_for` — `claude /design-login`, so the CLI starts already running the
   command — with `send_tmux_sequence` *after* the creds are seeded; otherwise `claude` would race ahead of
   the creds and show a fresh login.
2. Env `AUTH_REQUIRED_KEYS = designOauth.accessToken` (`auth_required_keys_for`; the watcher needs no
   change — it's key-agnostic), because the base token is present from the start and must not be mistaken
   for completion.
3. The user approves in the browser → `designOauth` lands in `.credentials.json`.
4. `before_cleanup` gates completion on `auth_complete_for?` and saves the merged blob (base + design).

### Amazon Bedrock
Bedrock lives on the `claude_code` `AgentCredential`, not in the OAuth token engine: an `awsBedrock` block
(`ClaudeCodeAdapter::BEDROCK_KEY`), one of the mutually exclusive `INFERENCE_KEYS`. The user picks Amazon
Bedrock inside Claude Code's own login wizard in the auth container. Two sources:

- **IAM Identity Center** — `CloudAuth::AwsDeviceFlow` runs the device flow server-side and stores the OIDC
  client registration and tokens in the block. The container gets only a `credential_process` helper, which
  asks `CloudCredentialsController` for short-lived role credentials (`CloudAuth::AwsCredentialVendor`).
- **Wizard-entered keys** — a Bedrock API key or long-term access keys are captured from the settings the
  wizard writes, and rendered back into Claude Code's user settings file each session.

`CloudAuth::Preflight` blocks a launch on a broken connection and offers a "Reconnect AWS" CTA. Design and
security notes: [cloud-connection-security.md](./cloud-connection-security.md) and
`docs/research/technical-aws-bedrock-cloud-provider-auth-2026-07-25.md`.

### Vertex — deferred (not modeled)
Vertex (GCP ADC via env) has no stored credential and no connect flow.

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
