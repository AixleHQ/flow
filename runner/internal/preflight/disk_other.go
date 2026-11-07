//go:build !linux

package preflight

import "errors"

// The runner runs on Linux only; this lets the packages build elsewhere, where the
// preflight refuses the machine anyway.
func freeBytes(string) (uint64, error) {
	return 0, errors.New("free space is only measured on Linux")
}
