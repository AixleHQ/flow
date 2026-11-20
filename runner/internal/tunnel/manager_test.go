package tunnel

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	wire "github.com/aixlehq/aixle-runner/protocol/tunnel"
)

var testNow = time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)

type memStore struct{}

func (memStore) Save(credentials.Credentials) error { return nil }
func (memStore) Delete() error                      { return nil }

type noRefresh struct{}

func (noRefresh) Refresh(context.Context, string) (protocol.TokenPair, error) {
	return protocol.TokenPair{}, errors.New("no refresh expected")
}

func newTokens() *tokens.Source {
	s := tokens.NewSource(memStore{}, noRefresh{}, credentials.Credentials{
		URL: "https://flow.aixle.com",
		TokenPair: protocol.TokenPair{
			AccessToken: "aracc_one", AccessTokenExpiresAt: testNow.Add(time.Hour),
			RefreshToken: "arref_one", RefreshTokenExpiresAt: testNow.Add(24 * time.Hour),
		},
	})
	s.SetClock(func() time.Time { return testNow })
	return s
}

// fakeGateway mints "ticket-N" and records the access token it saw.
type fakeGateway struct {
	mu      sync.Mutex
	minted  int
	access  []string
	failure error
}

func (g *fakeGateway) TunnelTicket(_ context.Context, access string) (protocol.TunnelTicket, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.access = append(g.access, access)
	if g.failure != nil {
		return protocol.TunnelTicket{}, g.failure
	}
	g.minted++
	return protocol.TunnelTicket{Ticket: "artun_" + string(rune('0'+g.minted))}, nil
}

func (g *fakeGateway) accessSeen() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]string(nil), g.access...)
}

func (g *fakeGateway) setFailure(err error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.failure = err
}

func (g *fakeGateway) count() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.minted
}

// fakeRelay is a relay's end of the upgrade: it checks the headers, answers a
// scripted refusal or accepts, and hands each connected session to the test.
type fakeRelay struct {
	t        *testing.T
	server   *httptest.Server
	mu       sync.Mutex
	refusals []refusalReply // consumed in order, one per upgrade
	tickets  []string
	headers  []http.Header
	sessions chan *wire.Session
	attempts atomic.Int32
	conns    sync.Map // *wire.Session -> wire.Conn
}

// closeWith ends a connection the way the relay does, with a close code.
func (r *fakeRelay) closeWith(s *wire.Session, code int) {
	conn, _ := r.conns.Load(s)
	conn.(wire.Conn).Close(code, "bye")
}

type refusalReply struct {
	status int
	code   string
}

func newFakeRelay(t *testing.T) *fakeRelay {
	r := &fakeRelay{t: t, sessions: make(chan *wire.Session, 16)}
	r.server = httptest.NewServer(http.HandlerFunc(r.serve))
	t.Cleanup(r.server.Close)
	return r
}

func (r *fakeRelay) url() string {
	return "ws" + strings.TrimPrefix(r.server.URL, "http") + "/runner/v1/tunnel"
}

func (r *fakeRelay) refuse(replies ...refusalReply) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.refusals = append(r.refusals, replies...)
}

func (r *fakeRelay) serve(w http.ResponseWriter, req *http.Request) {
	r.attempts.Add(1)
	r.mu.Lock()
	r.tickets = append(r.tickets, strings.TrimPrefix(req.Header.Get("Authorization"), "Bearer "))
	r.headers = append(r.headers, req.Header.Clone())
	var reply *refusalReply
	if len(r.refusals) > 0 {
		reply, r.refusals = &r.refusals[0], r.refusals[1:]
	}
	r.mu.Unlock()
	if reply != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(reply.status)
		io.WriteString(w, `{"error":"`+reply.code+`","message":"m"}`)
		return
	}
	c, err := websocket.Accept(w, req, &websocket.AcceptOptions{Subprotocols: []string{Subprotocol}})
	if err != nil {
		return
	}
	id := int64(123)
	conn := wire.NewWSConn(c)
	sess := wire.NewRelay(conn, wire.Config{SessionID: id, PingInterval: time.Second})
	r.conns.Store(sess, conn)
	ctx, cancel := context.WithTimeout(req.Context(), 5*time.Second)
	defer cancel()
	if err := sess.Handshake(ctx); err != nil {
		return
	}
	r.sessions <- sess
	<-sess.Done()
}

