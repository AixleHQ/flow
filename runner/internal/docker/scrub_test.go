package docker

import (
	"reflect"
	"sort"
	"strings"
	"testing"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

const otherKey = "aixle-r7-1f2e3d4c0"

// twoEnvironments starts a session container on this environment and on another
// one whose key has this one's as a prefix, with a workspace and a cache volume
// each.
func twoEnvironments(t *testing.T) (*harness, *Environment) {
	h := newEnvironment(t)
	other := h.another(otherKey)
	cache := map[string]any{"mounts": []map[string]any{{"type": "cache", "name": "pip", "target": "/root/.cache/pip"}}}
	h.start(h.env, cache)
	h.start(other, cache)
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	for _, name := range []string{"aixle-ws-" + envKey, "aixle-ws-" + otherKey} {
		h.engine.volumes[name].Files["repo/README.md"] = []byte("checkout")
		h.engine.volumes[name].Files["outputs/report.md"] = []byte("report")
	}
	return h, other
}

func (h *harness) containerNames() []string {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	var names []string
	for _, c := range h.engine.containers {
		names = append(names, c.Name)
	}
	return names
}

func (h *harness) volumeFiles(name string) map[string][]byte {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	if v, ok := h.engine.volumes[name]; ok {
		return v.Files
	}
	return nil
}

func scrubPayload() map[string]any { return map[string]any{"image": pinned} }

func TestScrubRemovesTheSessionContainersAndEmptiesTheOutputs(t *testing.T) {
	h, _ := twoEnvironments(t)
	r := h.runEnv(h.env.Scrub, scrubPayload())
	if r.Status != protocol.StatusOK || r.Data["outputs_emptied"] != true {
		t.Fatalf("%#v %v", r, r.Error)
	}
	if want := []string{"aixle-" + envKey + "-123"}; !reflect.DeepEqual(r.Data["removed_containers"], want) {
		t.Fatalf("removed %v", r.Data["removed_containers"])
	}
	if names := h.containerNames(); !reflect.DeepEqual(names, []string{"aixle-" + otherKey + "-123"}) {
		t.Fatalf("containers left %v", names)
	}
	if files := h.volumeFiles("aixle-ws-" + envKey); !reflect.DeepEqual(files, map[string][]byte{"repo/README.md": []byte("checkout")}) {
		t.Fatalf("workspace %v", files)
	}
	// The checkout, the cache volume and the image stay; the other environment is
	// not touched.
	if h.volumeFiles("aixle-cache-"+envKey+"-pip") == nil || !h.engine.images[pinned] {
		t.Fatal("the scrub removed a cache volume or the image")
	}
	if files := h.volumeFiles("aixle-ws-" + otherKey); len(files) != 2 {
		t.Fatalf("the other environment's workspace %v", files)
	}
	// The container that emptied the outputs ran the agent image as root, with no
	// network and only the workspace volume, and is gone.
	var scrub *fakeContainerRequest
	for _, c := range h.engine.creates {
		if c.Config.Labels[LabelRole] == "scrub" {
			scrub = &fakeContainerRequest{c.Config.Image, c.Config.User, string(c.HostConfig.NetworkMode), len(c.HostConfig.Mounts), c.Config.Labels[LabelEnvironment]}
		}
	}
	if scrub == nil || *scrub != (fakeContainerRequest{pinned, "0:0", "none", 1, envKey}) {
		t.Fatalf("scrub container %#v", scrub)
	}
}

type fakeContainerRequest struct {
	Image, User, Network string
	Mounts               int
	Environment          string
}

func TestScrubWithoutAWorkspaceVolume(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, map[string]any{"workspace_volume": false})
	r := h.runEnv(h.env.Scrub, scrubPayload())
	if r.Status != protocol.StatusOK || r.Data["outputs_emptied"] != false || len(h.containerNames()) != 0 {
		t.Fatalf("%#v", r)
	}
}

func TestAFailedScrubSaysSo(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	h.engine.scrubExit = 1
	r := h.runEnv(h.env.Scrub, scrubPayload())
	if r.Status != protocol.StatusError || r.Error.Class != ClassScrubFailed {
		t.Fatalf("%#v", r)
	}
	if len(h.containerNames()) != 0 {
		t.Fatal("the scrub container was left behind")
	}
	if r := h.runEnv(h.env.Scrub, map[string]any{}); r.Error == nil || r.Error.Class != ClassInvalidPayload {
		t.Fatalf("%#v", r)
	}
}

func TestResetAlsoRemovesTheEnvironmentsVolumes(t *testing.T) {
	h, _ := twoEnvironments(t)
	r := h.runEnv(h.env.Reset, map[string]any{})
	if r.Status != protocol.StatusOK {
		t.Fatalf("%#v %v", r, r.Error)
	}
	if want := []string{"aixle-cache-" + envKey + "-pip", "aixle-ws-" + envKey}; !reflect.DeepEqual(r.Data["removed_volumes"], want) {
		t.Fatalf("removed %v", r.Data["removed_volumes"])
	}
	if want := []string{"aixle-" + envKey + "-123"}; !reflect.DeepEqual(r.Data["removed_containers"], want) {
		t.Fatalf("removed %v", r.Data["removed_containers"])
	}
	h.engine.mu.Lock()
	var volumes []string
	for name := range h.engine.volumes {
		volumes = append(volumes, name)
	}
	h.engine.mu.Unlock()
	want := map[string]bool{"aixle-ws-" + otherKey: true, "aixle-cache-" + otherKey + "-pip": true}
	if len(volumes) != len(want) {
		t.Fatalf("volumes left %v", volumes)
	}
	for _, v := range volumes {
		if !want[v] {
			t.Fatalf("volumes left %v", volumes)
		}
	}
	if !reflect.DeepEqual(h.containerNames(), []string{"aixle-" + otherKey + "-123"}) || !h.engine.images[pinned] {
		t.Fatal("the reset touched another environment or the image")
	}
	// A reset of an environment with nothing left is not an error.
	if r := h.runEnv(h.env.Reset, map[string]any{}); r.Status != protocol.StatusOK {
		t.Fatalf("%#v", r)
	}
}

