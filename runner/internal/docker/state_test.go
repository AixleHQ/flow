package docker

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/api/types/system"
	"github.com/moby/moby/client"
)

// inspectingAPI answers what LocateState asks: the inspect of the runner's own
// container, and the daemon's info.
type inspectingAPI struct {
	API
	container container.InspectResponse
	err       error
	asked     []string
}

func (a *inspectingAPI) ContainerInspect(_ context.Context, id string, _ client.ContainerInspectOptions) (client.ContainerInspectResult, error) {
	a.asked = append(a.asked, id)
	if a.err != nil {
		return client.ContainerInspectResult{}, a.err
	}
	return client.ContainerInspectResult{Container: a.container}, nil
}

func (a *inspectingAPI) Info(context.Context, client.InfoOptions) (client.SystemInfoResult, error) {
	return client.SystemInfoResult{Info: system.Info{DockerRootDir: "/var/lib/docker"}}, nil
}

const ownID = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func ownContainer(hostname string, mounts ...container.MountPoint) *inspectingAPI {
	return &inspectingAPI{container: container.InspectResponse{
		ID: ownID, Config: &container.Config{Hostname: hostname}, Mounts: mounts,
	}}
}

func TestLocateStateOfAVolumeAnonymousOrNamed(t *testing.T) {
	for _, name := range []string{"aixle-runner", "9c1f3a5e0d2b4c6a8e0f1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f"} {
		api := ownContainer(ownID[:12], container.MountPoint{Type: mount.TypeVolume, Name: name, Source: "/var/lib/docker/volumes/x/_data", Destination: "/var/lib/aixle-runner"})
		got, err := LocateState(context.Background(), api, "/var/lib/aixle-runner", ownID[:12])
		if err != nil {
			t.Fatal(err)
		}
		want := StateLocation{Kind: StateVolume, Dir: "/var/lib/aixle-runner", Volume: name, DataRoot: "/var/lib/docker"}
		if got != want {
			t.Fatalf("got %+v, want %+v", got, want)
		}
		if !reflect.DeepEqual(api.asked, []string{ownID[:12]}) {
			t.Fatalf("asked for %v: the container is found by the hostname", api.asked)
		}
	}
}

func TestLocateStateOfADirectoryTakesTheMountsSource(t *testing.T) {
	api := ownContainer(ownID[:12], container.MountPoint{Type: mount.TypeBind, Source: "/srv/aixle", Destination: "/var/lib/aixle-runner"})
	got, err := LocateState(context.Background(), api, "/var/lib/aixle-runner", ownID[:12])
	if err != nil {
		t.Fatal(err)
	}
	// The path on the machine needs not be the path in the container.
	if want := (StateLocation{Kind: StateDirectory, Dir: "/var/lib/aixle-runner", Source: "/srv/aixle"}); got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
}

func TestLocateStateStopsWhenTheContainerItFoundIsNotItself(t *testing.T) {
	state := container.MountPoint{Type: mount.TypeVolume, Name: "v", Destination: "/var/lib/aixle-runner"}
	cases := map[string]*inspectingAPI{
		// --hostname overridden: no container has that id or name.
		"no such container": {err: cerrdefs.ErrNotFound},
		// --network host: the hostname is the machine's, and some other container may carry it.
		"another hostname": ownContainer("somebody-else", state),
		"another id":       {container: container.InspectResponse{ID: "ffffffffffff" + ownID[12:], Config: &container.Config{Hostname: ownID[:12]}, Mounts: []container.MountPoint{state}}},
		"no mount at the state directory": ownContainer(ownID[:12],
			container.MountPoint{Type: mount.TypeVolume, Name: "v", Destination: "/elsewhere"}),
	}
	for name, api := range cases {
		_, err := LocateState(context.Background(), api, "/var/lib/aixle-runner", ownID[:12])
		if !errors.Is(err, ErrNotOwnContainer) {
			t.Errorf("%s: %v", name, err)
			continue
		}
		for _, want := range []string{"--hostname", "--network host"} {
			if !strings.Contains(err.Error(), want) {
				t.Errorf("%s: the error does not name %s: %v", name, want, err)
			}
		}
	}
	if _, err := LocateState(context.Background(), ownContainer(""), "/var/lib/aixle-runner", ""); !errors.Is(err, ErrNotOwnContainer) {
		t.Errorf("an empty hostname: %v", err)
	}
	// A failed inspect stops the start with its reason.
	if _, err := LocateState(context.Background(), &inspectingAPI{err: errors.New("boom")}, "/var/lib/aixle-runner", "abc"); err == nil || !strings.Contains(err.Error(), "boom") || errors.Is(err, ErrNotOwnContainer) {
		t.Errorf("a failed inspect: %v", err)
	}
	tmpfs := ownContainer(ownID[:12], container.MountPoint{Type: mount.TypeTmpfs, Destination: "/var/lib/aixle-runner"})
	if _, err := LocateState(context.Background(), tmpfs, "/var/lib/aixle-runner", ownID[:12]); err == nil || !strings.Contains(err.Error(), "volume or a directory") {
		t.Errorf("a tmpfs: %v", err)
	}
}

