package docker

import (
	"context"
	"net"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/moby/moby/api/types/mount"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
)

// The tunnel's side of container.start: the five ports, the dial, the readiness wait,
// and what the runner then serves (runner-relay.md §3.3, §9).

// listenAll opens a listener for each of five surfaces and returns their ports in the
// order of TunnelSurfaces. Each listener accepts and closes, as a probe needs.
func listenAll(t *testing.T) []net.Listener {
	t.Helper()
	var ls []net.Listener
	for range TunnelSurfaces {
		l, err := net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { l.Close() })
		go func() {
			for {
				c, err := l.Accept()
				if err != nil {
					return
				}
				c.Close()
			}
		}()
		ls = append(ls, l)
	}
	return ls
}

func portOf(l net.Listener) int { return l.Addr().(*net.TCPAddr).Port }

func tunnelPayload(ports []int) map[string]any {
	m := map[string]any{}
	for i, surface := range TunnelSurfaces {
		m[surface] = ports[i]
	}
	return map[string]any{"ports": m}
}

func portsOf(ls []net.Listener) []int {
	var ports []int
	for _, l := range ls {
		ports = append(ports, portOf(l))
	}
	return ports
}

// withTunnel turns the tunnel on for the environment, as the check-in does.
func (h *harness) withTunnel() *tunnel.Serving {
	h.t.Helper()
	serving := &tunnel.Serving{}
	h.env.Tunnel = serving
	h.env.TunnelReadyTimeout = 600 * time.Millisecond
	return serving
}

// sidecarDial serves the sidecar's dial socket in the test's process, as the sidecar in
// the session's namespace would: the listeners stand for the ports in it.
func sidecarDial(t *testing.T, p *fakeProxy, ports []int) {
	t.Helper()
	dir, err := p.DialDir(sessionID)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go proxy.ServeDial(ctx, filepath.Join(dir, proxy.DialSocketName), ports, nil)
}

func TestContainerStartOnTheBridgeGivesTheSidecarTheDialSocketAndThePorts(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	serving := h.withTunnel()
	ls := listenAll(t)
	ports := portsOf(ls)
	sidecarDial(t, p, ports)

	h.start(h.env, map[string]any{"tunnel": tunnelPayload(ports)})

	sidecar := h.byName(h.env.SidecarName(sessionID))
	wantEntrypoint := []string{SidecarBinary, "--mode", "proxy", "--socket", SidecarSocketDir + "/relay.sock",
		"--listen", "127.0.0.1:" + strconv.Itoa(testProxyPort),
		"--dial-socket", SidecarDialDir + "/" + proxy.DialSocketName, "--dial-ports", joinPorts(ports)}
	if !reflect.DeepEqual([]string(sidecar.Config.Entrypoint), wantEntrypoint) {
		t.Fatalf("sidecar runs %v", sidecar.Config.Entrypoint)
	}
	dir, _ := p.DialDir(sessionID)
	wantDial := mount.Mount{Type: mount.TypeBind, Source: dir, Target: SidecarDialDir}
	if got := sidecar.Host.Mounts[len(sidecar.Host.Mounts)-1]; !reflect.DeepEqual(got, wantDial) {
		t.Fatalf("the dial directory is mounted as %#v, want read-write %#v", got, wantDial)
	}
	agent := h.byName(h.env.ContainerName(sessionID))
	if agent.Config.Labels[LabelTunnelPorts] != joinPorts(ports) {
		t.Fatalf("agent labels %v", agent.Config.Labels)
	}
	for _, m := range agent.Host.Mounts {
		if strings.HasPrefix(m.Source, p.dir) {
			t.Fatalf("the agent container mounts the runner's %s", m.Source)
		}
	}

	// The runner serves these five ports of this session, through the sidecar, and no other.
	for _, port := range ports {
		dialer, ok := serving.Authorize(sessionID, port)
		if !ok {
			t.Fatalf("port %d is not served", port)
		}
		conn, err := dialer.Dial(context.Background(), port)
		if err != nil {
			t.Fatalf("dialing %d: %v", port, err)
		}
		conn.Close()
	}
	if _, ok := serving.Authorize(sessionID, ports[0]+1); ok {
		t.Error("a port outside the five is served")
	}
	if _, ok := serving.Authorize(sessionID+1, ports[0]); ok {
		t.Error("another session's port is served")
	}

	// container.stop takes the grant away.
	if r := h.run(h.env.ContainerStop, map[string]any{}); r.Status != protocol.StatusOK {
		t.Fatalf("stop: %#v", r)
	}
	if _, ok := serving.Authorize(sessionID, ports[0]); ok {
		t.Error("the session is still served after container.stop")
	}
}

