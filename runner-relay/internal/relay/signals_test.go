package relay

import "testing"

// Rails publishes through Action Cable's pub/sub, which names a channel
// `<channel_prefix>:<channel>` (ActionCable::Server::Base#channel_with_prefix, Action
// Cable 8.1; test/services/runners/relay_signals_test.rb checks the Rails side against
// the same rule), and the channel alone when the configuration has no prefix. Until
// this test the relay joined the two without the colon and listened to a channel nobody
// published on: its tests used the same wrong name for both ends.
func TestChannelIsNamedTheWayActionCableNamesIt(t *testing.T) {
	for prefix, want := range map[string]string{
		"aixle_staging":     "aixle_staging:runner_relay",
		"aixle_development": "aixle_development:runner_relay",
		"":                  "runner_relay",
	} {
		if got := Channel(prefix); got != want {
			t.Errorf("Channel(%q) = %q, want %q", prefix, got, want)
		}
	}
}

// Every write of a route counts as a change, so that a `holders` answer that was out
// meanwhile knows it may be older.
func TestClearSessionCountsAsARouteChange(t *testing.T) {
	e := newEdgeHarness(t)
	e.route(42, 123, tokenA)
	before := e.server.routeGeneration()

	e.server.clearSession(123)

	if e.server.routeGeneration() != before+1 {
		t.Fatalf("generation %d, want %d", e.server.routeGeneration(), before+1)
	}
	if _, ok := e.server.Registry().ByRouteToken(tokenA); ok {
		t.Fatal("the route is still there")
	}
}

func TestSessionEndedCountsAsARouteChange(t *testing.T) {
	e := newEdgeHarness(t)
	e.route(42, 123, tokenA)
	before := e.server.routeGeneration()

	e.server.sessionEnded(123, 0, "ended")

	if e.server.routeGeneration() <= before {
		t.Fatal("a session end did not count as a route change")
	}
}

func TestRevokeStaleCountsAsARouteChange(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	m, _ := e.server.Registry().Machine(42)
	before := e.server.routeGeneration()

	e.server.revokeStale(m, 123)

	if e.server.routeGeneration() != before+1 {
		t.Fatalf("generation %d, want %d", e.server.routeGeneration(), before+1)
	}
}
