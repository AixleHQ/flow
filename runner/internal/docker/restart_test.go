package docker

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

// opsGateway is a fake of the two ops endpoints (PROTOCOL.md §5.4, §5.5).
type opsGateway struct {
	mu      sync.Mutex
	ops     []protocol.Op
	results map[int64]protocol.Result
	posts   map[int64]int
	idle    func()
}

func (g *opsGateway) PollOps(_ context.Context, _ string, after int64, _ time.Duration) (protocol.Poll, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	var out []protocol.Op
	for _, op := range g.ops {
		if _, done := g.results[op.ID]; op.Sequence > after && !done {
			out = append(out, op)
		}
	}
	if len(out) == 0 && g.idle != nil {
		g.idle()
	}
	return protocol.Poll{Ops: out}, nil
}

func (g *opsGateway) PostResult(_ context.Context, _ string, id int64, r protocol.Result) (protocol.ResultState, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.posts[id]++
	if _, ok := g.results[id]; !ok {
		g.results[id] = r
	}
	return protocol.ResultState{ID: id, State: "completed"}, nil
}

// add enqueues an op. A session op's envelope names the session the tests run.
func (g *opsGateway) add(id int64, name string, payload any) {
	raw, _ := json.Marshal(payload)
	op := protocol.Op{ID: id, Sequence: id, Op: name, DeadlineAt: time.Now().Add(time.Hour), Payload: raw}
	if !strings.HasPrefix(name, "env.") {
		session := sessionID
		op.SessionID = &session
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	g.ops = append(g.ops, op)
}

func (g *opsGateway) result(id int64) (protocol.Result, int) {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.results[id], g.posts[id]
}

type nopStore struct{}

func (nopStore) Save(credentials.Credentials) error { return nil }
func (nopStore) Delete() error                      { return nil }

type nopRefresher struct{}

func (nopRefresher) Refresh(context.Context, string) (protocol.TokenPair, error) {
	return protocol.TokenPair{}, nil
}

// hostRunner is one start of the host runner on a state directory, with the
// handlers it registers in production.
func hostRunner(t *testing.T, stateDir string, env *Environment, gw *opsGateway) *host.Loop {
	t.Helper()
	j, err := journal.Open(stateDir, nil)
	if err != nil {
		t.Fatal(err)
	}
	handlers := map[string]host.Handler{}
	for name, h := range env.Handlers() {
		handlers[name] = h
	}
	return &host.Loop{
		Gateway: gw,
		Tokens: tokens.NewSource(nopStore{}, nopRefresher{}, credentials.Credentials{TokenPair: protocol.TokenPair{
			AccessToken: "aracc_x", AccessTokenExpiresAt: time.Now().Add(time.Hour),
			RefreshToken: "arref_x", RefreshTokenExpiresAt: time.Now().Add(time.Hour),
		}}),
		Journal:  j,
		Handlers: handlers,
		Logger:   slog.New(slog.NewTextHandler(io.Discard, nil)),
		Wait:     time.Millisecond,
	}
}

func TestAHostRunnerRestartDoesNotStopTheAgent(t *testing.T) {
	h := newEnvironment(t)
	block := make(chan struct{})
	defer close(block)
	h.engine.run = func(x *fakeExec, _ []byte) fakeRun {
		if reflect.DeepEqual(command(x.Request.Cmd), []string{"sleep", "30"}) {
			return fakeRun{Block: block}
		}
		return fakeRun{Stdout: []byte("after the restart\n")}
	}
	gw := &opsGateway{results: map[int64]protocol.Result{}, posts: map[int64]int{}}
	gw.add(1, "container.start", startPayload(nil))
	gw.add(2, "exec", map[string]any{"cmd": []string{"sleep", "30"}})

	// The first host runner starts the container and is stopped during the exec,
	// as `systemctl restart aixle-runner` stops it.
	first := hostRunner(t, h.state, h.env, gw)
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan error)
	go func() { stopped <- first.Run(ctx) }()
	deadline := time.Now().Add(5 * time.Second)
	for !h.execStarted() {
		if time.Now().After(deadline) {
			t.Fatal("the exec never started")
		}
		time.Sleep(10 * time.Millisecond)
	}
	cancel()
	if err := <-stopped; err != nil {
		t.Fatal(err)
	}
	c := h.only()
	if !c.State.Running {
		t.Fatal("the restart stopped the agent container")
	}
	if r, posts := gw.result(2); posts != 0 {
		t.Fatalf("the cut-off exec was answered %#v", r)
	}

	// The restarted host runner keeps nothing in memory: it finds the container
	// by its labels, answers the cut-off exec `interrupted` without running it
	// again, and runs the next one.
	gw.add(3, "exec", map[string]any{"cmd": []string{"echo", "after"}})
	second := hostRunner(t, h.state, &Environment{API: h.env.API, Key: envKey, StateDir: h.state}, gw)
	ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	gw.mu.Lock()
	gw.idle = cancel
	gw.mu.Unlock()
	if err := second.Run(ctx); err != nil {
		t.Fatal(err)
	}
	if r, posts := gw.result(1); posts != 1 || r.Status != protocol.StatusOK {
		t.Fatalf("container.start: %d posts, %#v", posts, r)
	}
	if r, posts := gw.result(2); posts != 1 || r.Error == nil || r.Error.Class != host.ClassInterrupted {
		t.Fatalf("the cut-off exec: %d posts, %#v", posts, r)
	}
	if r, posts := gw.result(3); posts != 1 || r.Status != protocol.StatusOK || *r.Stdout != "after the restart\n" {
		t.Fatalf("the exec after the restart: %d posts, %#v", posts, r)
	}
	if n := h.execsOf([]string{"sleep", "30"}); n != 1 {
		t.Fatalf("the cut-off exec ran %d times", n)
	}
	if after := h.only(); after.ID != c.ID || !after.State.Running {
		t.Fatal("the container changed across the restart")
	}
}

