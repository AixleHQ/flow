package protocol

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParsePlatformURL(t *testing.T) {
	for _, ok := range []string{"https://flow.aixle.com", "https://flow.aixle.com/", "http://localhost:4003", "http://127.0.0.1:4003", "http://[::1]:4003"} {
		if _, err := ParsePlatformURL(ok); err != nil {
			t.Errorf("%s refused: %v", ok, err)
		}
	}
	for _, bad := range []string{"", "flow.aixle.com", "http://flow.aixle.com", "ftp://flow.aixle.com", "https://user:pw@flow.aixle.com", "https://flow.aixle.com/?a=1"} {
		if _, err := ParsePlatformURL(bad); err == nil {
			t.Errorf("%q accepted", bad)
		}
	}
}

func TestRefusalWithoutTheJSONShape(t *testing.T) {
	// 413 and 429 answer plain text (PROTOCOL.md §2).
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusTooManyRequests)
		_, _ = w.Write([]byte("Retry later\n"))
	}))
	defer server.Close()
	c, err := NewClient(server.URL, "0.0.0-dev", nil)
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.PollOps(context.Background(), "aracc_x", 0, 0)
	r, ok := AsRefusal(err)
	if !ok || r.Status != 429 || r.Code != "" {
		t.Fatalf("got %#v", err)
	}
	if Classify(err) != ActionBackoff {
		t.Errorf("429 is %s", Classify(err))
	}
}

func TestNetworkErrorIsBackoff(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	url := server.URL
	server.Close()
	c, _ := NewClient(url, "0.0.0-dev", &http.Client{Timeout: time.Second})
	_, err := c.Refresh(context.Background(), "arref_secret")
	var netErr *NetworkError
	if !errors.As(err, &netErr) {
		t.Fatalf("got %v", err)
	}
	if Classify(err) != ActionBackoff {
		t.Errorf("a network error is %s", Classify(err))
	}
	if strings.Contains(err.Error(), "arref_secret") {
		t.Error("the error carries the token")
	}
}

// Every row of "What a runner does on each refusal" (PROTOCOL.md §3).
func TestClassify(t *testing.T) {
	refusal := func(e Endpoint, status int, code string) error {
		return &Refusal{Endpoint: e, Status: status, Code: code, Message: "m"}
	}
	cases := []struct {
		name string
		err  error
		want Action
	}{
		{"access invalid_token: ops", refusal(EndpointOps, 401, "invalid_token"), ActionRefresh},
		{"access invalid_token: result", refusal(EndpointResult, 401, "invalid_token"), ActionRefresh},
		{"access invalid_token: registration", refusal(EndpointRegistration, 401, "invalid_token"), ActionRefresh},
		{"token invalid_token", refusal(EndpointToken, 401, "invalid_token"), ActionReregister},
		{"register invalid_token", refusal(EndpointRegister, 401, "invalid_token"), ActionNewRegistrationToken},
		{"credential_reuse_detected", refusal(EndpointToken, 401, "credential_reuse_detected"), ActionReuseDetected},
		{"runner_revoked", refusal(EndpointOps, 401, "runner_revoked"), ActionRevoked},
		{"runners_disabled", refusal(EndpointOps, 403, "runners_disabled"), ActionBackoff},
		{"429", refusal(EndpointOps, 429, ""), ActionBackoff},
		{"413", refusal(EndpointResult, 413, ""), ActionBug},
		{"unsupported_protocol", refusal(EndpointOps, 400, "unsupported_protocol"), ActionUpdate},
		{"invalid_runner_version", refusal(EndpointRegister, 400, "invalid_runner_version"), ActionUpdate},
		{"invalid_request", refusal(EndpointOps, 400, "invalid_request"), ActionBug},
		{"invalid_result", refusal(EndpointResult, 422, "invalid_result"), ActionBug},
		{"400 without the JSON shape", refusal(EndpointResult, 400, ""), ActionBug},
		{"ephemeral_not_supported", refusal(EndpointRegister, 422, "ephemeral_not_supported"), ActionFixConfiguration},
		{"invalid_registration", refusal(EndpointRegister, 422, "invalid_registration"), ActionFixConfiguration},
		{"result not_found", refusal(EndpointResult, 404, "not_found"), ActionDrop},
		{"502 from a proxy", refusal(EndpointOps, 502, ""), ActionBackoff},
		{"network", &NetworkError{Endpoint: EndpointOps, Err: errors.New("reset")}, ActionBackoff},
	}
	for _, tc := range cases {
		if got := Classify(tc.err); got != tc.want {
			t.Errorf("%s: %s, want %s", tc.name, got, tc.want)
		}
	}
}

func TestRefusalParsesTheJSONShape(t *testing.T) {
	r := newRefusal(EndpointOps, 401, []byte(`{"error":"invalid_token","message":"The token is unknown."}`))
	if r.Code != "invalid_token" || r.Message != "The token is unknown." {
		t.Fatalf("got %#v", r)
	}
	// Only exactly the two strings are the refusal shape (§3).
	r = newRefusal(EndpointResult, 400, []byte(`{"status":400,"error":"Bad Request"}`))
	if r.Code != "" {
		t.Fatalf("got %#v", r)
	}
}
