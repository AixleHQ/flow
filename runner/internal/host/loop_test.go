package host

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

var now = time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)

// gateway is a fake of the ops endpoints, following PROTOCOL.md §5.4 and §5.5: a
// poll returns the ops above `after` that have no result yet, and the first result
// of an op wins.
type gateway struct {
	mu          sync.Mutex
	ops         []protocol.Op
	results     map[int64]protocol.Result
	posts       map[int64]int
	afters      []int64
	tokens      []string
	pollErrs    []error
	resultErrs  []error
	inFlight    int
	maxInFlight int
	// idle is called by a poll that has nothing to return, to end the test.
	idle func()
}

func newGateway(ops ...protocol.Op) *gateway {
	return &gateway{ops: ops, results: map[int64]protocol.Result{}, posts: map[int64]int{}}
}

func (g *gateway) PollOps(_ context.Context, access string, after int64, wait time.Duration) ([]protocol.Op, error) {
	g.mu.Lock()
	g.inFlight++
	if g.inFlight > g.maxInFlight {
		g.maxInFlight = g.inFlight
	}
	g.mu.Unlock()
	defer func() { g.mu.Lock(); g.inFlight--; g.mu.Unlock() }()

	g.mu.Lock()
	defer g.mu.Unlock()
	g.afters = append(g.afters, after)
	g.tokens = append(g.tokens, access)
	if len(g.pollErrs) > 0 {
		err := g.pollErrs[0]
		g.pollErrs = g.pollErrs[1:]
		return nil, err
	}
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

func (g *gateway) PostResult(_ context.Context, access string, id int64, r protocol.Result) (protocol.ResultState, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.posts[id]++
	if len(g.resultErrs) > 0 {
		err := g.resultErrs[0]
		g.resultErrs = g.resultErrs[1:]
		if err != nil {
			return protocol.ResultState{}, err
		}
	}
	if _, ok := g.results[id]; !ok {
		g.results[id] = r
	}
	return protocol.ResultState{ID: id, State: "completed"}, nil
}

type memStore struct{ saved []credentials.Credentials }

func (s *memStore) Save(c credentials.Credentials) error { s.saved = append(s.saved, c); return nil }
func (s *memStore) Delete() error                        { return nil }

type refresher struct{ n int }

func (r *refresher) Refresh(_ context.Context, _ string) (protocol.TokenPair, error) {
	r.n++
	return protocol.TokenPair{
		AccessToken: "aracc_rotated", AccessTokenExpiresAt: now.Add(time.Hour),
		RefreshToken: "arref_rotated", RefreshTokenExpiresAt: now.Add(720 * time.Hour),
	}, nil
}

type harness struct {
	t       *testing.T
	dir     string
	gw      *gateway
	journal *journal.Journal
	loop    *Loop
	ran     map[int64]int
	sleeps  []time.Duration
	logs    *bytes.Buffer
	store   *memStore
	refresh *refresher
}

func newHarness(t *testing.T, dir string, gw *gateway) *harness {
	t.Helper()
	j, err := journal.Open(dir, func() time.Time { return now })
	if err != nil {
		t.Fatal(err)
	}
	h := &harness{t: t, dir: dir, gw: gw, journal: j, ran: map[int64]int{}, logs: &bytes.Buffer{}, store: &memStore{}, refresh: &refresher{}}
	source := tokens.NewSource(h.store, h.refresh, credentials.Credentials{
		URL: "https://flow.aixle.com",
		TokenPair: protocol.TokenPair{
			AccessToken: "aracc_first", AccessTokenExpiresAt: now.Add(time.Hour),
			RefreshToken: "arref_first", RefreshTokenExpiresAt: now.Add(720 * time.Hour),
		},
	})
	source.SetClock(func() time.Time { return now })
	b := backoff.New(time.Second, time.Minute)
	b.Rand = func() float64 { return 0 }
	h.loop = &Loop{
		Gateway: gw,
		Tokens:  source,
		Journal: j,
		Handlers: map[string]Handler{
			"image.ensure": func(_ context.Context, payload json.RawMessage) protocol.Result {
				var p struct {
					ID int64 `json:"id"`
				}
				_ = json.Unmarshal(payload, &p)
				h.ran[p.ID]++
				return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"pulled": true}}
			},
		},
		Logger:  slog.New(slog.NewTextHandler(h.logs, &slog.HandlerOptions{Level: slog.LevelDebug})),
		Backoff: b,
		Wait:    time.Millisecond,
		Now:     func() time.Time { return now },
		Sleep: func(_ context.Context, d time.Duration) error {
			h.sleeps = append(h.sleeps, d)
			return nil
		},
	}
	return h
}

