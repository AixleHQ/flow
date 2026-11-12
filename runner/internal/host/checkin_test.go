package host

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

type checkInGateway struct {
	answers  []error
	tokens   []string
	requests []protocol.CheckInRequest
	update   *protocol.Update
}

func (g *checkInGateway) CheckIn(_ context.Context, access string, req protocol.CheckInRequest) (protocol.CheckIn, error) {
	g.tokens = append(g.tokens, access)
	g.requests = append(g.requests, req)
	if len(g.answers) > 0 {
		err := g.answers[0]
		g.answers = g.answers[1:]
		if err != nil {
			return protocol.CheckIn{}, err
		}
	}
	return protocol.CheckIn{
		Environment: protocol.Environment{ID: 42, Key: "aixle-r7-build"},
		Config:      protocol.CheckInConfig{UploadMaxBytes: 100 << 20},
		Update:      g.update,
	}, nil
}

func newChecker(gw *checkInGateway) (*Checker, *[]time.Duration, *bytes.Buffer) {
	source := tokens.NewSource(&memStore{}, &refresher{}, credentials.Credentials{
		URL: "https://flow.aixle.com",
		TokenPair: protocol.TokenPair{
			AccessToken: "aracc_first", AccessTokenExpiresAt: now.Add(time.Hour),
			RefreshToken: "arref_first", RefreshTokenExpiresAt: now.Add(720 * time.Hour),
		},
	})
	source.SetClock(func() time.Time { return now })
	b := backoff.New(time.Second, time.Minute)
	b.Rand = func() float64 { return 0 }
	sleeps := &[]time.Duration{}
	logs := &bytes.Buffer{}
	return &Checker{
		Gateway: gw, Tokens: source, Backoff: b, Logger: slog.New(slog.NewTextHandler(logs, nil)),
		Sleep: func(_ context.Context, d time.Duration) error { *sleeps = append(*sleeps, d); return nil },
	}, sleeps, logs
}

var report = protocol.CheckInRequest{OS: "linux", Arch: "arm64", Facts: map[string]any{"docker": "27.2.0"}}

func TestCheckInReportsTheMachineWithTheAccessToken(t *testing.T) {
	gw := &checkInGateway{update: &protocol.Update{Version: "1.5.0", SHA256: strings.Repeat("a", 64)}}
	checker, sleeps, _ := newChecker(gw)

	answer, recorded, err := checker.CheckIn(context.Background(), report)

	if err != nil || !recorded || answer.Update == nil || answer.Update.Version != "1.5.0" || answer.Config.UploadMaxBytes != 100<<20 {
		t.Fatalf("%+v %v %v", answer, recorded, err)
	}
	if len(gw.requests) != 1 || gw.requests[0].OS != "linux" || gw.requests[0].Facts["docker"] != "27.2.0" || gw.tokens[0] != "aracc_first" || len(*sleeps) != 0 {
		t.Fatalf("requests %+v tokens %v sleeps %v", gw.requests, gw.tokens, *sleeps)
	}
}

func TestCheckInRetriesWhatTheRunnerCanWaitOut(t *testing.T) {
	gw := &checkInGateway{answers: []error{
		&protocol.NetworkError{Endpoint: protocol.EndpointCheckIn, Err: errors.New("connection reset")},
		&protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 403, Code: "runners_disabled"},
		&protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 429},
		&protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 502},
	}}
	checker, sleeps, _ := newChecker(gw)

	_, recorded, err := checker.CheckIn(context.Background(), report)

	if err != nil || !recorded || len(gw.requests) != 5 {
		t.Fatalf("%d requests, %v %v", len(gw.requests), recorded, err)
	}
	// Doubling from 1 s, and the lowest of the jitter in the test: half the ceiling.
	want := []time.Duration{500 * time.Millisecond, time.Second, 2 * time.Second, 4 * time.Second}
	if len(*sleeps) != len(want) {
		t.Fatalf("sleeps %v", *sleeps)
	}
	for i, d := range want {
		if (*sleeps)[i] != d {
			t.Errorf("pause %d was %v, want %v", i, (*sleeps)[i], d)
		}
	}
}

