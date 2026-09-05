# Keeping OAuth refresh tokens out of agent containers

**Status:** research, no implementation proposed yet
**Date:** 2026-09-05
**Origin:** the 2026-09-05 production incident (PRs #203, #204)

## The question

Today every agent container receives the user's full Claude credential blob, refresh token
included: `ClaudeCodeAdapter#config_files` writes both OAuth blocks into
`~/.claude/.credentials.json` for every session, not only for sessions that need them. The
CLI inside the container can therefore rotate the grant whenever it renews, and it does so
invisibly to us — the rotated block only comes back at session cleanup, via
`AgentSessionStrategy#persist_refreshed_credentials`.

That makes the number of holders of one single-use refresh token equal to the number of
running containers plus our own copy in the database. Whichever holder renews first rotates
the family; every other holder is then carrying a grant the server rejects. The 2026-09-05
incident is what that looks like in production: four credentials dead, three of them with a
perfectly valid base login, killed by an expired `designOauth` add-on.

The mitigations already shipped — a sweep that skips credentials a live container holds, a
pre-launch top-up, per-block invalidation instead of condemning the whole row — reduce the
number of collisions. They do not remove the cause. The question this document answers is
whether the cause can be removed: **can the container be given a short-lived access token
instead of a refresh token, with our platform holding the grant?**

## The constraint that comes first

The technical answer is not the binding one. Prior research (2026-07-09/10, two adversarial
workflows plus live probes) established Anthropic's position, anchored on the live license
section of `code.claude.com/docs/en/legal-and-compliance`:

> Anthropic does not permit third-party developers … to route requests through Free, Pro, or
> Max plan credentials **on behalf of their users**.

Three findings from that research bear directly on this design:

1. **The prohibited axis is who operates the routing**, not the binary or the user's consent.
   A vending endpoint operated by us is the *same* activity as our current capture-and-inject,
   expressed with different plumbing. It neither improves nor worsens the ToS posture.
2. **Anything the platform runs unattended should use an API key.** The Consumer Terms
   carve-out is API-key-only; a subscription OAuth token is not an API key.
3. **A user's own `claude setup-token` on their own infrastructure is tolerated but is not
   ours to route.**

The practical consequence: this work cannot be justified as reducing legal exposure, because
the exposure is in what we already do. It can only be justified as reliability engineering,
and on the API-key path the whole problem disappears — an API key has no refresh token, so
there is nothing to rotate and nothing to race.

## What Claude Code actually supports

From `code.claude.com/docs/en/authentication` (fetched 2026-09-05). Credential precedence,
highest first:

| # | Source | Header | Notes |
|---|---|---|---|
| 1 | Cloud provider (`CLAUDE_CODE_USE_BEDROCK` etc.) | provider's own | what our Bedrock path uses |
| 2 | `ANTHROPIC_AUTH_TOKEN` | `Authorization: Bearer` | documented for LLM gateways/proxies |
| 3 | `ANTHROPIC_API_KEY` | `X-Api-Key` | |
| 4 | `apiKeyHelper` script output | **not documented** | "for dynamic or rotating credentials, such as short-lived tokens fetched from a vault" |
| 5 | `CLAUDE_CODE_OAUTH_TOKEN` | — | `claude setup-token`, 1-year |
| 6 | Anthropic profile / federation | — | |
| 7 | Subscription OAuth from `/login` | — | what we inject today |

Relevant mechanics:

- **`apiKeyHelper` is re-run every 5 minutes** by default, tunable with
  `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`. A helper slower than 10 seconds shows a warning in the
  prompt bar; a helper that errors, times out, or prints nothing fails the request within
  three attempts.
- **Settings reload live.** Claude Code watches settings files and applies edits to a running
  session without a restart, credential helpers included. Environment variables do not reload.
- **Credentials live in `.credentials.json`** under `CLAUDE_CONFIG_DIR`, managed by
  `/login` / `/logout`.
- Anthropic's own guidance notes that **an unattended session that outlives its login stops
  making progress** and cannot recover without a fresh sign-in — the same failure our users
  hit from the other direction.

## The precedent we already operate

We have built this exact broker once already, for AWS:

- `CloudCredentialsController` vends credentials to the container, authenticated by a derived
  per-session key (`CloudAuth::SessionKey`) rather than the session's MCP key, and refuses to
  vend for a session that is no longer active.
- `CloudAuth::AwsCredentialVendor#to_credential_process_json` renders the response.
- The container side is a `credential_process` helper named in `~/.aws/config`
  (`ClaudeCodeAdapter#aws_config_file`), so the AWS SDK calls out and pipes the result back.

The topology, the auth model, the "only a live session vends" rule, and the failure logging
are all already proven in production. An `apiKeyHelper` broker for Anthropic tokens would be
the same shape with a different helper and a different vendor.

## The three options

### A. `apiKeyHelper` + vending endpoint

The container gets a helper script instead of a refresh token. The helper posts to us with
the session key; we return an access token minted from the grant we hold. The refresh token
never leaves our infrastructure, so no container can rotate it and the multi-holder race
disappears entirely. The 5-minute re-run cadence also fixes sessions longer than the token's
life — the `exec` phase allows 23 hours (`signal_timeout: 82_800`) against an 8-hour token.

**Blocking unknown:** the docs never state which header the helper's output is sent in. The
setting is described throughout as producing an "API key" / "API credential", which suggests
`X-Api-Key`. A subscription OAuth access token must be sent as `Authorization: Bearer` with
`anthropic-beta: oauth-2025-04-20`; sent as an API key it will not authenticate. Worse, the
Feb-2026 anti-spoofing change blocks `sk-ant-oat01-*` tokens presented outside the genuine
harness, so the failure may be deliberate rather than incidental. If the helper's output is
API-key-shaped, option A works **only** on the API-key path — where, as noted above, the
problem it solves no longer exists.

### B. `ANTHROPIC_AUTH_TOKEN` with no refresh token

Inject only the access token, as an environment variable, and stop writing
`claudeAiOauth.refreshToken` into the container at all. This is `Authorization: Bearer`, which
is the correct header for an OAuth access token, and it outranks everything below it in the
precedence list.

**Cost:** environment variables do not reload, and there is no refresh token in the container,
so the session dies when the token expires — a hard 8-hour ceiling against a 23-hour phase
timeout. Long sessions would need a different mechanism (rewriting the credentials file
mid-session, which the CLI may or may not re-read).

### C. Change nothing structural

Keep injecting, keep the mitigations from #203/#204, and let the new diagnostic logging say
whether rotation is actually the mechanism. Cheapest, and the honest default until the probes
below have run.

## What to measure before choosing

Each of these is a staging experiment, not a production change:

1. **Header probe (decides A).** Configure `apiKeyHelper` to print a subscription OAuth access
   token in a staging container and make one model request. A 401 means the output is sent as
   `X-Api-Key`, and option A is dead for subscription tokens. Success means A is viable.
2. **Bearer probe (decides B).** Set `ANTHROPIC_AUTH_TOKEN` to a subscription access token, no
   `.credentials.json` at all, and make one model request. This also tells us whether
   anti-spoofing rejects an `oat01` token presented outside the normal credential store.
3. **Mid-session reload probe (rescues B).** With a live session, rewrite
   `.credentials.json` from outside and see whether the CLI picks up the new token without a
   restart. Settings files reload; the credentials file is not documented as doing so.
4. **Design-token lifetime probe (independent).** Mint a `designOauth` token on staging, run no
   containers for 24 hours, and see whether the sweep alone keeps it alive. This separates
   "rotated out from under us" from "the grant aged out" — the two hypotheses the incident data
   still cannot distinguish, and the reason PR #204 added block/age/expiry to the failure log.

Probe 4 is worth running first: if design tokens simply age out, the multi-holder race is not
the mechanism behind the incident and options A and B are solving the wrong problem.

## Recommendation

Do not build the broker on the strength of the incident alone.

- Run probe 4 and read the new `block=… credential=… expiresAt=…` log lines from #204. They
  cost nothing and they decide whether there is a race to engineer against.
- Run probes 1 and 2 next; they are each a single request and they collapse the design space
  to at most one viable option.
- Treat the API-key path as the strategic answer for anything the platform runs unattended.
  It is what the ToS research already prescribes, and it removes this class of failure
  outright rather than reducing its frequency.
- If a broker is built anyway, build it as a copy of the AWS one — same session-key auth, same
  live-session-only rule, same failure logging — rather than as a new mechanism.