func TestAMountOfTheStateDirectoryPerKind(t *testing.T) {
	const dir = "/var/lib/aixle-runner"
	bin, socket := filepath.Join(dir, "bin"), filepath.Join(dir, "proxy", "123")
	cases := map[string]struct {
		at         StateLocation
		bin, proxy mount.Mount
	}{
		"on the machine": {
			OnMachine(dir),
			mount.Mount{Type: mount.TypeBind, Source: bin, Target: "/aixle-bin", ReadOnly: true},
			mount.Mount{Type: mount.TypeBind, Source: socket, Target: "/run/aixle-proxy", ReadOnly: true},
		},
		"a volume": {
			StateLocation{Kind: StateVolume, Dir: dir, Volume: "aixle-runner"},
			mount.Mount{Type: mount.TypeVolume, Source: "aixle-runner", Target: "/aixle-bin", ReadOnly: true, VolumeOptions: &mount.VolumeOptions{Subpath: "bin"}},
			mount.Mount{Type: mount.TypeVolume, Source: "aixle-runner", Target: "/run/aixle-proxy", ReadOnly: true, VolumeOptions: &mount.VolumeOptions{Subpath: "proxy/123"}},
		},
		"a directory": {
			StateLocation{Kind: StateDirectory, Dir: dir, Source: "/srv/aixle"},
			mount.Mount{Type: mount.TypeBind, Source: "/srv/aixle/bin", Target: "/aixle-bin", ReadOnly: true},
			mount.Mount{Type: mount.TypeBind, Source: "/srv/aixle/proxy/123", Target: "/run/aixle-proxy", ReadOnly: true},
		},
	}
	for name, tc := range cases {
		gotBin, err := tc.at.Mount(bin, "/aixle-bin", true)
		if err != nil || !reflect.DeepEqual(gotBin, tc.bin) {
			t.Errorf("%s: bin %#v, %v", name, gotBin, err)
		}
		gotProxy, err := tc.at.Mount(socket, "/run/aixle-proxy", true)
		if err != nil || !reflect.DeepEqual(gotProxy, tc.proxy) {
			t.Errorf("%s: proxy %#v, %v", name, gotProxy, err)
		}
	}
	// Nothing outside the state directory is mounted from a volume or a directory.
	for _, at := range []StateLocation{cases["a volume"].at, cases["a directory"].at} {
		if _, err := at.Mount("/etc", "/x", true); err == nil {
			t.Errorf("%+v mounted /etc", at)
		}
		if _, err := at.Mount(dir+"/../etc", "/x", true); err == nil {
			t.Errorf("%+v mounted a path that leaves the state directory", at)
		}
	}
}

