package docker

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/docker/cli/cli/config"
	"github.com/docker/cli/cli/config/configfile"
)

const (
	image  = "ghcr.io/aixlehq/flow-agent-claude-code"
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	// pinned is the image by digest, the reference most tests start their
	// container from; tagged is the same image by tag.
	pinned = image + "@" + digest
	tagged = image + ":1.4"
)

func payload(t *testing.T, v any) json.RawMessage {
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func steppingClock() func() time.Time {
	t := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	return func() time.Time { t = t.Add(1500 * time.Millisecond); return t }
}

// withDockerConfig makes raw, a config.json, the Docker configuration every pull
// of the test reads its credentials from.
func withDockerConfig(t *testing.T, raw string) {
	t.Helper()
	loaded, err := config.LoadFromReader(strings.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	previous := dockerConfig
	dockerConfig = func() *configfile.ConfigFile { return loaded }
	t.Cleanup(func() { dockerConfig = previous })
}
