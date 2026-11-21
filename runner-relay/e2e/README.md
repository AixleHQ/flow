# The browser path, end to end, on one machine with Docker

`e2e.sh` runs the whole path of `docs/design/agent-runtimes/runner-relay.md` §4 with the real parts, and with a
stand-in only for the Rails app:

```text
Chromium (Playwright) ─▶ Traefik, with this repository's docker/traefik/dynamic.yml
                           │ terminal-auth ─▶ stub.py   (ws_auth)
                           └ /t/…           ─▶ the real aixle-runner-relay ◀── Redis pub/sub (the platform's signals)
                                                  │ short calls ─▶ stub.py (holders, checks)
                                                  ▲ one WebSocket (a ticket signed with the shared key)
the runner's own code: tunnel manager + container.start + proxy sidecar + dial.sock
                                                  ─▶ the real agent image on the local Docker daemon
```

- `runner_driver.go.txt` is mounted into the runner module as a test (`runner/internal/tunnel`) and run with
  `go test`. It makes a real `container.start` on the local daemon (the real sidecar, running this branch's binary) and runs the
  tunnel manager against the relay, minting tickets as the gateway does. Control files in `/tmp/e2e/ctl` stop the container.
- `stub.py` answers `ws_auth` (the `viewer` cookie says owner or guest), `holders` and `checks`. Control files make `checks`
  answer `false` (`invalid`) and `holders` say that no machine holds the session (`session_gone`).
- `check.js` is the browser's side, with Playwright: the terminal page and a keystroke round trip, a second viewer's
  read-only terminal and the refusals of the owner-only surfaces, the IDE, an upload, the same terminal after the relay
  was restarted, and how long an open terminal takes to close after a signal. Screenshots go to `/tmp/e2e/shots`.

Run it as root on a machine with Docker, from a checkout of the branch (`IMG` is the agent image, by default
`ghcr.io/aixlehq/flow-kiro-cli:latest`, which is public):

```sh
runner-relay/e2e/e2e.sh
```

It prints `PASS`/`FAIL` per check and the relay's metrics at the end, and keeps its logs in `/tmp/e2e/logs`. The Rails
contracts it stands in for (`ws_auth`, `holders`, `checks`, the signals' format) are tested on the Rails side
(`test/controllers/api/v1/internal/`, `test/services/runners/relay_signals_test.rb`).
