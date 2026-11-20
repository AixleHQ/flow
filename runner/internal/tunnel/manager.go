// Package tunnel is the host runner's end of the interactive tunnel
// (docs/design/agent-runtimes/runner-relay.md §3; runner/protocol/PROTOCOL.md §8): it
// keeps one WebSocket to the platform's runner-relay while the machine holds a
// session. The frames and the multiplexer are runner/protocol/tunnel's.
//
// In this version the connection carries no stream: the relay's OPEN is refused
// (`refused`) until the dialers that reach a session's ports exist.
package tunnel

import (
	"context"
	"errors"
	"log/slog"
	"math/rand/v2"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	wire "github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// ModeSession is the check-in's `config.tunnel.mode` that makes the runner connect
// while its machine holds a session (§3.2).
const ModeSession = "session"

// Defaults of the manager's timings.
const (
	DefaultPollEvery = 5 * time.Second
	// DefaultStableAfter is how long a connection must have held before its end counts
	// as a drop of a working tunnel and not a failure to connect: the backoff starts
	// over only after one.
	DefaultStableAfter = 30 * time.Second
	// DefaultGoAwayJitter is the longest wait before the reconnect that follows a
	// GOAWAY (§3.2).
	DefaultGoAwayJitter = 2 * time.Second
	// drainLimit is how long a connection that got GOAWAY is left to finish: the relay
	// closes it after 30 s itself, and this is the runner's own bound.
	drainLimit = 35 * time.Second
)

// Gateway is the part of the protocol client the manager uses.
type Gateway interface {
	TunnelTicket(ctx context.Context, accessToken string) (protocol.TunnelTicket, error)
}

// Manager keeps the tunnel connected while the machine holds a session, and
// reconnects it after a drop.
type Manager struct {
	Gateway   Gateway
	Tokens    *tokens.Source
	Connector Connector
	// Holds says whether the machine holds a session now (docker.Environment.HoldsSession).
	Holds  func(ctx context.Context) (bool, error)
	Logger *slog.Logger
	// Backoff spaces the retries after a failure: 1 s growing to 30 s (§3.2). Nil is that.
	Backoff *backoff.Backoff

	// PollEvery is how often a machine without a connection looks for a session, and
	// a connected one looks for its end. Zero is DefaultPollEvery.
	PollEvery    time.Duration
	StableAfter  time.Duration
	GoAwayJitter time.Duration

	// Now, Sleep and Rand are replaced in tests.
	Now   func() time.Time
	Sleep func(ctx context.Context, d time.Duration) error
	Rand  func() float64
}

func (m *Manager) defaults() {
	if m.Logger == nil {
		m.Logger = slog.Default()
	}
	if m.Backoff == nil {
		m.Backoff = backoff.New(time.Second, 30*time.Second)
	}
	if m.PollEvery == 0 {
		m.PollEvery = DefaultPollEvery
	}
	if m.StableAfter == 0 {
		m.StableAfter = DefaultStableAfter
	}
	if m.GoAwayJitter == 0 {
		m.GoAwayJitter = DefaultGoAwayJitter
	}
	if m.Now == nil {
		m.Now = time.Now
	}
	if m.Sleep == nil {
		m.Sleep = backoff.Sleep
	}
	if m.Rand == nil {
		m.Rand = rand.Float64
	}
}

// Run keeps the tunnel until ctx is done, which returns nil. It returns a
// *tokens.StopError when the token endpoint refused in a way that ends the runner's
// work, and ErrUnsupported when the relay does not speak this runner's protocol:
// the tunnel is then off for this run, and the rest of the runner is not affected.
func (m *Manager) Run(ctx context.Context) error {
	m.defaults()
	for {
		if ctx.Err() != nil {
			return nil
		}
		held, err := m.Holds(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			m.Logger.Warn("tunnel: looking for the machine's session failed", "error", err)
		}
		if err != nil || !held {
			if m.sleep(ctx, m.PollEvery) != nil {
				return nil
			}
			continue
		}

		session, err := m.connect(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			if errors.Is(err, errNoSession) {
				// The platform has not seen the session yet, or it has just ended.
				if m.sleep(ctx, m.PollEvery) != nil {
					return nil
				}
				continue
			}
			if _, stop := tokens.AsStop(err); stop {
				return err
			}
			if refusal, ok := protocol.AsRefusal(err); ok && protocol.Classify(err) == protocol.ActionUpdate {
				m.Logger.Error("tunnel: the platform's relay does not accept this version of aixle-runner; the tunnel stays off until the runner is updated and restarted",
					"error", refusal.Code, "message", refusal.Message)
				return ErrUnsupported
			}
			delay := m.Backoff.Next()
			m.Logger.Warn("tunnel: connecting failed", "error", err, "retry_in", delay.Round(time.Millisecond))
			if m.sleep(ctx, delay) != nil {
				return nil
			}
			continue
		}

		connectedAt := m.Now()
		m.Logger.Info("tunnel: connected", "session_id", sessionID(session), "max_streams", session.Limits().MaxStreams)
		outcome := m.serve(ctx, session)
		if ctx.Err() != nil {
			session.Close()
			return nil
		}
		if m.Now().Sub(connectedAt) >= m.StableAfter {
			m.Backoff.Reset()
		}
		switch outcome {
		case outcomeGoAway:
			// Not an error: reconnect at once, with jitter so a fleet does not arrive
			// together (§3.2). The old connection drains in the background.
			wait := time.Duration(m.Rand() * float64(m.GoAwayJitter))
			m.Logger.Info("tunnel: the relay asked the runner to reconnect", "after", wait.Round(time.Millisecond))
			if m.sleep(ctx, wait) != nil {
				return nil
			}
		case outcomeReleased:
			// The machine's session ended: the tunnel closed and nothing is retried.
			m.Logger.Info("tunnel: closed, the machine holds no session")
		default:
			delay := m.Backoff.Next()
			m.Logger.Warn("tunnel: the connection ended", "error", errorText(session.Err()), "retry_in", delay.Round(time.Millisecond))
			if m.sleep(ctx, delay) != nil {
				return nil
			}
		}
	}
}

// ErrUnsupported is what Run returns when the relay refuses this runner's protocol.
var ErrUnsupported = errors.New("tunnel: the relay does not accept this runner's version")

var errNoSession = errors.New("tunnel: the machine holds no session on the platform")

// connect mints a ticket and opens the tunnel. A relay's refusal of the ticket
// (`invalid_ticket`, `ticket_replayed`) is met once with a new ticket (§3.1).
func (m *Manager) connect(ctx context.Context) (*wire.Session, error) {
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		ticket, err := m.mint(ctx)
		if err != nil {
			return nil, err
		}
		session, err := m.Connector.Connect(ctx, ticket.Ticket)
		if err == nil {
			return session, nil
		}
		lastErr = err
		if refusal, ok := protocol.AsRefusal(err); ok && (refusal.Code == "invalid_ticket" || refusal.Code == "ticket_replayed") {
			m.Logger.Warn("tunnel: the relay refused the ticket; minting a new one", "error", refusal.Code)
			continue
		}
		return nil, err
	}
	return nil, lastErr
}

