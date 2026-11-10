// Package update is the host runner's self-update (DESIGN.md §14.4,
// runner/protocol/PROTOCOL.md §5.4, §5.6, §5.7). When an answer of the long-poll
// without ops offers `update`, the runner takes it only while it holds no session
// and only towards a newer version. It reads the digest the platform pins from the
// checksums endpoint, asks the platform's release URL where the binary is, and
// downloads it into the directory of the running binary. Verify checks it, and only
// then does the new binary replace the old one, atomically. The runner then exits,
// and systemd starts the new binary (`Restart=always`).
//
// A machine whose operator turned self-update off (`configure --no-auto-update`),
// and a runner started from the published image, which sets
// AIXLE_RUNNER_NO_SELF_UPDATE, never update themselves, whatever the platform
// offers.
package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/aixlehq/aixle-runner/internal/fsutil"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// MaxBinaryBytes bounds a download. The runner's binary is about 20 MiB.
const MaxBinaryBytes = 256 << 20

// DownloadTimeout bounds one download. It is well under the platform's lifecycle
// op budget (Settings.runners.lifecycle_op_timeout, 10 minutes): a session the
// platform assigns to this machine while it updates has its `container.start`
// queued, and that op outlives the download and the restart, after which the
// runner polls and runs it (DESIGN.md §14.4). A download that does not finish in
// time is retried after RetryAfter.
const DownloadTimeout = 2 * time.Minute

// RetryAfter is how long an update that failed is not tried again: the platform
// offers it on every empty poll, every 25 seconds.
const RetryAfter = time.Hour

// ErrDigestMismatch is a downloaded binary whose SHA-256 is not the one the
// platform pins. It is never installed.
var ErrDigestMismatch = errors.New("the downloaded binary's SHA-256 is not the one the platform pins")

// Releases is the part of the protocol client the updater uses. Both endpoints
// are the platform's: the runner downloads only from where they point.
type Releases interface {
	Checksums(ctx context.Context, version string) (protocol.Checksums, error)
	Release(ctx context.Context, version, platform string) (protocol.ReleaseLocation, error)
}

// Expected is what Verify checks a downloaded binary against.
type Expected struct {
	Version  string
	Platform string
	// SHA256 is the digest from the platform's pins, hex-encoded.
	SHA256 string
}

// Verify is the hook every downloaded binary goes through before it is installed
// (DESIGN.md §14.3). Today it checks the SHA-256 only. A signature check is added
// here once releases are signed, without a change to the protocol.
func Verify(path string, want Expected) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("reading %s: %w", path, err)
	}
	got := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(got, want.SHA256) {
		return fmt.Errorf("%w: aixle-runner %s for %s is %s, the platform pins %s", ErrDigestMismatch, want.Version, want.Platform, got, want.SHA256)
	}
	return nil
}

// Updater applies the updates the platform offers.
type Updater struct {
	Releases Releases
	// Current is the running version, version.Version.
	Current string
	// Binary is the running binary's path, which an update replaces. The service
	// runs it from a directory its own user owns (internal/service).
	Binary string
	// Disabled turns self-update off: the machine's opt-out,
	// `configure --no-auto-update`, or AIXLE_RUNNER_NO_SELF_UPDATE, which the
	// published image sets because its tag is its version.
	Disabled bool
	// Busy says whether the machine holds a session: its session container
	// exists. The runner then waits for a later offer.
	Busy func(ctx context.Context) (bool, error)
	// Platform is `<os>-<arch>`. Empty means this build's.
	Platform string
	// HTTP downloads the binary. Nil is a client with DownloadTimeout.
	HTTP   *http.Client
	Logger *slog.Logger
	Now    func() time.Time

	failed  map[string]time.Time
	noticed map[string]bool
}

func (u *Updater) defaults() {
	if u.Logger == nil {
		u.Logger = slog.Default()
	}
	if u.Now == nil {
		u.Now = time.Now
	}
	if u.Platform == "" {
		u.Platform = runtime.GOOS + "-" + runtime.GOARCH
	}
	if u.HTTP == nil {
		u.HTTP = &http.Client{Timeout: DownloadTimeout}
	}
	if u.failed == nil {
		u.failed = map[string]time.Time{}
	}
	if u.noticed == nil {
		u.noticed = map[string]bool{}
	}
}

// notice logs a message once per key, so an offer repeated every poll does not
// repeat its line.
func (u *Updater) notice(key, msg string, args ...any) {
	if u.noticed[key] {
		return
	}
	u.noticed[key] = true
	u.Logger.Info(msg, args...)
}

