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
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/service"
)

const usage = `Usage:
  aixle-runner configure --url <platform> --token <registration token> --name <name> [--state-dir <dir>]
  aixle-runner unregister [--state-dir <dir>]
  aixle-runner service install | uninstall | start | stop
  aixle-runner --mode host [--state-dir <dir>]
  aixle-runner --mode proxy --socket <path> --listen <address>

--mode proxy is the callback proxy's sidecar, which the host runner starts next
to a session's agent container; it is not run by hand.

service install copies this binary to /usr/local/bin/aixle-runner, owned by
root, and the service runs that copy.
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
	if err := parse(fs, args); err != nil {
		return err
	}
	api, err := docker.Connect()
	if err != nil {
		return fmt.Errorf("connecting to the Docker daemon: %w", err)
	}
	defer api.Close()
	return cli.Configure(ctx, cli.ConfigureOptions{
		URL: *url, Token: *token, Name: *name, StateDir: *stateDir,
		Preflight: preflight.Env{Docker: api},
		Out:       stdout,
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
	// which the unit runs.
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
	mode := fs.String("mode", "", "the runner's mode: host, or proxy for the callback proxy's sidecar")
	socket := fs.String("socket", "", "proxy mode: the host runner's relay socket")
	listen := fs.String("listen", "", "proxy mode: the address the agent calls")
	if err := parse(fs, args); err != nil {
		return err
	}
	logger := slog.New(slog.NewTextHandler(stderr, nil))
	switch *mode {
	case "host":
		if *socket != "" || *listen != "" {
			return errUsage
		}
		return cli.RunHost(ctx, cli.HostOptions{StateDir: *stateDir, Logger: logger})
	case "proxy":
		if *socket == "" || *listen == "" {
			return errUsage
		}
		return proxy.RunSidecar(ctx, proxy.SidecarOptions{Socket: *socket, Listen: *listen, Logger: logger})
	}
	return errUsage
}
