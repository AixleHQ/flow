package docker

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// fakeProxy is the host runner's relay as the docker package sees it.
type fakeProxy struct {
	mu        sync.Mutex
	dir       string
	binary    string
	sockets   []int64
	listeners map[int64]int
	closed    []int64
	closedAll int
	// listenErr refuses every OpenListener.
	listenErr error
	// socketErr refuses every OpenSocket.
	socketErr error
}

func newFakeProxy(t *testing.T) *fakeProxy {
	t.Helper()
	binary := filepath.Join(t.TempDir(), "aixle-runner")
	if err := os.WriteFile(binary, []byte("#!/bin/true\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return &fakeProxy{dir: t.TempDir(), binary: binary, listeners: map[int64]int{}}
}

func (p *fakeProxy) OpenSocket(sessionID int64) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.sockets = append(p.sockets, sessionID)
	if p.socketErr != nil {
		return "", p.socketErr
	}
	dir := filepath.Join(p.dir, strconv.FormatInt(sessionID, 10))
	return dir, os.MkdirAll(dir, 0o755)
}

func (p *fakeProxy) OpenListener(sessionID int64, port int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.listenErr != nil {
		return p.listenErr
	}
	p.listeners[sessionID] = port
	return nil
}

func (p *fakeProxy) Close(sessionID int64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.closed = append(p.closed, sessionID)
}

func (p *fakeProxy) CloseAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.closedAll++
}

func (p *fakeProxy) Binary() string { return p.binary }

func (p *fakeProxy) closes() []int64 {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]int64(nil), p.closed...)
}

// lockedBuffer is a log the watcher's goroutine writes while the test reads.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// withProxy gives the harness's environment a fake relay, a log and a
// background context that ends with the test.
func (h *harness) withProxy() (*fakeProxy, *lockedBuffer) {
	h.t.Helper()
	p := newFakeProxy(h.t)
	log := &lockedBuffer{}
	ctx, cancel := context.WithCancel(context.Background())
	h.t.Cleanup(cancel)
	h.env.Proxy = p
	h.env.Logger = slog.New(slog.NewTextHandler(log, nil))
	h.env.Background = ctx
	return p, log
}

func (h *harness) byName(name string) *fakeContainer {
	h.t.Helper()
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	return h.engine.lookup(name)
}

func TestContainerStartPutsTheAgentInTheNetworkOfItsProxySidecar(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	r := h.start(h.env, nil)
	if r.Data["name"] != h.env.ContainerName(sessionID) {
		t.Fatalf("answered %v", r.Data)
	}

	if len(h.engine.creates) != 2 || h.engine.creates[0].Config.Labels[LabelRole] != RoleProxy {
		t.Fatalf("the sidecar must be created first, before the agent: %d creates", len(h.engine.creates))
	}
	sidecar := h.byName(h.env.SidecarName(sessionID))
	agent := h.byName(h.env.ContainerName(sessionID))
	if sidecar == nil || agent == nil || !sidecar.State.Running || !agent.State.Running {
		t.Fatalf("sidecar %v, agent %v", sidecar, agent)
	}

	wantEntrypoint := []string{SidecarBinary, "--mode", "proxy", "--socket", SidecarSocketDir + "/relay.sock", "--listen", "127.0.0.1:" + strconv.Itoa(testProxyPort)}
	if !reflect.DeepEqual([]string(sidecar.Config.Entrypoint), wantEntrypoint) || sidecar.Config.Image != pinned {
		t.Fatalf("sidecar runs %v from %s", sidecar.Config.Entrypoint, sidecar.Config.Image)
	}
	if sidecar.Config.User != SidecarUser || len(sidecar.Config.Env) != 0 {
		t.Fatalf("sidecar user %q, env %v: it holds nothing of the session", sidecar.Config.User, sidecar.Config.Env)
	}
	wantLabels := map[string]string{LabelEnvironment: envKey, LabelSession: "123", LabelRole: RoleProxy}
	if !reflect.DeepEqual(sidecar.Config.Labels, wantLabels) {
		t.Fatalf("sidecar labels %v", sidecar.Config.Labels)
	}
	wantMounts := []mount.Mount{
		{Type: mount.TypeBind, Source: p.binary, Target: SidecarBinary, ReadOnly: true},
		{Type: mount.TypeBind, Source: filepath.Join(p.dir, "123"), Target: SidecarSocketDir, ReadOnly: true},
	}
	if !reflect.DeepEqual(sidecar.Host.Mounts, wantMounts) {
		t.Fatalf("sidecar mounts %#v", sidecar.Host.Mounts)
	}
	if sidecar.Host.NetworkMode != "bridge" || !sidecar.Host.ReadonlyRootfs ||
		!reflect.DeepEqual(sidecar.Host.CapDrop, []string{"ALL"}) || !reflect.DeepEqual(sidecar.Host.SecurityOpt, []string{"no-new-privileges"}) {
		t.Fatalf("sidecar host config %#v", sidecar.Host)
	}

	if agent.Host.NetworkMode != container.NetworkMode("container:"+sidecar.ID) {
		t.Fatalf("the agent's network is %q, not the sidecar's", agent.Host.NetworkMode)
	}
	for _, m := range agent.Host.Mounts {
		if m.Source == p.binary || strings.HasPrefix(m.Source, p.dir) {
			t.Fatalf("the agent container mounts the runner's %s", m.Source)
		}
	}
	if !reflect.DeepEqual(p.sockets, []int64{sessionID}) {
		t.Fatalf("relay sockets %v", p.sockets)
	}

	// The session ops act on the agent, never on its sidecar.
	status := h.run(h.env.Status, map[string]any{})
	if status.Data["name"] != h.env.ContainerName(sessionID) {
		t.Fatalf("status reads %v", status.Data)
	}
}

