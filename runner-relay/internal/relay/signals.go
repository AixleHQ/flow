package relay

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// SignalChannel is the name of the platform's channel, before the Action Cable prefix
// (Runners::RelaySignals::CHANNEL).
const SignalChannel = "runner_relay"

// The signal types of §8.1.
const (
	signalMachineSession = "machine_session"
	signalSessionEnded   = "session_ended"
	signalMachineRevoked = "machine_revoked"
)

// signal is a message of the platform's channel. Every field has its type: a message of
// the wrong shape is refused, not coerced, and fields this version does not know are
// ignored so a newer platform is not refused by an older relay.
type signal struct {
	Type          string         `json:"type"`
	EnvironmentID *int64         `json:"environment_id"`
	SessionID     *int64         `json:"session_id"`
	RouteToken    *string        `json:"route_token"`
	Ports         map[string]int `json:"ports"`
}

// HandleSignal applies one message of the platform's channel. received is when it came
// from Redis, for the lag metric. A message it refuses is returned as an error and
// changes nothing; the reconcile pass repairs whatever a refused or lost signal meant.
func (s *Server) HandleSignal(payload []byte, received time.Time) (err error) {
	var sig signal
	if err := json.Unmarshal(payload, &sig); err != nil {
		s.metrics.SignalsReceived.WithLabelValues("unknown", "invalid").Inc()
		return fmt.Errorf("a signal that is not valid JSON of the expected shape: %w", err)
	}
	result := "applied"
	defer func() {
		if err != nil {
			result = "invalid"
		}
		s.metrics.SignalsReceived.WithLabelValues(metricType(sig.Type), result).Inc()
		if err == nil {
			s.metrics.SignalLag.Observe(time.Since(received).Seconds())
		}
	}()
	switch sig.Type {
	case signalMachineSession:
		return s.machineSession(sig)
	case signalSessionEnded:
		if sig.SessionID == nil || *sig.SessionID <= 0 {
			return errors.New("session_ended without a session_id")
		}
		s.sessionEnded(*sig.SessionID, tunnel.ResetRevoked, "the session ended")
		return nil
	case signalMachineRevoked:
		if sig.EnvironmentID == nil || *sig.EnvironmentID <= 0 {
			return errors.New("machine_revoked without an environment_id")
		}
		s.machineRevoked(*sig.EnvironmentID)
		return nil
	default:
		// A type of a newer platform: nothing to do, and nothing to alarm about.
		result = "ignored"
		return nil
	}
}

// metricType keeps the label to the known types, so a message cannot make labels.
func metricType(t string) string {
	switch t {
	case signalMachineSession, signalSessionEnded, signalMachineRevoked:
		return t
	}
	return "unknown"
}

func (s *Server) machineSession(sig signal) error {
	if sig.EnvironmentID == nil || *sig.EnvironmentID <= 0 {
		return errors.New("machine_session without an environment_id")
	}
	env := *sig.EnvironmentID
	if sig.SessionID == nil {
		s.release(env, tunnel.ResetSessionChange, "the session left the machine")
		return nil
	}
	if *sig.SessionID <= 0 || sig.RouteToken == nil || !routeToken.MatchString(*sig.RouteToken) || !validPorts(sig.Ports) {
		return errors.New("machine_session with a session and no valid route_token and ports")
	}
	s.assign(SessionRoute{SessionID: *sig.SessionID, EnvironmentID: env, RouteToken: *sig.RouteToken, Ports: sig.Ports})
	return nil
}

// assign records the session a machine holds. The previous session's streams are reset
// with `session_changed` (§6, item 2): a new session on the same connection gets new
// streams only.
func (s *Server) assign(route SessionRoute) {
	previous, had := s.registry.SetSession(route.EnvironmentID, route)
	if had && previous.SessionID != 0 && previous.SessionID != route.SessionID {
		s.endOnMachine(route.EnvironmentID, previous.SessionID, tunnel.ResetSessionChange, "the machine's session changed")
	}
}

// release records that a machine holds no session.
func (s *Server) release(environmentID int64, code tunnel.ResetCode, text string) {
	previous, had := s.registry.SetSession(environmentID, SessionRoute{})
	if had && previous.SessionID != 0 {
		s.endOnMachine(environmentID, previous.SessionID, code, text)
	}
}

