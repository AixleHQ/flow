package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/api/types/mount"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Result error classes of `env.scrub` and `env.reset` (PROTOCOL.md §6.4).
const (
	ClassScrubFailed = "scrub_failed"
	ClassResetFailed = "reset_failed"
)

// OutputsPath is the directory on the workspace volume that a scrub empties.
const OutputsPath = WorkspaceTarget + "/outputs"

// emptyOutputs is the command of the short-lived container that empties the
// outputs. find does not follow a symlink it is given (-P), so an outputs that
// the agent replaced with a link empties nothing outside the volume.
const emptyOutputs = `if [ -d ` + OutputsPath + ` ]; then find ` + OutputsPath + ` -mindepth 1 -delete; fi`

// ScrubPayload is the payload of `env.scrub`: the agent image, a reference as in
// `container.start`, that the container emptying the outputs runs. The daemon
// has it: the session's `container.start` pulled it.
type ScrubPayload struct {
	Image string `json:"image"`
}

// Scrub is `env.scrub` (DESIGN.md §7.2): it removes the environment's containers
// with `docker rm -f`, checks by label that none is left, and empties
// /workspace/outputs on the workspace volume. Repository checkouts, cache
// volumes and pulled images stay. It selects only by the environment's label and
// volume name, and never walks a host mount.
func (e *Environment) Scrub(ctx context.Context, raw json.RawMessage) protocol.Result {
	var p ScrubPayload
	if r := decodePayload(raw, &p, "{image}"); r != nil {
		return *r
	}
	ref, err := imageReference(p.Image)
	if err != nil {
		return *invalid("%s", err.Error())
	}

	removed, r := e.removeContainers(ctx, ClassScrubFailed)
	if r != nil {
		return *r
	}
	emptied, err := e.emptyOutputs(ctx, ref)
	if err != nil {
		return protocol.ErrorResult(ClassScrubFailed, "emptying "+OutputsPath+" failed: "+err.Error())
	}
	// The container that emptied the outputs is gone too.
	if r := e.checkNoContainer(ctx, ClassScrubFailed); r != nil {
		return *r
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{
		"removed_containers": removed,
		"outputs_emptied":    emptied,
	}}
}

// Reset is `env.reset` (DESIGN.md §7.2): the containers as in a scrub, then the
// workspace volume and every cache volume of the environment, each selected by
// its name and the environment's label. Pulled images stay. A volume with the
// environment's name but without its label is not the environment's: the reset
// removes no volume and answers `reset_failed` naming it.
func (e *Environment) Reset(ctx context.Context, _ json.RawMessage) protocol.Result {
	removed, r := e.removeContainers(ctx, ClassResetFailed)
	if r != nil {
		return *r
	}
	volumes, foreign, err := e.volumes(ctx)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, "listing the environment's volumes failed: "+err.Error())
	}
	if len(foreign) > 0 {
		return protocol.ErrorResult(ClassResetFailed, fmt.Sprintf(
			"volumes named like this environment's do not carry the label %s=%s, so they are not its own and no volume was removed: %s",
			LabelEnvironment, e.Key, strings.Join(foreign, ", ")))
	}
	removedVolumes := []string{}
	for _, name := range volumes {
		_, err := e.API.VolumeRemove(ctx, name, client.VolumeRemoveOptions{})
		if cerrdefs.IsNotFound(err) {
			continue
		}
		if err != nil {
			return protocol.ErrorResult(ClassResetFailed, fmt.Sprintf("removing the volume %s failed: %v", name, err))
		}
		removedVolumes = append(removedVolumes, name)
	}
	left, _, err := e.volumes(ctx)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, "listing the environment's volumes failed: "+err.Error())
	}
	if len(left) > 0 {
		return protocol.ErrorResult(ClassResetFailed, "volumes of the environment are left: "+strings.Join(left, ", "))
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{
		"removed_containers": removed,
		"removed_volumes":    removedVolumes,
	}}
}

// removeContainers removes every container labelled with the environment, the
// proxy sidecars included, then checks by label that none is left, and stops
// every relay of the environment.
func (e *Environment) removeContainers(ctx context.Context, class string) ([]string, *protocol.Result) {
	found, err := e.containers(ctx)
	if err != nil {
		r := protocol.ErrorResult(ClassDockerError, "listing the environment's containers failed: "+err.Error())
		return nil, &r
	}
	removed := []string{}
	// No session is left on the environment, so neither is a relay of one.
	if e.Proxy != nil {
		defer e.Proxy.CloseAll()
	}
	for _, c := range found {
		if c.Labels[LabelRole] == RoleProxy {
			e.retire(c.ID)
		}
		gone, err := e.removeContainer(ctx, c.ID, false)
		if err != nil {
			r := protocol.ErrorResult(class, err.Error())
			return nil, &r
		}
		if gone {
			removed = append(removed, containerLabel(c))
		}
	}
	sort.Strings(removed)
	if r := e.checkNoContainer(ctx, class); r != nil {
		return nil, r
	}
	return removed, nil
}