// Apply takes offer if it may: it returns true once the new binary is in place
// and the runner must restart on it. Anything that keeps the update from being
// applied is logged, and the running binary stays as it is.
func (u *Updater) Apply(ctx context.Context, offer protocol.Update) bool {
	u.defaults()
	log := u.Logger.With("version", offer.Version, "current", u.Current)
	if u.Disabled {
		u.notice("disabled:"+offer.Version, "the platform recommends a newer aixle-runner, and self-update is off on this machine (configure --no-auto-update, or AIXLE_RUNNER_NO_SELF_UPDATE in the image)",
			"version", offer.Version, "current", u.Current)
		return false
	}
	newer, err := version.Newer(offer.Version, u.Current)
	if err != nil || !newer {
		u.notice("not-newer:"+offer.Version, "ignoring an update that is not newer than this aixle-runner",
			"version", offer.Version, "current", u.Current, "error", err)
		return false
	}
	if at, ok := u.failed[offer.Version]; ok && u.Now().Sub(at) < RetryAfter {
		return false
	}
	busy, err := u.Busy(ctx)
	if err != nil {
		log.Warn("cannot tell whether a session runs on this machine, so it is not updated now", "error", err)
		return false
	}
	if busy {
		u.notice("busy:"+offer.Version, "an update is available, and this machine holds a session: it updates once it is idle",
			"version", offer.Version, "current", u.Current)
		return false
	}

	log.Info("updating aixle-runner")
	if err := u.install(ctx, offer); err != nil {
		u.failed[offer.Version] = u.Now()
		log.Error("the update failed; this aixle-runner keeps running and tries again later",
			"error", err, "retry_in", RetryAfter)
		return false
	}
	log.Info("aixle-runner was updated; restarting on the new version", "binary", u.Binary)
	return true
}

func (u *Updater) install(ctx context.Context, offer protocol.Update) error {
	sums, err := u.Releases.Checksums(ctx, offer.Version)
	if err != nil {
		return fmt.Errorf("reading the release's checksums: %w", err)
	}
	pinned, ok := sums.Binaries[u.Platform]
	if !ok || pinned.SHA256 == "" {
		return fmt.Errorf("the platform pins no %s binary of aixle-runner %s", u.Platform, offer.Version)
	}
	if !strings.EqualFold(pinned.SHA256, offer.SHA256) {
		return fmt.Errorf("the update's SHA-256 %s is not the one the release's checksums pin, %s", offer.SHA256, pinned.SHA256)
	}
	loc, err := u.Releases.Release(ctx, offer.Version, u.Platform)
	if err != nil {
		return fmt.Errorf("asking the platform where the binary is: %w", err)
	}
	if !strings.EqualFold(loc.SHA256, pinned.SHA256) {
		return fmt.Errorf("the release URL's SHA-256 %s is not the one the release's checksums pin, %s", loc.SHA256, pinned.SHA256)
	}

	ctx, cancel := context.WithTimeout(ctx, DownloadTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, loc.Location, nil)
	if err != nil {
		return fmt.Errorf("the release's location %q: %w", loc.Location, err)
	}
	resp, err := u.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("downloading the binary: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("downloading the binary: the server answered %d", resp.StatusCode)
	}

	want := Expected{Version: offer.Version, Platform: u.Platform, SHA256: pinned.SHA256}
	body := &capped{r: resp.Body, left: MaxBinaryBytes}
	// The copy lands next to the running binary and is renamed over it only once
	// Verify passed: until then the running binary is untouched, and a refused
	// download is removed.
	return fsutil.CopyFileAtomic(body, u.Binary, 0o755, func(tmp string) error {
		if body.over {
			return fmt.Errorf("the binary is over %d bytes", MaxBinaryBytes)
		}
		return Verify(tmp, want)
	})
}

// BinaryPath is the running binary, with links resolved: the file an update
// replaces, and the one the callback proxy's sidecar runs (cli.HostOptions.Binary).
func BinaryPath() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(exe)
}

// capped reads at most left bytes, and remembers whether there was more.
type capped struct {
	r    io.Reader
	left int64
	over bool
}

func (c *capped) Read(p []byte) (int, error) {
	if c.left <= 0 {
		var one [1]byte
		if n, _ := c.r.Read(one[:]); n > 0 {
			c.over = true
		}
		return 0, io.EOF
	}
	if int64(len(p)) > c.left {
		p = p[:c.left]
	}
	n, err := c.r.Read(p)
	c.left -= int64(n)
	return n, err
}
