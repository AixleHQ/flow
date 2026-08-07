# MCP OAuth discovery in the wild — what the catalog's servers actually support

**Date:** 2026-08-07
**Trigger:** "Couldn't connect to this MCP server" when connecting the Vercel MCP connector, on production and locally alike.
**Status:** research complete; one fix landed with this report, three follow-ups proposed.

## Question

Connecting `com.vercel/vercel-mcp` fails. Is that Vercel, is that us, and — the part that
decides what we build next — how do the *other* remote MCP servers in our catalog expect a
hosted web application to authenticate?

## The Vercel failure, root-caused

Discovery reaches step (c) and dies there:

```
MCP::RegistrationError: unexpected status=400
  oauth_discovery_service.rb post_registration → register_client → prepare
```

Vercel's registration endpoint answers:

```json
{"error":"invalid_redirect_uri",
 "error_description":"The provided redirect URIs are not approved for use by this authorization server."}
```

Measured policy (one POST per row, against `https://api.vercel.com/login/oauth/register`):

| `redirect_uris` | result |
| --- | --- |
| `https://flow.aixle.com/oauth/callback` | 400 `invalid_redirect_uri` |
| `http://localhost:4000/oauth/callback` | 201 |
| `http://127.0.0.1:4000/oauth/callback` | 201 |

Vercel's DCR approves **loopback callbacks only**. Both loopback registrations returned the
same `client_id` (`cl_Wbdt…`), so it is a canned public client rather than a fresh
registration. The consequence is categorical: no hosted deployment — ours, a self-hoster's,
anyone's — can ever self-register with Vercel. Retrying, network debugging and egress rules
are all irrelevant. It is also not a CIMD case: Vercel's authorization-server metadata does
**not** carry `client_id_metadata_document_supported`, so our CIMD branch never engages and
we fall through to DCR.

The user-visible symptom was "Couldn't connect to this MCP server", which is what every
`MCP::DiscoveryError` rendered. That is actively misleading here — the server answered
promptly and correctly, it simply refused us — and it is what cost the most time in this
investigation.

## Method

Read-only survey against the mirror's own data (no registration attempted):

- `Connector.discoverable` with a remote target → **9,994 connectors over 7,171 distinct
  hosts**. Deduplicated by host, because a publisher farm with 1,311 entries behind one
  gateway is one authorization server, not 1,311 of them.
- Probed **178 hosts**: all 28 featured remote hosts, plus 150 sampled in `md5(name)` order
  (deterministic, so the sample is reproducible).
- Each host walked through `MCP::OauthDiscoveryService`'s own steps (a) and (b), so the survey
  sees exactly what a user's Connect click sees.
- A second pass re-probed the 93 hosts that never reached authorization-server metadata,
  recording the raw probe status and whether a `WWW-Authenticate` header was offered.
- A third pass compared three probe *shapes* (bare GET, GET with the MCP `Accept` header,
  POST `initialize`) against five hosts that had failed.

Raw data: `tmp/auth_survey.jsonl`, `tmp/auth_survey_probe.jsonl` (not committed).

## Findings

### 1. DCR is near-universally advertised — which says nothing about whether it works

Of the 85 hosts (48%) that reached authorization-server metadata:

| Mechanism | Hosts | Share |
| --- | --- | --- |
| `registration_endpoint` (RFC 7591 DCR) | 82 | 96% |
| `client_id_metadata_document_supported` (CIMD) | 17 | 20% |
| `device_authorization_endpoint` | 8 | 9% |
| Neither DCR nor CIMD | 1 (`api.githubcopilot.com`) | 1% |

Featured hosts behave the same: 19 of 28 reached metadata; 18 advertise DCR, 5 CIMD, 2 device.

Vercel is in the 96%. **Advertising a registration endpoint is not the same as accepting a
registration**, and nothing in the metadata distinguishes the two — the only way to know is
to POST and read the error. This is the central lesson for the product: our connect flow has
to treat "DCR refused us" as an expected, explainable outcome rather than a transport fault.

### 2. Our probe has the wrong shape for about a fifth of the catalog

The 93 hosts that never reached metadata, by what the probe actually got back:

| Probe result | Hosts | Reading |
| --- | --- | --- |
| 405 Method Not Allowed | 23 | our bare `GET` is refused outright |
| 406 Not Acceptable | 13 | no `Accept: text/event-stream` on our request |
| 401 Unauthorized | 15 | wants auth — but only 7 sent `WWW-Authenticate`, and only 4 of those carried a `resource_metadata` hint |
| 200 OK | 14 | server needs no OAuth at all |
| 404 / 400 / 403 | 16 | stale or wrong URL in the registry |
| transport failure | 12 | host unreachable from here |

The 405 + 406 group is 36 hosts — 20% of the sample, 39% of the failures — and it is our bug,
not theirs. Confirmed by comparing probe shapes:

```
https://mcp.grafana.com/mcp
  GET bare            -> 302                     (the redirect swallows the 401)
  GET accept sse+json -> 401 WWW-Auth[Bearer resource_metadata="…/.well-known/oauth-protected-resource/mcp"]
  POST initialize     -> 401 WWW-Auth[Bearer resource_metadata="…"]
```