func (e *Environment) checkNoContainer(ctx context.Context, class string) *protocol.Result {
	left, err := e.containers(ctx)
	if err != nil {
		r := protocol.ErrorResult(ClassDockerError, "listing the environment's containers failed: "+err.Error())
		return &r
	}
	if len(left) > 0 {
		var names []string
		for _, c := range left {
			names = append(names, containerLabel(c))
		}
		r := protocol.ErrorResult(class, "containers of the environment are left: "+strings.Join(names, ", "))
		return &r
	}
	return nil
}

// volumes are the environment's volumes: `aixle-ws-<key>` and
// `aixle-cache-<key>-*`, each also labelled with the environment. The label
// keeps the prefix of another environment's key from matching. foreign are the
// volumes with such a name that are not the environment's: without its label,
// and not explained by another environment's label either (a cache volume of a
// key that starts with this one's is that environment's, not foreign).
func (e *Environment) volumes(ctx context.Context) (owned, foreign []string, err error) {
	res, err := e.API.VolumeList(ctx, client.VolumeListOptions{Filters: make(client.Filters).Add("name", "aixle-")})
	if err != nil {
		return nil, nil, err
	}
	for _, v := range res.Items {
		label := v.Labels[LabelEnvironment]
		switch {
		case v.Name == e.WorkspaceVolume():
		case strings.HasPrefix(v.Name, e.cacheVolumePrefix()):
			if label != e.Key && label != "" && strings.HasPrefix(v.Name, "aixle-cache-"+label+"-") {
				continue
			}
		default:
			continue
		}
		if label == e.Key {
			owned = append(owned, v.Name)
		} else {
			foreign = append(foreign, v.Name)
		}
	}
	sort.Strings(owned)
	sort.Strings(foreign)
	return owned, foreign, nil
}

// emptyOutputs runs a short-lived container of the agent image with the workspace
// volume mounted, which empties /workspace/outputs and is removed. It answers
// false when the environment has no workspace volume. A workspace volume without
// the environment's label is not its own: it is not mounted, and nothing is
// emptied.
func (e *Environment) emptyOutputs(ctx context.Context, ref string) (bool, error) {
	inspected, err := e.API.VolumeInspect(ctx, e.WorkspaceVolume(), client.VolumeInspectOptions{})
	if cerrdefs.IsNotFound(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if got := inspected.Volume.Labels[LabelEnvironment]; got != e.Key {
		return false, fmt.Errorf("the volume %s does not carry the label %s=%s (it has %q), so it is not this environment's; it was not mounted or changed",
			e.WorkspaceVolume(), LabelEnvironment, e.Key, got)
	}

	created, err := e.API.ContainerCreate(ctx, client.ContainerCreateOptions{
		Name:     "aixle-" + e.Key + "-scrub",
		Platform: imagePlatform(ctx, e.API, ref),
		Config: &container.Config{
			Image:      ref,
			Entrypoint: []string{"/bin/sh", "-c", emptyOutputs},
			User:       "0:0",
			WorkingDir: "/",
			Labels:     map[string]string{LabelEnvironment: e.Key, LabelRole: "scrub"},
		},
		HostConfig: &container.HostConfig{
			NetworkMode: "none",
			Mounts:      []mount.Mount{{Type: mount.TypeVolume, Source: e.WorkspaceVolume(), Target: WorkspaceTarget}},
			SecurityOpt: []string{"no-new-privileges"},
		},
	})
	if cerrdefs.IsNotFound(err) {
		return false, fmt.Errorf("the daemon does not have %s: container.start pulls it (%v)", ref, err)
	}
	if err != nil {
		return false, err
	}
	// The removal runs under its own timeout, not under the op's context, which
	// has ended or is about to: a stalled daemon then cannot hold up the serial
	// ops loop. A helper that is left is found by the final check by label, as
	// `scrub_failed`, and removed by the next scrub or reset.
	defer func() {
		removeCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), e.removeTimeout())
		defer cancel()
		_, _ = e.API.ContainerRemove(removeCtx, created.ID, client.ContainerRemoveOptions{Force: true, RemoveVolumes: true})
	}()

	wait := e.API.ContainerWait(ctx, created.ID, client.ContainerWaitOptions{Condition: container.WaitConditionNextExit})
	if _, err := e.API.ContainerStart(ctx, created.ID, client.ContainerStartOptions{}); err != nil {
		return false, err
	}
	select {
	case res := <-wait.Result:
		if res.Error != nil && res.Error.Message != "" {
			return false, fmt.Errorf("the container failed: %s", res.Error.Message)
		}
		if res.StatusCode != 0 {
			return false, fmt.Errorf("the container exited with %d", res.StatusCode)
		}
	case err := <-wait.Error:
		return false, err
	case <-ctx.Done():
		return false, ctx.Err()
	}
	return true, nil
}
