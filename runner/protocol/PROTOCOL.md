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
- **The request schemas** in [`schemas/v1/`](schemas/v1/) are the JSON Schemas (draft 2020-12)
  of the bodies and parameters the endpoints take (§5). The gateway checks every request against
  its schema, and a request that fails it gets the endpoint's own refusal. A new endpoint that
  takes a body or parameters adds its schema there.
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
| `credential_reuse_detected` | 401 | `token` | A spent refresh token was presented again, and it was not a retry after a lost response. Its whole family is now revoked (§4). |
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
   `POST /token` can tell a retry after a lost response from a reuse, and answer
   `credential_reuse_detected` for a reuse (§4).
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

**A network error on `POST /token`.** When the connection fails before the runner has the
response (a timeout, a reset, a dropped connection), the runner does not know whether the
gateway spent its refresh token. It backs off and retries with the same refresh token. The
gateway answers such a retry like a rotation, within the limits of §4.

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
- **Except a retry after a lost response.** A spent refresh token presented again is a retry,
  not a reuse, when both of these hold:
  - it was spent less than 60 seconds ago;
  - the pair its spend issued is unused: the gateway has accepted neither its access token nor
    its refresh token.

  The gateway then revokes that unused pair and answers `200` with a fresh pair of the same
  family, exactly as a rotation does. The 60 seconds count from the first spend, so a retry does
  not extend them, and a second retry within them revokes the first retry's pair. Anything else
  is reuse: a spent token presented 60 seconds or more after its spend, after the pair it issued
  was used, or two or more rotations old.
- **The retry's limit.** A runner retries a failed refresh about 1, 3, 7, 15 and 31 seconds after
  the first failure, so a dropped connection of up to about 30 seconds is covered. If the
  connection drops right after the gateway commits the rotation and stays down longer, the
  retry comes after the 60 seconds and is reuse: the machine must be registered again.
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

Schema: [`schemas/v1/register.request.json`](schemas/v1/register.request.json), checked after the
`ephemeral` refusal; `name` blank once trimmed and a value over 255 characters are checked when
the machine is recorded, with the same refusal.

Fixtures: `register/`, `headers/`.

### 5.2 `DELETE /runner/v1/registration`

`aixle-runner unregister`: the machine leaves its runner. No body. `204 No Content` with an empty
body. The machine's environment is marked gone and every token of the machine is revoked, so its
next request is `invalid_token`. A session that runs on the machine is not waited for (§8): the
platform enqueues none of its ops from then on.

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

Its own refusal: `401 credential_reuse_detected`, for a spent refresh token presented again. A
spent refresh token presented again within 60 seconds of its spend, while the pair the spend
issued is unused, is a retry after a lost response instead: it answers `200` with a fresh pair,
and the unused pair is revoked (§4).

Fixtures: `token/`.

### 5.4 `GET /runner/v1/ops?after=<sequence>&wait=<seconds>`

The long-poll a runner takes its machine's ops from.

| Parameter | Default | Rule |
| --- | --- | --- |
| `after` | `0` | A non-negative integer, at most `9223372036854775807` (2^63 − 1). The highest `sequence` the runner has taken. |
| `wait` | `25` | A non-negative integer, in seconds. A value above 25 is treated as 25. `0` answers at once. |

Anything else is `400 invalid_request`. Schema:
[`schemas/v1/ops.query.json`](schemas/v1/ops.query.json); a parameter written as a base-10
integer is read as that integer before it is checked.

`200 OK`, with `Cache-Control: no-store`:

```json
{
  "ops": [
    { "id": 1031, "sequence": 7, "op": "exec", "session_id": 123, "deadline_at": "2026-10-31T14:05:00Z", "payload": { } },
    { "id": 1032, "sequence": 8, "op": "env.reset", "deadline_at": "2026-10-31T14:15:00Z", "payload": { } }
  ]
}
```

- **What is returned.** The machine's own ops with a `sequence` above `after` and no result yet,
  oldest first, at most 20. A full batch means more may be waiting: the runner polls again at once
  with the new `after`.
- **Waiting.** With nothing to return, the gateway holds the request for up to `wait` seconds and
  answers as soon as an op is enqueued. When the wait ends with nothing, the answer is
  `{"ops": []}`, and the runner polls again.