func (r *fakeRelay) next(t *testing.T) *wire.Session {
	t.Helper()
	select {
	case s := <-r.sessions:
		return s
	case <-time.After(5 * time.Second):
		t.Fatal("no connection reached the relay")
		return nil
	}
}

func (r *fakeRelay) ticketsSeen() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.tickets...)
}

type harness struct {
	t       *testing.T
	gateway *fakeGateway
	relay   *fakeRelay
	manager *Manager
	holds   atomic.Bool
	sleeps  chan time.Duration
	logs    *syncBuffer
}

type syncBuffer struct {
	mu sync.Mutex
	b  strings.Builder
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

func newHarness(t *testing.T) *harness {
	h := &harness{t: t, gateway: &fakeGateway{}, relay: newFakeRelay(t), sleeps: make(chan time.Duration, 256), logs: &syncBuffer{}}
	h.holds.Store(true)
	h.manager = &Manager{
		Gateway:   h.gateway,
		Tokens:    newTokens(),
		Connector: &WSConnector{URL: h.relay.url(), Version: "0.5.0", Config: wire.Config{PingInterval: time.Second}},
		Holds:     func(context.Context) (bool, error) { return h.holds.Load(), nil },
		Logger:    slog.New(slog.NewJSONHandler(h.logs, nil)),
		Backoff:   &backoff.Backoff{Base: time.Second, Max: 30 * time.Second, Rand: func() float64 { return 1 }},
		// The sleeps are recorded and cut short, so a test does not wait for backoffs.
		PollEvery:    20 * time.Millisecond,
		GoAwayJitter: 2 * time.Second,
		Rand:         func() float64 { return 0.5 },
		Sleep: func(ctx context.Context, d time.Duration) error {
			if d != 20*time.Millisecond {
				h.sleeps <- d
			}
			return backoff.Sleep(ctx, min(d, 5*time.Millisecond))
		},
	}
	return h
}

func (h *harness) run() (stop func() error) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- h.manager.Run(ctx) }()
	var once sync.Once
	var result error
	stop = func() error {
		once.Do(func() {
			cancel()
			select {
			case result = <-done:
			case <-time.After(5 * time.Second):
				h.t.Error("Run did not return after its context was cancelled")
			}
		})
		return result
	}
	h.t.Cleanup(func() { stop() })
	return stop
}

func (h *harness) sleep(t *testing.T) time.Duration {
	t.Helper()
	select {
	case d := <-h.sleeps:
		return d
	case <-time.After(5 * time.Second):
		t.Fatal("the manager did not wait")
		return 0
	}
}

func TestItConnectsWhileTheMachineHoldsASession(t *testing.T) {
	h := newHarness(t)
	stop := h.run()

	session := h.relay.next(t)

	if id := session.Peer().SessionID; id != nil && *id != 123 {
		t.Fatalf("session id %v", *id)
	}
	if got := h.gateway.accessSeen(); len(got) != 1 || got[0] != "aracc_one" {
		t.Fatalf("the ticket was asked for with %v", got)
	}
	headers := h.relay.headers[0]
	if headers.Get("Authorization") != "Bearer artun_1" || headers.Get("X-Aixle-Runner-Protocol") != "1" ||
		headers.Get("X-Aixle-Runner-Version") != "0.5.0" || headers.Get("Sec-WebSocket-Protocol") != Subprotocol {
		t.Fatalf("headers: %v", headers)
	}
	if err := stop(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-session.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the connection outlived the runner")
	}
}

func TestItOpensNoConnectionForAnIdleMachineAndConnectsWhenASessionStarts(t *testing.T) {
	h := newHarness(t)
	h.holds.Store(false)
	h.run()

	time.Sleep(150 * time.Millisecond)
	if n := h.gateway.count() + int(h.relay.attempts.Load()); n != 0 {
		t.Fatalf("an idle machine asked for %d tickets or connections", n)
	}

	h.holds.Store(true)
	h.relay.next(t)
}

func TestItClosesTheTunnelWhenTheSessionEnds(t *testing.T) {
	h := newHarness(t)
	h.run()
	session := h.relay.next(t)

	h.holds.Store(false)

	select {
	case <-session.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the tunnel is still open after the session ended")
	}
	time.Sleep(100 * time.Millisecond)
	if got := h.relay.attempts.Load(); got != 1 {
		t.Fatalf("%d connections, want no new one for an idle machine", got)
	}
}

