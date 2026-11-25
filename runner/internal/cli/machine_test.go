package cli

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/statedir"
)

const machineKey = "aixle-r7-build"

// sessionDocker is a daemon with the containers of a machine, of another machine,
// and of nobody, which records what is removed.
type sessionDocker struct {
	hostDocker
	mu      sync.Mutex
	items   []container.Summary
	removed []string
}

func newSessionDocker() *sessionDocker {
	return &sessionDocker{items: []container.Summary{
		{ID: "agent", Labels: map[string]string{docker.LabelEnvironment: machineKey, docker.LabelSession: "7"}},
		{ID: "sidecar", Labels: map[string]string{docker.LabelEnvironment: machineKey, docker.LabelSession: "7", docker.LabelRole: docker.RoleProxy}},
		{ID: "of-another-machine", Labels: map[string]string{docker.LabelEnvironment: "aixle-other", docker.LabelSession: "9"}},
		{ID: "unlabelled", Labels: map[string]string{}},
	}}
}

func (d *sessionDocker) ContainerList(context.Context, client.ContainerListOptions) (client.ContainerListResult, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	// A daemon filters by label; this one answers everything and leaves the
	// check to the runner, which must not trust the filter alone.
	return client.ContainerListResult{Items: append([]container.Summary(nil), d.items...)}, nil
}

func (d *sessionDocker) ContainerRemove(_ context.Context, id string, _ client.ContainerRemoveOptions) (client.ContainerRemoveResult, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.removed = append(d.removed, id)
	for i, c := range d.items {
		if c.ID == id {
			d.items = append(d.items[:i], d.items[i+1:]...)
			break
		}
	}
	return client.ContainerRemoveResult{}, nil
}

func (d *sessionDocker) removedIDs() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return append([]string(nil), d.removed...)
}

func registeredAs(key string) answer {
	a := registered()
	a.body.(map[string]any)["environment"].(map[string]any)["key"] = key
	return a
}

// storeMachineCreds stores the credentials of a registered machine with its key.
func storeMachineCreds(t *testing.T, dir, url string) {
	t.Helper()
	exp := time.Now().Add(time.Hour).UTC().Truncate(time.Second)
	err := credentials.NewStore(dir).Save(credentials.Credentials{URL: url,
		Environment: protocol.Environment{Key: machineKey, DisplayName: "build-01"},
		TokenPair:   protocol.TokenPair{AccessToken: "aracc_one", AccessTokenExpiresAt: exp, RefreshToken: "arref_one", RefreshTokenExpiresAt: exp.Add(720 * time.Hour)}})
	if err != nil {
		t.Fatal(err)
	}
}

// stopOnFirstPoll cancels the runner's context when it asks for ops: it has
// registered, checked in, and runs.
func stopOnFirstPoll(p *platform, cancel context.CancelFunc) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.seen = func(r request) {
		if r.method == http.MethodGet && r.path == "/runner/v1/ops" {
			cancel()
		}
	}
}

func (p *platform) count(method, path string) int {
	p.mu.Lock()
	defer p.mu.Unlock()
	n := 0
	for _, r := range p.requests {
		if r.method == method && r.path == path {
			n++
		}
	}
	return n
}

