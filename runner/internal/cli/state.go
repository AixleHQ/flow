package cli

import (
	"errors"
	"fmt"
	"io/fs"

	"github.com/aixlehq/aixle-runner/internal/credentials"
	"github.com/aixlehq/aixle-runner/internal/statedir"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

// ErrNeedsOperator marks a failure of the host runner that a restart cannot fix,
// such as missing or invalid credentials. cmd/aixle-runner exits with
// service.ExitStop for it, so systemd does not restart the unit in a loop.
var ErrNeedsOperator = errors.New("an operator must act")

type operatorError struct{ err error }

func (e operatorError) Error() string        { return e.err.Error() }
func (e operatorError) Unwrap() error        { return e.err }
func (e operatorError) Is(target error) bool { return target == ErrNeedsOperator }

// NeedsOperator says whether err stops the runner until an operator acts: a
// refusal of the platform (a *tokens.StopError) or an ErrNeedsOperator.
func NeedsOperator(err error) bool {
	if _, ok := tokens.AsStop(err); ok {
		return true
	}
	return errors.Is(err, ErrNeedsOperator)
}

// lockForCommand takes the state directory's lock for `configure` or `unregister`,
// which refuse while a host runner holds it.
func lockForCommand(stateDir, command string) (*statedir.Lock, error) {
	l, err := statedir.Acquire(stateDir)
	switch {
	case err == nil:
		return l, nil
	case errors.Is(err, statedir.ErrLocked):
		return nil, fmt.Errorf("a host runner is running on %s, so `aixle-runner %s` cannot change its state: stop it first with `sudo aixle-runner service stop`", stateDir, command)
	case errors.Is(err, fs.ErrNotExist):
		return nil, credentials.ErrNotConfigured
	}
	return nil, fmt.Errorf("%s: %w", stateDir, err)
}

// lockForHost takes the state directory's lock for the lifetime of a host runner,
// so that two host runners never run the same op.
func lockForHost(stateDir string) (*statedir.Lock, error) {
	l, err := statedir.Acquire(stateDir)
	switch {
	case err == nil:
		return l, nil
	case errors.Is(err, statedir.ErrLocked):
		return nil, fmt.Errorf("another aixle-runner is using %s: only one host runner can run on a machine, and the service may be running already (see `systemctl status aixle-runner`)", stateDir)
	case errors.Is(err, fs.ErrNotExist):
		return nil, operatorError{credentials.ErrNotConfigured}
	}
	return nil, fmt.Errorf("%s: %w", stateDir, err)
}