- **One waiting poll per machine.** Only one poll of a machine waits at a time. A newer poll with
  `wait` above 0 ends the machine's older waiting poll, which answers `{"ops": []}` at once, and
  the newer one waits. A poll with `wait=0` ends no other poll. Two polls that start together may
  both answer `{"ops": []}`. No op is lost: an op stays deliverable until `after` acknowledges it.
  A runner that sends one poll at a time never sees this.
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

Fixtures: `ops/` (all with `wait=0`; the waiting itself, and a newer poll ending an older one, are
tested by the gateway's own tests).

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

Schema: [`schemas/v1/op_result.request.json`](schemas/v1/op_result.request.json). JSON Schema
counts `1.0` as an integer, so an `exit_code` of `1.0` is accepted, and stored as `1`.

Fixtures: `ops/`.

## 6. Ops

An op, as `GET ops` returns it:

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | integer | The op's identity, used in its result's path and to recognise a redelivery. |
| `sequence` | integer | Its position in the machine's queue. Each op's is greater than every earlier op's. |
| `op` | string | The op's name, below. |
| `session_id` | integer | The session a session op is for, above 0. A session op always has it; an environment op (`env.scrub`, `env.reset`) never has the key. |
| `deadline_at` | timestamp | A runner that receives the op after this time does not run it, and reports `expired`. |
| `payload` | object | The op's arguments. |

The result shape is the body of §5.5.

**The session ops** are `exec`, `write_file`, `read_file`, `batch`, `status`, `logs`,
`container.start`, `container.stop`, `session.start` and `session.stop`. Every one of them acts
for the session its envelope names, and for no other (§6.2, §6.3):

- A session op whose envelope has no `session_id` is not run: it answers an `error` result with
  `error.class` `session_required`.
- A session op that finds the environment's session container labelled with another session
  (`aixle.com/session`) does not touch it: it answers an `error` result with `error.class`
  `session_mismatch`. This holds for `container.start` and `container.stop` too (§6.2). So a late
  op of a finished session never reaches the next session's container.
- A session op that finds no session container answers `no_session_container` (`status`
  answers `missing` instead, §6.3).

The platform sends a session's ops only while the session holds the machine; once it has
released it, the platform answers them itself, as `no_session_container`, and enqueues nothing.
The runner's check is the safety net for an op enqueued just before the release.

**The platform's side of a deadline.** The platform stops waiting for an op at its `deadline_at`
and marks it `expired`, as if the runner had answered `expired`. An op that nobody waits for any
more, still without a result 10 seconds past its `deadline_at`, `pending` or `delivered`, is
marked `expired` by the platform's sweep: `delivered` does not prove the runner received it
(§5.4). A result that arrives later changes nothing (§5.5, the first result wins). Finished ops
are kept 7 days. `sequence` comes from a per-machine counter, so it keeps growing after a prune.

The op names of protocol 1 (DESIGN.md §6.4): `exec`, `write_file`, `read_file`, `batch`, `status`,
`logs`, `session.start`, `session.stop`, `container.start`, `container.stop`, `env.scrub` and
`env.reset`. There is no op that only pulls an image: `container.start` pulls it (§6.1).

**Payload and result schemas.** The gateway carries the payload as an opaque object. Each op's
payload and result, with its fixtures, are specified below: the agent image (§6.1), the agent
container (§6.2), the session ops (§6.3) and scrub and reset (§6.4). The platform enqueues
them from `ContainerRuntime::RunnerRuntime`, one op per runtime call of the session's strategy. `session.start` and `session.stop` are reserved and have no schema:
a runner answers them `unsupported_op` (below).

**Who runs them.** On `manual` the host runner runs every op of this section itself. It runs the
session ops through the Docker Engine API against the environment's session container (exec,
the archive API for files, inspect for the status), as the platform's development runtime
does. Nothing of the runner runs inside the agent container.

**Rules every op follows.**

- **Unknown payload fields are ignored**, so a newer platform can add optional fields (§7). A
  payload field of the wrong type, or a value outside its rule, is an `error` result with
  `error.class` `invalid_payload`, and nothing is run.
- **A failure of the Docker daemon** that the op's own classes do not cover is `docker_error`,
  with the daemon's message.
