package proxy

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

// gateway is a fake of the runner gateway's proxy route and token endpoint.
type gateway struct {
	mu       sync.Mutex
	requests []*http.Request
	bodies   []string
	// answer answers a proxy request; nil echoes it.
	answer func(w http.ResponseWriter, r *http.Request)
	// refuse refuses the first n proxy requests with invalid_token.
	refuse int
}

func (g *gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/runner/v1/token" {
		w.Header().Set("Content-Type", "application/json")
		exp := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"access_token": "aracc_fresh", "access_token_expires_at": exp,
			"refresh_token": "arref_fresh", "refresh_token_expires_at": exp,
		})
		return
	}
	body, _ := io.ReadAll(r.Body)
	g.mu.Lock()
	g.requests = append(g.requests, r.Clone(context.Background()))
	g.bodies = append(g.bodies, string(body))
	refuse := g.refuse > 0
	if refuse {
		g.refuse--
	}
	answer := g.answer
	g.mu.Unlock()
	if refuse {
		WriteRefusal(w, http.StatusUnauthorized, "invalid_token", "The token is unknown, used, revoked or expired.")
		return
	}
	if answer != nil {
		answer(w, r)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Mcp-Session-Id", "abc")
	w.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprintf(w, `{"path":%q,"query":%q}`, r.URL.EscapedPath(), r.URL.RawQuery)
}

func (g *gateway) last(t *testing.T) (*http.Request, string) {
	t.Helper()
	g.mu.Lock()
	defer g.mu.Unlock()
	if len(g.requests) == 0 {
		t.Fatal("the gateway got no request")
	}
	return g.requests[len(g.requests)-1], g.bodies[len(g.bodies)-1]
}

func (g *gateway) count() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return len(g.requests)
}

type memoryStore struct{}

func (memoryStore) Save(credentials.Credentials) error { return nil }
func (memoryStore) Delete() error                      { return nil }

