package docker

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

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
	f.images[pinned] = true
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

// testProxyPort is the `proxy_port` the platform sends by default: the
// sidecar's port (PROTOCOL.md §6.2).
const testProxyPort = 7690

func startPayload(extra map[string]any) map[string]any {
	p := map[string]any{"image": pinned, "proxy_port": testProxyPort}
	for k, v := range extra {
		p[k] = v
	}
	return p
}

func (h *harness) run(handler SessionHandler, payload any) protocol.Result {
	h.t.Helper()
	return h.runAs(sessionID, handler, payload)
}

// runAs runs a session op whose envelope names the session id.
func (h *harness) runAs(id int64, handler SessionHandler, payload any) protocol.Result {
	h.t.Helper()
	return handler(context.Background(), id, mustJSON(h.t, payload))
}

// runEnvelope runs a handler as the loop does, with the envelope's session id.
func (h *harness) runEnvelope(id int64, handler Handler, payload any) protocol.Result {
	h.t.Helper()
	return handler(context.Background(), &id, mustJSON(h.t, payload))
}

// runEnv runs an environment op.
func (h *harness) runEnv(handler EnvironmentHandler, payload any) protocol.Result {
	h.t.Helper()
	return handler(context.Background(), mustJSON(h.t, payload))
}

func (h *harness) start(env *Environment, extra map[string]any) protocol.Result {
	h.t.Helper()
	r := env.ContainerStart(context.Background(), sessionID, mustJSON(h.t, startPayload(extra)))
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
	if c.Config.Image != pinned {
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
		"proxy_port":           20123,
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
		{"image": "Not A Repo"},
		{"image": ""},
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

func TestContainerStartRefusesAnotherSessionsContainer(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	r := h.runAs(124, h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassSessionMismatch || !strings.Contains(r.Error.Message, "aixle-"+envKey+"-123") {
		t.Fatalf("%#v", r)
	}
	if c := h.only(); !c.State.Running || c.Config.Labels[LabelSession] != "123" {
		t.Fatal("the other session's container was touched")
	}
	// Another environment on the same machine is not affected.
	h.start(h.another("aixle-r7-99999999"), nil)
}

func TestContainerStartOverItsOwnContainerOrALeftoverIsContainerExists(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	// A create retried after an answer that never arrived finds its own container.
	if r := h.run(h.env.ContainerStart, startPayload(nil)); r.Status != protocol.StatusError || r.Error.Class != ClassContainerExists {
		t.Fatalf("its own container: %#v", r)
	}

	h = newEnvironment(t)
	h.engine.mu.Lock()
	leftover := &fakeContainer{ID: h.engine.nextID(), Name: "aixle-" + envKey + "-leftover", Config: container.Config{Labels: map[string]string{LabelEnvironment: envKey}},
		State: container.State{Status: container.StateExited}, Files: map[string]*fakeFile{}, exited: make(chan struct{})}
	h.engine.containers[leftover.ID] = leftover
	h.engine.mu.Unlock()
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerExists || !strings.Contains(r.Error.Message, leftover.Name) {
		t.Fatalf("a leftover without a session: %#v", r)
	}
}

func TestContainerStartAlwaysPullsTheImageThenCreatesTheContainer(t *testing.T) {
	for _, ref := range []string{pinned, tagged} {
		h := newEnvironment(t)
		h.engine.images = map[string]bool{}
		h.start(h.env, map[string]any{"image": ref})
		if len(h.engine.pulls) != 1 || h.engine.pulls[0] != ref || h.only().Config.Image != ref {
			t.Fatalf("%s: pulls %v", ref, h.engine.pulls)
		}
	}
	// An image the daemon already has is pulled again, so a tag that moved is followed.
	h := newEnvironment(t)
	h.start(h.env, nil)
	if len(h.engine.pulls) != 1 || h.engine.pulls[0] != pinned {
		t.Fatalf("pulls %v: every container.start pulls", h.engine.pulls)
	}
}

// The agent images are linux/amd64 only, so a daemon on arm64 pulls and runs
// them for that platform (under emulation) instead of failing on the manifest.
func TestTheAgentImageIsPulledAndTheContainerCreatedForLinuxAmd64(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	if len(h.engine.pullPlatforms) != 1 || h.engine.pullPlatforms[0] != "linux/amd64" {
		t.Fatalf("pull platforms %q", h.engine.pullPlatforms)
	}
	if len(h.engine.createPlatforms) == 0 {
		t.Fatal("nothing was created")
	}
	for _, p := range h.engine.createPlatforms {
		if p != "linux/amd64" {
			t.Fatalf("create platforms %q: every container made from the agent image is for linux/amd64", h.engine.createPlatforms)
		}
	}
}

func TestThePullSendsTheDockerCredentialsOfTheImagesRegistry(t *testing.T) {
	h := newEnvironment(t)
	login := base64.StdEncoding.EncodeToString([]byte("agent-bot:s3cret"))
	withDockerConfig(t, `{"auths": {"ghcr.io": {"auth": "`+login+`"}, "registry.internal": {"auth": "b3RoZXI6b3RoZXI="}}}`)
	h.start(h.env, map[string]any{"image": tagged})
	if len(h.engine.pullAuths) != 1 || h.engine.pullAuths[0] == "" {
		t.Fatalf("pull auths %q: the pull carried no credentials", h.engine.pullAuths)
	}
	decoded, err := base64.URLEncoding.DecodeString(h.engine.pullAuths[0])
	if err != nil {
		t.Fatal(err)
	}
	var sent map[string]string
	if err := json.Unmarshal(decoded, &sent); err != nil {
		t.Fatal(err)
	}
	if sent["username"] != "agent-bot" || sent["password"] != "s3cret" || sent["serveraddress"] != "ghcr.io" {
		t.Fatalf("sent %v: not ghcr.io's credentials", sent)
	}
}

// `docker login` stores Docker Hub's credentials under https://index.docker.io/v1/,
// not under the reference's domain, docker.io.
func TestAPullOfADockerHubImageSendsTheCredentialsDockerLoginStored(t *testing.T) {
	login := base64.StdEncoding.EncodeToString([]byte("hub-bot:hub-s3cret"))
	for _, ref := range []string{"myorg/agent:1", "docker.io/myorg/agent:1", "index.docker.io/myorg/agent:1"} {
		h := newEnvironment(t)
		withDockerConfig(t, `{"auths": {"https://index.docker.io/v1/": {"auth": "`+login+`"}, "ghcr.io": {"auth": "b3RoZXI6b3RoZXI="}}}`)
		h.run(h.env.ContainerStart, startPayload(map[string]any{"image": ref}))
		if len(h.engine.pullAuths) != 1 || h.engine.pullAuths[0] == "" {
			t.Fatalf("%s: pull auths %q: the pull carried no credentials", ref, h.engine.pullAuths)
		}
		decoded, err := base64.URLEncoding.DecodeString(h.engine.pullAuths[0])
		if err != nil {
			t.Fatal(err)
		}
		var sent map[string]string
		if err := json.Unmarshal(decoded, &sent); err != nil {
			t.Fatal(err)
		}
		if sent["username"] != "hub-bot" || sent["password"] != "hub-s3cret" {
			t.Fatalf("%s: sent %v: not Docker Hub's credentials", ref, sent)
		}
	}
}

func TestAPullWithNoCredentialsForItsRegistryIsAnonymous(t *testing.T) {
	h := newEnvironment(t)
	withDockerConfig(t, `{"auths": {"registry.internal": {"auth": "b3RoZXI6b3RoZXI="}}}`)
	h.start(h.env, map[string]any{"image": tagged})
	if len(h.engine.pullAuths) != 1 || h.engine.pullAuths[0] != "" {
		t.Fatalf("pull auths %q: another registry's credentials were sent", h.engine.pullAuths)
	}
}

func TestContainerStartCreatesNothingPastItsDeadline(t *testing.T) {
	h := newEnvironment(t)
	h.engine.pullDelay = 10 * time.Second
	ctx := protocol.WithOpDeadline(context.Background(), time.Now().Add(200*time.Millisecond))
	started := time.Now()
	r := h.env.ContainerStart(ctx, sessionID, mustJSON(t, startPayload(map[string]any{"image": tagged})))
	if elapsed := time.Since(started); elapsed > 5*time.Second {
		t.Fatalf("container.start ran %s, past its deadline", elapsed)
	}
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, "deadline_at") {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.containers) != 0 || len(h.engine.creates) != 0 || len(h.engine.volumes) != 0 {
		t.Fatalf("something was created past the deadline: %d containers, %d creates, %d volumes",
			len(h.engine.containers), len(h.engine.creates), len(h.engine.volumes))
	}
}

// A runner that stops (SIGTERM, a restart) while ContainerCreate runs cancels the
// op's context; that is not its deadline.
func TestContainerStartCutShortByTheRunnerStoppingDuringTheCreateLeavesNothing(t *testing.T) {
	h := newEnvironment(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h.engine.onCreate = cancel
	r := h.env.ContainerStart(ctx, sessionID, mustJSON(t, startPayload(nil)))
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, "cut short") {
		t.Fatalf("%#v", r)
	}
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	if len(h.engine.creates) != 1 {
		t.Fatalf("%d creates: the create never ran", len(h.engine.creates))
	}
	if len(h.engine.containers) != 0 {
		t.Fatalf("%d containers left after the cut-short create", len(h.engine.containers))
	}
}

// A daemon that stalls in the removal after a cut-short create holds the op for
// the removal's own timeout at most, not for ever: the serial ops loop goes on.
func TestARemovalThatBlocksAfterACutShortCreateReturnsWithinItsTimeout(t *testing.T) {
	h := newEnvironment(t)
	logs := captureLogs(h.env)
	h.env.RemoveTimeout = 200 * time.Millisecond
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	h.engine.onCreate = func() {
		h.engine.mu.Lock()
		h.engine.removeBlocks = true
		h.engine.mu.Unlock()
		cancel()
	}
	started := time.Now()
	r := h.env.ContainerStart(ctx, sessionID, mustJSON(t, startPayload(nil)))
	if elapsed := time.Since(started); elapsed > 5*time.Second {
		t.Fatalf("container.start ran %s: the removal was not bounded", elapsed)
	}
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, "env.reset removes it") {
		t.Fatalf("%#v", r)
	}
	if !strings.Contains(logs.String(), "removing the container of a failed container.start failed") {
		t.Fatalf("the failed removal was not logged: %q", logs.String())
	}
}

// A removal the daemon refuses after a failed start is logged, and the answer
// stays container_start_failed: the cleanup's env.reset removes what is left.
func TestARemovalThatErrorsAfterAFailedStartIsLogged(t *testing.T) {
	h := newEnvironment(t)
	logs := captureLogs(h.env)
	h.engine.startError = "OCI runtime create failed"
	h.engine.removeError = "driver failed to remove the root filesystem"
	r := h.run(h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassContainerStartFailed || !strings.Contains(r.Error.Message, "OCI runtime") {
		t.Fatalf("%#v", r)
	}
	if !strings.Contains(r.Error.Message, "driver failed to remove") {
		t.Fatalf("the answer does not say the removal failed: %s", r.Error.Message)
	}
	out := logs.String()
	if !strings.Contains(out, "removing the container of a failed container.start failed") || !strings.Contains(out, "driver failed to remove") {
		t.Fatalf("the failed removal was not logged: %q", out)
	}
}

// captureLogs sends the environment's log to a buffer the test reads.
func captureLogs(env *Environment) *syncBuffer {
	b := &syncBuffer{}
	env.Logger = slog.New(slog.NewTextHandler(b, nil))
	return b
}

// syncBuffer is a bytes.Buffer that the handler may write while the test reads.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func TestContainerStartPullsAReferenceWithoutATagAsLatest(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, map[string]any{"image": image})
	if len(h.engine.pulls) != 1 || h.engine.pulls[0] != image+":latest" || h.only().Config.Image != image+":latest" {
		t.Fatalf("pulls %v", h.engine.pulls)
	}
}

func TestAFailedPullIsAnOutcomeOfContainerStartAndCreatesNothing(t *testing.T) {
	for name, fail := range map[string]func(f *fakeEngine){
		// The registry's words arrive in the progress stream, even with an older copy there.
		"in the stream": func(f *fakeEngine) { f.pullError = "manifest for " + pinned + " not found: manifest unknown" },
		"refused":       func(f *fakeEngine) { f.pullStatus = 404 },
	} {
		h := newEnvironment(t)
		fail(h.engine)
		r := h.run(h.env.ContainerStart, startPayload(nil))
		if r.Status != protocol.StatusError || r.Error.Class != ClassImagePull {
			t.Fatalf("%s: %#v", name, r)
		}
		if !strings.Contains(r.Error.Message, "manifest unknown") && !strings.Contains(r.Error.Message, "pull access denied") {
			t.Fatalf("%s: the message does not carry the registry's words: %s", name, r.Error.Message)
		}
		if len(h.engine.containers) != 0 || len(h.engine.creates) != 0 || len(h.engine.volumes) != 0 {
			t.Fatalf("%s: something was created after a failed pull", name)
		}
	}
}

func TestContainerStartPullsNothingWhenItRefuses(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	r := h.runAs(124, h.env.ContainerStart, startPayload(nil))
	if r.Status != protocol.StatusError || r.Error.Class != ClassSessionMismatch {
		t.Fatalf("%#v", r)
	}
	if len(h.engine.pulls) != 1 {
		t.Fatalf("pulls %v: a refused start pulled", h.engine.pulls)
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
	// Without the session's container, the stop says so.
	r = h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusError || r.Error.Class != ClassNoSessionContainer {
		t.Fatalf("%#v", r)
	}
}

func TestContainerStopOfAnotherSessionsContainerIsAMismatch(t *testing.T) {
	h := newEnvironment(t)
	h.start(h.env, nil)
	r := h.runAs(124, h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusError || r.Error.Class != ClassSessionMismatch {
		t.Fatalf("%#v", r)
	}
	if c := h.only(); !c.State.Running || c.Config.Labels[LabelSession] != "123" {
		t.Fatal("the other session's container was stopped or removed")
	}
}

func TestContainerStopLeavesOtherEnvironmentsAlone(t *testing.T) {
	h := newEnvironment(t)
	other := h.another("aixle-r7-99999999")
	h.start(other, nil)
	r := h.run(h.env.ContainerStop, map[string]any{})
	if r.Status != protocol.StatusError || r.Error.Class != ClassNoSessionContainer || len(h.engine.containers) != 1 {
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
	want := []string{"batch", "container.start", "container.stop", "env.reset", "env.scrub", "exec", "logs", "read_file", "status", "write_file"}
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