A bare GET loses Grafana's hint twice over: no `Accept` header, and a 302 that our redirect
follower chases away from the 401 that carried the answer.

### 3. Our protected-resource fallback is not RFC 9728 path-aware

When the probe yields no hint, we fall back to `origin + /.well-known/oauth-protected-resource`.
RFC 9728 §3.1 inserts the well-known segment *before* the resource path, so the correct
fallback for `https://mcp.grafana.com/mcp` is
`https://mcp.grafana.com/.well-known/oauth-protected-resource/mcp` — which exists (200), while
our origin-level guess does not. Fixing finding 2 recovers Grafana via the hint; fixing this
recovers the servers that send no hint at all.

Not every failure is ours: `mcp.atlassian.com` returns a `WWW-Authenticate` with no
`resource_metadata` parameter, and **both** protected-resource URLs 404. Discovery genuinely
cannot proceed there — Atlassian is a manual-client case like Vercel.

### 4. Device flow is not the general escape hatch

Only 8 of 85 hosts (9%) advertise `device_authorization_endpoint`. It is real for a few named
providers — Vercel and Hugging Face among them — but it cannot be the answer for a catalog
where 96% speak DCR. CIMD is the mechanism actually heading in our direction: 20% today,
including `mcp.linear.app`, `mcp.notion.com`, `mcp.airtable.com`, `mcp.posthog.com` and
`huggingface.co`, and it is what MCP spec `2026-07-28` promotes as DCR's replacement. We
already implement it and already prefer it.

## What landed with this report

`MCP::DiscoveryError` now carries a `user_message` and an allowlisted `code`, and
`Web::OauthController#mcp_connect` shows the message instead of one fixed sentence. The
registration path extracts the RFC 7591 error code from the failure body — through
`RegistrationError::MESSAGES`, which is simultaneously the allowlist, so an authorization
server can never put its own prose in front of a user or into our logs. The Vercel case now
reads: *"This server's authorization server does not accept this deployment's callback URL, so
an operator has to register a client ID for it."*

## Follow-ups 1 and 2, done — and measured

Both landed right after this report: the probe now sends the streamable-HTTP `Accept` header
and retries with an MCP `initialize` when a server refuses the shape (400/404/405/406), and
the protected-resource fallback tries the RFC 9728 path-aware url before the origin-level one.

**Re-running all 93 previously-failing hosts against the fixed code: 2 now reach
authorization-server metadata** — one of them `mcp.grafana.com`, a featured connector.

That is far less than the "a fifth of the catalog" this report first projected from the
405/406 count, and the correction matters more than the fix does. Those hosts were not
gated servers we were probing wrongly; **most of them want no OAuth at all**. The evidence
was already in the second-pass data and was misread: 14 answered the probe with a plain 200,
and `docs.mcp.cloudflare.com` answers a POST `initialize` with 200. A 405 to a bare GET was
a transport-shape complaint from an open server, not a hidden auth challenge.

What the fix genuinely buys, then, is **accuracy**: 69 hosts moved from
`FetchError` ("couldn't connect") to `NoAuthServerError` ("this server did not advertise an
OAuth authorization server"), which is both true and actionable, and Grafana-class servers —
ones that really are gated and really do publish a challenge, just not to a bare GET — now
work. 22 remain genuine transport failures (dead hosts, stale registry urls).

## Proposed follow-ups

1. **A manual client per MCP server** for the servers that will never accept DCR (Vercel,
   Atlassian) — **decided and built, 2026-08-07.** A `client_id` is bound to a `redirect_uri`,
   hence to one deployment's domain, so no shared client can ever be shipped: every operator
   needs their own OAuth app at the provider. The existing `Oauth::Providers` registry does
   this for Sentry and Railway, but it is hard-coded per provider and configured through
   Settings, which makes every self-hoster wait on us to add an entry. Chosen shape instead:
   when discovery fails with a code that means "an operator must configure this"
   (`invalid_redirect_uri`, `no_registration_endpoint`), say so on the spot and offer the
   fields — client ID and secret — against that MCP server, persisted as an
   `OauthClient(source: "manual")`. Endpoints still come from discovery; only the credentials
   are hand-entered. One implementation covers Vercel, Atlassian and every future refusenik,
   with no code per provider. Shipped as `OauthClient(source: "manual")` scoped to one
   `mcp_server` — a tenancy rule, not a preference: those credentials belong to whoever pasted
   them, and another tenant's users must never authorize into that OAuth app. The callback
   enforces the same thing, refusing a manual client whose server does not match the signed
   state.
2. **Device flow** only if a named provider justifies it; the data does not support building
   it as a general fallback.

## Open question

How many of the 82 DCR-advertising hosts actually accept a hosted (non-loopback) redirect URI?
The metadata cannot answer it and the survey deliberately did not: finding out means POSTing a
real client registration to each third-party authorization server. Worth doing for the
featured subset if we need the number, but it is an outward-facing action on someone else's
infrastructure and should be an explicit decision.
