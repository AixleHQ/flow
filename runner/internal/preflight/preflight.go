// Package preflight checks, before `configure` registers a machine, that it can run
// sessions (DESIGN.md §6.8): Linux on amd64 or arm64, a reachable Docker daemon with
// API 1.41 or later, and 20 GiB free where the daemon keeps its images.
package preflight

import (
	"context"
	"errors"
	"fmt"
	"runtime"

	"github.com/moby/moby/client"
	"github.com/moby/moby/client/pkg/versions"
)

// MinDockerAPI is the lowest Docker Engine API version a machine may run.
const MinDockerAPI = "1.41"

// MinFreeBytes is the free space required for images and the workspace volume.
const MinFreeBytes uint64 = 20 << 30

// Docker is the part of the SDK client the preflight calls.
type Docker interface {
	ServerVersion(ctx context.Context, options client.ServerVersionOptions) (client.ServerVersionResult, error)
	Info(ctx context.Context, options client.InfoOptions) (client.SystemInfoResult, error)
}

// Env is what the preflight inspects. Its zero fields take the real machine's.
type Env struct {
	GOOS   string
	GOARCH string
	Docker Docker
	// FreeBytes returns the space available to unprivileged writes under path.
	FreeBytes func(path string) (uint64, error)
}

// Report is what the preflight found. It is sent to the platform as the
// registration's facts.
type Report struct {
	OS               string
	Arch             string
	DockerVersion    string
	DockerAPIVersion string
	DockerRootDir    string
	DiskFreeBytes    uint64
}

// Facts is the report as register's `facts` (runner/protocol/PROTOCOL.md §5.1).
func (r Report) Facts() map[string]any {
	return map[string]any{
		"docker":          r.DockerVersion,
		"docker_api":      r.DockerAPIVersion,
		"docker_root_dir": r.DockerRootDir,
		"disk_free_bytes": r.DiskFreeBytes,
	}
}

// Run makes every check and returns the report and one error per failed check,
// joined. A nil error means the machine passed.
func Run(ctx context.Context, env Env) (Report, error) {
	if env.GOOS == "" {
		env.GOOS = runtime.GOOS
	}
	if env.GOARCH == "" {
		env.GOARCH = runtime.GOARCH
	}
	if env.FreeBytes == nil {
		env.FreeBytes = freeBytes
	}
	report := Report{OS: env.GOOS, Arch: env.GOARCH}
	var failures []error

	if env.GOOS != "linux" || (env.GOARCH != "amd64" && env.GOARCH != "arm64") {
		failures = append(failures, fmt.Errorf("the machine is %s/%s: aixle-runner needs Linux on amd64 or arm64", env.GOOS, env.GOARCH))
	}

	if env.Docker == nil {
		failures = append(failures, errors.New("no Docker client"))
		return report, errors.Join(failures...)
	}
	version, err := env.Docker.ServerVersion(ctx, client.ServerVersionOptions{})
	if err != nil {
		failures = append(failures, fmt.Errorf("the Docker daemon is not reachable: %v", err))
		return report, errors.Join(failures...)
	}
	report.DockerVersion, report.DockerAPIVersion = version.Version, version.APIVersion
	if version.APIVersion == "" || versions.LessThan(version.APIVersion, MinDockerAPI) {
		failures = append(failures, fmt.Errorf("the Docker daemon speaks API %q: aixle-runner needs API %s or later (Docker Engine 20.10 or later)", version.APIVersion, MinDockerAPI))
	}

	info, err := env.Docker.Info(ctx, client.InfoOptions{})
	if err != nil {
		failures = append(failures, fmt.Errorf("reading the Docker daemon's info failed: %v", err))
		return report, errors.Join(failures...)
	}
	report.DockerRootDir = info.Info.DockerRootDir
	free, err := env.FreeBytes(report.DockerRootDir)
	if err != nil {
		failures = append(failures, fmt.Errorf("measuring the free space of %s, where Docker keeps its images, failed: %v", report.DockerRootDir, err))
		return report, errors.Join(failures...)
	}
	report.DiskFreeBytes = free
	if free < MinFreeBytes {
		failures = append(failures, fmt.Errorf("%s has %.1f GiB free: aixle-runner needs at least 20 GiB for images and the workspace volume", report.DockerRootDir, float64(free)/(1<<30)))
	}

	return report, errors.Join(failures...)
}
