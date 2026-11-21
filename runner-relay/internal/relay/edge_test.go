package relay

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/prometheus/client_golang/prometheus/testutil"

	"github.com/aixlehq/aixle-runner-relay/internal/rails"
	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

const (
	tokenA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	tokenB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// fakeRails is the platform's two calls.
type fakeRails struct {
	mu         sync.Mutex
	holders    map[string]rails.Holder
	holderErr  error
	holderHits int
	// checks answers a reconcile pass; nil answers true for every machine.
	checks     func([]rails.Machine) ([]bool, error)
	checkCalls [][]rails.Machine
}

func (f *fakeRails) Holders(_ context.Context, token string) (rails.Holder, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.holderHits++
	if f.holderErr != nil {
		return rails.Holder{}, f.holderErr
	}
	h, ok := f.holders[token]
	if !ok {
		return rails.Holder{}, rails.ErrNotFound
	}
	return h, nil
}

func (f *fakeRails) Checks(_ context.Context, machines []rails.Machine) ([]bool, error) {
	f.mu.Lock()
	f.checkCalls = append(f.checkCalls, machines)
	check := f.checks
	f.mu.Unlock()
	if check != nil {
		return check(machines)
	}
	out := make([]bool, len(machines))
	for i := range out {
		out[i] = true
	}
	return out, nil
}

func (f *fakeRails) hits() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.holderHits
}

func (f *fakeRails) calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.checkCalls)
}

// port numbers of the fake session: the platform's bridge ports.
var bridgePorts = map[string]int{"tty": 7681, "view": 7682, "fs": 4040, "upload": 4041, "ide": 8443}

// edgeHarness is a relay with a fake platform and a fake machine, a runner that dials
// five backends of its own.
type edgeHarness struct {
	*harness
	rails    *fakeRails
	runner   *tunnel.Session
	backends map[string]*httptest.Server
	seen     chan seenRequest
	cancel   context.CancelFunc
	// block releases the handlers of "/block" paths.
	block chan struct{}
}

type seenRequest struct {
	Surface string
	Path    string
	Header  http.Header
	Host    string
}

func newEdgeHarness(t *testing.T, opts ...func(*Options)) *edgeHarness {
	t.Helper()
	fake := &fakeRails{holders: map[string]rails.Holder{}}
	e := &edgeHarness{rails: fake, backends: map[string]*httptest.Server{}, seen: make(chan seenRequest, 64), block: make(chan struct{})}
	e.harness = newHarness(t, func(o *Options) {
		o.Rails = fake
		for _, f := range opts {
			f(o)
		}
	})
	t.Cleanup(func() { close(e.block) })
	for surface := range bridgePorts {
		e.backends[surface] = httptest.NewServer(e.backend(surface))
		t.Cleanup(e.backends[surface].Close)
	}
	return e
}

// backend is what listens on a surface's port in the session container.
func (e *edgeHarness) backend(surface string) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		c, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
		if err != nil {
			return
		}
		defer c.CloseNow()
		for {
			typ, data, err := c.Read(r.Context())
			if err != nil {
				return
			}
			if c.Write(r.Context(), typ, append([]byte(surface+":"), data...)) != nil {
				return
			}
		}
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		select {
		case e.seen <- seenRequest{Surface: surface, Path: r.URL.RequestURI(), Header: r.Header.Clone(), Host: r.Host}:
		default:
		}
		if strings.HasPrefix(r.URL.Path, "/block") {
			w.WriteHeader(http.StatusOK)
			w.(http.Flusher).Flush()
			select {
			case <-e.block:
			case <-r.Context().Done():
			}
			return
		}
		fmt.Fprintf(w, "%s %s", surface, r.URL.Path)
	})
	return mux
}

// machine connects the fake machine: a runner that holds `sessionID` and serves the five
// bridge ports from the backends. Anything else it refuses.
func (e *edgeHarness) machine(env, sessionID int64) *tunnel.Session {
	t := e.t
	t.Helper()
	sess := e.connect(e.ticket(env, &sessionID))
	e.runner = sess
	ctx, cancel := context.WithCancel(context.Background())
	e.cancel = cancel
	t.Cleanup(cancel)
	byPort := map[int]string{}
	for surface, port := range bridgePorts {
		byPort[port] = strings.TrimPrefix(e.backends[surface].URL, "http://")
	}
	go func() {
		for {
			in, err := sess.Accept(ctx)
			if err != nil {
				return
			}
			addr, ok := byPort[in.Port]
			if in.SessionID != sessionID || !ok {
				in.Reject(tunnel.ResetRefused, "not this session's port")
				continue
			}
			go func() {
				tcp, err := net.Dial("tcp", addr)
				if err != nil {
					in.Reject(tunnel.ResetDialFailed, err.Error())
					return
				}
				st, err := in.Accept()
				if err != nil {
					tcp.Close()
					return
				}
				pipe(st, tcp)
			}()
		}
	}()
	eventually(t, "the machine in the registry", func() bool { _, ok := e.server.Registry().Machine(env); return ok })
	return sess
}

