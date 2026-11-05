//go:build unix

package statedir

import (
	"errors"
	"fmt"
	"os"
	"syscall"
)

func lock(f *os.File) error {
	err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
	switch {
	case err == nil:
		return nil
	case errors.Is(err, syscall.EWOULDBLOCK):
		return ErrLocked
	}
	return fmt.Errorf("locking the state directory: %w", err)
}