func TestAVolumeInUseFailsTheReset(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	// A container that is not the environment's mounts its workspace volume.
	h.engine.mu.Lock()
	h.engine.containers["intruder"] = &fakeContainer{ID: "intruder", Name: "intruder", Files: map[string]*fakeFile{}, exited: make(chan struct{})}
	h.engine.containers["intruder"].Host.Mounts = h.only2("aixle-" + envKey + "-123").Host.Mounts
	h.engine.mu.Unlock()
	r := h.runEnv(h.env.Reset, map[string]any{})
	if r.Status != protocol.StatusError || r.Error.Class != ClassResetFailed {
		t.Fatalf("%#v", r)
	}
}

// only2 finds a container by name. The caller holds the lock.
func (h *harness) only2(name string) *fakeContainer {
	for _, c := range h.engine.containers {
		if c.Name == name {
			return c
		}
	}
	h.t.Fatalf("no container %s", name)
	return nil
}

// addVolume adds a volume that nothing of this environment created.
func (h *harness) addVolume(name string, labels map[string]string) {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	h.engine.volumes[name] = &fakeVolume{Name: name, Labels: labels, Files: map[string][]byte{"outputs/theirs.md": []byte("theirs")}}
}

func (h *harness) volumeNames() []string {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	var names []string
	for name := range h.engine.volumes {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

func TestScrubRefusesAWorkspaceVolumeThatIsNotTheEnvironments(t *testing.T) {
	for _, labels := range []map[string]string{{}, {LabelEnvironment: otherKey}} {
		h := newEnvironment(t)
		h.addVolume("aixle-ws-"+envKey, labels)
		r := h.runEnv(h.env.Scrub, scrubPayload())
		if r.Status != protocol.StatusError || r.Error.Class != ClassScrubFailed || !strings.Contains(r.Error.Message, "aixle-ws-"+envKey) {
			t.Fatalf("%v: %#v", labels, r)
		}
		if files := h.volumeFiles("aixle-ws-" + envKey); string(files["outputs/theirs.md"]) != "theirs" {
			t.Fatalf("%v: the volume was emptied: %v", labels, files)
		}
		h.engine.mu.Lock()
		creates := len(h.engine.creates)
		h.engine.mu.Unlock()
		if creates != 0 {
			t.Fatalf("%v: a container mounted the volume", labels)
		}
	}
}

func TestResetRefusesAVolumeThatIsNotTheEnvironments(t *testing.T) {
	for _, foreign := range []struct {
		name   string
		labels map[string]string
	}{
		{"aixle-ws-" + envKey, map[string]string{}},
		{"aixle-ws-" + envKey, map[string]string{LabelEnvironment: otherKey}},
		{"aixle-cache-" + envKey + "-foreign", map[string]string{}},
		{"aixle-cache-" + envKey + "-foreign", map[string]string{LabelEnvironment: otherKey}},
	} {
		h := newEnvironment(t)
		h.start(h.env, map[string]any{"workspace_volume": false, "mounts": []map[string]any{{"type": "cache", "name": "pip", "target": "/root/.cache/pip"}}})
		h.addVolume(foreign.name, foreign.labels)
		r := h.runEnv(h.env.Reset, map[string]any{})
		if r.Status != protocol.StatusError || r.Error.Class != ClassResetFailed || !strings.Contains(r.Error.Message, foreign.name) {
			t.Fatalf("%s %v: %#v", foreign.name, foreign.labels, r)
		}
		// No volume is removed, the environment's own included.
		names, want := h.volumeNames(), []string{"aixle-cache-" + envKey + "-pip", foreign.name}
		sort.Strings(want)
		if !reflect.DeepEqual(names, want) {
			t.Fatalf("%s %v: volumes %v", foreign.name, foreign.labels, names)
		}
	}
}

func TestResetLeavesTheCacheVolumesOfAKeyThatStartsWithThisOne(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	longer := h.another(envKey + "-x")
	h.start(longer, map[string]any{"mounts": []map[string]any{{"type": "cache", "name": "pip", "target": "/root/.cache/pip"}}})
	r := h.runEnv(h.env.Reset, map[string]any{})
	if r.Status != protocol.StatusOK || !reflect.DeepEqual(r.Data["removed_volumes"], []string{"aixle-ws-" + envKey}) {
		t.Fatalf("%#v %v", r, r.Error)
	}
	if names, want := h.volumeNames(), []string{"aixle-cache-" + envKey + "-x-pip", "aixle-ws-" + envKey + "-x"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("volumes %v", names)
	}
}