func pipe(st *tunnel.Stream, tcp net.Conn) {
	done := make(chan struct{}, 2)
	go func() { io.Copy(tcp, st); tcp.(*net.TCPConn).CloseWrite(); done <- struct{}{} }()
	go func() { io.Copy(st, tcp); st.CloseWrite(); done <- struct{}{} }()
	<-done
	<-done
	tcp.Close()
	st.Close()
}

// route tells the relay, by a signal, what the platform would.
func (e *edgeHarness) route(env, sessionID int64, token string) {
	e.t.Helper()
	e.signal(map[string]any{"type": "machine_session", "environment_id": env, "session_id": sessionID, "route_token": token, "ports": bridgePorts})
}

func (e *edgeHarness) signal(msg map[string]any) {
	e.t.Helper()
	payload, _ := json.Marshal(msg)
	if err := e.server.HandleSignal(payload, time.Now()); err != nil {
		e.t.Fatalf("signal %s: %v", payload, err)
	}
}

func (e *edgeHarness) get(path string, sessionHeader string, extra ...string) (*http.Response, string) {
	e.t.Helper()
	req, _ := http.NewRequest(http.MethodGet, e.http.URL+path, nil)
	if sessionHeader != "" {
		req.Header.Set("X-Session-Id", sessionHeader)
	}
	for i := 0; i+1 < len(extra); i += 2 {
		req.Header.Set(extra[i], extra[i+1])
	}
	resp, err := (&http.Client{Timeout: 5 * time.Second}).Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp, string(body)
}

func TestTheEdgeRoutesBySurfaceAndStripsThePathExceptForTheIDE(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	for _, tc := range []struct{ path, want string }{
		{"/t/" + tokenA + "/tty/term", "tty /term"},
		{"/t/" + tokenA + "/view/a/b%20c", "view /a/b c"},
		{"/t/" + tokenA + "/fs/files?x=1", "fs /files"},
		{"/t/" + tokenA + "/upload/", "upload /"},
		{"/t/" + tokenA + "/tty", "tty /"},
		{"/t/" + tokenA + "/ide/stable-abc/static/main.js", "ide /t/" + tokenA + "/ide/stable-abc/static/main.js"},
	} {
		resp, body := e.get(tc.path, "123")
		if resp.StatusCode != 200 || body != tc.want {
			t.Errorf("GET %s = %d %q, want %q", tc.path, resp.StatusCode, body, tc.want)
		}
	}
}

func TestTheEdgeKeepsTheQueryAndTheForwardedHeadersAndDropsTheIdentityHeaders(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	resp, _ := e.get("/t/"+tokenA+"/fs/list?dir=src", "123",
		"X-User-Id", "9", "X-Forwarded-For", "203.0.113.5", "X-Forwarded-Proto", "https", "Cookie", "vscode-tkn=abc",
		"X-Forwarded-Host", "app.example.com")
	if resp.StatusCode != 200 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	got := <-e.seen
	if got.Path != "/list?dir=src" {
		t.Errorf("path = %q", got.Path)
	}
	if got.Header.Get("X-Session-Id") != "" || got.Header.Get("X-User-Id") != "" {
		t.Errorf("identity headers reached the port: %v", got.Header)
	}
	if got.Header.Get("X-Forwarded-For") != "203.0.113.5" || got.Header.Get("X-Forwarded-Proto") != "https" ||
		got.Header.Get("X-Forwarded-Host") != "app.example.com" || got.Header.Get("Cookie") != "vscode-tkn=abc" {
		t.Errorf("headers = %v", got.Header)
	}
	if !strings.HasPrefix(got.Host, "127.0.0.1:") {
		t.Errorf("the Host header is the browser's request's: %q", got.Host)
	}
}

