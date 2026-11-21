# Agent credential lifecycle: one contract for every harness

**Status:** design, with the first four layers implemented (branch
`artempartos/harness-cred-refresh-strategy`). Each section below marks what has landed and
what has not.
**Date:** 2026-09-17 (§7 added 2026-11-21, task #219)
**Scope:** the seven agent runtimes in `CompanyMembership::AVAILABLE_AGENTS`, their stored
credentials, and everything that reads, refreshes, injects or recaptures them.

Related: `docs/design/oauth-implementation.md` (as-built OAuth guide),
`docs/research/technical-container-token-brokering-research-2026-09-05.md` (the broker options),
`docs/design/grok-runtime-integration.md`.

---

## 1. The three questions this answers

1. **Does every harness actually refresh?** Six of seven do since 2026-09-24; `gemini_cli`
   stores an API key, which has nothing to refresh. Each runtime declares why in
   `BaseAdapter#credential_lifecycle`, pinned by the contract test.
2. **Why do sessions that end in the middle lose their credential, and why can the sweep not
   fix it?** Because the grant has more than one holder and only the *container* writes back —
   once, at the end, on the happy path.
3. **How do we know when, why and how a credential died?** We mostly do not. Two columns are
   written by the sweep and read by nothing.

---

## 2. What exists today

Four mechanisms, each independently correct, none aware of the others:

| # | Mechanism | Code | Runs when |
|---|---|---|---|
| M1 | Launch top-up | `AgentCredential#refresh_if_expiring!` (`app/models/agent_credential.rb:219`) | session launch, `SESSION_REFRESH_THRESHOLD = 60.minutes` |
| M2 | Proactive sweep | `Activities::AgentCredentials::RefreshExpiringTokensActivity` (`:21`), `*/5` Temporal | `refreshable.refresh_due(15.minutes).without_live_session` |
| M3 | Cleanup merge-back | `AgentSessionStrategy#persist_refreshed_credentials` (`app/services/container_strategies/agent_session_strategy.rb:425`) | inside `before_cleanup` only |
| M4 | Launch gate | `SessionService#preflight_agent_credential!` | session launch, refuses a `status: error` row, and (until task #219, §7) an expired login a live session holds |

### Per-runtime coverage

| Runtime | Credential | Expiry known (`token_expires_at`) | Server-side `refresh!` | Who renews in practice | Gap |
|---|---|---|---|---|---|
| `claude_code` | `claudeAiOauth` or `platformOauth` (+ `platformProfile`) + `designOauth` + optional `primaryApiKey` | yes, soonest block | **yes** (`platform.claude.com/v1/oauth/token`; `platformOauth` via `api.anthropic.com/v1/oauth/token`; rotates) | us + the CLI in every container | multi-holder rotation |
| `codex` | `tokens.{access,refresh,id}` | yes (JWT `exp`) | **yes** | us + container | — |
| `cursor_cli` | `accessToken` + `refreshToken` | yes (JWT `exp`, 60 days) | **yes** — `api2.cursor.sh/oauth/token`, the endpoint the desktop IDE itself uses | us | fixed 2026-09-18; see §Cursor below |
| `kiro_cli` | SQLite `auth_kv` rows | yes | **yes** — Kiro social endpoint, or AWS SSO OIDC `CreateToken` for Builder ID / IdC | us + container | an IdC login dies at the directory's session cap (8h measured) whatever we do — see §3.2 |
| `antigravity_cli` | `token.{access_token,refresh_token,expiry}` | yes, consumer login only | **yes** — `oauth2.googleapis.com/token` with agy's consumer client (measured 2026-09-24: 3599s, refresh token not rotated), when `Settings.agents.antigravity` holds the client | us + container | Cloud-project login's client unverified: no expiry published, CLI renews it |
| `grok` | per-scope `{key, refresh_token, expires_at, oidc_issuer}` | yes | **yes** — `auth.x.ai/oauth2/token`, public client = the scope key's client id (`key` is the access token, 6h) | us + container | rotation not measured, declared `:rotating`; pre-OIDC logins without a refresh token are condemned at their expiry |
| `gemini_cli` | API key (encrypted blob) | no | n/a | n/a | none — static by design |

Sources: `app/services/agents/*_adapter.rb`, `AgentCredential::REFRESHABLE_AGENT_TYPES`
(`app/models/agent_credential.rb:53`), and the protocol notes in
`docs/research/technical-container-token-brokering-research-2026-09-05.md`.

### Blind spots

- **B1 — coverage is a literal.** `REFRESHABLE_AGENT_TYPES = %w[claude_code codex cursor_cli]`
  and `token_expires_at` are declared independently. A runtime can ship with an expiry and no
  refresh (that paints a working credential "expired" an hour after login) or with a refresh
  and no expiry (the sweep never selects it — exactly the `cursor_cli` `NULL`-expiry
  population PR #222 was opened for). Nothing fails the build in either case.
- **B2 — "held" is coarse and open-ended, and it is the measured production root cause.** M2
  and M1 both stand down whenever *any* active session row matches (user, company, agent).
  `TerminalSession.active` includes `ready`, whose stale threshold is **25 hours**
  (`Activities::Session::CleanupStaleActivity::READY_STALE_THRESHOLD`), while the Claude OAuth
  TTL is 8 hours. One forgotten interactive session pins the credential past its own expiry —
  see §3.1 for the production evidence.
- **B3 — an abnormal end loses the rotation.** The merge-back lives in `before_cleanup`, which
  runs on the normal path and on stale cleanup *when the container is still alive*. A pod that
  is OOM-killed, evicted or lost with its node is detected by `dead_container_scan_workflow`
  and taken to `SessionService.fail_session` — no scrape. Whatever the CLI rotated to inside
  that container is gone, and the refresh token we kept is the one the vendor already rotated
  out. Under reuse detection that can revoke the whole family, not just one token.
- **B4 — no history.** `refresh_error` (truncated to 500 chars) and `refresh_failure_count` are
  the entire record. Which block failed, against which endpoint, with what vendor payload, how
  far from expiry — none of it is kept, which is why the 2026-09-05 incident still cannot
  distinguish "rotated out from under us" from "aged out".
- **B5 — no signal to anyone.** `AgentCredentialResource#connection_status`
  (`app/resources/agent_credential_resource.rb:24`) derives from `expires_at` alone: a
  credential the sweep has condemned to `status: error` still renders **active** when its
  expiry is nil or in the future. There is no mailer for agent credentials (only
  `OauthMailer#refresh_failed` for `OauthCredential`), no metric, no alert.

---

## 3. Why it works locally and not in production

### 3.2 Refresh audit (investigated 2026-09-24, palad-prod)

Every credential row, the sweep's log in Sentry, and live containers, per runtime:

- **Every renewal now goes through `AgentCredential#renew!`** — sweep, launch top-up, and the
  web-side 401 retry in `fetch_available_models` (Cursor, Codex). It records the outcome
  (`clear_refresh_error!` / `mark_refresh_error!`) and reports each failure to Sentry as
  `AgentCredential::RefreshFailed` via `Rails.error` (source `agent_credential.refresh`,
  forwarded by `config/initializers/sentry.rb`, one issue per runtime × caller × permanent).
  Before, every failure was a `Rails.logger.warn` that reached Sentry only as an INFO log line,
  and the 401 path recorded nothing: 43 Cursor `Token refresh failed: 404` lines in 14 days,
  every Cursor row at `refresh_failure_count = 0`.
- **The `:held` guard applies only to rotating refresh tokens.** Cursor and Antigravity renew
  with a static refresh token, so a holder's copy stays valid and waiting for it to go quiet
  only lets the token expire.
- **Production lags develop.** The deployed image had neither the Cursor endpoint fix (#287)
  nor the `refresh_due` clause that selects rows whose `expires_at` was never derived, so 10
  Cursor, 3 Claude and 1 Kiro credential with long-expired tokens sat `active` with a NULL
  `expires_at`, never swept and never flagged.
- **Kiro IdC hits a hard cap.** Credential 121 (start URL `*.awsapps.com`, OIDC in us-west-2)
  was refreshed at 19:00, 19:05 and 19:10 and each time came back with the same expiry,
  19:13:51 — eight hours after the first token — and at 19:15 `CreateToken` answered
  `invalid_grant "Invalid refresh token provided"`. The refresh is correct; the directory's
  session duration ended the login, and only a new sign-in renews it.
- **Antigravity and Grok already renewed in the container** (a session on a four-day-stale
  Antigravity token ran and wrote back a fresh one; the Grok binary documents silent OIDC
  refresh), so server-side refresh closes the sweep gap rather than a runtime failure.
- Unrelated, found on the way: Antigravity sessions on the deployed image die on
  `--print took "--output-format" as its prompt` (fixed on develop, #260/#261), and two
  `gemini_cli` rows hold an empty blob.

### 3.1 What production actually does (investigated 2026-09-17, palad-prod)

The chain below was read off the production database and logs, and it is the reason this
document exists rather than a smaller fix:

1. A credential is skipped by both M1 (`:held`) and M2 (`without_live_session`) while any
   `active` session holds it. `ready` counts, and interactive `agent_session` / `auth_setup`
   sessions sit in `ready` until the 25-hour reaper.
2. **The token therefore dies while pinned, silently**: `refresh_error = nil`,
   `refresh_failure_count = 0`, because nothing ever attempted a refresh. Observed: credential
   19 (expiry 00:38) pinned 20 hours by `ready` session 16739; credential 99 pinned 20.8 hours
   by its own `auth_setup` session 16716. **Six `claude_code` credentials have since gone
   permanently `claudeAiOauth invalid_grant — reconnection required`.**
3. The next container launches with the dead token. Claude Code prints
   `Login expired · Please run /login` and produces nothing — M4 does not stop this, because
   the row is still `active`.
4. `ScanNoOutputSessionsActivity` cancels the session after 30 minutes. **355 such sessions in
   14 days, 138 of them (41%) carrying the auth banner** in `terminal_output.log`.
5. `CompleteStepActivity` fails a step only when `session.state == "failed"`; the watchdog
   leaves `cancelled`, so the step falls through to `mark_completed!`. **53 step runs completed
   on a cancelled or failed session in 14 days; 52 workflow runs reported COMPLETED with zero
   sub-steps done.**

So the damage is not only "auth keeps dropping". It is auth dropping *invisibly* and then being
reported as a green run — points 4 and 5 are adjacent to this design (they belong to the
watchdog and step-completion code) but they are the reason the credential failure went
unnoticed for two weeks, and they are listed in §5 so they are not lost.



Locally every agent on the machine reads and writes **one file** — `~/.claude/.credentials.json`
and friends. Whoever rotates the grant writes it back where the others read, so there is a
single writer and read-through for everyone.

In production the same grant is copied into every container at launch
(`SessionContextService` → `AgentCredential#write_to_container`), so the number of holders is
*containers + our database row*. Only the container writes back, only once, only at the end,
only on the happy path. Our copy is the stale one by construction, and the guards we added —
skip while held, merge per block, refuse to downgrade — reduce collisions without removing the
cause.

The invariant to restore is the local one:

> **One writer of the grant, and every holder reads through it.**

Two routes reach it:

- **(a) Make the database the shared file.** Containers keep the grant but write back
  *continuously*, not at cleanup. Vendor-agnostic, no unknowns, fixes B2 and B3 outright.
- **(b) Stop giving containers the grant.** The broker of
  `technical-container-token-brokering-research-2026-09-05.md`: a vending endpoint hands out a
  short-lived access token, the refresh token never leaves us. Strictly better, but it depends
  on vendor behaviour that is unverified (which header `apiKeyHelper` output is sent in;
  whether a credentials file is re-read mid-session) and it only applies to Claude today.

This design takes (a) now and keeps (b) as a measured follow-up.

---

## 4. The strategy

### Layer 0 — a declared lifecycle per runtime (the single mechanism) — **LANDED**

Add one descriptor to `BaseAdapter`, overridden by every adapter:

```ruby
# app/services/agents/base_adapter.rb
def credential_lifecycle
  {
    expiry:     :none,        # :token | :none | :unknown  — is an expiry readable from the blob?
    refresh:    :reauth_only, # :server | :container_only | :reauth_only
    rotation:   :static,      # :rotating | :static        — does a refresh invalidate the old grant?
    nominal_ttl: nil,         # documented vendor TTL, for the UI and for alert thresholds
    reauth:     :profile      # what the user must do when it dies
  }
end
```

What it buys, immediately:

- `REFRESHABLE_AGENT_TYPES` is **derived** from `refresh == :server`, not maintained by hand.
- A model test asserts every `CompanyMembership::AVAILABLE_AGENTS` entry declares one and that
  the illegal combinations cannot ship:
  - `expiry: :token` + `refresh: :reauth_only` is only legal when the runtime also declares
    that its status badge says "sign in again" rather than pretending a sweep will save it
    (the `grok` case, and the trap the 2026-09-17 survey found).
  - `refresh: :server` + `expiry: :none` is illegal — the sweep can never select it.
- Every surface (`connection_status`, preflight, sweep, admin, docs table above) reads one
  source instead of re-deriving the rules.

This is what makes the answer to "does every harness refresh?" mechanical instead of a survey.

### Layer 1 — fill the matrix — **landed**

| Runtime | Action | Where it stands |
|---|---|---|
| `kiro_cli` | land server-side refresh (social `refreshToken` + IdC `CreateToken`) | **done** — it now declares `refresh: :server` and the sweep selects it |
| `cursor_cli` | **done 2026-09-18** — the endpoint was found by reading the desktop IDE's own refresh code and confirmed against the live service; PR #222's `NULL`-expiry gate remains the complement | see §Cursor |
| `antigravity_cli` | Google `oauth2.googleapis.com/token` refresh with the consumer client | **done 2026-09-24** — pair verified against a live credential; needs `ANTIGRAVITY_OAUTH_CLIENT_ID`/`_SECRET` in the environment, never in the repo (secret scanning would get Google to revoke it for every agy user) |
| `grok` | `auth.x.ai/oauth2/token` refresh as the CLI's public client | **done 2026-09-24** — superseded the `reauth_only` declaration once production blobs showed the OIDC login stores a refresh token |
| `gemini_cli` | declare `expiry: :none` / static; keep the OAuth picker disallowed | done by design |
| `claude_code`, `codex` | nothing new | already both halves |

### Cursor: where the 404 actually came from

Our refresh had been answering 404 since 2026-09-05 and the reason was ours, not the
vendor's. Established on 2026-09-18 by logging in inside the freshly built image, probing
from there, and then reading the desktop IDE's bundle:

* the IDE's `_performAccessTokenRefresh` posts **JSON** to `${backendUrl}/oauth/token` with
  `backendUrl = https://api2.cursor.sh` and its own client id. Of the four things our call
  specified, only the path was right — the host, the encoding and the client id were not;
* `authenticator.cursor.sh` is a real OAuth server (its discovery document advertises the
  refresh_token and device_code grants, and its token endpoint is `/oauth2/token`), but it
  does not know our client id, nor the WorkOS client id cursor.com's web login uses;
* the token itself is a Cursor session JWT (`aud=cursor.com`, `type=session`), which WorkOS
  rejects — so the IdP was never the place to ask;
* the CLI never refreshes at all. Both the July and September bundles carry only
  `/auth/poll`, `/auth/exchange_user_api_key` and `/auth/cursor_dev_session_token`, and the
  refresh policy they share consumes an API key. Six months of production HTTP logs (119
  files, 2026-03-15 to 2026-09-15) show one auth endpoint, `GET /auth/poll`, and never
  `authenticator.cursor.sh` — which the domain filter would have captured.

The working call, confirmed live: `POST https://api2.cursor.sh/oauth/token`, JSON body
`{grant_type, client_id, refresh_token}`, answering `{access_token, id_token, shouldLogout}`
with a 60-day token and **no new refresh token**. The IDE stores that access token in both
slots, and so do we: the login's refresh token carries its own 60-day expiry, so keeping it
would let the credential die on schedule however often it was refreshed. `shouldLogout` is
the server ending the session and is treated as permanent.

What this leaves as the general lesson, and the reason the tracked-domain work above
matters: the old call was written from an OAuth template, its test stubbed our own URL, and
it was green for five months while failing every night in production. An adapter that talks
to a vendor is not working until it has been seen working on live traffic.

### Layer 2 — single writer in production (the core fix) — **2a and 2b landed, 2c open**

**2a. Live write-back.** The container already runs the watcher
(`docker/shared/watcher/index.js`), which already watches an auth path and already knows the
agent type. Extend it to watch the adapter's `auth_file_paths` **in agent sessions**, debounce
a few seconds, and POST the file contents to a new endpoint:

- authenticated by a derived per-session key — copy `CloudAuth::SessionKey`
  (`app/services/cloud_auth/session_key.rb`), which exists precisely so the MCP key is not
  reused for credential traffic;
- refuses a session that is not active, exactly as `CloudCredentialsController` does;
- server side reuses the cleanup path verbatim: `credential.with_lock` →
  `adapter.merge_refreshed_credentials(current, incoming)` → `AgentCredential.from_artifacts`,
  so the rotation guard and per-block merge already written apply unchanged.

This is the "one file" of the local setup, expressed as the database row. It removes B3
entirely (a pod that dies has already written back), and it keeps our copy fresh enough that
the sweep and the next launch stop handing out rotated-out grants.

**2b. Push a refreshed token back into the live container.** Write-back alone does not fix the
production case in §3.1, because an *idle* session rotates nothing: it just sits there holding
a copy while the clock runs out. The sweep must be allowed to refresh a held credential and
then hand the result to the holder — otherwise refreshing merely moves the invalid copy from us
to the container.

The delivery path already exists: `AgentCredential#write_to_container`
(`app/models/agent_credential.rb:192`) is exactly what launch uses. After a server-side
refresh, rewrite the credential files of every live container holding that credential.

One unknown gates how far this goes: **whether a CLI re-reads its credentials file mid-run**.
This is probe 3 of the broker research and it is cheap to run. Until it is answered, restrict
the push to sessions with no in-flight agent turn — which is precisely the idle-`ready`
population that causes the incident.

**What shipped in place of the first sketch of 2c.** The sweep no longer stands down on
every held credential. It splits them: a credential whose every holder has been silent for
ten minutes (`IDLE_BEFORE_REFRESH`, judged by the no-output check,
`Sessions::Checks::NoOutput`, on a snapshot of each holder read right before the rotation
through `Sessions::Monitor.snapshot`: by whether the screen changed for Kiro, by the log's
bytes for the other runtimes) is refreshed
and the result delivered; one with a holder mid-turn still defers, and
an unreadable container counts as working rather than as idle. That covers the incident
shape — a session parked for twenty hours — without rotating a grant under an agent that
is using it.

Delivery is the adapter's call (`BaseAdapter#deliver_credential`). Most runtimes keep the
token in a file of its own, and that file is written over. Kiro keeps it in a row of the
SQLite database the CLI holds open, next to state the CLI writes after launch, so writing
the stored blob over it would replace that database. Kiro instead runs a python3 script in the
container that updates only the `auth_kv` token row, inside a `BEGIN IMMEDIATE` transaction.
It keeps a row that the container has already renewed past the offered expiry. The token
reaches the script in a 0600 handoff file, not in argv, because a Kubernetes exec command is
part of the request URL.

**2c. A lease, still open.** The idle probe is an exec per holder per sweep and it says
nothing about a session that never goes quiet. The durable form is an explicit hold:

- the session records `held_until = now + 10.minutes`, refreshed by the same heartbeat that
  already proves the container alive;
- the sweep skips rows whose `held_until` is in the future, and *does* refresh a row whose
  holder stopped heartbeating.

A wedged or abandoned `ready` session then costs ten minutes of skipped sweeps, not
twenty-five hours, and no container has to be probed to find out.

**2d. One lock for every refresh: the refresh broker — landed (task #2731).** 2a and 2b made
the database the shared *file*; nothing made it the shared *lock*. On a laptop Claude Code
refreshes under `~/.claude/.oauth_refresh.lock`, and inside the lock it re-reads the
credentials file: if another process has already refreshed, it uses that result instead of
spending the refresh token again (read from the 2.1.281 binary). Each container has its own
lock, and the sweep stands down while a holder is mid-turn. So two busy containers crossing
an expiry together both spent the same single-use refresh token, the second one was logged out,
and its failed step took the run's other steps with it
(`docs/research/technical-graceful-agent-auth-expiry-research-2026-10-08.md`).

- **The proxy.** It runs in every agent image (`docker/base/logger/refresh_broker.py`) and
  hands any request to one of the adapter's `refresh_broker_endpoints` to
  `POST /agents/credentials/refresh`, using the write-back's session key.
- **The broker.** `Agents::RefreshBroker` decides under the refresh lease:
  - a refresh token the row still holds is refreshed for real;
  - one the row replaced within the last day is answered with the tokens that replaced it.
    Every write records the refresh tokens it replaces as SHA-256 digests in the credential's
    metadata (`AgentCredential#retire_replaced_refresh_tokens`);
  - an unknown token (a login made inside the container) goes on to the vendor;
  - a vendor `invalid_grant` is passed back to the CLI unchanged.
- **The fan-out.** Every write that replaces a refresh token starts
  `Workflows::AgentCredentialFanOutWorkflow`. Its activity delivers the new grant to every
  other live holder, and runs in the worker because only the worker has the container
  runtime. The CLI adopts the grant on its next 401, or inside its next refresh lock. The
  sweep's held path still delivers inline.
- **It fails open.** If the URL is unset, the endpoint is unreachable or slow (25 s), or the
  broker declines, the request goes to the vendor as before. Claude is the only runtime that
  declares broker endpoints so far.

Checked inside the agent image on mitmproxy 11.0.2:

- when the broker answers, the CLI gets the broker's answer;
- when the broker declines or is down, the request reaches the vendor;
- `mitm_logger.py`, loaded alongside, still drops both bodies.

Checked live on a local stack (2026-10-08). Two interactive Claude Code sessions shared one
login, and both were forced to cross its expiry at the same moment. One refresh reached
Anthropic. The second session waited on the lease and received the same new pair, and both
went on answering. A refresh made by one session alone was delivered to the other session's
container within a second.

Together these restore read-through in both directions: the container writes what it rotates,
we write what we rotate, the database is the file both sides share, and its row is the lock.

### Layer 3 — remove the second holder (measured, optional)

Only after Layer 2 is running and its event log (below) says whether rotation collisions still
happen. The probes are already specified in
`technical-container-token-brokering-research-2026-09-05.md` §"What to measure before
choosing": design-token ageing first (probe 4), then the `apiKeyHelper` header probe (1) and
the `ANTHROPIC_AUTH_TOKEN` probe (2). For anything the platform runs unattended, the API-key
path remains the strategic answer — an API key has no refresh token, so there is nothing to
race.

### Layer 4 — make expiry legible — **status, mail and HTTP capture landed; the event log open**

**What the proxy could and could not see (measured on production, 2026-09-17).** Every agent
image runs a MITM proxy and every runtime's traffic passes through it, but what reaches us is
decided twice — by `MITM_TRACKED_DOMAINS` and by whether the adapter collects the log at all.
Both were set so that no runtime's authentication was visible:

| runtime | sessions / 30d | `http.log` rows | hosts actually captured | auth traffic |
|---|---|---|---|---|
| `claude_code` | — | 621 | `api.anthropic.com` only | **none** — `platform.claude.com` was not tracked |
| `codex` | — | 5 | `chatgpt.com`, `ab.chatgpt.com` | **none** — `auth.openai.com` was not tracked |
| `cursor_cli` | 138 | 44 | `api2.cursor.sh`, `api3.cursor.sh` | **none** — the filter is a suffix match and Cursor's auth lives on `cursor.com` |
| `kiro_cli` | 22 | 9 | kiro.dev + amazonaws.com hosts | **yes**: `POST oidc.us-west-2.amazonaws.com/token` (21), `POST prod.us-east-1.auth.desktop.kiro.dev/refreshToken` (17), plus `client/register` and `device_authorization` |
| `antigravity_cli` | 51 | **0** | — | the adapter never collected the log |
| `gemini_cli` | 8 | **0** | — | nothing reached the proxy at all |
| `grok` | 11 | **0** | — | nothing reached the proxy at all |

Two conclusions worth keeping. Kiro's live traffic **confirms the protocol this branch
implements**, including that the IdC path answers on the registration's own region
(`us-west-2`) rather than the profile's. And `gemini_cli` / `grok` produce no records at all
despite the proxy being started and their adapters collecting the path — the likely cause is a
client that ignores `HTTP(S)_PROXY` (Node's `fetch`/undici does, on the image's Node 22), which
is its own investigation.

**Shipped here:** the auth hosts join each runtime's tracked domains, `antigravity_cli` starts
collecting its log, and — first, because the rest would be unsafe without it — the logger stops
writing credentials. Credential-bearing headers (`Authorization`, `Cookie`, `x-api-key`, …) are
replaced on every entry, which also closes a pre-existing exposure: API hosts carry the access
token on *every* request, so those tokens were already landing in stored session logs. An auth
endpoint's request and response bodies are dropped entirely and never buffered — that is where
refresh tokens live, and a refresh token is the whole grant rather than eight hours of one. The
endpoint, method, status and timing survive, which is what makes the lifecycle observable.

**Note:** the logger change is baked into the agent images, so it takes effect only after a
rebuild; the tracked-domain changes are app-side and take effect on the next session.


- **An event record per refresh attempt** (`credential_refresh_events`, or a structured log
  line plus a counter if a table is too much): credential, agent, block, trigger
  (`launch` | `sweep` | `container` | `cleanup`), outcome, vendor status + error code, expiry
  before and after, holder count at the time. This is the artefact that answers "when, why and
  how did it expire" without a binary dig or a Sentry archaeology session.
- **`connection_status` gains `error`** (done), the resource exposes `refresh_error` and
  `reauth_required` (done), and the profile prints the vendor's reason next to the badge.
  A condemned credential no longer renders as active.
- **A mailer on escalation** (done): `AgentCredentialMailer#refresh_failed`, sent once on
  the crossing into `error`, with the reason and a link to the profile.
- **Sweep counters per agent type** (`refreshed`, `not_needed`, `held`, `errors`) with two
  alerts: any agent erroring for N consecutive ticks, and an agent whose `held` ratio stays at
  100% (the lease is stuck — the exact shape of B2).

### Layer 5 — image and CLI freshness — **publishing, canary and versions landed**

- **`antigravity-cli` was missing from the `.github/workflows/images.yml` matrix** — the
  Makefile built it locally, CI never published it, so there was no
  `ghcr.io/aixlehq/flow-antigravity-cli` for production to pull. Added.
- **CLI versions.** Every runtime's CLI is pinned in `config/agent_runtimes.json`; a
  release reaches an image when someone raises the pin. Cursor and Kiro, whose vendor
  installers install only the latest release, are installed from the versioned package
  URL the installer itself downloads. Every image records its CLI version at
  `/etc/aixle-cli-version`.
- **A weekly canary build** (done) so a vendor-side auth change is found on a Monday
  morning rather than in a user's session. It builds the newest release of every pinned
  CLI (a green run says the pin can be raised), publishes only its own tags and never
  moves `latest` — promoting stays a human act.
- **A post-rebuild auth check per runtime.** A full login cannot be automated (device codes,
  browsers), so the check is two-part: an automated *shape* assertion that each image's CLI
  starts, reports the expected version, and creates its credential artefacts at the paths the
  adapter reads (`auth_watch_path`, `auth_file_paths`, `auth_required_keys`); and a manual
  per-runtime login pass against the freshly built images before they are promoted.

---

### Layer 6 — pause instead of dying — **landed (task #2731)**

A login that really cannot be renewed (its refresh token expired or was revoked) still has to
reach a person. Claude Code does not exit when that happens. It prints
`Login expired · Please run /login` and waits at its prompt, with the conversation and the
workspace intact. The no-output watchdog used to end that wait 30 minutes later, and the
deleted container took the work with it.

- **Detecting.** The per-minute snapshot `Sessions::Monitor` reads of each workflow step is
  also handed to `Sessions::Checks::AuthPause`, which takes `Sessions::AuthPause`'s actions
  (docs/architecture/workflows.md, "Session monitoring"). A session is paused when all three hold:
  - the adapter's narrow `auth_banner_pattern` appears in the last 40 lines;
  - no resume prompt comes after it;
  - the pane has been quiet for a minute.

  Pausing marks the session `auth_paused_at` and the run `paused`. The watchdog skips a paused
  session, and sibling steps keep running.
- **Healing.** A grant written in the last 10 minutes is delivered as it is. Otherwise the base
  login is refreshed and then delivered. Delivery types
  `Login renewed by Aixle. Continue the task from where you stopped.` into each paused holder.
  The run resumes once none of its steps is waiting.
- **Waiting for the owner.** A grant the vendor refuses condemns the credential, which sends
  the existing mail, and the step waits. The run page links to signing in again. A re-login
  replaces the refresh token, which fans out and resumes every paused holder.
- **Interactive sessions.**
  - The pane scan never reads them: it would cost an exec into every open session every
    minute. They are paused off the write-back instead. A refused CLI blanks its own block,
    the watcher posts it within seconds, and `ClaudeCodeAdapter#refused_login?` recognises it.
  - Nothing is typed into them, because a person may be typing there.
  - The session page says "The Claude Code login was refused" while the session waits, then
    "Login renewed — send your last message again" once a working grant has been delivered.
  - Checked live: the CLI took the delivered token on the next message, with no `/login`.
- **Giving up.** `AGENT_AUTH_PAUSE_LIMIT_MINUTES` (720) bounds the wait. After it, the session
  fails as before, as `auth_expired`.
- **Checked live (2026-10-08).**
  - A dead grant (the refresh token replaced with garbage) paused two parallel steps and their
    run. A re-login on Profile resumed both steps within a second, and each agent carried on
    from where it had stopped.
  - A refusal in one container, with the stored grant still good, paused that step. About two
    minutes later it healed and resumed with no one involved.
  - **Under load.** Three Haiku agents ran in parallel, each building a CommonMark converter
    against the spec, and all three were refused while busy.
    - The write-back signal paused each one 6–20 s after its refusal.
    - One re-login resumed all three.
    - One agent went from 218 to 241 of 652 examples straight afterwards: it continued its work
      rather than restarting it.
  - A hand-planted refresh token with the stored expiry was taken as a rotation and fanned out
    to every holder. A rotation must now carry a strictly later expiry.
  - The run surfaced three faults, all fixed in the same change:
    - a CLI's blanked block was being accepted on write-back, which lifted the credential out
      of `error`;
    - a terminal redraw was read as the agent working again;
    - a re-login after a refusal was not fanned out.
- **Declined: resuming in a new container.** `claude --resume` brings back the conversation
  but not the filesystem, and a new pod clones its repositories fresh. The research doc gives
  the reasoning.

## 5. Sequencing

| Phase | Work | State |
|---|---|---|
| **P0** | Refuse a launch on an already-expired credential; fail a step whose session ended `cancelled`; name the auth banner in the no-output watchdog | **done** |
| **P0** | Layer 0 contract + test; `error` in `connection_status` + mailer; kiro refresh | **done** |
| **P1** | Layer 2a write-back, 2b delivery to holders | **done** |
| **P1** | 2c lease (replacing the per-sweep idle probe) | open |
| **P1** | 2d refresh broker + fan-out to every holder; Layer 6 pause, heal and resume in place | **done** (task #2731); the broker needs the agent images rebuilt |
| **P2** | Layer 4 event log + sweep metrics | open — turns the next incident into a query |
| **P3** | antigravity refresh; the cursor 404; Layer 3 broker probes | open — each blocked on a live credential or a vendor answer |
| **P4** | Layer 5: publishing, canary, version file | **done**; the per-runtime login pass after a rebuild is manual and open |
| — | PR #222 (cursor `NULL`-expiry launch gate) | someone else's branch; it touches the same preflight, so it lands before or after this, not alongside |

## 6. How each phase is verified

- **P0** — a test that fails when a runtime ships an expiry without a refresh; a credential
  forced to `status: error` renders as error in the profile and sends one mail.
- **P1** — on staging: start a session, let the CLI rotate, kill the pod (no cleanup), and
  assert the stored blob already holds the rotated token (2a). Leave a session idle in `ready`
  past the token TTL and assert the container is running on a token the sweep minted (2b).
  Stop a session's heartbeat and assert the sweep refreshes that credential once the lease
  expires (2c). The §3.1 query — credentials whose expiry passed while `refresh_error` was
  still nil — must return zero rows afterwards.
- **P2** — replay the 2026-09-05 incident shape against the event log and confirm it
  distinguishes rotation from ageing.
- **P4** — rebuild all images, diff recorded CLI versions, run the login pass per runtime.

---

## 7. A launch while a holder carries the live token (task #219, 2026-11-21)

### 7.1 What happened

A step launch is refused with "Your Kiro Cli login has expired. Go to profile settings and
sign in again" while a running session already holds a working token, and nobody has to sign in
for the next launch to succeed. Seen twice: 2026-11-10 12:53:18 UTC (task #217, run 55269)
and 2026-11-21 14:09 UTC (task #271, run 80446). Production runs one to three Kiro sessions on one
credential almost all the time, so the window comes round about hourly.

The chain, from production Loki (task #219 description has the lines):

1. Kiro's token lives about an hour. Every launch finds a live holder, so
   `AgentCredential#refresh_if_expiring!` returns `:held` and logs "starting on N minutes of token life"
   (40, 28, 20, 11, 8 and 1 minutes in the 2026-11-10 window).
2. The sweep stands down each time: `a holder is mid-turn`
   (`RefreshExpiringTokensActivity#refresh_held`, rotating credentials only).
3. The stored copy expires. The next launch reaches `SessionService#preflight_agent_credential!`,
   and `AgentCredential#unrecoverably_expired?` (`base_login_expired?` + `rotating_refresh?` +
   `held_by_live_session?`) says "dead, and unrepairable because held", and refuses.
4. Seconds later a holder finishes and its cleanup (`persist_refreshed_credentials`) writes the
   token the CLI refreshed in the container. The stored copy is healthy again.

The refusal is wrong in its premise. The check assumes a held credential cannot be renewed,
while the holder's own copy is usually *the* live token and the stored copy is only stale
because nothing carried the holder's refresh back. Two defects stack: the live write-back
does not deliver (7.3), and the gate treats the stored copy as the only candidate (7.2).

### 7.2 The gate must look at the holders, not refuse

`unrecoverably_expired?` has three callers and one wrong rule:

| Caller | Context | Effect today |
|---|---|---|
| `SessionService.create_for_workflow_step` (`preflight_agent_credential!`, no session yet) | worker activity `LaunchStepSessionActivity` | the incident: the step fails in under a second |
| `SessionService.create_and_start` and `revalidate_admission!` | web request, and the admission phase | refuses an interactive launch; a queued session is cancelled |
| `AgentSessionStrategy#refresh_expiring_credential!` (`:held` + `base_login_expired?`) | container launch | second refusal site with the same premise |
| `ProjectTeams::Picker` | team member choice | treats the credential as unusable and skips the member |

**Decision: recover, then decide.** A new service `Agents::HolderRecovery`
(`app/services/agents/holder_recovery.rb`, next to `CredentialDelivery`) runs when a launch finds
the base login expired and live holders. It returns `:renewed`, or raises
`AgentCredential::PreflightError` with the right reason. In order:

1. **Pull.** For each holder with a container, `adapter.read_live_credential(runtime, container_id)`
   (new hook, 7.3) returns the credential as that container holds it, or `nil`. The result goes
   through the existing write-back rules under the row lock, exactly like the controller and the
   cleanup: `without_retired_grants`, then `merge_container_credentials` (same account, strictly later
   expiry, plausible expiry), then `AgentCredential.from_artifacts` inside
   `AgentCredential.rotating_for_session(holder.id)`. The freshest holder wins by the same
   comparison. If the base login is no longer expired, done.
2. **Idle holders: refresh and deliver.** If every holder is parked (the sweep's `parked?` test), the
   sweep would have refreshed on its next tick, so do it now: `renew!(source: :launch)`, then
   `Agents::CredentialDelivery`. This is the sweep's held path, extracted
   (`RefreshExpiringTokensActivity#refresh_held`, `#parked?`, `#deliver_to` move into the service and
   the activity calls it, so the two cannot drift).
3. **Busy holders: wait.** A holder mid-turn refreshes on its next request, because its token has
   expired. Poll step 1 every `POLL = 5.seconds` for at most `WAIT = 60.seconds`
   (a constant on the service, from the 3 s debounce + 15 s floor of the watcher plus margin).
4. **Last resort.** Still expired, so no holder has a live token. A holder stuck on the login banner
   is the usual case (`Sessions::AuthPause`). Now a server refresh is safe, since nothing live is
   running on a better grant: `renew!(source: :launch)`. Success starts the launch. A permanent failure
   condemns the credential through `record_refresh_outcome` as it does today and raises the existing
   sign-in message. A transient failure raises the new reason below.

Waiting needs the container runtime, which only the worker has, and a web request must not block for a
minute. So:

- `create_and_start` (web) keeps a cheap check only. It no longer refuses an expired login that
  holders carry: it refuses a login that is dead *now* (not refreshable, or condemned, as today) and lets
  a held one through. The session is created `queued`.
- `revalidate_admission!` and `create_for_workflow_step` run in activities and call the recovery.
  Implementation must confirm that the activities' start-to-close timeouts exceed the 60 s wait plus the
  launch work; if not, raise the timeout on those two activities, not the wait.
- `AgentSessionStrategy#refresh_expiring_credential!` keeps its `:held` branch as a backstop, but the
  message follows the same reason split. After recovery it should not be reachable with an expired base.

**`AgentCredential#unrecoverably_expired?` is renamed `login_dead?`** and loses the holders clause:
base login expired and the runtime has no server-side refresh (the case that really cannot be
repaired). `Picker` uses it, so a held, expired, refreshable credential no longer hides a team member.

**The message names the remedy.** `AgentCredential::PreflightError` gains `reason: :renewing`:

> Your Kiro Cli login is being renewed by a running session and could not be confirmed in time. Try again in a minute.

with no "profile settings" call to action. `:expired` ("sign in again") is raised only after a permanent
refusal by the vendor or for a login with no refresh path; `:unreadable` is unchanged. The controller and
the activity pass `e.message` through, so no UI change is needed. The reason is exposed as `e.reason` for the tests.

### 7.3 The live write-back must carry the CLI's refresh

Nothing in the logs shows Kiro's write-back ever changing the row: no
`took a kiro_cli token rotated in the container` line from 11:40 to 13:30, while holders refreshed. The
`POST /agents/credentials` 204s listed in the task are **not** evidence the Kiro watcher posted: the
endpoint answers every runtime, and a 204 is also the answer to an unchanged or rejected post.
Reading the code, four causes fit, and the design closes all of them because the logs cannot tell them apart:

| # | Cause | Where | Closed by |
|---|---|---|---|
| H1 | The state database is in WAL mode: a refresh lands in `data.sqlite3-wal`, the main file's bytes do not change, and the watcher reads only the main file | `docker/base/watcher/index.js` (`collect`, polling chokidar on one path) | reader below: a SQLite snapshot, which includes the WAL |
| H2 | The CLI writes the refreshed token only when it exits | the CLI | pull (7.2) reads the live token on demand |
| H3 | The post is accepted but the merge rejects it: `merge_container_credentials` demands the same `profile_arn` (`credential_identity`) and a strictly later expiry, and a container database with no profile row fails the identity test | `BaseAdapter#merge_container_credentials` | Kiro-specific merge below, and a logged reason on every rejection |
| H4 | The state database also holds the chat history, grows past 256 KB, and both the watcher (`CREDENTIAL_SYNC_MAX_BYTES`, silent `continue`) and the controller (`MAX_BODY_BYTES`, 413) drop it. Base64 adds a third on top | watcher, controller | the reader sends only the login rows |

`without_retired_grants` is not a cause for Kiro: `KiroCliAdapter` does not override `refresh_tokens`, so
it returns `{}` and drops nothing.

**Decision: report the login, not the database.**

- `BaseAdapter#read_live_credential(runtime, container_id)` (default: reads `auth_file_paths` through the
  existing container read and `extract_credentials`; returns `nil` on any failure). The Kiro override runs
  a python3 script like `TOKEN_SWAP_SCRIPT`: SQLite `backup()` of the state database into a temporary file
  (this reads the WAL and takes no lock the CLI waits on), then prints the `auth_kv` login rows and the
  `api.codewhisperer.profile` state row as a small SQLite file or JSON, base64. Nothing else leaves the container.
- The watcher gets the same read as an option. The adapter publishes the command in an env var
  (`CREDENTIAL_SYNC_READER`, next to `CREDENTIAL_SYNC_PATHS`, set where those are set in
  `agent_session_strategy`); when present, `collect()` runs it instead of reading the file, and it also
  watches the `-wal` file's mtime so a WAL-only change schedules a post. Other runtimes keep today's behaviour.
- `KiroCliAdapter#merge_container_credentials` is overridden: it takes the token row (and registration row)
  from the incoming login, applies the existing rules (same `profile_arn` when both have one, strictly later
  `expires_at`, `plausible_expiry?`), and splices it into the *stored* database with `blob_with_token`, the
  routine the server-side refresh already uses. The stored database is never replaced by a container's, so
  one session's chat history stops being written into the credential. A login with no profile row is
  accepted when the stored one has a profile (the stored profile stays).
- `BaseAdapter#merge_container_credentials` logs a reason when it returns `current` (`no_rotatable_keys`,
  `not_fresher`, `identity_changed`, `implausible_expiry`) at info, with the credential id. That is the
  answer to "why didn't it take", for every runtime, the next time.

The agent images carry the watcher, so the reader is live only after they are rebuilt (as in 2d). Until then
the pull in 7.2 is what keeps the launch working, and it needs no image change: the gate fix does not wait
for the rebuild.

### 7.4 The three questions

1. **Why the write-back did not carry the refresh.** Not established from logs. H1 and H4 are the
   likeliest (the Kiro CLI keeps one SQLite file the watcher reads whole, and a refresh happens inside a
   long-lived process); H2 and H3 cannot be excluded. The design does not depend on the answer: the pull
   covers all four, and the reader covers H1 and H4. **Implementation step 1 is the reproduction**
   (below), whose output goes into this section, so that the document says which one it was.
2. **When the CLI refreshes.** Not established. The one datapoint is session 58993: launched with 8 minutes
   of life (expiry about 12:52:46), its cleanup persisted a new token at 12:53:23, 37 s after that expiry.
   That fits refresh-on-expiry, not far ahead of it. The wait in 7.2 is sized for refresh-on-expiry: a
   busy holder refreshes within one request of the expiry, then the write-back adds 3 to 20 s.
3. **Parallel in-container refreshes of one grant.** Not established. Sessions 58993 and 59009 both started
   on the stored copy and both persisted a refreshed token with a later expiry (12:53:23 and about 13:06:28),
   so replaying the grant worked at least once. One datapoint does not show that Kiro's refresh token is not
   rotating (`credential_lifecycle` still declares `:rotating`). The design stays on the safe side: the pull
   comes before any server refresh, a server refresh with live holders happens only when all are parked
   (their copy is delivered right after) or when no holder has a live token, and the launch never refreshes
   under a busy holder.

### 7.5 Implementation steps

1. **Reproduce on Coder** (`coder_*`, a Kiro credential for a test user). Start a Kiro session on a login
   with under 2 minutes left and let it pass the expiry. Record: (a) `PRAGMA journal_mode` and the sizes of
   `data.sqlite3` and `-wal` over time; (b) when `auth_kv` changes relative to the expiry (answers 2);
   (c) whether the watcher posts (`Credential sync: reported`), and the controller's merge outcome with the
   new rejection log (answers 1); (d) start a second session on the same stored copy and see whether both
   refresh (answers 3). Paste results into 7.4. This is not a blocker for the other steps.
2. `BaseAdapter#read_live_credential` (default) and `KiroCliAdapter` override with its script; the
   `merge_container_credentials` reason log; the Kiro merge override.
3. `Agents::HolderRecovery`; move the held path out of `RefreshExpiringTokensActivity` into it.
4. `AgentCredential#login_dead?` (rename of `unrecoverably_expired?`, holders clause removed);
   `PreflightError reason: :renewing`; callers: `SessionService` (three sites), `Picker`,
   `AgentSessionStrategy#refresh_expiring_credential!`.
5. Watcher reader option and `-wal` watch; env var from the strategy. Image rebuild is a deployment step,
   not code.
6. Update this document's M4 row, 2b/2c text and Layer 4's sweep counters (add `recovered_at_launch`).

### 7.6 Testing

Minitest, factories, no `any_instance` or vendor stubbing (`.rubocop/cops/testing`). Container reads use
the existing fake runtime of `Agents::CredentialDelivery` tests.

- `test/services/agents/holder_recovery_test.rb`: **evidence 3** (stored Kiro token expired, one live
  holder whose container holds a later token): the launch is not refused and the stored row moves
  forward; a busy holder that has not refreshed yet, then does on the second poll (the wait; inject the
  clock and the poll interval, as the sweep tests do); all holders parked: refresh and delivery;
  no holder with a live token and a permanent refusal: `PreflightError` with `:expired`; the same with a
  transient failure: `:renewing`; an unreadable container counts as "no token", never as idle.
- `test/models/agent_credential_test.rb`: replace the three `unrecoverably_expired?` tests with `login_dead?`:
  expired and not refreshable is dead; expired and held is not.
- `test/integration/agent_credential_sync_test.rb`: **the live write-back stores a Kiro token the CLI
  refreshed**, using the existing `kiro_state` helper, with a post whose database holds only login rows and
  a later `expires_at`; and a post carrying a database with no profile row.
- `test/services/agents/kiro_cli_adapter_test.rb`: the merge splices into the stored database and leaves its
  other tables; refuses another account, an older token, an implausible expiry; logs the reason.
- `test/models/agent_credential_preflight_error_test.rb` (or the model test): the `:renewing` message has no
  "sign in".
- `test/temporal/activities/agent_credentials/refresh_expiring_tokens_activity_test.rb`: unchanged
  behaviour after the extraction.
- Watcher: its existing JS test, a case for the reader command and the WAL mtime.

### 7.7 Edge cases and risks

- **Two launches at once** both recover. The pull is idempotent (the second finds nothing later) and a server
  refresh goes through `with_refresh_lease`, which makes the later one wait for the first, as at launch today.
- **A holder in `finishing`**: `TerminalSession.active` includes it. Its container may vanish mid-pull; the
  read returns `nil`, and cleanup's own merge may arrive at the same time. Both go through `with_lock`.
- **A pulled token is older than the stored one** (the stored copy was refreshed by the sweep meanwhile): the
  merge keeps the stored one; no regression.
- **A compromised container** can post any login rows. The merge rules of `BaseAdapter` still hold, and the
  Kiro merge takes only the token and registration rows, never settings, tables or triggers
  (`blob_with_token` already refuses a database with `auth_kv` triggers).
- **The wait runs in an activity** holding a worker slot for up to 60 s per refused-to-be launch; bounded and
  rare (about hourly per credential).
- **Overlap with #273** (session lifecycle refactoring): this change stays in the credential preflight and the
  write-back and does not move session state. The three `SessionService` call sites change by one argument.
- **IdC logins** still die at the directory's session cap (§3.2); recovery ends in step 4 with a permanent
  refusal and the sign-in message, which is then correct.

### 7.8 Decisions and assumptions

| Decision | Source |
|---|---|
| Recover from holders and refuse only a really dead login | task #219 "What the fix must do" |
| Pull before refresh, never refresh under a busy holder | §3.1 and the 2026-09-05 incident (this document); question 3 is unanswered |
| Wait in the worker, not in the web request | `SessionService` call sites; the container runtime is worker-only (2d) |
| Kiro write-back carries the login rows, and the merge splices them into the stored database | H4 and the 256 KB caps in `docker/base/watcher/index.js` and `AgentCredentialSyncController` |
| Keep Claude, Codex and the others on the file write-back | not part of the incident; the default `read_live_credential` and `merge_container_credentials` stay |
| Step 1 reproduction cannot be done in this design session (no Kiro login on hand); it is the first implementation step | assumption |

### 7.9 Deferred

- The 2c lease (`held_until`), still open above. This design needs no hold marker.
- The refresh broker for Kiro (2d): needs question 3 answered first.
- Moving state out of `SessionService` (#273).
- Sweep counters and the event log (Layer 4) beyond the one counter added in step 6.
