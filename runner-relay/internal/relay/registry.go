package relay

import (
	"sync"
	"time"

	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// Machine is one connected machine: its tunnel session and who it is. The ids come
// from the ticket the gateway signed, never from the runner.
type Machine struct {
	EnvironmentID int64
	RunnerID      int64
	// SessionID is the session the machine held when it got its ticket, 0 for none.
	SessionID     int64
	RunnerVersion string
	ConnectedAt   time.Time

	conn tunnel.Conn
	sess *tunnel.Session
}

// CloseWith ends the machine's connection with a WebSocket close code the runner
// reads (tunnel.CloseReplaced, tunnel.CloseRevoked), then the session, which resets
// its streams and stops its goroutines.
func (m *Machine) CloseWith(code int, reason string) {
	m.conn.Close(code, reason)
	m.sess.Close()
}

// Registry holds the connected machines, one per environment (§7.3). Only the
// machine level exists in this task: the session and route-token lookups come with
// the browser path.
type Registry struct {
	mu       sync.Mutex
	machines map[int64]*Machine
}

// NewRegistry returns an empty registry.
func NewRegistry() *Registry { return &Registry{machines: map[int64]*Machine{}} }

// Add makes m the connection of its environment. It returns the machine it
// replaced, if any, which the caller closes.
func (r *Registry) Add(m *Machine) (replaced *Machine) {
	r.mu.Lock()
	defer r.mu.Unlock()
	replaced = r.machines[m.EnvironmentID]
	r.machines[m.EnvironmentID] = m
	return replaced
}

// Remove forgets m if it is still its environment's machine. It says whether it
// was: a machine that was replaced is not.
func (r *Registry) Remove(m *Machine) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.machines[m.EnvironmentID] != m {
		return false
	}
	delete(r.machines, m.EnvironmentID)
	return true
}

// Machine is the connection of an environment.
func (r *Registry) Machine(environmentID int64) (*Machine, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m, ok := r.machines[environmentID]
	return m, ok
}

// All is a snapshot of the connected machines.
func (r *Registry) All() []*Machine {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]*Machine, 0, len(r.machines))
	for _, m := range r.machines {
		out = append(out, m)
	}
	return out
}

// Len is the number of connected machines.
func (r *Registry) Len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.machines)
}
