package docker

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

const envKey = "aixle-r7-1f2e3d4c"

type harness struct {
	t      *testing.T
	engine *fakeEngine
	env    *Environment
	state  string
}

func newEnvironment(t *testing.T) *harness {
	t.Helper()
	f, c := newFakeEngine(t)
	f.images[image+"@"+digest] = true
	state := filepath.Join(t.TempDir(), "aixle-runner")
	if err := os.MkdirAll(state, 0o700); err != nil {
		t.Fatal(err)
	}
	return &harness{t: t, engine: f, state: state, env: &Environment{API: c, Key: envKey, StateDir: state, Now: steppingClock()}}
}

// another is a second environment on the same daemon.
func (h *harness) another(key string) *Environment {
	return &Environment{API: h.env.API, Key: key, StateDir: h.state}
}

// sessionID is the session of the ops a test runs, unless it names another.
const sessionID = int64(123)

func startPayload(extra map[string]any) map[string]any {
	p := map[string]any{"image": image, "digest": digest}
	for k, v := range extra {
		p[k] = v
	}
	return p
}

// sessionCtx is the context of an op whose envelope names the session id.
func sessionCtx(id int64) context.Context {
	return protocol.WithOpSession(context.Background(), &id)
}

func (h *harness) run(handler Handler, payload any) protocol.Result {
	h.t.Helper()
	return h.runAs(sessionID, handler, payload)
}

// runAs runs an op whose envelope names the session id.
func (h *harness) runAs(id int64, handler Handler, payload any) protocol.Result {
	h.t.Helper()
	return handler(sessionCtx(id), mustJSON(h.t, payload))
}

func (h *harness) start(env *Environment, extra map[string]any) protocol.Result {
	h.t.Helper()
	r := env.ContainerStart(sessionCtx(sessionID), mustJSON(h.t, startPayload(extra)))
	if r.Status != protocol.StatusOK {
		h.t.Fatalf("container.start: %#v %v", r, r.Error)
	}
	return r
}

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	return payload(t, v)
}

func (h *harness) only() *fakeContainer {
	h.t.Helper()
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	if len(h.engine.containers) != 1 {
		h.t.Fatalf("%d containers", len(h.engine.containers))
	}
	for _, c := range h.engine.containers {
		return c
	}
	return nil
}

func TestContainerStartRunsTheImageAsAHostedPodDoes(t *testing.T) {
	h := newEnvironment(t)
	r := h.start(h.env, map[string]any{"env": map[string]string{"TTYD_CMD": "claude", "ROUTE_TOKEN": "rt"}})
	c := h.only()

	if c.Name != "aixle-"+envKey+"-123" || r.Data["name"] != c.Name || r.Data["container_id"] != c.ID {
		t.Fatalf("name %q, result %#v", c.Name, r.Data)
	}
	if want := map[string]string{LabelEnvironment: envKey, LabelSession: "123"}; !reflect.DeepEqual(c.Config.Labels, want) {
		t.Fatalf("labels %v", c.Config.Labels)
	}
	if c.Config.Image != image+"@"+digest {
		t.Fatalf("image %q", c.Config.Image)
	}
	// The image's own entrypoint and command, unchanged.
	if c.Config.Entrypoint != nil || c.Config.Cmd != nil || c.Config.User != "" || c.Config.WorkingDir != "" {
		t.Fatalf("entrypoint %v, cmd %v, user %q, workdir %q", c.Config.Entrypoint, c.Config.Cmd, c.Config.User, c.Config.WorkingDir)
	}
	if want := []string{"ROUTE_TOKEN=rt", "TTYD_CMD=claude"}; !reflect.DeepEqual(c.Config.Env, want) {
		t.Fatalf("env %v", c.Config.Env)
	}
	if !c.State.Running {
		t.Fatal("the container was not started")
	}
	host := c.Host
	if host.NetworkMode != "bridge" || host.PidMode != "" || host.RestartPolicy.Name != "no" || host.AutoRemove {
		t.Fatalf("network %q, pid %q, restart %q, autoremove %v", host.NetworkMode, host.PidMode, host.RestartPolicy.Name, host.AutoRemove)
	}
	if !reflect.DeepEqual(host.CapDrop, []string{"CAP_NET_RAW"}) || !reflect.DeepEqual(host.SecurityOpt, []string{"no-new-privileges"}) {
		t.Fatalf("capdrop %v, securityopt %v", host.CapDrop, host.SecurityOpt)
	}
	// The workspace volume at /workspace, and nothing of the runner: no binary, no
	// socket, nothing of the state directory.
	if want := []mount.Mount{{Type: mount.TypeVolume, Source: "aixle-ws-" + envKey, Target: "/workspace"}}; !reflect.DeepEqual(host.Mounts, want) {
		t.Fatalf("mounts %#v", host.Mounts)
	}
	if len(host.Binds) != 0 || len(host.VolumesFrom) != 0 || host.Privileged {
		t.Fatalf("binds %v, volumes-from %v, privileged %v", host.Binds, host.VolumesFrom, host.Privileged)
	}
	if v := h.engine.volumes["aixle-ws-"+envKey]; v == nil || v.Labels[LabelEnvironment] != envKey {
		t.Fatalf("workspace volume %#v", v)
	}
}

