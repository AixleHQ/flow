package docker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Result error classes of `container.start` (runner/protocol/PROTOCOL.md §6.2).
const (
	ClassContainerExists      = "container_exists"
	ClassForbiddenMount       = "forbidden_mount"
	ClassContainerStartFailed = "container_start_failed"
	// ClassVolumeNotOwned: a volume has the environment's name but not its label.
	ClassVolumeNotOwned = "volume_not_owned"
	// ClassContainerNotOwned: a container has the session's name but not the
	// environment's and the session's labels.
	ClassContainerNotOwned = "container_not_owned"
)

// volumeName is what a cache mount's `name` may be: what Docker accepts in a
// volume name.
var volumeName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)

// WorkspaceTarget is where the workspace volume is mounted.
const WorkspaceTarget = "/workspace"

// StopTimeout is how long `container.stop` waits after SIGTERM before the daemon
// kills the container.
const StopTimeout = 10

// ContainerStartPayload is the payload of `container.start`. The session is the
// envelope's `session_id`, not a payload field.
type ContainerStartPayload struct {
	// Image is the agent image's reference, a tag or a digest, as the platform
	// was given it. `container.start` pulls it.
	Image string            `json:"image"`
	Env   map[string]string `json:"env"`
	// WorkspaceVolume mounts `aixle-ws-<key>` at /workspace. Absent means true.
	WorkspaceVolume     *bool      `json:"workspace_volume"`
	Mounts              []Mount    `json:"mounts"`
	Network             string     `json:"network"`
	PID                 string     `json:"pid"`
	Resources           *Resources `json:"resources"`
	PrivilegeEscalation bool       `json:"privilege_escalation"`
	// ProxyPort is the session's port of the callback proxy on 127.0.0.1: the
	// sidecar's, in the session's own network namespace, or with `network:
	// host` the host runner's listener's, on the machine. The platform
	// configures it and sends it; the host runner has no port of its own.
	// Required whenever the environment runs the proxy, and with `network:
	// host`.
	ProxyPort int `json:"proxy_port"`
}

// Mount is one entry of `container.start`'s `mounts`: a cache volume of the
// environment, or a path of the machine.
type Mount struct {
	Type     string `json:"type"`
	Name     string `json:"name"`
	Source   string `json:"source"`
	Target   string `json:"target"`
	Writable bool   `json:"writable"`
}

// Resources are the container's limits. A zero field sets no limit.
type Resources struct {
	CPUs        float64 `json:"cpus"`
	MemoryBytes int64   `json:"memory_bytes"`
	PidsLimit   int64   `json:"pids_limit"`
}

// The mount types of `container.start`.
const (
	MountCache = "cache"
	MountBind  = "bind"
)

func invalid(format string, args ...any) *protocol.Result {
	r := protocol.ErrorResult(ClassInvalidPayload, fmt.Sprintf(format, args...))
	return &r
}

func decodePayload(raw json.RawMessage, out any, shape string) *protocol.Result {
	if err := json.Unmarshal(raw, out); err != nil {
		return invalid("the payload is not %s: %v", shape, err)
	}
	return nil
}

func absoluteClean(p string) bool {
	return strings.HasPrefix(p, "/") && path.Clean(p) == p
}

func validTarget(field, p string) *protocol.Result {
	if !absoluteClean(p) || p == "/" {
		return invalid("`%s` must be an absolute, clean path other than /, got %q", field, p)
	}
	return nil
}

// within says whether p is dir or inside it.
func within(p, dir string) bool {
	return p == dir || dir == "/" || strings.HasPrefix(p, dir+"/")
}

func resolve(p string) (string, error) {
	resolved, err := filepath.EvalSymlinks(p)
	if err != nil {
		return "", err
	}
	return filepath.Clean(resolved), nil
}