func TestItAnswersEveryOpenWithRefused(t *testing.T) {
	h := newHarness(t)
	h.run()
	session := h.relay.next(t)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, err := session.Open(ctx, 123, 7681)

	var reset *wire.ResetError
	if !errors.As(err, &reset) || reset.Code != wire.ResetRefused {
		t.Fatalf("Open = %v, want RESET refused", err)
	}
}

func TestItReconnectsWithBackoffAfterADrop(t *testing.T) {
	h := newHarness(t)
	h.run()

	for i, want := range []time.Duration{time.Second, 2 * time.Second, 4 * time.Second} {
		session := h.relay.next(t)
		h.relay.closeWith(session, wire.CloseRevoked)
		if got := h.sleep(t); got != want {
			t.Fatalf("drop %d: waited %v, want %v", i+1, got, want)
		}
	}
	h.relay.next(t)
	if got := h.gateway.count(); got != 4 {
		t.Fatalf("%d tickets for 4 connections", got)
	}
}

func TestABackoffThatNeverEndsStaysAtThirtySeconds(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{503, "unavailable"}, refusalReply{503, "unavailable"}, refusalReply{503, "unavailable"},
		refusalReply{503, "unavailable"}, refusalReply{503, "unavailable"}, refusalReply{503, "unavailable"})
	h.run()

	var got []time.Duration
	for range 6 {
		got = append(got, h.sleep(t))
	}
	want := []time.Duration{time.Second, 2 * time.Second, 4 * time.Second, 8 * time.Second, 16 * time.Second, 30 * time.Second}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("delays %v, want %v", got, want)
		}
	}
}

func TestAStableConnectionStartsTheBackoffOver(t *testing.T) {
	h := newHarness(t)
	h.manager.StableAfter = 50 * time.Millisecond
	h.run()

	first := h.relay.next(t)
	h.relay.closeWith(first, wire.CloseRevoked)
	if got := h.sleep(t); got != time.Second {
		t.Fatalf("first drop: %v", got)
	}
	second := h.relay.next(t)
	time.Sleep(120 * time.Millisecond)
	h.relay.closeWith(second, wire.CloseRevoked)
	if got := h.sleep(t); got != time.Second {
		t.Fatalf("a drop after a stable connection waited %v, want the backoff to start over at 1s", got)
	}
}

func TestARefusedTicketIsMetWithANewOneOnce(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{401, "invalid_ticket"})
	h.run()

	h.relay.next(t)

	if got := h.relay.ticketsSeen(); len(got) != 2 || got[0] != "artun_1" || got[1] != "artun_2" {
		t.Fatalf("tickets presented: %v", got)
	}
	select {
	case d := <-h.sleeps:
		t.Fatalf("the retry with a new ticket waited %v", d)
	default:
	}
}

func TestAReplayedTicketIsMetWithANewOneToo(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{403, "ticket_replayed"})
	h.run()

	h.relay.next(t)

	if got := h.relay.ticketsSeen(); len(got) != 2 {
		t.Fatalf("tickets presented: %v", got)
	}
}

func TestASecondTicketRefusalBacksOff(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{401, "invalid_ticket"}, refusalReply{401, "invalid_ticket"})
	h.run()

	if got := h.sleep(t); got != time.Second {
		t.Fatalf("waited %v after two refusals, want 1s", got)
	}
	h.relay.next(t)
	if got := h.relay.ticketsSeen(); len(got) != 3 {
		t.Fatalf("tickets presented: %v", got)
	}
}

func TestItDoesNotConnectOrBackOffForAMachineTheGatewaySeesIdle(t *testing.T) {
	h := newHarness(t)
	h.gateway.setFailure(&protocol.Refusal{Endpoint: protocol.EndpointTunnelTicket, Status: 409, Code: "no_session", Message: "m"})
	h.run()

	time.Sleep(200 * time.Millisecond)
	select {
	case d := <-h.sleeps:
		t.Fatalf("a no_session answer grew the backoff: %v", d)
	default:
	}
	if got := h.relay.attempts.Load(); got != 0 {
		t.Fatalf("%d upgrades without a ticket", got)
	}
	if n := len(h.gateway.accessSeen()); n < 2 {
		t.Fatalf("the manager asked %d times, want it to keep asking", n)
	}
}