// newRelay is a relay to a fake gateway, with a real token source.
func newRelay(t *testing.T, g *gateway) *Relay {
	t.Helper()
	server := httptest.NewServer(g)
	t.Cleanup(server.Close)
	client, err := protocol.NewClient(server.URL, "1.4.0", nil)
	if err != nil {
		t.Fatal(err)
	}
	exp := time.Now().Add(time.Hour)
	creds := credentials.Credentials{URL: server.URL, TokenPair: protocol.TokenPair{
		AccessToken: "aracc_machine", AccessTokenExpiresAt: exp, RefreshToken: "arref_machine", RefreshTokenExpiresAt: exp,
	}}
	return &Relay{Gateway: client, Tokens: tokens.NewSource(memoryStore{}, client, creds), Logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
}

func TestTheRelaySendsTheAgentsRequestToTheProxyRouteWithTheMachinesToken(t *testing.T) {
	g := &gateway{}
	relay := httptest.NewServer(newRelay(t, g))
	defer relay.Close()

	req, _ := http.NewRequest(http.MethodPost, relay.URL+"/runner/v1/proxy/assets/store/a%20b.json?x=1", strings.NewReader(`{"jsonrpc":"2.0"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Session-Key", "the-session-key")
	req.Header.Set("Authorization", "Bearer the-agents-own")
	req.Header.Set("X-Aixle-Runner-Environment", "spoofed")
	req.Header.Set("Connection", "keep-alive, X-Hop")
	req.Header.Set("X-Hop", "dropped")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	got, sent := g.last(t)
	if got.Method != http.MethodPost || got.URL.EscapedPath() != "/runner/v1/proxy/assets/store/a%20b.json" || got.URL.RawQuery != "x=1" {
		t.Fatalf("the gateway got %s %s?%s", got.Method, got.URL.EscapedPath(), got.URL.RawQuery)
	}
	if got.Header.Get("Authorization") != "Bearer aracc_machine" {
		t.Fatalf("Authorization %q: the machine's token, never the agent's", got.Header.Get("Authorization"))
	}
	if got.Header.Get("X-Aixle-Runner-Protocol") != "1" || got.Header.Get("X-Aixle-Runner-Version") != "1.4.0" {
		t.Fatalf("protocol headers %v", got.Header)
	}
	if got.Header.Get("X-Session-Key") != "the-session-key" || got.Header.Get("Content-Type") != "application/json" || sent != `{"jsonrpc":"2.0"}` {
		t.Fatalf("the agent's request was changed: %v %s", got.Header, sent)
	}
	if got.Header.Get("X-Aixle-Runner-Environment") != "" || got.Header.Get("X-Hop") != "" {
		t.Fatalf("headers that must not pass passed: %v", got.Header)
	}
	if resp.StatusCode != http.StatusOK || resp.Header.Get("Mcp-Session-Id") != "abc" || !strings.Contains(string(body), "store/a%20b.json") {
		t.Fatalf("the answer %d %v %s", resp.StatusCode, resp.Header, body)
	}
}

func TestTheRelayRefreshesOnceOnInvalidTokenAndSendsTheSameRequestAgain(t *testing.T) {
	g := &gateway{refuse: 1}
	relay := httptest.NewServer(newRelay(t, g))
	defer relay.Close()

	resp, err := http.Post(relay.URL+"/runner/v1/proxy/git-credentials", "application/json", strings.NewReader(`{"url":"x"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	got, sent := g.last(t)
	if resp.StatusCode != http.StatusOK || g.count() != 2 || got.Header.Get("Authorization") != "Bearer aracc_fresh" || sent != `{"url":"x"}` {
		t.Fatalf("status %d after %d requests, %q, %q", resp.StatusCode, g.count(), got.Header.Get("Authorization"), sent)
	}
}

func TestTheRelayPassesTheGatewaysRefusalOnAsItIs(t *testing.T) {
	g := &gateway{answer: func(w http.ResponseWriter, _ *http.Request) {
		WriteRefusal(w, http.StatusForbidden, "session_not_on_environment", "The request carries no key of the session this machine runs now.")
	}}
	relay := httptest.NewServer(newRelay(t, g))
	defer relay.Close()

	resp, err := http.Post(relay.URL+"/runner/v1/proxy/mcp", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	var refusal map[string]string
	_ = json.NewDecoder(resp.Body).Decode(&refusal)
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden || resp.Header.Get(protocol.RefusalHeader) != "session_not_on_environment" || refusal["error"] != "session_not_on_environment" {
		t.Fatalf("%d %v %v", resp.StatusCode, resp.Header, refusal)
	}
}

func TestTheRelayPassesTheEndpointsOwnErrorOnAsItIs(t *testing.T) {
	g := &gateway{answer: func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = io.WriteString(w, `{"jsonrpc":"2.0","error":{"code":-32000}}`)
	}}
	relay := httptest.NewServer(newRelay(t, g))
	defer relay.Close()

	resp, err := http.Post(relay.URL+"/runner/v1/proxy/mcp", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	// Not a refusal of the gateway, so no refresh and no retry.
	if resp.StatusCode != http.StatusUnauthorized || string(body) != `{"jsonrpc":"2.0","error":{"code":-32000}}` || g.count() != 1 {
		t.Fatalf("%d %s after %d requests", resp.StatusCode, body, g.count())
	}
}

func TestTheRelayServesOnlyTheProxyRoute(t *testing.T) {
	g := &gateway{}
	relay := httptest.NewServer(newRelay(t, g))
	defer relay.Close()

	for _, path := range []string{"/runner/v1/ops?after=0&wait=0", "/runner/v1/token", "/runner/v1/check-in", "/mcp", "/runner/v1/proxy"} {
		resp, err := http.Post(relay.URL+path, "application/json", strings.NewReader(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound || resp.Header.Get(protocol.RefusalHeader) != ClassNotProxied {
			t.Errorf("%s: %d %v", path, resp.StatusCode, resp.Header)
		}
	}
	if g.count() != 0 {
		t.Fatalf("the gateway got %d requests", g.count())
	}
}

func TestTheRelayAnswersRelayFailedWhenTheGatewayIsDown(t *testing.T) {
	r := newRelay(t, &gateway{})
	down, _ := protocol.NewClient("http://127.0.0.1:1", "1.4.0", nil)
	r.Gateway = down
	relay := httptest.NewServer(r)
	defer relay.Close()

	resp, err := http.Post(relay.URL+"/runner/v1/proxy/mcp", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway || resp.Header.Get(protocol.RefusalHeader) != ClassRelayFailed {
		t.Fatalf("%d %v", resp.StatusCode, resp.Header)
	}
}

// startSidecar runs the sidecar against the session's socket of a Host.
func startSidecar(t *testing.T, socket string) string {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	ready := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- RunSidecar(ctx, SidecarOptions{Socket: socket, Listen: "127.0.0.1:0", Ready: ready,
			Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	}()
	t.Cleanup(func() {
		cancel()
		if err := <-done; err != nil {
			t.Errorf("the sidecar ended with %v", err)
		}
	})
	select {
	case address := <-ready:
		return address
	case err := <-done:
		t.Fatalf("the sidecar did not start: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("the sidecar did not start")
	}
	return ""
}

func socketHost(t *testing.T, relay http.Handler) *Host {
	t.Helper()
	// A short path: a Unix socket's path is at most 108 bytes.
	dir, err := os.MkdirTemp("", "ar")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	h := NewHost(dir, "/usr/local/bin/aixle-runner", relay, slog.New(slog.NewTextHandler(io.Discard, nil)))
	t.Cleanup(h.Stop)
	return h
}

func TestTheSidecarRelaysTheAgentsCallsThroughTheHostRunnersSocket(t *testing.T) {
	g := &gateway{}
	host := socketHost(t, newRelay(t, g))
	dir, err := host.OpenSocket(123)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(dir, SocketName))
	if err != nil || info.Mode().Perm() != 0o666 || info.Mode()&os.ModeSocket == 0 {
		t.Fatalf("the socket %v, %v", info, err)
	}
	if d, _ := os.Stat(dir); d.Mode().Perm() != 0o755 {
		t.Fatalf("the socket directory is %v", d.Mode())
	}

	address := startSidecar(t, filepath.Join(dir, SocketName))
	req, _ := http.NewRequest(http.MethodPost, "http://"+address+"/mcp?probe=1", strings.NewReader(`{"method":"tools/list"}`))
	req.Header.Set("X-Session-Key", "the-session-key")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()

	got, sent := g.last(t)
	if got.URL.Path != "/runner/v1/proxy/mcp" || got.URL.RawQuery != "probe=1" || sent != `{"method":"tools/list"}` {
		t.Fatalf("the gateway got %s?%s %s", got.URL.Path, got.URL.RawQuery, sent)
	}
	if got.Header.Get("Authorization") != "Bearer aracc_machine" || got.Header.Get("X-Session-Key") != "the-session-key" {
		t.Fatalf("headers %v", got.Header)
	}
	if got.Header.Get("X-Forwarded-For") != "" {
		t.Fatalf("the sidecar added X-Forwarded-For: %v", got.Header)
	}
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), "/runner/v1/proxy/mcp") {
		t.Fatalf("%d %s", resp.StatusCode, body)
	}

	// A restarted host runner replaces the socket in the same directory, which a
	// running sidecar has mounted: the sidecar reaches the new one.
	if _, err := host.OpenSocket(123); err != nil {
		t.Fatal(err)
	}
	resp, err = http.Post("http://"+address+"/git-credentials", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("after the socket was replaced: %d", resp.StatusCode)
	}

	host.Close(123)
	if _, err := os.Stat(dir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the socket directory is left: %v", err)
	}
	resp, err = http.Post("http://"+address+"/mcp", "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway || resp.Header.Get(protocol.RefusalHeader) != ClassRelayFailed {
		t.Fatalf("with the relay closed: %d %v", resp.StatusCode, resp.Header)
	}
}

func TestTheProxyStreamsTheAnswerAsItComes(t *testing.T) {
	second := make(chan struct{})
	g := &gateway{answer: func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(w, "data: first\n\n")
		w.(http.Flusher).Flush()
		<-second
		_, _ = io.WriteString(w, "data: second\n\n")
	}}
	host := socketHost(t, newRelay(t, g))
	dir, err := host.OpenSocket(1)
	if err != nil {
		t.Fatal(err)
	}
	address := startSidecar(t, filepath.Join(dir, SocketName))

	resp, err := http.Get("http://" + address + "/mcp")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	reader := bufio.NewReader(resp.Body)
	line, err := reader.ReadString('\n')
	if err != nil || line != "data: first\n" {
		t.Fatalf("the first event did not arrive before the answer ended: %q %v", line, err)
	}
	close(second)
	rest, _ := io.ReadAll(reader)
	if !strings.Contains(string(rest), "data: second") || resp.Header.Get("Content-Type") != "text/event-stream" {
		t.Fatalf("%q %v", rest, resp.Header)
	}
}

func TestTheHostListenerServesANetworkHostSession(t *testing.T) {
	g := &gateway{}
	host := socketHost(t, newRelay(t, g))
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := probe.Addr().(*net.TCPAddr).Port
	probe.Close()

	if err := host.OpenListener(7, port); err != nil {
		t.Fatal(err)
	}
	resp, err := http.Post(fmt.Sprintf("http://127.0.0.1:%d/cloud-credentials", port), "application/json", strings.NewReader(`{}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got, _ := g.last(t); resp.StatusCode != http.StatusOK || got.URL.Path != "/runner/v1/proxy/cloud-credentials" {
		t.Fatalf("%d %s", resp.StatusCode, got.URL.Path)
	}

	// The port is the session's: a second listener on it is refused.
	err = NewHost(t.TempDir(), "", g, nil).OpenListener(8, port)
	if !errors.Is(err, syscall.EADDRINUSE) {
		t.Fatalf("a taken port answered %v", err)
	}

	host.Close(7)
	if _, err := http.Post(fmt.Sprintf("http://127.0.0.1:%d/mcp", port), "application/json", strings.NewReader(`{}`)); err == nil {
		t.Fatal("the listener still answers after Close")
	}
}
