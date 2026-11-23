package relay

import "testing"

func TestSetSessionIfAbsentKeepsARoutedSessionAndReplacesAPlaceholder(t *testing.T) {
	r := NewRegistry()
	ports := map[string]int{"tty": 7681}

	// Nothing held: stored.
	if _, had, stored := r.SetSessionIfAbsent(42, SessionRoute{SessionID: 1, RouteToken: "a", Ports: ports}); had || !stored {
		t.Fatalf("empty registry: had=%v stored=%v, want had=false stored=true", had, stored)
	}

	// A routed session is not replaced, and its token still resolves.
	if prev, had, stored := r.SetSessionIfAbsent(42, SessionRoute{SessionID: 2, RouteToken: "b", Ports: ports}); !had || stored || prev.SessionID != 1 {
		t.Fatalf("routed session: prev=%+v had=%v stored=%v, want session 1 kept", prev, had, stored)
	}
	if got, _ := r.Session(42); got.SessionID != 1 || got.RouteToken != "a" {
		t.Fatalf("session = %+v, want session 1 with token a", got)
	}
	if _, ok := r.ByRouteToken("b"); ok {
		t.Fatal("the refused route's token must not resolve")
	}

	// A ticket's placeholder (no token) counts as none.
	r.SetSession(43, SessionRoute{SessionID: 5})
	prev, had, stored := r.SetSessionIfAbsent(43, SessionRoute{SessionID: 6, RouteToken: "c", Ports: ports})
	if !had || !stored || prev.SessionID != 5 {
		t.Fatalf("placeholder: prev=%+v had=%v stored=%v, want the placeholder replaced", prev, had, stored)
	}
	if got, ok := r.ByRouteToken("c"); !ok || got.SessionID != 6 || got.EnvironmentID != 43 {
		t.Fatalf("by token = %+v %v, want session 6 on 43", got, ok)
	}
}
