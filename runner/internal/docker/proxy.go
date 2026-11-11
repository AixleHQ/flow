package docker

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"syscall"
	"time"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/pkg/stdcopy"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// The callback proxy's side of `container.start` and `container.stop`
// (PROTOCOL.md §5.8, §6.2; DESIGN.md §6.9.3): the proxy sidecar, a second
// container per session that owns the agent's network namespace, and with
// `network: host` the host runner's own listener instead.

// Result error classes of the proxy (PROTOCOL.md §6.2).
const (
	// ClassDockerFilesNotVisible: the daemon refused a bind mount of the host
	// runner's files because it does not see them (task 8b, decision 4).
	ClassDockerFilesNotVisible = "docker_files_not_visible"
	// ClassProxyPortInUse: with `network: host`, the session's port on the
	// machine is taken.
	ClassProxyPortInUse = "proxy_port_in_use"
	// ClassProxyStartFailed: the relay or the sidecar could not be started.
	ClassProxyStartFailed = "proxy_start_failed"
)

const (
	// RoleProxy is the sidecar's `aixle.com/role`, so that it is never taken
	// for the session container.
	RoleProxy = "proxy"
	// LabelProxyPort is the port of a `network: host` session's listener, on its
	// agent container, so that a restarted host runner listens on it again.
	LabelProxyPort = "aixle.com/proxy-port"

	// SidecarBinary is where the host runner's own binary is mounted in the
	// sidecar, read-only, as its entrypoint.
	SidecarBinary = "/aixle-runner"
	// SidecarSocketDir is where the session's socket directory is mounted in
	// the sidecar, read-only.
	SidecarSocketDir = "/run/aixle-proxy"
	// SidecarUser runs the sidecar: nobody, with no capability.
	SidecarUser = "65534:65534"
	// SidecarLogTail is how many lines of a sidecar's log the host runner logs
	// when it exits.
	SidecarLogTail = 50
	// SidecarLogTimeout bounds reading that tail: the log is a diagnostic, and
	// a logs endpoint that stalls must not hold up the host runner.
	SidecarLogTimeout = 10 * time.Second
	// SidecarWaitRetry is the first pause before the host runner watches a
	// sidecar again after Docker's wait stream failed; each failure in a row
	// doubles it, up to SidecarWaitRetryMax.
	SidecarWaitRetry    = time.Second
	SidecarWaitRetryMax = 30 * time.Second
)

// ProxyHost is the host runner's relay (proxy.Host). Nil on an Environment
// starts no proxy, as the tests of the other ops do.
type ProxyHost interface {
	// OpenSocket serves the session's relay on a Unix socket, and returns the
	// directory to mount into the sidecar.
	OpenSocket(sessionID int64) (dir string, err error)
	// OpenListener serves the session's relay on 127.0.0.1:port of the machine.
	// A port that is taken is an error that wraps syscall.EADDRINUSE.
	OpenListener(sessionID int64, port int) error
	// Close stops the session's relay.
	Close(sessionID int64)
	// CloseAll stops every relay of the environment.
	CloseAll()
	// Binary is the runner's own executable, as the daemon resolves it.
	Binary() string
}

// MinProxyPort and MaxProxyPort bound `container.start`'s `proxy_port`.
const (
	MinProxyPort = 1024
	MaxProxyPort = 65535
)

// SidecarName is the session's sidecar, `aixle-<key>-<session id>-proxy`.
func (e *Environment) SidecarName(sessionID int64) string {
	return e.ContainerName(sessionID) + "-proxy"
}

func (e *Environment) background() context.Context {
	if e.Background == nil {
		return context.Background()
	}
	return e.Background
}

// retire records that the host runner itself removes the sidecar, so that its
// watcher does not take the exit for a crash.
func (e *Environment) retire(id string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.retired == nil {
		e.retired = map[string]bool{}
	}
	e.retired[id] = true
}

func (e *Environment) isRetired(id string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.retired[id]
}

// notVisible says whether a daemon's refusal is that a bind source does not
// exist, which for the host runner's own files means that the daemon does not
// see this machine's filesystem.
func notVisible(err error) bool {
	return err != nil && strings.Contains(err.Error(), "bind source path does not exist")
}

func filesNotVisible(err error, paths ...string) protocol.Result {
	return protocol.ErrorResult(ClassDockerFilesNotVisible, fmt.Sprintf(
		"the Docker daemon cannot see this machine's files, so it refused to mount %s into the proxy sidecar (%v). "+
			"aixle-runner needs the Docker daemon of the machine it runs on: a remote DOCKER_HOST, or a daemon that "+
			"runs elsewhere (a Coder workspace that uses its server's Docker), is not supported",
		strings.Join(paths, " and "), err))
}

