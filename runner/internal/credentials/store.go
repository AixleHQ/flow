// Package credentials keeps the machine's environment credential on disk:
// `credentials` in the state directory, mode 0600, owned by the runner's user
// (DESIGN.md §6.3, §9.2). Every write is atomic, so a crash leaves either the old
// pair or the new one, never a torn file.
package credentials

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/aixlehq/aixle-runner/internal/fsutil"
	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// FileName is the credentials file inside the state directory.
const FileName = "credentials"

// ErrNotConfigured means there is no credentials file: the machine has not been
// registered with `aixle-runner configure`, or it was unregistered.
var ErrNotConfigured = errors.New("this machine is not registered: run `aixle-runner configure` first")

// ErrInvalid means the credentials file cannot be used: it is not valid JSON, or a
// field is missing.
var ErrInvalid = errors.New("not a valid credentials file")

// Credentials is the content of the file.
type Credentials struct {
	// URL is the platform the machine registered with.
	URL         string               `json:"url"`
	Environment protocol.Environment `json:"environment"`
	protocol.TokenPair
	// AutoUpdate is false on a machine configured with `--no-auto-update`, which
	// never updates itself (DESIGN.md §14.4). Absent means true.
	AutoUpdate *bool `json:"auto_update,omitempty"`
}

// AutoUpdateEnabled says whether the machine updates itself.
func (c Credentials) AutoUpdateEnabled() bool {
	return c.AutoUpdate == nil || *c.AutoUpdate
}

// Store reads and writes the file.
type Store struct {
	path string
}

// NewStore returns the store in stateDir.
func NewStore(stateDir string) *Store {
	return &Store{path: filepath.Join(stateDir, FileName)}
}

// Path is the file's path.
func (s *Store) Path() string { return s.path }

// Load reads the credentials, or returns ErrNotConfigured.
func (s *Store) Load() (Credentials, error) {
	raw, err := os.ReadFile(s.path)
	if errors.Is(err, fs.ErrNotExist) {
		return Credentials{}, ErrNotConfigured
	}
	if err != nil {
		return Credentials{}, fmt.Errorf("reading %s: %w", s.path, err)
	}
	var c Credentials
	if err := json.Unmarshal(raw, &c); err != nil {
		// The error names the path, never the content, which holds the tokens.
		return Credentials{}, fmt.Errorf("%s is %w", s.path, ErrInvalid)
	}
	if c.URL == "" || c.AccessToken == "" || c.RefreshToken == "" {
		return Credentials{}, fmt.Errorf("%s is %w", s.path, ErrInvalid)
	}
	return c, nil
}

// Exists says whether a credentials file is present. Only a path that does not
// exist means no credentials: any other failure, such as a directory the caller
// cannot read, is returned, because it does not tell either way.
func (s *Store) Exists() (bool, error) {
	_, err := os.Lstat(s.path)
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, fs.ErrNotExist):
		return false, nil
	}
	return false, fmt.Errorf("checking for %s: %w", s.path, err)
}

// Save writes the credentials atomically with mode 0600.
func (s *Store) Save(c Credentials) error {
	raw, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return fmt.Errorf("encoding the credentials: %w", err)
	}
	return fsutil.WriteFileAtomic(s.path, append(raw, '\n'), 0o600)
}

// Delete removes the file. A missing file is not an error.
func (s *Store) Delete() error {
	err := os.Remove(s.path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("deleting %s: %w", s.path, err)
	}
	return nil
}