// checkBind refuses a bind source that would show the runner's state directory,
// where its credentials are, inside the container: the directory itself, a
// directory inside it, or one that contains it. Symlinks are resolved first, as
// the daemon resolves them.
func (e *Environment) checkBind(source string) *protocol.Result {
	refused := func(format string, args ...any) *protocol.Result {
		r := protocol.ErrorResult(ClassForbiddenMount, fmt.Sprintf(format, args...))
		return &r
	}
	if e.StateDir == "" {
		return refused("the runner's state directory is not known, so no bind mount can be checked")
	}
	state, err := filepath.Abs(e.StateDir)
	if err != nil {
		return refused("the runner's state directory %s cannot be resolved: %v", e.StateDir, err)
	}
	if resolved, err := resolve(state); err == nil {
		state = resolved
	}
	src, err := resolve(source)
	if err != nil {
		return refused("the bind source %s cannot be checked against the runner's state directory: %v", source, err)
	}
	if within(src, state) || within(state, src) {
		return refused("the bind source %s would expose the runner's state directory %s, which holds its credentials", source, state)
	}
	return nil
}

func (e *Environment) containerSpec(p ContainerStartPayload, sessionID int64) (*container.Config, *container.HostConfig, []string, *protocol.Result) {
	ref, err := imageReference(p.Image)
	if err != nil {
		return nil, nil, nil, invalid("%s", err.Error())
	}

	env := make([]string, 0, len(p.Env))
	for name, value := range p.Env {
		if name == "" || strings.ContainsAny(name, "=\x00") {
			return nil, nil, nil, invalid("`env` has an invalid variable name %q", name)
		}
		env = append(env, name+"="+value)
	}
	sort.Strings(env)

	var mounts []mount.Mount
	var volumes []string
	if p.WorkspaceVolume == nil || *p.WorkspaceVolume {
		volumes = append(volumes, e.WorkspaceVolume())
		mounts = append(mounts, mount.Mount{Type: mount.TypeVolume, Source: e.WorkspaceVolume(), Target: WorkspaceTarget})
	}
	for i, m := range p.Mounts {
		field := fmt.Sprintf("mounts[%d].target", i)
		if r := validTarget(field, m.Target); r != nil {
			return nil, nil, nil, r
		}
		switch m.Type {
		case MountCache:
			if !volumeName.MatchString(m.Name) {
				return nil, nil, nil, invalid("`mounts[%d].name` must be letters, digits, `_`, `.` and `-`, starting with a letter or digit, got %q", i, m.Name)
			}
			name := e.CacheVolume(m.Name)
			volumes = append(volumes, name)
			mounts = append(mounts, mount.Mount{Type: mount.TypeVolume, Source: name, Target: m.Target})
		case MountBind:
			if !absoluteClean(m.Source) {
				return nil, nil, nil, invalid("`mounts[%d].source` must be an absolute, clean path, got %q", i, m.Source)
			}
			if r := e.checkBind(m.Source); r != nil {
				return nil, nil, nil, r
			}
			mounts = append(mounts, mount.Mount{Type: mount.TypeBind, Source: m.Source, Target: m.Target, ReadOnly: !m.Writable})
		default:
			return nil, nil, nil, invalid("`mounts[%d].type` must be %q or %q, got %q", i, MountCache, MountBind, m.Type)
		}
	}

	network := p.Network
	switch network {
	case "":
		network = "bridge"
	case "bridge":
	case "host":
		if p.ProxyPort < MinProxyPort || p.ProxyPort > MaxProxyPort {
			return nil, nil, nil, invalid("with network \"host\", `proxy_port` must be an integer from %d to %d, got %d", MinProxyPort, MaxProxyPort, p.ProxyPort)
		}
	default:
		return nil, nil, nil, invalid("`network` must be \"bridge\" or \"host\", got %q", p.Network)
	}
	if e.Proxy != nil && (p.ProxyPort < MinProxyPort || p.ProxyPort > MaxProxyPort) {
		return nil, nil, nil, invalid("`proxy_port` must be an integer from %d to %d, got %d", MinProxyPort, MaxProxyPort, p.ProxyPort)
	}
	var pid container.PidMode
	switch p.PID {
	case "", "private":
	case "host":
		pid = "host"
	default:
		return nil, nil, nil, invalid("`pid` must be \"private\" or \"host\", got %q", p.PID)
	}

	var resources container.Resources
	if r := p.Resources; r != nil {
		if r.CPUs < 0 || r.MemoryBytes < 0 || r.PidsLimit < 0 {
			return nil, nil, nil, invalid("`resources` must not be negative")
		}
		resources.NanoCPUs = int64(r.CPUs * 1e9)
		resources.Memory = r.MemoryBytes
		resources.MemorySwap = r.MemoryBytes
		if r.PidsLimit > 0 {
			limit := r.PidsLimit
			resources.PidsLimit = &limit
		}
	}

	host := &container.HostConfig{
		Mounts:      mounts,
		NetworkMode: container.NetworkMode(network),
		PidMode:     pid,
		// An agent cannot resume mid-turn, so a container that stops stays stopped
		// and reports its exit code (DESIGN.md §17.1).
		RestartPolicy: container.RestartPolicy{Name: container.RestartPolicyDisabled},
		// As the hosted pod: no raw sockets, and no setuid escalation unless the
		// runtime's sudo needs it.
		CapDrop:   []string{"NET_RAW"},
		Resources: resources,
	}
	if !p.PrivilegeEscalation {
		host.SecurityOpt = []string{"no-new-privileges"}
	}
	config := &container.Config{
		Image: ref,
		Env:   env,
		Labels: map[string]string{
			LabelEnvironment: e.Key,
			LabelSession:     strconv.FormatInt(sessionID, 10),
		},
	}
	return config, host, volumes, nil
}

