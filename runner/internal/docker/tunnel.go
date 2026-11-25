package docker

import (
	"context"
	"fmt"
	"net"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
)

// The tunnel's side of `container.start` (runner/protocol/PROTOCOL.md §6.2, §8.12;
// docs/design/agent-runtimes/runner-relay.md §3.3, §9): the session's five ports are
// checked when they are the machine's own, reached through a Dialer, waited for, and
// then served for this session alone.

// defaultTunnelReadyTimeout is how long a session's ports have to answer, as long as a
// hosted session waits for them (DockerRuntime::PORT_READY_TIMEOUT).
const defaultTunnelReadyTimeout = 30 * time.Second

func joinPorts(ports []int) string {
	parts := make([]string, len(ports))
	for i, p := range ports {
		parts[i] = strconv.Itoa(p)
	}
	return strings.Join(parts, ",")
}

func parsePorts(list string) []int {
	var ports []int
	for _, field := range strings.Split(list, ",") {
		p, err := strconv.Atoi(field)
		if err != nil || p < MinProxyPort || p > MaxProxyPort {
			return nil
		}
		ports = append(ports, p)
	}
	return ports
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

// portsInUse are the ports that cannot be bound on the machine now, which is what a
// session with `network: host` needs: the agent binds them on every interface.
func portsInUse(ports []int) []int {
	var busy []int
	for _, port := range ports {
		l, err := net.Listen("tcp", ":"+strconv.Itoa(port))
		if err != nil {
			busy = append(busy, port)
			continue
		}
		l.Close()
	}
	return busy
}

// tunnelDialer is the way to reach a session's ports, nil when the tunnel does not serve
// the session: it is off, the payload had no ports, or a session on the bridge network
// has no sidecar to dial through.
func (e *Environment) tunnelDialer(sessionID int64, hostNetwork bool, sidecar string, ports []int) tunnel.Dialer {
	if e.Tunnel == nil || len(ports) == 0 {
		return nil
	}
	if !hostNetwork && sidecar == "" {
		return nil
	}
	return e.dialerFor(sessionID, hostNetwork)
}

// dialerFor picks how a session's ports are reached: the machine runner's own loopback on
// the host network, the sidecar's dial socket on the bridge network. It is nil on the
// bridge network when there is no proxy host or its dial directory is not usable. Both
// the start of a session and the restore after a restart of the runner choose here.
func (e *Environment) dialerFor(sessionID int64, hostNetwork bool) tunnel.Dialer {
	if hostNetwork {
		return tunnel.LoopbackDialer{}
	}
	if e.Proxy == nil {
		return nil
	}
	dir, err := e.Proxy.DialDir(sessionID)
	if err != nil {
		e.logger().Warn("the tunnel's dial directory is not usable; the session's terminal stays unreachable",
			"environment", e.Key, "session", sessionID, "error", err)
		return nil
	}
	return tunnel.SocketDialer{Socket: filepath.Join(dir, proxy.DialSocketName)}
}

// serveTunnel waits for the five ports to answer, with the dial the relay's streams use,
// and then serves them for the session. A session whose ports never answer is an
// error: the platform's `ready` stays honest (docs §9).
func (e *Environment) serveTunnel(ctx context.Context, sessionID int64, name string, ports []int, dialer tunnel.Dialer) *protocol.Result {
	timeout := e.TunnelReadyTimeout
	if timeout <= 0 {
		timeout = defaultTunnelReadyTimeout
	}
	waitCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	pending := ports
	for {
		pending = e.unanswered(waitCtx, dialer, pending)
		if len(pending) == 0 {
			e.Tunnel.Set(tunnel.Grant{SessionID: sessionID, Ports: ports, Dialer: dialer})
			return nil
		}
		if r := pastDeadline(ctx, "waiting for the session's ports"); r != nil {
			return r
		}
		if ctx.Err() != nil {
			r := protocol.ErrorResult(ClassContainerStartFailed, "the runner is stopping: "+ctx.Err().Error())
			return &r
		}
		if waitCtx.Err() != nil {
			r := protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf(
				"the session's ports %s did not answer within %s, so the session's terminal could not be reached. The container was removed",
				joinPorts(pending), timeout))
			return &r
		}
		if !e.agentRuns(ctx, name) {
			r := protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf(
				"the container %s stopped before its ports %s answered. The container was removed", name, joinPorts(pending)))
			return &r
		}
		select {
		case <-waitCtx.Done():
		case <-time.After(250 * time.Millisecond):
		}
	}
}

// unanswered dials each port once and returns the ones that did not answer.
func (e *Environment) unanswered(ctx context.Context, dialer tunnel.Dialer, ports []int) []int {
	var pending []int
	for _, port := range ports {
		dctx, cancel := context.WithTimeout(ctx, 2*time.Second)
		conn, err := dialer.Dial(dctx, port)
		cancel()
		if err != nil {
			pending = append(pending, port)
			continue
		}
		conn.Close()
	}
	return pending
}

// agentRuns says whether the session's container is running. One that cannot be
// inspected is taken to run.
func (e *Environment) agentRuns(ctx context.Context, name string) bool {
	inspected, err := e.API.ContainerInspect(ctx, name, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return false
	}
	if err != nil || inspected.Container.State == nil {
		return true
	}
	return inspected.Container.State.Running
}

// abandonAgent removes what a `container.start` made when its ports never answered: the
// agent's container, the sidecar and the relay.
func (e *Environment) abandonAgent(ctx context.Context, sessionID int64, name, sidecar string) {
	if e.Tunnel != nil {
		e.Tunnel.Clear(sessionID)
	}
	e.removeAfterFailedStart(ctx, name)
	if e.Proxy != nil {
		e.abandonSidecar(ctx, sessionID, sidecar)
	}
}

// restoreTunnel serves a running session's ports again after a restart of the host
// runner: the containers belong to the daemon and kept running, but what the runner
// served was its own.
func (e *Environment) restoreTunnel(sessionID int64, c container.Summary) {
	ports := parsePorts(c.Labels[LabelTunnelPorts])
	if e.Tunnel == nil || len(ports) != len(TunnelSurfaces) || c.State != container.StateRunning {
		return
	}
	dialer := e.dialerFor(sessionID, c.HostConfig.NetworkMode == "host")
	if dialer == nil {
		return
	}
	e.Tunnel.Set(tunnel.Grant{SessionID: sessionID, Ports: ports, Dialer: dialer})
}
