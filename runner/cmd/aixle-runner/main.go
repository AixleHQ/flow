// Command aixle-runner runs a customer's machine for the Aixle platform
// (docs/design/agent-runtimes/DESIGN.md §6, runner/protocol/PROTOCOL.md).
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/aixlehq/aixle-runner/internal/cli"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/host"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/service"
	"github.com/aixlehq/aixle-runner/internal/version"
)

const usage = `Usage:
  aixle-runner configure --url <platform> --token <registration token> --name <name> [--no-auto-update] [--state-dir <dir>]
  aixle-runner unregister [--state-dir <dir>]
  aixle-runner service install | uninstall | start | stop
  aixle-runner --mode host [--state-dir <dir>]
  aixle-runner version

service install copies this binary to /var/lib/aixle-runner/bin/aixle-runner,
owned by the service's own user, and the service runs that copy. The runner
updates that copy itself while the machine is idle, to the version the platform
recommends, unless configure was run with --no-auto-update. A runner with
AIXLE_RUNNER_NO_SELF_UPDATE=1 in its environment, as the published image sets,
never updates itself, and configure run with it registers as --no-auto-update.
`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	code := run(ctx, os.Args[1:], os.Stdout, os.Stderr)
	stop()
	os.Exit(code)
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}

	var err error
	switch args[0] {
	case "configure":
		err = configure(ctx, args[1:], stdout, stderr)
	case "unregister":
		err = unregister(ctx, args[1:], stdout, stderr)
	case "service":
		err = serviceCommand(ctx, args[1:], stderr)
	case "version", "--version":
		if len(args) > 1 {
			fmt.Fprint(stderr, usage)
			return 2
		}
		fmt.Fprintln(stdout, version.Version)
		return 0
	case "-h", "--help", "help":
		fmt.Fprint(stdout, usage)
		return 0
	default:
		err = hostMode(ctx, args, stderr)
	}

	switch {
	case err == nil:
		return 0
	case errors.Is(err, errUsage):
		fmt.Fprint(stderr, usage)
		return 2
	case errors.Is(err, host.ErrUpdated):
		// The new binary is in place: systemd starts it (Restart=always).
		fmt.Fprintln(stderr, "aixle-runner:", err)
		return service.ExitUpdated
	}
	fmt.Fprintln(stderr, "aixle-runner:", err)
	if cli.NeedsOperator(err) {
		return service.ExitStop
	}
	return 1
}

var errUsage = errors.New("usage")

func newFlags(name string, stderr io.Writer) (*flag.FlagSet, *string) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(stderr)
	stateDir := fs.String("state-dir", cli.DefaultStateDir, "the directory of the credentials and the journal")
	return fs, stateDir
}

func parse(fs *flag.FlagSet, args []string) error {
	if err := fs.Parse(args); err != nil {
		return errUsage
	}
	if fs.NArg() > 0 {
		return errUsage
	}
	return nil
}

func configure(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	fs, stateDir := newFlags("configure", stderr)
	url := fs.String("url", "", "the platform's address, e.g. https://flow.aixle.com")
	token := fs.String("token", "", "the registration token from \"Add machine\" on the runner page")
	name := fs.String("name", "", "how the machine is listed on the runner page")
	noAutoUpdate := fs.Bool("no-auto-update", false, "never update aixle-runner on this machine; its operator updates it")
	if err := parse(fs, args); err != nil {
		return err
	}
	api, err := docker.Connect()
	if err != nil {
		return fmt.Errorf("connecting to the Docker daemon: %w", err)
	}
	defer api.Close()
	return cli.Configure(ctx, cli.ConfigureOptions{
		URL: *url, Token: *token, Name: *name, StateDir: *stateDir, NoAutoUpdate: *noAutoUpdate,
		NoSelfUpdate: cli.SelfUpdateOff(os.Getenv(cli.NoSelfUpdateEnv)),
		Preflight:    preflight.Env{Docker: api},
		Out:          stdout,
	})
}

func unregister(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	fs, stateDir := newFlags("unregister", stderr)
	if err := parse(fs, args); err != nil {
		return err
	}
	return cli.Unregister(ctx, cli.UnregisterOptions{StateDir: *stateDir, Out: stdout})
}

func serviceCommand(ctx context.Context, args []string, stderr io.Writer) error {
	if len(args) == 0 {
		return errUsage
	}
	// The service always uses cli.DefaultStateDir: `install` hands that directory to
	// the service user, so it takes no other path.
	fs := flag.NewFlagSet("service "+args[0], flag.ContinueOnError)
	fs.SetOutput(stderr)
	if err := parse(fs, args[1:]); err != nil {
		return err
	}
	// install copies the running binary (/proc/self/exe) to service.BinaryPath,
	// in the service user's own directory, which the unit runs.
	m := service.NewManager(cli.DefaultStateDir)
	switch args[0] {
	case "install":
		return m.Install(ctx)
	case "uninstall":
		return m.Uninstall(ctx)
	case "start":
		return m.Start(ctx)
	case "stop":
		return m.Stop(ctx)
	}
	return errUsage
}

func hostMode(ctx context.Context, args []string, stderr io.Writer) error {
	fs, stateDir := newFlags("aixle-runner", stderr)
	mode := fs.String("mode", "", "the runner's mode: host")
	if err := parse(fs, args); err != nil {
		return err
	}
	if *mode != "host" {
		return errUsage
	}
	logger := slog.New(slog.NewTextHandler(stderr, nil))
	return cli.RunHost(ctx, cli.HostOptions{StateDir: *stateDir, Logger: logger,
		NoSelfUpdate: cli.SelfUpdateOff(os.Getenv(cli.NoSelfUpdateEnv))})
}
