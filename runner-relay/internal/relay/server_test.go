package relay

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/coder/websocket"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"

	"github.com/aixlehq/aixle-runner-relay/internal/ticket"
	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

var key = []byte("a-ticket-key-of-32-characters-xx")

type harness struct {
	t       *testing.T
	server  *Server
	http    *httptest.Server
	redis   *miniredis.Miniredis
	metrics *Metrics
	logs    *syncBuffer
	jti     int
}

type syncBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

func newHarness(t *testing.T, mutate func(*Options)) *harness {
	t.Helper()
	mr := miniredis.RunT(t)
	h := &harness{t: t, redis: mr, metrics: NewMetrics(), logs: &syncBuffer{}}
	opts := Options{
		Verifier: ticket.NewVerifier(key),
		Guard:    ticket.RedisGuard{Client: redis.NewClient(&redis.Options{Addr: mr.Addr(), MaxRetries: -1})},
		Metrics:  h.metrics,
		Logger:   slog.New(slog.NewJSONHandler(h.logs, &slog.HandlerOptions{Level: slog.LevelDebug})),
	}
	if mutate != nil {
		mutate(&opts)
	}
	h.server = New(opts)
	h.http = httptest.NewServer(h.server.Handler())
	t.Cleanup(func() {
		h.http.Close()
		h.server.CloseAll()
	})
	return h
}

func (h *harness) ticket(environment int64, session *int64) string {
	h.jti++
	return ticket.Sign(key, ticket.Claims{
		Version: ticket.Version, EnvironmentID: environment, RunnerID: 7, SessionID: session,
		ID:        "jti-" + string(rune('a'+h.jti)) + "-" + time.Now().Format("150405.000000000"),
		ExpiresAt: time.Now().Add(time.Minute).Unix(),
	})
}

func (h *harness) headers(token string) http.Header {
	header := http.Header{}
	header.Set("X-Aixle-Runner-Protocol", "1")
	header.Set("X-Aixle-Runner-Version", "0.5.0")
	if token != "" {
		header.Set("Authorization", "Bearer "+token)
	}
	return header
}

func (h *harness) url() string { return "ws" + strings.TrimPrefix(h.http.URL, "http") + Path }

// connect opens the tunnel as a runner and completes the handshake.
func (h *harness) connect(token string) *tunnel.Session {
	h.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, resp, err := websocket.Dial(ctx, h.url(), &websocket.DialOptions{HTTPHeader: h.headers(token), Subprotocols: []string{Subprotocol}})
	if err != nil {
		h.t.Fatalf("dial: %v (%v)", err, resp)
	}
	if c.Subprotocol() != Subprotocol {
		h.t.Fatalf("subprotocol = %q", c.Subprotocol())
	}
	sess := tunnel.NewRunner(tunnel.NewWSConn(c), tunnel.Config{RunnerVersion: "0.5.0"})
	if err := sess.Handshake(ctx); err != nil {
		h.t.Fatalf("handshake: %v", err)
	}
	h.t.Cleanup(func() { sess.Close() })
	return sess
}

