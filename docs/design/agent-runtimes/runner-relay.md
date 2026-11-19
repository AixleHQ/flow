# The Go runner relay service: the interactive tunnel, and the home of the runner's long-held connections

**Status:** proposal for review (task #253, "Runners 16a"), revised after Alex's review of PR #796 (2026-11-19). Nothing here is built.
**Naming (Alex, 2026-11-19):** the service is **`runner-relay`** everywhere: the directory `runner-relay/`, the binary `aixle-runner-relay`, the image and the Helm workload `runner-relay`, the variables `RUNNER_RELAY_*`, the metric prefix `runner_relay_`, the Redis channel `runner_relay` and the internal endpoints `/api/v1/internal/runner_relay/…`. It is not `runner-gateway`: that name belongs to the Rails deployment until row 26, and the Go service never becomes the whole gateway (the token checks, `Rack::Attack` and every short endpoint stay in Rails). In the text, "the relay" means this service.
**Parent:** [`DESIGN.md`](DESIGN.md) §6.9.5 (the tunnel) and §15 row 16. It refines §6.9.5 and
replaces row 16 with the rows 16b to 16g of §13 below, and adds the rows 24 to 26 for the
takeover.
**Baseline:** `origin/develop` @ `af7bfbf0`. The fixes of #252 (#255 to #261) are in: the runner's
HTTP/2 liveness ping (#256, PR #768) and the check-in before the callback proxies serve (#258,
PR #792). The design builds on both.

## 1. What is decided, and what this document decides

_A section number with `DESIGN.md` in front of it is the parent document's; a bare one is this document's._

Alex decided four things on 2026-11-15 (task #253). They are inputs here, not questions:

1. **The relay is a separate Go service,** built as the future home of every long-held runner
   connection: it waits for signals itself and calls Rails only with short requests.
2. **The browser is authorized as hosted containers are:** Traefik's `terminal-auth`
   ForwardAuth middleware calls `GET /api/v1/internal/ws_auth`. The relay sits behind that
   middleware and adds no browser authentication of its own.
3. **One replica at the start.** The multi-replica options are recorded with their costs (§11).
4. **The runner's entry point is the gateway's host,** with a new path, `/runner/v1/tunnel`,
   that the ingress routes to the service. Customers get no new outbound destination (`DESIGN.md` §9.5).

This document settles the rest, in this order: the service (§2), the runner's connection (§3),
the relay protocol (§4 to §6), the browser side (§7), signals (§8), the live terminal view
(§9), the takeover (§10), multi-replica (§11), testing (§12), the cut (§13), and the risks
and open choices (§14 to §16). Every choice that is not Alex's carries its options and their
costs, and the recommendation is marked **Recommended**.

**Where the wire is written.** The task asked for `runner/protocol/PROTOCOL.md` to describe the
relay protocol too. That file states that it describes "protocol `1` as the gateway implements it
today, and nothing it does not implement yet", and each endpoint adds its section in the task that
builds it. So the frames of §5 are specified here, as the contract the tasks are written against,
and each task that builds a piece writes that piece's `PROTOCOL.md` section with its fixtures
(§13). This design PR changes no file but this document, `DESIGN.md` and `docs/index.md`.

## 2. The service

### 2.1 Where it lives

A new top-level Go module, **`runner-relay/`**, with its own `go.mod`, `Dockerfile` and CI job, as
`docker/otlp-ingest/` and `runner/` are. It is platform code and ships with the platform: it is
**not** part of `runner/`, because `runner/` is extracted into `AixleHQ/aixle-runner` (`DESIGN.md` §14.1) and
customers must not receive the platform's service with it. **Decided (Alex, 2026-11-19).**

**Sharing protocol code with `aixle-runner`.** The two ends of the relay protocol must frame,
window and limit identically. Options:

| | A. One public Go package in `runner/`, imported by `runner-relay/` | B. Both in the `runner/` module | C. Two implementations, one set of fixtures |
| --- | --- | --- | --- |
| How | `runner/protocol/tunnel/` (stdlib and the WebSocket library only, no `internal/`). `runner-relay/go.mod` requires the runner module with `replace => ../runner` | `runner/cmd/aixle-runner-relay` | Each side codes the frames, both run `runner/protocol/fixtures/v1/tunnel/` |
| Drift | None: one codec and one flow-control implementation | None | Possible, caught by fixtures only |
| Extract of `runner/` (`DESIGN.md` §14.1) | The `replace` becomes a version of the extracted module; one line in `runner-relay/go.mod`, and the Docker build copies the package from the module cache instead of the repo | The platform's service leaves with the runner | Clean |
| CI | Two Go jobs, and a change in the package builds both | One job | Two jobs |

**Decided (Alex, 2026-11-19): A.** The multiplexer is the hard part (windows, fairness, reset races), and two
copies of it would be two sets of bugs. The package is a codec and a stream multiplexer over an
abstract message connection (`type Conn interface { ReadMessage; WriteMessage }`), so it needs no
HTTP and its tests need no network. The relay's Docker build context is the repository root, so
`COPY runner/protocol/tunnel` works while the replace is in place.

**WebSocket library:** `github.com/coder/websocket` (context-aware API, no global state, small).
`gorilla/websocket` is the alternative and would also do; the choice is a one-line detail for 16b,
both ends use the same one.

### 2.2 Process and configuration

One binary, `runner-relay/cmd/aixle-runner-relay`, one process, one HTTP server (`:8080`) and one admin server
(`:9090`: `/healthz`, `/readyz`, `/metrics`, never routed by the ingress). Configuration is
environment variables only, read once at start; the service never reads `config/`, `app/` or
`Settings`, as `runner/` does not (`DESIGN.md` §14.1).

| Variable | Meaning | Default |
| --- | --- | --- |
| `RUNNER_RELAY_LISTEN`, `RUNNER_RELAY_ADMIN_LISTEN` | Listen addresses | `:8080`, `:9090` |
| `RUNNER_RELAY_REDIS_URL`, `RUNNER_RELAY_REDIS_CHANNEL_PREFIX` | The platform's Redis. The prefix is the one `config/cable.yml` gives Action Cable (`aixle_<env>_`), because Rails publishes through `ActionCable.server.pubsub`, which prefixes the channel | none, none |
| `RUNNER_RELAY_RAILS_URL` | The web app's internal URL, for the short calls of §8.2 | none |
| `RUNNER_RELAY_INTERNAL_TOKEN` | Bearer for those calls (§8.2) | none |
| `RUNNER_RELAY_TICKET_KEY` | HMAC key that verifies tunnel tickets (§3.1) | none |
| `RUNNER_RELAY_MAX_STREAMS`, `RUNNER_RELAY_MAX_FRAME`, `RUNNER_RELAY_STREAM_WINDOW` | The caps of §6, offered to the runner in `hello` | `64`, `32768`, `262144` |
| `RUNNER_RELAY_CHECK_INTERVAL` | The reconcile pass of §8.3 | `60s` |

Rails side: `Settings.runners.relay` in `config/settings.yml`, filled from `RUNNERS_RELAY_*`
(`Configuration/NoEnvInApp` forbids `ENV` elsewhere): the ticket key, the internal token and the
relay's public path. `RUNNER_RELAY_TICKET_KEY` is a key of its own, never `RUNNERS_SECRET_KEY`, so a
compromised relay cannot decrypt `runner_operations` payloads.

**Packages** (`runner-relay/internal/`): `tunnel` (the registry of connected machines and their
multiplexers), `ticket` (verification), `edge` (the browser-facing handler, §7), `signals`
(Redis subscriber and reconcile, §8), `railsclient` (the short calls), `admin` (health and
metrics). No package imports another module's `internal/`.

### 2.3 Deployment shape, and the `aixle-infra` part

Same image build lane as `docker/otlp-ingest` (`images.yml` gains `runner-relay`; the workflow file is
applied by Alex from the task's patch, since agents cannot push `.github/workflows/`, as for
`runner-release.yml`). In this repository: `docker-compose.yml` gains a `runner-relay` service and
`Procfile.dev` a `runner-relay` entry, so the tunnel is developed against the `local` adapter (`DESIGN.md` §12.2)
with the dev Traefik's `terminal-auth` middleware in front.

The `aixle-infra` part is built in its own task (row 16f). The facts below were given by Alex on
2026-11-19 from `aixle-infra` (`kube/helmfile/values/aixle-app/staging.yaml`, `doc/helm/runner-gateway.md`)
and are taken as stated. The chart must have, before phase 4 is validated on staging:

- a Deployment `runner-relay`, **one replica**, `RollingUpdate` with `maxSurge: 1` and
  `maxUnavailable: 0`, `terminationGracePeriodSeconds: 45` (the 30 s drain of §5.4), requests and limits sized by §14,
  and the variables of §2.2 from a Secret (the key and the token) and a ConfigMap;
- a Service, and a `ServiceMonitor` or scrape annotation for `:9090/metrics`;
- **two ingress routes**, both on the **same entrypoint as the hosted terminal routes**, which is
  `TRAEFIK_ENTRYPOINT`: unset on production, which means `websecure` (the app's default in
  `config/settings.yml`), and `intwebsecure` on staging. Staging is reached over the VPN, and its public copy
  comes back into `intwebsecure` through basic auth; the gateway's `/runner/v1` route is on `intwebsecure`
  there too. The chart takes the entrypoint from that value and **never hard-codes `websecure`**. The host is one
  host, the one the hosted routes use (`ContainerRuntime::KubernetesRuntime#route_domain_host`: the sandbox
  host if set, otherwise the app's domain), not "the app host or the sandbox host":
  - `Host(<route_domain_host>) && Path('/runner/v1/tunnel')` to the runner-relay, with **no** `terminal-auth`
    middleware (the runner authenticates with its ticket, §3.1), at an **explicit priority above 100**, the
    priority of the gateway's `/runner/v1` route on staging, so the longer path wins;
  - `Host(<route_domain_host>) && PathPrefix('/t/')` to the runner-relay, **with** `terminal-auth` (the same
    middleware the hosted routes use, `authResponseHeadersRegex` unchanged), at an **explicit low priority above
    the catch-all `web` route's 1, for example 2**. Hosted per-session routes are
    `Host(<route_domain_host>) && PathPrefix('/t/<token>/<surface>')` with no explicit priority, so Traefik ranks
    them by rule length. A relay route that matched two hosts, or was longer, could outrank them and take every
    hosted terminal; `staging.yaml` documents this exact failure for the catch-all, which got `priority: 1` for
    it. With one host and priority 2, a hosted session still reaches its pod, and a hosted session whose route
    is not yet created falls to the runner-relay, which answers `404` for a token it does not know (§7.1);
- **no strip middleware.** The runner-relay strips the surface prefix itself (§7.2), because it needs the
  route token and the surface from the path;
- **a NetworkPolicy** for the pods' own ingress: the `aixle-app` namespace has `allow-ingress-from-same-namespace`
  (`podSelector: {}`) and NetworkPolicies add up, so **the platform's own pods in that namespace reach the
  runner-relay too, not only Traefik.** That is acceptable: agent session pods run in separate runtime
  namespaces, which reach only `web` and `mcp`. 16f adds an ingress rule for Traefik's namespace to `:8080`
  and one for the scrape to `:9090`. This must not be described as "only from Traefik". The relay adds no
  browser authentication (decision 2), so reachability from outside the namespace is controlled by
  Traefik and these policies, and the header cross-check of §7.1 is defence in depth;
- WebSocket timeouts on the entrypoint that do not cut an idle terminal. Hosted terminals already need this, so it
  should hold; 16f checks it.

### 2.4 Health and observability

- `/healthz`: the process serves. `/readyz`: the Redis subscription of §8.1 is live and the last
  reconcile pass (§8.3) is not older than three intervals. It does not depend on Rails being up:
  a Rails outage must not take down the terminals already open.
- **Metrics** (Prometheus): `runner_relay_machines_connected`, `runner_relay_streams_open{surface}`,
  `runner_relay_bytes_total{direction}`, `runner_relay_frames_total{type}`, `runner_relay_stream_resets_total{code}`,
  `runner_relay_tunnel_connects_total{result}` (ok, bad_ticket, replayed, version),
  `runner_relay_dial_seconds` (histogram of open to open_ok), `runner_relay_write_queue_bytes` (per-machine
  maximum), `runner_relay_signal_lag_seconds` and `runner_relay_reconcile_revocations_total` (a reconcile that
  closes something means a signal was lost), `runner_relay_rails_request_seconds{endpoint,status}`.
- **Logs:** JSON through `log/slog`. A machine is logged by environment id, a session by id, a
  route token by its first six characters, a ticket and a token never. A panic in a connection's
  goroutine is recovered, logged and closes that machine's connection, not the process.
- Sentry is not wired in 16c; the metrics above are what an alert reads. Adding the Sentry Go SDK
  later is additive.

## 3. The runner side

### 3.1 Authentication: a short-lived ticket, minted by the gateway

The runner holds an access token (`aracc_…`, 1 hour). The relay must accept the runner's
WebSocket without a long Rails request, and the throttles of PROTOCOL.md §2 (600 per token, 3000
per IP, in `Rack::Attack`) apply to requests that reach Rails, not to the relay.

| | **A. Ticket (Recommended)** | B. The relay validates the access token through Rails | C. The relay reads PostgreSQL |
| --- | --- | --- | --- |
| Flow | The runner `POST`s `/runner/v1/tunnel-ticket` to the gateway with its access token, as to any endpoint. The answer is a ticket: HMAC-signed claims `{e: environment id, r: runner id, s: current session id or null, jti, exp: now + 60 s}`. The runner opens `GET /runner/v1/tunnel` with `Authorization: Bearer artun_<claims>.<mac>` | The relay sends each token it sees to a short internal endpoint that runs the gateway's check order, and caches the answer 5 s | The relay checks the token digest in `runner_credentials` |
| Check order, refusals, `runner_revoked`, `runners_disabled`, the 5 s revocation window | Unchanged: the existing endpoint code runs it | Re-implemented behind a second endpoint | Re-implemented in Go |
| Throttling | **Stays in `Rack::Attack`**: the ticket request is a gateway request, counted per token and per IP. The relay's upgrade needs no Rails call to refuse a bad ticket (a signature check), so a flood of bad upgrades costs the relay CPU only | A new throttle for the internal endpoint, and a flood of bad tokens becomes load on Rails | A flood is database load |
| The relay's secrets | The ticket key only | The internal token | A database credential |
| Cost | One extra short request per connect; a signing key shared with Rails; a ticket is a bearer for 60 s (below) | An internal endpoint to keep identical to the gateway's | Violates the layering: the service would own the credential schema |

**Decision (recommended): A.** The access token never reaches the relay, and nothing the gateway
checks is copied.

- **Endpoint:** `POST /runner/v1/tunnel-ticket`, an additive protocol 1 endpoint (§7 of PROTOCOL.md:
  adding an endpoint is not a breaking change). Access token, the three headers, the standard check
  order and refusals. It answers `409 no_session` when the machine holds no session in v1 (§3.2), so
  an idle machine opens no connection. `200`: `{"ticket": "artun_…", "expires_at": "…Z"}`.
  Rails side: `Runners::TunnelTicket.issue(environment:)` and `RunnerGateway::V1::TunnelTicketsController`
  (a nested resource named for the record it creates, per `implementation-patterns.md`), schema in
  `runner/protocol/schemas/v1/` if it takes a body (it takes none).
- **Single use.** The relay records the ticket's `jti` with `SET relay:jti:<jti> 1 NX EX 90` in Redis
  and refuses a second use (`403 ticket_replayed`). A leaked ticket is thus useless after the runner
  used it, and within its 60 seconds only to a thief who is faster than the runner. If Redis is down
  `/readyz` fails and no connection is accepted.
- **The ticket goes in the `Authorization` header,** never in the URL, so no access log holds it.
- **Version header.** The upgrade carries `X-Aixle-Runner-Protocol: 1` and `X-Aixle-Runner-Version`;
  the relay checks the protocol and the WebSocket subprotocol `aixle-runner-relay.v1` and answers
  `400 unsupported_protocol` otherwise.
- **After the connection is up** the token's own expiry does not matter: the connection's validity
  is the machine's, kept by signals and the reconcile pass (§8), not by a clock. A machine revoked
  or unregistered loses its connection through `machine_revoked` (§8.1), at the latest on the next
  reconcile pass.
- **The upgrade's refusals** are the gateway's JSON shape (`PROTOCOL.md` §3) with two new codes:
  `401 invalid_ticket` (bad signature, expired, malformed), `403 ticket_replayed`. A runner treats
  both as "mint a new ticket and retry once", then backs off.

### 3.2 When the runner connects, and reconnect

- **v1 (this task's cut):** the host runner opens the tunnel when it starts a session container
  (`container.start` succeeded) and closes it when the container is gone. An idle machine holds no
  connection, so the relay's memory follows the number of running sessions. The protocol does not
  assume this: `hello` carries a nullable session id (§5), so the takeover (§10) can keep the
  connection open for an idle machine, and `aixle-runner` decides by a field of the check-in's
  `config`, `tunnel: {"mode": "session" | "always"}`, which the platform sets.
- **Reconnect.** On a lost connection, an `error` close or a missing pong the runner: resets all its
  open streams (closing the dialed TCP connections), asks for a new ticket and reconnects with
  `internal/backoff`'s jittered growth (1 s to 30 s, as the long-poll does). It does not retry
  `invalid_token` forever: the existing refusal table of `PROTOCOL.md` §3 applies to the ticket
  request. A `GOAWAY` (§5) from the relay is not an error: the runner reconnects at once, with
  jitter of up to 2 s, and the old connection drains.
- **Open streams do not survive a reconnect** (§5.6). The terminal is a `tmux attach` and a browser
  client reconnects by itself, so a new stream restores the view with no loss of the session.
- **The tunnel is not a liveness signal.** Losing it does not change the machine's state, the
  session, or the 15-minute grace of `DESIGN.md` §6.7; those are fed by polls and heartbeats only. A session
  with a down tunnel is a session without a terminal, not a failed one.

### 3.3 How the runner reaches the ports

`aixle-runner` gets a `Dialer` interface in the host runner (`runner/internal/tunnel`), one
implementation per way of reaching a session's ports, so `kubernetes` adds its own later:

- **`manual` and `coder`, bridge network.** Through the proxy sidecar (`DESIGN.md` §6.9.3), which is in the
  agent's network namespace. The sidecar gets a second Unix socket, **`dial.sock`**, in a directory of
  the host runner's state directory that is bind-mounted read-write into the sidecar and read by the
  host runner. For each stream the host runner connects to it, writes one line with the port, and the
  sidecar dials `127.0.0.1:<port>` and pipes the two. The sidecar takes the allowed ports on its command
  line at start (from `container.start`'s payload) and refuses any other. This keeps rootless Docker
  working, where a container's IP is not reachable from the machine (`DESIGN.md` §6.9.5); the existing socket
  runs the other way (sidecar to host runner), so a second one is needed. It needs no credential in
  the sidecar.
- **`network: host`.** No sidecar: the host runner dials `127.0.0.1:<port>` itself.
- **`kubernetes`.** The controller dials the pod's IP, behind the required NetworkPolicy
  (`DESIGN.md` §6.9.5, `DESIGN.md` §6.9.7). Row 19.

**The ports.** A machine holds one session at a time (`runner_environments.current_session_id`), so
the tunnel is one session per machine at once, and there is no per-session registry to design.
`container.start`'s payload gains `tunnel`: `{"ports": {"tty": 7681, "view": 7682, "fs": 4040,
"upload": 4041, "ide": 8443}}`. The runner serves exactly these five and no others, for exactly the
session the payload names, and refuses an `open` for another session or port with `RESET refused`.

- **Bridge:** the image's own ports, as above.
- **`network: host`:** `Runners::Tunnel.ports(session)` assigns five consecutive ports from a range,
  `30000 + (session id mod 1000) × 8 + 0…4`, the same way `proxy_port` is derived (8b: the platform
  chooses and sends, so the sides cannot disagree). The environment variables the image reads
  (`TTYD_PORT`, `VIEW_PORT`, `WATCHER_PORT`, `UPLOAD_PORT`, `VSCODE_PORT`) are set from it in
  `container.start`'s `env`. The host runner probes that the five ports are free before it starts the
  container and answers the op with a clear error (`ports_in_use`) otherwise, so a collision with another
  process on the machine fails the session with a readable message (`DESIGN.md` §6.9.7: H2, rare, clear error).
  This refines `DESIGN.md` §6.9.5's sentence "the host runner assigns free ports": the platform assigns, the
  host runner verifies, as with `proxy_port`.

## 4. How the pieces connect

```
 Browser ── https ──▶ Traefik ──ForwardAuth──▶ Rails  GET /api/v1/internal/ws_auth   (unchanged)
                         │
                         └─ /t/<token>/<surface>/…  ─▶ relay :8080 ◀── Redis pub/sub  (§8)
                                                          ▲  │ short HTTP (§8.2)
                                                          │  └──▶ Rails
   Runner ── POST /runner/v1/tunnel-ticket ──▶ gateway     │
   Runner ── WSS /runner/v1/tunnel (ticket) ───────────────┘   one WebSocket per machine
        │ one stream per browser TCP connection
        └─▶ Dialer ─▶ sidecar dial.sock / 127.0.0.1 ─▶ ttyd 7681 · 7682 · watcher 4040 · 4041 · IDE 8443
```

**Why streams are raw TCP.** The relay terminates the browser's HTTP and WebSocket and speaks them
itself; the runner only opens a TCP connection to one of five ports and copies bytes. The runner
needs no HTTP or WebSocket parsing, and a new surface later is a port in a table. In the relay,
`net/http/httputil.ReverseProxy` runs over a `Transport` whose `DialContext` opens a stream, so
keep-alive, WebSocket upgrade, chunked bodies and the IDE's many parallel requests come from the
standard library.

## 5. The relay protocol (version 1)

One WebSocket per machine, binary messages, **one frame per message**. All integers are big-endian.

```
frame  = type (1 byte) | stream id (4 bytes) | payload
```

Stream id `0` is the connection. The relay assigns stream ids, from 1, upward, never reused on a
connection (the browser side is the only one that opens streams in v1, so there is no odd/even split;
a later runner-initiated stream, if one is ever needed, takes a high bit, which is reserved now).

| Type | Code | Direction | Payload | Meaning |
| --- | --- | --- | --- | --- |
| `HELLO` | 0x01 | both, once, relay first | JSON | Version and limits (below) |
| `OPEN` | 0x02 | relay → runner | JSON `{"session_id": 123, "port": 7681}` | Open a stream: dial `port` of the session |
| `OPEN_OK` | 0x03 | runner → relay | none | The dial succeeded; DATA may flow both ways |
| `DATA` | 0x04 | both | up to `max_frame` bytes | Stream bytes |
| `WINDOW` | 0x05 | both | u32 credit, bytes | The sender of this frame may receive that many more DATA bytes |
| `CLOSE` | 0x06 | both | none | Half-close: this side will send no more DATA |
| `RESET` | 0x07 | both | u8 code, optional UTF-8 text | Abort the stream in both directions at once |
| `PING` | 0x08 | both, stream 0 | 8 bytes | Heartbeat |
| `PONG` | 0x09 | both, stream 0 | the same 8 bytes | Heartbeat answer |
| `GOAWAY` | 0x0A | relay → runner, stream 0 | none | No new streams; reconnect (§5.4) |

**`HELLO`.** The relay sends `{"v": 1, "max_frame": 32768, "max_streams": 64, "window": 262144,
"ping_interval": 20, "session_id": 123 | null}` as the first message. The runner answers
`{"v": 1, "max_frame": …, "max_streams": …, "window": …, "runner_version": "…"}` with values at or
below the relay's; the connection uses the minimum of each. Anything else first, or a version the
runner does not speak, closes the WebSocket with code 1002. Unknown fields are ignored and unknown
frame types close with 1002, so a later version can add both.

### 5.1 Streams

- **Open.** The relay sends `OPEN`; the runner checks the session and port (§3.3), dials with a 10 s
  timeout, and answers `OPEN_OK` or `RESET` (`refused`, `dial_failed`, `timeout`). Data sent before
  `OPEN_OK` is not allowed: the relay waits for it. (The cost is one round trip on a new stream, and a
  stream of the same upstream connection is reused by HTTP keep-alive, so it is paid once per TCP
  connection, not per request.)
- **Half-close.** `CLOSE` ends one direction, like a TCP FIN. The other side may keep sending. A
  stream is finished when both sides sent `CLOSE`, or after any `RESET`. Frames of a finished stream id
  that arrive later (they were in flight) are dropped; a `DATA` after the peer's `CLOSE` on a live stream
  is a protocol error and resets the stream (`protocol`).
- **Reset codes** (the payload's first byte): `1 cancelled` (the browser went away), `2 refused`
  (not this session or not one of the five ports), `3 dial_failed`, `4 timeout`,
  `5 session_changed`, `6 revoked` (the machine, or the session, §8), `7 flow_violation`,
  `8 protocol`, `9 internal`, `10 shutdown`. The text is for logs only.

### 5.2 Flow control

Credit-based, per stream and per direction, as in HTTP/2 but with no connection-level window.

- Each side starts with `window` bytes of credit for the peer (the negotiated `window`, 256 KiB). A
  sender may have at most that many `DATA` bytes unacknowledged on a stream, and a receiver's buffer
  for the stream is therefore bounded by the same number. A receiver that gets more resets the
  stream with `flow_violation`.
- The receiver sends `WINDOW` with the bytes it has handed on to its local connection, once at least
  half the window is owed, so the typical interactive stream sends few of them.
- A sender with no credit waits, and backpressure reaches the TCP connection on its own side. One
  stalled stream (a browser that stopped reading a large IDE file) stalls only itself.
- **Bound for the connection:** `max_streams × window` of buffered data per direction, 16 MiB at the
  defaults. This is what one machine can cost the relay, and it is the number §14 sizes the pod by.
- **Fairness.** Each side writes with one goroutine per connection that takes ready frames from the
  streams in turn, one `DATA` frame each, after any control frame (`WINDOW`, `RESET`, `PING`, `PONG`,
  `CLOSE`, `OPEN`). A terminal's keystroke is not queued behind an IDE download. The frame is at most
  `max_frame` (32 KiB), so a control frame waits for at most one data frame.

### 5.3 Limits

| Limit | Default | When exceeded |
| --- | --- | --- |
| Frame payload | 32 KiB (`max_frame`; the hard ceiling for any negotiation is 64 KiB) | Close 1009 |
| Concurrent streams per machine | 64 | The relay does not send the `OPEN`: the browser request gets `503` with `Retry-After: 1` (a WebSocket upgrade, close 1013). A runner that receives an `OPEN` above its limit answers `RESET refused` |
| Stream window | 256 KiB | `RESET flow_violation` |
| Time to `OPEN_OK` | 10 s | `RESET timeout` |
| Connections per machine | 1 | A second one replaces the first: the old one is closed with 4000 `replaced` (the same rule as "one waiting poll per machine", `DESIGN.md` §6.1) |

There is **no per-IP limit** on new tunnel connections (Alex, 2026-11-19). After a relay restart, a customer with more than a few dozen machines behind one NAT address would be refused with `429`s on exactly the reconnect that matters. A bad ticket costs the relay one signature check, and minting tickets is already throttled by `Rack::Attack` at the gateway.

### 5.4 Heartbeat, `GOAWAY`, close

- The relay sends `PING` every `ping_interval` seconds (20 s); the runner answers `PONG`. Either side
  that has received no frame of any kind for three intervals (60 s) closes the connection. The runner
  also sends its own `PING` if it has heard nothing for one interval, so a half-open path is found from
  both ends. Application-level pings are used, not WebSocket control frames, because intermediaries
  answer the latter.
- `GOAWAY` tells the runner to finish its open streams (the relay accepts no new `OPEN` on this
  connection) and reconnect; the relay closes the connection when the last stream ends or after 30 s.
  The relay sends it on shutdown, on `replaced`, and when a drain is requested from the admin port.
- WebSocket close codes: 1000 normal, 1002 protocol, 1009 too large, 1013 try again, 4000 `replaced`,
  4001 `revoked` (the machine no longer holds a session, or is revoked), 4002 `ticket`.

### 5.5 What happens to open streams

| Event | Streams |
| --- | --- |
| The browser's connection ends | The relay sends `RESET cancelled` and frees the stream; the runner closes the dialed TCP connection at once. A graceful browser close first sends `CLOSE` |
| The dialed TCP connection ends (ttyd exits, the container stops) | The runner sends `CLOSE`, or `RESET internal` on an error; the relay closes or aborts the browser side |
| The runner stops the session container (`container.stop`) | The runner resets every stream with `session_changed` before it stops |
| The machine's connection is lost, or `GOAWAY` finishes | All streams are lost on both sides. The relay answers the browser: an HTTP request in flight `502`, a WebSocket close 1012. Nothing resumes |
| `revoked` or `session_changed` from a signal (§8) | The relay sends `RESET` with that code for each affected stream and closes the browser's side (HTTP: connection closed; WebSocket: close 1008 for `revoked`, 1012 for a session change) |

### 5.6 Why no stream resumption

Resuming a stream after a reconnect needs both sides to retain unacknowledged bytes and agree on an
offset, which is the complexity `DESIGN.md` §6.9.7 rules out for a rare case with no data at risk: the terminal's
state is in tmux, the IDE's in the container, and an upload is retried by its client. The cost is a brief
blank terminal on a network blip, which the session page already recovers from by reconnecting ttyd.

## 6. Cleanup, revocation and caps, in one place

1. **A browser disconnect** is `RESET cancelled` (§5.5). Nothing outlives the browser's TCP connection
   by more than one frame round trip.
2. **The machine's current session changes** (assigned, released, or replaced): the relay resets every
   stream of the old session with `session_changed`. A new session on the same connection gets new
   streams only (the runner checks the `session_id` in each `OPEN`).
3. **A viewer's authorization is checked when a browser connection opens, and not again while it stays
   open** (Alex, 2026-11-19: as hosted). `terminal-auth` (`ws_auth`) runs for each new HTTP request and
   WebSocket upgrade, so a viewer whose access was removed cannot open a new connection; a terminal that is
   **already open outlives the removal until it is closed**, as on a hosted container. The relay keeps no
   viewer table and has no per-viewer revocation. Making this stricter is a separate task for hosted and
   runner sessions together. What does end open connections is the session or the machine: item 4 and
   `session_ended` (§8.1).
4. **The machine is revoked, unregistered, or its runner deleted, or the company's `external_runners`
   flag is turned off:** the connection closes with 4001 and every browser connection of that session
   closes with it.
5. **Limits** are §5.3. One viewer cannot starve another: streams are shared per machine, and the
   64-stream cap is per machine, not per viewer (a single session has few viewers; if one proves to
   be a problem the cap becomes per viewer, which the registry already has the keys for).

## 7. The browser side

### 7.1 Routing to the relay, and finding the machine

Hosted sessions get per-session `IngressRoute`s from `KubernetesRuntime` (`create_ingressroute`:
five routes, `tty` 7681, `fs` 4040, `ide` 8443, `view` 7682, `upload` 4041, each behind `terminal-auth`
and, except `ide`, a `stripPrefix`). A runner session creates none of that: one static route in
`aixle-infra` (§2.3) sends every `/t/…` that no hosted route claimed to the relay, behind the same
`terminal-auth` middleware. **The platform does not create anything per runner session.**

Traefik runs `ws_auth` first. On success the request reaches the relay with `X-User-Id` and
`X-Session-Id` set by `WsAuthController`, only the `vscode-*` cookies kept, and the sandbox cookie set
on the response, exactly as for a hosted pod.

In the relay:

1. Parse `/t/<route_token>/<surface>/<rest>`. A surface other than the five, or a malformed token, is
   `404` (`ws_auth` treats an unknown surface as owner-only `tty`, which is safe, but nothing is served).
2. **Find the session and its machine.** The registry (§7.3) maps the route token to
   `(session id, environment id, ports)` from the `machine_session` signal (§8.1); on a miss, one short
   call, `GET /api/v1/internal/runner_relay/holders/:route_token` (§8.2), asks Rails, which answers from
   `runner_environments.current_session_id` and the session's `route_token`. A token Rails does not know
   is `404`; a session not held by a machine, or a machine not connected, is `503` with `Retry-After: 2`
   (a runner session whose tunnel is briefly down is not gone).
3. **Cross-check.** `X-Session-Id` must equal the session id found by the token. A mismatch is `403`.
   The relay trusts the header only because Traefik wrote it after `ws_auth` and the NetworkPolicy of §2.3
   admits nobody else, and checks it against the token as defence in depth.
4. Map the surface to the port from the registry's `ports` (the five of §3.3), open a stream, proxy.

**Why a session maps to a machine only through the platform.** A runner is never believed about *which
session it holds*: its `HELLO` reply says nothing of it. If it were, a malicious machine of one company could claim another company's session and receive
that session's viewers' traffic. The mapping comes from Rails (the ticket's `s` claim at connect, then
`machine_session` signals, with the holders call as the fallback), and the runner **enforces the same**
in the other direction: it serves only the session its own `container.start` created.

### 7.2 Path and cookies

- `tty`, `view`, `fs` and `upload`: the relay strips `/t/<token>/<surface>` (as the hosted
  `stripPrefix` middlewares do); `ide` is **not** stripped, because OpenVSCode runs with
  `--server-base-path /t/<token>/ide`.
- Forwarded headers: the request as Traefik delivered it (the cookie list `ws_auth` set, the
  `X-Forwarded-*` Traefik adds). The relay removes hop-by-hop headers, `X-User-Id` and `X-Session-Id`.
- Upload (`upload`, 4041) and pasted images are owner-only by `ws_auth` (`OWNER_ONLY_SURFACES`), unchanged.

### 7.3 The registry

An in-memory map, behind an interface so the multi-replica option of §11 replaces the implementation and
not the callers:

```go
type Registry interface {
    Machine(environmentID int64) (*Machine, bool)
    BySession(sessionID int64) (*Machine, bool)
    ByRouteToken(token string) (SessionRoute, bool)
    // Add, Remove, SetSession(environmentID, sessionID, routeToken, ports)
}
```

Each `Machine` owns its multiplexer, its open browser connections per session (to close them on
`session_ended` and `machine_revoked`) and its connection's cancel function. There is no viewer table.

## 8. Signals: how the relay learns without long Rails requests

### 8.1 Pub/sub from Rails

Rails publishes JSON on one channel, `runner_relay`, through `ActionCable.server.pubsub.broadcast`, after
the transaction commits (`ActiveRecord.after_all_transactions_commit`), the way `Runners::Operations#wake`
does, and logs and swallows a failed publish (the reconcile pass of §8.3 is the safety net). The relay
subscribes with `RUNNER_RELAY_REDIS_CHANNEL_PREFIX` + `runner_relay`.

| `type` | Published when | Relay does |
| --- | --- | --- |
| `machine_session` `{environment_id, session_id \| null, route_token, ports}` | A session takes or leaves a machine (`Runners::Machines`, the `current_session_id` writes of `Runners::Revocation`) | Updates the registry; resets the streams of the previous session (`session_changed`) |
| `session_ended` `{session_id}` | A runner session leaves `ready` for any reason (a state-machine callback on `TerminalSession`) | Resets that session's streams (`revoked`), closes its browser connections |
| `machine_revoked` `{environment_id}` | Revoke, unregister, runner deleted (`Runners::Registration`, `Runners::Revocation`) | Closes the machine's connection (4001) |

Redis pub/sub is fire-and-forget. **A message can be lost** (a Redis restart, a relay's reconnect).
The design therefore treats a signal as a hint that makes the common case immediate, and the reconcile
pass as the guarantee.

| Signal channel options | Cost |
| --- | --- |
| **Pub/sub plus the reconcile pass (Recommended)** | Cheap; the same mechanism as `runner_env_<id>`; a lost message is repaired within the check interval (60 s) |
| Redis Streams with a consumer group | Durable and ordered, but per-pod consumer state and trimming to build, for events that the reconcile pass already makes safe |
| Rails polled by the relay every few seconds | No Redis dependency, but a steady request load that grows with machines, which is what the service exists to avoid |
| PostgreSQL `LISTEN/NOTIFY` from Go | Couples the service to the database and its connection limits |

### 8.2 The short calls to Rails

Authenticated with `Authorization: Bearer <RUNNER_RELAY_INTERNAL_TOKEN>`, compared in constant time, in
`Api::V1::Internal` (which skips the user-facing machinery, `internal/application_controller.rb`). Each
answers in milliseconds and holds no connection.

- `GET /api/v1/internal/runner_relay/holders/:route_token` (`Api::V1::Internal::RunnerRelay::HoldersController#show`):
  `{session_id, environment_id, state, ports}`; `404` when no runner session has the token.
- `POST /api/v1/internal/runner_relay/checks` (`...ChecksController#create`), body
  `{"machines": [{"environment_id": 7, "session_id": 123}]}`, answer `{"machines": [true]}`. A machine is
  valid when it is registered, its runner is not revoked, the company's `external_runners` flag is on and it
  still holds that session (and that session is still `ready`).

**No change to `WsAuthController`.** The relay does not decide viewer authorization, so nothing is extracted
from it: `terminal-auth` stays the only authorization of a browser (decision 2).

### 8.3 The reconcile pass

Every `RUNNER_RELAY_CHECK_INTERVAL`, and after every Redis (re)subscription, the relay sends one `checks`
request with all its connected machines and the session each holds, and revokes what comes back `false`
exactly as a signal would. One request, batched, regardless of the number of machines. This bounds how long
a lost `machine_session`, `session_ended` or `machine_revoked` signal can go unnoticed: **60 s at the
longest**. It covers machine- and session-level changes only; a viewer's access is not part of it (§6, item 3).

A Rails outage makes a pass fail: the relay keeps what it has and retries with backoff. It never closes a
connection because Rails did not answer.

## 9. The live view of a runner session's terminal

Row 8c built no live-log chunks (`DESIGN.md` §6.5, `DESIGN.md` §6.9.4); a runner session's page shows no live terminal until the
tunnel. **Nothing new rides the tunnel for this**: the live view of a hosted session is its ttyd
WebSocket, reached at `websocket_url` (`/t/<token>/tty/ws` for the owner, `/view/ws` for everyone else,
from `TerminalSessionResource`), and that URL already exists for a runner session, because a route token is
generated for every `TerminalSession` (`before_create :generate_route_token`). Once the relay serves `/t/…`
the page, the read-only viewers, the IDE link (`ide_url`), the file panel (`watcher_url`) and the upload
(`upload_url`) work as on hosted. What 16g changes is only what hides them:

- `Runners::Selection.refusal`'s `:interactive` refusal and the new-session form's disabled runners ("can't
  run interactive sessions yet") go;
- the capability table's `interactive_terminal` becomes true on every type (`DESIGN.md` §4);
- the session page's runner-specific "no live terminal" state, if the page has one, goes. (16g looks for it;
  none was found by this design's search.)

The exec-based snapshot (`Sessions::Snapshot::ExecSource`, `get_session_log`, `NoOutput`) is **not**
touched: it feeds the monitor and the MCP tool, not the browser.

The one new behaviour is **readiness**. Hosted sessions wait for their ports before `ready`
(`DockerRuntime#wait_for_ports`); a runner session is `ready` when its container runs (`DESIGN.md` §6.9.4), possibly before
ttyd listens. A dial that fails in that window is `RESET dial_failed` and the browser gets `502`; ttyd's
own client and the page's frame retry. 16e measures how long the window is on the local adapter, and if it is
visible, `container.start` waits for the five ports (the runner checks them with the same dial) before it
answers, which keeps the platform's `ready` honest and costs a few seconds of session start. **Open choice,
left to 16e with its measurement.**

## 10. The takeover: the ops long-poll and the callback proxy

This task designs the end state. Moving the pieces is rows 24 to 26 of §15.

### 10.1 What the end state is

`/runner/v1/*` has only short requests, served by the web application. The relay holds every long
connection and is the only deployment with a long-lived-connection budget:

| Path | Today | End state |
| --- | --- | --- |
| `GET /runner/v1/ops` (long-poll, ≤25 s, one per machine) | A `runner-gateway` Puma thread, with Redis pub/sub | The relay holds the wait; Rails answers only short reads (§10.2) |
| `ANY /runner/v1/proxy/:route/*` (about one per running session, up to 15 minutes) | A gateway thread, `ActionController::Live` | The relay streams; Rails only authorizes (§10.3) |
| `/runner/v1/tunnel` | — | The relay |
| Everything else (`register`, `token`, `check-in`, `heartbeat`, `ops/:id/result`, releases, `tunnel-ticket`) | The gateway | The web app |

### 10.2 The ops long-poll

The wire does not change: the runner still sends `GET /runner/v1/ops?after=&wait=` and still gets the same
answers (`PROTOCOL.md` §5.4), so no runner release is needed and protocol 1 stands. The ingress sends that
one path to the relay. For each request the relay:

1. forwards it to Rails **with `wait=0`**, the client's headers and its address in `X-Forwarded-For`;
2. if Rails answers anything but `200 {"ops": []}` (ops, an `update`, a refusal, a `429`), answers the same;
3. otherwise reads the channel from the answer's `X-Aixle-Runner-Wake: runner_env_<id>` header (added to the
   empty `wait=0` answer by the gateway code; the relay strips it) and makes sure it is subscribed to that
   channel (with the Action Cable prefix). **The subscription is kept per connected machine between polls**
   (dropped 60 s after the machine's last poll), so in steady state it is already live before the first read
   and no second read is needed to close the gap. Only a machine's first poll after it was away (no live
   subscription) subscribes **and then forwards once more**, so an op enqueued between the first read and the
   subscription is seen by the second. Then the relay waits up to `wait` seconds for a message;
4. on a message, or at the end of the wait, forwards with `wait=0` again, which is the "check after the wait"
   of `PROTOCOL.md` §3 for free, and answers what Rails answers.

**The count.** With the subscription kept, an idle cycle makes **two** short requests to Rails: the first read
and the read after the wait. A cycle that follows a gap makes three (a machine's first poll). Without the kept
subscription every cycle would make three (the first read, the read after subscribing, the read after the
wait). Rows 24 and §14 use the recommended two: 1,000 machines are about 80 requests a second to the web app
(about 120 a second if the subscription were not kept). The cost of keeping it is one Redis subscription per
connected machine (in Go a map of channels over one connection, not one socket each) and a 60 s tail after a
machine stops polling.

The `runner_env_<id>` message types (`op_enqueued`, `poll_waiting`) and the rule "a newer waiting poll ends the
older one" move to Go unchanged: the relay announces on subscription and a waiting poll that hears another's
announcement answers `{"ops": []}`. Both implementations speak the same channel, so the rollout can move
machines over with the ingress alone.

**Where the token check and the throttles end up.** Nowhere new: **every request the relay forwards is a real
short request to the web app,** so the token and the check order of §3 are the existing code, and
`Rack::Attack` counts it per bearer digest and per IP as it does today. Costs:

- two short requests per idle poll cycle instead of one held one (about 2 per machine per 25 s; 1,000 machines
  are about 80 requests a second to the web app, 120 if the subscription were not kept), against the 600 a minute
  limit of one token (about 5 a minute from a poll loop), far below it;
- `Rack::Attack`'s per-IP count must see the runner's IP, so the web app must trust the relay's
  `X-Forwarded-For` (the same `ActionDispatch::RemoteIp` trusted-proxy list that the ingress needs);
- the relay itself limits what it holds without asking Rails: one waiting poll per bearer digest, and a cap on
  waiting polls per client IP (a flood of requests with *different* garbage tokens never reaches a wait, since
  the first forward answers `401`, so this is only a concurrency guard).

#### 10.2.1 Option for row 24: commands over the runner's persistent WebSocket

Requested by Alex (2026-11-19) as a direction to consider **before row 24 is cut**. It is **not decided
now**: row 24 decides it when it is cut. The idea: once the relay is in Go, one WebSocket per machine held
at all times costs little, and the relay, which already listens to `runner_env_<id>`, tells the runner over
that connection when there is work, so the long-poll goes away.

| | **(a) Wake frame, then one short read (Alex's preference to start with)** | (b) The relay fetches the ops and pushes them |
| --- | --- | --- |
| How | The relay sends a `WAKE` frame (stream 0, relay to runner). The runner then makes one `GET /runner/v1/ops?wait=0` to Rails, as the runner does at the end of a poll today | On a wake, the relay reads the ops from Rails and sends them as frames; the runner answers results as now |
| Token check, check order, `Rack::Attack` | Stay in Rails: the read is an ordinary gateway request with the machine's token | The relay would need the machine's token (it never sees it, §3.1) or an internal endpoint that repeats the check order and the throttle, and the two would drift |
| Delivery | The ops wire (`after=`, results, replay) is the one that exists | A second delivery path with its own acknowledgement and replay rules |
| Cost | One short request per op, plus a fallback read (below) | Less latency, a new endpoint and a new contract |

What it means for the rest of the design, for either variant:

- **The tunnel's `mode: always` (§3.2).** The option needs the connection open for an idle machine, so the
  platform sets `tunnel: {"mode": "always"}` for runners that use it. The relay's memory then follows connected
  machines, not running sessions: an idle connection holds only its goroutines and small buffers (windows are
  per open stream), but 1,000 machines are 1,000 held connections and the pod is sized for it in 16f/row 24.
  The ticket is minted per connect, not per session, and `HELLO`'s `session_id` is already nullable (§5).
- **Protocol version.** HTTP protocol `1` does not change. `WAKE` is a new relay frame type, and an unknown frame
  type closes the connection with 1002 (§5), so it is **negotiated**: the runner's `HELLO` reply declares
  `"wake": true`, and the relay sends `WAKE` only to a runner that did. This is an additive field and needs no
  new relay protocol version.
- **Runners that still poll.** Every runner without the feature, and any runner whose network breaks
  WebSockets, keeps the long-poll through the relay as §10.2 describes; both paths stay until the last old
  runner is gone. A runner with a live tunnel and `wake` stops long-polling and reads on `WAKE`.
- **Liveness.** The tunnel is not a liveness signal (§3.2) and the platform's offline detection is fed by polls.
  So a runner on this path still makes a `wait=0` read on a fixed fallback interval (for example every 25 s),
  which doubles as the lost-wake safety net. That is one request a machine per interval, against two in the
  long-poll's steady state, and the tunnel's loss is covered by falling back to the long-poll at once.
- **Row 24's decision.** Cut it with the measured request load of §10.2, the number of idle connections the
  relay holds, and whether (a) is enough. (b) is recorded as an option and not recommended.

The alternative, authenticating and counting in Go (a cached check, a second copy of `Rack::Attack`'s windows
in Redis), is rejected for the takeover: it would duplicate the check order and the throttle, and the two would
drift. It remains open if the request load above is ever a problem (§16).

### 10.3 The callback proxy

`RunnerGateway::V1::ProxiesController` does three things in one thread today: it authenticates and checks the
route and the session key (`Runners::Proxy.holder`), it forwards the request, and it streams the answer. The
first is short and stays in Rails; the other two move to the relay.

1. The relay sends Rails **an authorization request** carrying the bearer, the three runner headers, the route,
   the method, the path below the route and the headers `Runners::Proxy.holder` reads (`X-Session-Key`,
   `X-Session-Id`, `X-Agent-Key`, `X-Git-Key`, `X-Azure-Git-Key`, `X-Cloud-Key`), no body. The endpoint is
   `POST /runner/v1/proxy-authorizations` (a gateway endpoint, so the standard check order, flag and
   `Rack::Attack` apply: it counts as the request it replaces). The service takes named parameters and never
   sees the request (§6.1), so the controller change is small.
2. Rails answers a refusal (the existing `route_not_allowed`, `session_not_on_environment` and the
   `X-Aixle-Runner-Refusal` header) or `200` with `{"upstream": "<the route's hosted address>", "headers":
   {"X-Aixle-Runner-Environment": "…"}}`.
3. The relay forwards the original request, body streamed, to that address (the bearer and gateway headers left
   out), and streams the answer back. No thread or database connection of Rails is held while it streams.

**What does not move:** the upstream endpoints themselves. An MCP call that runs 15 minutes still holds a
thread in the process that serves `/action_mcp`; the takeover moves the *proxy's* wait out of the gateway and
leaves the upstream's cost where hosted agents already put it (the MCP process, `config/puma_mcp.rb`). The
relay's forward to `mcp` targets that process's address as the gateway's does today.

### 10.4 Removing the `runner-gateway` deployment

Row 26, after rows 24 and 25 have run with the ingress on the relay for a stable period:

1. The web process draws `config/routes/runner_gateway.rb` as well (`config/routes.rb` loses its
   `AIXLE_PROCESS_MODE` branch, and `/runner/v1/*` stops answering `404` in the web process). The routes already
   exist, and the controllers are `ActionController::API` with no session and no CSRF, so they do not need the
   gateway to run.
2. **The 2 MiB body cap** moves from Puma's `http_content_length_limit` in `config/puma_runner_gateway.rb`
   to a Traefik `buffering` middleware (`maxRequestBodyBytes`) on `/runner/v1`, so the `413` stays pre-application
   (an `aixle-infra` change; PROTOCOL.md §2 keeps its words). The test of the `413` moves with it.
3. Delete `config/puma_runner_gateway.rb`, the `runner_gateway` Procfile entry and Compose port, the
   `AIXLE_PROCESS_MODE` code, `config/application.rb`'s Action Cable exclusion, and `ActionController::Live` from
   `ProxiesController`. The `runner-gateway` Helm deployment and `doc/helm/runner-gateway.md` go in `aixle-infra`.
4. The web app's thread budget: it takes the gateway's short requests only, about two per machine per 25 s (§10.2) plus
   results, heartbeats and proxy authorizations. Sizing is part of the row.
5. `RUNNER_GATEWAY_*` settings are removed.

After this, the Rails app holds no long request for a runner at all. `Rack::Attack`, the token checks and
`Runners::*` are exactly where they are today, in the web app.

## 11. Multi-replica options (recorded, not built)

One replica is a decision (3). A machine's connection lives in one pod, and a browser's request can reach
any, so more than one replica needs a way to find the pod. The `Registry` interface (§7.3) is the seam.

| | **A. Redis registry and pod-to-pod forwarding** | B. Sticky routing by machine | C. Streams through Redis |
| --- | --- | --- | --- |
| How | On connect a pod writes `relay:machine:<env id> → pod address` with a 45 s TTL, refreshed every 15 s, deleted by compare-and-delete. A pod that gets a request for a machine it does not hold forwards it to the owner's pod over an internal listener | Make the browser and the runner land on the same pod by hashing the same key | Frames travel as Redis messages between pods |
| Cost | One more hop for the request that lands elsewhere (pod-to-pod, inside the cluster); a stale entry after a pod dies (a TTL's worth of `503`); an internal listener to protect | The runner and the browser share no key at the ingress (a machine id against a route token), so it needs the ingress to hash a path segment or a pod-addressed route, which Traefik does not do natively | Every byte of every terminal through Redis; latency and Redis load that grow with traffic |
| Signals | Already broadcast to all pods; each applies only what it holds | — | — |

**Recommended when the time comes: A.** Signals need nothing (every pod subscribes). The reconcile pass is
per pod. `GOAWAY` and `replaced` already make a pod rotation routine. What 16 builds toward it: the
registry interface, `X-Forwarded-*` handling that does not assume a single hop, and metrics per pod. A
rolling deploy of the single replica (§2.3) briefly has two pods and the registry in each is empty of the other's
machines: the `503 Retry-After` of §7.1 covers it, and the runner reconnects within seconds.

## 12. Testing approach

Follows `docs/testing.md` and each area's existing conventions.

- **`runner/protocol/tunnel` (Go):** table tests of the codec; the multiplexer between two in-memory
  connections: open, data in both directions, half-close in both orders, reset races (reset while data is in
  flight), flow control (a sender blocks at zero credit, a window update releases it, an oversized frame
  resets the stream), fairness (a busy stream does not delay a ping or another stream), the stream cap, the
  heartbeat timeout with a fake clock. `go test -race`.
- **Fixtures.** `runner/protocol/fixtures/v1/tunnel/` holds frame sequences (a byte-exact hex for each frame
  type and a sequence per scenario above), run by the Go package, and by the Rails tests for the one Rails-side
  contract (the ticket, `tunnel-ticket`'s fixtures in the existing `ops`/`register` format), as the other
  endpoints do through `runner_protocol_conformance_test.rb`.
- **`runner-relay/` (Go):** the ticket verifier (valid, expired, replayed, wrong key, wrong version), the edge handler
  with a fake machine (routing by token and surface, the header cross-check, the path strip, `ide` unstripped,
  `503` for a disconnected machine, `404` for a stranger), signal handling (`machine_session`, `session_ended`,
  `machine_revoked`, a lost signal repaired by the reconcile pass against a fake Rails), and a Redis test
  instance for the subscriber, as `docker/otlp-ingest` tests its own HTTP surface.
- **Rails:** `Runners::TunnelTicket` and the endpoint (every refusal of the check order, the ticket's claims, the
  per-token throttle counting it); the publishers (a signal after commit, none on rollback, a failed publish
  swallowed); `Api::V1::Internal::RunnerRelay::*` (the internal token, tenant isolation: another company's
  session token answers `404`); 
- **End to end,** against the `local` adapter in Compose with the dev Traefik: a runner session's terminal
  opens, takes keystrokes and shows output; a second viewer gets the read-only terminal and not the owner-only
  surfaces; the IDE loads; an upload works; killing the relay and restarting it brings the terminal back
  with no session failure; ending the session or revoking the machine closes the stream within a pass. Playwright
  (`test/playwright`) for the page.
- **Staging validation** is a phase 4 check in the style of `DESIGN.md` §12.4, a QA task (row 16g), run on a real machine.

## 13. The cut

Each row merges on its own behind the flags, `develop` releasable after each. Row 16 of `DESIGN.md` §15 becomes 16a (this
design) and 16b to 16g. The takeover rows 24 to 26 follow in the same table.

| Task | Content | Depends on |
| --- | --- | --- |
| **16b** | **The tunnel package.** `runner/protocol/tunnel`: codec, multiplexer, flow control, fairness, limits and heartbeat over an abstract connection, with the in-memory test harness and the fixtures `fixtures/v1/tunnel/`. `PROTOCOL.md` gets a new section for the relay frames (§5 above) and removes the "not in protocol 1 yet" line for the tunnel. Go CI job unchanged (it already covers `runner/`). No service, no Rails | — |
| **16c** | **The service skeleton and the runner's connection.** `runner-relay/` module, config, `/healthz` `/readyz` `/metrics`, the Dockerfile, a Go CI job (`runner-relay (Go)`, in the required `Checks`), the `images.yml` entry (a patch for Alex); the `Settings.runners.relay` keys; `Runners::TunnelTicket` and `POST /runner/v1/tunnel-ticket` with `PROTOCOL.md` §5.11 and fixtures; the ticket verifier and `jti` replay guard; `GET /runner/v1/tunnel` upgrade, `HELLO`, heartbeat, `replaced`, `GOAWAY`; the runner's `tunnel` manager (ticket, connect, reconnect with backoff); Compose and `Procfile.dev`. A machine connects while it holds a session; no browser path yet | 16b |
| **16d** | **The platform's half.** `Runners::Tunnel.ports(session)` and `tunnel` in `container.start`'s payload (with the schema and the fixture change) and the `network: host` port variables; the `runner_relay` publishers (`machine_session`, `session_ended`, `machine_revoked`); the internal `holders` and `checks` endpoints and the relay's internal token. The relay does not consume them yet | 16c |
| **16e** | **The browser path.** The relay's edge handler (routing by token and surface, the stream `Transport`, path rules, header cross-check), signal subscription, the reconcile pass, revocation; the runner's `Dialer`s (the sidecar's `dial.sock` and the `network: host` dial) and the port check at start (`ports_in_use`); the readiness measurement of §9. End to end on the `local` adapter in Compose. `external_runners` stays on the test company only | 16d |
| **16f** | **`aixle-infra`.** The Deployment, Service, Secret and ConfigMap, the two ingress routes of §2.3 (on `TRAEFIK_ENTRYPOINT`, one host, explicit priorities), the NetworkPolicy ingress rules, the scrape and the alerts. A separate repository's task, which can start once 16c's image exists | 16c |
| **16g** | **Parity and the first customers.** Lift `interactive_terminal` (`Runners::Selection`, the capability table, the form's disabled runners and the builder); the session page; the user guide text; the staging validation of the interactive path on a real machine (QA); then `external_runners` can go to the first named companies (`DESIGN.md` §12.2, phase 4). `PROTOCOL.md` is checked against what was built | 16e, 16f |
| **24** | **The ops long-poll moves into the relay** (§10.2): `X-Aixle-Runner-Wake` on the empty `wait=0` answer, the relay's `/runner/v1/ops` handler with the subscription, the per-machine subscription kept between polls, the replace rule, the trusted `X-Forwarded-For`, the ingress route; the gateway keeps answering the path until the ingress moves. **Decides first whether commands go over the runner's persistent WebSocket instead (§10.2.1); variant (a), a wake frame and one short `wait=0` read, is preferred (Alex, 2026-11-19), and the decision is made when this row is cut** | 16g |
| **25** | **The callback proxy moves into the relay** (§10.3): `POST /runner/v1/proxy-authorizations`, the relay's streaming forward, the ingress route; `ProxiesController` keeps its forward for the rollout and loses it in 26 | 24 |
| **26** | **Remove the `runner-gateway` deployment** (§10.4), with the `aixle-infra` part: the web app serves `/runner/v1/*`, the body cap in Traefik, the Puma file, the Procfile, the Compose port, the process-mode code, `ActionController::Live`, the chart and its doc | 25 |
| 27 (deferred) | **More than one relay replica** (§11): the Redis registry and forwarding. Cut when a deployment needs it | 16g |

16f runs in parallel with 16d and 16e. 24 to 26 are not part of the phase 4 release.

## 14. Edge cases and risks

Harm levels are those of `DESIGN.md` §6.9.7 (H1 security or data loss, H2 a session that fails or hangs, H3 degraded with a workaround, H4 cosmetic).

| Case | Harm (`DESIGN.md` §6.9.7) | Decision |
| --- | --- | --- |
| The relay restarts or is deployed: every tunnel drops | H3, often | Runners reconnect in seconds with jitter; a terminal reconnects through ttyd; the session is not affected (§3.2). `GOAWAY` and the rolling update make a planned restart a drain |
| A ticket is stolen in its 60 s | H1, rare | Single use (`jti`), header-only transport, 60 s; stealing needs the runner's TLS session or its token request |
| A browser, or any pod in the `aixle-app` namespace, reaches the runner-relay directly, skipping Traefik | H1 | The namespace's `allow-ingress-from-same-namespace` lets the platform's own pods in; agent session pods run in other namespaces and reach only `web` and `mcp`. The header cross-check (§7.1) is defence in depth. Same position as a hosted pod |
| A malicious machine claims another company's session | H1 | The session-to-machine mapping comes from Rails only (§7.1); the runner enforces the session it created |
| A viewer's access is removed while a terminal is open | H3 | The open terminal stays until it is closed, as on hosted (§6, item 3). Not re-checked; a separate task for hosted and runners together |
| A signal is lost | H2, rare | The same pass (§8.3), and a re-sync after every resubscription |
| Redis is down | H2 | `/readyz` fails for new connections; open streams continue; the reconcile pass cannot run until Redis answers, but it needs Rails, not Redis, so it still runs |
| Rails is down | H3 | Open streams continue; new tunnel tickets cannot be minted and a reconnect fails until Rails returns |
| ttyd not listening yet | H4 | `502` and the client retries; §9 measures it |
| `network: host` ports taken | H2, rare | The runner probes and fails `container.start` with `ports_in_use` |
| A rootless Docker's socket permissions for `dial.sock` | H2, sometimes | 16e verifies on the staging machine's configuration; the existing socket works with the same ownership approach in the other direction |
| Memory: 16 MiB per machine at full windows | H2, rare | Sized in 16f from the metric `runner_relay_write_queue_bytes`; the caps are configuration. A session uses a few hundred KiB in practice |
| A large IDE download stalls a terminal | H4 | Per-stream windows and the writer's fairness (§5.2) |
| The time skew between Rails and the relay, over 60 s | H2, rare | The ticket's `exp` is checked with 5 s tolerance; `runner_relay_tunnel_connects_total{result="bad_ticket"}` shows it |
| Hosted routes for a session not yet created fall to the relay | H4 | `404` for an unknown token (§7.1), which a hosted pod's route replaces as soon as it exists |
| The takeover's two short requests per poll cycle (three after a gap) | H3 | Within the limits (§10.2); revisit with real load |

## 15. Decisions and assumptions

| # | Decision | Source |
| --- | --- | --- |
| 1 to 4 | The four decisions of §1 | Alex, 2026-11-15 (the task) |
| 5 | The task's hold was lifted and the task was started on 2026-11-19, after #255 to #261 merged. The design is under review in PR #796; it is approved by the merge | Alex, 2026-11-19 (task comment) |
| 6 | `runner-relay/` is a top-level module, not part of `runner/`; the protocol package is public in `runner/protocol/tunnel` | §2.1; `runner/` is extracted (`DESIGN.md` §14.1) and must not carry platform code |
| 7 | A runner connects while it holds a session in v1; the protocol allows a permanent connection | §3.2; the takeover's ops do not need the tunnel (§10.2) |
| 8 | The tunnel is authenticated by a gateway-minted ticket | §3.1; keeps the check order and `Rack::Attack` where they are |
| 9 | Streams are raw TCP; the relay speaks HTTP and WebSocket | §4; the runner stays small and needs no change for a new surface |
| 10 | The platform assigns the per-session ports, the runner verifies them | §3.3, following 8b's `proxy_port`; refines `DESIGN.md` §6.9.5 |
| 11 | A viewer's authorization is checked when a browser connection opens (`terminal-auth`), not again while it stays open; an open terminal outlives a removed access, as on hosted. Machine- and session-level revocation is kept | Alex, 2026-11-19 (review of PR #796, Q3); §6 |
| 12 | The reconcile pass is the guarantee; pub/sub is the fast path | §8.1 |
| 13 | The takeover keeps the token check and the throttles in Rails by forwarding short requests | §10.2 |
| 14 | `runner-relay.md` specifies the wire; `PROTOCOL.md` is written task by task as each piece is built | `PROTOCOL.md`'s own rule (it describes only what the gateway implements); this design PR changes no file but the design documents |
| 15 | The live view needs no new transport | §9; `websocket_url` already exists for every session with a route token |
| 16 | The service is named `runner-relay` everywhere; it lives in a separate Go module outside `runner/`, and the protocol package `runner/protocol/tunnel` is shared with `aixle-runner` (option A) | Alex, 2026-11-19 (review of PR #796, Q2; §2.1) |
| 17 | The runner authenticates to the relay with a gateway-minted ticket (option A) | Alex, 2026-11-19 (Q1; §3.1) |
| 18 | The ops takeover forwards short `wait=0` reads to Rails; the count is two requests per idle cycle with the subscription kept between polls (three after a gap). Commands over the persistent WebSocket are an option decided when row 24 is cut, variant (a) preferred | Alex, 2026-11-19 (Q4; §10.2, §10.2.1) |
| 19 | The cut of §13 is accepted for now and is adjusted as the tasks are cut | Alex, 2026-11-19 (Q5; §13) |
| 20 | The `/t/` route has an explicit low priority (2, above the catch-all's 1) and the one host the hosted routes use (`route_domain_host`); the tunnel route has an explicit priority above 100 | Alex, 2026-11-19 (Q6; §2.3) |
| 21 | Both routes use `TRAEFIK_ENTRYPOINT` (`websecure` by default, `intwebsecure` on staging), never a hard-coded `websecure` | Alex, 2026-11-19 (Q7; §2.3) |
| 22 | The NetworkPolicy adds Traefik's namespace; the platform's own pods in the namespace reach the relay too, which is accepted | Alex, 2026-11-19 (Q8; §2.3) |
| 23 | No per-IP limit on tunnel connections: a bad ticket costs one signature check, and minting tickets is throttled by `Rack::Attack` | Alex, 2026-11-19 (Q9; §5.3) |
| 24 | The `aixle-infra` facts (priorities, single host, `TRAEFIK_ENTRYPOINT`, same-namespace policy) are taken as stated in the review comments; §2.3 is fixed now | Alex, 2026-11-19 (round instructions) |
| 25 | `PROTOCOL.md` stays unedited by this design (accepted); each building task writes its section | Alex, 2026-11-19 (round instructions); §1 |

## 16. Deferred, and what to check

- **More than one replica** (§11, row 27).
- **Sentry in the relay**, a per-viewer stream cap, per-viewer re-authorization of open terminals (a separate task for hosted and runners together), WebSocket compression on the stream: not needed for phase 4.
- **`kubernetes` and `coder` specifics** beyond the `Dialer` seam (§3.3): rows 17 and 19.
- **Commands over the persistent WebSocket** (§10.2.1): decided when row 24 is cut; (a) is preferred.
- **Whether the ops long-poll's two short requests per cycle are acceptable** at the fleet size customers reach.
  If not, the cached-check variant of §10.2 is the next option, and it needs the `Rack::Attack` windows in Go.
- **Readiness of the ports before `ready`** (§9): measured in 16e.
