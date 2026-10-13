#!/bin/sh
set -u

stop_children() {
  trap '' TERM INT
  kill "$server_pid" "$proxy_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  wait "$proxy_pid" 2>/dev/null || true
}

engram serve --socket /data/engram.sock &
server_pid=$!
socat TCP-LISTEN:7437,reuseaddr,fork UNIX-CONNECT:/data/engram.sock &
proxy_pid=$!

trap 'stop_children; exit 143' TERM
trap 'stop_children; exit 130' INT

while kill -0 "$server_pid" 2>/dev/null && kill -0 "$proxy_pid" 2>/dev/null; do
  sleep 1
done
if kill -0 "$server_pid" 2>/dev/null; then
  wait "$proxy_pid"
else
  wait "$server_pid"
fi
status=$?
stop_children
# Both children are long-lived services; even a clean early exit requires a restart.
[ "$status" -ne 0 ] || status=1
exit "$status"