- **The output cap is 1 MiB** (1 048 576 bytes): the most an op returns of one output stream or
  one file. It is a constant of protocol 1, since the runner reads no platform settings.
- **A result over the body cap is `result_too_large`.** Before it journals and posts a result,
  the runner encodes it once. If the encoded result is over the gateway's 2 MiB body cap (§2) less
  a 16 KiB margin, the runner posts an `error` result with `error.class` `result_too_large`
  instead, and nothing else: the gateway would refuse the larger body with `413`, which is not
  resent (§3), and the op would never be answered. The message names the op and the encoded size,
  and for a `batch` how many steps it has and how many ran. The op did run: a `batch` of
  `write_file`s, for example, wrote its files. It happens to an `exec` near the output cap on both
  streams, a `batch` of large steps, or output that JSON escapes heavily (`<`, `>`, `&` and control
  bytes such as the `ESC` of a terminal's colours take 6 bytes each).
- **`error.class` is the contract**; `error.message` is for people and may change.

**An op this runner does not implement.** The platform can be newer than the runner. A runner
that receives an op name it does not implement does not run it, and answers an `error` result
with `error.class` `unsupported_op` and a message that names the op and the runner's version.

**An op interrupted by a restart.** Ops run at most once. A runner that stopped while an op ran
does not run it again when it is redelivered: it answers an `error` result with `error.class`
`interrupted`. This holds for the session ops too. The session container belongs to the Docker
daemon, not to the runner, so a runner restart does not stop it: a command an `exec` started
keeps running in the container, and the restarted runner finds the container again by its
labels.

### 6.1 The agent image

The agent image is pulled by `container.start` (§6.2), as a Kubernetes pod pulls its image: the
platform never sends an op that only pulls, and its own pull phase does nothing on a runner.

An `image` in a payload is an image reference as the platform was given it, by tag or by digest,
e.g. `ghcr.io/aixlehq/flow-agent-claude-code:latest` or
`ghcr.io/aixlehq/flow-agent-claude-code@sha256:…`. A reference with neither is read as `:latest`,
as `docker pull` reads it. A value that is not a reference is `invalid_payload`.

`container.start` always pulls the reference through the Docker Engine API before it creates the
container, because Docker's create API does not pull. A tag that moved is followed, and the
daemon downloads only the layers it lacks. There is no pull policy, and no digest is returned:
the platform never contacts a registry.

The runner pulls with the Docker credentials of the user it runs as, resolved as the Docker CLI
resolves them for `docker pull`: from that user's Docker configuration (`$DOCKER_CONFIG`, or
`~/.docker/config.json`), credential helpers included, for the image's registry. Docker Hub's
credentials are looked up under `https://index.docker.io/v1/`, where `docker login` stores them,
for a reference on `docker.io` or `index.docker.io`. An operator who
runs agent images from a private registry runs `docker login`, or configures a credential helper,
as that user. With no credentials for the registry, the pull is anonymous. A pull that fails is the `container.start` outcome
`image_pull_failed`, even with an older copy of the image on the daemon, and its message carries
the registry's or the daemon's own words, e.g. `manifest unknown` or `pull access denied`.

### 6.2 The agent container: `container.start` and `container.stop`

Host-runner ops (`manual`). An environment has at most one session container at a time.

**Names, labels and volumes.** For an environment of key `<key>`:

| What | Name | Label |
| --- | --- | --- |
| The session container | `aixle-<key>-<session_id>`, with the envelope's `session_id` | `aixle.com/environment=<key>` and `aixle.com/session=<session_id>` |
| The workspace volume | `aixle-ws-<key>` | `aixle.com/environment=<key>` |
| A cache volume | `aixle-cache-<key>-<name>` | `aixle.com/environment=<key>` |

#### `container.start`

Pulls the agent image (§6.1), then creates and starts the session's agent container from it,
named and labelled with the envelope's `session_id`. The pull, the volumes, the create and the
start run until the op's `deadline_at` at most: past it nobody waits for the result, so the op
creates nothing more, removes a container whose create the deadline cut off, and answers
`container_start_failed`, and the runner moves on to the next op. The container runs the image's own entrypoint and
command, unchanged, as a hosted pod does. The
runner puts nothing of its own into it: no binary, no socket, no token and nothing of its state
directory.

