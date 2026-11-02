// Package tokens hands out the machine's access token and keeps the stored pair
// rotated (runner/protocol/PROTOCOL.md §4): it refreshes before the access token
// expires and on an access `invalid_token`, stores every new pair before using it,
// and turns the refusals that end the runner's work into a *StopError.
package tokens

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// RefreshMargin is how long before its expiry the access token is refreshed.
const RefreshMargin = 5 * time.Minute

// Refresher is the gateway's token endpoint.
type Refresher interface {
	Refresh(ctx context.Context, refreshToken string) (protocol.TokenPair, error)
}

// Store is where the pair is persisted.
type Store interface {
	Save(credentials.Credentials) error
	Delete() error
}

// Source owns the credentials of one machine.
type Source struct {
	mu        sync.Mutex
	store     Store
	refresher Refresher
	creds     credentials.Credentials
	// unsaved is set when a rotated pair could not be stored yet. It is not used
	// until it is stored: the spent refresh token is gone, so a restart with the
	// old file would be refused anyway, but a pair the file does not hold must
	// not be the one in use.
	unsaved bool
	// stale is set by an access `invalid_token`: the next Access refreshes.
	stale bool
	now   func() time.Time
}

// NewSource returns a source for creds, as loaded from store.
func NewSource(store Store, refresher Refresher, creds credentials.Credentials) *Source {
	return &Source{store: store, refresher: refresher, creds: creds, now: time.Now}
}

// SetClock replaces the clock, for tests.
func (s *Source) SetClock(now func() time.Time) { s.now = now }

// Credentials returns the current credentials.
func (s *Source) Credentials() credentials.Credentials {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.creds
}

// Access returns an access token that is not about to expire, refreshing first
// when needed.
func (s *Source) Access(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.unsaved {
		if err := s.store.Save(s.creds); err != nil {
			return "", fmt.Errorf("storing the rotated credentials: %w", err)
		}
		s.unsaved = false
	}
	if s.stale || !s.now().Add(RefreshMargin).Before(s.creds.AccessTokenExpiresAt) {
		if err := s.refreshLocked(ctx); err != nil {
			return "", err
		}
	}
	return s.creds.AccessToken, nil
}

func (s *Source) refreshLocked(ctx context.Context) error {
	pair, err := s.refresher.Refresh(ctx, s.creds.RefreshToken)
	if err != nil {
		return s.stopOn(err)
	}
	s.creds.TokenPair = pair
	s.stale = false
	if err := s.store.Save(s.creds); err != nil {
		s.unsaved = true
		return fmt.Errorf("storing the rotated credentials: %w", err)
	}
	return nil
}

// Do runs call with the access token. On an `invalid_token` it refreshes once and
// runs call again with the new token (§3). A refusal that ends the runner's work
// is returned as a *StopError; any other error is returned as it is, for the caller
// to classify.
func (s *Source) Do(ctx context.Context, call func(accessToken string) error) error {
	for attempt := 0; ; attempt++ {
		access, err := s.Access(ctx)
		if err != nil {
			return err
		}
		err = call(access)
		if err == nil {
			return nil
		}
		if protocol.Classify(err) != protocol.ActionRefresh {
			return s.stopOn(err)
		}
		if attempt > 0 {
			// A freshly issued access token was refused: the machine was
			// unregistered or revoked in between.
			return &StopError{Action: protocol.ActionReregister, Err: err}
		}
		s.mu.Lock()
		if s.creds.AccessToken == access {
			s.stale = true
		}
		s.mu.Unlock()
	}
}

// stopOn converts the refusals after which the runner cannot go on.
func (s *Source) stopOn(err error) error {
	switch action := protocol.Classify(err); action {
	case protocol.ActionReregister, protocol.ActionRevoked, protocol.ActionUpdate:
		return &StopError{Action: action, Err: err}
	case protocol.ActionReuseDetected:
		if delErr := s.store.Delete(); delErr != nil {
			return &StopError{Action: action, Err: errors.Join(err, delErr)}
		}
		return &StopError{Action: action, Err: err}
	}
	return err
}

// StopError is a refusal after which the runner stops and an operator acts.
type StopError struct {
	Action protocol.Action
	Err    error
}

func (e *StopError) Error() string {
	switch e.Action {
	case protocol.ActionReregister:
		return "the platform no longer accepts this machine's credentials (it was unregistered, revoked, or unused for 30 days): register it again with `aixle-runner configure` (" + e.Err.Error() + ")"
	case protocol.ActionReuseDetected:
		return "this machine's refresh token was presented by someone else, so the platform revoked its credentials; the local credentials were deleted: register the machine again with `aixle-runner configure` (" + e.Err.Error() + ")"
	case protocol.ActionRevoked:
		return "the runner of this machine was revoked or deleted: register with a registration token of a live runner (" + e.Err.Error() + ")"
	case protocol.ActionUpdate:
		return "the platform does not accept this version of aixle-runner: update aixle-runner (" + e.Err.Error() + ")"
	}
	return e.Err.Error()
}

func (e *StopError) Unwrap() error { return e.Err }

// AsStop returns the *StopError inside err, if there is one.
func AsStop(err error) (*StopError, bool) {
	var s *StopError
	ok := errors.As(err, &s)
	return s, ok
}