func TestTheSidecarMountsSubdirectoriesOfAVolumeOrADirectory(t *testing.T) {
	state := "/var/lib/aixle-runner"
	cases := map[string]struct {
		at   StateLocation
		want func(rel string, readOnly bool) mount.Mount
	}{
		"anonymous volume": {StateLocation{Kind: StateVolume, Dir: state, Volume: "0f3a9c"}, func(rel string, ro bool) mount.Mount {
			return mount.Mount{Type: mount.TypeVolume, Source: "0f3a9c", Target: "", ReadOnly: ro, VolumeOptions: &mount.VolumeOptions{Subpath: rel}}
		}},
		"named volume": {StateLocation{Kind: StateVolume, Dir: state, Volume: "aixle-runner"}, func(rel string, ro bool) mount.Mount {
			return mount.Mount{Type: mount.TypeVolume, Source: "aixle-runner", Target: "", ReadOnly: ro, VolumeOptions: &mount.VolumeOptions{Subpath: rel}}
		}},
		"directory": {StateLocation{Kind: StateDirectory, Dir: state, Source: "/home/me/aixle"}, func(rel string, ro bool) mount.Mount {
			return mount.Mount{Type: mount.TypeBind, Source: "/home/me/aixle/" + rel, Target: "", ReadOnly: ro}
		}},
	}
	for name, tc := range cases {
		h := newEnvironment(t)
		p, _ := h.withProxy()
		p.dir = filepath.Join(t.TempDir(), "proxy")
		stateDir := filepath.Dir(p.dir)
		p.binary = filepath.Join(stateDir, "bin", "aixle-runner")
		tc.at.Dir = stateDir
		h.env.State = tc.at

		if r := h.start(h.env, nil); r.Status != "ok" {
			t.Fatalf("%s: %#v %v", name, r, r.Error)
		}
		sidecar := h.byName(h.env.SidecarName(sessionID))
		if sidecar == nil {
			t.Fatalf("%s: no sidecar", name)
		}
		bin, socket := tc.want("bin", true), tc.want("proxy/123", true)
		bin.Target, socket.Target = SidecarBinaryDir, SidecarSocketDir
		if !reflect.DeepEqual(sidecar.Host.Mounts, []mount.Mount{bin, socket}) {
			t.Errorf("%s: mounts %#v, want %#v and %#v", name, sidecar.Host.Mounts, bin, socket)
		}
		if got := sidecar.Config.Entrypoint[0]; got != SidecarBinary {
			t.Errorf("%s: the sidecar runs %s, not %s", name, got, SidecarBinary)
		}
		for _, m := range sidecar.Host.Mounts {
			if strings.Contains(m.Source, "/volumes/") || strings.HasPrefix(m.Source, "/var/lib/docker") {
				t.Errorf("%s: a mount from under Docker's data root: %s", name, m.Source)
			}
		}
	}
}

func TestCheckBindProtectsWhereTheStateDirectoryIsOnTheMachine(t *testing.T) {
	state := t.TempDir()
	source, dataRoot, other := t.TempDir(), t.TempDir(), t.TempDir()
	cases := map[string]struct {
		at      StateLocation
		bind    string
		refused bool
	}{
		"a directory's source":              {StateLocation{Kind: StateDirectory, Dir: state, Source: source}, source, true},
		"inside a directory's source":       {StateLocation{Kind: StateDirectory, Dir: state, Source: source}, filepath.Join(source, "bin"), true},
		"a path that holds the source":      {StateLocation{Kind: StateDirectory, Dir: state, Source: source}, filepath.Dir(source), true},
		"another path with a directory":     {StateLocation{Kind: StateDirectory, Dir: state, Source: source}, other, false},
		"a volume's files, under the root":  {StateLocation{Kind: StateVolume, Dir: state, Volume: "v", DataRoot: dataRoot}, filepath.Join(dataRoot, "volumes"), true},
		"another path with a volume":        {StateLocation{Kind: StateVolume, Dir: state, Volume: "v", DataRoot: dataRoot}, other, false},
		"the state directory on a machine":  {OnMachine(state), state, true},
		"another path on a machine":         {OnMachine(state), other, false},
		"the state directory in a volume":   {StateLocation{Kind: StateVolume, Dir: state, Volume: "v", DataRoot: dataRoot}, state, true},
		"a path inside the state directory": {StateLocation{Kind: StateDirectory, Dir: state, Source: source}, filepath.Join(state, "proxy"), true},
	}
	for name, tc := range cases {
		e := &Environment{StateDir: state, State: tc.at}
		if tc.bind == filepath.Join(state, "proxy") {
			if err := mkdir(filepath.Join(state, "proxy")); err != nil {
				t.Fatal(err)
			}
		}
		r := e.checkBind(tc.bind)
		if (r != nil) != tc.refused {
			t.Errorf("%s: refused %v: %v", name, r != nil, r)
		}
	}
}

func mkdir(path string) error { return os.MkdirAll(path, 0o755) }
