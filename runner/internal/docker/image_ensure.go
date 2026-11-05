package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
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

var digestPattern = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)

// ImageEnsurePayload is the payload of `image.ensure`.
type ImageEnsurePayload struct {
	Image  string `json:"image"`
	Digest string `json:"digest"`
}

// Reference validates the payload and returns `image@digest`.
func (p ImageEnsurePayload) Reference() (string, error) {
	if p.Image == "" {
		return "", fmt.Errorf("`image` is required")
	}
	if strings.Contains(p.Image, "@") {
		return "", fmt.Errorf("`image` must not carry a digest, the digest is its own field: got %q", p.Image)
	}
	if !digestPattern.MatchString(p.Digest) {
		return "", fmt.Errorf("`digest` must be sha256:<64 lowercase hex digits>, got %q", p.Digest)
	}
	ref := p.Image + "@" + p.Digest
	if _, err := reference.ParseNormalizedNamed(ref); err != nil {
		return "", fmt.Errorf("%q is not an image reference: %v", ref, err)
	}
	return ref, nil
}

// ImageEnsure is the `image.ensure` handler: it pulls `image@digest` unless the
// daemon has it already, and reports whether it pulled and how long the op took.
// A pull that fails is an `error` result with the registry's message (DESIGN.md §8,
// "Agent image cannot be pulled").
func ImageEnsure(api API, now func() time.Time) func(ctx context.Context, payload json.RawMessage) protocol.Result {
	if now == nil {
		now = time.Now
	}
	return func(ctx context.Context, raw json.RawMessage) protocol.Result {
		var payload ImageEnsurePayload
		if err := json.Unmarshal(raw, &payload); err != nil {
			return protocol.ErrorResult(ClassInvalidPayload, "the payload is not {image, digest}: "+err.Error())
		}
		ref, err := payload.Reference()
		if err != nil {
			return protocol.ErrorResult(ClassInvalidPayload, err.Error())
		}

		started := now()
		pulled := false
		_, err = api.ImageInspect(ctx, ref)
		switch {
		case err == nil:
		case cerrdefs.IsNotFound(err):
			if err := pull(ctx, api, ref); err != nil {
				return protocol.ErrorResult(ClassImagePull, fmt.Sprintf("pulling %s failed: %v", ref, err))
			}
			pulled = true
		default:
			return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("inspecting %s failed: %v", ref, err))
		}

		return protocol.Result{
			Status: protocol.StatusOK,
			Data: map[string]any{
				"pulled":      pulled,
				"duration_ms": now().Sub(started).Milliseconds(),
			},
		}
	}
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
