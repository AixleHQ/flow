// Package preflight checks, before `configure` registers a machine, that it can run
// sessions (DESIGN.md §6.8): Linux on amd64 or arm64, a reachable Docker daemon with
// API 1.41 or later. The free disk space is reported for information only: it is
// measured where the runner can, logged, and never refuses a machine
// (docs/design/agent-runtimes/add-machine.md §3.3).
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

// WarnFreeBytes is the free space below which the report warns. It never refuses.
const WarnFreeBytes uint64 = 20 << 30

// MinSubpathAPI and MinSubpathEngine are the Docker Engine API and release that
// mount a volume's subdirectory, which a runner whose state directory is a volume
// needs for its proxy sidecar.
const (
	MinSubpathAPI    = "1.45"
	MinSubpathEngine = "26.0"
)

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
	// StateDir is the runner's state directory: the path whose free space is
	// reported. Empty measures nothing.
	StateDir string
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
	// DiskFreePath is where DiskFreeBytes was measured: the state directory.
	// It is empty when nothing was measured.
	DiskFreePath  string
	DiskFreeBytes uint64
	// Notes are what the preflight found that does not refuse the machine: the
	// free space figure with its path, a warning below WarnFreeBytes, a measure
	// that failed. They are for the operator's log, and nothing relies on them.
	Notes []string
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
	report.measureDisk(env)

	return report, errors.Join(failures...)
}

// measureDisk reports the free space of the state directory, which in a volume is
// on the daemon's filesystem and in a directory on the machine's. It is for
// information only: a failed measure or a low figure is a note, not a failure.
func (r *Report) measureDisk(env Env) {
	if env.StateDir == "" {
		return
	}
	free, err := env.FreeBytes(env.StateDir)
	if err != nil {
		r.Notes = append(r.Notes, fmt.Sprintf("the free space of %s could not be measured (%v); nothing relies on it", env.StateDir, err))
		return
	}
	r.DiskFreePath, r.DiskFreeBytes = env.StateDir, free
	gib := float64(free) / (1 << 30)
	r.Notes = append(r.Notes, fmt.Sprintf("%.1f GiB free on %s (for information only)", gib, env.StateDir))
	if free < WarnFreeBytes {
		r.Notes = append(r.Notes, fmt.Sprintf("only %.1f GiB is free on %s: images and the workspace volume may not fit; this is a warning, the runner starts anyway", gib, env.StateDir))
	}
}

// RequireSubpath is the check of a runner whose state directory is a volume: the
// daemon must be Docker Engine 26.0 (API 1.45) or later, which mounts a volume's
// subdirectory. The error names the version found, the minimum and the ways out.
// A runner with a directory of the machine does not need it.
func RequireSubpath(ctx context.Context, d Docker) error {
	version, err := d.ServerVersion(ctx, client.ServerVersionOptions{})
	if err != nil {
		return fmt.Errorf("the Docker daemon is not reachable: %v", err)
	}
	if version.APIVersion != "" && !versions.LessThan(version.APIVersion, MinSubpathAPI) {
		return nil
	}
	return fmt.Errorf("the Docker daemon is Docker Engine %s (API %q): a runner whose state directory is a volume needs Docker Engine %s or later (API %s). "+
		"Update Docker, or keep the runner's state in a directory on this machine (mount a directory at the state directory instead of a volume), or use the Linux service",
		version.Version, version.APIVersion, MinSubpathEngine, MinSubpathAPI)
}
