# Runner protocol conformance fixtures

The fixtures pin the wire behaviour that [`PROTOCOL.md`](../PROTOCOL.md) describes, apart from the
clauses listed under [What the fixtures do not cover](#what-the-fixtures-do-not-cover). Each one is
a scenario: named setup steps and HTTP exchanges, in order, with the response every exchange must
get. Both sides run them:

- **The gateway.** `test/integration/runner_protocol_conformance_test.rb` runs every fixture
  against the Rails gateway's routes, in the normal Rails CI shards. A new fixture file is picked
  up without a code change.
- **The runner.** `runner/internal/protocol/conformance_test.go` builds a Go fake of the gateway
  from each fixture and drives `aixle-runner`'s client through every exchange the client can
  send. The fake checks that each request is exactly the fixture's request, and answers with the
  fixture's response, its matchers filled in with concrete values; the client must read that
  answer as the protocol says. The fake checks the protocol headers both ways: a header the
  fixture's request carries must be there with that value, and one it removes with `null` must
  be absent. An exchange the client never sends (a protocol header other than `1`, a release
  request that carries the protocol headers, a malformed `after`, an invalid result body) is
  skipped, because it tests the gateway's
  checks, which the Rails side runs. The test fails if no register, check-in, token, unregister, ops,
  releases or proxy exchange was driven, and it fails for a fixture of which it drives no exchange
  at all, unless the fixture is on its `gatewayOnly` list with the reason (empty today). It runs in
  the Go CI job. `runner/internal/docker/fixtures_test.go` also
  ties the `ops/` fixtures to the runner's handlers: every payload a fixture enqueues for an op
  the runner implements passes that op's payload checks, and every error class a fixture posts
  for such an op is one the runner reports.

`v1/` holds the fixtures of protocol `1`. A protocol bump adds `v2/` next to it.

## What the fixtures do not cover

These clauses of `PROTOCOL.md` are verified outside the portable suite. The Go fake replays only
what the fixtures say, so the runner's handling of these answers (the `413`, the `429` and the
other refusals) is covered by the runner's own unit tests (`runner/internal/protocol/client_test.go`,
the table of §3 in `TestClassify`).

