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

// The agent images (ghcr.io/aixlehq/flow-<image>) are OCI indexes for
// linux/amd64 and linux/arm64; a runtime whose CLI has no arm64 build is
// amd64-only (config/agent_runtimes.json, `platforms`). The runner pulls the
// daemon's own platform when the image has it, and linux/amd64 otherwise, which an
// arm64 daemon runs under emulation: built into OrbStack and Docker Desktop,
// binfmt on ARM Linux (DESIGN.md §6.9.3).

// fallbackPlatform is the platform every agent image has.
func fallbackPlatform() ocispec.Platform {
	return ocispec.Platform{OS: "linux", Architecture: "amd64"}
}

// nativePlatform is the platform of the machine's Docker daemon, as the image
// index names it: arm64 for an arm64 daemon, and linux/amd64 for anything else,
// or when the daemon does not say.
func nativePlatform(ctx context.Context, api API) ocispec.Platform {
	info, err := api.Info(ctx, client.InfoOptions{})
	if err != nil {
		return fallbackPlatform()
	}
	switch strings.ToLower(info.Info.Architecture) {
	case "aarch64", "arm64":
		return ocispec.Platform{OS: "linux", Architecture: "arm64"}
	}
	return fallbackPlatform()
}

// imagePlatform is the platform of the image the daemon holds under ref, which is
// the one the last pull left there: every container made from the image is
// created for it. Nil, the daemon's own choice, when the daemon does not say.
func imagePlatform(ctx context.Context, api API, ref string) *ocispec.Platform {
	inspected, err := api.ImageInspect(ctx, ref)
	if err != nil || inspected.Architecture == "" {
		return nil
	}
	osName := inspected.Os
	if osName == "" {
		osName = "linux"
	}
	return &ocispec.Platform{OS: osName, Architecture: inspected.Architecture}
}

// lacksPlatform reports whether err is the registry's or the daemon's answer to a
// pull of a platform the image does not have, in the wording of the classic image
// store and of containerd's.
func lacksPlatform(err error) bool {
	msg := strings.ToLower(err.Error())
	for _, s := range []string{"no matching manifest", "does not provide the specified platform", "no match for platform"} {
		if strings.Contains(msg, s) {
			return true
		}
	}
	return false
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
// registry (registryAuth), for the daemon's own platform, or for linux/amd64 when
// the image has no build for it. It always pulls, so a tag that moved is followed,
// and the daemon downloads only the layers it lacks. A pull that fails returns the
// registry's or the daemon's own words (DESIGN.md §8, "Agent image cannot be
// pulled"), even when the daemon has an older copy.
func pull(ctx context.Context, api API, ref string) error {
	auth, err := registryAuth(ref)
	if err != nil {
		return err
	}
	native := nativePlatform(ctx, api)
	err = pullFor(ctx, api, ref, auth, native)
	if err != nil && native.Architecture != fallbackPlatform().Architecture && lacksPlatform(err) {
		err = pullFor(ctx, api, ref, auth, fallbackPlatform())
	}
	return err
}

func pullFor(ctx context.Context, api API, ref, auth string, platform ocispec.Platform) error {
	resp, err := api.ImagePull(ctx, ref, client.ImagePullOptions{RegistryAuth: auth, Platforms: []ocispec.Platform{platform}})
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