func TestAMachineRunnerRegistersOnItsFirstStartFromTheEnvironmentAndNeverAgain(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/register": {registeredAs(machineKey)},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	})
	dir := filepath.Join(t.TempDir(), "state")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stopOnFirstPoll(p, cancel)

	var out bytes.Buffer
	opts := MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, URL: url, Token: "arreg_secret", Name: "build-01", NoSelfUpdate: true, Out: &out}
	if err := RunMachine(ctx, opts); err != nil {
		t.Fatal(err)
	}
	if !credsExist(t, dir) {
		t.Fatal("the first start registered nothing")
	}
	p.mu.Lock()
	register := p.requests[0]
	p.mu.Unlock()
	if register.path != "/runner/v1/register" || register.auth != "Bearer arreg_secret" || register.body["name"] != "build-01" || register.body["auto_update"] != false {
		t.Fatalf("register: %+v", register)
	}
	if strings.Contains(out.String(), "arreg_secret") || strings.Contains(out.String(), "aracc_") || strings.Contains(out.String(), "arref_") {
		t.Fatalf("a token is in the output: %s", out.String())
	}

	// The credentials exist now: a restart ignores the three variables, and the
	// platform fails the test on a second `register`.
	p2, url2 := newPlatform(t, map[string][]answer{"GET /runner/v1/ops": {{200, map[string]any{"ops": []any{}}}}})
	creds, _ := credentials.NewStore(dir).Load()
	creds.URL = url2
	if err := credentials.NewStore(dir).Save(creds); err != nil {
		t.Fatal(err)
	}
	ctx2, cancel2 := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel2()
	stopOnFirstPoll(p2, cancel2)
	opts.URL, opts.Docker = url2, newSessionDocker()
	if err := RunMachine(ctx2, opts); err != nil {
		t.Fatal(err)
	}
	if n := p2.count(http.MethodPost, "/runner/v1/register"); n != 0 {
		t.Fatalf("a start with credentials registered %d times", n)
	}
}

func TestAMachineRunnerNamesItselfAfterTheHostnameWhenNoNameIsGiven(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registeredAs(machineKey)}})
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stopOnFirstPoll(p, cancel)
	if err := RunMachine(ctx, MachineOptions{StateDir: t.TempDir(), Docker: newSessionDocker(), Logger: quiet, URL: url, Token: "arreg_secret"}); err != nil {
		t.Fatal(err)
	}
	hostname, _ := os.Hostname()
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.requests[0].body["name"] != hostname {
		t.Fatalf("registered as %v, not %q", p.requests[0].body["name"], hostname)
	}
}

func TestARefusedTokenWritesNoCredentialsAndStopsWithAnError(t *testing.T) {
	_, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {refused(401, "invalid_token")}})
	dir := filepath.Join(t.TempDir(), "state")
	var out bytes.Buffer
	err := RunMachine(context.Background(), MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, URL: url, Token: "arreg_secret", Name: "m", Out: &out})
	if err == nil || !strings.Contains(err.Error(), "unknown, used or expired") {
		t.Fatalf("got %v", err)
	}
	if credsExist(t, dir) {
		t.Fatal("a refused token left credentials")
	}
	if strings.Contains(err.Error()+out.String(), "arreg_secret") {
		t.Fatal("the token is in the output")
	}
}

func TestAMachineRunnerWithoutCredentialsOrTokenStillNeedsAnOperator(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")
	err := RunMachine(context.Background(), MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, URL: "https://flow.example"})
	if err == nil || !NeedsOperator(err) {
		t.Fatalf("got %v", err)
	}
}

// One of the two is a typo or a dropped variable: the error names the missing
// one, never a value.
func TestAHalfSetRegistrationEnvironmentNamesTheMissingVariable(t *testing.T) {
	for _, tc := range []struct{ name, url, token, missing, secret string }{
		{"no token", "https://flow.example", "", RegisterTokenEnv, "https://flow.example"},
		{"no url", "", "arreg_secret", RegisterURLEnv, "arreg_secret"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), "state")
			err := RunMachine(context.Background(), MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, URL: tc.url, Token: tc.token})
			if err == nil || !NeedsOperator(err) {
				t.Fatalf("got %v", err)
			}
			if !strings.Contains(err.Error(), tc.missing+" is not set") || strings.Contains(err.Error(), tc.secret) {
				t.Fatalf("got %v", err)
			}
		})
	}
}

// With credentials all three variables are ignored, a half-set one too.
func TestAHalfSetRegistrationEnvironmentIsIgnoredOnceCredentialsExist(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"GET /runner/v1/ops": {{200, map[string]any{"ops": []any{}}}}})
	dir := t.TempDir()
	storeMachineCreds(t, dir, url)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stopOnFirstPoll(p, cancel)
	if err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, URL: "https://other.example", Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
}

