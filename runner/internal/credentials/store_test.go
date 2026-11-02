package credentials

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

func sample(n string) Credentials {
	exp := time.Date(2026, 11, 2, 13, 0, 0, 0, time.UTC)
	return Credentials{
		URL:         "https://flow.aixle.com",
		Environment: protocol.Environment{ID: 42, Key: "aixle-r7-build", DisplayName: "build-01", State: "registered"},
		TokenPair: protocol.TokenPair{
			AccessToken: "aracc_" + n, AccessTokenExpiresAt: exp,
			RefreshToken: "arref_" + n, RefreshTokenExpiresAt: exp.Add(720 * time.Hour),
		},
	}
}

func TestNotConfigured(t *testing.T) {
	s := NewStore(t.TempDir())
	if _, err := s.Load(); !errors.Is(err, ErrNotConfigured) {
		t.Fatalf("got %v", err)
	}
	if s.Exists() {
		t.Fatal("exists")
	}
}

func TestSaveLoadAndRotate(t *testing.T) {
	dir := t.TempDir()
	s := NewStore(dir)
	if err := s.Save(sample("1")); err != nil {
		t.Fatal(err)
	}
	if err := s.Save(sample("2")); err != nil {
		t.Fatal(err)
	}
	got, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if got.AccessToken != "aracc_2" || got.RefreshToken != "arref_2" || got.Environment.Key != "aixle-r7-build" || !got.AccessTokenExpiresAt.Equal(sample("2").AccessTokenExpiresAt) {
		t.Fatalf("loaded %#v", got)
	}

	info, _ := os.Stat(s.Path())
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", info.Mode().Perm())
	}
	// The atomic write leaves no temporary file behind.
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Fatalf("the directory holds %d files", len(entries))
	}
}

func TestACorruptFileIsReportedWithoutItsContent(t *testing.T) {
	dir := t.TempDir()
	_ = os.WriteFile(filepath.Join(dir, FileName), []byte(`{"access_token":"aracc_secret"`), 0o600)
	_, err := NewStore(dir).Load()
	if err == nil || strings.Contains(err.Error(), "aracc_secret") {
		t.Fatalf("got %v", err)
	}
}

func TestDelete(t *testing.T) {
	s := NewStore(t.TempDir())
	_ = s.Save(sample("1"))
	if err := s.Delete(); err != nil {
		t.Fatal(err)
	}
	if s.Exists() {
		t.Fatal("still there")
	}
	if err := s.Delete(); err != nil {
		t.Fatal("deleting twice failed")
	}
}
