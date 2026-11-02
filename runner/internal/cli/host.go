package cli

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// HostOptions are the inputs of `aixle-runner --mode host`.
type HostOptions struct {
	StateDir   string
	HTTPClient *http.Client
	Docker     docker.API
	Logger     *slog.Logger
}

// RunHost runs the host runner until ctx is done. A refusal that needs an operator
// is returned as a *tokens.StopError.
func RunHost(ctx context.Context, opts HostOptions) error {
	store := credentials.NewStore(opts.StateDir)
	creds, err := store.Load()
	if err != nil {
		return err
	}
	client, err := protocol.NewClient(creds.URL, version.Version, opts.HTTPClient)
	if err != nil {
		return err
	}
	j, err := journal.Open(opts.StateDir, nil)
	if err != nil {
		return err
	}
	api := opts.Docker
	if api == nil {
		c, err := docker.Connect()
		if err != nil {
			return fmt.Errorf("connecting to the Docker daemon: %w", err)
		}
		defer c.Close()
		api = c
	}

	opts.Logger.Info("aixle-runner starting", "mode", "host", "version", version.Version,
		"platform", creds.URL, "environment", creds.Environment.Key)
	loop := &host.Loop{
		Gateway: client,
		Tokens:  tokens.NewSource(store, client, creds),
		Journal: j,
		Handlers: map[string]host.Handler{
			"image.ensure": docker.ImageEnsure(api, nil),
		},
		Logger: opts.Logger,
	}
	return loop.Run(ctx)
}