func (h *harness) execStarted() bool {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	for _, x := range h.engine.execs {
		if x.Started {
			return true
		}
	}
	return false
}

func (h *harness) execsOf(cmd []string) int {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	n := 0
	for _, x := range h.engine.execs {
		if reflect.DeepEqual(command(x.Request.Cmd), cmd) {
			n++
		}
	}
	return n
}

// command is an exec's command without the `timeout -k <s> <s>` that bounds it
// by its timeout or by the op's deadline.
func command(cmd []string) []string {
	if len(cmd) > 4 && cmd[0] == "timeout" && cmd[1] == "-k" {
		return cmd[4:]
	}
	return cmd
}

func TestAResultOverTheGatewaysBodyCapIsAnsweredResultTooLarge(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	for _, p := range []string{"/a", "/b"} {
		h.put(c, p, &fakeFile{Content: bytes.Repeat([]byte("x"), 900<<10), Mode: 0o644})
	}
	gw := &opsGateway{results: map[int64]protocol.Result{}, posts: map[int64]int{}}
	gw.add(1, "batch", map[string]any{"ops": []map[string]any{
		{"op": "read_file", "payload": map[string]any{"path": "/a"}},
		{"op": "read_file", "payload": map[string]any{"path": "/b"}},
	}})
	gw.add(2, "read_file", map[string]any{"path": "/a"})
	loop := hostRunner(t, h.state, h.env, gw)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	gw.mu.Lock()
	gw.idle = cancel
	gw.mu.Unlock()
	if err := loop.Run(ctx); err != nil {
		t.Fatal(err)
	}
	r, posts := gw.result(1)
	if posts != 1 || r.Error == nil || r.Error.Class != host.ClassResultTooLarge || r.Data != nil {
		t.Fatalf("batch: %d posts, %#v", posts, r)
	}
	if !strings.Contains(r.Error.Message, "batch's result is") || !strings.Contains(r.Error.Message, "2 steps, of which 2 ran") {
		t.Fatalf("message %q", r.Error.Message)
	}
	// One file of 900 KiB fits.
	if r, posts := gw.result(2); posts != 1 || r.Status != protocol.StatusOK {
		t.Fatalf("read_file: %d posts, %#v", posts, r)
	}
}
