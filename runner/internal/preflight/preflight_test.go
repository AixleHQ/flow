package preflight

import (
	"context"
	"errors"
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
	return func(path string) (uint64, error) {
		if path != "/var/lib/docker" {
			return 0, errors.New("wrong path " + path)
		}
		return n, nil
	}
}

func env() Env {
	return Env{GOOS: "linux", GOARCH: "amd64", Docker: fakeDocker{api: "1.47"}, FreeBytes: free(100 << 30)}
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
	e.FreeBytes = free(MinFreeBytes)
	if _, err := Run(context.Background(), e); err != nil {
		t.Fatal(err)
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
		"low disk":       {func(e *Env) { e.FreeBytes = free(MinFreeBytes - 1) }, "at least 20 GiB"},
		"statfs fails":   {func(e *Env) { e.FreeBytes = func(string) (uint64, error) { return 0, errors.New("denied") } }, "free space"},
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
	e.FreeBytes = free(1 << 30)
	_, err := Run(context.Background(), e)
	for _, want := range []string{"Linux", "1.41", "20 GiB"} {
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in %v", want, err)
		}
	}
}
