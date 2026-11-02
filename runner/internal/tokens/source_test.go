package tokens

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/protocol"
)

var now = time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)

type fakeStore struct {
	saved   []credentials.Credentials
	deleted bool
	failing bool
	events  *[]string
}

func (s *fakeStore) Save(c credentials.Credentials) error {
	if s.failing {
		return errors.New("disk full")
	}
	s.saved = append(s.saved, c)
	*s.events = append(*s.events, "save "+c.AccessToken)
	return nil
}

func (s *fakeStore) Delete() error { s.deleted = true; return nil }

type fakeRefresher struct {
	pairs  []protocol.TokenPair
	errs   []error
	seen   []string
	events *[]string
}

func (r *fakeRefresher) Refresh(_ context.Context, refresh string) (protocol.TokenPair, error) {
	r.seen = append(r.seen, refresh)
	*r.events = append(*r.events, "refresh "+refresh)
	if len(r.errs) > 0 {
		err := r.errs[0]
		r.errs = r.errs[1:]
		if err != nil {
			return protocol.TokenPair{}, err
		}
	}
	p := r.pairs[0]
	r.pairs = r.pairs[1:]
	return p, nil
}

func pair(n string, expires time.Time) protocol.TokenPair {
	return protocol.TokenPair{
		AccessToken: "aracc_" + n, AccessTokenExpiresAt: expires,
		RefreshToken: "arref_" + n, RefreshTokenExpiresAt: expires.Add(30 * 24 * time.Hour),
	}
}

func refusal(e protocol.Endpoint, status int, code string) error {
	return &protocol.Refusal{Endpoint: e, Status: status, Code: code, Message: "m"}
}

func setup(current protocol.TokenPair, next ...protocol.TokenPair) (*Source, *fakeStore, *fakeRefresher, *[]string) {
	events := &[]string{}
	store := &fakeStore{events: events}
	ref := &fakeRefresher{pairs: next, events: events}
	s := NewSource(store, ref, credentials.Credentials{URL: "https://flow.aixle.com", TokenPair: current})
	s.SetClock(func() time.Time { return now })
	return s, store, ref, events
}

func TestAccessIsUsedUntilItIsAboutToExpire(t *testing.T) {
	s, _, ref, _ := setup(pair("1", now.Add(time.Hour)))
	token, err := s.Access(context.Background())
	if err != nil || token != "aracc_1" || len(ref.seen) != 0 {
		t.Fatalf("token %q, err %v, refreshes %v", token, err, ref.seen)
	}
}