// ContainerStart is `container.start`: it pulls the payload's image, always, then
// creates and starts the session's agent container from it, running the image's
// own entrypoint and command, as a hosted pod does. Docker's create API does not
// pull, and a failed pull is `image_pull_failed`, with nothing created. The container is
// named and labelled with the envelope's session. Nothing of the runner goes into
// it: no binary, no socket, no token and nothing of the state directory. With a
// Proxy, the session's proxy sidecar is created and started first, and the agent
// container joins its network namespace; the runner's binary and the relay's
// socket go into the sidecar only, and the sidecar listens on the payload's
// `proxy_port`. With `network: host` the relay listens on that port of the
// machine instead, and there is no sidecar. Over
// another session's container it answers `session_mismatch`; over its own, or
// over a container of the environment that names no session, `container_exists`.
//
// The pull, the volumes, the create and the start run until the op's
// `deadline_at` at most. Past it, nobody waits for the result, so nothing is
// created, and the serial ops loop moves on to the session's next op, the
// cleanup's `container.stop` and `env.reset` among them.
func (e *Environment) ContainerStart(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	if deadline, ok := protocol.OpDeadline(ctx); ok {
		var cancel context.CancelFunc
		ctx, cancel = context.WithDeadline(ctx, deadline)
		defer cancel()
	}
	var p ContainerStartPayload
	if r := decodePayload(raw, &p, "a container.start payload"); r != nil {
		return *r
	}
	config, host, volumes, r := e.containerSpec(p, sessionID)
	if r != nil {
		return *r
	}
	name := e.ContainerName(sessionID)

	existing, err := e.containers(ctx)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, "listing the environment's containers failed: "+err.Error())
	}
	if len(existing) > 0 {
		session := strconv.FormatInt(sessionID, 10)
		var names []string
		for _, c := range existing {
			if other := c.Labels[LabelSession]; other != "" && other != session {
				return protocol.ErrorResult(ClassSessionMismatch, fmt.Sprintf(
					"environment %s has the session container %s of session %s, not the op's session %d; nothing was started",
					e.Key, containerLabel(c), other, sessionID))
			}
			names = append(names, containerLabel(c))
		}
		return protocol.ErrorResult(ClassContainerExists, fmt.Sprintf(
			"environment %s already has a container (%s): run container.stop or env.scrub first", e.Key, strings.Join(names, ", ")))
	}

	// Pulled once the cheap refusals above are out of the way, so a session
	// that cannot start here pulls nothing.
	if err := pull(ctx, e.API, config.Image); err != nil {
		if r := pastDeadline(ctx, "the pull of "+config.Image); r != nil {
			return *r
		}
		return protocol.ErrorResult(ClassImagePull, fmt.Sprintf("pulling %s failed: %v", config.Image, err))
	}

	// The volumes are created with the environment's label, so that reset finds
	// them by label as well as by name. Creating a volume that exists returns it
	// unchanged, so one with the name but not the label is not the environment's:
	// it is refused and left alone (PROTOCOL.md §6.2).
	for _, v := range volumes {
		res, err := e.API.VolumeCreate(ctx, client.VolumeCreateOptions{Name: v, Labels: map[string]string{LabelEnvironment: e.Key}})
		if err != nil {
			if r := pastDeadline(ctx, "creating the volume "+v); r != nil {
				return *r
			}
			return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("creating the volume %s failed: %v", v, err))
		}
		if got := res.Volume.Labels[LabelEnvironment]; got != e.Key {
			return protocol.ErrorResult(ClassVolumeNotOwned, fmt.Sprintf(
				"the volume %s exists without the label %s=%s (it has %q), so it is not this environment's; it was not mounted or changed",
				v, LabelEnvironment, e.Key, got))
		}
	}

	// The callback proxy (PROTOCOL.md §5.8): the sidecar is created first and
	// owns the network namespace the agent joins, so that it outlives the
	// agent's last call; with `network: host` the host runner listens itself.
	sidecar := ""
	if e.Proxy != nil {
		if host.NetworkMode == "host" {
			if r := e.openListener(sessionID, p.ProxyPort); r != nil {
				return *r
			}
			config.Labels[LabelProxyPort] = strconv.Itoa(p.ProxyPort)
		} else {
			id, r := e.startSidecar(ctx, sessionID, config.Image, host.NetworkMode, p.ProxyPort)
			if r != nil {
				return *r
			}
			sidecar = id
			host.NetworkMode = container.NetworkMode("container:" + id)
		}
	}
	result := e.startAgent(ctx, name, config, host)
	if result.Status != protocol.StatusOK {
		if e.Proxy != nil {
			e.abandonSidecar(ctx, sessionID, sidecar)
		}
		return result
	}
	if sidecar != "" {
		e.watchSidecar(sessionID, sidecar)
	}
	return result
}

