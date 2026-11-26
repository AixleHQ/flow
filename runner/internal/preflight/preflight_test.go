package preflight

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/moby/moby/api/types/system"
	"github.com/moby/moby/client"
)

type fakeDocker struct {
	api        string
	versionErr error
	infoErr    error
}

func (f fakeDocker) ServerVersion(context.Context, client.ServerVersionOptions) (client.ServerVersionResult, error) {
	if f.versionErr != nil {
		return client.ServerVersionResult{}, f.versionErr
	}
	return client.ServerVersionResult{Version: "27.1.0", APIVersion: f.api}, nil
}

func (f fakeDocker) Info(context.Context, client.InfoOptions) (client.SystemInfoResult, error) {
	if f.infoErr != nil {
		return client.SystemInfoResult{}, f.infoErr
	}
	return client.SystemInfoResult{Info: system.Info{DockerRootDir: "/var/lib/docker"}}, nil
}

func free(n uint64) func(string) (uint64, error) {
	return func(string) (uint64, error) { return n, nil }
}

func env() Env {
	return Env{GOOS: "linux", GOARCH: "amd64", Docker: fakeDocker{api: "1.47"}, StateDir: "/var/lib/aixle-runner", FreeBytes: free(100 << 30)}
}

func TestAMachineThatPasses(t *testing.T) {
	for _, arch := range []string{"amd64", "arm64"} {
		e := env()
		e.GOARCH = arch
		report, err := Run(context.Background(), e)
		if err != nil {
			t.Fatal(err)
		}
		facts := report.Facts()
		if report.Arch != arch || facts["docker"] != "27.1.0" || facts["docker_api"] != "1.47" || facts["disk_free_bytes"] != uint64(100<<30) {
			t.Fatalf("report %#v", report)
		}
	}
}

func TestTheMinimumsPass(t *testing.T) {
	e := env()
	e.Docker = fakeDocker{api: "1.41"}
	e.FreeBytes = free(WarnFreeBytes)
	report, err := Run(context.Background(), e)
	if err != nil {
		t.Fatal(err)
	}
	if len(report.Notes) != 1 {
		t.Fatalf("notes %v: 20 GiB is not below the warning", report.Notes)
	}
}

// The free space is for information only (add-machine.md §3.3): the figure comes
// with the path measured, a low figure is a warning, a failed measure a note, and
// none of them refuses the machine.
func TestTheDiskFigureIsInformationOnly(t *testing.T) {
	var measured []string
	e := env()
	e.FreeBytes = func(path string) (uint64, error) { measured = append(measured, path); return 100 << 30, nil }
	report, err := Run(context.Background(), e)
	if err != nil || !reflect.DeepEqual(measured, []string{"/var/lib/aixle-runner"}) {
		t.Fatalf("measured %v, %v: only the state directory is measured, not Docker's data root", measured, err)
	}
	if report.DiskFreePath != "/var/lib/aixle-runner" || report.DiskFreeBytes != 100<<30 ||
		len(report.Notes) != 1 || !strings.Contains(report.Notes[0], "100.0 GiB free on /var/lib/aixle-runner") {
		t.Fatalf("report %#v", report)
	}

	e.FreeBytes = free(WarnFreeBytes - 1)
	report, err = Run(context.Background(), e)
	if err != nil {
		t.Fatalf("a low figure refused the machine: %v", err)
	}
	if len(report.Notes) != 2 || !strings.Contains(report.Notes[1], "starts anyway") {
		t.Fatalf("notes %v", report.Notes)
	}

	e.FreeBytes = func(string) (uint64, error) { return 0, errors.New("denied") }
	report, err = Run(context.Background(), e)
	if err != nil {
		t.Fatalf("a failed measure refused the machine: %v", err)
	}
	if len(report.Notes) != 1 || !strings.Contains(report.Notes[0], "could not be measured") || report.DiskFreePath != "" {
		t.Fatalf("report %#v", report)
	}

	e.StateDir = ""
	if report, err = Run(context.Background(), e); err != nil || len(report.Notes) != 0 {
		t.Fatalf("no state directory measures nothing: %v %v", report.Notes, err)
	}
}

func TestASubpathNeedsDocker26OnlyForAVolume(t *testing.T) {
	ctx := context.Background()
	if err := RequireSubpath(ctx, fakeDocker{api: "1.45"}); err != nil {
		t.Fatal(err)
	}
	err := RequireSubpath(ctx, fakeDocker{api: "1.44"})
	if err == nil {
		t.Fatal("Docker 1.44 mounts no subpath")
	}
	for _, want := range []string{"1.44", "26.0", "Update Docker", "directory on this machine", "Linux service"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("the error lacks %q: %v", want, err)
		}
	}
	// The runner's preflight itself starts on Docker 1.41: a directory needs no subpath.
	e := env()
	e.Docker = fakeDocker{api: "1.44"}
	if _, err := Run(ctx, e); err != nil {
		t.Fatalf("a daemon before 26 is refused by the preflight: %v", err)
	}
}

func TestFailedChecks(t *testing.T) {
	cases := map[string]struct {
		change func(*Env)
		want   string
	}{
		"darwin":         {func(e *Env) { e.GOOS = "darwin" }, "needs Linux on amd64 or arm64"},
		"386":            {func(e *Env) { e.GOARCH = "386" }, "needs Linux on amd64 or arm64"},
		"no daemon":      {func(e *Env) { e.Docker = fakeDocker{versionErr: errors.New("Cannot connect to the Docker daemon")} }, "not reachable"},
		"old API":        {func(e *Env) { e.Docker = fakeDocker{api: "1.40"} }, "needs API 1.41 or later"},
		"info fails":     {func(e *Env) { e.Docker = fakeDocker{api: "1.47", infoErr: errors.New("boom")} }, "info failed"},
		"api is missing": {func(e *Env) { e.Docker = fakeDocker{api: ""} }, "needs API 1.41"},
	}
	for name, tc := range cases {
		e := env()
		tc.change(&e)
		_, err := Run(context.Background(), e)
		if err == nil || !strings.Contains(err.Error(), tc.want) {
			t.Errorf("%s: got %v", name, err)
		}
	}
}

func TestEveryFailureIsReported(t *testing.T) {
	e := env()
	e.GOOS = "darwin"
	e.Docker = fakeDocker{api: "1.40"}
	_, err := Run(context.Background(), e)
	for _, want := range []string{"Linux", "1.41"} {
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in %v", want, err)
		}
	}
}