// A runner below the minimum, or one whose credentials are gone, does not go on to
// take ops.
func TestCheckInStopsOnARefusalThatEndsTheRunnersWork(t *testing.T) {
	for _, tc := range []struct {
		name string
		err  error
		want protocol.Action
	}{
		{"below the minimum", &protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 400, Code: "runner_version_unsupported", Message: "no longer supported (minimum 1.2.0)"}, protocol.ActionUpdate},
		{"revoked", &protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 401, Code: "runner_revoked"}, protocol.ActionRevoked},
	} {
		gw := &checkInGateway{answers: []error{tc.err}}
		checker, sleeps, _ := newChecker(gw)

		_, recorded, err := checker.CheckIn(context.Background(), report)

		stop, ok := tokens.AsStop(err)
		if recorded || !ok || stop.Action != tc.want || len(gw.requests) != 1 || len(*sleeps) != 0 {
			t.Errorf("%s: %v %v, %d requests", tc.name, recorded, err, len(gw.requests))
		}
	}
}

// A refused report is a bug in the runner, and the ops do not depend on it.
func TestCheckInGoesOnWithoutItWhenThePlatformRefusesTheReport(t *testing.T) {
	gw := &checkInGateway{answers: []error{&protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 422, Code: "invalid_check_in", Message: "os"}}}
	checker, sleeps, logs := newChecker(gw)

	_, recorded, err := checker.CheckIn(context.Background(), report)

	if err != nil || recorded || len(gw.requests) != 1 || len(*sleeps) != 0 {
		t.Fatalf("%v %v, %d requests", recorded, err, len(gw.requests))
	}
	if !strings.Contains(logs.String(), "bug in aixle-runner") {
		t.Errorf("the refusal is not reported:\n%s", logs.String())
	}
}

// A check-in route that keeps failing must not stop a machine that can work.
func TestCheckInGivesUpAfterABoundedNumberOfAttemptsAndTheRunnerGoesOn(t *testing.T) {
	down := &protocol.Refusal{Endpoint: protocol.EndpointCheckIn, Status: 502}
	gw := &checkInGateway{answers: []error{down, down, down, down, down, down, down}}
	checker, sleeps, logs := newChecker(gw)

	_, recorded, err := checker.CheckIn(context.Background(), report)

	if err != nil || recorded || len(gw.requests) != DefaultCheckInAttempts || len(*sleeps) != DefaultCheckInAttempts-1 {
		t.Fatalf("%v %v, %d requests, %d pauses", recorded, err, len(gw.requests), len(*sleeps))
	}
	if !strings.Contains(logs.String(), "going on without a check-in") {
		t.Errorf("the give-up is not logged:\n%s", logs.String())
	}

	gw = &checkInGateway{answers: []error{down, down, down}}
	checker, _, _ = newChecker(gw)
	checker.MaxAttempts = 2
	if _, recorded, err = checker.CheckIn(context.Background(), report); err != nil || recorded || len(gw.requests) != 2 {
		t.Fatalf("MaxAttempts: %v %v, %d requests", recorded, err, len(gw.requests))
	}
}

func TestCheckInEndsWithTheRunner(t *testing.T) {
	gw := &checkInGateway{answers: []error{&protocol.NetworkError{Endpoint: protocol.EndpointCheckIn, Err: errors.New("down")}}}
	checker, _, _ := newChecker(gw)
	ctx, cancel := context.WithCancel(context.Background())
	checker.Sleep = func(context.Context, time.Duration) error { cancel(); return ctx.Err() }

	_, recorded, err := checker.CheckIn(ctx, report)

	if recorded || !errors.Is(err, context.Canceled) {
		t.Fatalf("%v %v", recorded, err)
	}
}
