package update

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

func digest(b string) string {
	sum := sha256.Sum256([]byte(b))
	return hex.EncodeToString(sum[:])
}

// releases is a fake of the platform's two release endpoints, pinning one digest.
type releases struct {
	mu       sync.Mutex
	pinned   string
	location string
	calls    []string
}

func (r *releases) Checksums(_ context.Context, version string) (protocol.Checksums, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, "checksums "+version)
	return protocol.Checksums{Version: version, Binaries: map[string]protocol.Digest{"linux-amd64": {SHA256: r.pinned}}}, nil
}

func (r *releases) Release(_ context.Context, version, platform string) (protocol.ReleaseLocation, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, "release "+version+" "+platform)
	return protocol.ReleaseLocation{Location: r.location, SHA256: r.pinned}, nil
}

// server serves the binary's bytes, as the asset host behind the redirect does.
type server struct {
	mu        sync.Mutex
	downloads int
	body      string
}

func (s *server) serve(body string) { s.mu.Lock(); s.body = body; s.mu.Unlock() }
func (s *server) count() int        { s.mu.Lock(); defer s.mu.Unlock(); return s.downloads }

type fixture struct {
	t        *testing.T
	updater  *Updater
	releases *releases
	server   *server
	logs     *bytes.Buffer
	now      *time.Time
}

const (
	oldBinary = "aixle-runner 1.4.0"
	newBinary = "aixle-runner 1.5.0"
)

func newFixture(t *testing.T) *fixture {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "aixle-runner")
	if err := os.WriteFile(bin, []byte(oldBinary), 0o755); err != nil {
		t.Fatal(err)
	}
	srv := &server{body: newBinary}
	asset := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		srv.mu.Lock()
		defer srv.mu.Unlock()
		srv.downloads++
		if r.Header.Get("Authorization") != "" {
			t.Error("the download carried a token")
		}
		_, _ = w.Write([]byte(srv.body))
	}))
	t.Cleanup(asset.Close)
	rel := &releases{pinned: digest(newBinary), location: asset.URL + "/aixle-runner-linux-amd64"}
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	logs := &bytes.Buffer{}
	f := &fixture{t: t, releases: rel, server: srv, logs: logs, now: &now}
	f.updater = &Updater{
		Releases: rel,
		Current:  "1.4.0",
		Binary:   bin,
		Busy:     func(context.Context) (bool, error) { return false, nil },
		Platform: "linux-amd64",
		Logger:   slog.New(slog.NewTextHandler(logs, nil)),
		Now:      func() time.Time { return *f.now },
	}
	return f
}

func (f *fixture) offer() protocol.Update {
	return protocol.Update{Version: "1.5.0", SHA256: digest(newBinary)}
}

func (f *fixture) binary() string {
	f.t.Helper()
	b, err := os.ReadFile(f.updater.Binary)
	if err != nil {
		f.t.Fatal(err)
	}
	return string(b)
}

// onlyTheBinary fails unless the binary's directory holds nothing else: a refused
// download leaves no file behind.
func (f *fixture) onlyTheBinary() {
	f.t.Helper()
	entries, _ := os.ReadDir(filepath.Dir(f.updater.Binary))
	if len(entries) != 1 {
		names := []string{}
		for _, e := range entries {
			names = append(names, e.Name())
		}
		f.t.Fatalf("the directory holds %v", names)
	}
}

func TestAnIdleRunnerSwitchesToTheVerifiedBinary(t *testing.T) {
	f := newFixture(t)
	if !f.updater.Apply(context.Background(), f.offer()) {
		t.Fatalf("not applied:\n%s", f.logs)
	}
	if got := f.binary(); got != newBinary {
		t.Fatalf("the binary is %q", got)
	}
	info, _ := os.Stat(f.updater.Binary)
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("mode %v", info.Mode().Perm())
	}
	f.onlyTheBinary()
	want := []string{"checksums 1.5.0", "release 1.5.0 linux-amd64"}
	if len(f.releases.calls) != 2 || f.releases.calls[0] != want[0] || f.releases.calls[1] != want[1] {
		t.Fatalf("calls %v", f.releases.calls)
	}
}