// run runs the loop until the gateway has nothing left to return.
func (h *harness) run() error {
	h.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	h.gw.idle = cancel
	err := h.loop.Run(ctx)
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		h.t.Fatal("the loop did not settle")
	}
	return err
}

func ensureOp(id, seq int64) protocol.Op {
	payload, _ := json.Marshal(map[string]any{"id": id})
	return protocol.Op{ID: id, Sequence: seq, Op: "image.ensure", DeadlineAt: now.Add(5 * time.Minute), Payload: payload}
}

func refusal(e protocol.Endpoint, status int, code string) error {
	return &protocol.Refusal{Endpoint: e, Status: status, Code: code, Message: "m"}
}

func TestRunsAnOpOncePostsItsResultAndMovesAfter(t *testing.T) {
	h := newHarness(t, t.TempDir(), newGateway(ensureOp(1031, 7), ensureOp(1032, 8)))
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if h.ran[1031] != 1 || h.ran[1032] != 1 {
		t.Fatalf("ran %v", h.ran)
	}
	if h.gw.posts[1031] != 1 || h.gw.results[1031].Status != protocol.StatusOK {
		t.Fatalf("posts %v results %v", h.gw.posts, h.gw.results)
	}
	if got := h.gw.afters; len(got) != 2 || got[0] != 0 || got[1] != 8 {
		t.Fatalf("polled with after %v", got)
	}
	if h.journal.After() != 8 {
		t.Fatalf("journal after %d", h.journal.After())
	}
	if h.gw.maxInFlight != 1 {
		t.Fatalf("%d polls were outstanding at once", h.gw.maxInFlight)
	}
}

func TestTheResultIsJournalledBeforeItIsPosted(t *testing.T) {
	gw := newGateway(ensureOp(1, 1))
	h := newHarness(t, t.TempDir(), gw)
	var journalled bool
	gw.resultErrs = []error{nil}
	inner := h.loop.Gateway
	h.loop.Gateway = postHook{Gateway: inner, before: func(id int64) {
		e, ok := h.journal.Lookup(id)
		journalled = ok && e.Result != nil
	}}
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if !journalled {
		t.Fatal("the result was posted before it was journalled")
	}
}

type postHook struct {
	Gateway
	before func(id int64)
}

func (p postHook) PostResult(ctx context.Context, access string, id int64, r protocol.Result) (protocol.ResultState, error) {
	p.before(id)
	return p.Gateway.PostResult(ctx, access, id, r)
}

func TestARestartDoesNotRunAnOpAgain(t *testing.T) {
	dir := t.TempDir()
	gw := newGateway(ensureOp(1, 1))
	first := newHarness(t, dir, gw)
	// The result never arrives, and the runner is stopped while it retries.
	ctx, cancel := context.WithCancel(context.Background())
	gw.resultErrs = []error{&protocol.NetworkError{Endpoint: protocol.EndpointResult, Err: errors.New("connection reset")}}
	first.loop.Sleep = func(context.Context, time.Duration) error { cancel(); return context.Canceled }
	if err := first.loop.Run(ctx); err != nil {
		t.Fatal(err)
	}
	if first.ran[1] != 1 || len(gw.results) != 0 {
		t.Fatalf("ran %v, results %v", first.ran, gw.results)
	}

	// The restarted runner gets the op again and answers it from the journal.
	second := newHarness(t, dir, gw)
	if err := second.run(); err != nil {
		t.Fatal(err)
	}
	if second.ran[1] != 0 {
		t.Fatal("the op ran again after the restart")
	}
	if gw.results[1].Status != protocol.StatusOK || gw.results[1].Data["pulled"] != true {
		t.Fatalf("posted %#v", gw.results[1])
	}

	// A third start resumes from the persisted `after`.
	third := newHarness(t, dir, gw)
	if err := third.run(); err != nil {
		t.Fatal(err)
	}
	if got := gw.afters[len(gw.afters)-1]; got != 1 {
		t.Fatalf("resumed with after=%d", got)
	}
}

