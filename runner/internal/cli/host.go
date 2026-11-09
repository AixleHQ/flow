package cli

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// HostOptions are the inputs of `aixle-runner --mode host`.
type HostOptions struct {
	StateDir   string
	HTTPClient *http.Client
	Docker     docker.API
	Logger     *slog.Logger
	// Binary is the runner's own executable, which the proxy sidecar runs.
	// Empty is this process's executable.
	Binary string
}

// RunHost runs the host runner until ctx is done. It holds the state directory's
// lock while it runs, and refuses at once if another process holds it. A failure
// that needs an operator, such as a refusal or missing credentials, satisfies
// NeedsOperator.
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

	binary, err := ownBinary(opts.Binary)
	if err != nil {
		return err
	}

	opts.Logger.Info("aixle-runner starting", "mode", "host", "version", version.Version,
		"platform", creds.URL, "environment", creds.Environment.Key)
	source := tokens.NewSource(store, client, creds)
	// The callback proxy's relay (PROTOCOL.md §5.6): the sessions' sidecars, or
	// with `network: host` the agents themselves, reach the platform through it,
	// with this machine's credential. It serves the proxy route only.
	relay := &proxy.Relay{Gateway: client, Tokens: source, Logger: opts.Logger}
	proxies := proxy.NewHost(opts.StateDir, binary, relay, opts.Logger)
	defer proxies.Stop()
	// The host runner runs every op itself, the session ops included, through the
	// Docker API against the environment's session container (DESIGN.md §6.8).
	env := &docker.Environment{API: api, Key: creds.Environment.Key, StateDir: opts.StateDir, Logger: opts.Logger,
		Proxy: proxies, Background: ctx}
	if err := env.Resume(ctx); err != nil {
		opts.Logger.Warn("serving the running sessions' callback proxies again failed", "error", err)
	}
	handlers := map[string]host.Handler{}
	for name, handler := range env.Handlers() {
		handlers[name] = handler
	}
	loop := &host.Loop{
		Gateway:  client,
		Tokens:   source,
		Journal:  j,
		Handlers: handlers,
		Logger:   opts.Logger,
	}
	return loop.Run(ctx)
}

// ownBinary is the runner's own executable, symlinks resolved, as the Docker
// daemon resolves a bind mount's source.
func ownBinary(configured string) (string, error) {
	path := configured
	if path == "" {
		exe, err := os.Executable()
		if err != nil {
			return "", fmt.Errorf("finding aixle-runner's own executable: %w", err)
		}
		path = exe
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", fmt.Errorf("resolving aixle-runner's own executable %s: %w", path, err)
	}
	return resolved, nil
}