Payload:

| Field | Type | Rule |
| --- | --- | --- |
| `image` | string | Required. The agent image's reference (§6.1), which the op always pulls before it creates the container. |
| `env` | object | Optional, string to string. The container's environment variables, on top of the image's. A name must not be empty or contain `=`. |
| `workspace_volume` | boolean | Optional, default `true`: the workspace volume is mounted at `/workspace`. `false` mounts nothing there. |
| `mounts` | array | Optional, default `[]`. Each entry is one of the two below. |
| `network` | string | Optional: `bridge` (the default) or `host`. |
| `pid` | string | Optional: `private` (the default) or `host`. |
| `resources` | object | Optional: `{"cpus": <number>, "memory_bytes": <integer>, "pids_limit": <integer>}`, each optional and not negative. An absent or `0` field sets no limit. `memory_bytes` also caps swap. |
| `privilege_escalation` | boolean | Optional, default `false`. `false` starts the container with `no-new-privileges`, as the hosted pod is started for a runtime that needs no `sudo`. |

A `mounts` entry:

| `type` | Fields | Mounted as |
| --- | --- | --- |
| `cache` | `name`: letters, digits, `_`, `.` and `-`, starting with a letter or digit; `target` | The cache volume `aixle-cache-<key>-<name>` at `target`, writable. |
| `bind` | `source`: an absolute, clean path of the machine; `target`; `writable`, a boolean, default `false` | `source` at `target`, read-only unless `writable` is `true`. |

A `target` is an absolute, clean path other than `/`. A `bind` whose `source`, symlinks
resolved, is the runner's state directory, is inside it or contains it, is refused with
`forbidden_mount`: the state directory holds the environment's credentials. A source the runner
cannot resolve is refused the same way.

A runner installed as the service runs with systemd's `PrivateTmp=true`, so it sees a private
`/tmp` and `/var/tmp`, not the machine's. A `bind` whose `source` is under the machine's `/tmp`
or `/var/tmp` does not resolve there and is refused with `forbidden_mount`. This is a known
limitation: a bind source must be outside those directories when the runner runs as the
service.

The container is also created with the restart policy `no` (an agent cannot resume mid-turn, so
a container that stops stays stopped and keeps its exit code), the `NET_RAW` capability dropped,
and no published ports. The runner creates the workspace and cache volumes with the
environment's label before it creates the container. Creating a volume that already exists
returns it unchanged, so a volume with one of these names that does not carry
`aixle.com/environment=<key>` is not the environment's: `container.start` refuses with
`volume_not_owned`, naming it, and neither mounts nor changes it.

Results:

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| The container runs | `ok` | `{"container_id": <string>, "name": <string>}` | |
| The environment has another session's container | `error` | | `session_mismatch`; the message names it and both sessions, and nothing is started |
| The environment already has a container: this session's own, or one left over that names no session | `error` | | `container_exists`; the message names it. Run `container.stop` or `env.scrub` first. |
| The pull failed, even with an older copy of the image on the daemon | `error` | | `image_pull_failed`; the message carries the registry's or the daemon's own words (§6.1). Nothing is created. |
| A bind would expose the state directory | `error` | | `forbidden_mount` |
| A workspace or cache volume with the environment's name exists without its label | `error` | | `volume_not_owned`; the message names the volume. No container is created. |
| The daemon refused to create or start the container | `error` | | `container_start_failed`, with the daemon's words. A container that was created but did not start is removed, under the removal's own timeout of 30 seconds, not the op's. A removal that fails or times out is logged and named in the message, and the answer stays `container_start_failed`: the session's cleanup sends `env.reset`, which removes what is left. |
| The payload is not the one above | `error` | | `invalid_payload` |

```json
{ "status": "ok", "data": { "container_id": "4f1c…", "name": "aixle-aixle-r7-1f2e3d4c-123" } }
```

#### `container.stop`

Stops the container of the envelope's session, sending SIGTERM and SIGKILL 10 seconds later, and
removes it with its anonymous volumes. The workspace and cache volumes stay. The name alone is
not proof: a container named `aixle-<key>-<session_id>` that does not carry both
`aixle.com/environment=<key>` and `aixle.com/session=<session_id>` is refused with
`container_not_owned`, and is neither stopped nor removed. Without a container of this session
the op answers an `error` and touches nothing, so that the platform can tell "this session's
container is already gone" from "the machine holds another session".

