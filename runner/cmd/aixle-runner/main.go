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
	"strconv"
	"strings"

	"github.com/aixlehq/aixle-runner/internal/cli"
	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/machine"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/proxy"
	"github.com/aixlehq/aixle-runner/internal/service"
	"github.com/aixlehq/aixle-runner/internal/version"
)

const usage = `Usage:
  aixle-runner configure --url <platform> --token <registration token> --name <name> [--no-auto-update] [--state-dir <dir>]
  aixle-runner unregister [--state-dir <dir>]
  aixle-runner service install | uninstall | start | stop
  aixle-runner --mode machine [--state-dir <dir>] [--unregister-on-stop]
  aixle-runner --mode proxy --socket <path> --listen <address> [--dial-socket <path> --dial-ports <p,p,…>]
  aixle-runner version

--mode proxy is the callback proxy's sidecar, which the machine runner starts next
to a session's agent container; it is not run by hand.

--mode machine registers the machine on its first start, when the state directory
has no credentials yet, from AIXLE_RUNNER_URL, AIXLE_RUNNER_TOKEN and
AIXLE_RUNNER_NAME (the machine's hostname if unset). Once it has credentials the
three are ignored. SIGINT, SIGTERM and SIGHUP stop it: it removes the sessions'
sidecars and containers, then unregisters the machine if --unregister-on-stop or
AIXLE_RUNNER_UNREGISTER_ON_STOP=1 is set (the flag wins), and exits.

service install copies this binary to /var/lib/aixle-runner/bin/aixle-runner,
owned by the service's own user, and the service runs that copy. The runner
updates that copy itself while the machine is idle, to the version the platform
recommends, unless configure was run with --no-auto-update. A runner with
AIXLE_RUNNER_NO_SELF_UPDATE=1 in its environment, as the published image sets,
never updates itself, and configure run with it registers as --no-auto-update.
`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), cli.StopSignals...)
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
		err = machineMode(ctx, args, stdout, stderr)
	}

	switch {
	case err == nil:
		return 0
	case errors.Is(err, errUsage):
		fmt.Fprint(stderr, usage)
		return 2
	case errors.Is(err, machine.ErrUpdated):
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

// runMachine is replaced in tests.
var runMachine = cli.RunMachine

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
	// The machine's volumes go with it. Connecting does not dial, so with the
	// daemon down the unregister works and cli logs the failed removal. A client
	// that cannot be built (a malformed DOCKER_HOST) is said here: the unregister
	// still runs, and the volumes stay on the host.
	opts := cli.UnregisterOptions{StateDir: *stateDir, Out: stdout}
	api, err := docker.Connect()
	if err != nil {
		fmt.Fprintf(stderr, "Could not connect to Docker, so the machine's volumes were not removed: %v\n", err)
	} else {
		defer api.Close()
		opts.Docker = api
	}
	return cli.Unregister(ctx, opts)
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

func machineMode(ctx context.Context, args []string, stdout, stderr io.Writer) error {
	fs, stateDir := newFlags("aixle-runner", stderr)
	mode := fs.String("mode", "", "the runner's mode: machine, or proxy for the callback proxy's sidecar")
	unregisterDefault, envErr := cli.BoolEnv(cli.UnregisterOnStopEnv, os.Getenv(cli.UnregisterOnStopEnv))
	unregisterOnStop := fs.Bool("unregister-on-stop", unregisterDefault, "machine mode: unregister the machine when the runner is stopped ("+cli.UnregisterOnStopEnv+"=1)")
	socket := fs.String("socket", "", "proxy mode: the machine runner's relay socket")
	listen := fs.String("listen", "", "proxy mode: the address the agent calls")
	dialSocket := fs.String("dial-socket", "", "proxy mode: the socket the machine runner dials the tunnel's ports through")
	dialPorts := fs.String("dial-ports", "", "proxy mode: the ports the dial socket may reach, comma separated")
	if err := parse(fs, args); err != nil {
		return err
	}
	logger := slog.New(slog.NewTextHandler(stderr, nil))
	switch *mode {
	case "machine":
		if *socket != "" || *listen != "" || *dialSocket != "" || *dialPorts != "" {
			return errUsage
		}
		inContainer, err := cli.BoolEnv(cli.InContainerEnv, os.Getenv(cli.InContainerEnv))
		if envErr != nil || err != nil {
			return errors.Join(envErr, err)
		}
		return runMachine(ctx, cli.MachineOptions{StateDir: *stateDir, Logger: logger,
			NoSelfUpdate: cli.SelfUpdateOff(os.Getenv(cli.NoSelfUpdateEnv)),
			TunnelURL:    os.Getenv(cli.TunnelURLEnv),
			URL:          os.Getenv(cli.RegisterURLEnv), Token: os.Getenv(cli.RegisterTokenEnv), Name: os.Getenv(cli.RegisterNameEnv),
			UnregisterOnStop: *unregisterOnStop, InContainer: inContainer, Out: stdout})
	case "proxy":
		if *socket == "" || *listen == "" {
			return errUsage
		}
		ports, err := parsePorts(*dialPorts)
		if err != nil || (*dialSocket == "") != (len(ports) == 0) {
			return errUsage
		}
		return proxy.RunSidecar(ctx, proxy.SidecarOptions{Socket: *socket, Listen: *listen, Logger: logger,
			DialSocket: *dialSocket, DialPorts: ports})
	}
	return errUsage
}

// parsePorts reads --dial-ports: ports from 1 to 65535, comma separated, or none.
func parsePorts(list string) ([]int, error) {
	if list == "" {
		return nil, nil
	}
	var ports []int
	for _, field := range strings.Split(list, ",") {
		port, err := strconv.Atoi(field)
		if err != nil || port < 1 || port > 65535 {
			return nil, fmt.Errorf("%q is not a port", field)
		}
		ports = append(ports, port)
	}
	return ports, nil
}