// startAgent creates and starts the agent container of `container.start`. A
// container that was created but did not start is removed.
func (e *Environment) startAgent(ctx context.Context, name string, config *container.Config, host *container.HostConfig) protocol.Result {
	if r := pastDeadline(ctx, "creating "+name); r != nil {
		return *r
	}
	created, err := e.API.ContainerCreate(ctx, client.ContainerCreateOptions{Name: name, Config: config, HostConfig: host})
	switch {
	case err == nil:
	case ctx.Err() != nil:
		// The daemon may have created it before the answer was cut off: by the
		// op's deadline, or by the runner stopping. Either way it is removed.
		removal := e.removeAfterFailedStart(ctx, name)
		if r := pastDeadline(ctx, "creating "+name); r != nil {
			return *r
		}
		return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf(
			"creating %s was cut short (%v); %s", name, ctx.Err(), removal))
	case cerrdefs.IsConflict(err):
		return protocol.ErrorResult(ClassContainerExists, fmt.Sprintf("creating %s failed: %v", name, err))
	default:
		return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("creating %s failed: %v", name, err))
	}
	if _, err := e.API.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		// A container that never started is not left behind.
		removal := e.removeAfterFailedStart(ctx, created.ID)
		if r := pastDeadline(ctx, "starting "+name); r != nil {
			return *r
		}
		return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("starting %s failed: %v; %s", name, err, removal))
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"container_id": created.ID, "name": name}}
}

// defaultRemoveTimeout bounds the removal after a failed or cut-short
// `container.start` when Environment.RemoveTimeout is zero.
const defaultRemoveTimeout = 30 * time.Second

// removeAfterFailedStart removes what a failed or cut-short `container.start`
// may have left, and says in the answer's words what became of it. The removal
// runs under its own timeout, not under the op's context, which has ended or
// is about to: a stalled daemon then cannot hold up the serial ops loop. A
// removal that fails is logged, and the answer stays `container_start_failed`:
// the session still holds its machine, and the cleanup's `env.reset` removes a
// container that is left (PROTOCOL.md §6.2).
func (e *Environment) removeAfterFailedStart(ctx context.Context, ref string) string {
	timeout := e.RemoveTimeout
	if timeout <= 0 {
		timeout = defaultRemoveTimeout
	}
	removeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), timeout)
	defer cancel()
	_, err := e.API.ContainerRemove(removeCtx, ref, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
	if err == nil || cerrdefs.IsNotFound(err) {
		return "nothing was left"
	}
	e.logger().Warn("removing the container of a failed container.start failed; env.reset removes what is left",
		"environment", e.Key, "container", ref, "error", err)
	return fmt.Sprintf("removing what the daemon made failed (%v), and env.reset removes it", err)
}

