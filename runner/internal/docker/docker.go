// Package docker is the host runner's use of the Docker Engine API, through the
// official Go SDK (github.com/moby/moby/client): the preflight's daemon checks and
// the `image.ensure` op.
package docker

import (
	"context"

	"github.com/moby/moby/client"
)

// API is the part of the SDK client the runner calls. *client.Client implements it.
type API interface {
	ServerVersion(ctx context.Context, options client.ServerVersionOptions) (client.ServerVersionResult, error)
	Info(ctx context.Context, options client.InfoOptions) (client.SystemInfoResult, error)
	ImageInspect(ctx context.Context, imageID string, inspectOpts ...client.ImageInspectOption) (client.ImageInspectResult, error)
	ImagePull(ctx context.Context, refStr string, options client.ImagePullOptions) (client.ImagePullResponse, error)
}

// Connect returns a client of the local daemon, configured the way the docker CLI
// is: DOCKER_HOST and friends, or the default socket. The API version is
// negotiated with the daemon on the first call.
func Connect() (*client.Client, error) {
	return client.New(client.FromEnv)
}
