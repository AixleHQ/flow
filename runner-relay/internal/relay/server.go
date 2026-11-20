// Package relay is the service's tunnel endpoint: the `GET /runner/v1/tunnel`
// upgrade, the registry of connected machines, and the drain
// (docs/design/agent-runtimes/runner-relay.md §3.1, §5.3, §5.4).
package relay

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/aixlehq/aixle-runner-relay/internal/ticket"
	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

const (
	// Path is the runner's entry point.
	Path = "/runner/v1/tunnel"
	// Subprotocol is the WebSocket subprotocol of relay protocol 1.
	Subprotocol = "aixle-runner-relay.v1"

	protocolHeader = "X-Aixle-Runner-Protocol"
	versionHeader  = "X-Aixle-Runner-Version"
	// closeInternal is the WebSocket code for a failure of the relay's own.
	closeInternal  = 1011
	closeGoingAway = 1001
)

// semver is Semantic Versioning 2.0's own expression, the check the gateway makes of
// X-Aixle-Runner-Version.
var semver = regexp.MustCompile(`^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)` +
	`(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?` +
	`(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$`)

// Options configure a Server.
type Options struct {
	Verifier *ticket.Verifier
	Guard    ticket.Guard
	Metrics  *Metrics
	Logger   *slog.Logger

	// The limits offered in HELLO (§5.3); zero takes the package's defaults.
	MaxFrame     int
	MaxStreams   int
	Window       int
	PingInterval time.Duration
	// HandshakeTimeout bounds the HELLO exchange; zero is 10 s.
	HandshakeTimeout time.Duration
	// GuardTimeout bounds the call to Redis that records a ticket id; zero is 3 s.
	GuardTimeout time.Duration
	// Clock is passed to the tunnel sessions; nil is the real one.
	Clock tunnel.Clock
}

// Server is the relay's tunnel endpoint.
type Server struct {
	opts     Options
	log      *slog.Logger
	registry *Registry
	metrics  *Metrics

	mu       sync.Mutex
	draining bool
	wg       sync.WaitGroup // one per connected machine, until its session ended
}

// New returns a Server.
func New(opts Options) *Server {
	if opts.Logger == nil {
		opts.Logger = slog.New(slog.NewJSONHandler(discard{}, nil))
	}
	if opts.Metrics == nil {
		opts.Metrics = NewMetrics()
	}
	if opts.HandshakeTimeout == 0 {
		opts.HandshakeTimeout = 10 * time.Second
	}
	if opts.GuardTimeout == 0 {
		opts.GuardTimeout = 3 * time.Second
	}
	return &Server{opts: opts, log: opts.Logger, registry: NewRegistry(), metrics: opts.Metrics}
}

type discard struct{}

func (discard) Write(p []byte) (int, error) { return len(p), nil }

// Registry is the connected machines.
func (s *Server) Registry() *Registry { return s.registry }

// Handler serves the tunnel upgrade.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET "+Path, s.upgrade)
	return mux
}

// Ready says whether the service takes new connections: Redis answers (a ticket
// cannot be accepted without it) and no drain is under way. It does not depend on
// Rails: a Rails outage must not take down the connections that are open.
func (s *Server) Ready(ctx context.Context) error {
	if s.Draining() {
		return errors.New("draining")
	}
	return s.opts.Guard.Ping(ctx)
}

// Draining says whether Drain was called.
func (s *Server) Draining() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.draining
}

// Drain stops taking connections and sends GOAWAY on every open one: the runners
// reconnect, and each connection closes when its last stream ended (§5.4). It is
// called on shutdown and from the admin port.
func (s *Server) Drain() {
	s.mu.Lock()
	s.draining = true
	s.mu.Unlock()
	for _, m := range s.registry.All() {
		if err := m.sess.GoAway(); err != nil {
			s.log.Debug("GOAWAY not sent", "environment_id", m.EnvironmentID, "error", err.Error())
		}
	}
}

