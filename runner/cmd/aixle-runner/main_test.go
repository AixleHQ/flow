package main

import (
	"bytes"
	"context"
	"io"
	"path/filepath"
	"strings"
	"testing"

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