Payload: `{}`.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| The container is gone | `ok` | `{"removed": <boolean>}`: `false` only when the container went away while it was being stopped | |
| The environment's session container is another session's | `error` | | `session_mismatch`; the container is not touched |
| The environment has no session container | `error` | | `no_session_container` |
| A container has the name but not both labels | `error` | | `container_not_owned`; the container is not touched |
| The daemon refused | `error` | | `docker_error` |
| The payload is not the one above | `error` | | `invalid_payload` |

Fixtures: `ops/container_start.json`, `ops/container_stop.json`.

### 6.3 The session ops

`exec`, `write_file`, `read_file`, `batch`, `status` and `logs` act on the environment's session
container, the one labelled `aixle.com/environment=<key>` and `aixle.com/session`, and only when
its `aixle.com/session` is the envelope's `session_id` (§6). Every step of a `batch` is checked
the same way.

| Outcome | `status` | `error.class` |
| --- | --- | --- |
| The envelope has no `session_id` | `error` | `session_required`; nothing is run |
| The session container is another session's | `error` | `session_mismatch`; the message names the container and both sessions, and the container is not touched. `status` answers this too, not `missing`. |

**Without a session container.** `exec`, and an `exec` in a `batch`, need the container
running. `write_file`, `read_file` and `logs` need it to exist, and work on a container that has
exited, so that the platform can collect the output of an agent that ended. Without what it
needs, an op answers an `error` result with `error.class` `no_session_container`. `status`
answers `missing` instead.

#### `exec`

Runs a command in the session container through the daemon's exec API, without a TTY.

| Field | Type | Rule |
| --- | --- | --- |
| `cmd` | array of strings | Required, not empty. The command and its arguments; no shell is added. |
| `env` | object | Optional, string to string. Added to the container's environment for this command. |
| `cwd` | string | Optional, an absolute path. Default: the image's working directory. |
| `user` | string | Optional. A user name or uid, with an optional `:group`. Default: the image's user. |
| `timeout` | integer | Optional, seconds. The command runs under coreutils `timeout` (which the agent images have): SIGTERM at `timeout` seconds, SIGKILL 5 seconds later, to its whole process group. The op's `deadline_at` bounds it too: absent or `0`, or longer than the seconds left until `deadline_at` when the command starts, the command gets those seconds instead (at least 1), the same way. After the deadline nobody waits for the result, and the runner runs one op at a time. |
| `stdin` | string | Optional. Written to the command's standard input, which is then closed. Without it the command's standard input is not attached. |

| Outcome | `status` | `exit_code` | `stdout`, `stderr` | `data` | `error.class` |
| --- | --- | --- | --- | --- | --- |
| The command ran, whatever its exit code | `ok` | Its exit code | Each up to the output cap | `{"stdout_truncated": <boolean>, "stderr_truncated": <boolean>}` | |
| The command ran past its `timeout`, or past the op's `deadline_at` when that came first, and was ended | `error` | `124` (or `137` after SIGKILL), when the daemon reported it | What it wrote, capped | as above | `exec_timeout` |
| The daemon refused the exec | `error` | | | | `exec_failed` |
| No running session container | `error` | | | | `no_session_container` |
| The payload is not the one above | `error` | | | | `invalid_payload` |

**The output cap.** Each stream keeps its first 1 MiB; the rest is read and dropped, so the
command never blocks on a full pipe, and `<stream>_truncated` is `true`. A UTF-8 character cut
by the cap is dropped, and bytes that are not UTF-8 arrive as U+FFFD.

```json
{ "status": "ok", "exit_code": 0, "stdout": "main\n", "stderr": "", "data": { "stdout_truncated": false, "stderr_truncated": false } }
```

#### `write_file`

Writes one file into the session container through the archive API (what `docker cp` does).
Missing parent directories are created, owned by root with mode `0755`; an existing file is
replaced.