// Each stop signal tears the machine down. Where the signal is delivered, the
// runner sees what the process sees, so the test sends the real one.
func TestEachStopSignalRemovesTheSessionContainersAndUnregistersOnlyWhenAsked(t *testing.T) {
	for _, sig := range StopSignals {
		for _, unregister := range []bool{true, false} {
			t.Run(fmt.Sprintf("%v/unregister=%v", sig, unregister), func(t *testing.T) {
				p, url := newPlatform(t, map[string][]answer{
					"GET /runner/v1/ops":             {{200, map[string]any{"ops": []any{}}}},
					"DELETE /runner/v1/registration": {{204, nil}},
				})
				dir := t.TempDir()
				storeMachineCreds(t, dir, url)
				d := newSessionDocker()
				ctx, stop := signalContext(t)
				defer stop()
				p.mu.Lock()
				p.seen = func(r request) {
					if r.method == http.MethodGet && r.path == "/runner/v1/ops" {
						syscall.Kill(os.Getpid(), sig.(syscall.Signal))
					}
				}
				p.mu.Unlock()

				if err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: d, Logger: quiet, UnregisterOnStop: unregister, Out: io.Discard}); err != nil {
					t.Fatal(err)
				}
				// Only the machine's own containers go: not another machine's, not an unlabelled one.
				if got := d.removedIDs(); len(got) != 2 || !contains(got, "agent") || !contains(got, "sidecar") {
					t.Fatalf("removed %v", got)
				}
				if n := p.count(http.MethodDelete, "/runner/v1/registration"); (n == 1) != unregister || n > 1 {
					t.Fatalf("unregistered %d times, with the setting %v", n, unregister)
				}
				if credsExist(t, dir) == unregister {
					t.Fatalf("credentials exist: %v, unregister: %v", credsExist(t, dir), unregister)
				}
			})
		}
	}
}

func signalContext(t *testing.T) (context.Context, context.CancelFunc) {
	t.Helper()
	ctx, stop := signal.NotifyContext(context.Background(), StopSignals...)
	t.Cleanup(stop)
	return ctx, stop
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// Unregister, teardown and exit fit in `docker stop`'s 10 s, against a gateway
// that never answers.
func TestAStopWithAGatewayThatNeverAnswersFinishesInsideDockerStopsTimeout(t *testing.T) {
	var mu sync.Mutex
	unregistering := false
	ok := &platform{answers: map[string][]answer{
		"POST /runner/v1/check-in": {checkedIn()},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	}}
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodDelete {
			mu.Lock()
			unregistering = true
			mu.Unlock()
			<-r.Context().Done()
			return
		}
		ok.ServeHTTP(w, r)
	}))
	t.Cleanup(s.Close)
	dir := t.TempDir()
	storeMachineCreds(t, dir, s.URL)
	ctx, cancel := context.WithCancel(context.Background())
	stopOnFirstPoll(ok, cancel)

	started := time.Now()
	err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, UnregisterOnStop: true, Out: io.Discard})
	if err != nil {
		t.Fatal(err)
	}
	if took := time.Since(started); took > 9500*time.Millisecond {
		t.Fatalf("the stop took %v", took)
	}
	mu.Lock()
	defer mu.Unlock()
	if !unregistering {
		t.Fatal("the runner never tried to unregister")
	}
	// The unregister failed, so the credentials stay, to be tried again.
	if !credsExist(t, dir) {
		t.Fatal("the credentials were deleted though the platform never answered")
	}
}

// The platform commits the unregister, then fails the session the machine held,
// which calls Temporal: the answer can come after the old 3 s deadline. A stop
// waits for it inside its one budget, and logs no failure.
func TestAStopWaitsForAnUnregisterThatAnswersAfterThreeSeconds(t *testing.T) {
	ok := &platform{answers: map[string][]answer{
		"POST /runner/v1/check-in": {checkedIn()},
		"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
	}}
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodDelete {
			time.Sleep(4 * time.Second)
			w.WriteHeader(http.StatusNoContent)
			return
		}
		ok.ServeHTTP(w, r)
	}))
	t.Cleanup(s.Close)
	dir := t.TempDir()
	storeMachineCreds(t, dir, s.URL)
	ctx, cancel := context.WithCancel(context.Background())
	stopOnFirstPoll(ok, cancel)
	var logs bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logs, nil))

	if err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: logger, UnregisterOnStop: true, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(logs.String(), "failed") {
		t.Fatalf("a failure was logged: %s", logs.String())
	}
	if credsExist(t, dir) {
		t.Fatal("the credentials stay though the platform unregistered the machine")
	}
}