func TestContainerStartWaitsForThePortsBeforeItAnswers(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	serving := h.withTunnel()
	h.env.TunnelReadyTimeout = 10 * time.Second
	ls := listenAll(t)
	ports := portsOf(ls)
	// The last port starts answering only after a while, as ttyd or the IDE does.
	late := ls[len(ls)-1]
	late.Close()
	sidecarDial(t, p, ports)
	go func() {
		time.Sleep(700 * time.Millisecond)
		l, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(portOf(late)))
		if err != nil {
			return
		}
		t.Cleanup(func() { l.Close() })
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			c.Close()
		}
	}()

	start := time.Now()
	h.start(h.env, map[string]any{"tunnel": tunnelPayload(ports)})
	if time.Since(start) < 600*time.Millisecond {
		t.Fatalf("container.start answered after %v, before the last port did", time.Since(start))
	}
	if _, ok := serving.Authorize(sessionID, ports[4]); !ok {
		t.Fatal("not served")
	}
}

func TestContainerStartFailsAndRemovesWhatItMadeWhenThePortsNeverAnswer(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	serving := h.withTunnel()
	ls := listenAll(t)
	ports := portsOf(ls)
	sidecarDial(t, p, ports)
	ls[2].Close() // the file panel never listens

	r := h.run(h.env.ContainerStart, startPayload(map[string]any{"tunnel": tunnelPayload(ports)}))
	if r.Error == nil || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, strconv.Itoa(ports[2])) {
		t.Fatalf("result %#v", r)
	}
	if len(h.engine.containers) != 0 {
		t.Fatalf("%d containers left", len(h.engine.containers))
	}
	if _, ok := serving.Authorize(sessionID, ports[0]); ok {
		t.Error("a session whose start failed is served")
	}
}

func TestContainerStartWithHostNetworkAnswersPortsInUseAndCreatesNothing(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	serving := h.withTunnel()
	ls := listenAll(t)
	ports := portsOf(ls)
	// The machine's own process holds one of the ports, on every interface.
	taken, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Fatal(err)
	}
	defer taken.Close()
	ports[3] = taken.Addr().(*net.TCPAddr).Port
	for _, l := range ls {
		l.Close()
	}

	r := h.run(h.env.ContainerStart, startPayload(map[string]any{"network": "host", "proxy_port": 20123, "tunnel": tunnelPayload(ports)}))

	if r.Error == nil || r.Error.Class != ClassPortsInUse || !strings.Contains(r.Error.Message, strconv.Itoa(ports[3])) {
		t.Fatalf("result %#v", r)
	}
	if len(h.engine.containers) != 0 || len(h.engine.pulls) != 0 {
		t.Fatalf("something was created: %d containers, %d pulls", len(h.engine.containers), len(h.engine.pulls))
	}
	if _, ok := serving.Authorize(sessionID, ports[0]); ok {
		t.Error("a session that did not start is served")
	}
}

func TestContainerStartWithHostNetworkDialsTheMachinesLoopback(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	serving := h.withTunnel()
	h.env.TunnelReadyTimeout = 10 * time.Second
	ls := listenAll(t)
	ports := portsOf(ls)
	// Free at the check; answering by the time the container is up (the agent binds them).
	for _, l := range ls {
		l.Close()
	}
	go func() {
		time.Sleep(300 * time.Millisecond)
		for _, port := range ports {
			l, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(port))
			if err != nil {
				continue
			}
			t.Cleanup(func() { l.Close() })
			go func() {
				for {
					c, err := l.Accept()
					if err != nil {
						return
					}
					c.Close()
				}
			}()
		}
	}()

	h.start(h.env, map[string]any{"network": "host", "proxy_port": 20123, "tunnel": tunnelPayload(ports)})

	agent := h.only()
	if agent.Config.Labels[LabelTunnelPorts] != joinPorts(ports) || len(p.sockets) != 0 {
		t.Fatalf("labels %v, sockets %v", agent.Config.Labels, p.sockets)
	}
	dialer, ok := serving.Authorize(sessionID, ports[1])
	if !ok {
		t.Fatal("not served")
	}
	if _, isLoopback := dialer.(tunnel.LoopbackDialer); !isLoopback {
		t.Fatalf("dialer %T", dialer)
	}
}

