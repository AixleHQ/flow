package docker

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/distribution/reference"
	"github.com/docker/cli/cli/config"
	"github.com/docker/cli/cli/config/configfile"
	"github.com/moby/moby/api/pkg/authconfig"
	"github.com/moby/moby/api/types/registry"
	"github.com/moby/moby/client"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
)

// AgentPlatform is the platform the agent images are built for: the images
// (ghcr.io/aixlehq/flow-<image>) are OCI indexes with linux/amd64 only. The pull
// and the creation of every container made from one ask for it, so a daemon on
// arm64 runs them under amd64 emulation instead of failing with "no matching
// manifest for linux/arm64/v8" (DESIGN.md §6.9.3). Native arm64 images, when
// they exist, make this the daemon's own platform again.
func AgentPlatform() *ocispec.Platform {
	return &ocispec.Platform{OS: "linux", Architecture: "amd64"}
}

// Result error classes shared by the ops (runner/protocol/PROTOCOL.md §6).
const (
	ClassInvalidPayload = "invalid_payload"
	ClassDockerError    = "docker_error"
	// ClassImagePull is the pull of `container.start` failing (PROTOCOL.md §6.2).
	ClassImagePull = "image_pull_failed"
)

// dockerConfig is the Docker CLI configuration of the user the runner runs as:
// $DOCKER_CONFIG/config.json, or ~/.docker/config.json. It is read for every
// pull, so a `docker login` takes effect without a restart. Replaced in tests.
var dockerConfig = func() *configfile.ConfigFile {
	return config.LoadDefaultConfigFile(os.Stderr)
}

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

// pull pulls ref through the Docker Engine API, with the credentials of its
// registry (registryAuth). It always pulls, so a tag that moved is followed, and
// the daemon downloads only the layers it lacks. A pull that fails returns the
// registry's or the daemon's own words (DESIGN.md §8, "Agent image cannot be
// pulled"), even when the daemon has an older copy.
func pull(ctx context.Context, api API, ref string) error {
	auth, err := registryAuth(ref)
	if err != nil {
		return err
	}
	resp, err := api.ImagePull(ctx, ref, client.ImagePullOptions{RegistryAuth: auth, Platforms: []ocispec.Platform{*AgentPlatform()}})
	if err != nil {
		return err
	}
	defer resp.Close()
	// Wait reads the progress stream to its end and returns the error a message of
	// the stream carries: the registry's own words, e.g. "manifest unknown".
	return resp.Wait(ctx)
}

// registryAuth resolves the credentials of ref's registry as the Docker CLI does
// for `docker pull`: from the Docker configuration of the user the runner runs
// as, through its credential helpers too, and encodes them for the Engine API's
// X-Registry-Auth. With no credentials for the registry it answers "", and the
// pull is anonymous. The credentials are never logged or kept.
func registryAuth(ref string) (string, error) {
	named, err := reference.ParseNormalizedNamed(ref)
	if err != nil {
		return "", err
	}
	host := authConfigKey(reference.Domain(named))
	found, err := dockerConfig().GetAuthConfig(host)
	if err != nil {
		return "", fmt.Errorf("reading the Docker credentials of %s failed: %w", host, err)
	}
	auth := registry.AuthConfig(found)
	if auth.Username == "" && auth.Password == "" && auth.Auth == "" && auth.IdentityToken == "" && auth.RegistryToken == "" {
		return "", nil
	}
	return authconfig.Encode(auth)
}

// dockerHubAuthKey is the key `docker login` and the credential helpers store
// Docker Hub's credentials under (the CLI's registry.IndexServer).
const dockerHubAuthKey = "https://index.docker.io/v1/"

// authConfigKey is the key of a registry's credentials in the Docker
// configuration, as the Docker CLI's getAuthConfigKey maps it: Docker Hub's are
// under dockerHubAuthKey, every other registry's under its domain.
func authConfigKey(domain string) string {
	if domain == "docker.io" || domain == "index.docker.io" {
		return dockerHubAuthKey
	}
	return domain
}