func TestTheEdgeRefusesWhatIsNotARoute(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	for _, path := range []string{
		"/t/", "/t/" + tokenA, "/t/" + tokenA + "/", "/t/" + tokenA + "/shell/x", "/t/" + tokenA + "/TTY/x",
		"/t/short/tty/x", "/t/not a token!!!!!!!!!!!!!!!!!!!!!/tty/x",
	} {
		resp, _ := e.get(path, "123")
		if resp.StatusCode != 404 {
			t.Errorf("GET %s = %d, want 404", path, resp.StatusCode)
		}
	}
	if e.rails.hits() != 0 {
		t.Errorf("a malformed path reached the platform %d times", e.rails.hits())
	}
}

func TestAStrangerTokenIs404AfterOneHoldersCall(t *testing.T) {
	e := newEdgeHarness(t)
	resp, _ := e.get("/t/"+tokenB+"/tty/ws", "1")
	if resp.StatusCode != 404 {
		t.Fatalf("status %d", resp.StatusCode)
	}
	if e.rails.hits() != 1 {
		t.Fatalf("holders called %d times", e.rails.hits())
	}
}

func TestAMissIsResolvedByHoldersOnceAndRemembered(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	env := int64(42)
	e.rails.holders[tokenA] = rails.Holder{SessionID: 123, EnvironmentID: &env, State: "ready", Ports: bridgePorts}

	for i := 0; i < 2; i++ {
		resp, body := e.get("/t/"+tokenA+"/tty/x", "123")
		if resp.StatusCode != 200 || body != "tty /x" {
			t.Fatalf("round %d: %d %q", i, resp.StatusCode, body)
		}
	}
	if e.rails.hits() != 1 {
		t.Fatalf("holders called %d times, want 1", e.rails.hits())
	}
}

func TestTheEdgeChecksTheSessionHeaderAgainstTheToken(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	for _, header := range []string{"", "124", "abc", "0123"} {
		resp, _ := e.get("/t/"+tokenA+"/tty/x", header)
		if resp.StatusCode != 403 {
			t.Errorf("X-Session-Id %q = %d, want 403", header, resp.StatusCode)
		}
	}
	select {
	case got := <-e.seen:
		t.Fatalf("a refused request reached the port: %v", got)
	default:
	}
}

func TestADisconnectedMachineIs503WithRetryAfter(t *testing.T) {
	e := newEdgeHarness(t)
	// The platform says machine 42 holds session 123, and no connection of 42 is here.
	e.route(42, 123, tokenA)

	resp, _ := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 503 || resp.Header.Get("Retry-After") != "2" {
		t.Fatalf("status %d, Retry-After %q", resp.StatusCode, resp.Header.Get("Retry-After"))
	}
}

func TestASessionNoMachineHoldsIs503WithRetryAfter(t *testing.T) {
	e := newEdgeHarness(t)
	e.rails.holders[tokenA] = rails.Holder{SessionID: 123, EnvironmentID: nil, State: "ready"}

	resp, _ := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 503 || resp.Header.Get("Retry-After") != "2" {
		t.Fatalf("status %d, Retry-After %q", resp.StatusCode, resp.Header.Get("Retry-After"))
	}
}

