package cli

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// UnregisterOptions are the inputs of `aixle-runner unregister`.
type UnregisterOptions struct {
	StateDir   string
	HTTPClient *http.Client
	Out        io.Writer
}

// Unregister removes the machine from its runner (DELETE /registration) and then
// deletes the local credentials and journal. It refuses while a machine runner runs.
func Unregister(ctx context.Context, opts UnregisterOptions) error {
	lock, err := lockForCommand(opts.StateDir, "unregister")
	if err != nil {
		return err
	}
	defer lock.Release()
	err = unregisterLocked(ctx, opts)
	var failed unregisterFailure
	if errors.As(err, &failed) {
		return fmt.Errorf("unregistering failed, and the credentials were kept so it can be tried again: %w", failed.err)
	}
	return err
}

// unregisterFailure is the platform not answering the unregister. The command
// and a stop each say what it means for them.
type unregisterFailure struct{ err error }

func (e unregisterFailure) Error() string { return "unregistering failed: " + e.err.Error() }
func (e unregisterFailure) Unwrap() error { return e.err }

// unregisterLocked is Unregister for a caller that holds the state directory's
// lock: the machine runner, which unregisters itself when it stops.
func unregisterLocked(ctx context.Context, opts UnregisterOptions) error {
	store := credentials.NewStore(opts.StateDir)
	creds, err := store.Load()
	if err != nil {
		return err
	}
	client, err := protocol.NewClient(creds.URL, version.Version, opts.HTTPClient)
	if err != nil {
		return err
	}
	source := tokens.NewSource(store, client, creds)

	err = source.Do(ctx, func(access string) error { return client.Unregister(ctx, access) })
	if stop, ok := tokens.AsStop(err); ok && stop.Action != protocol.ActionUpdate {
		// The platform does not accept these credentials any more, so the machine
		// is gone from it already. Only the local copy is left to remove.
		fmt.Fprintln(opts.Out, "The platform no longer knows this machine's credentials; removing the local copy.")
	} else if err != nil {
		return unregisterFailure{err}
	}

	if err := store.Delete(); err != nil {
		return err
	}
	if err := journal.Delete(opts.StateDir); err != nil {
		return fmt.Errorf("deleting the journal: %w", err)
	}
	fmt.Fprintln(opts.Out, "Unregistered this machine and deleted its credentials.")
	return nil
}
