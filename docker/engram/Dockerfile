FROM golang:1.25.10-alpine AS build

ENV CGO_ENABLED=0 GOTOOLCHAIN=local GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
RUN go install -trimpath -ldflags="-s -w -X main.version=3.4.0" github.com/Gentleman-Programming/engram/v3/cmd/engram@v3.4.0

FROM alpine:3.23
RUN apk add --no-cache ca-certificates socat tini \
    && addgroup -S engram && adduser -S -G engram engram \
    && mkdir -p /data && chown engram:engram /data
COPY --from=build /go/bin/engram /usr/local/bin/engram
COPY --chmod=755 start-engram.sh /usr/local/bin/start-engram
USER engram
ENV ENGRAM_DATA_DIR=/data ENGRAM_CLOUD_AUTOSYNC=0 ENGRAM_CLOUD_SYNC=false
# Upstream v3.4.0 binds TCP to loopback; proxy its private Unix socket on the container network.
ENTRYPOINT ["/sbin/tini", "-g", "--"]
CMD ["/usr/local/bin/start-engram"]
