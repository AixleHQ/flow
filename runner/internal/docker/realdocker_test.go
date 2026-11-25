package docker

import (
	"bufio"
	"bytes"
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

	"github.com/moby/moby/api/pkg/stdcopy"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"
	"github.com/moby/moby/client/pkg/versions"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/statedir"
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
	realDockerSession(t, "bridge", map[string]int{"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041, "ide": 8443}, nil)
}

// TestRealDockerHostNetworkSessionServesItsFivePortsOnTheMachine is the same with
// `network: host`: the five ports are the machine's own, the image reads them from its
// variables, and the runner dials 127.0.0.1.
func TestRealDockerHostNetworkSessionServesItsFivePortsOnTheMachine(t *testing.T) {
	realDockerSession(t, "host", map[string]int{"tty": 31200, "view": 31201, "fs": 31202, "upload": 31203, "ide": 31204},
		map[string]string{"TTYD_PORT": "31200", "VIEW_PORT": "31201", "WATCHER_PORT": "31202", "UPLOAD_PORT": "31203", "VSCODE_PORT": "31204"})
}

func realDockerSession(t *testing.T, network string, ports map[string]int, extraEnv map[string]string) {
	t.Helper()
	image := os.Getenv(RealDockerImageEnv)
	if image == "" {
		t.Skip(RealDockerImageEnv + " is not set")
	}
	api, err := Connect()
	if err != nil {
		t.Fatal(err)
	}
	defer api.Close()

	// A short path: a Unix socket's path is limited to about 100 bytes, which t.TempDir's
	// name of the test overruns.
	state, err := os.MkdirTemp("", "rd")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(state) })
	// The sidecar mounts the binary's directory, `<state-dir>/bin` as the runner makes it.
	binary := statedir.BinPath(state)
	if err := os.MkdirAll(filepath.Dir(binary), 0o755); err != nil {
		t.Fatal(err)
	}
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
	containerEnv := map[string]string{"ROUTE_TOKEN": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "TTYD_CMD": "bash"}
	for k, v := range extraEnv {
		containerEnv[k] = v
	}
	payload, _ := json.Marshal(map[string]any{
		"image": image, "network": network, "proxy_port": 7690, "tunnel": map[string]any{"ports": ports}, "env": containerEnv,
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
	// With the bridge network, a port the sidecar was not given is refused by the sidecar
	// itself, whatever the runner's own table says.
	if dialer, ok := serving.Authorize(session, ports["tty"]); ok && network == "bridge" {
		if _, err := dialer.Dial(ctx, 22); err == nil {
			t.Fatal("the sidecar dialed a port outside its list")
		}
	}
}

// --- The mounts spike of add-machine.md §3.2 -----------------------------------

// These tests answer the question the Docker half of the design rests on, on a real
// daemon: a container the runner creates through the API can mount
//   - a `Subpath` of a directory of an anonymous volume,
//   - a `Subpath` of a directory of a named volume (Docker Engine 26.0, API 1.45),
//   - a subdirectory of a bind source,
//
// that another container (the runner's own) mounts whole. Run them on Docker 26 or
// later, and on Docker Desktop or OrbStack if one is at hand:
//
//	AIXLE_RUNNER_REAL_DOCKER_IMAGE=alpine:3.22 go test ./internal/docker -run RealDockerMounts -v
//
// The image needs `sh` and `cat`.

// realDockerHolder starts the container that stands for the runner's own: it mounts
// the state directory whole at /state, writes a file in `bin` and one in a
// directory a session would use, and keeps running, as the runner does while its
// sidecars are created.
func realDockerHolder(t *testing.T, ctx context.Context, api *client.Client, image, name string, mounts []mount.Mount) container.InspectResponse {
	t.Helper()
	created, err := api.ContainerCreate(ctx, client.ContainerCreateOptions{Name: name, Config: &container.Config{
		Image: image, Entrypoint: []string{"sh", "-c"},
		Cmd: []string{"mkdir -p /state/bin /state/proxy/7 && echo from-bin > /state/bin/marker && echo from-proxy > /state/proxy/7/marker && echo outside > /state/credentials && touch /state/ready && sleep 600"},
	}, HostConfig: &container.HostConfig{Mounts: mounts, NetworkMode: "none"}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = api.ContainerRemove(context.Background(), created.ID, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
	})
	if _, err := api.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		t.Fatal(err)
	}
	for deadline := time.Now().Add(20 * time.Second); ; time.Sleep(200 * time.Millisecond) {
		out, code := realDockerRun(t, ctx, api, image, nil, "test -f /state/ready", mount.Mount{}, created.ID)
		_ = out
		if code == 0 || time.Now().After(deadline) {
			break
		}
	}
	inspected, err := api.ContainerInspect(ctx, created.ID, client.ContainerInspectOptions{})
	if err != nil {
		t.Fatal(err)
	}
	return inspected.Container
}

// realDockerRun runs `sh -c script` in a container with the given mount, and returns its output and exit code.
// With `via` set it execs in that container instead.
func realDockerRun(t *testing.T, ctx context.Context, api *client.Client, image string, _ []string, script string, m mount.Mount, via ...string) (string, int) {
	t.Helper()
	if len(via) > 0 {
		exec, err := api.ExecCreate(ctx, via[0], client.ExecCreateOptions{Cmd: []string{"sh", "-c", script}, AttachStdout: true, AttachStderr: true})
		if err != nil {
			t.Fatal(err)
		}
		attached, err := api.ExecAttach(ctx, exec.ID, client.ExecAttachOptions{})
		if err != nil {
			t.Fatal(err)
		}
		var out bytes.Buffer
		_, _ = stdcopy.StdCopy(&out, &out, attached.Reader)
		attached.Close()
		inspected, err := api.ExecInspect(ctx, exec.ID, client.ExecInspectOptions{})
		if err != nil {
			t.Fatal(err)
		}
		return out.String(), inspected.ExitCode
	}
	created, err := api.ContainerCreate(ctx, client.ContainerCreateOptions{Config: &container.Config{
		Image: image, Entrypoint: []string{"sh", "-c"}, Cmd: []string{script}, User: SidecarUser,
	}, HostConfig: &container.HostConfig{Mounts: []mount.Mount{m}, NetworkMode: "none"}})
	if err != nil {
		t.Fatal(err)
	}
	defer api.ContainerRemove(context.Background(), created.ID, client.ContainerRemoveOptions{Force: true})
	if _, err := api.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		t.Fatalf("starting a container with the mount %+v: %v", m, err)
	}
	wait := api.ContainerWait(ctx, created.ID, client.ContainerWaitOptions{Condition: container.WaitConditionNotRunning})
	var code int
	select {
	case r := <-wait.Result:
		code = int(r.StatusCode)
	case err := <-wait.Error:
		t.Fatal(err)
	}
	logs, err := api.ContainerLogs(ctx, created.ID, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true})
	if err != nil {
		t.Fatal(err)
	}
	defer logs.Close()
	var out bytes.Buffer
	_, _ = stdcopy.StdCopy(&out, &out, logs)
	return out.String(), code
}

