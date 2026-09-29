FROM golang:1.27-alpine AS build

WORKDIR /src
RUN go env -w GOPROXY=https://proxy.golang.org,direct
# go.sum is committed: the build downloads exactly what it lists and verifies each
# module against it, instead of resolving whatever `go mod tidy` found that day.
COPY go.mod go.sum ./
RUN go mod download
COPY . ./
RUN go build -mod=readonly -o /bin/otlp-ingest ./

FROM alpine:3.24
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=build /bin/otlp-ingest /app/otlp-ingest
EXPOSE 4318
ENTRYPOINT ["/app/otlp-ingest"]
