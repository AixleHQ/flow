# Agent credential lifecycle: one contract for every harness

**Status:** design, with the first four layers implemented (branch
`artempartos/harness-cred-refresh-strategy`). Each section below marks what has landed and
what has not.
**Date:** 2026-09-17
**Scope:** the seven agent runtimes in `CompanyMembership::AVAILABLE_AGENTS`, their stored
credentials, and everything that reads, refreshes, injects or recaptures them.

Related: `docs/design/oauth-implementation.md` (as-built OAuth guide),
`docs/research/technical-container-token-brokering-research-2026-09-05.md` (the broker options),
`docs/design/grok-runtime-integration.md`.

---

## 1. The three questions this answers

1. **Does every harness actually refresh?** Today three of seven do, and the reason a given
   runtime does or does not is spread across a hardcoded list, an optional adapter method and
   two unmerged branches.
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
| M4 | Launch gate | `SessionService#preflight_agent_credential!` | session launch, refuses a `status: error` row |

### Per-runtime coverage

| Runtime | Credential | Expiry known (`token_expires_at`) | Server-side `refresh!` | Who renews in practice | Gap |
|---|---|---|---|---|---|
| `claude_code` | `claudeAiOauth` + `designOauth` + optional `primaryApiKey` | yes, soonest block | **yes** (`platform.claude.com/v1/oauth/token`, rotates) | us + the CLI in every container | multi-holder rotation |
| `codex` | `tokens.{access,refresh,id}` | yes (JWT `exp`) | **yes** | us + container | — |
| `cursor_cli` | `accessToken` + `refreshToken` | yes (JWT `exp`, 60 days) | **yes** — `api2.cursor.sh/oauth/token`, the endpoint the desktop IDE itself uses | us | fixed 2026-09-18; see §Cursor below |
| `kiro_cli` | SQLite `auth_kv` rows | no | no | container only | implemented on `feat/agent-token-refresh-coverage`, unmerged |
| `antigravity_cli` | `token.{access_token,refresh_token,expiry}` | no | no | container only | protocol recovered from the binary, client pair unverified |
| `grok` | `{key, token_type, expires_at}` per scope | yes | no — **no refresh token is stored at all** | nobody; only re-login | expiry shown with no way to act on it |
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

### Layer 1 — fill the matrix — **kiro landed; cursor and antigravity open**

| Runtime | Action | Where it stands |
|---|---|---|
| `kiro_cli` | land server-side refresh (social `refreshToken` + IdC `CreateToken`) | **done** — it now declares `refresh: :server` and the sweep selects it |
| `cursor_cli` | **done 2026-09-18** — the endpoint was found by reading the desktop IDE's own refresh code and confirmed against the live service; PR #222's `NULL`-expiry gate remains the complement | see §Cursor |
| `antigravity_cli` | implement Google `oauth2.googleapis.com/token` refresh; verify which embedded client pair the consumer login uses | needs one live credential to test |
| `grok` | declare `reauth_only`, surface "re-login required" instead of a silent expiry, refuse the launch | **done** — the declaration, the badge and the launch gate are in |
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
ten minutes (`IDLE_BEFORE_REFRESH`, read through the same pane the no-output watchdog
reads) is refreshed and the result delivered; one with a holder mid-turn still defers, and
an unreadable container counts as working rather than as idle. That covers the incident
shape — a session parked for twenty hours — without rotating a grant under an agent that
is using it.

**2c. A lease, still open.** The idle probe is an exec per holder per sweep and it says
nothing about a session that never goes quiet. The durable form is an explicit hold:

- the session records `held_until = now + 10.minutes`, refreshed by the same heartbeat that
  already proves the container alive;
- the sweep skips rows whose `held_until` is in the future, and *does* refresh a row whose
  holder stopped heartbeating.

A wedged or abandoned `ready` session then costs ten minutes of skipped sweeps, not
twenty-five hours, and no container has to be probed to find out.

Together the three restore read-through in both directions: the container writes what it
rotates, we write what we rotate, and the database is the file both sides share.

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
- **CLI versions.** Claude Code (through `claude.ai/install.sh`'s version argument),
  Codex, Gemini, Grok and Antigravity are pinned in their Dockerfiles; a release reaches
  an image when someone raises the pin. Cursor and Kiro come from vendor installers that
  install only the latest release — their install layers rebuild when the installer or
  its manifest changes, so identical Dockerfiles still produce different CLIs on
  different days for those two. Every image records its CLI version at
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

## 5. Sequencing

| Phase | Work | State |
|---|---|---|
| **P0** | Refuse a launch on an already-expired credential; fail a step whose session ended `cancelled`; name the auth banner in the no-output watchdog | **done** |
| **P0** | Layer 0 contract + test; `error` in `connection_status` + mailer; kiro refresh | **done** |
| **P1** | Layer 2a write-back, 2b delivery to holders | **done** |
| **P1** | 2c lease (replacing the per-sweep idle probe) | open |
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