// openListener starts a `network: host` session's relay on its port.
func (e *Environment) openListener(sessionID int64, port int) *protocol.Result {
	err := e.Proxy.OpenListener(sessionID, port)
	if err == nil {
		return nil
	}
	var r protocol.Result
	if errors.Is(err, syscall.EADDRINUSE) {
		r = protocol.ErrorResult(ClassProxyPortInUse, fmt.Sprintf(
			"the session's proxy port 127.0.0.1:%d on this machine is in use (%v), so a session with network: host cannot start here", port, err))
	} else {
		r = protocol.ErrorResult(ClassProxyStartFailed, fmt.Sprintf("starting the callback proxy on 127.0.0.1:%d failed: %v", port, err))
	}
	return &r
}

// startSidecar opens the session's relay socket, then creates and starts the
// sidecar from the agent image, running the host runner's own binary in proxy
// mode on 127.0.0.1:port, the payload's `proxy_port`, in the network the
// payload names. It answers
// the sidecar's id, which the agent container joins
// (`NetworkMode: container:<id>`). On a refusal nothing is left: no
// container, no socket.
func (e *Environment) startSidecar(ctx context.Context, sessionID int64, image string, network container.NetworkMode, port int) (string, *protocol.Result) {
	fail := func(r protocol.Result) (string, *protocol.Result) {
		e.Proxy.Close(sessionID)
		return "", &r
	}
	dir, err := e.Proxy.OpenSocket(sessionID)
	if err != nil {
		return fail(protocol.ErrorResult(ClassProxyStartFailed, "starting the callback proxy's relay failed: "+err.Error()))
	}
	binary := e.Proxy.Binary()
	name := e.SidecarName(sessionID)
	config := &container.Config{
		Image:      image,
		Entrypoint: []string{SidecarBinary, "--mode", "proxy", "--socket", SidecarSocketDir + "/relay.sock", "--listen", "127.0.0.1:" + strconv.Itoa(port)},
		User:       SidecarUser,
		WorkingDir: "/",
		Labels: map[string]string{
			LabelEnvironment: e.Key,
			LabelSession:     strconv.FormatInt(sessionID, 10),
			LabelRole:        RoleProxy,
		},
	}
	host := &container.HostConfig{
		NetworkMode: network,
		Mounts: []mount.Mount{
			{Type: mount.TypeBind, Source: binary, Target: SidecarBinary, ReadOnly: true},
			{Type: mount.TypeBind, Source: dir, Target: SidecarSocketDir, ReadOnly: true},
		},
		RestartPolicy:  container.RestartPolicy{Name: container.RestartPolicyDisabled},
		CapDrop:        []string{"ALL"},
		SecurityOpt:    []string{"no-new-privileges"},
		ReadonlyRootfs: true,
	}
	if r := pastDeadline(ctx, "creating "+name); r != nil {
		return fail(*r)
	}
	created, err := e.API.ContainerCreate(ctx, client.ContainerCreateOptions{Name: name, Config: config, HostConfig: host})
	switch {
	case err == nil:
	case notVisible(err):
		return fail(filesNotVisible(err, binary, dir))
	case ctx.Err() != nil:
		removal := e.removeAfterFailedStart(ctx, name)
		if r := pastDeadline(ctx, "creating "+name); r != nil {
			return fail(*r)
		}
		return fail(protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("creating %s was cut short (%v); %s", name, ctx.Err(), removal)))
	case cerrdefs.IsConflict(err):
		return fail(protocol.ErrorResult(ClassContainerExists, fmt.Sprintf("creating %s failed: %v", name, err)))
	default:
		return fail(protocol.ErrorResult(ClassProxyStartFailed, fmt.Sprintf("creating the proxy sidecar %s failed: %v", name, err)))
	}
	if _, err := e.API.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		removal := e.removeAfterFailedStart(ctx, created.ID)
		if notVisible(err) {
			return fail(filesNotVisible(err, binary, dir))
		}
		if r := pastDeadline(ctx, "starting "+name); r != nil {
			return fail(*r)
		}
		return fail(protocol.ErrorResult(ClassProxyStartFailed, fmt.Sprintf("starting the proxy sidecar %s failed: %v; %s", name, err, removal)))
	}
	return created.ID, nil
}

// abandonSidecar removes the sidecar of a `container.start` whose agent
// container did not start, and stops its relay.
func (e *Environment) abandonSidecar(ctx context.Context, sessionID int64, id string) {
	if id != "" {
		e.retire(id)
		e.removeAfterFailedStart(ctx, id)
	}
	e.Proxy.Close(sessionID)
}

