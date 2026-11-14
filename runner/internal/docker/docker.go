// Package docker is the host runner's use of the Docker Engine API, through the
// official Go SDK (github.com/moby/moby/client): the preflight's daemon checks,
// the agent container and its image (`container.start` / `container.stop`), the
// callback proxy's sidecar next to it, the session ops run against it, and
// `env.scrub` / `env.reset`.
package docker

import (
	"context"

	"github.com/moby/moby/client"
)

// API is the part of the SDK client the runner calls. *client.Client implements it.
type API interface {
	ServerVersion(ctx context.Context, options client.ServerVersionOptions) (client.ServerVersionResult, error)
	Info(ctx context.Context, options client.InfoOptions) (client.SystemInfoResult, error)
	ImagePull(ctx context.Context, refStr string, options client.ImagePullOptions) (client.ImagePullResponse, error)
	ImageInspect(ctx context.Context, imageID string, inspectOpts ...client.ImageInspectOption) (client.ImageInspectResult, error)

	ContainerCreate(ctx context.Context, options client.ContainerCreateOptions) (client.ContainerCreateResult, error)
	ContainerStart(ctx context.Context, containerID string, options client.ContainerStartOptions) (client.ContainerStartResult, error)
	ContainerStop(ctx context.Context, containerID string, options client.ContainerStopOptions) (client.ContainerStopResult, error)
	ContainerRemove(ctx context.Context, containerID string, options client.ContainerRemoveOptions) (client.ContainerRemoveResult, error)
	ContainerInspect(ctx context.Context, containerID string, options client.ContainerInspectOptions) (client.ContainerInspectResult, error)
	ContainerList(ctx context.Context, options client.ContainerListOptions) (client.ContainerListResult, error)
	ContainerWait(ctx context.Context, containerID string, options client.ContainerWaitOptions) client.ContainerWaitResult
	ContainerLogs(ctx context.Context, containerID string, options client.ContainerLogsOptions) (client.ContainerLogsResult, error)

	ExecCreate(ctx context.Context, containerID string, options client.ExecCreateOptions) (client.ExecCreateResult, error)
	ExecAttach(ctx context.Context, execID string, options client.ExecAttachOptions) (client.ExecAttachResult, error)
	ExecInspect(ctx context.Context, execID string, options client.ExecInspectOptions) (client.ExecInspectResult, error)

	CopyToContainer(ctx context.Context, containerID string, options client.CopyToContainerOptions) (client.CopyToContainerResult, error)
	CopyFromContainer(ctx context.Context, containerID string, options client.CopyFromContainerOptions) (client.CopyFromContainerResult, error)

	VolumeCreate(ctx context.Context, options client.VolumeCreateOptions) (client.VolumeCreateResult, error)
	VolumeInspect(ctx context.Context, volumeID string, options client.VolumeInspectOptions) (client.VolumeInspectResult, error)
	VolumeList(ctx context.Context, options client.VolumeListOptions) (client.VolumeListResult, error)
	VolumeRemove(ctx context.Context, volumeID string, options client.VolumeRemoveOptions) (client.VolumeRemoveResult, error)
}

// Connect returns a client of the local daemon, configured the way the docker CLI
// is: DOCKER_HOST and friends, or the default socket. The API version is
// negotiated with the daemon on the first call.
func Connect() (*client.Client, error) {
	return client.New(client.FromEnv)
}