| Field | Type | Rule |
| --- | --- | --- |
| `path` | string | Required. An absolute, clean path other than `/`. |
| `content` | string | Required. The file's bytes, standard base64 with padding. `""` writes an empty file. An absent or `null` `content` is `invalid_payload`, in a `batch` step too, and nothing is written. |
| `mode` | integer | Optional, default `420` (`0644`). From `0` to `4095` (`07777`). |
| `uid`, `gid` | integer | Optional, default `0`, not negative. The file's owner. |

| Outcome | `status` | `error.class` |
| --- | --- | --- |
| Written | `ok`, no `data` | |
| The daemon refused the write | `error` | `write_failed` |
| No session container | `error` | `no_session_container` |
| The payload is not the one above | `error` | `invalid_payload` |

#### `read_file`

Reads one regular file of the session container through the archive API. A symlink is followed
once, to the target the daemon resolves.

Payload: `{"path": <an absolute, clean path other than />}`.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| Read | `ok` | `{"content": <base64>, "size": <integer>}`: the file's bytes and their number | |
| The file is over the output cap | `error` | | `file_too_large`. Nothing of it is returned (§8). |
| No such file | `error` | | `file_not_found` |
| A directory or another non-regular file | `error` | | `not_a_file` |
| No session container | `error` | | `no_session_container` |
| The payload is not the one above | `error` | | `invalid_payload` |

#### `batch`

An ordered list of `exec`, `write_file` and `read_file` ops, run one after another until the
first that fails. A step fails when its result is an `error`, or when it is an `exec` whose
exit code is not `0`.

Payload: `{"ops": [{"op": <"exec" | "write_file" | "read_file">, "payload": <that op's payload>}, …]}`,
at least one. Every step is checked before the first runs: an empty list, another op name (a
nested `batch` included) or an invalid step payload is `invalid_payload`, and nothing runs.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| Every step succeeded | `ok` | `{"results": [<result>, …]}`: each step's result, in the shape of §5.5, in order | |
| A step failed | `error` | `{"results": […]}`, ending with the failed step's result | `batch_step_failed`; the message names the step's index and op, and how many did not run |

#### `status`

The session container's state, read from the daemon's inspect. Payload: `{}`.

| `data.state` | When | Other `data` |
| --- | --- | --- |
| `running` | The container runs (a paused one counts: it has not exited) | `container_id`, `name` |
| `starting` | Created and not started yet, or restarting | `container_id`, `name` |
| `terminated` | Exited, dead, or being removed | `container_id`, `name`, `exit_code` (integer), `oom_killed` (boolean) |
| `missing` | The environment has no session container | none |

Each is an `ok` result. A daemon that cannot be asked is `docker_error`.

#### `logs`

The tail of the terminal-output file, `/tmp/terminal_output.log`, which the agent image's
entrypoint writes from the agent's tmux pane (DESIGN.md §6.5).

Payload: `{"bytes": <integer>}`, optional: how much of the end of the file to return, from `1`
to the output cap. Absent or `0` means the output cap.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| Read | `ok` | `{"tail": <string>, "size": <integer>, "truncated": <boolean>}`: the last `bytes` of the file as text, the file's size, and whether the tail is shorter than the file. Before the agent has written anything the file does not exist, and `tail` is `""` with `size` `0`. | |
| No session container | `error` | | `no_session_container` |
| The payload is not the one above | `error` | | `invalid_payload` |

A UTF-8 character cut at the start of the tail is dropped, and bytes that are not UTF-8 arrive
as U+FFFD.

Fixtures: `ops/exec.json`, `ops/write_and_read_file.json`, `ops/batch.json`,
`ops/status_and_logs.json`, `ops/no_session_container.json`, `ops/reserved_session_ops.json`.

### 6.4 `env.scrub` and `env.reset`

Host-runner ops (`manual`), the scrub and the reset of DESIGN.md §7.2. Who decides between
them, and when, is the platform's.

**Scope by ownership, never by enumeration.** Both act only on what the runner created for the
environment: containers labelled `aixle.com/environment=<key>`, and the volumes `aixle-ws-<key>`
and `aixle-cache-<key>-*` that also carry that label. Nothing of another environment is touched,
even one whose key starts with this one's. Neither op walks a host-path mount: what an agent
wrote through a writable bind mount is outside the guarantee.

#### `env.scrub`

