FROM golang:1.22-alpine AS build

WORKDIR /src
RUN go env -w GOPROXY=https://proxy.golang.org,direct
COPY . ./
RUN go mod tidy
RUN go build -o /bin/otlp-ingest ./

FROM alpine:3.21
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=build /bin/otlp-ingest /app/otlp-ingest
EXPOSE 4318
ENTRYPOINT ["/app/otlp-ingest"]
