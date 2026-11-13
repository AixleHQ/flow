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
		{"runner_version_unsupported", refusal(EndpointRegister, 400, "runner_version_unsupported"), ActionUpdate},
		{"release not_found", refusal(EndpointReleases, 404, "not_found"), ActionBug},
		{"invalid_request", refusal(EndpointOps, 400, "invalid_request"), ActionBug},
		{"invalid_result", refusal(EndpointResult, 422, "invalid_result"), ActionBug},
		{"invalid_check_in", refusal(EndpointCheckIn, 422, "invalid_check_in"), ActionBug},
		{"check-in invalid_token", refusal(EndpointCheckIn, 401, "invalid_token"), ActionRefresh},
		{"check-in below the minimum", refusal(EndpointCheckIn, 400, "runner_version_unsupported"), ActionUpdate},
		{"400 without the JSON shape", refusal(EndpointResult, 400, ""), ActionBug},
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

// A redirect from the endpoint comes back unchanged (§5.8): following it would
// send the bearer outside the proxy prefix.
func TestProxyReturnsARedirectUnchanged(t *testing.T) {
	var requests []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests = append(requests, r.URL.Path)
		w.Header().Set("Location", "/runner/v1/ops")
		w.WriteHeader(http.StatusTemporaryRedirect)
	}))
	defer server.Close()
	for _, injected := range []*http.Client{nil, {Timeout: 5 * time.Second}} {
		requests = nil
		c, err := NewClient(server.URL, "0.0.0-dev", injected)
		if err != nil {
			t.Fatal(err)
		}
		resp, err := c.Proxy(context.Background(), "aracc_secret", http.MethodPost, "mcp", http.Header{}, []byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusTemporaryRedirect || resp.Header.Get("Location") != "/runner/v1/ops" {
			t.Errorf("got %d %q", resp.StatusCode, resp.Header.Get("Location"))
		}
		if len(requests) != 1 || requests[0] != "/runner/v1/proxy/mcp" {
			t.Errorf("requests %v", requests)
		}
		if injected != nil && injected.CheckRedirect != nil {
			t.Error("the injected client was changed")
		}
	}
}

// A cross-origin redirect is not followed, so no session key leaves the gateway.
func TestProxyDoesNotFollowACrossOriginRedirect(t *testing.T) {
	other := 0
	elsewhere := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		other++
		if r.Header.Get("X-Session-Key") != "" {
			t.Error("the session key reached another origin")
		}
	}))
	defer elsewhere.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, elsewhere.URL+"/steal", http.StatusFound)
	}))
	defer server.Close()
	c, err := NewClient(server.URL, "0.0.0-dev", nil)
	if err != nil {
		t.Fatal(err)
	}
	header := http.Header{"X-Session-Key": []string{"sk_secret"}}
	resp, err := c.Proxy(context.Background(), "aracc_secret", http.MethodGet, "assets/x", header, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusFound || other != 0 {
		t.Errorf("got %d, %d requests elsewhere", resp.StatusCode, other)
	}
}

// check-in sends the report as JSON with the access token as the bearer and
// both protocol headers, and reads the environment, the config and the update.
func TestCheckInSendsTheReportAndReadsTheAnswer(t *testing.T) {
	var method, path, auth, version, proto, contentType, body string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method, path, auth = r.Method, r.URL.Path, r.Header.Get("Authorization")
		version, proto, contentType = r.Header.Get("X-Aixle-Runner-Version"), r.Header.Get("X-Aixle-Runner-Protocol"), r.Header.Get("Content-Type")
		raw := make([]byte, 512)
		n, _ := r.Body.Read(raw)
		body = string(raw[:n])
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"environment":{"id":42,"key":"aixle-r7-x","display_name":"build-01","state":"registered"},` +
			`"config":{"upload_max_bytes":104857600,"future":1},"update":{"version":"1.5.0","sha256":"abc"}}`))
	}))
	defer server.Close()
	c, err := NewClient(server.URL, "1.4.0", nil)
	if err != nil {
		t.Fatal(err)
	}

	got, err := c.CheckIn(context.Background(), "aracc_one", CheckInRequest{OS: "linux", Arch: "amd64", Facts: map[string]any{"docker": "27.2.0"}})

	if err != nil {
		t.Fatal(err)
	}
	if method != http.MethodPost || path != "/runner/v1/check-in" || auth != "Bearer aracc_one" || version != "1.4.0" || proto != "1" || contentType != "application/json" {
		t.Errorf("%s %s auth %q version %q protocol %q type %q", method, path, auth, version, proto, contentType)
	}
	if body != `{"os":"linux","arch":"amd64","facts":{"docker":"27.2.0"}}` {
		t.Errorf("body %s", body)
	}
	if got.Environment.ID != 42 || got.Config.UploadMaxBytes != 104857600 || got.Update == nil || got.Update.Version != "1.5.0" {
		t.Errorf("answer %+v", got)
	}
}

func TestCheckInRefusalIsClassified(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"runner_version_unsupported","message":"aixle-runner 1.1.9 is no longer supported (minimum 1.2.0). Update aixle-runner."}`))
	}))
	defer server.Close()
	c, _ := NewClient(server.URL, "1.1.9", nil)

	_, err := c.CheckIn(context.Background(), "aracc_one", CheckInRequest{})

	r, ok := AsRefusal(err)
	if !ok || r.Endpoint != EndpointCheckIn || r.Code != "runner_version_unsupported" || Classify(err) != ActionUpdate {
		t.Fatalf("%v", err)
	}
}
