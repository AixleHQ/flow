// Package version holds the runner's own version, sent in X-Aixle-Runner-Version
// (runner/protocol/PROTOCOL.md §1).
package version

// Version is set at build time:
//
//	go build -ldflags "-X github.com/aixlehq/aixle-runner/internal/version.Version=1.4.0" ./cmd/aixle-runner
//
// A local build reports 0.0.0-dev, a valid semantic version, so the gateway accepts it.
var Version = "0.0.0-dev"
