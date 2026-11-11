# syntax=docker/dockerfile:1
#
# The dev `local` adapter's host runner (docs/design/agent-runtimes/DESIGN.md
# §12.2): aixle-runner built from this checkout's runner/, run as the
# `runner-local` Compose service. Development only: it is never published and
# never offered as a runner type. Built with the context ./runner.

# The Go version of runner/go.mod, which CI installs.
ARG GO_VERSION=1.27.4

FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/aixle-runner ./cmd/aixle-runner

FROM alpine:3.22
COPY --from=build /out/aixle-runner /usr/local/bin/aixle-runner
# The proxy sidecar bind-mounts the runner's own binary and its relay socket,
# from the state directory, and the Docker daemon resolves those paths on this
# machine, not in this container (PROTOCOL.md §5.8). So the binary runs from,
# and the state lives in, RUNNER_LOCAL_DIR: a directory of this machine mounted
# at the same path (docker-compose.yml).
COPY --chmod=755 <<'EOF' /usr/local/bin/runner-local-entrypoint
#!/bin/sh
set -eu
dir="${RUNNER_LOCAL_DIR:?RUNNER_LOCAL_DIR names the directory of this machine mounted at the same path}"
mkdir -p "$dir/bin" "$dir/state"
chmod 700 "$dir/state"
cp /usr/local/bin/aixle-runner "$dir/bin/aixle-runner.new"
mv "$dir/bin/aixle-runner.new" "$dir/bin/aixle-runner"
exec "$dir/bin/aixle-runner" "$@" --state-dir "$dir/state"
EOF
ENTRYPOINT ["runner-local-entrypoint"]
CMD ["--mode", "host"]