// Wait returns when every connection has ended, or with ctx's error.
func (s *Server) Wait(ctx context.Context) error {
	done := make(chan struct{})
	go func() { s.wg.Wait(); close(done) }()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// CloseAll closes the connections that are left, with 1001 going away, and waits for
// their goroutines.
func (s *Server) CloseAll() {
	for _, m := range s.registry.All() {
		m.CloseWith(closeGoingAway, "relay shutting down")
	}
	s.wg.Wait()
}

func (s *Server) upgrade(w http.ResponseWriter, r *http.Request) {
	// The same order as the gateway's (PROTOCOL.md §3): the version headers, then the
	// credential. The subprotocol is part of the version.
	if r.Header.Get(protocolHeader) != "1" || !offers(r, Subprotocol) {
		s.refuse(w, ResultVersion, http.StatusBadRequest, "unsupported_protocol",
			"This relay speaks runner protocol 1 and the WebSocket subprotocol "+Subprotocol+". Update aixle-runner.")
		return
	}
	runnerVersion := r.Header.Get(versionHeader)
	if len(runnerVersion) > 255 || !semver.MatchString(runnerVersion) {
		s.refuse(w, ResultVersion, http.StatusBadRequest, "invalid_runner_version",
			"X-Aixle-Runner-Version must be a semantic version (SemVer 2.0).")
		return
	}
	token, ok := bearer(r)
	if !ok {
		s.refuse(w, ResultBadTicket, http.StatusUnauthorized, "invalid_ticket", "The ticket is missing, malformed, forged or expired.")
		return
	}
	claims, err := s.opts.Verifier.Verify(token)
	if err != nil {
		s.refuse(w, ResultBadTicket, http.StatusUnauthorized, "invalid_ticket", "The ticket is missing, malformed, forged or expired.")
		return
	}
	if s.Draining() {
		w.Header().Set("Retry-After", "2")
		s.refuse(w, ResultUnavailable, http.StatusServiceUnavailable, "unavailable", "The relay is restarting. Try again.")
		return
	}
	// Single use. Redis down is no refusal of the ticket: no connection is accepted
	// without the record (§3.1), and the runner backs off and mints a new ticket.
	gctx, cancel := context.WithTimeout(r.Context(), s.opts.GuardTimeout)
	fresh, err := s.opts.Guard.Claim(gctx, claims.ID)
	cancel()
	if err != nil {
		s.log.Error("recording a ticket id failed", "environment_id", claims.EnvironmentID, "error", err.Error())
		w.Header().Set("Retry-After", "2")
		s.refuse(w, ResultUnavailable, http.StatusServiceUnavailable, "unavailable", "The relay cannot take connections now. Try again.")
		return
	}
	if !fresh {
		s.refuse(w, ResultReplayed, http.StatusForbidden, "ticket_replayed", "The ticket was used already.")
		return
	}

	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{Subprotocols: []string{Subprotocol}})
	if err != nil {
		// Accept answered the request itself.
		s.metrics.TunnelConnects.WithLabelValues(ResultHandshake).Inc()
		s.log.Warn("the WebSocket upgrade failed", "environment_id", claims.EnvironmentID, "error", err.Error())
		return
	}
	s.serve(r.Context(), c, claims, runnerVersion)
}

// serve runs one machine's connection until its session ends.
func (s *Server) serve(ctx context.Context, c *websocket.Conn, claims ticket.Claims, runnerVersion string) {
	conn := tunnel.NewWSConn(c)
	cfg := tunnel.Config{
		MaxFrame: s.opts.MaxFrame, MaxStreams: s.opts.MaxStreams, Window: s.opts.Window,
		PingInterval: s.opts.PingInterval, Clock: s.opts.Clock, Logger: s.log,
	}
	m := &Machine{
		EnvironmentID: claims.EnvironmentID, RunnerID: claims.RunnerID, RunnerVersion: runnerVersion,
		ConnectedAt: time.Now(), conn: conn,
	}
	if claims.SessionID != nil {
		m.SessionID = *claims.SessionID
		cfg.SessionID = *claims.SessionID
	}
	m.sess = tunnel.NewRelay(conn, cfg)
	log := s.log.With("environment_id", m.EnvironmentID, "runner_id", m.RunnerID, "session_id", m.SessionID,
		"runner_version", runnerVersion)

	// A panic below closes this machine's connection, not the process.
	defer func() {
		if p := recover(); p != nil {
			log.Error("a panic in a tunnel connection", "panic", p)
			conn.Close(closeInternal, "internal error")
			m.sess.Close()
		}
	}()

	hctx, cancel := context.WithTimeout(ctx, s.opts.HandshakeTimeout)
	err := m.sess.Handshake(hctx)
	cancel()
	if err != nil {
		s.metrics.TunnelConnects.WithLabelValues(ResultHandshake).Inc()
		log.Warn("the tunnel handshake failed", "error", err.Error())
		return
	}

	// The registry holds a machine only once it is up, so a connection that fails its
	// HELLO never takes the place of a working one.
	s.wg.Add(1)
	defer s.wg.Done()
	if old := s.registry.Add(m); old != nil {
		s.metrics.Replaced.Inc()
		log.Info("a newer connection replaces the machine's older one")
		// Not waited for: the old runner may be gone, and its close handshake takes seconds.
		go old.CloseWith(tunnel.CloseReplaced, "replaced")
	}
	s.metrics.TunnelConnects.WithLabelValues(ResultOK).Inc()
	s.metrics.MachinesConnected.Set(float64(s.registry.Len()))
	log.Info("a machine connected")
	// A drain that began while this connection was completing its HELLO has not seen it in the
	// registry: Drain sets the flag first and then reads the registry, and this adds first and
	// then reads the flag, so one of the two sees the other.
	if s.Draining() {
		m.sess.GoAway()
	}

	<-m.sess.Done()
	s.registry.Remove(m)
	s.metrics.MachinesConnected.Set(float64(s.registry.Len()))
	log.Info("a machine disconnected", "reason", errString(m.sess.Err()), "seconds", int(time.Since(m.ConnectedAt).Seconds()))
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// refuse answers with the gateway's JSON refusal shape (PROTOCOL.md §3).
func (s *Server) refuse(w http.ResponseWriter, result string, status int, code, message string) {
	s.metrics.TunnelConnects.WithLabelValues(result).Inc()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": code, "message": message})
}

// bearer is the credential of `Authorization: Bearer <token>`.
func bearer(r *http.Request) (string, bool) {
	scheme, token, ok := strings.Cut(r.Header.Get("Authorization"), " ")
	if !ok || scheme != "Bearer" || token == "" || strings.ContainsAny(token, " \t") {
		return "", false
	}
	return token, true
}

// offers says whether the request lists a WebSocket subprotocol.
func offers(r *http.Request, want string) bool {
	for _, line := range r.Header.Values("Sec-WebSocket-Protocol") {
		for _, p := range strings.Split(line, ",") {
			if strings.TrimSpace(p) == want {
				return true
			}
		}
	}
	return false
}
