package cli

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/update"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// HostOptions are the inputs of `aixle-runner --mode host`.
type HostOptions struct {
	StateDir   string
	HTTPClient *http.Client
	Docker     docker.API
	Logger     *slog.Logger
	// Binary is the file a self-update replaces. Empty is the running binary.
	Binary string
}

// RunHost runs the host runner until ctx is done. It holds the state directory's
// lock while it runs, and refuses at once if another process holds it. A failure
// that needs an operator, such as a refusal or missing credentials, satisfies
// NeedsOperator. A self-update that replaced the binary returns host.ErrUpdated.
func RunHost(ctx context.Context, opts HostOptions) error {
	lock, err := lockForHost(opts.StateDir)
	if err != nil {
		return err
	}
	defer lock.Release()

	store := credentials.NewStore(opts.StateDir)
	creds, err := store.Load()
	if errors.Is(err, credentials.ErrNotConfigured) || errors.Is(err, credentials.ErrInvalid) {
		// Restarting cannot fix it: only `configure` can.
		return operatorError{err}
	}
	if err != nil {
		return err
	}
	client, err := protocol.NewClient(creds.URL, version.Version, opts.HTTPClient)
	if err != nil {
		return err
	}
	j, err := journal.Open(opts.StateDir, nil)
	if errors.Is(err, journal.ErrInvalid) {
		// Without the journal the runner cannot tell which ops it ran, so it must
		// not poll this environment again.
		return operatorError{fmt.Errorf("%w. The runner cannot tell which ops it ran: run `aixle-runner unregister`, then `aixle-runner configure` with a new registration token", err)}
	}
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
		"platform", creds.URL, "environment", creds.Environment.Key, "auto_update", creds.AutoUpdateEnabled())
	// The host runner runs every op itself, the session ops included, through the
	// Docker API against the environment's session container (DESIGN.md §6.8).
	env := &docker.Environment{API: api, Key: creds.Environment.Key, StateDir: opts.StateDir, Logger: opts.Logger}
	handlers := map[string]host.Handler{}
	for name, handler := range env.Handlers() {
		handlers[name] = handler
	}
	binary := opts.Binary
	if binary == "" {
		if binary, err = update.BinaryPath(); err != nil {
			return fmt.Errorf("finding the running binary: %w", err)
		}
	}
	loop := &host.Loop{
		Gateway:  client,
		Tokens:   tokens.NewSource(store, client, creds),
		Journal:  j,
		Handlers: handlers,
		Updater: &update.Updater{
			Releases: client,
			Current:  version.Version,
			Binary:   binary,
			Disabled: !creds.AutoUpdateEnabled(),
			Busy:     env.HoldsSession,
			Logger:   opts.Logger,
		},
		Logger: opts.Logger,
	}
	return loop.Run(ctx)
}