1. Removes every container of the environment with `docker rm -f` and its anonymous volumes.
2. Checks by label that none is left.
3. If the workspace volume exists, empties `/workspace/outputs` on it: a short-lived container
   of the agent image, labelled with the environment and `aixle.com/role=scrub`, running as root
   with no network and only the workspace volume mounted, deletes everything inside the
   directory and is removed. A `/workspace/outputs` that is a symlink is not followed.
4. Checks by label again that no container is left.

Repository checkouts, the cache volumes and the pulled images stay. A workspace volume that does
not carry `aixle.com/environment=<key>` is not the environment's: step 3 does not mount it, nothing
is emptied, and the scrub answers `scrub_failed` naming it.

Payload: `{"image": <string>}`, a reference as in §6.1: the agent image the container of step 3
runs. The daemon must have it: the session's `container.start` pulled it.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| Scrubbed | `ok` | `{"removed_containers": [<name>, …], "outputs_emptied": <boolean>}`: the containers removed, sorted, and whether a workspace volume was there to empty | |
| A container could not be removed, one is left, the outputs could not be emptied, or the workspace volume is not the environment's | `error` | | `scrub_failed` |
| The payload is not the one above | `error` | | `invalid_payload` |

#### `env.reset`

The scrub's steps 1 and 2, then the removal of the workspace volume and every cache volume of
the environment, and a check that none of them is left. There are no outputs to empty, since
the volume goes. Pulled images stay.

Before it removes a volume, the reset looks for volumes named like the environment's that are not
its own: `aixle-ws-<key>`, or `aixle-cache-<key>-*`, without `aixle.com/environment=<key>`. A cache
volume whose label is another key `<other>` and whose name starts with `aixle-cache-<other>-`
belongs to that environment and is not counted. If there is one, no volume is removed, and the
reset answers `reset_failed` naming it.

Payload: `{}`.

| Outcome | `status` | `data` | `error.class` |
| --- | --- | --- | --- |
| Reset | `ok` | `{"removed_containers": [<name>, …], "removed_volumes": [<name>, …]}`, each sorted | |
| A container or a volume could not be removed, for example a volume another container uses, one is left, or a volume named like the environment's is not its own | `error` | | `reset_failed` |

Fixtures: `ops/env_scrub_and_reset.json`.

## 7. Versioning

- The protocol version is an integer, sent in `X-Aixle-Runner-Protocol`. The gateway accepts `1`
  only; `1.0` is not `1`.
- A breaking change bumps the integer, and adds `fixtures/v2/`. Adding an endpoint, an op or an
  optional field is not a breaking change, so a runner ignores response fields it does not know.
- Supporting the current and the previous version side by side, with a minimum runner version,
  is a later policy (DESIGN.md §14.4). It is not built.

## 8. Not in protocol 1 yet

Each of these is designed in DESIGN.md §6 and comes with its own section and fixtures:

- The callback proxy `/runner/v1/proxy/:route/*`: task 8b. `POST /runner/v1/check-in`,
  `POST /runner/v1/heartbeat` and `POST /runner/v1/sessions/:id/log`: task 8c.
  `POST /runner/v1/sessions/:id/events`: later.
- Output and files over the 1 MiB output cap (§6): `exec` returns the first 1 MiB of each stream
  and `read_file` refuses a larger file. They come back through an upload to a signed URL with
  task 8c. Until then a result whose encoded body is over the gateway's 2 MiB cap is answered
  `result_too_large` (§6).
- `session.start` and `session.stop`: reserved, answered `unsupported_op`.
- The releases endpoints `GET /runner/v1/releases/:version/:os-:arch` and
  `GET /runner/v1/releases/:version/checksums`: task 10.
- `409 busy` on `DELETE /registration` while a session runs. Task 8a assigns sessions to machines
  without it: a machine unregistered during a session stops holding that session, the session's
  next ops are not enqueued and answer `no_session_container`, and the session fails as one whose
  container is gone. That session's container keeps running on the machine: nothing can stop it,
  because the runner is unregistered and its credentials are revoked, so the operator removes it
  by hand. Scrub and return to service are tasks 11 and 13.
- An endpoint that issues registration tokens ("Add machine"): task 12.
- Ephemeral registration: refused with `ephemeral_not_supported` until it is built.
