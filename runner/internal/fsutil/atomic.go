// Package fsutil holds the file helpers the state directory needs.
package fsutil

import (
	"fmt"
	"os"
	"path/filepath"
)

// WriteFileAtomic replaces path with data: it writes a temporary file in the same
// directory with mode perm, syncs it, renames it over path and syncs the directory.
// A reader sees either the old content or the new one.
func WriteFileAtomic(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("creating %s: %w", dir, err)
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*")
	if err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	tmpName := tmp.Name()
	committed := false
	defer func() {
		if !committed {
			_ = os.Remove(tmpName)
		}
	}()

	// CreateTemp makes the file 0600 already; Chmod covers a wider perm and a umask.
	if err := tmp.Chmod(perm); err != nil {
		tmp.Close()
		return fmt.Errorf("writing %s: %w", path, err)
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return fmt.Errorf("writing %s: %w", path, err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("writing %s: %w", path, err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	committed = true

	// The rename is durable only once the directory is synced.
	d, err := os.Open(dir)
	if err != nil {
		return fmt.Errorf("syncing %s: %w", dir, err)
	}
	if err := d.Sync(); err != nil {
		d.Close()
		return fmt.Errorf("syncing %s: %w", dir, err)
	}
	if err := d.Close(); err != nil {
		return fmt.Errorf("syncing %s: %w", dir, err)
	}
	return nil
}