func TestContainerStartAppliesMountsNetworkPidAndResources(t *testing.T) {
	h := newEnvironment(t)
	toolchain := t.TempDir()
	cache := t.TempDir()
	h.start(h.env, map[string]any{
		"workspace_volume": true,
		"mounts": []map[string]any{
			{"type": "cache", "name": "pip", "target": "/home/agent/.cache/pip"},
			{"type": "bind", "source": toolchain, "target": "/opt/toolchains"},
			{"type": "bind", "source": cache, "target": "/home/agent/.npm", "writable": true},
		},
		"network":              "host",
		"pid":                  "host",
		"resources":            map[string]any{"cpus": 1.5, "memory_bytes": 4 << 30, "pids_limit": 512},
		"privilege_escalation": true,
	})
	host := h.only().Host
	want := []mount.Mount{
		{Type: mount.TypeVolume, Source: "aixle-ws-" + envKey, Target: "/workspace"},
		{Type: mount.TypeVolume, Source: "aixle-cache-" + envKey + "-pip", Target: "/home/agent/.cache/pip"},
		{Type: mount.TypeBind, Source: toolchain, Target: "/opt/toolchains", ReadOnly: true},
		{Type: mount.TypeBind, Source: cache, Target: "/home/agent/.npm"},
	}
	if !reflect.DeepEqual(host.Mounts, want) {
		t.Fatalf("mounts %#v", host.Mounts)
	}
	if host.NetworkMode != "host" || host.PidMode != "host" {
		t.Fatalf("network %q, pid %q", host.NetworkMode, host.PidMode)
	}
	if host.NanoCPUs != 1_500_000_000 || host.Memory != 4<<30 || host.MemorySwap != 4<<30 || host.PidsLimit == nil || *host.PidsLimit != 512 {
		t.Fatalf("resources %#v", host.Resources)
	}
	if len(host.SecurityOpt) != 0 {
		t.Fatalf("securityopt %v with privilege escalation", host.SecurityOpt)
	}
	if v := h.engine.volumes["aixle-cache-"+envKey+"-pip"]; v == nil || v.Labels[LabelEnvironment] != envKey {
		t.Fatalf("cache volume %#v", v)
	}
}

func TestContainerStartWithoutTheWorkspaceVolume(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, map[string]any{"workspace_volume": false})
	if mounts := h.only().Host.Mounts; len(mounts) != 0 {
		t.Fatalf("mounts %#v", mounts)
	}
}

func TestContainerStartRefusesABindThatExposesTheStateDirectory(t *testing.T) {
	h := newEnvironment(t)
	link := filepath.Join(t.TempDir(), "innocent")
	if err := os.Symlink(h.state, link); err != nil {
		t.Fatal(err)
	}
	inside := filepath.Join(h.state, "sub")
	_ = os.MkdirAll(inside, 0o700)
	for _, source := range []string{h.state, filepath.Dir(h.state), inside, link, "/"} {
		r := h.run(h.env.ContainerStart, startPayload(map[string]any{
			"mounts": []map[string]any{{"type": "bind", "source": source, "target": "/mnt/x"}},
		}))
		if r.Status != protocol.StatusError || r.Error.Class != ClassForbiddenMount {
			t.Errorf("%s: %#v", source, r)
		}
	}
	if len(h.engine.containers) != 0 {
		t.Fatal("a container was created")
	}
}

func TestContainerStartRefusesInvalidPayloads(t *testing.T) {
	h := newEnvironment(t)
	for _, extra := range []map[string]any{
		{"digest": "latest"},
		{"env": map[string]string{"A=B": "c"}},
		{"network": "none"},
		{"pid": "container:x"},
		{"mounts": []map[string]any{{"type": "tmpfs", "target": "/x"}}},
		{"mounts": []map[string]any{{"type": "cache", "name": "../x", "target": "/x"}}},
		{"mounts": []map[string]any{{"type": "cache", "name": "pip", "target": "relative"}}},
		{"mounts": []map[string]any{{"type": "bind", "source": "relative", "target": "/x"}}},
		{"resources": map[string]any{"memory_bytes": -1}},
	} {
		r := h.run(h.env.ContainerStart, startPayload(extra))
		if r.Status != protocol.StatusError || r.Error.Class != ClassInvalidPayload {
			t.Errorf("%v: %#v", extra, r)
		}
	}
	if len(h.engine.creates) != 0 {
		t.Fatal("an invalid payload reached the daemon")
	}
}

func TestContainerStartRefusesASecondContainer(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	r := h.runAs(124, h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerExists || !strings.Contains(r.Error.Message, "aixle-"+envKey+"-123") {
		t.Fatalf("%#v", r)
	}
	// Another environment on the same machine is not affected.
	h.start(h.another("aixle-r7-99999999"), nil)
}

func TestContainerStartWithoutTheImage(t *testing.T) {
	h := newEnvironment(t)
	h.engine.images = map[string]bool{}
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassImageNotFound {
		t.Fatalf("%#v", r)
	}
}

func TestAContainerThatCannotStartIsRemoved(t *testing.T) {
	h := newEnvironment(t)
	h.engine.startError = "OCI runtime create failed"
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, "OCI runtime") {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.containers) != 0 {
		t.Fatal("the container was left behind")
	}
}

