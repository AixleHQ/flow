// Package cli implements the aixle-runner commands. cmd/aixle-runner parses the
// command line and calls them.
package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/user"
	"strconv"
	"strings"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/service"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// DefaultStateDir holds the credentials and the journal (DESIGN.md §6.3).
const DefaultStateDir = "/var/lib/aixle-runner"

// ConfigureOptions are the inputs of `aixle-runner configure`.
type ConfigureOptions struct {
	URL      string
	Token    string
	Name     string
	StateDir string
	// Preflight is the machine the preflight inspects.
	Preflight  preflight.Env
	HTTPClient *http.Client
	Out        io.Writer
}

// Configure runs the preflight, registers the machine and stores its credentials.
// A failed preflight registers nothing.
func Configure(ctx context.Context, opts ConfigureOptions) error {
	name := strings.TrimSpace(opts.Name)
	switch {
	case opts.URL == "":
		return errors.New("--url is required: the platform's address, e.g. https://flow.aixle.com")
	case opts.Token == "":
		return errors.New("--token is required: the registration token from \"Add machine\" on the runner page")
	case name == "":
		return errors.New("--name is required: how the machine is listed on the runner page")
	}
	client, err := protocol.NewClient(opts.URL, version.Version, opts.HTTPClient)
	if err != nil {
		return err
	}
	store := credentials.NewStore(opts.StateDir)
	if store.Exists() {
		return fmt.Errorf("this machine is registered already (%s exists): run `aixle-runner unregister` first to register it again", store.Path())
	}

	fmt.Fprintln(opts.Out, "Checking this machine...")
	report, err := preflight.Run(ctx, opts.Preflight)
	if err != nil {
		return fmt.Errorf("the machine did not pass the preflight, so it was not registered:\n  - %s",
			strings.ReplaceAll(err.Error(), "\n", "\n  - "))
	}

	reg, err := client.Register(ctx, opts.Token, protocol.RegisterRequest{
		Name:  name,
		OS:    report.OS,
		Arch:  report.Arch,
		Facts: report.Facts(),
	})
	if err != nil {
		return registerError(err)
	}

	creds := credentials.Credentials{URL: opts.URL, Environment: reg.Environment, TokenPair: reg.TokenPair}
	if err := store.Save(creds); err != nil {
		return fmt.Errorf("the machine was registered, but its credentials could not be stored, so this machine cannot use them: unregister it on the runner page and run configure again with a new token: %w", err)
	}
	if err := handToServiceUser(opts.StateDir); err != nil {
		return err
	}
	fmt.Fprintf(opts.Out, "Registered this machine as %q. Its credentials are in %s.\n", reg.Environment.DisplayName, store.Path())
	return nil
}

func registerError(err error) error {
	r, _ := protocol.AsRefusal(err)
	switch protocol.Classify(err) {
	case protocol.ActionNewRegistrationToken:
		return errors.New("the registration token is unknown, used or expired (a token is valid for one hour and registers one machine): get a new one with \"Add machine\" on the runner page")
	case protocol.ActionFixConfiguration:
		return fmt.Errorf("the platform refused the registration: %s (%s). The registration token was not spent: fix the input and run configure again with the same token", r.Message, r.Code)
	case protocol.ActionUpdate:
		return fmt.Errorf("the platform does not accept this version of aixle-runner (%s): update aixle-runner, then run configure again", version.Version)
	case protocol.ActionRevoked:
		return errors.New("the runner this token belongs to was revoked or deleted: use a registration token of a live runner")
	case protocol.ActionBackoff:
		return fmt.Errorf("registering failed: %v. The registration token is spent only by a registration that succeeds: try again later with the same token", err)
	}
	return fmt.Errorf("registering failed, which is a bug in aixle-runner: %w", err)
}

// handToServiceUser gives the state directory to the `aixle-runner` user when
// configure runs as root after `service install` created it, so the service can
// read and rotate the credentials. Before that, `service install` does it.
func handToServiceUser(stateDir string) error {
	if os.Geteuid() != 0 {
		return nil
	}
	u, err := user.Lookup(service.User)
	if err != nil {
		return nil
	}
	uid, _ := strconv.Atoi(u.Uid)
	gid, _ := strconv.Atoi(u.Gid)
	for _, p := range []string{stateDir, credentials.NewStore(stateDir).Path()} {
		if err := os.Lchown(p, uid, gid); err != nil {
			return fmt.Errorf("handing %s to %s: %w", p, service.User, err)
		}
	}
	return nil
}
