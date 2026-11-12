package cli

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
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
	// Binary is the runner's own executable, symlinks resolved. It has two uses:
	// it is the file a self-update replaces, and the one the callback proxy's
	// sidecar runs, bind-mounted read-only (PROTOCOL.md §5.8). Empty is the
	// running binary (update.BinaryPath).
	Binary string
	// NoSelfUpdate turns self-update off whatever the credentials say: the
	// published image sets NoSelfUpdateEnv, since in a container the image tag is
	// the version (DESIGN.md §14.4).
	NoSelfUpdate bool
}

// NoSelfUpdateEnv, set to a true value (`1`, `true`), turns self-update off for
// the host runner, and makes configure register the machine as
// `--no-auto-update`. docker/runner/Dockerfile sets it.
const NoSelfUpdateEnv = "AIXLE_RUNNER_NO_SELF_UPDATE"

// SelfUpdateOff reads NoSelfUpdateEnv's value. Empty, or a value that is not a
// boolean, leaves self-update to the credentials.
func SelfUpdateOff(value string) bool {
	off, err := strconv.ParseBool(strings.TrimSpace(value))
	return err == nil && off
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
	// The relay's sockets below the state directory are 0666: only the
	// directory's 0700 keeps other local users from the relay (§6.9.3). A
	// directory the runner cannot narrow needs an operator, not a restart.
	if err := restrictStateDir(opts.StateDir); err != nil {
		return operatorError{err}
	}

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

	// One path for the updater and the proxy sidecars. An update runs only while
	// the machine holds no session (Busy), and a sidecar exists only with its
	// session; the update renames the new file into place, so a sidecar that
	// still runs keeps the old inode and the next one mounts the new file.
	binary := opts.Binary
	if binary == "" {
		if binary, err = update.BinaryPath(); err != nil {
			return fmt.Errorf("finding the running binary: %w", err)
		}
	}

	// One value for the start line and the updater, so the line reports what the
	// updater does.
	selfUpdate := creds.AutoUpdateEnabled() && !opts.NoSelfUpdate
	opts.Logger.Info("aixle-runner starting", "mode", "host", "version", version.Version,
		"platform", creds.URL, "environment", creds.Environment.Key, "auto_update", selfUpdate)
	source := tokens.NewSource(store, client, creds)
	// The callback proxy's relay (PROTOCOL.md §5.8): the sessions' sidecars, or
	// with `network: host` the agents themselves, reach the platform through it,
	// with this machine's credential. It serves the proxy route only.
	relay := &proxy.Relay{Gateway: client, Tokens: source, Logger: opts.Logger}
	proxies := proxy.NewHost(opts.StateDir, binary, relay, opts.Logger)
	defer proxies.Stop()
	// The host runner runs every op itself, the session ops included, through the
	// Docker API against the environment's session container (DESIGN.md §6.8).
	env := &docker.Environment{API: api, Key: creds.Environment.Key, StateDir: opts.StateDir, Logger: opts.Logger,
		Proxy: proxies, Background: ctx}
	// A Resume that cannot list the environment's containers has served no
	// running session's proxy again, and nothing would call it later. So the
	// host runner does not poll: it exits with a plain failure, not
	// service.ExitStop, and the service manager starts it again
	// (Restart=always, RestartSec=5), which retries Resume until Docker answers.
	if err := env.Resume(ctx); err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return fmt.Errorf("serving the running sessions' callback proxies again failed; exiting so that the service manager restarts the runner and it tries again: %w", err)
	}
	handlers := map[string]host.Handler{}
	for name, handler := range env.Handlers() {
		handlers[name] = handler
	}
	updater := &update.Updater{
		Releases: client,
		Current:  version.Version,
		Binary:   binary,
		Disabled: !selfUpdate,
		Busy:     env.HoldsSession,
		Logger:   opts.Logger,
	}

	// The check-in after every start (PROTOCOL.md §5.9): the platform records the
	// version this binary is, which a machine that updated itself has moved on
	// from the one it registered with, and the machine's facts as they are now.
	// Its answer may offer an update, taken under the rule of an empty poll.
	checker := &host.Checker{Gateway: client, Tokens: source, Logger: opts.Logger}
	answer, _, err := checker.CheckIn(ctx, checkInReport(ctx, api, opts.Logger))
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	if answer.Update != nil && updater.Apply(ctx, *answer.Update) {
		return host.ErrUpdated
	}

	loop := &host.Loop{
		Gateway:  client,
		Tokens:   source,
		Journal:  j,
		Handlers: handlers,
		Updater:  updater,
		Logger:   opts.Logger,
	}
	return loop.Run(ctx)
}

// preflightTimeout bounds the preflight of a check-in: the daemon is asked twice.
const preflightTimeout = 30 * time.Second

// checkInReport is what a check-in reports: the preflight's os, arch and facts
// (the same as `configure` reports at registration). A machine that no longer
// passes the preflight still checks in, with the failure in its facts under
// `preflight_error`, so that the platform shows a machine that cannot run the
// agent (DESIGN.md §6.8) instead of hearing nothing from it.
func checkInReport(ctx context.Context, api docker.API, logger *slog.Logger) protocol.CheckInRequest {
	ctx, cancel := context.WithTimeout(ctx, preflightTimeout)
	defer cancel()
	report, err := preflight.Run(ctx, preflight.Env{Docker: api})
	facts := report.Facts()
	if err != nil {
		logger.Warn("this machine no longer passes the preflight; checking in anyway", "error", err)
		facts["preflight_error"] = err.Error()
	}
	return protocol.CheckInRequest{OS: report.OS, Arch: report.Arch, Facts: facts}
}
