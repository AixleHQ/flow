package docker

import (
	"context"
	"fmt"
	"strings"

	"github.com/distribution/reference"
	"github.com/moby/moby/client"
)

// Result error classes shared by the ops (runner/protocol/PROTOCOL.md §6).
const (
	ClassInvalidPayload = "invalid_payload"
	ClassDockerError    = "docker_error"
	// ClassImagePull is the pull of `container.start` failing (PROTOCOL.md §6.2).
	ClassImagePull = "image_pull_failed"
)

// imageReference validates an op's `image` and returns the reference the daemon
// is asked for: the one given, a tag or a digest, with the tag `latest` when it
// names neither, as `docker pull` reads it.
func imageReference(image string) (string, error) {
	if strings.TrimSpace(image) == "" {
		return "", fmt.Errorf("`image` is required")
	}
	named, err := reference.ParseNormalizedNamed(image)
	if err != nil {
		return "", fmt.Errorf("`image` %q is not an image reference: %v", image, err)
	}
	return reference.FamiliarString(reference.TagNameOnly(named)), nil
}

// pull pulls ref through the Docker Engine API. It always pulls, so a tag that
// moved is followed, and the daemon downloads only the layers it lacks. A pull
// that fails returns the registry's or the daemon's own words (DESIGN.md §8,
// "Agent image cannot be pulled"), even when the daemon has an older copy.
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
