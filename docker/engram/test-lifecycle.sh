#!/bin/sh
set -eu

image=${1:-flow-engram:3.4.0}
container="flow-engram-lifecycle-$$"
cleanup() { docker rm -f "$container" >/dev/null 2>&1 || true; }
trap cleanup EXIT

wait_for_exit() {
  attempts=0
  while [ "$(docker inspect -f '{{.State.Running}}' "$container")" = true ]; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 50 ]; then
      echo "FAIL: container stayed running after a child failed" >&2
      docker logs "$container" >&2
      docker exec "$container" ps >&2
      return 1
    fi
    sleep 0.1
  done
  code=$(docker inspect -f '{{.State.ExitCode}}' "$container")
  [ "$code" -ne 0 ] || { echo "FAIL: child failure reported success" >&2; return 1; }
}

wait_for_health() {
  attempts=0
  until docker exec "$container" wget -q -O /dev/null http://127.0.0.1:7437/health; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 50 ] || return 1
    sleep 0.1
  done
}

docker run -d --name "$container" -e ENGRAM_DATA_DIR=/dev/null "$image" >/dev/null
wait_for_exit
cleanup
echo "PASS: startup failure terminates the container"

for process in engram socat; do
  docker run -d --name "$container" "$image" >/dev/null
  wait_for_health
  docker exec "$container" pkill -TERM -x "$process"
  wait_for_exit
  cleanup
  echo "PASS: $process failure terminates the container"
done

docker run -d --name "$container" "$image" >/dev/null
wait_for_health
docker stop -t 3 "$container" >/dev/null
code=$(docker inspect -f '{{.State.ExitCode}}' "$container")
[ "$code" -eq 143 ] || { echo "FAIL: shutdown exit code was $code" >&2; exit 1; }
echo "PASS: shutdown forwards TERM and exits without forced killing"
