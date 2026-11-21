package docker

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
)

// RealDockerImageEnv names an agent image: with it set, the test below runs the tunnel's
// bridge path against the machine's own Docker daemon, with the real proxy sidecar. It is
// not part of CI (it pulls an image of several hundred megabytes and needs a daemon that
// sees this machine's files):
//
//	AIXLE_RUNNER_REAL_DOCKER_IMAGE=ghcr.io/aixlehq/flow-kiro-cli:latest go test ./internal/docker -run RealDocker -v
const RealDockerImageEnv = "AIXLE_RUNNER_REAL_DOCKER_IMAGE"

// TestRealDockerBridgeSessionServesItsFivePortsThroughTheSidecar starts a session as
// `container.start` does on a real daemon (a real sidecar running this repository's
// binary, the agent image, the dial socket mounted read-write), waits for the five
// ports, and speaks HTTP to each through the dialer the relay's streams use.
func TestRealDockerBridgeSessionServesItsFivePortsThroughTheSidecar(t *testing.T) {
	image := os.Getenv(RealDockerImageEnv)
	if image == "" {
		t.Skip(RealDockerImageEnv + " is not set")
	}
	api, err := Connect()
	if err != nil {
		t.Fatal(err)
	}
	defer api.Close()

	state := t.TempDir()
	if err := os.Chmod(state, 0o700); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(state, "aixle-runner")
	build := exec.Command("go", "build", "-o", binary, "../../cmd/aixle-runner")
	build.Env = append(os.Environ(), "CGO_ENABLED=0")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("building the runner: %v\n%s", err, out)
	}

	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serving := &tunnel.Serving{}
	env := &Environment{
		API: api, Key: "realdocker", StateDir: state, Logger: logger, Background: ctx, Tunnel: serving,
		Proxy:              proxy.NewHost(state, binary, http.NotFoundHandler(), logger),
		TunnelReadyTimeout: 90 * time.Second,
	}
	const session = int64(987654)
	ports := map[string]int{"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041, "ide": 8443}
	payload, _ := json.Marshal(map[string]any{
		"image": image, "proxy_port": 7690, "tunnel": map[string]any{"ports": ports},
		"env": map[string]string{"ROUTE_TOKEN": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "TTYD_CMD": "bash"},
	})
	t.Cleanup(func() {
		stop := context.Background()
		env.ContainerStop(stop, session, json.RawMessage(`{}`))
		env.Reset(stop, nil)
	})

	started := time.Now()
	result := env.ContainerStart(ctx, session, payload)
	if result.Status != protocol.StatusOK {
		t.Fatalf("container.start: %#v %v", result, result.Error)
	}
	t.Logf("container.start answered after %v, with the five ports answering", time.Since(started).Round(100*time.Millisecond))

	for surface, port := range ports {
		dialer, ok := serving.Authorize(session, port)
		if !ok {
			t.Fatalf("%s (%d) is not served", surface, port)
		}
		conn, err := dialer.Dial(ctx, port)
		if err != nil {
			t.Fatalf("%s: dialing %d: %v", surface, port, err)
		}
		conn.SetDeadline(time.Now().Add(10 * time.Second))
		path := "/"
		if surface == "ide" {
			path = "/t/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/ide/"
		}
		fmt.Fprintf(conn, "GET %s HTTP/1.0\r\nHost: localhost\r\n\r\n", path)
		status, err := bufio.NewReader(conn).ReadString('\n')
		conn.Close()
		if err != nil || !strings.HasPrefix(status, "HTTP/") {
			t.Fatalf("%s: %q, %v", surface, status, err)
		}
		t.Logf("%-6s :%d  %s", surface, port, strings.TrimSpace(status))
	}
	// A port the sidecar was not given is refused, whatever the runner's own table says.
	if dialer, ok := serving.Authorize(session, 7681); ok {
		if _, err := dialer.Dial(ctx, 22); err == nil {
			t.Fatal("the sidecar dialed a port outside its list")
		}
	}
}
