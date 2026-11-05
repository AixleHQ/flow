package docker

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"reflect"
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

func (g *opsGateway) PollOps(_ context.Context, _ string, after int64, _ time.Duration) ([]protocol.Op, error) {
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
	return out, nil
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

func (g *opsGateway) add(id int64, name string, payload any) {
	raw, _ := json.Marshal(payload)
	g.mu.Lock()
	defer g.mu.Unlock()
	g.ops = append(g.ops, protocol.Op{ID: id, Sequence: id, Op: name, DeadlineAt: time.Now().Add(time.Hour), Payload: raw})
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
		if reflect.DeepEqual(x.Request.Cmd, []string{"sleep", "30"}) {
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
		if reflect.DeepEqual(x.Request.Cmd, cmd) {
			n++
		}
	}
	return n
}
