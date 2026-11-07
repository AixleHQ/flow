package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/distribution/reference"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Result error classes of `image.ensure` (runner/protocol/PROTOCOL.md §6.1).
const (
	ClassInvalidPayload = "invalid_payload"
	ClassDockerError    = "docker_error"
	ClassImagePull      = "image_pull_failed"
)

// ImageEnsurePayload is the payload of `image.ensure`.
type ImageEnsurePayload struct {
	// Image is the reference as the platform was given it: a tag or a digest.
	Image string `json:"image"`
}

// Reference validates the payload and returns the reference the daemon is
// asked for: the payload's, with the tag `latest` when it names neither a tag
// nor a digest, as `docker pull` reads it.
func (p ImageEnsurePayload) Reference() (string, error) {
	if strings.TrimSpace(p.Image) == "" {
		return "", fmt.Errorf("`image` is required")
	}
	named, err := reference.ParseNormalizedNamed(p.Image)
	if err != nil {
		return "", fmt.Errorf("`image` %q is not an image reference: %v", p.Image, err)
	}
	return reference.FamiliarString(reference.TagNameOnly(named)), nil
}

// ImageEnsure is the `image.ensure` handler: it always pulls the reference, so a
// tag that moved is followed, and the daemon downloads only the layers it lacks.
// It reports whether the pull brought anything new (the image was missing, or
// the reference now names another image) and how long the op took. A pull that
// fails is an `error` result with the registry's or the daemon's words
// (DESIGN.md §8, "Agent image cannot be pulled").
func ImageEnsure(api API, now func() time.Time) func(ctx context.Context, payload json.RawMessage) protocol.Result {
	if now == nil {
		now = time.Now
	}
	return func(ctx context.Context, raw json.RawMessage) protocol.Result {
		var payload ImageEnsurePayload
		if err := json.Unmarshal(raw, &payload); err != nil {
			return protocol.ErrorResult(ClassInvalidPayload, "the payload is not {image}: "+err.Error())
		}
		ref, err := payload.Reference()
		if err != nil {
			return protocol.ErrorResult(ClassInvalidPayload, err.Error())
		}

		started := now()
		before, err := imageID(ctx, api, ref)
		if err != nil {
			return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("inspecting %s failed: %v", ref, err))
		}
		if err := pull(ctx, api, ref); err != nil {
			return protocol.ErrorResult(ClassImagePull, fmt.Sprintf("pulling %s failed: %v", ref, err))
		}
		after, err := imageID(ctx, api, ref)
		if err != nil {
			return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("inspecting %s after its pull failed: %v", ref, err))
		}
		if after == "" {
			return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("the daemon does not have %s after pulling it", ref))
		}
		pulled := before != after

		return protocol.Result{
			Status: protocol.StatusOK,
			Data: map[string]any{
				"pulled":      pulled,
				"duration_ms": now().Sub(started).Milliseconds(),
			},
		}
	}
}

// imageID is the ID of the image the daemon has under ref, or "" when it has none.
func imageID(ctx context.Context, api API, ref string) (string, error) {
	inspected, err := api.ImageInspect(ctx, ref)
	if cerrdefs.IsNotFound(err) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return inspected.ID, nil
}

func pull(ctx context.Context, api API, ref string) error {
	resp, err := api.ImagePull(ctx, ref, client.ImagePullOptions{})
	if err != nil {
		return err
	}
	defer resp.Close()
	// Wait reads the progress stream to its end and returns the error a message of
	// the stream carries: the registry's own words, e.g. "manifest unknown".
	return resp.Wait(ctx)
}