func (s *Server) endOnMachine(environmentID, sessionID int64, code tunnel.ResetCode, text string) {
	if m, ok := s.registry.Machine(environmentID); ok {
		n := m.EndSession(sessionID, code, text)
		s.log.Info("a machine's session ended", "environment_id", environmentID, "session_id", sessionID, "reset", code.String(), "streams", n)
	}
}

// sessionEnded resets the session's streams with code and closes its browser
// connections, on whichever machine carries them (§8.1).
func (s *Server) sessionEnded(sessionID int64, code tunnel.ResetCode, text string) {
	s.registry.ClearSession(sessionID)
	for _, m := range s.registry.All() {
		if n := m.EndSession(sessionID, code, text); n > 0 {
			s.log.Info("a session ended", "environment_id", m.EnvironmentID, "session_id", sessionID, "reset", code.String(), "streams", n)
		}
	}
}

// machineRevoked closes the machine's connection with 4001, and every browser connection
// of its session with it (§6, item 4).
func (s *Server) machineRevoked(environmentID int64) {
	previous, had := s.registry.SetSession(environmentID, SessionRoute{})
	m, ok := s.registry.Machine(environmentID)
	if !ok {
		return
	}
	if had && previous.SessionID != 0 {
		m.EndSession(previous.SessionID, tunnel.ResetRevoked, "the machine was revoked")
	}
	s.log.Info("a machine was revoked; closing its connection", "environment_id", environmentID)
	go m.CloseWith(tunnel.CloseRevoked, "revoked")
}

// RunSignals subscribes to the platform's channel and applies what arrives, until ctx
// is done. A broken subscription is made again with a growing wait, and every
// (re)subscription asks for a reconcile pass: a message may have been lost meanwhile
// (§8.3).
func (s *Server) RunSignals(ctx context.Context, rdb *redis.Client, channel string) {
	s.signalsExpected.Store(true)
	ps := rdb.Subscribe(ctx)
	defer ps.Close()
	delay := time.Second
	for ctx.Err() == nil {
		if err := ps.Subscribe(ctx, channel); err != nil {
			s.subscribed.Store(false)
			s.log.Warn("subscribing to the signal channel failed", "error", err.Error(), "retry_in", delay.String())
			if !sleep(ctx, delay) {
				return
			}
			delay = min(2*delay, 30*time.Second)
			continue
		}
		delay = time.Second
		s.receive(ctx, ps)
		s.subscribed.Store(false)
	}
}

// receive reads the subscription until it breaks. go-redis makes the connection again
// on the next call after an error and subscribes again by itself; each confirmation it
// then sends is a (re)subscription.
func (s *Server) receive(ctx context.Context, ps *redis.PubSub) {
	failures := 0
	for ctx.Err() == nil {
		msg, err := ps.ReceiveTimeout(ctx, s.signalIdle())
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			if isTimeout(err) {
				// Quiet channel: a ping tells a live connection from a dead one.
				if perr := ps.Ping(ctx); perr != nil {
					err = perr
				} else {
					continue
				}
			}
			s.subscribed.Store(false)
			failures++
			wait := min(time.Duration(failures)*time.Second, 30*time.Second)
			s.log.Warn("the signal subscription broke", "error", err.Error(), "retry_in", wait.String())
			if !sleep(ctx, wait) {
				return
			}
			continue
		}
		switch m := msg.(type) {
		case *redis.Subscription:
			if m.Kind == "subscribe" {
				failures = 0
				s.subscribed.Store(true)
				s.log.Info("subscribed to the signal channel", "channel", m.Channel)
				s.requestReconcile()
			}
		case *redis.Message:
			if err := s.HandleSignal([]byte(m.Payload), time.Now()); err != nil {
				s.log.Warn("a signal was refused", "error", err.Error())
			}
		}
	}
}

func (s *Server) signalIdle() time.Duration {
	if s.opts.SignalIdle > 0 {
		return s.opts.SignalIdle
	}
	return 15 * time.Second
}

func isTimeout(err error) bool {
	var t interface{ Timeout() bool }
	return errors.As(err, &t) && t.Timeout()
}

func sleep(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
