package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Result error classes of `container.start` (runner/protocol/PROTOCOL.md §6.2).
const (
	ClassContainerExists      = "container_exists"
	ClassImageNotFound        = "image_not_found"
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
	Image  string            `json:"image"`
	Digest string            `json:"digest"`
	Env    map[string]string `json:"env"`
	// WorkspaceVolume mounts `aixle-ws-<key>` at /workspace. Absent means true.
	WorkspaceVolume     *bool      `json:"workspace_volume"`
	Mounts              []Mount    `json:"mounts"`
	Network             string     `json:"network"`
	PID                 string     `json:"pid"`
	Resources           *Resources `json:"resources"`
	PrivilegeEscalation bool       `json:"privilege_escalation"`
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
	ref, err := ImageEnsurePayload{Image: p.Image, Digest: p.Digest}.Reference()
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
	case "bridge", "host":
	default:
		return nil, nil, nil, invalid("`network` must be \"bridge\" or \"host\", got %q", p.Network)
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

// ContainerStart is `container.start`: it creates and starts the session's agent
// container from the image pinned by digest, running the image's own entrypoint
// and command, as a hosted pod does. The container is named and labelled with
// the envelope's session. Nothing of the runner goes into it: no binary, no
// socket, no token and nothing of the state directory.
func (e *Environment) ContainerStart(ctx context.Context, raw json.RawMessage) protocol.Result {
	sessionID, r := opSession(ctx)
	if r != nil {
		return *r
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
		var names []string
		for _, c := range existing {
			names = append(names, containerLabel(c))
		}
		return protocol.ErrorResult(ClassContainerExists, fmt.Sprintf(
			"environment %s already has a container (%s): run container.stop or env.scrub first", e.Key, strings.Join(names, ", ")))
	}

	// The volumes are created with the environment's label, so that reset finds
	// them by label as well as by name. Creating a volume that exists returns it
	// unchanged, so one with the name but not the label is not the environment's:
	// it is refused and left alone (PROTOCOL.md §6.2).
	for _, v := range volumes {
		res, err := e.API.VolumeCreate(ctx, client.VolumeCreateOptions{Name: v, Labels: map[string]string{LabelEnvironment: e.Key}})
		if err != nil {
			return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("creating the volume %s failed: %v", v, err))
		}
		if got := res.Volume.Labels[LabelEnvironment]; got != e.Key {
			return protocol.ErrorResult(ClassVolumeNotOwned, fmt.Sprintf(
				"the volume %s exists without the label %s=%s (it has %q), so it is not this environment's; it was not mounted or changed",
				v, LabelEnvironment, e.Key, got))
		}
	}

	created, err := e.API.ContainerCreate(ctx, client.ContainerCreateOptions{Name: name, Config: config, HostConfig: host})
	switch {
	case err == nil:
	case cerrdefs.IsNotFound(err):
		return protocol.ErrorResult(ClassImageNotFound, fmt.Sprintf("the daemon does not have %s: run image.ensure first (%v)", config.Image, err))
	case cerrdefs.IsConflict(err):
		return protocol.ErrorResult(ClassContainerExists, fmt.Sprintf("creating %s failed: %v", name, err))
	default:
		return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("creating %s failed: %v", name, err))
	}
	if _, err := e.API.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		// A container that never started is not left behind.
		_, _ = e.API.ContainerRemove(context.WithoutCancel(ctx), created.ID, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
		return protocol.ErrorResult(ClassContainerStartFailed, fmt.Sprintf("starting %s failed: %v", name, err))
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"container_id": created.ID, "name": name}}
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
// anonymous volumes. The named volumes stay. A container that is already gone is
// not an error. The name alone does not prove the container is the session's: one
// without the environment's and the session's labels is refused and not touched.
func (e *Environment) ContainerStop(ctx context.Context, raw json.RawMessage) protocol.Result {
	sessionID, r := opSession(ctx)
	if r != nil {
		return *r
	}
	var p ContainerStopPayload
	if r := decodePayload(raw, &p, "{}"); r != nil {
		return *r
	}
	name := e.ContainerName(sessionID)
	inspected, err := e.API.ContainerInspect(ctx, name, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"removed": false}}
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
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"removed": removed}}
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
