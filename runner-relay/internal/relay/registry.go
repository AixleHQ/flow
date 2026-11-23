package relay

import (
	"context"
	"net/http"
	"net/http/httputil"
	"sync"
	"sync/atomic"
	"time"

	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// Surfaces are the five interactive surfaces of a runner session, in the order of
// the platform's ports (Runners::Tunnel::SURFACES).
var Surfaces = []string{"tty", "view", "fs", "upload", "ide"}

// SessionRoute is what the relay knows of the session a machine holds: the platform's
// answer, from the `machine_session` signal or the `holders` call, never the runner's
// (runner-relay.md §7.1). RouteToken and Ports are empty while only the session's id
// is known (from the ticket the machine connected with).
type SessionRoute struct {
	SessionID     int64
	EnvironmentID int64
	RouteToken    string
	Ports         map[string]int
}

// Registry is the relay's table of connected machines and of the session each
// holds (§7.3). It is behind an interface so the multi-replica option of §11 replaces
// the implementation and not the callers.
type Registry interface {
	// Machine is the connection of an environment.
	Machine(environmentID int64) (*Machine, bool)
	// BySession is the connected machine that holds a session.
	BySession(sessionID int64) (*Machine, bool)
	// ByRouteToken is the session a route token names, when the relay knows it.
	ByRouteToken(token string) (SessionRoute, bool)
	// Session is the session an environment holds, as far as the relay knows.
	Session(environmentID int64) (SessionRoute, bool)

	// Add makes m the connection of its environment and returns the machine it
	// replaced. A machine that connects with a session in its ticket holds that session
	// until a signal says otherwise.
	Add(m *Machine) (replaced *Machine)
	// Remove forgets m if it is still its environment's machine, and says whether it was.
	Remove(m *Machine) bool
	// SetSession records the session an environment holds (a zero route.SessionID: none)
	// and returns the one it held before.
	SetSession(environmentID int64, route SessionRoute) (previous SessionRoute, had bool)
	// SetSessionIfAbsent records route only when the environment holds no routed session
	// (the placeholder a ticket leaves has no route token and counts as none), under one
	// lock, so a signal cannot land between the check and the store. It says whether it
	// stored, and returns the session the placeholder named, if there was one.
	SetSessionIfAbsent(environmentID int64, route SessionRoute) (previous SessionRoute, had, stored bool)
	// ClearSession forgets the route of a session wherever it is held, and returns the
	// environments that held it.
	ClearSession(sessionID int64) []int64

	// All is a snapshot of the connected machines; Len their number.
	All() []*Machine
	Len() int
}

// Machine is one connected machine: its tunnel session, what browser traffic it is
// carrying, and who it is. The ids come from the ticket the gateway signed, never from
// the runner.
type Machine struct {
	EnvironmentID int64
	RunnerID      int64
	// SessionID is the session the machine held when it got its ticket, 0 for none. The
	// registry's Session is the current one.
	SessionID     int64
	RunnerVersion string
	ConnectedAt   time.Time

	conn tunnel.Conn
	sess *tunnel.Session

	// transport and proxy carry the browser's requests over streams of sess.
	transport *http.Transport
	proxy     *httputil.ReverseProxy

	mu       sync.Mutex
	streams  map[int64]map[*stream]struct{}
	requests map[int64]map[uint64]context.CancelFunc
	nextReq  uint64
	closed   atomic.Bool
}

// CloseWith ends the machine's connection with a WebSocket close code the runner
// reads (tunnel.CloseReplaced, tunnel.CloseRevoked), then the session, which resets
// its streams and stops its goroutines.
func (m *Machine) CloseWith(code int, reason string) {
	m.closed.Store(true)
	m.conn.Close(code, reason)
	m.sess.Close()
}

// beginRequest registers a browser request of a session, so that ending the session
// cancels it. The returned function unregisters it.
func (m *Machine) beginRequest(sessionID int64, cancel context.CancelFunc) (end func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.requests == nil {
		m.requests = map[int64]map[uint64]context.CancelFunc{}
	}
	if m.requests[sessionID] == nil {
		m.requests[sessionID] = map[uint64]context.CancelFunc{}
	}
	m.nextReq++
	id := m.nextReq
	m.requests[sessionID][id] = cancel
	return func() {
		m.mu.Lock()
		defer m.mu.Unlock()
		delete(m.requests[sessionID], id)
		if len(m.requests[sessionID]) == 0 {
			delete(m.requests, sessionID)
		}
	}
}

// track registers an open stream of a session.
func (m *Machine) track(sessionID int64, st *stream) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.streams == nil {
		m.streams = map[int64]map[*stream]struct{}{}
	}
	if m.streams[sessionID] == nil {
		m.streams[sessionID] = map[*stream]struct{}{}
	}
	m.streams[sessionID][st] = struct{}{}
}

func (m *Machine) untrack(sessionID int64, st *stream) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.streams[sessionID], st)
	if len(m.streams[sessionID]) == 0 {
		delete(m.streams, sessionID)
	}
}