// A failed unregister on stop does not say the credentials were kept: with `--rm`
// they go with the container. The `unregister` command keeps its text.
func TestAFailedUnregisterOnStopSaysToRemoveTheMachineOnThePlatform(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{
		"GET /runner/v1/ops":             {{200, map[string]any{"ops": []any{}}}},
		"DELETE /runner/v1/registration": {{500, nil}},
	})
	dir := t.TempDir()
	storeMachineCreds(t, dir, url)
	ctx, cancel := context.WithCancel(context.Background())
	stopOnFirstPoll(p, cancel)
	var logs bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&logs, nil))

	if err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: logger, UnregisterOnStop: true, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	line := logs.String()
	if !strings.Contains(line, "unregistering this machine on stop failed") || !strings.Contains(line, "remove it there") {
		t.Fatalf("log: %s", line)
	}
	if strings.Contains(line, "credentials were kept") {
		t.Fatalf("a stop must not say the credentials were kept: %s", line)
	}
}

func TestTheUnregisterCommandKeepsItsTextWhenTheCallFails(t *testing.T) {
	_, url := newPlatform(t, map[string][]answer{"DELETE /runner/v1/registration": {{500, nil}}})
	dir := t.TempDir()
	storeMachineCreds(t, dir, url)
	err := Unregister(context.Background(), UnregisterOptions{StateDir: dir, Out: io.Discard})
	if err == nil || !strings.Contains(err.Error(), "the credentials were kept so it can be tried again") {
		t.Fatalf("got %v", err)
	}
	if !credsExist(t, dir) {
		t.Fatal("the credentials were deleted")
	}
}

// An update, or a failure the service manager restarts, is not a stop: the sessions stay.
func TestAFailureThatIsNotAStopLeavesTheSessionContainers(t *testing.T) {
	_, url := newPlatform(t, map[string][]answer{
		"POST /runner/v1/check-in": {refused(400, "runner_version_unsupported")},
	})
	dir := t.TempDir()
	storeMachineCreds(t, dir, url)
	d := newSessionDocker()
	_ = RunMachine(context.Background(), MachineOptions{StateDir: dir, Docker: d, Logger: quiet, UnregisterOnStop: true, Out: io.Discard})
	if got := d.removedIDs(); len(got) != 0 {
		t.Fatalf("removed %v without a stop", got)
	}
}

func TestAMachineRunnerPutsItsBinaryInTheStateDirectoryAtStart(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"GET /runner/v1/ops": {{200, map[string]any{"ops": []any{}}}}})
	dir := t.TempDir()
	storeMachineCreds(t, dir, url)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	stopOnFirstPoll(p, cancel)
	if err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: newSessionDocker(), Logger: quiet, Out: io.Discard}); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(statedir.BinPath(dir))
	if err != nil || info.Mode().Perm() != 0o755 {
		t.Fatalf("the binary: %v, %v", info, err)
	}
	if bin, _ := os.Stat(filepath.Dir(statedir.BinPath(dir))); bin.Mode().Perm() != 0o755 {
		t.Fatalf("the bin directory is %v: the sidecar runs as nobody", bin.Mode())
	}
}

// Only in a container does the runner inspect anything, and a runner that cannot
// be sure of its container, or a volume on a Docker before 26, stops at start
// without spending the token.
func TestAContainerRunnerThatCannotLocateItsStateStopsBeforeRegistering(t *testing.T) {
	p, url := newPlatform(t, map[string][]answer{"POST /runner/v1/register": {registeredAs(machineKey)}})
	dir := filepath.Join(t.TempDir(), "state")
	api := &ownDocker{hostDocker: hostDocker{}}
	err := RunMachine(context.Background(), MachineOptions{StateDir: dir, Docker: api, Logger: quiet, URL: url, Token: "arreg_secret", Name: "m",
		InContainer: true, Hostname: "abcdef123456", Out: io.Discard})
	if err == nil || !NeedsOperator(err) || !strings.Contains(err.Error(), "--hostname") || !strings.Contains(err.Error(), "--network host") {
		t.Fatalf("got %v", err)
	}
	if n := p.count(http.MethodPost, "/runner/v1/register"); n != 0 || credsExist(t, dir) {
		t.Fatalf("registered %d times", n)
	}
}