func TestRealDockerMountsASubpathOfAnAnonymousAndOfANamedVolumeAndASubdirectoryOfABind(t *testing.T) {
	image := os.Getenv(RealDockerImageEnv)
	if image == "" {
		t.Skip(RealDockerImageEnv + " is not set")
	}
	api, err := Connect()
	if err != nil {
		t.Fatal(err)
	}
	defer api.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	version, err := api.ServerVersion(ctx, client.ServerVersionOptions{})
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("Docker Engine %s, API %s", version.Version, version.APIVersion)
	if err := pull(ctx, api, image); err != nil {
		t.Fatal(err)
	}
	subpathOK := !versions.LessThan(version.APIVersion, "1.45")

	// What the sidecar sees: a subdirectory, and nothing outside it.
	check := func(t *testing.T, m mount.Mount, wantFile, wantContent string) {
		t.Helper()
		out, code := realDockerRun(t, ctx, api, image, nil, "cat "+wantFile+" && ! test -e /m/credentials && ! test -e /m/proxy && ! test -e /m/bin", m)
		if code != 0 || strings.TrimSpace(out) != wantContent {
			t.Fatalf("mount %+v: exit %d, %q (want %q)", m, code, out, wantContent)
		}
	}

	t.Run("an anonymous volume", func(t *testing.T) {
		if !subpathOK {
			t.Skipf("API %s is before 1.45: a volume subpath needs Docker Engine 26.0", version.APIVersion)
		}
		// Docker makes the anonymous volume: the mount has no source.
		holder := realDockerHolder(t, ctx, api, image, "", []mount.Mount{{Type: mount.TypeVolume, Target: "/state"}})
		name := holder.Mounts[0].Name
		if holder.Mounts[0].Type != mount.TypeVolume || name == "" {
			t.Fatalf("the holder's mount: %+v", holder.Mounts)
		}
		for sub, want := range map[string]string{"bin": "from-bin", "proxy/7": "from-proxy"} {
			check(t, mount.Mount{Type: mount.TypeVolume, Source: name, Target: "/m", ReadOnly: true, VolumeOptions: &mount.VolumeOptions{Subpath: sub}}, "/m/marker", want)
		}
	})

	t.Run("a named volume", func(t *testing.T) {
		if !subpathOK {
			t.Skipf("API %s is before 1.45: a volume subpath needs Docker Engine 26.0", version.APIVersion)
		}
		name := fmt.Sprintf("aixle-runner-spike-%d", time.Now().UnixNano())
		if _, err := api.VolumeCreate(ctx, client.VolumeCreateOptions{Name: name}); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _, _ = api.VolumeRemove(context.Background(), name, client.VolumeRemoveOptions{Force: true}) })
		realDockerHolder(t, ctx, api, image, "", []mount.Mount{{Type: mount.TypeVolume, Source: name, Target: "/state"}})
		for sub, want := range map[string]string{"bin": "from-bin", "proxy/7": "from-proxy"} {
			check(t, mount.Mount{Type: mount.TypeVolume, Source: name, Target: "/m", ReadOnly: true, VolumeOptions: &mount.VolumeOptions{Subpath: sub}}, "/m/marker", want)
		}
	})

	t.Run("a bind source", func(t *testing.T) {
		// A directory the daemon sees: the test shares the machine with a local daemon.
		source, err := os.MkdirTemp("", "aixle-spike")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { os.RemoveAll(source) })
		holder := realDockerHolder(t, ctx, api, image, "", []mount.Mount{{Type: mount.TypeBind, Source: source, Target: "/state"}})
		// The runner learns the bind's Source from its own container, and the sidecar
		// binds the subdirectories under it; the path in the container need not match.
		var found string
		for _, m := range holder.Mounts {
			if m.Destination == "/state" && m.Type == mount.TypeBind {
				found = m.Source
			}
		}
		if found == "" {
			t.Fatalf("the holder's mounts: %+v", holder.Mounts)
		}
		for sub, want := range map[string]string{"bin": "from-bin", "proxy/7": "from-proxy"} {
			check(t, mount.Mount{Type: mount.TypeBind, Source: filepath.Join(found, sub), Target: "/m", ReadOnly: true}, "/m/marker", want)
		}
	})
}

