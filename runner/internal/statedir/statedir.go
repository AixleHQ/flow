// Package statedir guards the runner's state directory, which holds the
// credentials and the journal (DESIGN.md §6.3, §6.7). Lock keeps two processes from
// using it at once, and CheckWritable tells, before a registration token is spent,
// whether the credentials could be stored there.
package statedir

import (
	"errors"
	"fmt"
	"os"
)

// ErrLocked means another process holds the state directory: a host runner, or a
// `configure` or `unregister` in progress.
var ErrLocked = errors.New("another aixle-runner process holds the state directory")

// Lock is an exclusive lock on a state directory, held until Release.
type Lock struct {
	f *os.File
}

// Acquire takes the exclusive lock of dir without waiting. It locks the directory
// itself, not a file in it: a lock file created by root in `configure` could not
// be opened later by the `aixle-runner` user. A missing directory is an error that
// matches fs.ErrNotExist, and a held lock is ErrLocked.
func Acquire(dir string) (*Lock, error) {
	f, err := os.Open(dir)
	if err != nil {
		return nil, fmt.Errorf("opening the state directory: %w", err)
	}
	if err := lock(f); err != nil {
		f.Close()
		return nil, err
	}
	return &Lock{f: f}, nil
}

// Release gives the lock up.
func (l *Lock) Release() error {
	return l.f.Close()
}

// CheckWritable creates dir if it is missing, then writes and removes a probe file
// in it.
func CheckWritable(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, ".probe-*")
	if err != nil {
		return err
	}
	name := f.Name()
	closeErr := f.Close()
	if err := os.Remove(name); err != nil {
		return err
	}
	return closeErr
}

// Mode is the state directory's mode. It keeps the credentials, the journal and
// the callback proxy's sockets to the runner's own user: the sockets are 0666
// below it, and only this directory stops another local user from reaching the
// relay, which adds the machine's credential (DESIGN.md §6.9.3).
const Mode os.FileMode = 0o700

// chmod is os.Chmod, replaced in tests.
var chmod = os.Chmod

// Restrict narrows dir to Mode when its mode is wider: when the group or others
// have any permission on it. A directory that is already owner-only is left as it
// is. When it cannot be narrowed, for example because the runner's user does not
// own it, the error names the directory and its mode.
func Restrict(dir string) error {
	info, err := os.Stat(dir)
	if err != nil {
		return fmt.Errorf("checking the mode of the state directory: %w", err)
	}
	mode := info.Mode().Perm()
	if mode&0o077 == 0 {
		return nil
	}
	if err := chmod(dir, Mode); err != nil {
		return fmt.Errorf("the state directory %s is mode %04o, and the runner could not narrow it to %04o: %w. "+
			"Make it owned by the runner's user and mode %04o (`sudo chmod %o %s`), then start the runner again",
			dir, mode, Mode, err, Mode, Mode, dir)
	}
	return nil
}