func TestAnOpInterruptedByARestartIsNotRunAgain(t *testing.T) {
	dir := t.TempDir()
	op := ensureOp(5, 3)
	j, _ := journal.Open(dir, func() time.Time { return now })
	if err := j.Begin(op); err != nil {
		t.Fatal(err)
	}

	h := newHarness(t, dir, newGateway(op))
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	r := h.gw.results[5]
	if h.ran[5] != 0 || r.Status != protocol.StatusError || r.Error.Class != ClassInterrupted {
		t.Fatalf("ran %d, posted %#v", h.ran[5], r)
	}
}

func TestAGracefulStopDuringAnOpIsAnsweredAsInterrupted(t *testing.T) {
	dir := t.TempDir()
	gw := newGateway(ensureOp(5, 3))
	first := newHarness(t, dir, gw)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	// The handler runs until the runner is stopped, as a pull does on SIGTERM, and
	// then fails because of the cancellation.
	first.loop.Handlers["image.ensure"] = func(ctx context.Context, _ json.RawMessage) protocol.Result {
		cancel()
		<-ctx.Done()
		return protocol.ErrorResult("image_pull_failed", "pulling failed: "+ctx.Err().Error())
	}
	if err := first.loop.Run(ctx); err != nil {
		t.Fatal(err)
	}
	if len(gw.results) != 0 {
		t.Fatalf("posted %#v while stopping", gw.results)
	}
	if e, ok := first.journal.Lookup(5); !ok || e.Result != nil {
		t.Fatalf("journalled %#v", e)
	}

	second := newHarness(t, dir, gw)
	if err := second.run(); err != nil {
		t.Fatal(err)
	}
	r := gw.results[5]
	if second.ran[5] != 0 || gw.posts[5] != 1 || r.Status != protocol.StatusError || r.Error.Class != ClassInterrupted {
		t.Fatalf("ran %d, posts %d, posted %#v", second.ran[5], gw.posts[5], r)
	}
}

func TestAnOpPastItsDeadlineIsExpiredNotRun(t *testing.T) {
	op := ensureOp(9, 1)
	op.DeadlineAt = now.Add(-time.Second)
	h := newHarness(t, t.TempDir(), newGateway(op))
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if h.ran[9] != 0 || h.gw.results[9].Status != protocol.StatusExpired || h.gw.results[9].Error != nil {
		t.Fatalf("ran %d, posted %#v", h.ran[9], h.gw.results[9])
	}
}

func TestAnOpThisVersionDoesNotImplementAnswersAStableClass(t *testing.T) {
	op := protocol.Op{ID: 3, Sequence: 1, Op: "container.start", DeadlineAt: now.Add(time.Minute), Payload: json.RawMessage(`{}`)}
	h := newHarness(t, t.TempDir(), newGateway(op))
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	r := h.gw.results[3]
	if r.Status != protocol.StatusError || r.Error.Class != ClassUnsupportedOp || !strings.Contains(r.Error.Message, "container.start") {
		t.Fatalf("posted %#v", r)
	}
}

func TestANotFoundResultIsDropped(t *testing.T) {
	gw := newGateway(ensureOp(1, 1), ensureOp(2, 2))
	gw.resultErrs = []error{refusal(protocol.EndpointResult, 404, "not_found")}
	h := newHarness(t, t.TempDir(), gw)
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if gw.posts[1] != 1 || len(h.sleeps) != 0 {
		t.Fatalf("the dropped result was sent %d times", gw.posts[1])
	}
	if h.ran[2] != 1 || h.journal.After() != 2 {
		t.Fatalf("ran %v, after %d", h.ran, h.journal.After())
	}
}

func TestARefusedResultIsNotResent(t *testing.T) {
	for _, err := range []error{
		refusal(protocol.EndpointResult, 422, "invalid_result"),
		refusal(protocol.EndpointResult, 413, ""),
	} {
		gw := newGateway(ensureOp(1, 1))
		gw.resultErrs = []error{err}
		h := newHarness(t, t.TempDir(), gw)
		if err := h.run(); err != nil {
			t.Fatal(err)
		}
		if gw.posts[1] != 1 || len(h.sleeps) != 0 {
			t.Fatalf("%v: sent %d times, slept %v", err, gw.posts[1], h.sleeps)
		}
		if !strings.Contains(h.logs.String(), "bug in aixle-runner") {
			t.Fatalf("%v was not reported: %s", err, h.logs)
		}
	}
}