// refusal sends a plain request and returns its status and JSON error code.
func (h *harness) refusal(header http.Header) (int, string) {
	h.t.Helper()
	req, _ := http.NewRequest(http.MethodGet, h.http.URL+Path, nil)
	req.Header = header
	req.Header.Set("Connection", "Upgrade")
	req.Header.Set("Upgrade", "websocket")
	req.Header.Set("Sec-WebSocket-Version", "13")
	req.Header.Set("Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var out struct{ Error, Message string }
	if err := json.Unmarshal(body, &out); err != nil {
		h.t.Fatalf("status %d, body %q is not a refusal", resp.StatusCode, body)
	}
	return resp.StatusCode, out.Error
}

func eventually(t *testing.T, what string, ok func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if ok() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func session(n int64) *int64 { return &n }

func TestAMachineConnectsAndGetsTheTicketsSessionInHello(t *testing.T) {
	h := newHarness(t, nil)
	sess := h.connect(h.ticket(42, session(123)))

	hello := sess.Peer()
	if hello.SessionID == nil || *hello.SessionID != 123 {
		t.Fatalf("HELLO session_id = %v, want 123", hello.SessionID)
	}
	lim := sess.Limits()
	if lim.MaxFrame != 32768 || lim.MaxStreams != 64 || lim.Window != 262144 {
		t.Fatalf("limits: %+v", lim)
	}
	eventually(t, "the machine in the registry", func() bool { _, ok := h.server.Registry().Machine(42); return ok })
	m, _ := h.server.Registry().Machine(42)
	if m.RunnerID != 7 || m.SessionID != 123 || m.RunnerVersion != "0.5.0" {
		t.Fatalf("machine: %+v", m)
	}
	if got := testutil.ToFloat64(h.metrics.MachinesConnected); got != 1 {
		t.Fatalf("machines_connected = %v", got)
	}
	if got := testutil.ToFloat64(h.metrics.TunnelConnects.WithLabelValues(ResultOK)); got != 1 {
		t.Fatalf("connects ok = %v", got)
	}
}

func TestAnIdleMachineGetsNullInHello(t *testing.T) {
	h := newHarness(t, nil)
	sess := h.connect(h.ticket(42, nil))
	if sess.Peer().SessionID != nil {
		t.Fatalf("HELLO session_id = %v, want null", *sess.Peer().SessionID)
	}
}

func TestTheConnectionIsKeptAliveByTheHeartbeat(t *testing.T) {
	h := newHarness(t, func(o *Options) { o.PingInterval = time.Second })
	sess := h.connect(h.ticket(42, nil))
	select {
	case <-sess.Done():
		t.Fatalf("the session ended: %v", sess.Err())
	case <-time.After(3500 * time.Millisecond):
	}
}

func TestTheUpgradesRefusals(t *testing.T) {
	h := newHarness(t, nil)
	good := h.ticket(42, nil)

	with := func(mutate func(http.Header)) http.Header {
		header := h.headers(good)
		header.Set("Sec-WebSocket-Protocol", Subprotocol)
		mutate(header)
		return header
	}
	expired := ticket.Sign(key, ticket.Claims{Version: ticket.Version, EnvironmentID: 42, RunnerID: 7, ID: "old",
		ExpiresAt: time.Now().Add(-time.Minute).Unix()})
	wrongVersion := ticket.Sign(key, ticket.Claims{Version: 2, EnvironmentID: 42, RunnerID: 7, ID: "v2",
		ExpiresAt: time.Now().Add(time.Minute).Unix()})
	forged := ticket.Sign([]byte("another-key-of-32-characters-xxxx"), ticket.Claims{Version: ticket.Version, EnvironmentID: 42,
		RunnerID: 7, ID: "forged", ExpiresAt: time.Now().Add(time.Minute).Unix()})

	cases := []struct {
		name   string
		header http.Header
		status int
		code   string
	}{
		{"no protocol header", with(func(h http.Header) { h.Del("X-Aixle-Runner-Protocol") }), 400, "unsupported_protocol"},
		{"another protocol", with(func(h http.Header) { h.Set("X-Aixle-Runner-Protocol", "2") }), 400, "unsupported_protocol"},
		{"no subprotocol", with(func(h http.Header) { h.Del("Sec-WebSocket-Protocol") }), 400, "unsupported_protocol"},
		{"another subprotocol", with(func(h http.Header) { h.Set("Sec-WebSocket-Protocol", "aixle-runner-relay.v2") }), 400, "unsupported_protocol"},
		{"no runner version", with(func(h http.Header) { h.Del("X-Aixle-Runner-Version") }), 400, "invalid_runner_version"},
		{"a runner version that is not semver", with(func(h http.Header) { h.Set("X-Aixle-Runner-Version", "1.0") }), 400, "invalid_runner_version"},
		{"the headers come before the ticket", with(func(h http.Header) { h.Del("X-Aixle-Runner-Protocol"); h.Set("Authorization", "Bearer nope") }), 400, "unsupported_protocol"},
		{"no ticket", with(func(h http.Header) { h.Del("Authorization") }), 401, "invalid_ticket"},
		{"not a bearer", with(func(h http.Header) { h.Set("Authorization", "Basic abc") }), 401, "invalid_ticket"},
		{"garbage", with(func(h http.Header) { h.Set("Authorization", "Bearer garbage") }), 401, "invalid_ticket"},
		{"an access token", with(func(h http.Header) { h.Set("Authorization", "Bearer aracc_abc") }), 401, "invalid_ticket"},
		{"expired", with(func(h http.Header) { h.Set("Authorization", "Bearer "+expired) }), 401, "invalid_ticket"},
		{"wrong version", with(func(h http.Header) { h.Set("Authorization", "Bearer "+wrongVersion) }), 401, "invalid_ticket"},
		{"wrong key", with(func(h http.Header) { h.Set("Authorization", "Bearer "+forged) }), 401, "invalid_ticket"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			status, code := h.refusal(c.header)
			if status != c.status || code != c.code {
				t.Fatalf("got %d %s, want %d %s", status, code, c.status, c.code)
			}
		})
	}
	if got := h.server.Registry().Len(); got != 0 {
		t.Fatalf("%d machines registered after refusals", got)
	}
	if got := testutil.ToFloat64(h.metrics.TunnelConnects.WithLabelValues(ResultBadTicket)); got != 7 {
		t.Fatalf("bad_ticket = %v, want 7", got)
	}
	if got := testutil.ToFloat64(h.metrics.TunnelConnects.WithLabelValues(ResultVersion)); got != 7 {
		t.Fatalf("version = %v, want 7", got)
	}
}

func TestATicketWorksOnce(t *testing.T) {
	h := newHarness(t, nil)
	token := h.ticket(42, nil)
	h.connect(token)

	header := h.headers(token)
	header.Set("Sec-WebSocket-Protocol", Subprotocol)
	status, code := h.refusal(header)
	if status != http.StatusForbidden || code != "ticket_replayed" {
		t.Fatalf("got %d %s", status, code)
	}
	if got := testutil.ToFloat64(h.metrics.TunnelConnects.WithLabelValues(ResultReplayed)); got != 1 {
		t.Fatalf("replayed = %v", got)
	}
}

func TestWithoutRedisNoConnectionIsAccepted(t *testing.T) {
	h := newHarness(t, nil)
	token := h.ticket(42, nil)
	h.redis.Close()

	header := h.headers(token)
	header.Set("Sec-WebSocket-Protocol", Subprotocol)
	status, code := h.refusal(header)
	if status != http.StatusServiceUnavailable || code != "unavailable" {
		t.Fatalf("got %d %s", status, code)
	}
	if err := h.server.Ready(context.Background()); err == nil {
		t.Fatal("Ready is nil with Redis down")
	}
}

func TestASecondConnectionReplacesTheFirstWithCode4000(t *testing.T) {
	h := newHarness(t, nil)
	first := h.connect(h.ticket(42, session(1)))
	second := h.connect(h.ticket(42, session(1)))

	select {
	case <-first.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the first connection is still open")
	}
	var closed *tunnel.CloseError
	if !errors.As(first.Err(), &closed) || closed.Code != tunnel.CloseReplaced {
		t.Fatalf("the first connection ended with %v, want a close with code 4000", first.Err())
	}
	select {
	case <-second.Done():
		t.Fatalf("the second connection ended: %v", second.Err())
	default:
	}
	eventually(t, "one machine left", func() bool { return h.server.Registry().Len() == 1 })
	if got := testutil.ToFloat64(h.metrics.Replaced); got != 1 {
		t.Fatalf("replaced = %v", got)
	}
	if got := testutil.ToFloat64(h.metrics.MachinesConnected); got != 1 {
		t.Fatalf("machines_connected = %v", got)
	}
}

func TestAnotherMachineIsNotReplaced(t *testing.T) {
	h := newHarness(t, nil)
	first := h.connect(h.ticket(1, nil))
	h.connect(h.ticket(2, nil))
	select {
	case <-first.Done():
		t.Fatalf("machine 1 was closed: %v", first.Err())
	case <-time.After(200 * time.Millisecond):
	}
	if h.server.Registry().Len() != 2 {
		t.Fatalf("%d machines", h.server.Registry().Len())
	}
}

func TestAConnectionThatFailsItsHelloDoesNotReplaceAWorkingOne(t *testing.T) {
	h := newHarness(t, func(o *Options) { o.HandshakeTimeout = 200 * time.Millisecond })
	first := h.connect(h.ticket(42, nil))

	// A client that opens the WebSocket and never answers HELLO.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, h.url(), &websocket.DialOptions{HTTPHeader: h.headers(h.ticket(42, nil)), Subprotocols: []string{Subprotocol}})
	if err != nil {
		t.Fatal(err)
	}
	defer c.CloseNow()
	eventually(t, "the handshake failure", func() bool {
		return testutil.ToFloat64(h.metrics.TunnelConnects.WithLabelValues(ResultHandshake)) == 1
	})
	select {
	case <-first.Done():
		t.Fatalf("the working connection was closed: %v", first.Err())
	default:
	}
}

func TestDrainSendsGoAwayAndStopsTakingConnections(t *testing.T) {
	h := newHarness(t, nil)
	sess := h.connect(h.ticket(42, nil))
	if err := h.server.Ready(context.Background()); err != nil {
		t.Fatalf("not ready before the drain: %v", err)
	}

	h.server.Drain()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := sess.Accept(ctx); !errors.Is(err, tunnel.ErrGoAway) {
		t.Fatalf("Accept after the drain = %v, want ErrGoAway", err)
	}
	if err := h.server.Wait(ctx); err != nil {
		t.Fatalf("the connection did not close after its last stream: %v", err)
	}
	if h.server.Registry().Len() != 0 {
		t.Fatal("the machine is still registered")
	}
	if err := h.server.Ready(context.Background()); err == nil {
		t.Fatal("ready during a drain")
	}
	header := h.headers(h.ticket(42, nil))
	header.Set("Sec-WebSocket-Protocol", Subprotocol)
	if status, code := h.refusal(header); status != http.StatusServiceUnavailable || code != "unavailable" {
		t.Fatalf("a new connection during the drain: %d %s", status, code)
	}
}

func TestLogsNeverHoldATicket(t *testing.T) {
	h := newHarness(t, nil)
	token := h.ticket(42, session(9))
	sess := h.connect(token)
	// Replay, forged and valid tickets all leave a log line or none.
	header := h.headers(token)
	header.Set("Sec-WebSocket-Protocol", Subprotocol)
	h.refusal(header)
	h.redis.Close()
	header = h.headers(h.ticket(43, nil))
	header.Set("Sec-WebSocket-Protocol", Subprotocol)
	h.refusal(header)
	sess.Close()
	h.server.CloseAll()

	logs := h.logs.String()
	if logs == "" {
		t.Fatal("no logs at all")
	}
	for _, secret := range []string{token, strings.TrimPrefix(token, ticket.Prefix), "artun_", "Bearer"} {
		if strings.Contains(logs, secret) {
			t.Fatalf("the logs hold %q:\n%s", secret, logs)
		}
	}
	if !strings.Contains(logs, `"environment_id":42`) {
		t.Fatalf("the logs do not name the machine:\n%s", logs)
	}
}