// pastDeadline is the answer of a `container.start` whose deadline_at passed
// during step, or nil while it has not. A context that ended because the runner
// is stopping is not a deadline: the loop discards that result (host.Loop).
func pastDeadline(ctx context.Context, step string) *protocol.Result {
	if !errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return nil
	}
	r := protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf(
		"the op's deadline_at passed during %s; nobody waits for this result, so nothing was created", step))
	return &r
}

func containerLabel(c container.Summary) string {
	if len(c.Names) > 0 {
		return trimName(c.Names[0])
	}
	return c.ID
}

// ContainerStopPayload is the payload of `container.stop`: `{}`. The session is
// the envelope's `session_id`.
type ContainerStopPayload struct{}

// ContainerStop is `container.stop`: it stops the envelope's session's container,
// giving the entrypoint StopTimeout seconds to shut down, and removes it with its
// anonymous volumes. The named volumes stay. The name alone does not prove the
// container is the session's: one without the environment's and the session's
// labels is refused and not touched. Without this session's container it answers
// an error and touches nothing: `session_mismatch` when the environment's session
// container is another session's, `no_session_container` when there is none.
func (e *Environment) ContainerStop(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p ContainerStopPayload
	if r := decodePayload(raw, &p, "{}"); r != nil {
		return *r
	}
	name := e.ContainerName(sessionID)
	inspected, err := e.API.ContainerInspect(ctx, name, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return e.noContainerOf(ctx, sessionID)
	}
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("inspecting %s failed: %v", name, err))
	}
	var labels map[string]string
	if inspected.Container.Config != nil {
		labels = inspected.Container.Config.Labels
	}
	session := strconv.FormatInt(sessionID, 10)
	if labels[LabelEnvironment] != e.Key || labels[LabelSession] != session {
		return protocol.ErrorResult(ClassContainerNotOwned, fmt.Sprintf(
			"the container %s does not carry the labels %s=%s and %s=%s, so it is not this session's; it was not stopped or removed",
			name, LabelEnvironment, e.Key, LabelSession, session))
	}
	// By ID, so that what is removed is the container whose labels were checked.
	removed, err := e.removeContainer(ctx, inspected.Container.ID, true)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, err.Error())
	}
	// The sidecar goes with the agent's container, after it: the agent's last
	// call has been answered by then.
	if err := e.removeSidecar(ctx, sessionID); err != nil {
		return protocol.ErrorResult(ClassDockerError, err.Error())
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"removed": removed}}
}

// noContainerOf is the answer of `container.stop` when the environment has no
// container of the session's name: the environment's session container, when it
// has one, is another session's.
func (e *Environment) noContainerOf(ctx context.Context, sessionID int64) protocol.Result {
	c, err := e.sessionContainer(ctx)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, "finding the session container failed: "+err.Error())
	}
	if c != nil {
		if r := checkSession(c, sessionID); r != nil {
			return *r
		}
	}
	return protocol.ErrorResult(ClassNoSessionContainer, fmt.Sprintf(
		"environment %s has no container of session %d: nothing was stopped", e.Key, sessionID))
}

// removeContainer stops (when graceful) and removes a container. It answers
// whether there was one to remove.
func (e *Environment) removeContainer(ctx context.Context, id string, graceful bool) (bool, error) {
	if graceful {
		timeout := StopTimeout
		_, err := e.API.ContainerStop(ctx, id, client.ContainerStopOptions{Timeout: &timeout})
		if cerrdefs.IsNotFound(err) {
			return false, nil
		}
		if err != nil {
			return false, fmt.Errorf("stopping %s failed: %w", id, err)
		}
	}
	_, err := e.API.ContainerRemove(ctx, id, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
	if cerrdefs.IsNotFound(err) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("removing %s failed: %w", id, err)
	}
	return true, nil
}
