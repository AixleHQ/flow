package statedir

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
)

func TestASecondHolderCannotTakeTheLock(t *testing.T) {
	dir := t.TempDir()
	first, err := Acquire(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Acquire(dir); !errors.Is(err, ErrLocked) {
		t.Fatalf("the second holder got %v", err)
	}
	if err := first.Release(); err != nil {
		t.Fatal(err)
	}
	again, err := Acquire(dir)
	if err != nil {
		t.Fatalf("after the release: %v", err)
	}
	_ = again.Release()
}

func TestLockingAMissingDirectory(t *testing.T) {
	if _, err := Acquire(filepath.Join(t.TempDir(), "missing")); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("got %v", err)
	}
}

func TestCheckWritableCreatesTheDirectoryAndLeavesNothing(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "state")
	if err := CheckWritable(dir); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 0 {
		t.Fatalf("entries %v, %v", entries, err)
	}
	info, _ := os.Stat(dir)
	if info.Mode().Perm() != 0o700 {
		t.Fatalf("mode %v", info.Mode().Perm())
	}
}

func TestCheckWritableRefusesADirectoryItCannotWrite(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root writes any directory")
	}
	dir := t.TempDir()
	if err := os.Chmod(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	if err := CheckWritable(dir); !errors.Is(err, fs.ErrPermission) {
		t.Fatalf("got %v", err)
	}
}