// watchSidecar waits, in the background, for the sidecar to stop. A sidecar
// the host runner did not remove itself has crashed, and the agent has lost
// its network with it: the agent's container is stopped, so that the session
// fails through the platform's dead-container path, and the exit is logged
// with its code and the tail of the sidecar's log (task 8b, decision 10).
//
// Docker's wait is a long-lived HTTP stream, and it can break while the
// sidecar still runs. The watcher then looks at the sidecar: one that has
// stopped or is gone has exited; one that still runs is waited for again,
// after a pause that doubles from SidecarWaitRetry up to
// SidecarWaitRetryMax. Only the sidecar's intentional removal or the host
// runner's stopping ends the watch.
//
// A sidecar that is gone without the host runner retiring it (removed by
// `docker rm -f`, say) stops the agent too, logged with exit code -1. That is
// intended: the agent has lost its network all the same, so it is handled as
// a sidecar exit (decision 10).
func (e *Environment) watchSidecar(sessionID int64, id string) {
	ctx := e.background()
	go func() {
		pause := e.sidecarWaitRetry()
		for {
			wait := e.API.ContainerWait(ctx, id, client.ContainerWaitOptions{Condition: container.WaitConditionNotRunning})
			select {
			case res := <-wait.Result:
				if res.Error == nil || res.Error.Message == "" {
					e.sidecarExited(ctx, sessionID, id, res.StatusCode)
					return
				}
				// A result that carries an error is the wait failing, not the
				// sidecar exiting (scrub.go reads it the same way): look at
				// the sidecar, as for an error on the stream.
				if ctx.Err() != nil || e.isRetired(id) {
					return
				}
				e.logger().Warn("watching the proxy sidecar failed; looking at it, then watching it again",
					"environment", e.Key, "session", sessionID, "sidecar", id, "error", res.Error.Message, "retry_in", pause)
			case err := <-wait.Error:
				if ctx.Err() != nil || e.isRetired(id) {
					return
				}
				if !cerrdefs.IsNotFound(err) {
					e.logger().Warn("watching the proxy sidecar failed; looking at it, then watching it again",
						"environment", e.Key, "session", sessionID, "sidecar", id, "error", err, "retry_in", pause)
				}
			case <-ctx.Done():
				return
			}
			if code, stopped := e.sidecarStopped(ctx, id); stopped {
				e.sidecarExited(ctx, sessionID, id, code)
				return
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(pause):
			}
			pause = min(2*pause, SidecarWaitRetryMax)
		}
	}()
}

func (e *Environment) sidecarWaitRetry() time.Duration {
	if e.SidecarWaitRetry > 0 {
		return e.SidecarWaitRetry
	}
	return SidecarWaitRetry
}

// sidecarStopped says whether the sidecar has stopped or is gone, with its
// exit code (-1 when it is gone). A sidecar that cannot be inspected is
// taken to run, and is waited for again.
func (e *Environment) sidecarStopped(ctx context.Context, id string) (int64, bool) {
	inspected, err := e.API.ContainerInspect(ctx, id, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return -1, true
	}
	if err != nil || inspected.Container.State == nil {
		return 0, false
	}
	if inspected.Container.State.Running {
		return 0, false
	}
	return int64(inspected.Container.State.ExitCode), true
}

// sidecarExited fails the session of a sidecar that exited: it stops the
// agent's container first, so that reading the sidecar's log, which goes
// through Docker's logs endpoint and can stall, never holds up the session's
// failure (decision 10). The exit is logged after, with its code and the tail
// of the sidecar's log.
func (e *Environment) sidecarExited(ctx context.Context, sessionID int64, id string, code int64) {
	if e.isRetired(id) {
		return
	}
	e.stopAgent(ctx, sessionID, "its sidecar exited")
	tail := e.logTail(ctx, id)
	e.logger().Warn("the proxy sidecar exited during the session; stopped the agent's container, so the session fails",
		"environment", e.Key, "session", sessionID, "sidecar", e.SidecarName(sessionID), "exit_code", code, "log_tail", tail)
}

// stopAgent stops the session's agent container, when it has the
// environment's and the session's labels, so that the session fails through
// the platform's dead-container path: the agent has lost its callbacks
// (task 8b, decision 10). The container stays, stopped, for the platform to
// read. why says what happened, for the log.
func (e *Environment) stopAgent(ctx context.Context, sessionID int64, why string) {
	name := e.ContainerName(sessionID)
	inspected, err := e.API.ContainerInspect(ctx, name, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return
	}
	if err != nil {
		e.logger().Warn("inspecting the agent's container after "+why+" failed", "environment", e.Key, "container", name, "error", err)
		return
	}
	var labels map[string]string
	if inspected.Container.Config != nil {
		labels = inspected.Container.Config.Labels
	}
	if labels[LabelEnvironment] != e.Key || labels[LabelSession] != strconv.FormatInt(sessionID, 10) || labels[LabelRole] != "" {
		return
	}
	timeout := StopTimeout
	if _, err := e.API.ContainerStop(ctx, inspected.Container.ID, client.ContainerStopOptions{Timeout: &timeout}); err != nil && !cerrdefs.IsNotFound(err) {
		e.logger().Warn("stopping the agent's container after "+why+" failed", "environment", e.Key, "container", name, "error", err)
	}
}