func TestContainerStartWithHostNetworkListensOnTheMachineAndStartsNoSidecar(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	h.start(h.env, map[string]any{"network": "host", "proxy_port": 20123})

	agent := h.only()
	if agent.Host.NetworkMode != "host" || agent.Config.Labels[LabelProxyPort] != "20123" {
		t.Fatalf("network %q, labels %v", agent.Host.NetworkMode, agent.Config.Labels)
	}
	if p.listeners[sessionID] != 20123 || len(p.sockets) != 0 {
		t.Fatalf("listeners %v, sockets %v", p.listeners, p.sockets)
	}

	stopped := h.run(h.env.ContainerStop, map[string]any{})
	if stopped.Status != protocol.StatusOK || !reflect.DeepEqual(p.closes(), []int64{sessionID}) {
		t.Fatalf("stop %#v, relays closed %v", stopped, p.closes())
	}
}

func TestContainerStartNeedsTheProxyPort(t *testing.T) {
	for _, network := range []string{"bridge", "host"} {
		for _, port := range []any{nil, 0, 80, 70000, "20123"} {
			h := newEnvironment(t)
			h.withProxy()
			payload := startPayload(map[string]any{"network": network, "proxy_port": port})
			if port == nil {
				delete(payload, "proxy_port")
			}
			r := h.run(h.env.ContainerStart, payload)
			if r.Error == nil || r.Error.Class != ClassInvalidPayload || len(h.engine.containers) != 0 {
				t.Fatalf("network %s, proxy_port %v: %#v", network, port, r)
			}
		}
	}
}

func TestTheSidecarListensOnThePayloadsProxyPort(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	h.start(h.env, map[string]any{"proxy_port": 7800})

	sidecar := h.byName(h.env.SidecarName(sessionID))
	entrypoint := []string(sidecar.Config.Entrypoint)
	if got := entrypoint[len(entrypoint)-1]; got != "127.0.0.1:7800" {
		t.Fatalf("the sidecar listens on %s, not the payload's port: %v", got, entrypoint)
	}
}

func TestContainerStartRefusesAProxyPortInUse(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	p.listenErr = fmt.Errorf("listening on 127.0.0.1:20123: %w", syscall.EADDRINUSE)
	r := h.run(h.env.ContainerStart, startPayload(map[string]any{"network": "host", "proxy_port": 20123}))
	if r.Error == nil || r.Error.Class != ClassProxyPortInUse || !strings.Contains(r.Error.Message, "20123") {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.containers) != 0 {
		t.Fatalf("%d containers created", len(h.engine.containers))
	}
}

