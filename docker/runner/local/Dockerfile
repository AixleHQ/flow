# syntax=docker/dockerfile:1
#
# The dev `local` adapter's host runner (docs/design/agent-runtimes/DESIGN.md
# §12.2): aixle-runner built from this checkout's runner/, run as the
# `runner-local` Compose service. Development only: it is never published and
# never offered as a runner type. Built with the context ./runner.

# The Go version of runner/go.mod, which CI installs.
ARG GO_VERSION=1.27.3

FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/aixle-runner ./cmd/aixle-runner

FROM alpine:3.22
COPY --from=build /out/aixle-runner /usr/local/bin/aixle-runner
ENTRYPOINT ["aixle-runner"]
CMD ["--mode", "host"]
