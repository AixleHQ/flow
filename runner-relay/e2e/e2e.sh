#!/bin/bash
# The browser path end to end, on one machine with Docker (a Coder workspace here):
#   Chromium (Playwright) → the repository's own docker/traefik/dynamic.yml (terminal-auth in front,
#   the `/t/` route to the relay) → the real aixle-runner-relay → a real WebSocket tunnel ←
#   the real runner code (tunnel manager, container.start, proxy sidecar, dial.sock) → the real
#   agent image on the local Docker daemon. The Rails app is replaced by stub.py (ws_auth, holders,
#   checks); the signals are published to a real Redis in the format Runners::RelaySignals sends.
#
#   runner-relay/e2e/e2e.sh   (as root, from a checkout of the branch under test; see README.md)
set -u
REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
E=$REPO/runner-relay/e2e
D=/tmp/e2e; CTL=$D/ctl; LOG=$D/logs
IMG=${IMG:-ghcr.io/aixlehq/flow-kiro-cli:latest}
CHANNEL=aixle_e2e_runner_relay
mkdir -p "$CTL" "$LOG" "$D/shots"; rm -f "$CTL"/* "$LOG"/*; rm -rf "$D"/rd*
export PATH=$PATH
FAILS=0
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
step() { echo; echo "== $1"; }
publish() { docker exec e2e-redis redis-cli -p 16379 publish "$CHANNEL" "$1" >/dev/null; }
now_ms() { date +%s%3N; }

cleanup() {
  touch "$CTL/exit"; sleep 3
  docker rm -f e2e-redis e2e-traefik e2e-driver >/dev/null 2>&1
  pkill -f e2e-relay; pkill -f stub.py
}
trap cleanup EXIT
docker rm -f e2e-redis e2e-traefik e2e-driver >/dev/null 2>&1; pkill -f e2e-relay; pkill -f stub.py; sleep 1

step "build the relay"
docker run --rm -v $REPO:/src -v gomod:/go/pkg/mod -v $D:/out -w /src/runner-relay -e CGO_ENABLED=0 golang:1.27 \
  go build -o /out/e2e-relay ./cmd/aixle-runner-relay || exit 1

step "start redis, the stub platform, the relay, traefik"
docker run -d --name e2e-redis --network host redis:7.2-alpine redis-server --port 16379 >/dev/null
python3 $E/stub.py > $LOG/stub.log 2>&1 &
start_relay() {
  RUNNER_RELAY_LISTEN=0.0.0.0:4004 RUNNER_RELAY_ADMIN_LISTEN=127.0.0.1:4005 \
  RUNNER_RELAY_REDIS_URL=redis://127.0.0.1:16379/1 RUNNER_RELAY_REDIS_CHANNEL_PREFIX=aixle_e2e_ \
  RUNNER_RELAY_RAILS_URL=http://127.0.0.1:4000 RUNNER_RELAY_INTERNAL_TOKEN=e2e-internal-token \
  RUNNER_RELAY_TICKET_KEY=e2e-ticket-key-0123456789abcdef RUNNER_RELAY_CHECK_INTERVAL=5s \
  nohup $D/e2e-relay >> $LOG/relay.log 2>&1 &
  echo $! > $D/relay.pid
}
start_relay
docker run -d --name e2e-traefik --network host --add-host web:127.0.0.1 -e PORT=4000 -e RUNNER_RELAY_PORT=4004 \
  -v $REPO/docker/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro traefik:v3.6.6 \
  --providers.file.filename=/etc/traefik/dynamic.yml --entrypoints.web.address=:8088 --log.level=INFO >/dev/null
for i in $(seq 1 30); do curl -sf http://127.0.0.1:4005/readyz >/dev/null && break; sleep 1; done
curl -s http://127.0.0.1:4005/readyz | grep -q ready && ok "the relay is ready (subscription live, first pass done)" || bad "the relay is not ready"

step "start the runner side: a real container.start on the local daemon, and the tunnel"
docker run -d --name e2e-driver --network host -v /var/run/docker.sock:/var/run/docker.sock -v /tmp:/tmp \
  -v $REPO:/src -v $E/runner_driver.go.txt:/src/runner/internal/tunnel/e2e_driver_test.go -v gomod:/go/pkg/mod \
  -e TMPDIR=$D -e E2E_IMAGE=$IMG -e E2E_CTL=$CTL -e E2E_RELAY_WS=ws://127.0.0.1:4004/runner/v1/tunnel \
  -e E2E_TICKET_KEY=e2e-ticket-key-0123456789abcdef -w /src/runner golang:1.27 \
  go test ./internal/tunnel -run E2EDriver -v -count=1 -timeout 60m >/dev/null
for i in $(seq 1 180); do [ -f $CTL/ready ] && break; sleep 1; done
[ -f $CTL/ready ] && ok "container.start answered with the five ports answering" || { bad "the driver never became ready"; docker logs e2e-driver 2>&1 | tail -20; exit 1; }
connected() { grep -c "a machine connected" $LOG/relay.log; }
for i in $(seq 1 30); do [ "$(connected)" -ge 1 ] && break; sleep 1; done
[ "$(connected)" -ge 1 ] && ok "the machine's tunnel connected to the relay" || bad "the machine did not connect"

check() { docker run --rm --network host -v $E:/e2e -v $D/shots:/shots mcr.microsoft.com/playwright:v1.49.1-jammy \
  sh -c 'cd /tmp && npm i playwright@1.49.1 --silent >/dev/null 2>&1; NODE_PATH=/tmp/node_modules node /e2e/check.js "$@"' sh "$@"; }

step "1. the surfaces, as the owner and as a second viewer (Playwright)"
check main | tee $LOG/check-main.log; [ ${PIPESTATUS[0]} = 0 ] && ok "browser checks passed" || bad "browser checks failed"

step "2. kill the relay: the page gets a refusal; restart it: the terminal comes back, the session did not fail"
kill "$(cat $D/relay.pid)"; sleep 2
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Cookie: viewer=owner' http://127.0.0.1:8088/t/e2eroutetoken0123456789abcdef00/tty/)
echo "while the relay is down, the page answers $code"
before=$(connected); start_relay
for i in $(seq 1 60); do [ "$(connected)" -gt "$before" ] && break; sleep 1; done
[ "$(connected)" -gt "$before" ] && ok "the runner reconnected to the restarted relay" || bad "the runner did not reconnect"
docker inspect -f '{{.State.Running}}' aixle-e2e-555 2>/dev/null | grep -q true && ok "the session's container ran through it" || bad "the session's container stopped"
check again | tee $LOG/check-again.log; [ ${PIPESTATUS[0]} = 0 ] && ok "the terminal works again" || bad "the terminal does not work after the restart"

watch() { check watch 90000 > $1 2>&1 & echo $!; }
wait_closed() { # file, max ms
  local s=$(now_ms); while [ $(( $(now_ms) - s )) -lt $2 ]; do grep -q WATCH $1 2>/dev/null && { echo $(( $(now_ms) - s )); return 0; }; sleep 0.2; done; return 1; }

step "3. session_ended closes the open terminal"
touch $CTL/session_gone; w=$(watch $LOG/watch-ended.log); sleep 6
publish '{"type":"session_ended","session_id":555}'
t=$(wait_closed $LOG/watch-ended.log 8000) && ok "the terminal closed ${t} ms after the signal: $(grep WATCH $LOG/watch-ended.log)" || bad "the terminal stayed open after session_ended"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Cookie: viewer=owner' http://127.0.0.1:8088/t/e2eroutetoken0123456789abcdef00/tty/)
[ "$code" = 503 ] && ok "a new request for the ended session is 503 (Retry-After 2)" || bad "a new request answered $code"
rm -f $CTL/session_gone

step "4. a lost signal: the platform says the machine is no longer valid, and no signal comes"
w=$(watch $LOG/watch-lost.log); sleep 6; touch $CTL/invalid
t=$(wait_closed $LOG/watch-lost.log 15000) && ok "the reconcile pass closed it ${t} ms after the platform changed (interval 5 s)" || bad "the reconcile pass did not close it"
grep -q "reconcile pass found" $LOG/relay.log && ok "the relay logged the revocation" || bad "no revocation logged"
rm -f $CTL/invalid
before=$(connected); for i in $(seq 1 60); do [ "$(connected)" -gt "$before" ] && break; sleep 1; done

step "5. machine_revoked closes the machine's connection with 4001 and its terminals"
check again >/dev/null 2>&1   # warms the route again
b5=$(connected)
w=$(watch $LOG/watch-revoked.log); sleep 6
publish '{"type":"machine_revoked","environment_id":42}'
t=$(wait_closed $LOG/watch-revoked.log 8000) && ok "the terminal closed ${t} ms after the signal" || bad "the terminal stayed open after machine_revoked"
grep -q "was revoked; closing its connection" $LOG/relay.log && ok "the relay closed the machine's connection" || bad "no close logged"

step "6. container.stop resets the streams with session_changed before the container goes"
for i in $(seq 1 60); do [ "$(connected)" -gt "$b5" ] && break; sleep 1; done
sleep 2; check again >/dev/null 2>&1
w=$(watch $LOG/watch-stop.log); sleep 6; touch $CTL/stop-container
t=$(wait_closed $LOG/watch-stop.log 20000) && ok "the terminal closed ${t} ms after container.stop was run" || bad "the terminal stayed open through container.stop"

step "metrics"
curl -s http://127.0.0.1:4005/metrics | grep -E '^runner_relay_(machines_connected|streams_open|stream_resets_total|reconcile_revocations_total|reconcile_passes_total|signals_total|edge_requests_total|dial_seconds_count|signal_lag_seconds_count|rails_request_seconds_count)' | tee $LOG/metrics.txt

echo; echo "FAILED CHECKS: $FAILS"
exit $FAILS
