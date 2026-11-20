package cli

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

func TestTheTunnelStaysOffUnlessThePlatformTurnsItOn(t *testing.T) {
	off := protocol.CheckIn{}
	unknown := protocol.CheckIn{Config: protocol.CheckInConfig{Tunnel: &protocol.TunnelConfig{Mode: "always"}}}
	if tunnelManager(off, nil, nil, nil, "", quiet) != nil {
		t.Error("a check-in without config.tunnel turned the tunnel on")
	}
	if tunnelManager(unknown, nil, nil, nil, "", quiet) != nil {
		t.Error("a mode this runner does not know turned the tunnel on")
	}
}

func TestTunnelOverrideKeepsThePlatformURLsRule(t *testing.T) {
	for _, ok := range []string{"wss://relay.example.com/runner/v1/tunnel", "ws://127.0.0.1:4004/runner/v1/tunnel", "ws://localhost:4004/x", "ws://[::1]:4004/x"} {
		if got, err := tunnelOverride(ok); err != nil || got != ok {
			t.Errorf("%s: %q, %v", ok, got, err)
		}
	}
	for _, bad := range []string{"", "relay.example.com", "ws://relay.example.com/x", "http://127.0.0.1:4004", "https://relay.example.com",
		"wss://user:pw@relay.example.com/x", "wss://relay.example.com/x?a=1", "wss://relay.example.com/x#f"} {
		if got, err := tunnelOverride(bad); err == nil {
			t.Errorf("%q accepted as %q", bad, got)
		}
	}
}

func TestAnUnusableTunnelOverrideKeepsTheTunnelOff(t *testing.T) {
	on := protocol.CheckIn{Config: protocol.CheckInConfig{Tunnel: &protocol.TunnelConfig{Mode: "session"}}}
	if tunnelManager(on, nil, nil, nil, "http://nope", quiet) != nil {
		t.Error("an override that is not a ws URL left the tunnel on")
	}
}

func TestTunnelPathTakesOnlyThePlatformsOwnPaths(t *testing.T) {
	for path, want := range map[string]string{
		"":                       protocol.DefaultTunnelPath,
		"/runner/v1/tunnel":      "/runner/v1/tunnel",
		"/runner/v1/relay/ws":    "/runner/v1/relay/ws",
		"/elsewhere":             protocol.DefaultTunnelPath,
		"//evil.example/runner/": protocol.DefaultTunnelPath,
		"/runner/v1/t?x=1":       protocol.DefaultTunnelPath,
		"/runner/v1/t#frag":      protocol.DefaultTunnelPath,
		"runner/v1/tunnel":       protocol.DefaultTunnelPath,
	} {
		if got := tunnelPath(path); got != want {
			t.Errorf("tunnelPath(%q) = %q, want %q", path, got, want)
		}
	}
}

type fakeManager struct {
	run func(ctx context.Context) error
}

func (f fakeManager) Run(ctx context.Context) error { return f.run(ctx) }

func TestWithoutAManagerTheLoopRunsAlone(t *testing.T) {
	want := errors.New("loop ended")
	got := runWithTunnel(context.Background(), func(context.Context) error { return want }, nil, quiet)
	if got != want {
		t.Fatalf("got %v", got)
	}
}

func TestTheManagerRunsBesideTheLoopAndEndsWithIt(t *testing.T) {
	managerEnded := make(chan struct{})
	manager := fakeManager{run: func(ctx context.Context) error {
		<-ctx.Done()
		close(managerEnded)
		return nil
	}}

	err := runWithTunnel(context.Background(), func(ctx context.Context) error {
		time.Sleep(20 * time.Millisecond)
		return nil
	}, manager, quiet)

	if err != nil {
		t.Fatal(err)
	}
	select {
	case <-managerEnded:
	default:
		t.Fatal("runWithTunnel returned before the manager ended")
	}
}

func TestARefusalThatEndsTheRunnersWorkInTheTunnelEndsTheLoopAndIsReturned(t *testing.T) {
	stop := &tokens.StopError{Action: protocol.ActionRevoked, Err: errors.New("revoked")}
	manager := fakeManager{run: func(context.Context) error { return stop }}

	err := runWithTunnel(context.Background(), func(ctx context.Context) error {
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(5 * time.Second):
			return errors.New("the loop was not stopped")
		}
	}, manager, quiet)

	if got, ok := tokens.AsStop(err); !ok || got != stop {
		t.Fatalf("got %v", err)
	}
}

func TestOtherEndsOfTheManagerDoNotStopTheLoop(t *testing.T) {
	for name, managerErr := range map[string]error{
		"unsupported": tunnel.ErrUnsupported,
		"an error":    errors.New("boom"),
		"nil":         nil,
	} {
		t.Run(name, func(t *testing.T) {
			want := errors.New("the loop's own end")
			manager := fakeManager{run: func(context.Context) error { return managerErr }}

			err := runWithTunnel(context.Background(), func(ctx context.Context) error {
				time.Sleep(30 * time.Millisecond)
				if ctx.Err() != nil {
					t.Error("the manager's end stopped the loop")
				}
				return want
			}, manager, quiet)

			if err != want {
				t.Fatalf("got %v", err)
			}
		})
	}
}
