# Aixle runner protocol, version 1

The wire contract between `aixle-runner` and the platform's runner gateway. This document
describes protocol `1` as the gateway implements it today, and nothing it does not implement
yet. Later endpoints and ops each add their own section here, with their fixtures, in the task
that builds them (§8).

- **This document is the source of truth for the wire.** The design and its rationale are in
  `docs/design/agent-runtimes/DESIGN.md` §6 and §9. Where the two say the same thing, this
  document wins.
- **The conformance fixtures** in [`fixtures/v1/`](fixtures/v1/) pin this behaviour, in the
  format [`fixtures/README.md`](fixtures/README.md) describes. The gateway's Rails tests run every
  one of them (`test/integration/runner_protocol_conformance_test.rb`), so a change to a status,
  an error code or a response shape fails CI. The README lists the few clauses that are verified
  outside the fixtures, such as the `413` and the `429`.
- **Self-contained.** Nothing here needs the Rails code. The protocol lives with the runner,
  under `runner/`, and the runner's code is written against this directory, never against
  the gateway's code (DESIGN.md §14.1).

## 1. Transport

- **HTTPS**, to the platform's host on port 443. Every path is under `/runner/v1/`.
- **JSON bodies** in UTF-8, sent with `Content-Type: application/json`. Keys are `snake_case`.
- **Timestamps** are ISO 8601 strings in UTC with a `Z` offset, to the second:
  `2026-10-31T14:00:00Z`.
- **No cookie session and no CSRF token.** The gateway sets no cookie.
- A path the gateway does not serve answers `404`.

Every request carries these three headers:

| Header | Value | Refused with |
| --- | --- | --- |
| `Authorization` | `Bearer <token>`, the token kind the endpoint takes (§4) | `401 invalid_token` |
| `X-Aixle-Runner-Protocol` | `1`, exactly | `400 unsupported_protocol` |
| `X-Aixle-Runner-Version` | The runner's own version, in the grammar below (`1.4.0`, `1.5.0-rc.1+build.7`; no `v` prefix) | `400 invalid_runner_version` |

**The version grammar the gateway accepts.** `MAJOR.MINOR.PATCH`, then an optional
`-PRERELEASE`, then an optional `+BUILD`:

- `MAJOR`, `MINOR` and `PATCH` are each one or more ASCII digits. Leading zeros are accepted.
- `PRERELEASE` and `BUILD` are each one or more characters of `0-9`, `A-Z`, `a-z`, `.` and `-`.
  Empty identifiers and numeric identifiers with leading zeros are accepted.

