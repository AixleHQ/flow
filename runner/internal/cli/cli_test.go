package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/moby/moby/api/types/system"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
)

type fakeDocker struct{ api string }

func (f fakeDocker) ServerVersion(context.Context, client.ServerVersionOptions) (client.ServerVersionResult, error) {
	return client.ServerVersionResult{Version: "27.1.0", APIVersion: f.api}, nil
}

func (f fakeDocker) Info(context.Context, client.InfoOptions) (client.SystemInfoResult, error) {
	return client.SystemInfoResult{Info: system.Info{DockerRootDir: "/var/lib/docker"}}, nil
}

func goodMachine() preflight.Env {
	return preflight.Env{GOOS: "linux", GOARCH: "arm64", Docker: fakeDocker{api: "1.47"},
		FreeBytes: func(string) (uint64, error) { return 50 << 30, nil }}
}

type request struct {
	method, path, auth string
	body               map[string]any
}

// platform is a fake gateway answering each endpoint with a scripted response.
type platform struct {
	mu       sync.Mutex
	requests []request
	answers  map[string][]answer
}

type answer struct {
	status int
	body   any
}

func (p *platform) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	p.mu.Lock()
	defer p.mu.Unlock()
	raw, _ := io.ReadAll(r.Body)
	var body map[string]any
	_ = json.Unmarshal(raw, &body)
	p.requests = append(p.requests, request{r.Method, r.URL.Path, r.Header.Get("Authorization"), body})
	key := r.Method + " " + r.URL.Path
	queue := p.answers[key]
	if len(queue) == 0 {
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	a := queue[0]
	if len(queue) > 1 {
		p.answers[key] = queue[1:]
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(a.status)
	if a.body != nil {
		_ = json.NewEncoder(w).Encode(a.body)
	}
}

func newPlatform(t *testing.T, answers map[string][]answer) (*platform, string) {
	p := &platform{answers: answers}
	s := httptest.NewServer(p)
	t.Cleanup(s.Close)
	return p, s.URL
}

func ts(d time.Duration) string { return time.Now().Add(d).UTC().Format(time.RFC3339) }

func registered() answer {
	return answer{201, map[string]any{
		"environment":  map[string]any{"id": 42, "key": "aixle-r7-build", "display_name": "build-01", "state": "registered"},
		"access_token": "aracc_one", "access_token_expires_at": ts(time.Hour),
		"refresh_token": "arref_one", "refresh_token_expires_at": ts(720 * time.Hour),
	}}
}

func refused(status int, code string) answer {
	return answer{status, map[string]any{"error": code, "message": "refused"}}
}

func configureOpts(url, dir string) ConfigureOptions {
	return ConfigureOptions{URL: url, Token: "arreg_token", Name: " build-01 ", StateDir: dir, Preflight: goodMachine(), Out: io.Discard}
}

func TestConfigureRegistersAndStoresTheCredentials(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	if err := Configure(context.Background(), configureOpts(url, dir)); err != nil {
		t.Fatal(err)
	}
	if len(p.requests) != 1 {
		t.Fatalf("requests %v", p.requests)
	}
	r := p.requests[0]
	facts, _ := r.body["facts"].(map[string]any)
	if r.auth != "Bearer arreg_token" || r.body["name"] != "build-01" || r.body["os"] != "linux" || r.body["arch"] != "arm64" ||
		r.body["ephemeral"] != false || facts["docker"] != "27.1.0" || facts["docker_api"] != "1.47" {
		t.Fatalf("register sent %#v", r)
	}

	creds, err := credentials.NewStore(dir).Load()
	if err != nil {
		t.Fatal(err)
	}
	if creds.URL != url || creds.AccessToken != "aracc_one" || creds.RefreshToken != "arref_one" || creds.Environment.ID != 42 {
		t.Fatalf("stored %#v", creds)
	}
	info, _ := os.Stat(credentials.NewStore(dir).Path())
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", info.Mode().Perm())
	}
}

func TestAFailedPreflightRegistersNothing(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	opts := configureOpts(url, dir)
	opts.Preflight.Docker = fakeDocker{api: "1.39"}
	err := Configure(context.Background(), opts)
	if err == nil || !strings.Contains(err.Error(), "not registered") || !strings.Contains(err.Error(), "1.41") {
		t.Fatalf("got %v", err)
	}
	if len(p.requests) != 0 {
		t.Fatalf("register was called: %v", p.requests)
	}
	if credentials.NewStore(dir).Exists() {
		t.Fatal("credentials were stored")
	}
}

