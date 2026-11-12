package docker

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Output and files over the output cap come back through an upload to a signed
// URL the op's payload carries (runner/protocol/PROTOCOL.md §6.5). A slot is
// one such URL, for one output: `stdout` and `stderr` of an `exec`, `content` of
// a `read_file`.

// UploadSlot is one entry of a payload's `uploads`.
type UploadSlot struct {
	// ID names the upload in the result. It is opaque.
	ID string `json:"id"`
	// URL takes a PUT of the bytes. It is signed, so it carries no credential of
	// the runner's: the runner's bearer is never sent to it.
	URL string `json:"url"`
	// MaxBytes is the most the platform takes. A larger output is cut to it, and
	// a larger file is refused.
	MaxBytes int64 `json:"max_bytes"`
}

// Uploads are the slots of a payload, by output name. A slot that is `null` is
// absent.
type Uploads map[string]*UploadSlot

func (u Uploads) validate() *protocol.Result {
	for name, slot := range u {
		if slot == nil {
			continue
		}
		if slot.ID == "" || slot.URL == "" || slot.MaxBytes < 0 {
			return invalid("`uploads.%s` must be {id, url, max_bytes} with an id, a url and a max_bytes that is not negative", name)
		}
	}
	return nil
}

// slot is the usable slot of an output, or nil: one that is absent, or whose
// limit is not above the output cap, since an output the cap holds is inline.
func (u Uploads) slot(name string) *UploadSlot {
	if slot := u[name]; slot != nil && slot.MaxBytes > OutputCap {
		return slot
	}
	return nil
}

// Uploader puts the bytes of an output to a slot's URL.
type Uploader interface {
	Upload(ctx context.Context, slot UploadSlot, body io.ReaderAt, size int64) error
}

// Upload attempts: a PUT that failed on the network or with a 5xx is sent again
// after these pauses, so a blip does not cost the output.
var uploadRetryPauses = []time.Duration{500 * time.Millisecond, 2 * time.Second}

// HTTPUploader is the Uploader of the host runner: one PUT with the exact
// Content-Length, no other credential than the URL's own signature, and no
// redirect followed.
type HTTPUploader struct {
	// Client is replaced in tests. Nil is a client with no overall timeout: the
	// op's deadline bounds the upload.
	Client *http.Client
	// Pauses replaces the pauses between attempts, in tests.
	Pauses []time.Duration
}

// Upload sends body, size bytes of it, with a PUT. Only a 2xx answer counts.
// The error never carries the URL, which is the signature.
func (u HTTPUploader) Upload(ctx context.Context, slot UploadSlot, body io.ReaderAt, size int64) error {
	if err := checkSlotURL(slot.URL); err != nil {
		return err
	}
	client := u.Client
	if client == nil {
		client = &http.Client{}
	}
	// The signed URL is the capability: a redirect is not followed.
	noRedirect := *client
	noRedirect.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	pauses := u.Pauses
	if pauses == nil {
		pauses = uploadRetryPauses
	}
	var last error
	for attempt := 0; ; attempt++ {
		retry, err := put(ctx, &noRedirect, slot.URL, body, size)
		if err == nil {
			return nil
		}
		last = err
		if !retry || attempt >= len(pauses) {
			return last
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("%w (%v)", last, ctx.Err())
		case <-time.After(pauses[attempt]):
		}
	}
}

// put makes one attempt. The first result says whether another attempt can
// succeed.
func put(ctx context.Context, client *http.Client, target string, body io.ReaderAt, size int64) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, target, io.NopCloser(io.NewSectionReader(body, 0, size)))
	if err != nil {
		return false, errors.New("building the upload request failed")
	}
	req.ContentLength = size
	resp, err := client.Do(req)
	if err != nil {
		// net/http names the URL in its error; the URL is the signature.
		var urlErr *url.Error
		if errors.As(err, &urlErr) {
			err = urlErr.Err
		}
		return ctx.Err() == nil, fmt.Errorf("the upload failed: %w", err)
	}
	defer resp.Body.Close()
	message, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return false, nil
	}
	return resp.StatusCode >= 500, fmt.Errorf("the upload was refused with status %d: %s", resp.StatusCode, strings.TrimSpace(string(message)))
}