// logTail is the end of a container's log, both streams, as text. It is read
// under its own deadline, SidecarLogTimeout.
func (e *Environment) logTail(ctx context.Context, id string) string {
	timeout := e.SidecarLogTimeout
	if timeout <= 0 {
		timeout = SidecarLogTimeout
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	logs, err := e.API.ContainerLogs(ctx, id, client.ContainerLogsOptions{ShowStdout: true, ShowStderr: true, Tail: strconv.Itoa(SidecarLogTail)})
	if err != nil {
		return "(the log could not be read: " + err.Error() + ")"
	}
	defer logs.Close()
	var out bytes.Buffer
	if _, err := stdcopy.StdCopy(&out, &out, logs); err != nil && out.Len() == 0 {
		return "(the log could not be read: " + err.Error() + ")"
	}
	return strings.TrimSpace(out.String())
}

// removeSidecar removes the session's sidecar, when it has one with the
// environment's, the session's and the proxy role's labels, and stops its
// relay.
func (e *Environment) removeSidecar(ctx context.Context, sessionID int64) error {
	if e.Proxy != nil {
		defer e.Proxy.Close(sessionID)
	}
	name := e.SidecarName(sessionID)
	inspected, err := e.API.ContainerInspect(ctx, name, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("inspecting %s failed: %w", name, err)
	}
	var labels map[string]string
	if inspected.Container.Config != nil {
		labels = inspected.Container.Config.Labels
	}
	if labels[LabelEnvironment] != e.Key || labels[LabelSession] != strconv.FormatInt(sessionID, 10) || labels[LabelRole] != RoleProxy {
		return nil
	}
	e.retire(inspected.Container.ID)
	_, err = e.removeContainer(ctx, inspected.Container.ID, false)
	return err
}

// Resume serves the relays of the sessions that run on the environment again,
// after a restart of the host runner: the containers belong to the daemon and
// kept running, but the relay was the host runner's. A sidecar that exited
// while the host runner was down is handled as a crash. A relay or a
// `network: host` listener that cannot be served again leaves its agent with
// no callback, so the agent's container is stopped and the session fails
// through the dead-container path, as when a sidecar exits; nothing retries.
func (e *Environment) Resume(ctx context.Context) error {
	if e.Proxy == nil {
		return nil
	}
	found, err := e.containers(ctx)
	if err != nil {
		return fmt.Errorf("listing the environment's containers failed: %w", err)
	}
	for _, c := range found {
		session, err := strconv.ParseInt(c.Labels[LabelSession], 10, 64)
		if err != nil || session <= 0 {
			continue
		}
		switch {
		case c.Labels[LabelRole] == RoleProxy:
			if c.State != container.StateRunning {
				// It is still there, so inspect gives its real exit code; -1 is
				// left for one removed meanwhile, or one inspect cannot read.
				code, known := e.sidecarStopped(ctx, c.ID)
				if !known {
					code = -1
				}
				e.sidecarExited(ctx, session, c.ID, code)
				continue
			}
			if _, err := e.Proxy.OpenSocket(session); err != nil {
				e.logger().Warn("serving a running sidecar's relay again failed; stopping the agent's container, so the session fails",
					"environment", e.Key, "session", session, "error", err)
				e.stopAgent(ctx, session, "its relay could not be served again")
				continue
			}
			e.watchSidecar(session, c.ID)
		case c.Labels[LabelRole] == "" && c.Labels[LabelProxyPort] != "" && c.State == container.StateRunning:
			port, err := strconv.Atoi(c.Labels[LabelProxyPort])
			var r *protocol.Result
			if err != nil {
				failed := protocol.ErrorResult(ClassProxyStartFailed, fmt.Sprintf("the container's %s label %q is not a port", LabelProxyPort, c.Labels[LabelProxyPort]))
				r = &failed
			} else {
				r = e.openListener(session, port)
			}
			if r != nil {
				e.logger().Warn("serving a network: host session's proxy again failed; stopping the agent's container, so the session fails",
					"environment", e.Key, "session", session, "error", r.Error.Message)
				e.stopAgent(ctx, session, "its proxy listener could not be served again")
			}
		}
	}
	return nil
}
