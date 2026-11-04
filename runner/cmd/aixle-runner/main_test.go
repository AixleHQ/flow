package main

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/service"
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
	code := run(context.Background(), []string{"--mode", "host", "--state-dir", dir}, io.Discard, &stderr)
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
	code := run(context.Background(), []string{"--mode", "host", "--state-dir", dir}, io.Discard, &stderr)
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
