package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/cli"
	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/service"
	"github.com/aixlehq/aixle-runner/internal/version"
)

func TestServiceTakesNoStateDir(t *testing.T) {
	for _, command := range []string{"install", "uninstall", "start", "stop"} {
		var stderr bytes.Buffer
		code := run(context.Background(), []string{"service", command, "--state-dir", "/tmp/x"}, io.Discard, &stderr)
		if code != 2 || !strings.Contains(stderr.String(), "Usage:") {
			t.Errorf("service %s --state-dir: exit %d, %s", command, code, stderr.String())
		}
	}
	if strings.Contains(usage, "stop [--state-dir") {
		t.Fatal("the usage offers --state-dir to service")
	}
}

func TestAHostRunnerWithoutCredentialsExitsSoSystemdDoesNotRestartIt(t *testing.T) {
	var stderr bytes.Buffer
	dir := filepath.Join(t.TempDir(), "never-configured")
	code := run(context.Background(), []string{"--mode", "machine", "--state-dir", dir}, io.Discard, &stderr)
	if code != service.ExitStop || !strings.Contains(stderr.String(), "configure") {
		t.Fatalf("exit %d, %s", code, stderr.String())
	}
}

func TestAHostRunnerWithACorruptJournalExitsSoSystemdDoesNotRestartIt(t *testing.T) {
	dir := t.TempDir()
	exp := time.Now().Add(time.Hour).UTC().Truncate(time.Second)
	err := credentials.NewStore(dir).Save(credentials.Credentials{URL: "https://flow.aixle.com", TokenPair: protocol.TokenPair{
		AccessToken: "aracc_one", AccessTokenExpiresAt: exp, RefreshToken: "arref_one", RefreshTokenExpiresAt: exp.Add(720 * time.Hour),
	}})
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, journal.FileName)
	if err := os.WriteFile(path, []byte("not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	code := run(context.Background(), []string{"--mode", "machine", "--state-dir", dir}, io.Discard, &stderr)
	out := stderr.String()
	if code != service.ExitStop {
		t.Fatalf("exit %d, %s", code, out)
	}
	for _, want := range []string{path, "aixle-runner unregister", "aixle-runner configure` with a new registration token"} {
		if !strings.Contains(out, want) {
			t.Errorf("the message lacks %q: %s", want, out)
		}
	}
	if strings.Contains(out, "aracc_") || strings.Contains(out, "arref_") {
		t.Fatalf("the message carries a token: %s", out)
	}
}

func TestTheUsageNamesTheBinaryTheServiceRuns(t *testing.T) {
	if !strings.Contains(usage, service.BinaryPath) {
		t.Fatalf("usage:\n%s", usage)
	}
}

func TestTheServiceBinaryLivesInTheStateDirectory(t *testing.T) {
	// The service user owns the state directory, so it can replace its own binary
	// on a self-update (DESIGN.md §14.4).
	if filepath.Dir(filepath.Dir(service.BinaryPath)) != cli.DefaultStateDir {
		t.Fatalf("%s is not under %s", service.BinaryPath, cli.DefaultStateDir)
	}
}

func TestVersionPrintsTheVersion(t *testing.T) {
	for _, arg := range []string{"version", "--version"} {
		var stdout bytes.Buffer
		if code := run(context.Background(), []string{arg}, &stdout, io.Discard); code != 0 || stdout.String() != version.Version+"\n" {
			t.Fatalf("%s: exit %d, %q", arg, code, stdout.String())
		}
	}
	if code := run(context.Background(), []string{"version", "extra"}, io.Discard, io.Discard); code != 2 {
		t.Fatalf("exit %d", code)
	}
}

func TestAnUpdateExitsWithItsOwnCode(t *testing.T) {
	if service.ExitUpdated == 0 || service.ExitUpdated == 1 || service.ExitUpdated == service.ExitStop {
		t.Fatalf("ExitUpdated is %d", service.ExitUpdated)
	}
}

func TestTheModesAreMachineAndProxy(t *testing.T) {
	for _, args := range [][]string{{"--mode", "host"}, {"--mode", "controller"}, {"--mode", ""}, {"--mode", "session"}} {
		var stderr bytes.Buffer
		if code := run(context.Background(), args, io.Discard, &stderr); code != 2 || !strings.Contains(stderr.String(), "Usage:") {
			t.Errorf("%v: exit %d, %s", args, code, stderr.String())
		}
	}
	if strings.Contains(usage, "--mode host") || !strings.Contains(usage, "--mode machine") {
		t.Fatalf("usage:\n%s", usage)
	}
}

// What the machine mode gets from its flags and environment: the settings are
// explicit, and the flag wins over the variable.
func TestTheMachineModeReadsItsSettingsFromTheEnvironmentAndTheFlagWins(t *testing.T) {
	var got cli.MachineOptions
	defer func(old func(context.Context, cli.MachineOptions) error) { runMachine = old }(runMachine)
	runMachine = func(_ context.Context, opts cli.MachineOptions) error { got = opts; return nil }

	cases := []struct {
		name           string
		env            map[string]string
		args           []string
		unregister     bool
		inContainer    bool
		url, token, nm string
		failsWith      string
	}{
		{name: "nothing set", args: nil},
		{name: "the variable turns it on", env: map[string]string{"AIXLE_RUNNER_UNREGISTER_ON_STOP": "1"}, unregister: true},
		{name: "the flag turns it on", args: []string{"--unregister-on-stop"}, unregister: true},
		{name: "the flag wins over the variable", env: map[string]string{"AIXLE_RUNNER_UNREGISTER_ON_STOP": "1"}, args: []string{"--unregister-on-stop=false"}},
		{name: "0 is off", env: map[string]string{"AIXLE_RUNNER_UNREGISTER_ON_STOP": "0"}},
		{name: "in a container, registering", env: map[string]string{"AIXLE_RUNNER_IN_CONTAINER": "1", "AIXLE_RUNNER_URL": "https://flow.example", "AIXLE_RUNNER_TOKEN": "arreg_x", "AIXLE_RUNNER_NAME": "n"},
			inContainer: true, url: "https://flow.example", token: "arreg_x", nm: "n"},
		{name: "a bad value", env: map[string]string{"AIXLE_RUNNER_UNREGISTER_ON_STOP": "maybe"}, failsWith: "must be 1 or 0"},
	}
	for _, tc := range cases {
		got = cli.MachineOptions{}
		for _, name := range []string{"AIXLE_RUNNER_UNREGISTER_ON_STOP", "AIXLE_RUNNER_IN_CONTAINER", "AIXLE_RUNNER_URL", "AIXLE_RUNNER_TOKEN", "AIXLE_RUNNER_NAME"} {
			t.Setenv(name, tc.env[name])
		}
		var stderr bytes.Buffer
		code := run(context.Background(), append([]string{"--mode", "machine", "--state-dir", "/x"}, tc.args...), io.Discard, &stderr)
		if tc.failsWith != "" {
			if code == 0 || !strings.Contains(stderr.String(), tc.failsWith) {
				t.Errorf("%s: exit %d, %s", tc.name, code, stderr.String())
			}
			continue
		}
		if code != 0 || got.StateDir != "/x" || got.UnregisterOnStop != tc.unregister || got.InContainer != tc.inContainer ||
			got.URL != tc.url || got.Token != tc.token || got.Name != tc.nm {
			t.Errorf("%s: exit %d, %s, got %+v", tc.name, code, stderr.String(), got)
		}
	}
}

func TestAStopIsSIGINTSIGTERMOrSIGHUP(t *testing.T) {
	var names []string
	for _, s := range cli.StopSignals {
		names = append(names, s.String())
	}
	if want := "interrupt terminated hangup"; strings.Join(names, " ") != want {
		t.Fatalf("stop signals: %v", names)
	}
}

func TestUnregisterSaysTheVolumesStayWhenDockerCannotBeReached(t *testing.T) {
	platform := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer platform.Close()
	dir := t.TempDir()
	exp := time.Now().Add(time.Hour).UTC().Truncate(time.Second)
	err := credentials.NewStore(dir).Save(credentials.Credentials{URL: platform.URL, TokenPair: protocol.TokenPair{
		AccessToken: "aracc_one", AccessTokenExpiresAt: exp, RefreshToken: "arref_one", RefreshTokenExpiresAt: exp.Add(720 * time.Hour),
	}})
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("DOCKER_HOST", "bogus://nowhere")

	var stdout, stderr bytes.Buffer
	if err := unregister(context.Background(), []string{"--state-dir", dir}, &stdout, &stderr); err != nil {
		t.Fatalf("unregister: %v (stdout %s, stderr %s)", err, stdout.String(), stderr.String())
	}
	if got := stderr.String(); !strings.Contains(got, "Could not connect to Docker, so the machine's volumes were not removed") {
		t.Errorf("stderr = %q", got)
	}
	if !strings.Contains(stdout.String(), "Unregistered this machine") {
		t.Errorf("stdout = %q", stdout.String())
	}
	if _, err := credentials.NewStore(dir).Load(); err == nil {
		t.Error("the credentials are still there")
	}
}
