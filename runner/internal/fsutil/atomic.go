// Package fsutil holds the file helpers the state directory and the service need.
package fsutil

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// WriteFileAtomic replaces path with data: it writes a temporary file in the same
// directory with mode perm, syncs it, renames it over path and syncs the directory.
// A reader sees either the old content or the new one. A missing directory is
// created with mode 0700.
func WriteFileAtomic(path string, data []byte, perm os.FileMode) error {
	return writeAtomic(path, perm, 0o700, func(f *os.File) error {
		_, err := f.Write(data)
		return err
	}, nil)
}

// CopyFileAtomic replaces dst with a copy of src, as WriteFileAtomic does. Before
// the rename it calls own, when given, with the temporary file's name, so the
// copy has its final owner the moment it appears at dst. A missing directory is
// created with mode 0755.
func CopyFileAtomic(src, dst string, perm os.FileMode, own func(name string) error) error {
	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("reading %s: %w", src, err)
	}
	defer in.Close()
	return writeAtomic(dst, perm, 0o755, func(f *os.File) error {
		_, err := io.Copy(f, in)
		return err
	}, own)
}

func writeAtomic(path string, perm, dirPerm os.FileMode, fill func(*os.File) error, own func(string) error) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, dirPerm); err != nil {
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
	if err := fill(tmp); err != nil {
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
	if own != nil {
		if err := own(tmpName); err != nil {
			return fmt.Errorf("writing %s: %w", path, err)
		}
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