| Clause | Why it is not a fixture | Verified by |
| --- | --- | --- |
| Timing and concurrency: the long-poll waking up when an op is enqueued, a poll that holds its wait, the check after the wait, and races between two requests | A fixture runs its steps one after another, and every fixture polls with `wait=0`. | `test/integration/runner_gateway_operations_test.rb` and `test/services/runners/operations_test.rb` |
| One waiting poll per machine: a newer poll ends the older one, which answers `{"ops": []}` at once (§5.4) | It needs two requests in flight at once, which the fixture format cannot express. | `test/integration/runner_gateway_operations_test.rb` ("a newer poll of the environment ends the waiting one, …", "a poll of another environment does not end a waiting one", "a poll with wait=0 does not end a waiting one") |
| A `wait` above 25 treated as 25 (§5.4) | The poll would be held for 25 seconds. | Not tested. `Runners::Operations.poll` clamps it to `MAX_WAIT`. |
| The `413` for a body over 2 MiB (§2) | Puma answers it before the application, and the Rails tests have no Puma. | No test sends a body through Puma. The cap is `http_content_length_limit` in `config/puma_runner_gateway.rb`. |
| The `429` of the rate limits (§2) | Rack::Attack is off in the tests, and a limit takes hundreds of requests. | The status and the three limits: `test/integration/rack_attack_test.rb` ("registering runners from one address is cut off", "the runner gateway is capped per credential, whichever address it calls from", "the runner gateway is capped per address, whatever bearer value each request sends"). Its plain-text body and the absent `Retry-After` are Rack::Attack's defaults, not tested. |
| The `404` for a path the gateway does not serve (§1) | It comes from the gateway process's routing, not from an endpoint, and its body is the framework's not-found page, which is not part of the contract. | `test/integration/process_mode_routes_test.rb` ("inside the gateway, only /runner/v1/* and /up are routed") |
| `401 runner_revoked` (§3) | Revoking a runner also revokes its tokens, so a scenario sees `invalid_token` first. `runner_revoked` needs only the runner's status to change, which no setup step does. | `test/integration/runner_gateway_test.rb` ("a revocation reaches the gateway within five seconds") |
| The `400` for a body that is not valid JSON (§3) | A harness always serialises `body`, so it cannot send malformed JSON. | Not tested. It is the framework's own answer, documented as built. |
| The callback proxy's forward (§5.8): the request as the platform's endpoint receives it (`X-Aixle-Runner-Environment` added, the bearer and the gateway's headers left out), an answer streamed as it comes, the key check of every credential route, and `502 upstream_unavailable` | The fixtures see only the gateway's side of the wire, one exchange at a time; the internal endpoint is behind it. | `test/integration/runner_gateway_proxy_test.rb`, and on the runner's side `runner/internal/proxy/proxy_test.go` |

## Files

One scenario per file, `v1/<area>/<scenario>.json`, in plain JSON (no comments, no trailing
commas), so that Ruby's `JSON` and Go's `encoding/json` both read it. Every file is an object:

```json
{
  "description": "What the scenario shows, in one or two sentences.",
  "steps": [
    { "given": "registration_token", "as": "reg" },
    {
      "request": {
        "method": "POST",
        "path": "/runner/v1/register",
        "token": "{{reg}}",
        "body": { "name": "build-01", "os": "linux", "arch": "amd64", "facts": {}, "ephemeral": false }
      },
      "response": {
        "status": 201,
        "headers": { "Cache-Control": "no-store" },
        "body": { "environment": { "$type": "object" }, "access_token": { "$prefix": "aracc_" } }
      },
      "capture": { "access": "/access_token" }
    }
  ]
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `description` | yes | A string for the reader. |
| `steps` | yes | A non-empty array. A step is either a setup step (it has `given`) or an exchange (it has `request` and `response`). Steps run in order. Setup steps usually come first, and a scenario may put one between exchanges, for example to turn the flag back on. |

A harness refuses a fixture with an unknown key, an unknown setup step, an unknown matcher or a
variable that is not defined yet. Such a fixture fails, so a typo cannot pass as a check that
nothing ran.

## The world every scenario starts in

One company with the `external_runners` flag on, and one live `manual` runner of that company.
Nothing is registered yet. Every scenario starts from a fresh world.

## Variables

Setup steps and captures define variables. A variable name is lowercase letters, digits, `_` and
`.`, and the dot has no meaning beyond grouping (`m.access_token` is one name). A variable is
defined once per scenario.

- In a request's `path`, `token` and header values, `{{name}}` is replaced by the variable's value
  as a string.
- In a request's `body`, `{"$var": "name"}` is replaced by the variable's value with its JSON type
  (an integer stays an integer).
- In a response's `body`, `{"$var": "name"}` matches a value equal to the variable's.

## Setup steps

A setup step is `{"given": "<name>", ...arguments}`. A harness implements each with the real
services it tests: the Rails harness calls `Runners::Credentials.mint_registration!`,
`Runners::Registration.register!`, `Runners::Operations.enqueue!` and the runner's revoke,
creates a session of the machine for `session_on_machine`, and gives `Runners::Release` the
pins of `release_pins`. The Go fake replays the fixture's answers, so it only checks a setup
step's arguments.

| `given` | Arguments | What it does | Defines |
| --- | --- | --- | --- |
| `registration_token` | `as` | Mints a registration token for the runner, as "Add machine" will. There is no endpoint for this yet. | `<as>`: the token |
| `registered_machine` | `as`, `name` (optional, default: the value of `as`) | Registers one machine of the runner with a fresh registration token, as a successful `POST /runner/v1/register` does, with protocol `1` and runner version `1.4.0`. | `<as>.access_token`, `<as>.refresh_token`, `<as>.environment_id` (an integer) |
| `session_on_machine` | `machine` (a `registered_machine`'s `as`), `as` | Creates a session of the runner that runs on that machine, as the platform assigns one. It does not hold the machine yet. | `<as>.id` (an integer: the `session_id` its ops carry), `<as>.mcp_key` (the key its MCP calls carry in `X-Session-Key`) |
| `session_holds_machine` | `machine` (a `registered_machine`'s `as`), `session` (a `session_on_machine`'s `as`) | Makes the session the one that holds the machine now, as the platform's allocation does. | nothing |
| `upstream_answers` | `route` (a proxy route of PROTOCOL.md §5.8), `status` (an integer), `body` (optional, a JSON value) | The platform's endpoint behind that route answers every request with this status and JSON body. The runner's harness has nothing to set up: its fake gateway sends the fixture's response. | nothing |
| `op_enqueued` | `machine` (a `registered_machine`'s `as`), `session` (optional, a `session_on_machine`'s `as` of the same machine), `as`, `op` (an op name), `payload` (an object) | Puts an op on that machine's queue with a deadline 5 minutes ahead, in whole seconds. A session op (PROTOCOL.md §6) needs `session`, and its envelope then carries that session's `session_id`; an environment op takes none. The platform enqueues an op only while its session holds the machine, so the step first makes `session`, or for an environment op a session of the machine, its holder. | `<as>.id` and `<as>.sequence` (integers), `<as>.deadline_at` (the ISO 8601 string the gateway sends) |
| `runner_revoked` | none | Revokes the runner, which revokes all of its credentials. | nothing |
| `flag_off` | none | Turns `external_runners` off for the company. | nothing |
| `flag_on` | none | Turns it back on. | nothing |
| `time_passes` | `seconds` (an integer) | Moves the gateway's clock forward. | nothing |
| `release_pins` | `min_version`, `recommended_version` (each optional, a version string; absent means null), `binaries` (optional, the `binaries` map of the platform's pins, `runners.release` in `config/settings.yml`: `{"1.5.0": {"linux-amd64": {"sha256": "<64 hex>"}}}`; absent means none) | Replaces the platform's runner pins for the rest of the scenario: the committed `runners.release` block, its `protocol_supported` and `download_url` kept, with these three keys in place of its own. Without this step a scenario runs on the committed pins, which pin no minimum and recommend `0.1.0` with its binaries, below the version the scenarios' requests report (`1.4.0`), so they offer no update. | nothing |

## Exchanges

```json
{ "request": { ... }, "response": { ... }, "capture": { ... } }
```

### `request`

| Key | Required | Meaning |
| --- | --- | --- |
| `method` | yes | `GET`, `POST` or `DELETE`. |
| `path` | yes | The path from the gateway's root, query string included, e.g. `/runner/v1/ops?after=0&wait=0`. |
| `token` | no | Sent as `Authorization: Bearer <token>`. Without it, no `Authorization` header is sent. |
| `headers` | no | Headers to add or replace. A `null` value removes a default header. |
| `body` | no | A JSON value, sent serialized with `Content-Type: application/json`. Without it, the request has no body. |

Every request carries `X-Aixle-Runner-Protocol: 1` and `X-Aixle-Runner-Version: 1.4.0` unless
`headers` replaces or removes them. Header names are case-insensitive. A `302` (the release
redirect, `PROTOCOL.md` §5.6) has no body to match: its `Location` and `X-Aixle-Runner-Sha256`
are checked as `headers`, and the Go client must read them back.

### `response`

| Key | Required | Meaning |
| --- | --- | --- |
| `status` | yes | The exact HTTP status. |
| `headers` | no | Headers that must have exactly these values. A `null` value means the header must be absent. Headers not listed are not checked. |
| `body` | no | A matcher for the JSON body (below). `null` means the body must be empty. Without `body`, the body is not checked. |

### Matching a body

- A JSON object matches an object with **exactly the same keys**, each value matching. An extra or
  missing key fails, so a changed response shape fails its fixture.
- An array matches an array of the same length, element by element.
- A string, number, boolean or `null` matches an equal value.
- An object with a single key starting with `$` is a matcher:

| Matcher | Matches |
| --- | --- |
| `{"$type": "string"}` | any string |
| `{"$type": "integer"}` | any integer |
| `{"$type": "boolean"}` | `true` or `false` |
| `{"$type": "object"}` | any object, whatever its keys |
| `{"$type": "array"}` | any array |
| `{"$type": "timestamp"}` | `YYYY-MM-DDTHH:MM:SSZ`: UTC, whole seconds, such as `2026-10-31T14:00:00Z`. It must be a real date and time, so `2026-02-30T00:00:00Z` does not match, and neither does a fraction (`…:00.123Z`) or another offset (`…:00+00:00`). A harness parses the value and checks that it serializes back to the same string (Go: `time.Parse(time.RFC3339, v)`, then `t.UTC().Format("2006-01-02T15:04:05Z") == v`). |
| `{"$prefix": "aracc_"}` | a string that starts with the prefix |
| `{"$var": "name"}` | a value equal to the variable's |

Refusal bodies match `message` with `{"$type": "string"}`: the message is for people and may
change, while `error` is the contract.

### `capture`

An object from variable names to [JSON Pointers](https://www.rfc-editor.org/rfc/rfc6901) into the
response body, read after the response has matched. `{"pair.access": "/access_token"}` defines
`pair.access`, and `{"first": "/ops/0/id"}` reads into an array. A pointer to nothing fails the
fixture.

## Adding a fixture

1. Add the file under `v1/<area>/`. The Rails conformance test picks it up.
2. Use only the setup steps above. A scenario that needs a new one adds it to this README and to
   every harness in the same change.
3. When a later task adds an endpoint or an op, it adds that endpoint's or op's section to
   `PROTOCOL.md` and its fixtures here, in the same change.