func TestRefreshBeforeExpiryRotatesAndStoresBeforeUse(t *testing.T) {
	s, store, ref, events := setup(pair("1", now.Add(RefreshMargin-time.Second)), pair("2", now.Add(time.Hour)))
	var used string
	err := s.Do(context.Background(), func(access string) error {
		*events = append(*events, "use "+access)
		used = access
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if used != "aracc_2" || ref.seen[0] != "arref_1" {
		t.Fatalf("used %q, refreshed with %v", used, ref.seen)
	}
	want := []string{"refresh arref_1", "save aracc_2", "use aracc_2"}
	if len(*events) != 3 || (*events)[0] != want[0] || (*events)[1] != want[1] || (*events)[2] != want[2] {
		t.Fatalf("events %v, want %v", *events, want)
	}
	if got := store.saved[0]; got.RefreshToken != "arref_2" || got.URL != "https://flow.aixle.com" {
		t.Fatalf("stored %#v", got)
	}
	// The next refresh presents only the new refresh token.
	s.SetClock(func() time.Time { return now.Add(2 * time.Hour) })
	ref.pairs = []protocol.TokenPair{pair("3", now.Add(3*time.Hour))}
	if _, err := s.Access(context.Background()); err != nil {
		t.Fatal(err)
	}
	if ref.seen[1] != "arref_2" {
		t.Fatalf("second refresh used %s", ref.seen[1])
	}
}

func TestAccessInvalidTokenRefreshesOnceAndRetries(t *testing.T) {
	s, _, ref, _ := setup(pair("1", now.Add(time.Hour)), pair("2", now.Add(time.Hour)))
	var calls []string
	err := s.Do(context.Background(), func(access string) error {
		calls = append(calls, access)
		if access == "aracc_1" {
			return refusal(protocol.EndpointOps, 401, "invalid_token")
		}
		return nil
	})
	if err != nil || len(calls) != 2 || calls[1] != "aracc_2" || len(ref.seen) != 1 {
		t.Fatalf("err %v, calls %v, refreshes %v", err, calls, ref.seen)
	}
}

func TestRefusedRefreshAfterInvalidTokenStopsForReregistration(t *testing.T) {
	s, _, ref, _ := setup(pair("1", now.Add(time.Hour)))
	ref.errs = []error{refusal(protocol.EndpointToken, 401, "invalid_token")}
	err := s.Do(context.Background(), func(string) error { return refusal(protocol.EndpointOps, 401, "invalid_token") })
	stop, ok := AsStop(err)
	if !ok || stop.Action != protocol.ActionReregister {
		t.Fatalf("got %v", err)
	}
}

func TestFreshTokenRefusedAgainStops(t *testing.T) {
	s, _, _, _ := setup(pair("1", now.Add(time.Hour)), pair("2", now.Add(time.Hour)))
	err := s.Do(context.Background(), func(string) error { return refusal(protocol.EndpointOps, 401, "invalid_token") })
	if stop, ok := AsStop(err); !ok || stop.Action != protocol.ActionReregister {
		t.Fatalf("got %v", err)
	}
}

func TestReuseDetectedDeletesTheCredentials(t *testing.T) {
	s, store, ref, _ := setup(pair("1", now))
	ref.errs = []error{refusal(protocol.EndpointToken, 401, "credential_reuse_detected")}
	_, err := s.Access(context.Background())
	stop, ok := AsStop(err)
	if !ok || stop.Action != protocol.ActionReuseDetected || !store.deleted {
		t.Fatalf("err %v, deleted %v", err, store.deleted)
	}
}

func TestRevokedAndUpdateStopWithoutDeleting(t *testing.T) {
	for _, tc := range []struct {
		err  error
		want protocol.Action
	}{
		{refusal(protocol.EndpointOps, 401, "runner_revoked"), protocol.ActionRevoked},
		{refusal(protocol.EndpointOps, 400, "unsupported_protocol"), protocol.ActionUpdate},
		{refusal(protocol.EndpointOps, 400, "invalid_runner_version"), protocol.ActionUpdate},
	} {
		s, store, _, _ := setup(pair("1", now.Add(time.Hour)))
		err := s.Do(context.Background(), func(string) error { return tc.err })
		if stop, ok := AsStop(err); !ok || stop.Action != tc.want || store.deleted {
			t.Errorf("%v: got %v", tc.err, err)
		}
	}
}

func TestBackoffRefusalsAreReturnedAsTheyAre(t *testing.T) {
	s, store, ref, _ := setup(pair("1", now))
	disabled := refusal(protocol.EndpointToken, 403, "runners_disabled")
	ref.errs = []error{disabled}
	_, err := s.Access(context.Background())
	if _, stop := AsStop(err); stop || !errors.Is(err, disabled) || store.deleted {
		t.Fatalf("got %v", err)
	}
	if protocol.Classify(err) != protocol.ActionBackoff {
		t.Fatalf("classified %s", protocol.Classify(err))
	}
	// Once the company's runners are enabled again, the same credentials work.
	ref.pairs = []protocol.TokenPair{pair("2", now.Add(time.Hour))}
	if token, err := s.Access(context.Background()); err != nil || token != "aracc_2" {
		t.Fatalf("token %q, err %v", token, err)
	}
}

func TestARotatedPairIsNotUsedUntilStored(t *testing.T) {
	s, store, _, _ := setup(pair("1", now), pair("2", now.Add(time.Hour)))
	store.failing = true
	if _, err := s.Access(context.Background()); err == nil {
		t.Fatal("an unstored pair was handed out")
	}
	store.failing = false
	token, err := s.Access(context.Background())
	if err != nil || token != "aracc_2" || len(store.saved) != 1 {
		t.Fatalf("token %q, err %v, saved %d", token, err, len(store.saved))
	}
}

func TestStopErrorCarriesNoToken(t *testing.T) {
	s, _, ref, _ := setup(pair("1", now))
	ref.errs = []error{refusal(protocol.EndpointToken, 401, "invalid_token")}
	_, err := s.Access(context.Background())
	for _, secret := range []string{"aracc_1", "arref_1"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("%q carries %s", err, secret)
		}
	}
}