func TestTheTunnelPayloadIsIgnoredWhenTheTunnelIsOff(t *testing.T) {
	h := newEnvironment(t)
	h.withProxy()
	// No h.withTunnel(): the platform has not turned the tunnel on for this machine.
	h.start(h.env, map[string]any{"tunnel": tunnelPayload([]int{7681, 7682, 4040, 4041, 8443})})

	sidecar := h.byName(h.env.SidecarName(sessionID))
	for _, arg := range sidecar.Config.Entrypoint {
		if strings.HasPrefix(arg, "--dial") {
			t.Fatalf("the sidecar got %v", sidecar.Config.Entrypoint)
		}
	}
	if _, ok := h.byName(h.env.ContainerName(sessionID)).Config.Labels[LabelTunnelPorts]; ok {
		t.Fatal("the agent is labelled with tunnel ports")
	}
}

func TestTheTunnelPayloadIsChecked(t *testing.T) {
	for name, tunnelValue := range map[string]any{
		"a missing surface":   map[string]any{"ports": map[string]any{"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041}},
		"an unknown surface":  map[string]any{"ports": map[string]any{"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041, "shell": 8443}},
		"a port below 1024":   tunnelPayload([]int{80, 7682, 4040, 4041, 8443}),
		"a port above 65535":  tunnelPayload([]int{7681, 7682, 4040, 4041, 70000}),
		"the same port twice": tunnelPayload([]int{7681, 7681, 4040, 4041, 8443}),
		"ports as strings":    map[string]any{"ports": map[string]any{"tty": "7681", "view": 7682, "fs": 4040, "upload": 4041, "ide": 8443}},
		"no ports":            map[string]any{},
	} {
		h := newEnvironment(t)
		h.withProxy()
		h.withTunnel()
		r := h.run(h.env.ContainerStart, startPayload(map[string]any{"tunnel": tunnelValue}))
		if r.Error == nil || r.Error.Class != ClassInvalidPayload || len(h.engine.containers) != 0 {
			t.Errorf("%s: %#v", name, r)
		}
	}
}

func TestResumeServesARunningSessionsPortsAgain(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	h.withTunnel()
	ls := listenAll(t)
	ports := portsOf(ls)
	sidecarDial(t, p, ports)
	h.start(h.env, map[string]any{"tunnel": tunnelPayload(ports)})

	// A restarted host runner: nothing is served until Resume, and the same daemon runs on.
	restarted := &tunnel.Serving{}
	h.env.Tunnel = restarted
	h.env.Proxy = p
	if err := h.env.Resume(context.Background()); err != nil {
		t.Fatal(err)
	}
	dialer, ok := restarted.Authorize(sessionID, ports[0])
	if !ok {
		t.Fatal("the session's ports are not served again")
	}
	conn, err := dialer.Dial(context.Background(), ports[0])
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
	if _, ok := restarted.Authorize(sessionID+1, ports[0]); ok {
		t.Error("another session is served")
	}
}

func TestScrubStopsServing(t *testing.T) {
	h := newEnvironment(t)
	p, _ := h.withProxy()
	serving := h.withTunnel()
	ls := listenAll(t)
	ports := portsOf(ls)
	sidecarDial(t, p, ports)
	h.start(h.env, map[string]any{"tunnel": tunnelPayload(ports)})

	if r := h.runEnv(h.env.Reset, map[string]any{}); r.Status != protocol.StatusOK {
		t.Fatalf("reset: %#v", r)
	}
	if _, ok := serving.Authorize(sessionID, ports[0]); ok {
		t.Error("the session is still served after env.reset")
	}
}
