package relay

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/aixlehq/aixle-runner-relay/internal/rails"
)

// refusals are the log lines of refused requests and failed streams.
func (e *edgeHarness) refusals() []map[string]any {
	var out []map[string]any
	for _, line := range strings.Split(e.logs.String(), "\n") {
		var entry map[string]any
		if json.Unmarshal([]byte(line), &entry) != nil || entry["msg"] != "the edge refused a request" {
			continue
		}
		out = append(out, entry)
	}
	return out
}

// wantRefusal checks that exactly one line was logged, with the reason, the status and
// the fields of the request, and no secret.
func (e *edgeHarness) wantRefusal(reason string, status float64, fields map[string]any) {
	e.t.Helper()
	lines := e.refusals()
	if len(lines) != 1 {
		e.t.Fatalf("%d refusal lines, want 1: %v", len(lines), lines)
	}
	line := lines[0]
	if line["reason"] != reason || line["status"] != status {
		e.t.Fatalf("logged %v, want reason %q status %v", line, reason, status)
	}
	for k, want := range fields {
		if line[k] != want {
			e.t.Errorf("field %s = %v, want %v (line %v)", k, line[k], want, line)
		}
	}
	for _, secret := range []string{tokenA, tokenB} {
		if strings.Contains(e.logs.String(), secret) {
			e.t.Errorf("the log has a route token")
		}
	}
}

func TestARefusalForAMachineThatIsNotConnectedIsLogged(t *testing.T) {
	e := newEdgeHarness(t)
	e.route(42, 123, tokenA)
	e.get("/t/"+tokenA+"/tty/x", "123")
	e.wantRefusal("machine_not_connected", 503, map[string]any{"session_id": float64(123), "surface": "tty", "environment_id": float64(42)})
}

func TestARefusalForASessionThatChangedIsLogged(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	env := int64(42)
	e.rails.holders[tokenA] = rails.Holder{SessionID: 123, EnvironmentID: &env, State: "ready", Ports: bridgePorts}
	e.rails.duringHolders = func() { e.route(42, 124, tokenB) }
	e.get("/t/"+tokenA+"/view/x", "123")
	e.wantRefusal("session_changed", 503, map[string]any{"session_id": float64(123), "surface": "view", "environment_id": float64(42)})
}

func TestARefusalForAHoldersErrorIsLoggedWithTheError(t *testing.T) {
	e := newEdgeHarness(t)
	e.rails.holderErr = errors.New("rails: holders answered 500")
	e.get("/t/"+tokenA+"/tty/x", "123")
	e.wantRefusal("holders_error", 503, map[string]any{"surface": "tty", "error": "rails: holders answered 500"})
}

func TestARefusalForASessionNoMachineHoldsIsLogged(t *testing.T) {
	e := newEdgeHarness(t)
	e.rails.holders[tokenA] = rails.Holder{SessionID: 123, EnvironmentID: nil, State: "ready"}
	e.get("/t/"+tokenA+"/tty/x", "123")
	e.wantRefusal("holders_no_machine", 503, map[string]any{"session_id": float64(123), "surface": "tty"})
}

func TestARefusalForAnUnknownTokenAndABadPathAreLogged(t *testing.T) {
	e := newEdgeHarness(t)
	e.get("/t/"+tokenB+"/ide/x", "1")
	e.wantRefusal("unknown_token", 404, map[string]any{"surface": "ide"})

	e2 := newEdgeHarness(t)
	e2.get("/t/short/tty/x", "1")
	e2.wantRefusal("bad_route", 404, nil)
}

func TestARefusalForAMismatchedSessionHeaderIsLogged(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	e.get("/t/"+tokenA+"/tty/x", "124")
	e.wantRefusal("session_mismatch", 403, map[string]any{"session_id": float64(123), "surface": "tty", "environment_id": float64(42)})
}

func TestAStreamTheRunnerRefusedIsLoggedWithTheResetCode(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 999, tokenA)
	e.get("/t/"+tokenA+"/tty/x", "999")
	e.wantRefusal("stream_refused", 502, map[string]any{"session_id": float64(999), "surface": "tty", "environment_id": float64(42)})
	if got, _ := e.refusals()[0]["error"].(string); !strings.Contains(got, "stream reset: refused") {
		t.Errorf("error = %v", got)
	}
}

func TestAStreamWhosePortDidNotAnswerIsLoggedWithTheResetCode(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.backends["tty"].Close()
	e.route(42, 123, tokenA)
	e.get("/t/"+tokenA+"/tty/x", "123")
	e.wantRefusal("stream_reset", 502, map[string]any{"session_id": float64(123), "surface": "tty", "environment_id": float64(42)})
	if got, _ := e.refusals()[0]["error"].(string); !strings.Contains(got, "stream reset: dial_failed") {
		t.Errorf("error = %v", got)
	}
}

// The platform's answer wins over a session the relay still holds for the machine and
// that no signal has changed since: the relay never heard of that session's end.
func TestAHoldersAnswerReplacesAStaleSessionTheRegistryHolds(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	e.route(42, 100, tokenB)
	env := int64(42)
	e.rails.holders[tokenA] = rails.Holder{SessionID: 123, EnvironmentID: &env, State: "ready", Ports: bridgePorts}

	resp, body := e.get("/t/"+tokenA+"/tty/x", "123")
	if resp.StatusCode != 200 || body != "tty /x" {
		t.Fatalf("%d %q", resp.StatusCode, body)
	}
	if cur, _ := e.server.Registry().Session(42); cur.SessionID != 123 || cur.RouteToken != tokenA {
		t.Fatalf("the registry holds %+v", cur)
	}
	if _, ok := e.server.Registry().ByRouteToken(tokenB); ok {
		t.Fatal("the stale token is still routed")
	}
	if len(e.refusals()) != 0 {
		t.Fatalf("refusals: %v", e.refusals())
	}
}