func (m *Manager) mint(ctx context.Context) (protocol.TunnelTicket, error) {
	var ticket protocol.TunnelTicket
	err := m.Tokens.Do(ctx, func(access string) error {
		var err error
		ticket, err = m.Gateway.TunnelTicket(ctx, access)
		return err
	})
	if refusal, ok := protocol.AsRefusal(err); ok && refusal.Code == "no_session" {
		return protocol.TunnelTicket{}, errNoSession
	}
	if err != nil {
		return protocol.TunnelTicket{}, err
	}
	return ticket, nil
}

type outcome int

const (
	outcomeDropped outcome = iota
	outcomeGoAway
	outcomeReleased
)

// serve runs a connected session until it ends, the relay says GOAWAY, or the
// machine's session is gone.
func (m *Manager) serve(ctx context.Context, session *wire.Session) outcome {
	goaway := make(chan struct{})
	go m.refuseStreams(ctx, session, goaway)

	tick := time.NewTicker(m.PollEvery)
	defer tick.Stop()
	for {
		select {
		case <-session.Done():
			if relayClosedNormally(session.Err()) {
				return outcomeGoAway
			}
			return outcomeDropped
		case <-ctx.Done():
			return outcomeDropped
		case <-goaway:
			go drain(session)
			return outcomeGoAway
		case <-tick.C:
			held, err := m.Holds(ctx)
			if err == nil && !held {
				session.Close()
				return outcomeReleased
			}
		}
	}
}

// relayClosedNormally says whether the relay itself ended the connection in an orderly
// way: close code 1000, after the drain that follows its GOAWAY (the GOAWAY and the close
// can arrive together, with no streams to wait for), or 1001 when it shuts down. That is
// the relay asking the runner to reconnect, as GOAWAY does, and not a failure (§3.2).
func relayClosedNormally(err error) bool {
	var closed *wire.CloseError
	return errors.As(err, &closed) && (closed.Code == wire.CloseNormal || closed.Code == closeGoingAway)
}

// closeGoingAway is the WebSocket close code of a server that is shutting down.
const closeGoingAway = 1001

// refuseStreams answers every OPEN with RESET refused: no port is served yet. It
// closes goaway when the relay's GOAWAY has been received and no OPEN is left.
func (m *Manager) refuseStreams(ctx context.Context, session *wire.Session, goaway chan<- struct{}) {
	for {
		in, err := session.Accept(ctx)
		if err != nil {
			if errors.Is(err, wire.ErrGoAway) {
				close(goaway)
			}
			return
		}
		in.Reject(wire.ResetRefused, "no port is served by this runner yet")
	}
}

// drain leaves a connection that got GOAWAY to finish, and closes it if it has not.
func drain(session *wire.Session) {
	t := time.NewTimer(drainLimit)
	defer t.Stop()
	select {
	case <-session.Done():
	case <-t.C:
		session.Close()
	}
}

func (m *Manager) sleep(ctx context.Context, d time.Duration) error { return m.Sleep(ctx, d) }

func sessionID(s *wire.Session) any {
	if id := s.Peer().SessionID; id != nil {
		return *id
	}
	return nil
}

func errorText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
