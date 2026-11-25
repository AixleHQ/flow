package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/machine"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/statedir"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
	"github.com/aixlehq/aixle-runner/internal/update"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// MachineOptions are the inputs of `aixle-runner --mode machine`.
type MachineOptions struct {
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
	// TunnelURL is TunnelURLEnv's value: where the tunnel connects instead of the
	// platform's own host. Empty, the usual case, is the platform's.
	TunnelURL string
	// Sleep waits between the tries of resuming the sessions while Docker is
	// down. Replaced in tests; nil waits for real.
	Sleep func(ctx context.Context, d time.Duration) error

	// URL, Token and Name register the machine on its first start
	// (RegisterURLEnv, RegisterTokenEnv, RegisterNameEnv): used only while the
	// state directory has no credentials, and ignored once it has them. Name is
	// the machine's hostname when empty.
	URL, Token, Name string
	// UnregisterOnStop makes a stop (SIGINT, SIGTERM, SIGHUP) unregister the
	// machine, after the sidecars and the session containers are removed.
	// It is explicit: nothing is inferred from how the runner is run.
	UnregisterOnStop bool
	// InContainer says the runner runs in a container (InContainerEnv, set by
	// the published image). The runner then inspects its own container, only to
	// learn where its state directory is on the machine.
	InContainer bool
	// Hostname is the container's hostname, with InContainer. Empty is os.Hostname.
	Hostname string
	// Out receives what registering reports. Nil discards it.
	Out io.Writer
}

// The environment of a machine runner that registers itself on its first start
// (docs/design/agent-runtimes/add-machine.md §3.1), and the settings the
// published image sets.
const (
	RegisterURLEnv   = "AIXLE_RUNNER_URL"
	RegisterTokenEnv = "AIXLE_RUNNER_TOKEN"
	RegisterNameEnv  = "AIXLE_RUNNER_NAME"
	// UnregisterOnStopEnv is `--unregister-on-stop`, `1` or `0`: the flag wins.
	UnregisterOnStopEnv = "AIXLE_RUNNER_UNREGISTER_ON_STOP"
	// InContainerEnv, `1`, says the runner runs in a container.
	InContainerEnv = "AIXLE_RUNNER_IN_CONTAINER"
)

// How a stop fits in `docker stop`'s 10 s before SIGKILL: the teardown and the
// unregister each have their own short deadline.
const (
	teardownTimeout   = 5 * time.Second
	unregisterTimeout = 3 * time.Second
)

// StopSignals stop a machine runner: SIGINT, SIGTERM, and SIGHUP, which closing
// the operator's terminal sends. The systemd service is stopped with SIGTERM.
var StopSignals = []os.Signal{syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP}

// BoolEnv reads a setting that is `1` or `0` (or another boolean). Empty is false.
func BoolEnv(name, value string) (bool, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return false, nil
	}
	on, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s must be 1 or 0, got %q", name, value)
	}
	return on, nil
}

// NoSelfUpdateEnv, set to a true value (`1`, `true`), turns self-update off for
// the machine runner, and makes configure register the machine as
// `--no-auto-update`. docker/runner/Dockerfile sets it.
const NoSelfUpdateEnv = "AIXLE_RUNNER_NO_SELF_UPDATE"

// SelfUpdateOff reads NoSelfUpdateEnv's value. Empty, or a value that is not a
// boolean, leaves self-update to the credentials.
func SelfUpdateOff(value string) bool {
	off, err := strconv.ParseBool(strings.TrimSpace(value))
	return err == nil && off
}