func TestAContainerRunnerWithAVolumeNeedsDocker26AndWithADirectoryDoesNot(t *testing.T) {
	for kind, tc := range map[string]struct {
		api       string
		mountType string
		wantErr   string
	}{
		"volume, old Docker":    {"1.44", "volume", "needs Docker Engine 26.0 or later"},
		"volume, Docker 26":     {"1.45", "volume", ""},
		"directory, old Docker": {"1.44", "bind", ""},
	} {
		p, url := newPlatform(t, map[string][]answer{
			"POST /runner/v1/register": {registeredAs(machineKey)},
			"GET /runner/v1/ops":       {{200, map[string]any{"ops": []any{}}}},
		})
		dir := filepath.Join(t.TempDir(), "state")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		stopOnFirstPoll(p, cancel)
		api := &ownDocker{hostDocker: hostDocker{}, apiVersion: tc.api, mountType: tc.mountType, dir: dir}
		err := RunMachine(ctx, MachineOptions{StateDir: dir, Docker: api, Logger: quiet, URL: url, Token: "arreg_secret", Name: "m",
			InContainer: true, Hostname: "abcdef123456", Out: io.Discard})
		cancel()
		switch {
		case tc.wantErr == "" && err != nil:
			t.Errorf("%s: %v", kind, err)
		case tc.wantErr != "":
			if err == nil || !strings.Contains(err.Error(), tc.wantErr) || !NeedsOperator(err) {
				t.Errorf("%s: got %v", kind, err)
			}
			if p.count(http.MethodPost, "/runner/v1/register") != 0 {
				t.Errorf("%s: the token was spent", kind)
			}
		}
	}
}

// ownDocker answers the inspect of the runner's own container, and a daemon of apiVersion.
type ownDocker struct {
	hostDocker
	apiVersion string
	mountType  string
	dir        string
}

func (d *ownDocker) ServerVersion(ctx context.Context, o client.ServerVersionOptions) (client.ServerVersionResult, error) {
	if d.apiVersion == "" {
		return d.hostDocker.ServerVersion(ctx, o)
	}
	return client.ServerVersionResult{Version: "25.0.5", APIVersion: d.apiVersion}, nil
}

func (d *ownDocker) ContainerInspect(context.Context, string, client.ContainerInspectOptions) (client.ContainerInspectResult, error) {
	if d.mountType == "" {
		return client.ContainerInspectResult{}, errNotFound
	}
	return client.ContainerInspectResult{Container: container.InspectResponse{
		ID: "abcdef123456" + strings.Repeat("0", 52), Config: &container.Config{Hostname: "abcdef123456"},
		Mounts: []container.MountPoint{{Type: mount.Type(d.mountType), Name: "vol", Source: "/srv/aixle", Destination: d.dir}},
	}}, nil
}

var errNotFound = notFound{}

type notFound struct{}

func (notFound) Error() string { return "no such container" }
func (notFound) NotFound()     {}

func TestBoolEnv(t *testing.T) {
	for value, want := range map[string]bool{"": false, "1": true, "0": false, "true": true, " 1 ": true} {
		if got, err := BoolEnv("X", value); err != nil || got != want {
			t.Errorf("%q: %v, %v", value, got, err)
		}
	}
	if _, err := BoolEnv("X", "maybe"); err == nil || !strings.Contains(err.Error(), "must be 1 or 0") {
		t.Errorf("maybe: %v", err)
	}
}

// A restarted runner finds a session's sidecar that is not running: Resume reads it
// as an exit, which stops the agent, and reading its log fails here.
func (d *sessionDocker) ContainerInspect(context.Context, string, client.ContainerInspectOptions) (client.ContainerInspectResult, error) {
	return client.ContainerInspectResult{}, errNotFound
}

func (d *sessionDocker) ContainerLogs(context.Context, string, client.ContainerLogsOptions) (client.ContainerLogsResult, error) {
	return nil, errors.New("no logs")
}