// checkSlotURL accepts https, and http only to a loopback host, as the platform
// URL is accepted (protocol.ParsePlatformURL): a development platform serves its
// stand-in for S3 there.
func checkSlotURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return errors.New("the upload URL is not an absolute URL")
	}
	switch u.Scheme {
	case "https":
		return nil
	case "http":
		if host := u.Hostname(); host == "localhost" || (net.ParseIP(host) != nil && net.ParseIP(host).IsLoopback()) {
			return nil
		}
	}
	return errors.New("the upload URL must use https")
}

// spool is a temporary file that holds an output while it is uploaded. It is
// removed with Close, and it is readable only by the runner's user.
type spool struct {
	f *os.File
	n int64
}

func newSpool() (*spool, error) {
	f, err := os.CreateTemp("", "aixle-upload-*")
	if err != nil {
		return nil, err
	}
	return &spool{f: f}, nil
}

func (s *spool) Write(p []byte) (int, error) {
	n, err := s.f.Write(p)
	s.n += int64(n)
	return n, err
}

// Close removes the file.
func (s *spool) Close() {
	if s == nil {
		return
	}
	name := s.f.Name()
	_ = s.f.Close()
	_ = os.Remove(name)
}

// outputBuffer keeps the output of one stream of an exec. The first OutputCap
// bytes stay in memory. With a slot, the stream goes on into a spool file up to
// the slot's limit, so the whole of it can be uploaded; the rest is read and
// dropped, so the command never blocks on a full pipe, and marked truncated.
type outputBuffer struct {
	head bytes.Buffer
	slot *UploadSlot
	file *spool
	// err is why the spool could not be written: the output is then cut to the
	// cap, as it is without a slot.
	err       error
	truncated bool
}

func newOutputBuffer(slot *UploadSlot) *outputBuffer { return &outputBuffer{slot: slot} }

func (o *outputBuffer) Write(p []byte) (int, error) {
	total := len(p)
	if o.file == nil {
		room := OutputCap - o.head.Len()
		if len(p) <= room {
			o.head.Write(p)
			return total, nil
		}
		// The head is full from here on, whatever happens to the rest.
		o.head.Write(p[:room])
		p = p[room:]
		if o.slot == nil || o.err != nil {
			o.truncated = true
			return total, nil
		}
		file, err := newSpool()
		if err == nil {
			_, err = file.Write(o.head.Bytes())
		}
		if err != nil {
			file.Close()
			o.err = err
			o.truncated = true
			return total, nil
		}
		o.file = file
	}
	room := o.slot.MaxBytes - o.file.n
	if room < int64(len(p)) {
		o.truncated = true
		p = p[:max(room, 0)]
	}
	if _, err := o.file.Write(p); err != nil {
		// Keep what the head holds: the output is cut to the cap.
		o.err = err
		o.file.Close()
		o.file = nil
		o.truncated = true
	}
	return total, nil
}

// spooled says whether the stream went over the cap into a file.
func (o *outputBuffer) spooled() bool { return o.file != nil }

// inline is the first OutputCap bytes as a JSON string can carry them: a rune cut
// by the cap is dropped, and bytes that are not UTF-8 become U+FFFD.
func (o *outputBuffer) inline() string {
	b := o.head.Bytes()
	if o.truncated || o.spooled() {
		b = trimPartialRuneEnd(b)
	}
	return strings.ToValidUTF8(string(b), "\uFFFD")
}

func (o *outputBuffer) close() { o.file.Close() }

// uploaded is the `data.uploads` entry of an output that came back through its
// slot.
func uploaded(slot *UploadSlot, size int64) map[string]any {
	return map[string]any{"id": slot.ID, "size": size}
}

// upload sends a spool to its slot, within the op's deadline: after it nobody
// waits for the result, so the upload is not tried.
func (e *Environment) upload(ctx context.Context, slot *UploadSlot, s *spool) error {
	if deadline, ok := protocol.OpDeadline(ctx); ok {
		if !e.now().Before(deadline) {
			return errors.New("the op's deadline has passed")
		}
		var cancel context.CancelFunc
		ctx, cancel = context.WithDeadline(ctx, deadline)
		defer cancel()
	}
	uploader := e.Uploader
	if uploader == nil {
		uploader = HTTPUploader{}
	}
	return uploader.Upload(ctx, *slot, s.f, s.n)
}
