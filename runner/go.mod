module github.com/aixlehq/aixle-runner

// The Go version is pinned: CI (`.github/workflows/ci.yml`, the Runner job) installs
// exactly this one from this file.
go 1.27.4

require (
	github.com/containerd/errdefs v1.0.0
	github.com/distribution/reference v0.6.0
	github.com/docker/cli v29.9.3+incompatible
	github.com/moby/moby/api v1.56.1
	github.com/moby/moby/client v0.6.2
	github.com/opencontainers/image-spec v1.1.1
)

require (
	github.com/Microsoft/go-winio v0.6.2 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/containerd/errdefs/pkg v0.3.0 // indirect
	github.com/docker/docker-credential-helpers v0.9.12 // indirect
	github.com/docker/go-connections v0.8.2 // indirect
	github.com/docker/go-units v0.5.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/go-logr/logr v1.4.4 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/moby/docker-image-spec v1.3.1 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/sirupsen/logrus v1.9.3 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.60.0 // indirect
	go.opentelemetry.io/otel v1.47.0 // indirect
	go.opentelemetry.io/otel/log v1.47.0 // indirect
	go.opentelemetry.io/otel/metric v1.47.0 // indirect
	go.opentelemetry.io/otel/trace v1.47.0 // indirect
	golang.org/x/sys v0.33.0 // indirect
)
