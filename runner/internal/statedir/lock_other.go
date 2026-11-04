//go:build !unix

package statedir

import (
	"errors"
	"os"
)

func lock(*os.File) error {
	return errors.New("locking the state directory is supported on Linux only")
}