// RunMachine runs the machine runner until ctx is done. It holds the state directory's
// lock while it runs, and refuses at once if another process holds it. A failure
// that needs an operator, such as a refusal or missing credentials, satisfies
// NeedsOperator. A self-update that replaced the binary returns machine.ErrUpdated.
func RunMachine(ctx context.Context, opts MachineOptions) error {
	registering := opts.URL != "" && opts.Token != ""
	if registering {
		// A fresh state directory, as `configure` makes it. With credentials in it
		// already nothing changes.
		if err := os.MkdirAll(opts.StateDir, 0o700); err != nil {
			return fmt.Errorf("creating the state directory %s: %w", opts.StateDir, err)
		}
	}
	lock, err := lockForMachine(opts.StateDir)
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

	api := opts.Docker
	if api == nil {
		c, err := docker.Connect()
		if err != nil {
			return fmt.Errorf("connecting to the Docker daemon: %w", err)
		}
		defer c.Close()
		api = c
	}
	// Where the state directory is on the machine, before the token is spent: a
	// runner that cannot mount its sidecar's directories must not register.
	location, err := locateState(ctx, api, opts)
	if err != nil {
		return operatorError{err}
	}

	store := credentials.NewStore(opts.StateDir)
	creds, err := store.Load()
	if errors.Is(err, credentials.ErrNotConfigured) && registering {
		// The first start: register as `configure` does. With credentials the three
		// variables are ignored, so a restart never needs the token.
		if err := registerOnFirstStart(ctx, api, opts); err != nil {
			return err
		}
		creds, err = store.Load()
	}
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

	// The sidecar runs a copy of this binary from the state directory, which it
	// mounts (add-machine.md §3.2): on a bare machine and in a container alike.
	sidecarBinary, err := statedir.InstallBinary(opts.StateDir, binary)
	if err != nil {
		return err
	}

	// One value for the start line and the updater, so the line reports what the
	// updater does.
	selfUpdate := creds.AutoUpdateEnabled() && !opts.NoSelfUpdate
	opts.Logger.Info("aixle-runner starting", "mode", "machine", "version", version.Version,
		"platform", creds.URL, "environment", creds.Environment.Key, "auto_update", selfUpdate)
	source := tokens.NewSource(store, client, creds)
	// The callback proxy's relay (PROTOCOL.md §5.8): the sessions' sidecars, or
	// with `network: host` the agents themselves, reach the platform through it,
	// with this machine's credential. It serves the proxy route only.
	relay := &proxy.Relay{Gateway: client, Tokens: source, Logger: opts.Logger}
	proxies := proxy.NewHost(opts.StateDir, sidecarBinary, relay, opts.Logger)
	defer proxies.Stop()
	// The machine runner runs every op itself, the session ops included, through the
	// Docker API against the environment's session container (DESIGN.md §6.8).
	env := &docker.Environment{API: api, Key: creds.Environment.Key, StateDir: opts.StateDir, State: location, Logger: opts.Logger,
		Proxy: proxies, Background: ctx}
	// A stop signal tears the machine down: the sidecars and the session
	// containers go, and the machine unregisters if the setting is on. Only a stop
	// does it: an update, or a failure the service manager restarts, leaves the
	// sessions running as before.
	defer func() {
		if ctx.Err() != nil {
			stopMachine(ctx, env, opts)
		}
	}()
	handlers := map[string]machine.Handler{}
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
	// It comes before the sessions' proxies are served again, so that a machine
	// whose Docker is down still reports it (DESIGN.md §8, "Prerequisites
	// missing") instead of exiting unheard.
	checker := &machine.Checker{Gateway: client, Tokens: source, Logger: opts.Logger}
	answer, _, err := checker.CheckIn(ctx, checkInReport(ctx, api, opts.StateDir, opts.Logger))
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	if answer.Update != nil && updater.Apply(ctx, *answer.Update) {
		return machine.ErrUpdated
	}

	// The interactive tunnel (PROTOCOL.md §8): the platform turns it on in the check-in's
	// config, and the runner then connects to the relay while the machine holds a session.
	// What it serves is what this runner's own `container.start` set up, so the environment
	// gets the table before any session's container is started or resumed.
	var manager tunnelRunner
	serving := &tunnel.Serving{}
	if m := tunnelManager(answer, client, source, env, serving, opts.TunnelURL, opts.Logger); m != nil {
		manager = m
		env.Tunnel = serving
	}

	// A Resume that cannot list the environment's containers has served no
	// running session's proxy again, and nothing would call it later, so the
	// machine runner does not poll until it has. It waits for Docker with a
	// backoff instead of exiting: an exit makes the service manager restart it
	// every few seconds (Restart=always, RestartSec=5), a loop that tells the
	// operator nothing. Once Docker answers it reports the machine again, so
	// that the platform has the facts of a machine that works, and Return to
	// service (DESIGN.md §5.2) reaches a runner that polls.
	waited, err := resumeWhenDockerAnswers(ctx, env, opts.Logger, opts.Sleep)
	if err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	if waited {
		answer, _, err = checker.CheckIn(ctx, checkInReport(ctx, api, opts.StateDir, opts.Logger))
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		if answer.Update != nil && updater.Apply(ctx, *answer.Update) {
			return machine.ErrUpdated
		}
	}

	loop := &machine.Loop{
		Gateway:  client,
		Tokens:   source,
		Journal:  j,
		Handlers: handlers,
		Updater:  updater,
		Logger:   opts.Logger,
	}
	return runWithTunnel(ctx, loop.Run, manager, opts.Logger)
}

// resumeBackoffMax bounds the wait between two tries of resuming the sessions'
// proxies while the Docker daemon is down: a daemon the operator starts is found
// again within this time.
const resumeBackoffMax = 30 * time.Second

