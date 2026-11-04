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
	"strings"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/preflight"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/service"
	"github.com/aixlehq/aixle-runner/internal/statedir"
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
	// LookupUser and Geteuid are replaced in tests. nil means user.Lookup and
	// os.Geteuid.
	LookupUser func(name string) (*user.User, error)
	Geteuid    func() int
}

// Configure runs the preflight, registers the machine and stores its credentials.
// A failed preflight registers nothing, and neither does a state directory that
// cannot be written or is held by a running host runner.
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
	// Everything that could keep the credentials from being stored is checked before
	// the token is spent: the token registers one machine only.
	if _, err := store.Exists(); err != nil {
		return fmt.Errorf("configure cannot tell whether this machine is registered already, so it registered nothing: run configure as root (sudo): %w", err)
	}
	if err := statedir.CheckWritable(opts.StateDir); err != nil {
		return fmt.Errorf("configure cannot write the state directory %s (%v), so it registered nothing and the registration token is not spent: run configure as root (sudo)", opts.StateDir, err)
	}
	owner, err := serviceOwner(opts)
	if err != nil {
		return fmt.Errorf("configure cannot tell who must own the credentials, so it registered nothing and the registration token is not spent: %w", err)
	}
	lock, err := lockForCommand(opts.StateDir, "configure")
	if err != nil {
		return err
	}
	defer lock.Release()
	// Asked again under the lock, which a running host runner would have held.
	exists, err := store.Exists()
	if err != nil {
		return fmt.Errorf("configure cannot tell whether this machine is registered already, so it registered nothing: %w", err)
	}
	if exists {
		return fmt.Errorf("this machine is registered already (%s exists): run `aixle-runner unregister` first to register it again", store.Path())
	}

	fmt.Fprintln(opts.Out, "Checking this machine...")
	report, err := preflight.Run(ctx, opts.Preflight)
	if err != nil {
		return fmt.Errorf("the machine did not pass the preflight, so it was not registered:\n  - %s",
			strings.ReplaceAll(err.Error(), "\n", "\n  - "))
	}

	// A journal without credentials belongs to an environment that is gone, for
	// example after `credential_reuse_detected`. Its `after` would hide the new
	// environment's first ops.
	if err := journal.Delete(opts.StateDir); err != nil {
		return fmt.Errorf("deleting the journal of the previous registration: %w", err)
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
	if err := handTo(owner, opts.StateDir); err != nil {
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

// serviceOwner is the `aixle-runner` user when configure runs as root after
// `service install` created it: the service must read and rotate the credentials.
// It is nil otherwise; before `service install`, install hands them over. Only a
// user that does not exist is not an error.
func serviceOwner(opts ConfigureOptions) (*service.Account, error) {
	geteuid, lookup := opts.Geteuid, opts.LookupUser
	if geteuid == nil {
		geteuid = os.Geteuid
	}
	if lookup == nil {
		lookup = user.Lookup
	}
	if geteuid() != 0 {
		return nil, nil
	}
	acct, ok, err := service.LookupAccount(lookup)
	if err != nil || !ok {
		return nil, err
	}
	return &acct, nil
}

// handTo gives the state directory and the credentials to owner, if any.
func handTo(owner *service.Account, stateDir string) error {
	if owner == nil {
		return nil
	}
	for _, p := range []string{stateDir, credentials.NewStore(stateDir).Path()} {
		if err := os.Lchown(p, owner.UID, owner.GID); err != nil {
			return fmt.Errorf("handing %s to %s: %w", p, service.User, err)
		}
	}
	return nil
}