func TestResultsAreRetriedUntilAccepted(t *testing.T) {
	gw := newGateway(ensureOp(1, 1))
	gw.resultErrs = []error{
		refusal(protocol.EndpointResult, 429, ""),
		refusal(protocol.EndpointResult, 503, ""),
		&protocol.NetworkError{Endpoint: protocol.EndpointResult, Err: errors.New("timeout")},
	}
	h := newHarness(t, t.TempDir(), gw)
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if gw.posts[1] != 4 || gw.results[1].Status != protocol.StatusOK || h.ran[1] != 1 {
		t.Fatalf("posts %d, result %#v, ran %d", gw.posts[1], gw.results[1], h.ran[1])
	}
	if len(h.sleeps) != 3 || !(h.sleeps[0] < h.sleeps[1] && h.sleeps[1] < h.sleeps[2]) {
		t.Fatalf("slept %v", h.sleeps)
	}
}

func TestDisabledRunnersBackOffAndKeepTheCredentials(t *testing.T) {
	gw := newGateway(ensureOp(1, 1))
	gw.pollErrs = []error{
		refusal(protocol.EndpointOps, 403, "runners_disabled"),
		refusal(protocol.EndpointOps, 403, "runners_disabled"),
	}
	h := newHarness(t, t.TempDir(), gw)
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if len(h.sleeps) != 2 || h.ran[1] != 1 {
		t.Fatalf("slept %v, ran %v", h.sleeps, h.ran)
	}
	for _, tok := range gw.tokens {
		if tok != "aracc_first" {
			t.Fatalf("the credentials changed: %v", gw.tokens)
		}
	}
}

func TestAnAccessInvalidTokenRefreshesAndRetries(t *testing.T) {
	gw := newGateway(ensureOp(1, 1))
	gw.pollErrs = []error{refusal(protocol.EndpointOps, 401, "invalid_token")}
	h := newHarness(t, t.TempDir(), gw)
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if h.refresh.n != 1 || len(h.store.saved) != 1 || gw.tokens[1] != "aracc_rotated" || len(h.sleeps) != 0 {
		t.Fatalf("refreshes %d, saved %d, tokens %v, slept %v", h.refresh.n, len(h.store.saved), gw.tokens, h.sleeps)
	}
}

func TestRefusalsThatNeedAnOperatorStopTheLoop(t *testing.T) {
	for _, tc := range []struct {
		err  error
		want protocol.Action
	}{
		{refusal(protocol.EndpointOps, 401, "runner_revoked"), protocol.ActionRevoked},
		{refusal(protocol.EndpointOps, 400, "unsupported_protocol"), protocol.ActionUpdate},
	} {
		gw := newGateway()
		gw.pollErrs = []error{tc.err}
		h := newHarness(t, t.TempDir(), gw)
		err := h.run()
		if stop, ok := tokens.AsStop(err); !ok || stop.Action != tc.want {
			t.Errorf("%v: got %v", tc.err, err)
		}
	}
}

func TestARefusedPollStopsAsABug(t *testing.T) {
	gw := newGateway()
	gw.pollErrs = []error{refusal(protocol.EndpointOps, 400, "invalid_request")}
	h := newHarness(t, t.TempDir(), gw)
	err := h.run()
	if err == nil || !strings.Contains(err.Error(), "bug in aixle-runner") {
		t.Fatalf("got %v", err)
	}
}

func TestNoTokenReachesTheLog(t *testing.T) {
	gw := newGateway(ensureOp(1, 1))
	gw.pollErrs = []error{refusal(protocol.EndpointOps, 401, "invalid_token"), refusal(protocol.EndpointOps, 403, "runners_disabled")}
	gw.resultErrs = []error{&protocol.NetworkError{Endpoint: protocol.EndpointResult, Err: errors.New("reset")}}
	h := newHarness(t, t.TempDir(), gw)
	if err := h.run(); err != nil {
		t.Fatal(err)
	}
	if h.logs.Len() == 0 {
		t.Fatal("nothing was logged")
	}
	for _, prefix := range []string{"aracc_", "arref_", "arreg_"} {
		if strings.Contains(h.logs.String(), prefix) {
			t.Fatalf("the log carries a token:\n%s", h.logs)
		}
	}
}