// resumeWhenDockerAnswers serves the running sessions' callback proxies again
// (docker.Environment.Resume), trying again with a backoff for as long as the
// Docker daemon cannot be reached. The boolean says whether it had to wait.
// It returns only when Resume succeeded, or with ctx's error.
func resumeWhenDockerAnswers(ctx context.Context, env *docker.Environment, logger *slog.Logger, sleep func(context.Context, time.Duration) error) (bool, error) {
	if sleep == nil {
		sleep = backoff.Sleep
	}
	retry := backoff.New(time.Second, resumeBackoffMax)
	waited := false
	for {
		err := env.Resume(ctx)
		if err == nil {
			return waited, nil
		}
		if ctx.Err() != nil {
			return waited, ctx.Err()
		}
		waited = true
		delay := retry.Next()
		logger.Warn("serving the running sessions' callback proxies again failed; waiting for Docker and trying again", "error", err, "retry_in", delay.Round(time.Millisecond))
		if err := sleep(ctx, delay); err != nil {
			return waited, err
		}
	}
}

// preflightTimeout bounds the preflight of a check-in: the daemon is asked twice.
const preflightTimeout = 30 * time.Second

// checkInReport is what a check-in reports: the preflight's os, arch and facts
// (the same as `configure` reports at registration). A machine that no longer
// passes the preflight still checks in, with the failure in its facts under
// `preflight_error`, so that the platform shows a machine that cannot run the
// agent (DESIGN.md §6.8) instead of hearing nothing from it.
func checkInReport(ctx context.Context, api docker.API, stateDir string, logger *slog.Logger) protocol.CheckInRequest {
	ctx, cancel := context.WithTimeout(ctx, preflightTimeout)
	defer cancel()
	report, err := preflight.Run(ctx, preflight.Env{Docker: api, StateDir: stateDir})
	for _, note := range report.Notes {
		// The free space is for information only: nothing relies on it.
		logger.Info(note)
	}
	facts := report.Facts()
	if err != nil {
		logger.Warn("this machine no longer passes the preflight; checking in anyway", "error", err)
		facts["preflight_error"] = err.Error()
	}
	return protocol.CheckInRequest{OS: report.OS, Arch: report.Arch, Facts: facts}
}

// locateState says where the state directory is on the machine. A runner on the
// machine itself needs no inspection. A runner in a container finds its own
// container and reads only where its directory lives; a volume needs Docker 26.
func locateState(ctx context.Context, api docker.API, opts MachineOptions) (docker.StateLocation, error) {
	if !opts.InContainer {
		return docker.OnMachine(opts.StateDir), nil
	}
	hostname := opts.Hostname
	if hostname == "" {
		var err error
		if hostname, err = os.Hostname(); err != nil {
			return docker.StateLocation{}, fmt.Errorf("reading the hostname: %w", err)
		}
	}
	location, err := docker.LocateState(ctx, api, opts.StateDir, hostname)
	if err != nil {
		return docker.StateLocation{}, err
	}
	if location.Kind == docker.StateVolume {
		if err := preflight.RequireSubpath(ctx, api); err != nil {
			return docker.StateLocation{}, err
		}
	}
	return location, nil
}

// registerOnFirstStart registers the machine from the three environment
// variables, with the code of `configure`. The token is single use: it is spent
// here, and a start with credentials never reads it.
func registerOnFirstStart(ctx context.Context, api docker.API, opts MachineOptions) error {
	name := opts.Name
	if strings.TrimSpace(name) == "" {
		if hostname, err := os.Hostname(); err == nil {
			name = hostname
		}
	}
	out := opts.Out
	if out == nil {
		out = io.Discard
	}
	return Configure(ctx, ConfigureOptions{
		URL: opts.URL, Token: opts.Token, Name: name, StateDir: opts.StateDir,
		NoSelfUpdate: opts.NoSelfUpdate,
		Preflight:    preflight.Env{Docker: api},
		HTTPClient:   opts.HTTPClient,
		Out:          out,
		lockHeld:     true,
	})
}

// stopMachine is a machine runner's stop (SIGINT, SIGTERM, SIGHUP): the sidecars
// are torn down and the session containers removed, then the machine
// unregisters if the setting is on. Each step has its own deadline, so that all
// of it fits in `docker stop`'s 10 s. A step that fails is logged and the
// next one runs.
func stopMachine(ctx context.Context, env *docker.Environment, opts MachineOptions) {
	// ctx is done: the steps run on their own deadlines.
	base := context.WithoutCancel(ctx)
	teardown, cancel := context.WithTimeout(base, teardownTimeout)
	if err := env.Shutdown(teardown); err != nil {
		opts.Logger.Warn("removing the sidecars and the session containers failed", "error", err)
	}
	cancel()
	if !opts.UnregisterOnStop {
		return
	}
	out := opts.Out
	if out == nil {
		out = io.Discard
	}
	unregister, cancel := context.WithTimeout(base, unregisterTimeout)
	defer cancel()
	if err := unregisterLocked(unregister, UnregisterOptions{StateDir: opts.StateDir, HTTPClient: opts.HTTPClient, Out: out}); err != nil {
		opts.Logger.Warn("unregistering this machine on stop failed", "error", err)
	}
}
