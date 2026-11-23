package tunnel

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/aixlehq/aixle-runner/internal/proxy"
	wire "github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// DialTimeout bounds the dial of a session's port for one stream. The relay waits
// for OPEN_OK for its own open timeout, which is longer.
const DialTimeout = 8 * time.Second

// Dialer reaches a port of a session's container (docs/design/agent-runtimes/runner-relay.md
// §3.3). There is one implementation per way of reaching it, so `kubernetes` adds its own.
type Dialer interface {
	Dial(ctx context.Context, port int) (net.Conn, error)
}

// SocketDialer reaches the ports of a session on the default bridge network through the
// session's proxy sidecar, in whose network namespace they listen (proxy.DialViaSidecar).
type SocketDialer struct {
	// Socket is the sidecar's dial socket, in the session's dial directory.
	Socket string
}

// Dial implements Dialer.
func (d SocketDialer) Dial(ctx context.Context, port int) (net.Conn, error) {
	return proxy.DialViaSidecar(ctx, d.Socket, port)
}

// LoopbackDialer reaches the ports of a session with `network: host`, which listen on the
// machine's own 127.0.0.1.
type LoopbackDialer struct{}

// Dial implements Dialer.
func (LoopbackDialer) Dial(ctx context.Context, port int) (net.Conn, error) {
	var d net.Dialer
	return d.DialContext(ctx, "tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
}

// Grant is what the runner serves through the tunnel: the session its own
// `container.start` created, its five ports, and the way to reach them.
type Grant struct {
	SessionID int64
	Ports     []int
	Dialer    Dialer
}

func (g Grant) allows(sessionID int64, port int) bool {
	if g.SessionID != sessionID {
		return false
	}
	for _, p := range g.Ports {
		if p == port {
			return true
		}
	}
	return false
}

// Serving is the table of what the runner serves: at most one Grant, since a machine
// holds one session at a time. `container.start` sets it and `container.stop` and the
// resets clear it; a relay's OPEN for anything else is refused (§3.3). It also holds
// the streams that are open, so that taking the grant away resets them.
type Serving struct {
	mu      sync.Mutex
	grant   *Grant
	streams map[*wire.Stream]int64
}

// Set makes g what the runner serves. A grant of another session that was set before
// ends: its streams are reset with `session_changed`.
func (s *Serving) Set(g Grant) {
	s.mu.Lock()
	var stale []*wire.Stream
	if s.grant != nil && s.grant.SessionID != g.SessionID {
		stale = s.takeLocked(s.grant.SessionID)
	}
	s.grant = &g
	s.mu.Unlock()
	resetAll(stale)
}

// Clear stops serving a session and resets its open streams with `session_changed`,
// before its container goes (PROTOCOL.md §8.7). A session that is not the granted one
// changes nothing.
func (s *Serving) Clear(sessionID int64) {
	s.mu.Lock()
	var stale []*wire.Stream
	if s.grant != nil && s.grant.SessionID == sessionID {
		stale = s.takeLocked(sessionID)
		s.grant = nil
	}
	s.mu.Unlock()
	resetAll(stale)
}

// ClearAll stops serving whatever it serves.
func (s *Serving) ClearAll() {
	s.mu.Lock()
	var stale []*wire.Stream
	if s.grant != nil {
		stale = s.takeLocked(s.grant.SessionID)
		s.grant = nil
	}
	s.mu.Unlock()
	resetAll(stale)
}

func (s *Serving) takeLocked(sessionID int64) []*wire.Stream {
	var out []*wire.Stream
	for st, id := range s.streams {
		if id == sessionID {
			out = append(out, st)
			delete(s.streams, st)
		}
	}
	return out
}

func resetAll(streams []*wire.Stream) {
	for _, st := range streams {
		st.Reset(wire.ResetSessionChange, "the session left this machine")
	}
}

// Authorize is the dialer of a session's port, when the runner serves it.
func (s *Serving) Authorize(sessionID int64, port int) (Dialer, bool) {
	if s == nil {
		return nil, false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.grant == nil || !s.grant.allows(sessionID, port) {
		return nil, false
	}
	return s.grant.Dialer, true
}

// track registers an open stream of a session; false if the session is no longer served,
// which happens when the grant was taken away while the port was being dialed.
func (s *Serving) track(sessionID int64, st *wire.Stream) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.grant == nil || s.grant.SessionID != sessionID {
		return false
	}
	if s.streams == nil {
		s.streams = map[*wire.Stream]int64{}
	}
	s.streams[st] = sessionID
	return true
}

func (s *Serving) untrack(st *wire.Stream) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.streams, st)
}

// serveStreams answers the relay's OPENs until the session ends, and closes goaway when
// the relay's GOAWAY has been received and no OPEN is left. An OPEN for another session
// or a port outside the grant is `RESET refused` (§3.3); a port that does not answer is
// `RESET dial_failed`.
func (m *Manager) serveStreams(ctx context.Context, session *wire.Session, goaway chan<- struct{}) {
	for {
		in, err := session.Accept(ctx)
		if err != nil {
			if errors.Is(err, wire.ErrGoAway) {
				close(goaway)
			}
			return
		}
		go m.serveStream(ctx, in)
	}
}

func (m *Manager) serveStream(ctx context.Context, in *wire.Incoming) {
	dialer, ok := m.Serving.Authorize(in.SessionID, in.Port)
	if !ok {
		in.Reject(wire.ResetRefused, "this runner does not serve that session's port")
		return
	}
	dctx, cancel := context.WithTimeout(ctx, DialTimeout)
	conn, err := dialer.Dial(dctx, in.Port)
	cancel()
	if err != nil {
		m.Logger.Warn("tunnel: dialing a session's port failed", "session_id", in.SessionID, "port", in.Port, "error", err)
		in.Reject(wire.ResetDialFailed, fmt.Sprintf("port %d did not answer", in.Port))
		return
	}
	st, err := in.Accept()
	if err != nil {
		conn.Close()
		return
	}
	// The grant may have been taken away while the port was dialed: no stream of a session
	// that is not served stays open.
	if !m.Serving.track(in.SessionID, st) {
		st.Reset(wire.ResetSessionChange, "the session left this machine")
		conn.Close()
		return
	}
	defer m.Serving.untrack(st)
	proxy.Pipe(st, conn)
}
