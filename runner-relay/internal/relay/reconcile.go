package relay

import (
	"context"
	"errors"
	"time"

	"github.com/aixlehq/aixle-runner-relay/internal/rails"
	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// requestReconcile asks the reconcile loop for a pass now, after a (re)subscription.
func (s *Server) requestReconcile() {
	select {
	case s.reconcileNow <- struct{}{}:
	default:
	}
}

// RunReconciler runs a pass every CheckInterval and whenever a (re)subscription asks
// for one, until ctx is done (§8.3). A pass that Rails does not answer is made again
// with a growing wait; it never closes anything.
func (s *Server) RunReconciler(ctx context.Context) {
	s.reconcileExpected.Store(true)
	interval := s.checkInterval()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		s.passWithRetry(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-s.reconcileNow:
		}
	}
}

// passWithRetry makes a pass, and again after a wait of 1 s doubling to 30 s for as long
// as Rails does not answer. Each attempt that ends, answered or not, is a pass for
// /readyz: it says the loop is alive, which is what the probe may ask. The probe
// does not ask for Rails, so that a Rails outage does not take down the terminals that
// are open.
func (s *Server) passWithRetry(ctx context.Context) {
	delay := time.Second
	for ctx.Err() == nil {
		err := s.Reconcile(ctx)
		s.lastPass.Store(time.Now().UnixNano())
		if err == nil {
			return
		}
		if ctx.Err() != nil {
			return
		}
		s.log.Warn("the reconcile pass could not ask the platform; what is open stays open", "error", err.Error(), "retry_in", delay.String())
		if !sleep(ctx, delay) {
			return
		}
		delay = min(2*delay, 30*time.Second)
	}
}

func (s *Server) checkInterval() time.Duration {
	if s.opts.CheckInterval > 0 {
		return s.opts.CheckInterval
	}
	return 60 * time.Second
}

// Reconcile makes one pass: one `checks` call for every connected machine that holds a
// session, and what comes back false is closed as its signal would have closed it. An
// error means Rails did not answer, and nothing was closed.
func (s *Server) Reconcile(ctx context.Context) error {
	if s.opts.Rails == nil {
		return errors.New("no platform client")
	}
	type held struct {
		m       *Machine
		session int64
	}
	var asked []held
	var items []rails.Machine
	for _, m := range s.registry.All() {
		route, ok := s.registry.Session(m.EnvironmentID)
		if !ok || route.SessionID == 0 {
			continue // an idle machine is always invalid to the platform, so it is not asked
		}
		id := route.SessionID
		asked = append(asked, held{m, id})
		items = append(items, rails.Machine{EnvironmentID: m.EnvironmentID, SessionID: &id})
	}
	if len(items) == 0 {
		s.metrics.ReconcilePasses.WithLabelValues("ok").Inc()
		return nil
	}
	answers, err := s.opts.Rails.Checks(ctx, items)
	switch {
	case errors.Is(err, rails.ErrInvalid):
		// The body is the relay's own: a bug here, never a reason to revoke.
		s.metrics.ReconcilePasses.WithLabelValues("invalid").Inc()
		s.log.Error("the platform refused the reconcile request as invalid; this is a bug in the relay and nothing was revoked")
		return nil
	case err != nil:
		s.metrics.ReconcilePasses.WithLabelValues("rails_error").Inc()
		return err
	}
	s.metrics.ReconcilePasses.WithLabelValues("ok").Inc()
	for i, valid := range answers {
		if valid {
			continue
		}
		s.revokeStale(asked[i].m, asked[i].session)
	}
	return nil
}

// revokeStale closes a machine the platform says is not valid or does not hold the
// session the relay believes. A signal that arrived while the call was out may have
// changed the machine's session already: then the answer is old and is dropped.
func (s *Server) revokeStale(m *Machine, sessionID int64) {
	if cur, ok := s.registry.Machine(m.EnvironmentID); !ok || cur != m {
		return
	}
	if route, ok := s.registry.Session(m.EnvironmentID); !ok || route.SessionID != sessionID {
		return
	}
	s.metrics.ReconcileRevocations.Inc()
	s.log.Warn("the reconcile pass found a machine the platform does not confirm; closing it, as its signal would have",
		"environment_id", m.EnvironmentID, "session_id", sessionID)
	s.routeMu.Lock()
	s.routeGen++
	s.registry.ClearSession(sessionID)
	s.routeMu.Unlock()
	m.EndSession(sessionID, tunnel.ResetRevoked, "revoked by the reconcile pass")
	go m.CloseWith(tunnel.CloseRevoked, "revoked")
}