func TestContainerStartNamesTheCauseWhenTheDaemonDoesNotSeeTheRunnersFiles(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	h.engine.bindsNotVisible = true
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Error == nil || r.Error.Class != ClassDockerFilesNotVisible {
		t.Fatalf("%#v", r)
	}
	for _, want := range []string{"cannot see this machine's files", "DOCKER_HOST", p.binary, "bind source path does not exist"} {
		if !strings.Contains(r.Error.Message, want) {
			t.Errorf("the message lacks %q: %s", want, r.Error.Message)
		}
	}
	if len(h.engine.containers) != 0 || !reflect.DeepEqual(p.closes(), []int64{sessionID}) {
		t.Fatalf("left %d containers, relays closed %v", len(h.engine.containers), p.closes())
	}
}

func TestContainerStartRemovesTheSidecarWhenTheAgentDoesNotStart(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	h.engine.startErrorFor = map[string]string{h.env.ContainerName(sessionID): "OCI runtime create failed"}
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Error == nil || r.Error.Class != ClassContainerStartFailed {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.containers) != 0 || !reflect.DeepEqual(p.closes(), []int64{sessionID}) {
		t.Fatalf("left %d containers, relays closed %v", len(h.engine.containers), p.closes())
	}
}

func TestContainerStopRemovesTheSidecarAfterTheAgent(t *testing.T) {
	h := newEnvironment(t)
	p, log := h.withProxy()
	h.start(h.env, nil)
	r := h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusOK || r.Data["removed"] != true {
		t.Fatalf("%#v", r)
	}
	if want := []string{h.env.ContainerName(sessionID), h.env.SidecarName(sessionID)}; !reflect.DeepEqual(h.engine.removed, want) {
		t.Fatalf("removed %v, want %v", h.engine.removed, want)
	}
	if !reflect.DeepEqual(p.closes(), []int64{sessionID}) {
		t.Fatalf("relays closed %v", p.closes())
	}
	time.Sleep(100 * time.Millisecond)
	if strings.Contains(log.String(), "sidecar exited") {
		t.Fatalf("a sidecar the runner removed was taken for a crash: %s", log)
	}
}

func TestScrubRemovesTheSidecarsAndEveryRelay(t *testing.T) {
	h := newEnvironment(t)
	p, log := h.withProxy()
	h.start(h.env, nil)
	r := h.runEnv(h.env.Scrub, map[string]any{"image": pinned})
	if r.Status != protocol.StatusOK {
		t.Fatalf("%#v", r)
	}
	want := []string{h.env.ContainerName(sessionID), h.env.SidecarName(sessionID)}
	if got := r.Data["removed_containers"]; !reflect.DeepEqual(got, want) {
		t.Fatalf("removed %v", got)
	}
	if p.closedAll != 1 {
		t.Fatalf("CloseAll ran %d times", p.closedAll)
	}
	time.Sleep(100 * time.Millisecond)
	if strings.Contains(log.String(), "sidecar exited") {
		t.Fatalf("a sidecar the scrub removed was taken for a crash: %s", log)
	}
}

func TestASidecarThatExitsStopsTheAgentAndIsLogged(t *testing.T) {
	h := newEnvironment(t)
	_, log := h.withProxy()
	h.start(h.env, nil)
	sidecar := h.byName(h.env.SidecarName(sessionID))
	h.engine.mu.Lock()
	sidecar.Logs = []byte("aixle-runner proxy listening\npanic: something broke\n")
	h.engine.exit(sidecar, 2)
	h.engine.mu.Unlock()

	deadline := time.Now().Add(5 * time.Second)
	for {
		agent := h.byName(h.env.ContainerName(sessionID))
		h.engine.mu.Lock()
		running := agent.State.Running
		h.engine.mu.Unlock()
		if !running {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the agent's container still runs after its sidecar exited")
		}
		time.Sleep(20 * time.Millisecond)
	}
	// The agent's container stays, stopped: the platform reads it as dead and
	// collects its output.
	status := h.run(h.env.Status, map[string]any{})
	if status.Data["state"] != "terminated" {
		t.Fatalf("status %v", status.Data)
	}
	out := log.String()
	for _, want := range []string{"the proxy sidecar exited", "exit_code=2", "panic: something broke", "session=123"} {
		if !strings.Contains(out, want) {
			t.Errorf("the log lacks %q: %s", want, out)
		}
	}
}