func TestAPlatformOutageOnAMissIs503NotA404(t *testing.T) {
	e := newEdgeHarness(t)
	e.rails.holderErr = errors.New("connection refused")

	resp, _ := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 503 || resp.Header.Get("Retry-After") != "2" {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

func TestAPortThatDoesNotAnswerIs502(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.backends["tty"].Close()
	e.route(42, 123, tokenA)

	resp, _ := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 502 {
		t.Fatalf("status %d, want 502", resp.StatusCode)
	}
	if got := testutil.ToFloat64(e.metrics.StreamResets.WithLabelValues("dial_failed")); got != 1 {
		t.Fatalf("dial_failed resets = %v", got)
	}
}

func TestAPortOutsideTheRunnersSessionIsRefusedByTheRunner(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	// The platform names a session the runner does not hold: the runner's own check answers.
	e.route(42, 999, tokenA)

	resp, _ := e.get("/t/"+tokenA+"/tty/x", "999")
	if resp.StatusCode != 502 {
		t.Fatalf("status %d, want 502", resp.StatusCode)
	}
	if got := testutil.ToFloat64(e.metrics.StreamResets.WithLabelValues("refused")); got != 1 {
		t.Fatalf("refused resets = %v", got)
	}
}

func TestAWebSocketThroughTheEdge(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	url := "ws" + strings.TrimPrefix(e.http.URL, "http") + "/t/" + tokenA + "/view/ws"
	c, _, err := websocket.Dial(ctx, url, &websocket.DialOptions{HTTPHeader: http.Header{"X-Session-Id": {"123"}}})
	if err != nil {
		t.Fatal(err)
	}
	defer c.CloseNow()
	if err := c.Write(ctx, websocket.MessageText, []byte("hello")); err != nil {
		t.Fatal(err)
	}
	_, data, err := c.Read(ctx)
	if err != nil || string(data) != "view:hello" {
		t.Fatalf("got %q, %v", data, err)
	}
	if got := testutil.ToFloat64(e.metrics.StreamsOpen.WithLabelValues("view")); got != 1 {
		t.Fatalf("streams_open{view} = %v", got)
	}
	c.Close(websocket.StatusNormalClosure, "")
	eventually(t, "the stream to be released", func() bool {
		return testutil.ToFloat64(e.metrics.StreamsOpen.WithLabelValues("view")) == 0
	})
}

// open starts a request that the backend holds open, and returns when its headers are in.
func (e *edgeHarness) open(token, surface string, sessionID int64) (*http.Response, error) {
	req, _ := http.NewRequest(http.MethodGet, e.http.URL+"/t/"+token+"/"+surface+"/block", nil)
	req.Header.Set("X-Session-Id", strconv.FormatInt(sessionID, 10))
	return (&http.Client{}).Do(req)
}

// readEnds says whether reading the body stops, which is how a closed browser
// connection looks to the browser.
func readEnds(body io.Reader) bool {
	done := make(chan struct{})
	go func() { io.Copy(io.Discard, body); close(done) }()
	select {
	case <-done:
		return true
	case <-time.After(3 * time.Second):
		return false
	}
}

func TestAMachineSessionSignalResetsThePreviousSessionsStreams(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	m, _ := e.server.Registry().Machine(42)
	if m.OpenStreams(123) != 1 {
		t.Fatalf("open streams = %d", m.OpenStreams(123))
	}

	// Session 124 takes the machine.
	e.route(42, 124, tokenB)

	if !readEnds(resp.Body) {
		t.Fatal("the browser's connection stayed open")
	}
	eventually(t, "the stream to be gone", func() bool { return m.OpenStreams(123) == 0 })
	if got := testutil.ToFloat64(e.metrics.StreamResets.WithLabelValues("session_changed")); got != 1 {
		t.Fatalf("session_changed resets = %v", got)
	}
	// The old token no longer names a session this machine holds; the new one does.
	if _, ok := e.server.Registry().ByRouteToken(tokenA); ok {
		t.Error("the old token is still routed")
	}
	if r, ok := e.server.Registry().ByRouteToken(tokenB); !ok || r.SessionID != 124 || r.EnvironmentID != 42 {
		t.Errorf("the new token: %+v %v", r, ok)
	}
	// The machine's connection stays: a session change is not a revocation.
	select {
	case <-e.runner.Done():
		t.Fatal("the connection closed")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestAMachineSessionSignalWithNoSessionReleasesTheMachine(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	e.signal(map[string]any{"type": "machine_session", "environment_id": 42, "session_id": nil, "route_token": nil, "ports": nil})

	if !readEnds(resp.Body) {
		t.Fatal("the browser's connection stayed open")
	}
	if _, ok := e.server.Registry().Session(42); ok {
		t.Error("the machine still holds a session")
	}
}

func TestSessionEndedResetsItsStreamsWithRevokedAndClosesTheBrowsersConnections(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	var responses []*http.Response
	for _, surface := range []string{"tty", "view", "ide"} {
		resp, err := e.open(tokenA, surface, 123)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		responses = append(responses, resp)
	}

	e.signal(map[string]any{"type": "session_ended", "session_id": 123})

	for i, resp := range responses {
		if !readEnds(resp.Body) {
			t.Errorf("connection %d stayed open", i)
		}
	}
	if got := testutil.ToFloat64(e.metrics.StreamResets.WithLabelValues("revoked")); got != 3 {
		t.Fatalf("revoked resets = %v, want 3", got)
	}
	// The machine's connection is not touched, and the session is no longer routed.
	if _, ok := e.server.Registry().ByRouteToken(tokenA); ok {
		t.Error("the token is still routed")
	}
	select {
	case <-e.runner.Done():
		t.Fatal("the connection closed")
	default:
	}
}

func TestSessionEndedForAnotherSessionTouchesNothing(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	e.signal(map[string]any{"type": "session_ended", "session_id": 999})

	m, _ := e.server.Registry().Machine(42)
	if m.OpenStreams(123) != 1 {
		t.Fatal("the stream of another session was reset")
	}
}

func TestMachineRevokedClosesTheConnectionWith4001(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	e.signal(map[string]any{"type": "machine_revoked", "environment_id": 42})

	select {
	case <-e.runner.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the connection stayed open")
	}
	var closed *tunnel.CloseError
	if !errors.As(e.runner.Err(), &closed) || closed.Code != tunnel.CloseRevoked {
		t.Fatalf("the runner saw %v, want close code 4001", e.runner.Err())
	}
	if !readEnds(resp.Body) {
		t.Fatal("the browser's connection stayed open")
	}
	eventually(t, "the machine to leave the registry", func() bool { return e.server.Registry().Len() == 0 })
	if _, ok := e.server.Registry().ByRouteToken(tokenA); ok {
		t.Error("the revoked machine's session is still routed")
	}
}

func TestMachineRevokedForAnotherMachineTouchesNothing(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.signal(map[string]any{"type": "machine_revoked", "environment_id": 43})
	select {
	case <-e.runner.Done():
		t.Fatal("the connection closed")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestSignalsOfTheWrongShapeAreRefusedAndChangeNothing(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)

	for _, payload := range []string{
		`not json`,
		`{"type":"machine_session","environment_id":"42","session_id":124,"route_token":"` + tokenB + `","ports":{}}`,
		`{"type":"machine_session","environment_id":42,"session_id":124,"route_token":"x","ports":{"tty":1,"view":2}}`,
		`{"type":"machine_session","environment_id":42,"session_id":124,"route_token":null,"ports":null}`,
		`{"type":"machine_session","environment_id":42,"session_id":124,"route_token":"` + tokenB + `","ports":{"tty":"7681"}}`,
		`{"type":"session_ended"}`,
		`{"type":"machine_revoked","environment_id":null}`,
		`{"type":"session_ended","session_id":1.5}`,
	} {
		if err := e.server.HandleSignal([]byte(payload), time.Now()); err == nil {
			t.Errorf("%s was accepted", payload)
		}
	}
	if r, ok := e.server.Registry().Session(42); !ok || r.SessionID != 123 {
		t.Fatalf("the machine's session changed: %+v", r)
	}
	// A type of a newer platform is ignored, and a field this version does not know is too.
	if err := e.server.HandleSignal([]byte(`{"type":"something_new","x":1}`), time.Now()); err != nil {
		t.Errorf("an unknown type: %v", err)
	}
	if err := e.server.HandleSignal([]byte(`{"type":"session_ended","session_id":5,"extra":true}`), time.Now()); err != nil {
		t.Errorf("an unknown field: %v", err)
	}
}

// -- The reconcile pass ------------------------------------------------------

func TestAReconcilePassClosesWhatThePlatformDoesNotConfirm(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	// The platform ended the session and the signal was lost: the check says false.
	e.rails.checks = func(m []rails.Machine) ([]bool, error) { return make([]bool, len(m)), nil }

	if err := e.server.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}

	if !readEnds(resp.Body) {
		t.Fatal("the browser's connection stayed open")
	}
	select {
	case <-e.runner.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the machine's connection stayed open")
	}
	if got := testutil.ToFloat64(e.metrics.ReconcileRevocations); got != 1 {
		t.Fatalf("reconcile revocations = %v", got)
	}
	// One request, with the machine and the session the relay believed it held.
	if len(e.rails.checkCalls) != 1 || len(e.rails.checkCalls[0]) != 1 ||
		e.rails.checkCalls[0][0].EnvironmentID != 42 || *e.rails.checkCalls[0][0].SessionID != 123 {
		t.Fatalf("checks: %+v", e.rails.checkCalls)
	}
}

func TestAReconcilePassLeavesWhatThePlatformConfirms(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if err := e.server.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	m, _ := e.server.Registry().Machine(42)
	if m.OpenStreams(123) != 1 {
		t.Fatal("a confirmed stream was reset")
	}
	if got := testutil.ToFloat64(e.metrics.ReconcileRevocations); got != 0 {
		t.Fatalf("reconcile revocations = %v", got)
	}
}

func TestAReconcilePassSendsOnlyMachinesThatHoldASession(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	idle := e.connect(e.ticket(43, nil))
	_ = idle
	eventually(t, "both machines", func() bool { return e.server.Registry().Len() == 2 })

	if err := e.server.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(e.rails.checkCalls) != 1 || len(e.rails.checkCalls[0]) != 1 || e.rails.checkCalls[0][0].EnvironmentID != 42 {
		t.Fatalf("checks: %+v", e.rails.checkCalls)
	}
}

func TestAReconcilePassThatRailsDoesNotAnswerClosesNothing(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	resp, err := e.open(tokenA, "tty", 123)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	e.rails.checks = func([]rails.Machine) ([]bool, error) { return nil, errors.New("connection refused") }

	if err := e.server.Reconcile(context.Background()); err == nil {
		t.Fatal("want the error")
	}
	m, _ := e.server.Registry().Machine(42)
	if m.OpenStreams(123) != 1 {
		t.Fatal("a stream was reset because Rails did not answer")
	}
	select {
	case <-e.runner.Done():
		t.Fatal("the connection closed because Rails did not answer")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestAReconcileAnswerThatCameAfterASignalChangedTheSessionIsDropped(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	// While the call is out, session 124 takes the machine.
	e.rails.checks = func(m []rails.Machine) ([]bool, error) {
		e.route(42, 124, tokenB)
		return make([]bool, len(m)), nil
	}
	if err := e.server.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	select {
	case <-e.runner.Done():
		t.Fatal("the machine was closed on an answer about a session it no longer holds")
	case <-time.After(100 * time.Millisecond):
	}
	if got := testutil.ToFloat64(e.metrics.ReconcileRevocations); got != 0 {
		t.Fatalf("reconcile revocations = %v", got)
	}
}

func TestAnInvalidChecksRequestRevokesNothing(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	e.rails.checks = func([]rails.Machine) ([]bool, error) { return nil, rails.ErrInvalid }

	if err := e.server.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	select {
	case <-e.runner.Done():
		t.Fatal("the connection closed")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestTheReconcileLoopRunsOnItsIntervalAndRetriesAfterAnOutage(t *testing.T) {
	e := newEdgeHarness(t, func(o *Options) { o.CheckInterval = 50 * time.Millisecond })
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go e.server.RunReconciler(ctx)

	eventually(t, "two passes", func() bool { return e.rails.calls() >= 2 })
	if err := e.server.Ready(ctx); err != nil {
		t.Fatalf("not ready: %v", err)
	}

	// A signal is lost: the platform now says false, and the next pass closes the machine.
	e.rails.mu.Lock()
	e.rails.checks = func(m []rails.Machine) ([]bool, error) { return make([]bool, len(m)), nil }
	e.rails.mu.Unlock()
	select {
	case <-e.runner.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the loop did not close the machine")
	}
}

func TestReadyNeedsTheSubscriptionAndAFreshPass(t *testing.T) {
	e := newEdgeHarness(t, func(o *Options) { o.CheckInterval = 50 * time.Millisecond })
	if err := e.server.Ready(context.Background()); err != nil {
		t.Fatalf("a relay with neither part started: %v", err)
	}
	e.server.signalsExpected.Store(true)
	if err := e.server.Ready(context.Background()); err == nil {
		t.Fatal("ready without a subscription")
	}
	e.server.subscribed.Store(true)
	e.server.reconcileExpected.Store(true)
	if err := e.server.Ready(context.Background()); err == nil {
		t.Fatal("ready before the first pass")
	}
	e.server.lastPass.Store(time.Now().UnixNano())
	if err := e.server.Ready(context.Background()); err != nil {
		t.Fatalf("not ready: %v", err)
	}
	e.server.lastPass.Store(time.Now().Add(-200 * time.Millisecond).UnixNano())
	if err := e.server.Ready(context.Background()); err == nil {
		t.Fatal("ready with a pass older than three intervals")
	}
}

func TestTheReplacedMachineKeepsTheSessionForTheNewConnection(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	// The same machine reconnects.
	old := e.runner
	e.machine(42, 123)
	select {
	case <-old.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the old connection stayed open")
	}
	resp, body := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 200 || body != "tty /x" {
		t.Fatalf("%d %q", resp.StatusCode, body)
	}
}
