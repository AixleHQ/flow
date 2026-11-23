# syntax=docker/dockerfile:1
#
# The runner-relay service (docs/design/agent-runtimes/runner-relay.md §2.1).
#
# The build context is the REPOSITORY ROOT, not this directory: the module requires
# the runner module's runner/protocol/tunnel package through `replace => ../runner`
# (runner-relay/go.mod), so the build needs that package beside it:
#
#   docker build -f runner-relay/Dockerfile .
#
# Once runner/ is extracted into its own repository (DESIGN.md §14.1) the replace
# becomes a version, and the COPY of runner/ below goes.

FROM golang:1.27-alpine AS build

WORKDIR /src
RUN go env -w GOPROXY=https://proxy.golang.org,direct
# go.sum is committed: the build downloads exactly what it lists and verifies each
# module against it, instead of resolving whatever `go mod tidy` found that day.
COPY runner/go.mod runner/go.sum runner/
COPY runner-relay/go.mod runner-relay/go.sum runner-relay/
WORKDIR /src/runner-relay
RUN go mod download
WORKDIR /src
# The one package of the runner module that the relay imports.
COPY runner/protocol/tunnel runner/protocol/tunnel
COPY runner-relay runner-relay
WORKDIR /src/runner-relay
RUN CGO_ENABLED=0 go build -mod=readonly -trimpath -ldflags "-s -w" -o /bin/aixle-runner-relay ./cmd/aixle-runner-relay

FROM alpine:3.24
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=build /bin/aixle-runner-relay /app/aixle-runner-relay
# The runners' tunnel (routed by the ingress), and the admin port: /healthz, /readyz,
# and /metrics, which the ingress never routes.
EXPOSE 8080 9090
ENTRYPOINT ["/app/aixle-runner-relay"]
