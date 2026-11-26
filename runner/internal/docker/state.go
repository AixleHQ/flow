package docker

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"strings"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"
)

// Where the runner's state directory lives on the machine, so that the proxy
// sidecar, which the Docker daemon creates, can mount a part of it
// (docs/design/agent-runtimes/add-machine.md §3.2). Only official Docker APIs
// are used: a volume's `Subpath`, or a bind under a bind mount's `Source`. Nothing
// is ever mounted from under Docker's data root.

// StateKind is how the state directory is held.
type StateKind int

const (
	// StateOnMachine is a runner that runs on the machine itself: the state
	// directory's path is the machine's path.
	StateOnMachine StateKind = iota
	// StateVolume is a runner in a container whose state directory is a
	// volume, anonymous or named.
	StateVolume
	// StateDirectory is a runner in a container whose state directory is a
	// bind mount of a directory of the machine.
	StateDirectory
)

// StateLocation says where the state directory is on the machine.
type StateLocation struct {
	Kind StateKind
	// Dir is the state directory as this process sees it, absolute.
	Dir string
	// Volume is the volume's name, for StateVolume.
	Volume string
	// Source is the machine's path of the directory, for StateDirectory.
	Source string
	// DataRoot is the daemon's data root, for StateVolume: no agent bind may
	// reach under it, which is where a volume's files are.
	DataRoot string
}

// OnMachine is the location of a runner that runs on the machine itself.
func OnMachine(stateDir string) StateLocation {
	if abs, err := filepath.Abs(stateDir); err == nil {
		stateDir = abs
	}
	return StateLocation{Kind: StateOnMachine, Dir: stateDir}
}

// Mount is the mount of path, a file or directory of the state directory, at
// target in a container the runner creates.
func (l StateLocation) Mount(path, target string, readOnly bool) (mount.Mount, error) {
	if l.Kind == StateOnMachine {
		return mount.Mount{Type: mount.TypeBind, Source: path, Target: target, ReadOnly: readOnly}, nil
	}
	rel, err := filepath.Rel(l.Dir, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, "../") {
		return mount.Mount{}, fmt.Errorf("%s is not in the state directory %s", path, l.Dir)
	}
	switch l.Kind {
	case StateVolume:
		m := mount.Mount{Type: mount.TypeVolume, Source: l.Volume, Target: target, ReadOnly: readOnly}
		if rel != "." {
			m.VolumeOptions = &mount.VolumeOptions{Subpath: rel}
		}
		return m, nil
	case StateDirectory:
		return mount.Mount{Type: mount.TypeBind, Source: filepath.Join(l.Source, rel), Target: target, ReadOnly: readOnly}, nil
	}
	return mount.Mount{}, fmt.Errorf("unknown state location kind %d", l.Kind)
}

// protectedPaths are the machine's paths that an agent's bind must neither be in
// nor contain, beside the state directory itself.
func (l StateLocation) protectedPaths() []string {
	switch l.Kind {
	case StateVolume:
		if l.DataRoot != "" {
			return []string{l.DataRoot}
		}
	case StateDirectory:
		return []string{l.Source}
	}
	return nil
}

// ErrNotOwnContainer says the runner could not tell that the container it found
// by its hostname is its own.
var ErrNotOwnContainer = errors.New("the runner could not find its own container")

// LocateState finds where stateDir is on the machine for a runner in a
// container. It finds the container by hostname, which Docker sets to the
// container's short id, and checks that the container is itself: the same
// hostname and a mount at the state directory. It reads only where the
// directory lives, and chooses no behaviour.
func LocateState(ctx context.Context, api API, stateDir, hostname string) (StateLocation, error) {
	abs, err := filepath.Abs(stateDir)
	if err != nil {
		return StateLocation{}, err
	}
	notOwn := func(format string, args ...any) error {
		return fmt.Errorf("%w: %s. Run the container without overriding --hostname and without --network host, with the state directory %s mounted as a volume or a directory",
			ErrNotOwnContainer, fmt.Sprintf(format, args...), abs)
	}
	if hostname == "" {
		return StateLocation{}, notOwn("the hostname is empty")
	}
	inspected, err := api.ContainerInspect(ctx, hostname, client.ContainerInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return StateLocation{}, notOwn("no container has the hostname %q", hostname)
	}
	if err != nil {
		return StateLocation{}, fmt.Errorf("inspecting its own container %q failed: %w", hostname, err)
	}
	c := inspected.Container
	if c.Config == nil || c.Config.Hostname != hostname || !strings.HasPrefix(c.ID, hostname) {
		return StateLocation{}, notOwn("the container found for the hostname %q is not this one", hostname)
	}
	for _, m := range c.Mounts {
		if filepath.Clean(m.Destination) != abs {
			continue
		}
		switch m.Type {
		case mount.TypeVolume:
			if m.Name == "" {
				return StateLocation{}, fmt.Errorf("the volume mounted at %s has no name", abs)
			}
			info, err := api.Info(ctx, client.InfoOptions{})
			if err != nil {
				return StateLocation{}, fmt.Errorf("reading the Docker daemon's info failed: %w", err)
			}
			return StateLocation{Kind: StateVolume, Dir: abs, Volume: m.Name, DataRoot: info.Info.DockerRootDir}, nil
		case mount.TypeBind:
			if !filepath.IsAbs(m.Source) {
				return StateLocation{}, fmt.Errorf("the directory mounted at %s has the source %q, which is not an absolute path", abs, m.Source)
			}
			return StateLocation{Kind: StateDirectory, Dir: abs, Source: filepath.Clean(m.Source)}, nil
		}
		return StateLocation{}, fmt.Errorf("%s is a %s mount: the state directory must be a volume or a directory of the machine", abs, m.Type)
	}
	return StateLocation{}, notOwn("the container has no mount at the state directory")
}