func TestAGoAwayReconnectsAtOnceWithJitterAndNoBackoff(t *testing.T) {
	h := newHarness(t)
	h.run()
	first := h.relay.next(t)

	if err := first.GoAway(); err != nil {
		t.Fatal(err)
	}

	second := h.relay.next(t)
	_ = second
	// Jitter 0.5 × 2 s, and no step of the failure backoff.
	if got := h.sleep(t); got != time.Second {
		t.Fatalf("waited %v after GOAWAY, want the jitter of 1s", got)
	}
	h.manager.Backoff.Reset()
	select {
	case <-first.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the drained connection did not close")
	}
}

func TestTheNextFailureAfterAGoAwayStartsTheBackoffAtOneSecond(t *testing.T) {
	h := newHarness(t)
	h.run()
	first := h.relay.next(t)
	first.GoAway()
	second := h.relay.next(t)
	h.sleep(t) // the jitter

	h.relay.closeWith(second, wire.CloseRevoked)

	if got := h.sleep(t); got != time.Second {
		t.Fatalf("waited %v, want 1s: a GOAWAY is no failure", got)
	}
}

func TestARelayThatClosesNormallyIsAskingForAReconnectNotFailing(t *testing.T) {
	for name, code := range map[string]int{"normal": wire.CloseNormal, "going away": 1001} {
		t.Run(name, func(t *testing.T) {
			h := newHarness(t)
			h.run()
			first := h.relay.next(t)

			h.relay.closeWith(first, code)

			h.relay.next(t)
			if got := h.sleep(t); got != time.Second {
				t.Fatalf("waited %v, want the 1s of jitter (0.5 of 2s), not a backoff step", got)
			}
		})
	}
}

func TestARelayThatClosesWithAnotherCodeBacksOff(t *testing.T) {
	h := newHarness(t)
	h.run()
	first := h.relay.next(t)

	h.relay.closeWith(first, wire.CloseReplaced)

	if got := h.sleep(t); got != time.Second {
		t.Fatalf("waited %v", got)
	}
	h.relay.next(t)
}

func TestUnsupportedProtocolEndsRunWithErrUnsupported(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{400, "unsupported_protocol"})

	err := h.manager.Run(context.Background())

	if !errors.Is(err, ErrUnsupported) {
		t.Fatalf("Run = %v", err)
	}
}

func TestARefusalThatEndsTheRunnersWorkIsReturned(t *testing.T) {
	h := newHarness(t)
	h.gateway.failure = &protocol.Refusal{Endpoint: protocol.EndpointTunnelTicket, Status: 401, Code: "runner_revoked", Message: "m"}

	err := h.manager.Run(context.Background())

	stop, ok := tokens.AsStop(err)
	if !ok || stop.Action != protocol.ActionRevoked {
		t.Fatalf("Run = %v", err)
	}
}

func TestOtherFailuresOfTheTicketEndpointBackOff(t *testing.T) {
	h := newHarness(t)
	h.gateway.failure = &protocol.Refusal{Endpoint: protocol.EndpointTunnelTicket, Status: 403, Code: "runners_disabled", Message: "m"}
	h.run()

	for _, want := range []time.Duration{time.Second, 2 * time.Second} {
		if got := h.sleep(t); got != want {
			t.Fatalf("waited %v, want %v", got, want)
		}
	}
}

func TestANetworkFailureOfTheUpgradeBacksOff(t *testing.T) {
	h := newHarness(t)
	h.relay.server.Close()
	h.run()

	if got := h.sleep(t); got != time.Second {
		t.Fatalf("waited %v", got)
	}
}

func TestNoTicketReachesTheLogs(t *testing.T) {
	h := newHarness(t)
	h.relay.refuse(refusalReply{401, "invalid_ticket"}, refusalReply{403, "ticket_replayed"})
	h.run()
	h.sleep(t)
	session := h.relay.next(t)
	h.relay.closeWith(session, wire.CloseRevoked)
	h.sleep(t)

	logs := h.logs.String()
	if logs == "" {
		t.Fatal("no logs")
	}
	for _, secret := range []string{"artun_", "aracc_", "arref_", "Bearer"} {
		if strings.Contains(logs, secret) {
			t.Fatalf("the logs hold %q:\n%s", secret, logs)
		}
	}
}
