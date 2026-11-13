package cli

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/moby/moby/api/types/system"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/statedir"
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
	method, path, query, auth string
	body                      map[string]any
}

// platform is a fake gateway answering each endpoint with a scripted response.
type platform struct {
	mu       sync.Mutex
	requests []request
	answers  map[string][]answer
	// seen, when set, is called with each request.
	seen func(request)
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
	req := request{r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Authorization"), body}
	p.requests = append(p.requests, req)
	if p.seen != nil {
		p.seen(req)
	}
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

// checkedIn is the platform's answer to a check-in: nothing to update.
func checkedIn() answer {
	return answer{200, map[string]any{
		"environment": map[string]any{"id": 42, "key": "aixle-r7-build", "display_name": "build-01", "state": "registered"},
		"config":      map[string]any{"upload_max_bytes": 104857600},
	}}
}

// newPlatform serves the answers it is given. A host runner checks in after it
// starts (PROTOCOL.md §5.9), so unless a test scripts the check-in, the platform
// takes it.
func newPlatform(t *testing.T, answers map[string][]answer) (*platform, string) {
	if _, scripted := answers["POST /runner/v1/check-in"]; !scripted {
		answers["POST /runner/v1/check-in"] = []answer{checkedIn()}
	}
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

func credsExist(t *testing.T, dir string) bool {
	t.Helper()
	ok, err := credentials.NewStore(dir).Exists()
	if err != nil {
		t.Fatal(err)
	}
	return ok
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
		facts["docker"] != "27.1.0" || facts["docker_api"] != "1.47" {
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

func TestConfigureWithoutTheOptOutSendsNoAutoUpdate(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	if err := Configure(context.Background(), configureOpts(url, dir)); err != nil {
		t.Fatal(err)
	}
	if _, sent := p.requests[0].body["auto_update"]; sent {
		t.Fatalf("register sent %#v", p.requests[0].body)
	}
	creds, _ := credentials.NewStore(dir).Load()
	if creds.AutoUpdate != nil || !creds.AutoUpdateEnabled() {
		t.Fatalf("stored %#v", creds.AutoUpdate)
	}
}

func TestConfigureNoAutoUpdateTellsThePlatformAndKeepsTheOptOut(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	opts := configureOpts(url, dir)
	opts.NoAutoUpdate = true
	var out bytes.Buffer
	opts.Out = &out
	if err := Configure(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if v, sent := p.requests[0].body["auto_update"]; !sent || v != false {
		t.Fatalf("register sent %#v", p.requests[0].body)
	}
	creds, err := credentials.NewStore(dir).Load()
	if err != nil || creds.AutoUpdateEnabled() {
		t.Fatalf("stored %#v, %v", creds.AutoUpdate, err)
	}
	if !strings.Contains(out.String(), "Self-update is off") {
		t.Fatalf("printed %q", out.String())
	}
}

// configure run from the published image, which sets NoSelfUpdateEnv, registers
// the machine as one that does not update itself, as --no-auto-update does.
func TestConfigureWithNoSelfUpdateRegistersAsNoAutoUpdate(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	opts := configureOpts(url, dir)
	opts.NoSelfUpdate = true
	var out bytes.Buffer
	opts.Out = &out
	if err := Configure(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if v, sent := p.requests[0].body["auto_update"]; !sent || v != false {
		t.Fatalf("register sent %#v", p.requests[0].body)
	}
	creds, err := credentials.NewStore(dir).Load()
	if err != nil || creds.AutoUpdateEnabled() {
		t.Fatalf("stored %#v, %v", creds.AutoUpdate, err)
	}
	if !strings.Contains(out.String(), "Self-update is off") {
		t.Fatalf("printed %q", out.String())
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
	if credsExist(t, dir) {
		t.Fatal("credentials were stored")
	}
}

func TestConfigureRefusals(t *testing.T) {
	cases := map[string]struct {
		answer answer
		want   string
	}{
		"invalid_token":        {refused(401, "invalid_token"), "unknown, used or expired"},
		"invalid_registration": {refused(422, "invalid_registration"), "was not spent"},
		"runners_disabled":     {refused(403, "runners_disabled"), "try again later with the same token"},
		"unsupported_protocol": {refused(400, "unsupported_protocol"), "update aixle-runner"},
		"runner_version_unsupported": {answer{400, map[string]any{
			"error": "runner_version_unsupported", "message": "aixle-runner 0.0.0-dev is no longer supported (minimum 0.1.0)."}},
			"is no longer supported (minimum 0.1.0). The registration token was not spent: update aixle-runner"},
		"runner_revoked": {refused(401, "runner_revoked"), "revoked or deleted"},
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
		if credsExist(t, dir) {
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
	_ = j.Record(protocol.Op{ID: 1, Sequence: 1, Op: "env.scrub"}, protocol.Result{Status: protocol.StatusOK})
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
	if credsExist(t, dir) {
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
	if len(p.requests) != 2 || credsExist(t, dir) {
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
	if !credsExist(t, dir) {
		t.Fatal("the credentials were deleted")
	}
}

func TestUnregisterOfAnUnconfiguredMachine(t *testing.T) {
	err := Unregister(context.Background(), UnregisterOptions{StateDir: t.TempDir(), Out: io.Discard})
	if !errors.Is(err, credentials.ErrNotConfigured) {
		t.Fatalf("got %v", err)
	}
}

// hostDocker is the Docker of a host runner that is given no op to run, on a
// machine with no container of the environment to serve a proxy for again.
type hostDocker struct{ docker.API }

func (hostDocker) ServerVersion(ctx context.Context, o client.ServerVersionOptions) (client.ServerVersionResult, error) {
	return fakeDocker{api: "1.47"}.ServerVersion(ctx, o)
}

func (hostDocker) Info(ctx context.Context, o client.InfoOptions) (client.SystemInfoResult, error) {
	return fakeDocker{api: "1.47"}.Info(ctx, o)
}

func (hostDocker) ContainerList(context.Context, client.ContainerListOptions) (client.ContainerListResult, error) {
	return client.ContainerListResult{}, nil
}

// unlistableDocker is the Docker of a machine whose daemon cannot list the
// environment's containers when the host runner starts.
type unlistableDocker struct{ hostDocker }

func (unlistableDocker) ContainerList(context.Context, client.ContainerListOptions) (client.ContainerListResult, error) {
	return client.ContainerListResult{}, errors.New("Cannot connect to the Docker daemon")
}

// A host runner that cannot list the environment's containers has served no
// running session's proxy again, and nothing would try later: it exits, with a
// failure the service manager restarts, before it polls.
func TestAHostRunnerThatCannotResumeItsSessionsExitsBeforePolling(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"GET /runner/v1/ops": {{200, map[string]any{"ops": []any{}}}}})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	err := RunHost(ctx, HostOptions{StateDir: dir, Docker: unlistableDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err == nil || !strings.Contains(err.Error(), "Cannot connect to the Docker daemon") || !strings.Contains(err.Error(), "restarts") {
		t.Fatalf("got %v", err)
	}
	if NeedsOperator(err) {
		t.Fatalf("a restart can fix it, but it is reported as needing an operator: %v", err)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, r := range p.requests {
		if r.method == http.MethodGet && r.path == "/runner/v1/ops" {
			t.Fatalf("the host runner polled with its sessions not served again: %v", p.requests)
		}
	}
}

// The relay's sockets are 0666 below the state directory, so the host runner
// narrows a wider state directory to 0700 when it starts.
func TestAHostRunnerNarrowsAWiderStateDirectory(t *testing.T) {
	_, url := newPlatform(t, map[string][]answer{})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = RunHost(ctx, HostOptions{StateDir: dir, Docker: unlistableDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o700 {
		t.Fatalf("the state directory is still %04o", info.Mode().Perm())
	}
}

// A state directory the host runner cannot narrow stops it until an operator
// acts, with an error that names the directory and its mode, before it serves
// any relay or polls.
func TestAHostRunnerThatCannotNarrowItsStateDirectoryNeedsAnOperator(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	restrictStateDir = func(dir string) error {
		return fmt.Errorf("the state directory %s is mode 0755, and the runner could not narrow it to 0700: %w", dir, fs.ErrPermission)
	}
	t.Cleanup(func() { restrictStateDir = statedir.Restrict })
	err := RunHost(context.Background(), HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err == nil || !NeedsOperator(err) || !strings.Contains(err.Error(), dir) || !strings.Contains(err.Error(), "0755") {
		t.Fatalf("got %v", err)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.requests) != 0 {
		t.Fatalf("the host runner called the platform: %v", p.requests)
	}
}

func TestConfigureDeletesTheJournalOfAPreviousRegistration(t *testing.T) {
	dir := t.TempDir()
	// The credentials are gone, as after credential_reuse_detected, but the
	// previous environment's journal is still there with after > 0.
	j, err := journal.Open(dir, nil)
	if err != nil {
		t.Fatal(err)
	}
	_ = j.Record(protocol.Op{ID: 900, Sequence: 7, Op: "env.scrub"}, protocol.Result{Status: protocol.StatusOK})
	if err := j.Acknowledge(900); err != nil || j.After() != 7 {
		t.Fatalf("after %d, %v", j.After(), err)
	}

	p, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/register": {registered()},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	})
	if err := Configure(context.Background(), configureOpts(url, dir)); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	p.mu.Lock()
	p.seen = func(r request) {
		if r.method == http.MethodGet {
			cancel()
		}
	}
	p.mu.Unlock()
	err = RunHost(ctx, HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err != nil {
		t.Fatal(err)
	}
	var polls []string
	for _, r := range p.requests {
		if r.method == http.MethodGet {
			polls = append(polls, r.query)
		}
	}
	if len(polls) == 0 || !strings.HasPrefix(polls[0], "after=0&") {
		t.Fatalf("polled with %v", polls)
	}
}

func TestConfigureRegistersNothingWhenItCannotCheckTheCredentials(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads any directory")
	}
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := filepath.Join(t.TempDir(), "state")
	if err := os.Mkdir(dir, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	err := Configure(context.Background(), configureOpts(url, dir))
	if err == nil || !strings.Contains(err.Error(), "registered nothing") || !strings.Contains(err.Error(), "root") {
		t.Fatalf("got %v", err)
	}
	if len(p.requests) != 0 {
		t.Fatalf("register was called: %v", p.requests)
	}
}

func TestConfigureRegistersNothingWhenItCannotWriteTheStateDirectory(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root writes any directory")
	}
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	parent := t.TempDir()
	if err := os.Chmod(parent, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(parent, 0o700) })
	for _, dir := range []string{parent, filepath.Join(parent, "missing")} {
		err := Configure(context.Background(), configureOpts(url, dir))
		if err == nil || !strings.Contains(err.Error(), "not spent") || !strings.Contains(err.Error(), "root") {
			t.Fatalf("%s: got %v", dir, err)
		}
	}
	if len(p.requests) != 0 {
		t.Fatalf("register was called: %v", p.requests)
	}
}

func TestConfigureAndUnregisterRefuseWhileAHostRunnerRuns(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/register":       {registered()},
		"DELETE /runner/v1/registration": {{204, nil}},
	})
	empty, registeredDir := t.TempDir(), t.TempDir()
	storeCreds(t, registeredDir, url)
	for _, dir := range []string{empty, registeredDir} {
		lock, err := statedir.Acquire(dir)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = lock.Release() })
	}

	err := Configure(context.Background(), configureOpts(url, empty))
	if err == nil || !strings.Contains(err.Error(), "aixle-runner service stop") {
		t.Fatalf("configure: got %v", err)
	}
	err = Unregister(context.Background(), UnregisterOptions{StateDir: registeredDir, Out: io.Discard})
	if err == nil || !strings.Contains(err.Error(), "aixle-runner service stop") {
		t.Fatalf("unregister: got %v", err)
	}
	if len(p.requests) != 0 || !credsExist(t, registeredDir) {
		t.Fatalf("requests %v", p.requests)
	}
}

func TestASecondHostRunnerRefusesAtOnce(t *testing.T) {
	dir := t.TempDir()
	storeCreds(t, dir, "https://flow.aixle.com")
	lock, err := statedir.Acquire(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	err = RunHost(context.Background(), HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err == nil || !strings.Contains(err.Error(), "only one host runner") {
		t.Fatalf("got %v", err)
	}
	// systemd may restart the unit: the other process can be gone by then.
	if NeedsOperator(err) {
		t.Fatal("a held lock stops the unit for good")
	}
}

func TestAHostRunnerWithoutUsableCredentialsNeedsAnOperator(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "never-configured")
	empty := t.TempDir()
	corrupt := t.TempDir()
	if err := os.WriteFile(filepath.Join(corrupt, credentials.FileName), []byte("{"), 0o600); err != nil {
		t.Fatal(err)
	}
	incomplete := t.TempDir()
	if err := os.WriteFile(filepath.Join(incomplete, credentials.FileName), []byte(`{"url":"https://flow.aixle.com"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{missing, empty, corrupt, incomplete} {
		err := RunHost(context.Background(), HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
		if err == nil || !NeedsOperator(err) {
			t.Errorf("%s: got %v", dir, err)
		}
	}
}

func corruptJournal(t *testing.T, dir string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, journal.FileName), []byte(`{"after":`), 0o600); err != nil {
		t.Fatal(err)
	}
}

func TestAHostRunnerWithACorruptJournalNeedsAnOperator(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	corruptJournal(t, dir)
	err := RunHost(context.Background(), HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	if err == nil || !NeedsOperator(err) || !errors.Is(err, journal.ErrInvalid) {
		t.Fatalf("got %v", err)
	}
	for _, want := range []string{filepath.Join(dir, journal.FileName), "aixle-runner unregister", "configure` with a new registration token"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("the message lacks %q: %v", want, err)
		}
	}
	if len(p.requests) != 0 {
		t.Fatalf("requests %v", p.requests)
	}
}

func TestUnregisterAndConfigureWorkWithACorruptJournal(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"DELETE /runner/v1/registration": {{204, nil}},
		"POST /runner/v1/register":       {registered()},
	})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	corruptJournal(t, dir)
	if err := Unregister(context.Background(), UnregisterOptions{StateDir: dir, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	if credsExist(t, dir) {
		t.Fatal("the credentials are still there")
	}
	// Configure also copes with the corrupt file, should it come back.
	corruptJournal(t, dir)
	if err := Configure(context.Background(), configureOpts(url, dir)); err != nil {
		t.Fatal(err)
	}
	if !credsExist(t, dir) || len(p.requests) != 2 {
		t.Fatalf("requests %v", p.requests)
	}
	j, err := journal.Open(dir, nil)
	if err != nil || j.After() != 0 {
		t.Fatalf("journal after configure: %v", err)
	}
}

func TestConfigureAsRootRegistersNothingWhenTheServiceUserLookupFails(t *testing.T) {
	cases := map[string]func(string) (*user.User, error){
		"lookup": func(string) (*user.User, error) { return nil, errors.New("nss: connection refused") },
		"uid":    func(string) (*user.User, error) { return &user.User{Uid: "x", Gid: "997"}, nil },
		"gid":    func(string) (*user.User, error) { return &user.User{Uid: "998", Gid: "-"}, nil },
	}
	for name, lookup := range cases {
		p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
		dir := t.TempDir()
		opts := configureOpts(url, dir)
		opts.Geteuid = func() int { return 0 }
		opts.LookupUser = lookup
		err := Configure(context.Background(), opts)
		if err == nil || !strings.Contains(err.Error(), "not spent") {
			t.Errorf("%s: got %v", name, err)
		}
		if len(p.requests) != 0 || credsExist(t, dir) {
			t.Errorf("%s: registered: %v", name, p.requests)
		}
	}
}

func TestConfigureAsRootBeforeServiceInstallKeepsTheCredentials(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registered()}})
	dir := t.TempDir()
	opts := configureOpts(url, dir)
	opts.Geteuid = func() int { return 0 }
	opts.LookupUser = func(name string) (*user.User, error) { return nil, user.UnknownUserError(name) }
	if err := Configure(context.Background(), opts); err != nil {
		t.Fatal(err)
	}
	if len(p.requests) != 1 || !credsExist(t, dir) {
		t.Fatalf("requests %v", p.requests)
	}
}

func TestSelfUpdateOffReadsABoolean(t *testing.T) {
	for value, want := range map[string]bool{"1": true, "true": true, " TRUE ": true, "": false, "0": false, "false": false, "off": false, "yes": false} {
		if got := SelfUpdateOff(value); got != want {
			t.Errorf("%q: got %v, want %v", value, got, want)
		}
	}
}

// The published image sets AIXLE_RUNNER_NO_SELF_UPDATE (docker/runner/Dockerfile):
// a host runner started from it reports self-update as off, whatever its
// credentials say.
func TestAHostRunnerWithNoSelfUpdateStartsWithSelfUpdateOff(t *testing.T) {
	for _, noSelfUpdate := range []bool{false, true} {
		_, url := newPlatform(t, map[string][]answer{})
		dir := t.TempDir()
		storeCreds(t, dir, url)
		var logs bytes.Buffer
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		_ = RunHost(ctx, HostOptions{StateDir: dir, Docker: hostDocker{}, NoSelfUpdate: noSelfUpdate,
			Logger: slog.New(slog.NewTextHandler(&logs, nil))})
		want := fmt.Sprintf("auto_update=%v", !noSelfUpdate)
		if !strings.Contains(logs.String(), want) {
			t.Errorf("NoSelfUpdate %v: the start line lacks %s:\n%s", noSelfUpdate, want, logs.String())
		}
	}
}

// A host runner checks in after it starts, before it takes an op, with the
// machine's os, arch and facts, and the version it runs in the header
// (PROTOCOL.md §5.9).
func TestAHostRunnerChecksInBeforeItPolls(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"GET /runner/v1/ops": {{200, map[string]any{"ops": []any{}}}}})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	p.mu.Lock()
	p.seen = func(r request) {
		if r.method == http.MethodGet {
			cancel()
		}
	}
	p.mu.Unlock()

	if err := RunHost(ctx, HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))}); err != nil {
		t.Fatal(err)
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.requests) < 2 || p.requests[0].method != http.MethodPost || p.requests[0].path != "/runner/v1/check-in" || p.requests[1].path != "/runner/v1/ops" {
		t.Fatalf("requests %+v", p.requests)
	}
	check := p.requests[0]
	facts, _ := check.body["facts"].(map[string]any)
	if check.auth == "" || check.body["os"] != runtime.GOOS || check.body["arch"] != runtime.GOARCH || facts["docker"] != "27.1.0" || facts["docker_api"] != "1.47" {
		t.Errorf("check-in %+v", check)
	}
}

// A machine that no longer passes the preflight still checks in, and says why.
func TestACheckInReportOfAMachineThatFailsThePreflightCarriesTheFailure(t *testing.T) {
	report := checkInReport(context.Background(), unlistableDocker{}, slog.New(slog.NewTextHandler(io.Discard, nil)))

	if report.OS != runtime.GOOS || report.Arch != runtime.GOARCH {
		t.Errorf("report %+v", report)
	}
	// unlistableDocker answers the daemon's version, so the failure is the free
	// space of a directory this machine does not have, or none at all.
	if failure, failed := report.Facts["preflight_error"]; failed && failure == "" {
		t.Errorf("an empty failure: %+v", report.Facts)
	}
	if report.Facts["docker"] != "27.1.0" {
		t.Errorf("facts %+v", report.Facts)
	}

	down := checkInReport(context.Background(), brokenDocker{}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if msg, _ := down.Facts["preflight_error"].(string); !strings.Contains(msg, "not reachable") {
		t.Errorf("facts %+v", down.Facts)
	}
}

// brokenDocker is a daemon that cannot be reached.
type brokenDocker struct{ hostDocker }

func (brokenDocker) ServerVersion(context.Context, client.ServerVersionOptions) (client.ServerVersionResult, error) {
	return client.ServerVersionResult{}, errors.New("connection refused")
}

// A runner that updated itself checks in with its new version, and the platform's
// answer may offer an update, which an idle machine takes before it polls.
func TestAHostRunnerTakesTheUpdateOfItsCheckIn(t *testing.T) {
	offer := answer{200, map[string]any{
		"environment": map[string]any{"id": 42, "key": "aixle-r7-build", "display_name": "build-01", "state": "registered"},
		"config":      map[string]any{"upload_max_bytes": 1},
		"update":      map[string]any{"version": "9.9.9", "sha256": strings.Repeat("a", 64)},
	}}
	p, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/check-in": {offer},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	})
	dir := t.TempDir()
	storeCreds(t, dir, url)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	p.mu.Lock()
	p.seen = func(r request) {
		if r.method == http.MethodGet && strings.HasPrefix(r.path, "/runner/v1/releases/") && strings.HasSuffix(r.path, "/checksums") {
			cancel()
		}
	}
	p.mu.Unlock()

	_ = RunHost(ctx, HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})

	p.mu.Lock()
	defer p.mu.Unlock()
	var paths []string
	for _, r := range p.requests {
		paths = append(paths, r.method+" "+r.path)
	}
	if len(paths) < 2 || paths[0] != "POST /runner/v1/check-in" || !strings.Contains(paths[1], "/runner/v1/releases/9.9.9/checksums") {
		t.Fatalf("requests %v", paths)
	}
}

// A runner below the platform's minimum is refused at check-in and stops for an
// operator: it takes no op.
func TestAHostRunnerBelowTheMinimumStopsAtCheckIn(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/check-in": {refused(400, "runner_version_unsupported")},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	})
	dir := t.TempDir()
	storeCreds(t, dir, url)

	err := RunHost(context.Background(), HostOptions{StateDir: dir, Docker: hostDocker{}, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})

	if err == nil || !NeedsOperator(err) || !strings.Contains(err.Error(), "update aixle-runner") {
		t.Fatalf("got %v", err)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, r := range p.requests {
		if r.path == "/runner/v1/ops" {
			t.Fatalf("the runner polled after the refusal: %+v", p.requests)
		}
	}
}