So the gateway accepts some values that [Semantic Versioning 2.0](https://semver.org) refuses, such
as `01.2.3`, `1.2.3-01` and `1.2.3-..`, and refuses `1.4`, `v1.4.0`, `1.2.3-` and `1.2.3+`. A
runner sends a strict SemVer 2.0 version, which this grammar always accepts. The gateway
requires strict SemVer 2.0 once the version skew policy (DESIGN.md §14.4) is built.

## 2. Limits

- **Body size: 2 MiB.** A request body over 2 MiB, chunked bodies included, is answered `413` by
  the gateway's HTTP server before the application reads it. That `413` does not have the JSON
  refusal shape.
- **Rate limits**, each counted over a fixed 60-second window:

  | Limit | Counted per | Applies to |
  | --- | --- | --- |
  | 600 requests a minute | bearer token | every `/runner/v1/*` request |
  | 3000 requests a minute | client IP | every `/runner/v1/*` request |
  | 30 requests a minute | client IP | `POST /runner/v1/register` |

  A request over a limit is answered `429` with a plain-text body, not the JSON refusal shape,
  and no `Retry-After` header. A runner at rest makes one request every 25 s (the long-poll), so
  it stays far below these limits.
- **Caching.** Every response that carries a token (`register` and `token`) and every `GET ops`
  response has `Cache-Control: no-store`.

## 3. Refusals

A refusal is a JSON object of two strings:

```json
{ "error": "invalid_token", "message": "The token is unknown, used, revoked or expired." }
```

`error` is the machine-readable code and the contract. `message` is for people and may change.
These are the only refusals without this shape:

- `413`, for a body over the cap (§2);
- `429`, for a request over a rate limit (§2);
- a `404` for a path the gateway does not serve;
- a `400` for a `POST /register` or `POST /ops/:id/result` body that is not valid JSON. Its body
  is an HTML page or `{"status": 400, "error": "Bad Request"}`, depending on `Accept`. That
  `error` is not a code of the table below. The body is parsed after steps 1 to 4 of the check
  order, so a malformed body with a bad header, token, runner or flag gets that refusal
  instead.

| `error` | Status | Endpoints | Meaning |
| --- | --- | --- | --- |
| `unsupported_protocol` | 400 | all | `X-Aixle-Runner-Protocol` is missing or not `1`. The message names the version the gateway speaks. |
| `invalid_runner_version` | 400 | all | `X-Aixle-Runner-Version` is missing or not a semantic version. |
| `invalid_request` | 400 | `GET ops` | `after` or `wait` is malformed or out of range (§5.4). |
| `invalid_token` | 401 | all | The token is unknown, of the wrong kind for the endpoint, revoked, expired, already used (a registration token), or of an unregistered machine. |
| `runner_revoked` | 401 | all | The token is valid, but its runner is revoked or deleted. |
| `credential_reuse_detected` | 401 | `token` | A refresh token was presented a second time. Its whole family is now revoked (§4). |
| `runners_disabled` | 403 | all | External runners are turned off for the runner's company. The credentials stay valid. |
| `not_found` | 404 | `ops/:id/result` | The op does not exist, or belongs to another machine. |
| `ephemeral_not_supported` | 422 | `register` | The body asked for `ephemeral: true`. |
| `invalid_registration` | 422 | `register` | The body is invalid: a blank or missing `name`, `facts` that is not an object (`null` included), or a field over 255 characters. An `X-Aixle-Runner-Version` over 255 characters is refused this way too, since it is recorded with the machine. |
| `invalid_result` | 422 | `ops/:id/result` | The result body is invalid (§5.5). |

**Check order.** Every request is checked in this order, and the first failure answers:

1. `X-Aixle-Runner-Protocol`, then `X-Aixle-Runner-Version`. They are checked before the token, so
   a bad header is reported even with a bad token.
2. The token: known, of the endpoint's kind, unrevoked, unexpired, not of an unregistered
   machine and, for a registration token, unused. Anything else is `invalid_token`, before the
   runner or the flag is looked at, so a dead token learns nothing about either. The one
   exception is a spent refresh token: it passes this step, even past its own expiry, so that
   `POST /token` can answer `credential_reuse_detected` (§4).
3. The runner's status: revoked or deleted is `runner_revoked`. The gateway caches this check for
   up to 5 seconds, so a revocation reaches it within 5 seconds.
4. The `external_runners` flag for the runner's company: off is `runners_disabled`.
5. The endpoint's own parameters and body.

Revoking a runner also revokes every token it has, so after a revocation its tokens are usually
refused at step 2 with `invalid_token`. `runner_revoked` is what a runner sees inside the window
before that, or when `register` or `token` race a revocation.

**After the long-poll's wait.** A `GET ops` that waited (`wait` above 0) runs steps 2 to 4 again
before it answers. A token revoked, a machine unregistered or the flag turned off during the wait
then gets the refusal, not the ops (§5.4).

### What a runner does on each refusal

| Refusal | The runner |
| --- | --- |
| `401 invalid_token` from an endpoint that takes the access token | Refreshes once (`POST /token`) and retries with the new access token. If the refresh is refused with `401`, the credentials are dead: it stops and asks for re-registration. |
| `401 invalid_token` from `POST /token` | Stops and asks for re-registration. The machine's credentials are gone (unregistered, revoked or unused for 30 days). |
| `401 invalid_token` from `POST /register` | Reports that the registration token is unknown, used or expired, and asks the operator for a new one. It does not retry. |
| `401 credential_reuse_detected` | Deletes its stored credentials and stops: someone else held its refresh token. Re-registration is required. |
| `401 runner_revoked` | Stops. The runner was revoked or deleted; the machine can only join again by registering with a new token of a live runner. |
| `403 runners_disabled` | Keeps its credentials, backs off and retries. Once the company's runners are enabled again, the same tokens work. |
| `429` | Backs off and retries. The windows are 60 seconds long. |
| `413` | Does not resend the same body. |
| `400 unsupported_protocol`, `400 invalid_runner_version` | Stops and reports that `aixle-runner` must be updated. Retrying cannot succeed. |
| `400 invalid_request`, `422 invalid_result` | A bug in the runner: it reports it and does not resend the same request. |
| `400` without the JSON refusal shape | A bug in the runner, which sent a body that is not valid JSON: it reports it and does not resend the same body. |
| `422 ephemeral_not_supported`, `422 invalid_registration` | Reports the problem with its configuration. The registration token is not spent, so `configure` can be run again with the same token once the input is fixed. |
| `404 not_found` from a result | Drops that result: the op is not this machine's. |

"Backs off" means retrying with increasing delays, with jitter, so that a fleet of machines does
not retry in step.

## 4. Tokens

Tokens are opaque strings with a prefix by kind, so a leaked one is recognisable. A runner must
not parse anything after the prefix. The gateway stores only a digest of each token: a token is
returned once, by the response that issues it.

| Kind | Prefix | Issued by | Lifetime | Sent to |
| --- | --- | --- | --- | --- |
| Registration | `arreg_` | The platform, for a `manual` runner ("Add machine") | Single use, valid for 1 hour | `POST /register` |
| Access | `aracc_` | `register` and `token` | 1 hour | `DELETE /registration`, `GET /ops`, `POST /ops/:id/result` |
| Refresh | `arref_` | `register` and `token` | 30 days, and spent by its one use | `POST /token` |

The rules:

- **A registration token registers one machine.** It is spent only by a registration that
  succeeds, so a refused `register` (bad headers, `422`, flag off) leaves it usable. A second use,
  or a use after 1 hour, is `invalid_token`.
- **An access token is valid for 1 hour.** `access_token_expires_at` says when. A runner
  refreshes before that time, or on an `invalid_token` from an access endpoint.
- **A refresh token rotates on every use.** `POST /token` spends it and returns a new access and
  refresh pair of the same family. The runner stores the new pair before it uses it, and from
  then on presents only the new refresh token. The previous access token stays valid until its
  own expiry.
- **A refresh token not used for 30 days expires.** `refresh_token_expires_at` says when. Using it
  after that is `invalid_token`.
- **Reusing a refresh token revokes its family.** A spent refresh token presented again means two
  holders have it: the gateway answers `credential_reuse_detected` and revokes every token of the
  family, the newest pair included. This holds even after the spent token's own 30-day expiry.
- **Unregistering revokes every token of the machine** (`DELETE /registration`), and revoking or
  deleting the runner revokes every token of every one of its machines.

A runner keeps its tokens in a file only its own user can read, and never logs them.

## 5. Endpoints

| Endpoint | Token | Answer |
| --- | --- | --- |
| `POST /runner/v1/register` | registration | `201` with the environment and a token pair |
| `DELETE /runner/v1/registration` | access | `204` |
| `POST /runner/v1/token` | refresh | `200` with a token pair |
| `GET /runner/v1/ops` | access | `200` with up to 20 ops |
| `POST /runner/v1/ops/:id/result` | access | `200` with the op's state |

Each endpoint can also answer the refusals of §3 for every endpoint (`unsupported_protocol`,
`invalid_runner_version`, `invalid_token`, `runner_revoked`, `runners_disabled`, `413`, `429`).
The refusals listed below are the endpoint's own.

### 5.1 `POST /runner/v1/register`

`aixle-runner configure` on a `manual` machine: spends the registration token and creates the
machine, which the platform calls an environment.

| Field | Type | Rule |
| --- | --- | --- |
| `name` | string | Required. Leading and trailing spaces are dropped, and it must not be blank then. At most 255 characters. |
| `os` | string | Optional, at most 255 characters, e.g. `linux`. A value that is not a string is ignored. |
| `arch` | string | Optional, at most 255 characters, e.g. `amd64`. A value that is not a string is ignored. |
| `facts` | object | Optional, default `{}` when the key is absent. What the machine reports about itself, e.g. `{"docker": "27.1.0"}`. Omit it or send an object: `null` is refused with `invalid_registration`. |
| `ephemeral` | boolean | Optional, default `false`. `true` is refused: ephemeral registration is not in protocol 1 yet. |

The `X-Aixle-Runner-Version` of the request is recorded as the machine's runner version.

`201 Created`, with `Cache-Control: no-store`:

```json
{
  "environment": { "id": 42, "key": "aixle-r7-1f2e3d4c", "display_name": "build-01", "state": "registered" },
  "access_token": "aracc_…",
  "access_token_expires_at": "2026-10-31T15:00:00Z",
  "refresh_token": "arref_…",
  "refresh_token_expires_at": "2026-11-30T14:00:00Z"
}
```

`environment.id` is an integer and `environment.key` an opaque string; a runner does not parse
either.

Its own refusals: `422 ephemeral_not_supported`, then `422 invalid_registration`. Neither spends the
token. Two machines that race on one token create one environment; the other gets
`invalid_token`.

Fixtures: `register/`, `headers/`.

### 5.2 `DELETE /runner/v1/registration`

`aixle-runner unregister`: the machine leaves its runner. No body. `204 No Content` with an empty
body. The machine's environment is marked gone and every token of the machine is revoked, so its
next request is `invalid_token`.

Fixtures: `unregister/`.

### 5.3 `POST /runner/v1/token`

The refresh token, sent as the bearer, is exchanged for a new pair (§4). No body. `200 OK`, with
`Cache-Control: no-store`:

```json
{
  "access_token": "aracc_…",
  "access_token_expires_at": "2026-10-31T15:00:00Z",
  "refresh_token": "arref_…",
  "refresh_token_expires_at": "2026-11-30T14:00:00Z"
}
```

Its own refusal: `401 credential_reuse_detected`, for a refresh token presented a second time.

Fixtures: `token/`.

### 5.4 `GET /runner/v1/ops?after=<sequence>&wait=<seconds>`

The long-poll a runner takes its machine's ops from.

| Parameter | Default | Rule |
| --- | --- | --- |
| `after` | `0` | A non-negative integer, at most `9223372036854775807` (2^63 − 1). The highest `sequence` the runner has taken. |
| `wait` | `25` | A non-negative integer, in seconds. A value above 25 is treated as 25. `0` answers at once. |

Anything else is `400 invalid_request`.

`200 OK`, with `Cache-Control: no-store`:

```json
{
  "ops": [
    { "id": 1031, "sequence": 7, "op": "exec", "deadline_at": "2026-10-31T14:05:00Z", "payload": { } }
  ]
}
```

- **What is returned.** The machine's own ops with a `sequence` above `after` and no result yet,
  oldest first, at most 20. A full batch means more may be waiting: the runner polls again at once
  with the new `after`.
- **Waiting.** With nothing to return, the gateway holds the request for up to `wait` seconds and
  answers as soon as an op is enqueued. When the wait ends with nothing, the answer is
  `{"ops": []}`, and the runner polls again.
- **Acknowledging.** `after` is the acknowledgement: an op at or below it is not returned again.
  An op above it is returned by every poll until it is acknowledged or has a result. So a runner
  sets `after` to the highest `sequence` it has recorded, and must expect to receive an op it has
  already seen; it recognises one by its `id`.
- **`delivered`.** The gateway marks the ops it returns `delivered`. That does not prove the runner
  received them: a response lost on the network, or a poll refused by the check after its wait,
  leaves them `delivered` too. They are still returned until acknowledged.
- **The check after the wait.** A poll that waited checks the token, the runner and the flag
  again before it answers (§3). If one fails, it answers the refusal without the ops, and those
  ops stay deliverable.

Fixtures: `ops/` (all with `wait=0`; the waiting itself is tested by the gateway's own tests).

### 5.5 `POST /runner/v1/ops/:id/result`

The runner's outcome of one op, `:id` being the op's `id`.

| Field | Type | Rule |
| --- | --- | --- |
| `status` | string | Required: `ok`, `error` or `expired`. |
| `exit_code` | integer | Optional. |
| `stdout` | string | Optional. |
| `stderr` | string | Optional. |
| `data` | object | Optional. What the op returns beyond its output. |
| `error` | object | Optional. Exactly `{"class": <string>, "message": <string>}`, no other keys. |

A `null` field counts as absent, and other fields are ignored. A field of the wrong type, or an
`error` of any other shape, is `422 invalid_result`.

| `status` | Means | The op's `state` |
| --- | --- | --- |
| `ok` | The op ran and succeeded. | `completed` |
| `error` | The op ran, or tried to, and failed. | `failed` |
| `expired` | The runner received the op after its `deadline_at` and did not run it (§6). | `expired` |

`200 OK`:

```json
{ "id": 1031, "state": "completed" }
```

**The first result wins.** A result for an op that already has one answers `200` with the state
the first result set, and changes nothing. So a runner that is not sure its result arrived sends
it again.

Its own refusals: `404 not_found`, for an op of another machine or no op at all, and
`422 invalid_result`.

Fixtures: `ops/`.

## 6. Ops

An op, as `GET ops` returns it:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | integer | The op's identity, used in its result's path and to recognise a redelivery. |
| `sequence` | integer | Its position in the machine's queue. Each op's is greater than every earlier op's. |
| `op` | string | The op's name, below. |
| `deadline_at` | timestamp | A runner that receives the op after this time does not run it, and reports `expired`. |
| `payload` | object | The op's arguments. |

The result shape is the body of §5.5.

The op names of protocol 1 (DESIGN.md §6.4): `exec`, `write_file`, `read_file`, `batch`, `status`,
`logs`, `session.start`, `session.stop`, `image.ensure`, `container.start`, `container.stop`,
`env.scrub` and `env.reset`.

**Payload and result schemas are not part of this version of the document.** The gateway
carries the payload as an opaque object. Each op's payload and result, with its fixtures, are
specified by the task that first implements the op: 6a for the host ops, 6b for the session ops,
and 8 for the platform side that enqueues them.

## 7. Versioning

- The protocol version is an integer, sent in `X-Aixle-Runner-Protocol`. The gateway accepts `1`
  only; `1.0` is not `1`.
- A breaking change bumps the integer, and adds `fixtures/v2/`. Adding an endpoint, an op or an
  optional field is not a breaking change, so a runner ignores response fields it does not know.
- Supporting the current and the previous version side by side, with a minimum runner version,
  is a later policy (DESIGN.md §14.4). It is not built.

## 8. Not in protocol 1 yet

Each of these is designed in DESIGN.md §6 and comes with its own section and fixtures:

- `POST /runner/v1/check-in`, `POST /runner/v1/heartbeat`, `POST /runner/v1/sessions/:id/log`,
  `POST /runner/v1/sessions/:id/events` and the callback proxy `/runner/v1/proxy/:route/*`: task 8
  and later.
- `session_id` in the op envelope: task 8.
- The releases endpoints `GET /runner/v1/releases/:version/:os-:arch` and
  `GET /runner/v1/releases/:version/checksums`: task 10.
- `409 busy` on `DELETE /registration` while a session runs: the first task that assigns a session
  to a machine.
- An endpoint that issues registration tokens ("Add machine"): task 12.
- Ephemeral registration: refused with `ephemeral_not_supported` until it is built.