func TestASidecarIsWatchedAgainWhenTheWaitStreamFails(t *testing.T) {
	h := newEnvironment(t)
	_, log := h.withProxy()
	h.env.SidecarWaitRetry = 10 * time.Millisecond
	h.engine.mu.Lock()
	h.engine.waitFailures = 2
	h.engine.mu.Unlock()
	h.start(h.env, nil)

	// The first two waits break while the sidecar runs; the third one waits.
	deadline := time.Now().Add(5 * time.Second)
	for {
		h.engine.mu.Lock()
		waits := h.engine.waits
		h.engine.mu.Unlock()
		if waits >= 3 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the watcher stopped after %d waits: %s", waits, log)
		}
		time.Sleep(10 * time.Millisecond)
	}
	if !h.running(h.env.ContainerName(sessionID)) {
		t.Fatal("a broken wait stream stopped the agent, but its sidecar still runs")
	}

	sidecar := h.byName(h.env.SidecarName(sessionID))
	h.engine.mu.Lock()
	h.engine.exit(sidecar, 3)
	h.engine.mu.Unlock()
	for h.running(h.env.ContainerName(sessionID)) {
		if time.Now().After(deadline) {
			t.Fatal("the agent's container still runs after its sidecar exited")
		}
		time.Sleep(20 * time.Millisecond)
	}
	out := log.String()
	for _, want := range []string{"watching the proxy sidecar failed", "the proxy sidecar exited", "exit_code=3"} {
		if !strings.Contains(out, want) {
			t.Errorf("the log lacks %q: %s", want, out)
		}
	}
}

func TestResumeServesTheRunningSessionsAgain(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	h.start(h.env, nil)
	other := h.another("aixle-r7-other")
	p2, _ := (&harness{t: t, engine: h.engine, env: other, state: h.state}).withProxy()
	other.ContainerStart(context.Background(), 456, mustJSON(t, startPayload(map[string]any{"network": "host", "proxy_port": 20456})))

	// A restarted host runner: a fresh relay, the same daemon.
	p := newFakeProxy(t)
	h.env.Proxy = p
	if err := h.env.Resume(context.Background()); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(p.sockets, []int64{sessionID}) || len(p.listeners) != 0 {
		t.Fatalf("sockets %v, listeners %v", p.sockets, p.listeners)
	}

	p2b := newFakeProxy(t)
	other.Proxy = p2b
	if err := other.Resume(context.Background()); err != nil {
		t.Fatal(err)
	}
	if p2b.listeners[456] != 20456 || len(p2b.sockets) != 0 {
		t.Fatalf("listeners %v, sockets %v (before: %v)", p2b.listeners, p2b.sockets, p2.listeners)
	}
}

func (h *harness) running(name string) bool {
	h.t.Helper()
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	c := h.engine.lookup(name)
	if c == nil {
		h.t.Fatalf("no container %s", name)
	}
	return c.State.Running
}

func TestResumeStopsTheAgentWhenItsRelayCannotBeServedAgain(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	h.start(h.env, nil)

	// A restarted host runner whose relay socket cannot be opened.
	p := newFakeProxy(t)
	p.socketErr = errors.New("listening on relay.sock: permission denied")
	h.env.Proxy = p
	if err := h.env.Resume(context.Background()); err != nil {
		t.Fatal(err)
	}
	if h.running(h.env.ContainerName(sessionID)) {
		t.Fatal("the agent still runs with no relay to reach the platform")
	}
	if !h.running(h.env.SidecarName(sessionID)) {
		t.Fatal("the sidecar was stopped: only the agent is, so that the session fails")
	}
	if status := h.run(h.env.Status, map[string]any{}); status.Data["state"] != "terminated" {
		t.Fatalf("status %v", status.Data)
	}
}

func TestResumeStopsANetworkHostAgentWhenItsListenerCannotBeServedAgain(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	h.start(h.env, map[string]any{"network": "host", "proxy_port": 20123})

	p := newFakeProxy(t)
	p.listenErr = fmt.Errorf("listening on 127.0.0.1:20123: %w", syscall.EADDRINUSE)
	h.env.Proxy = p
	if err := h.env.Resume(context.Background()); err != nil {
		t.Fatal(err)
	}
	if h.running(h.env.ContainerName(sessionID)) {
		t.Fatal("the agent still runs with no listener to reach the platform")
	}
	if status := h.run(h.env.Status, map[string]any{}); status.Data["state"] != "terminated" {
		t.Fatalf("status %v", status.Data)
	}
}