// EndSession resets every stream of a session with code and cancels its browser
// requests, which closes their connections: the session left the machine, or ended
// (§6, items 2 and 4). It returns the number of streams reset.
func (m *Machine) EndSession(sessionID int64, code tunnel.ResetCode, text string) int {
	m.mu.Lock()
	streams := make([]*stream, 0, len(m.streams[sessionID]))
	for st := range m.streams[sessionID] {
		streams = append(streams, st)
	}
	cancels := make([]context.CancelFunc, 0, len(m.requests[sessionID]))
	for _, cancel := range m.requests[sessionID] {
		cancels = append(cancels, cancel)
	}
	m.mu.Unlock()
	for _, st := range streams {
		st.Reset(code, text)
	}
	for _, cancel := range cancels {
		cancel()
	}
	return len(streams)
}

// OpenStreams is the number of streams the machine carries for a session.
func (m *Machine) OpenStreams(sessionID int64) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return len(m.streams[sessionID])
}

// MemoryRegistry is the Registry of a single replica: maps in memory.
type MemoryRegistry struct {
	mu       sync.Mutex
	machines map[int64]*Machine
	sessions map[int64]SessionRoute // by environment id
	byToken  map[string]int64       // route token -> environment id
}

// NewRegistry returns an empty in-memory registry.
func NewRegistry() *MemoryRegistry {
	return &MemoryRegistry{machines: map[int64]*Machine{}, sessions: map[int64]SessionRoute{}, byToken: map[string]int64{}}
}

var _ Registry = (*MemoryRegistry)(nil)

func (r *MemoryRegistry) Add(m *Machine) (replaced *Machine) {
	r.mu.Lock()
	defer r.mu.Unlock()
	replaced = r.machines[m.EnvironmentID]
	r.machines[m.EnvironmentID] = m
	if _, known := r.sessions[m.EnvironmentID]; !known && m.SessionID != 0 {
		r.sessions[m.EnvironmentID] = SessionRoute{SessionID: m.SessionID, EnvironmentID: m.EnvironmentID}
	}
	return replaced
}

func (r *MemoryRegistry) Remove(m *Machine) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.machines[m.EnvironmentID] != m {
		return false
	}
	delete(r.machines, m.EnvironmentID)
	return true
}

func (r *MemoryRegistry) Machine(environmentID int64) (*Machine, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m, ok := r.machines[environmentID]
	return m, ok
}

func (r *MemoryRegistry) BySession(sessionID int64) (*Machine, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for env, route := range r.sessions {
		if route.SessionID == sessionID {
			if m, ok := r.machines[env]; ok {
				return m, true
			}
		}
	}
	return nil, false
}

func (r *MemoryRegistry) ByRouteToken(token string) (SessionRoute, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	env, ok := r.byToken[token]
	if !ok {
		return SessionRoute{}, false
	}
	return r.sessions[env], true
}

func (r *MemoryRegistry) Session(environmentID int64) (SessionRoute, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	route, ok := r.sessions[environmentID]
	return route, ok
}

func (r *MemoryRegistry) SetSession(environmentID int64, route SessionRoute) (SessionRoute, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	previous, had := r.sessions[environmentID]
	if had && previous.RouteToken != "" && r.byToken[previous.RouteToken] == environmentID {
		delete(r.byToken, previous.RouteToken)
	}
	if route.SessionID == 0 {
		delete(r.sessions, environmentID)
		return previous, had
	}
	route.EnvironmentID = environmentID
	r.sessions[environmentID] = route
	if route.RouteToken != "" {
		// A token names one session, held by one machine: the newest signal wins, and the
		// previous holder's own signal (a null session) follows.
		r.byToken[route.RouteToken] = environmentID
	}
	return previous, had
}

func (r *MemoryRegistry) SetSessionIfAbsent(environmentID int64, route SessionRoute) (SessionRoute, bool, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	previous, had := r.sessions[environmentID]
	if had && previous.RouteToken != "" {
		return previous, had, false
	}
	if route.SessionID == 0 {
		return previous, had, false
	}
	route.EnvironmentID = environmentID
	r.sessions[environmentID] = route
	if route.RouteToken != "" {
		r.byToken[route.RouteToken] = environmentID
	}
	return previous, had, true
}

func (r *MemoryRegistry) ClearSession(sessionID int64) []int64 {
	r.mu.Lock()
	defer r.mu.Unlock()
	var envs []int64
	for env, route := range r.sessions {
		if route.SessionID != sessionID {
			continue
		}
		if route.RouteToken != "" && r.byToken[route.RouteToken] == env {
			delete(r.byToken, route.RouteToken)
		}
		delete(r.sessions, env)
		envs = append(envs, env)
	}
	return envs
}

func (r *MemoryRegistry) All() []*Machine {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]*Machine, 0, len(r.machines))
	for _, m := range r.machines {
		out = append(out, m)
	}
	return out
}

func (r *MemoryRegistry) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.machines)
}