// A sidecar of the real runner binary, created by startSidecar for each way the state
// directory can be held, runs with the mounts the design describes.
func TestRealDockerSidecarRunsWithTheMountsOfEveryKindOfState(t *testing.T) {
	image := os.Getenv(RealDockerImageEnv)
	if image == "" {
		t.Skip(RealDockerImageEnv + " is not set")
	}
	api, err := Connect()
	if err != nil {
		t.Fatal(err)
	}
	defer api.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	version, err := api.ServerVersion(ctx, client.ServerVersionOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if err := pull(ctx, api, image); err != nil {
		t.Fatal(err)
	}
	// The binary the holder puts in the state directory.
	built := filepath.Join(t.TempDir(), "aixle-runner")
	build := exec.Command("go", "build", "-o", built, "../../cmd/aixle-runner")
	build.Env = append(os.Environ(), "CGO_ENABLED=0")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("building the runner: %v\n%s", err, out)
	}

	holderScript := "mkdir -p /state/bin /state/proxy/7 && cp /src/aixle-runner /state/bin/aixle-runner && chmod 755 /state/bin /state/bin/aixle-runner && chmod 755 /state/proxy /state/proxy/7 && touch /state/ready && sleep 600"
	hold := func(t *testing.T, m mount.Mount) container.InspectResponse {
		created, err := api.ContainerCreate(ctx, client.ContainerCreateOptions{Config: &container.Config{Image: image, Entrypoint: []string{"sh", "-c"}, Cmd: []string{holderScript}},
			HostConfig: &container.HostConfig{NetworkMode: "none", Mounts: []mount.Mount{m, {Type: mount.TypeBind, Source: filepath.Dir(built), Target: "/src", ReadOnly: true}}}})
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			_, _ = api.ContainerRemove(context.Background(), created.ID, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
		})
		if _, err := api.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
			t.Fatal(err)
		}
		for deadline := time.Now().Add(20 * time.Second); time.Now().Before(deadline); time.Sleep(200 * time.Millisecond) {
			if _, code := realDockerRun(t, ctx, api, image, nil, "test -f /state/ready", mount.Mount{}, created.ID); code == 0 {
				break
			}
		}
		inspected, err := api.ContainerInspect(ctx, created.ID, client.ContainerInspectOptions{})
		if err != nil {
			t.Fatal(err)
		}
		return inspected.Container
	}

	source, err := os.MkdirTemp("", "aixle-spike")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(source) })
	named := fmt.Sprintf("aixle-runner-spike-%d", time.Now().UnixNano())
	if _, err := api.VolumeCreate(ctx, client.VolumeCreateOptions{Name: named}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = api.VolumeRemove(context.Background(), named, client.VolumeRemoveOptions{Force: true}) })

	kinds := []struct {
		name   string
		mount  mount.Mount
		volume bool
	}{
		{"anonymous volume", mount.Mount{Type: mount.TypeVolume, Target: "/state"}, true},
		{"named volume", mount.Mount{Type: mount.TypeVolume, Source: named, Target: "/state"}, true},
		{"directory", mount.Mount{Type: mount.TypeBind, Source: source, Target: "/state"}, false},
	}
	for _, kind := range kinds {
		t.Run(kind.name, func(t *testing.T) {
			if kind.volume && versions.LessThan(version.APIVersion, "1.45") {
				t.Skipf("API %s is before 1.45", version.APIVersion)
			}
			holder := hold(t, kind.mount)
			// What the runner does at start: it finds its own container by hostname and reads where /state lives.
			located, err := LocateState(ctx, api, "/state", holder.Config.Hostname)
			if err != nil {
				t.Fatal(err)
			}
			t.Logf("located: %+v", located)
			const session = int64(7)
			logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
			bg, stop := context.WithCancel(ctx)
			defer stop()
			env := &Environment{API: api, Key: "spike", StateDir: "/state", State: located, Logger: logger, Background: bg,
				Proxy: &stateProxy{dir: "/state/proxy", binary: statedir.BinPath("/state")}}
			id, r := env.startSidecar(ctx, session, image, "none", 7690, nil)
			if r != nil {
				t.Fatalf("startSidecar: %v", r.Error)
			}
			t.Cleanup(func() {
				env.retire(id)
				_, _ = api.ContainerRemove(context.Background(), id, client.ContainerRemoveOptions{Force: true})
			})
			time.Sleep(3 * time.Second)
			inspected, err := api.ContainerInspect(ctx, id, client.ContainerInspectOptions{})
			if err != nil {
				t.Fatal(err)
			}
			state := inspected.Container.State
			logs := env.logTail(ctx, id)
			if state == nil || !state.Running {
				t.Fatalf("the sidecar is not running: %+v\n%s", state, logs)
			}
			t.Logf("sidecar running with %d mounts\n%s", len(inspected.Container.Mounts), logs)
			for _, m := range inspected.Container.Mounts {
				if strings.Contains(m.Source, "/volumes/") && m.Type == mount.TypeBind {
					t.Errorf("a bind from under Docker's data root: %+v", m)
				}
			}
		})
	}
}

// stateProxy is the relay as startSidecar sees it, for directories a holder container made.
type stateProxy struct{ dir, binary string }

func (p *stateProxy) OpenSocket(session int64) (string, error) {
	return fmt.Sprintf("%s/%d", p.dir, session), nil
}
func (p *stateProxy) OpenListener(int64, int) error { return nil }
func (p *stateProxy) DialDir(session int64) (string, error) {
	return fmt.Sprintf("/state/dial/%d", session), nil
}
func (p *stateProxy) Close(int64)    {}
func (p *stateProxy) CloseAll()      {}
func (p *stateProxy) Binary() string { return p.binary }