func TestConfigureRefusals(t *testing.T) {
	cases := map[string]struct {
		answer answer
		want   string
	}{
		"invalid_token":           {refused(401, "invalid_token"), "unknown, used or expired"},
		"invalid_registration":    {refused(422, "invalid_registration"), "was not spent"},
		"ephemeral_not_supported": {refused(422, "ephemeral_not_supported"), "was not spent"},
		"runners_disabled":        {refused(403, "runners_disabled"), "try again later with the same token"},
		"unsupported_protocol":    {refused(400, "unsupported_protocol"), "update aixle-runner"},
		"runner_revoked":          {refused(401, "runner_revoked"), "revoked or deleted"},
	}
	for name, tc := range cases {
		_, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {tc.answer}})
		dir := t.TempDir()
		err := Configure(context.Background(), configureOpts(url, dir))
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: got %v", name, err)
		}
		if err != nil && strings.Contains(err.Error(), "arreg_token") {
			t.Errorf("%s: the error carries the token", name)
		}
		if credentials.NewStore(dir).Exists() {
			t.Errorf("%s: credentials were stored", name)
		}
	}
}

func TestConfigureRefusesARegisteredMachine(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	_ = Configure(context.Background(), configureOpts(url, dir))
	err := Configure(context.Background(), configureOpts(url, dir))
	if err == nil || !strings.Contains(err.Error(), "unregister") || len(p.requests) != 1 {
		t.Fatalf("got %v after %d requests", err, len(p.requests))
	}
}

func TestConfigureNeedsItsFlags(t *testing.T) {
	for _, change := range []func(*ConfigureOptions){
		func(o *ConfigureOptions) { o.URL = "" },
		func(o *ConfigureOptions) { o.Token = "" },
		func(o *ConfigureOptions) { o.Name = "  " },
		func(o *ConfigureOptions) { o.URL = "http://flow.aixle.com" },
	} {
		o := configureOpts("https://flow.aixle.com", t.TempDir())
		change(&o)
		if err := Configure(context.Background(), o); err == nil {
			t.Errorf("accepted %#v", o)
		}
	}
}

func storeCreds(t *testing.T, dir, url string) {
	t.Helper()
	exp := time.Now().Add(time.Hour).UTC().Truncate(time.Second)
	err := credentials.NewStore(dir).Save(credentials.Credentials{URL: url, TokenPair: protocol.TokenPair{
		AccessToken: "aracc_one", AccessTokenExpiresAt: exp, RefreshToken: "arref_one", RefreshTokenExpiresAt: exp.Add(720 * time.Hour),
	}})
	if err != nil {
		t.Fatal(err)
	}
	j, _ := journal.Open(dir, nil)
	_ = j.Record(protocol.Op{ID: 1, Sequence: 1, Op: "image.ensure"}, protocol.Result{Status: protocol.StatusOK})
}

func TestUnregisterDeletesTheRegistrationThenTheLocalState(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"DELETE /runner/v1/registration": {{204, nil}}})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	if err := Unregister(context.Background(), UnregisterOptions{StateDir: dir, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	if len(p.requests) != 1 || p.requests[0].auth != "Bearer aracc_one" {
		t.Fatalf("requests %v", p.requests)
	}
	if credentials.NewStore(dir).Exists() {
		t.Fatal("the credentials are still there")
	}
	if _, err := os.Stat(dir + "/" + journal.FileName); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("the journal is still there")
	}
}

func TestUnregisterOfAMachineThePlatformDroppedCleansUp(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"DELETE /runner/v1/registration": {refused(401, "invalid_token")},
		"POST /runner/v1/token":          {refused(401, "invalid_token")},
	})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	if err := Unregister(context.Background(), UnregisterOptions{StateDir: dir, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	if len(p.requests) != 2 || credentials.NewStore(dir).Exists() {
		t.Fatalf("requests %v", p.requests)
	}
}

func TestUnregisterKeepsTheCredentialsWhenItCannotReachThePlatform(t *testing.T) {
	_, url := newPlatform(t, map[string][]answer{"DELETE /runner/v1/registration": {refused(403, "runners_disabled")}})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	var out bytes.Buffer
	err := Unregister(context.Background(), UnregisterOptions{StateDir: dir, Out: &out})
	if err == nil || !strings.Contains(err.Error(), "kept") {
		t.Fatalf("got %v", err)
	}
	if !credentials.NewStore(dir).Exists() {
		t.Fatal("the credentials were deleted")
	}
}

func TestUnregisterOfAnUnconfiguredMachine(t *testing.T) {
	err := Unregister(context.Background(), UnregisterOptions{StateDir: t.TempDir(), Out: io.Discard})
	if !errors.Is(err, credentials.ErrNotConfigured) {
		t.Fatalf("got %v", err)
	}
}