func TestContainerStopStopsAndRemovesTheContainer(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	r := h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusOK || r.Data["removed"] != true {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.containers) != 0 || h.engine.volumes["aixle-ws-"+envKey] == nil {
		t.Fatalf("containers %v, volumes %v", h.engine.containers, h.engine.volumes)
	}
	// A container already gone is not an error.
	r = h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusOK || r.Data["removed"] != false {
		t.Fatalf("%#v", r)
	}
}

func TestContainerStopLeavesOtherSessionsAlone(t *testing.T) {
	h := newEnvironment(t)
	other := h.another("aixle-r7-99999999")
	h.start(other, nil)
	r := h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusOK || r.Data["removed"] != false || len(h.engine.containers) != 1 {
		t.Fatalf("%#v, %d containers", r, len(h.engine.containers))
	}
}

func TestTheReservedSessionOpsHaveNoHandler(t *testing.T) {
	h := newEnvironment(t)
	handlers := h.env.Handlers()
	var names []string
	for name := range handlers {
		names = append(names, name)
	}
	want := []string{"batch", "container.start", "container.stop", "env.reset", "env.scrub", "exec", "image.ensure", "logs", "read_file", "status", "write_file"}
	sort.Strings(names)
	if !reflect.DeepEqual(names, want) {
		t.Fatalf("handlers %v", names)
	}
}

func TestContainerStartRefusesAVolumeThatIsNotTheEnvironments(t *testing.T) {
	for _, labels := range []map[string]string{{}, {LabelEnvironment: otherKey}} {
		h := newEnvironment(t)
		name := "aixle-cache-" + envKey + "-pip"
		h.engine.mu.Lock()
		h.engine.volumes[name] = &fakeVolume{Name: name, Labels: labels, Files: map[string][]byte{"data": []byte("theirs")}}
		h.engine.mu.Unlock()
		r := h.run(h.env.ContainerStart, startPayload(map[string]any{
			"mounts": []map[string]any{{"type": "cache", "name": "pip", "target": "/root/.cache/pip"}},
		}))
		if r.Status != protocol.StatusError || r.Error.Class != ClassVolumeNotOwned || !strings.Contains(r.Error.Message, name) {
			t.Fatalf("%v: %#v", labels, r)
		}
		h.engine.mu.Lock()
		creates, v := len(h.engine.creates), h.engine.volumes[name]
		h.engine.mu.Unlock()
		if creates != 0 {
			t.Fatalf("%v: a container was created", labels)
		}
		if !reflect.DeepEqual(v.Labels, labels) || string(v.Files["data"]) != "theirs" {
			t.Fatalf("%v: the volume was changed: %#v", labels, v)
		}
	}
}

func TestContainerStopRefusesAContainerWithTheNameButNotTheLabels(t *testing.T) {
	name := "aixle-" + envKey + "-123"
	for _, labels := range []map[string]string{
		nil,
		{LabelEnvironment: envKey},
		{LabelEnvironment: otherKey, LabelSession: "123"},
		{LabelEnvironment: envKey, LabelSession: "124"},
	} {
		h := newEnvironment(t)
		h.engine.mu.Lock()
		c := &fakeContainer{ID: h.engine.nextID(), Name: name, Config: container.Config{Labels: labels},
			State: container.State{Status: container.StateRunning, Running: true}, Files: map[string]*fakeFile{}, exited: make(chan struct{})}
		h.engine.containers[c.ID] = c
		h.engine.mu.Unlock()
		r := h.run(h.env.ContainerStop, map[string]any{})
		if r.Status != protocol.StatusError || r.Error.Class != ClassContainerNotOwned || !strings.Contains(r.Error.Message, name) {
			t.Fatalf("%v: %#v", labels, r)
		}
		if after := h.only(); after.ID != c.ID || !after.State.Running {
			t.Fatalf("%v: the container was stopped or removed", labels)
		}
	}
}

func TestContainerStartNamesAndLabelsTheContainerFromTheEnvelope(t *testing.T) {
	h := newEnvironment(t)
	// A session_id left in the payload is an unknown field, and ignored.
	r := h.runAs(456, h.env.ContainerStart, startPayload(map[string]any{"session_id": 999}))
	if r.Status != protocol.StatusOK {
		t.Fatalf("%#v", r)
	}
	c := h.only()
	if c.Name != "aixle-"+envKey+"-456" || c.Config.Labels[LabelSession] != "456" || c.Config.Labels[LabelEnvironment] != envKey {
		t.Fatalf("name %q, labels %v", c.Name, c.Config.Labels)
	}
	if r := h.runAs(456, h.env.Status, map[string]any{}); r.Status != protocol.StatusOK || r.Data["state"] != StateRunning {
		t.Fatalf("%#v", r)
	}
}