func TestATamperedBinaryIsRefusedAndTheOldOneKeepsRunning(t *testing.T) {
	f := newFixture(t)
	f.server.serve("aixle-runner 1.5.0, with something added")
	if f.updater.Apply(context.Background(), f.offer()) {
		t.Fatal("a tampered binary was installed")
	}
	if got := f.binary(); got != oldBinary {
		t.Fatalf("the binary is %q", got)
	}
	f.onlyTheBinary()
	if !bytes.Contains(f.logs.Bytes(), []byte("SHA-256")) {
		t.Fatalf("the log does not say why:\n%s", f.logs)
	}

	// The same offer on the next poll is not downloaded again for an hour.
	f.updater.Apply(context.Background(), f.offer())
	if f.server.count() != 1 {
		t.Fatalf("downloaded %d times", f.server.count())
	}
	*f.now = f.now.Add(RetryAfter)
	f.server.serve(newBinary)
	if !f.updater.Apply(context.Background(), f.offer()) || f.binary() != newBinary {
		t.Fatal("the retry an hour later did not install the right binary")
	}
}

func TestNoUpdateWhileTheMachineHoldsASession(t *testing.T) {
	f := newFixture(t)
	f.updater.Busy = func(context.Context) (bool, error) { return true, nil }
	if f.updater.Apply(context.Background(), f.offer()) || f.updater.Apply(context.Background(), f.offer()) {
		t.Fatal("updated during a session")
	}
	if f.server.count() != 0 || len(f.releases.calls) != 0 || f.binary() != oldBinary {
		t.Fatalf("downloads %d, calls %v", f.server.count(), f.releases.calls)
	}
	if n := bytes.Count(f.logs.Bytes(), []byte("holds a session")); n != 1 {
		t.Fatalf("logged %d times:\n%s", n, f.logs)
	}

	// Once the session is gone, the next offer is taken.
	f.updater.Busy = func(context.Context) (bool, error) { return false, nil }
	if !f.updater.Apply(context.Background(), f.offer()) {
		t.Fatal("not applied once idle")
	}

	f = newFixture(t)
	f.updater.Busy = func(context.Context) (bool, error) { return false, errors.New("docker: connection refused") }
	if f.updater.Apply(context.Background(), f.offer()) || f.server.count() != 0 {
		t.Fatal("updated without knowing whether a session runs")
	}
}

func TestTheOptOutNeverUpdates(t *testing.T) {
	f := newFixture(t)
	f.updater.Disabled = true
	for i := 0; i < 3; i++ {
		if f.updater.Apply(context.Background(), f.offer()) {
			t.Fatal("updated with the opt-out")
		}
	}
	if f.server.count() != 0 || len(f.releases.calls) != 0 || f.binary() != oldBinary {
		t.Fatalf("downloads %d, calls %v", f.server.count(), f.releases.calls)
	}
	if n := bytes.Count(f.logs.Bytes(), []byte("self-update is off")); n != 1 {
		t.Fatalf("logged %d times:\n%s", n, f.logs)
	}
}

func TestAnOfferThatIsNotNewerIsIgnored(t *testing.T) {
	for _, v := range []string{"1.4.0", "1.3.9", "1.5.0-rc.1-not semver", "latest"} {
		f := newFixture(t)
		o := f.offer()
		o.Version = v
		if f.updater.Apply(context.Background(), o) || len(f.releases.calls) != 0 {
			t.Errorf("%s: applied, calls %v", v, f.releases.calls)
		}
	}
}

func TestDigestsThatDisagreeAreNotDownloaded(t *testing.T) {
	f := newFixture(t)
	o := f.offer()
	o.SHA256 = digest("something else")
	if f.updater.Apply(context.Background(), o) || f.server.count() != 0 || f.binary() != oldBinary {
		t.Fatalf("applied, downloads %d", f.server.count())
	}

	f = newFixture(t)
	f.releases.pinned = digest("something else")
	if f.updater.Apply(context.Background(), f.offer()) || f.server.count() != 0 {
		t.Fatalf("applied, downloads %d", f.server.count())
	}
}

func TestVerifyChecksTheDigest(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bin")
	if err := os.WriteFile(path, []byte(newBinary), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := Verify(path, Expected{Version: "1.5.0", Platform: "linux-amd64", SHA256: digest(newBinary)}); err != nil {
		t.Fatal(err)
	}
	err := Verify(path, Expected{Version: "1.5.0", Platform: "linux-amd64", SHA256: digest(oldBinary)})
	if !errors.Is(err, ErrDigestMismatch) {
		t.Fatalf("got %v", err)
	}
}
