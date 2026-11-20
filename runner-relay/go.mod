module github.com/aixlehq/aixle-runner-relay

// The Go version is pinned: CI (`.github/workflows/ci.yml`, the runner-relay job)
// installs exactly this one from this file. It is the runner module's, which this
// module builds against.
go 1.27.4

require (
	github.com/aixlehq/aixle-runner v0.0.0
	github.com/alicebob/miniredis/v2 v2.40.0
	github.com/coder/websocket v1.8.15
	github.com/prometheus/client_golang v1.25.0
	github.com/redis/go-redis/v9 v9.23.0
)

require (
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/prometheus/client_model v0.6.3 // indirect
	github.com/prometheus/common v0.72.0 // indirect
	github.com/prometheus/procfs v0.22.0 // indirect
	github.com/yuin/gopher-lua v1.1.1 // indirect
	go.uber.org/atomic v1.12.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	google.golang.org/protobuf v1.36.12 // indirect
)

// runner/protocol/tunnel is the one package of the runner module the relay uses
// (docs/design/agent-runtimes/runner-relay.md §2.1). Once runner/ is extracted
// (DESIGN.md §14.1) this becomes a version of the extracted module.
replace github.com/aixlehq/aixle-runner => ../runner
