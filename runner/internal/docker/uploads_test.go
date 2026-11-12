package docker

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// recordingUploader keeps what it is sent, or fails.
type recordingUploader struct {
	slots  []UploadSlot
	bodies [][]byte
	err    error
}

func (r *recordingUploader) Upload(_ context.Context, slot UploadSlot, body io.ReaderAt, size int64) error {
	if r.err != nil {
		return r.err
	}
	data, err := io.ReadAll(io.NewSectionReader(body, 0, size))
	if err != nil {
		return err
	}
	r.slots = append(r.slots, slot)
	r.bodies = append(r.bodies, data)
	return nil
}

func slotPayload(id string, max int64) map[string]any {
	return map[string]any{"id": id, "url": "https://uploads.example.test/cache/" + id, "max_bytes": max}
}

func uploadedEntry(t *testing.T, r protocol.Result, name string) map[string]any {
	t.Helper()
	entries, _ := r.Data["uploads"].(map[string]any)
	entry, _ := entries[name].(map[string]any)
	return entry
}

func TestExecUploadsAStreamOverTheCapAndKeepsTheOtherInline(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	// Multi-byte runes everywhere, and bytes that are not UTF-8: an upload is the bytes as they are.
	big := append(bytes.Repeat([]byte("é"), OutputCap), 0xff, 'z')
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Stdout: big, Stderr: []byte("warn\n")} }

	r := h.run(h.env.Exec, map[string]any{
		"cmd": []string{"cat"}, "uploads": map[string]any{"stdout": slotPayload("one", 8<<20), "stderr": slotPayload("two", 8<<20)},
	})

	if r.Status != protocol.StatusOK {
		t.Fatalf("%#v", r)
	}
	if r.Stdout != nil {
		t.Errorf("an uploaded stream has no inline text, got %d bytes", len(*r.Stdout))
	}
	if r.Stderr == nil || *r.Stderr != "warn\n" {
		t.Errorf("the stream under the cap stays inline: %v", r.Stderr)
	}
	entry := uploadedEntry(t, r, "stdout")
	if entry["id"] != "one" || entry["size"] != int64(len(big)) {
		t.Fatalf("uploads %#v", r.Data["uploads"])
	}
	if uploadedEntry(t, r, "stderr") != nil {
		t.Errorf("stderr fits the cap and is not uploaded: %#v", r.Data["uploads"])
	}
	if len(uploader.bodies) != 1 || !bytes.Equal(uploader.bodies[0], big) || uploader.slots[0].ID != "one" {
		t.Fatalf("uploaded %d bodies", len(uploader.bodies))
	}
	if r.Data["stdout_truncated"] != false {
		t.Errorf("the whole stream was uploaded: %#v", r.Data)
	}
}

func TestExecCutsAStreamAtTheSlotsLimit(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	limit := int64(OutputCap + 100)
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Stdout: bytes.Repeat([]byte("a"), OutputCap*3)} }

	r := h.run(h.env.Exec, map[string]any{"cmd": []string{"yes"}, "uploads": map[string]any{"stdout": slotPayload("one", limit)}})

	if uploadedEntry(t, r, "stdout")["size"] != limit || int64(len(uploader.bodies[0])) != limit {
		t.Fatalf("uploaded %d bytes, %#v", len(uploader.bodies[0]), r.Data)
	}
	if r.Data["stdout_truncated"] != true {
		t.Errorf("a stream cut at the limit is marked truncated: %#v", r.Data)
	}
}

func TestAnExecThatFailsToUploadAnswersTheFirstMiBAndSaysWhy(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	h.env.Uploader = &recordingUploader{err: errors.New("the upload was refused with status 403: expired")}
	h.engine.run = func(*fakeExec, []byte) fakeRun {
		return fakeRun{Stdout: append(bytes.Repeat([]byte("a"), OutputCap), []byte("tail")...)}
	}

	r := h.run(h.env.Exec, map[string]any{"cmd": []string{"cat"}, "uploads": map[string]any{"stdout": slotPayload("one", 8<<20)}})

	if r.Status != protocol.StatusOK || r.Stdout == nil || len(*r.Stdout) != OutputCap {
		t.Fatalf("%#v", r)
	}
	if r.Data["stdout_truncated"] != true {
		t.Errorf("data %#v", r.Data)
	}
	errs, _ := r.Data["upload_errors"].(map[string]any)
	if msg, _ := errs["stdout"].(string); !strings.Contains(msg, "403") {
		t.Errorf("upload_errors %#v", r.Data["upload_errors"])
	}
	if r.Data["uploads"] != nil {
		t.Errorf("nothing was uploaded: %#v", r.Data["uploads"])
	}
}

func TestExecWithoutAUsableSlotCutsTheStreamAsBefore(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Stdout: bytes.Repeat([]byte("a"), OutputCap+1)} }

	// No slot, a slot with a limit the cap holds, and a null slot.
	for _, uploads := range []any{nil, map[string]any{"stdout": slotPayload("one", OutputCap)}, map[string]any{"stdout": nil}} {
		r := h.run(h.env.Exec, map[string]any{"cmd": []string{"yes"}, "uploads": uploads})
		if r.Status != protocol.StatusOK || r.Stdout == nil || len(*r.Stdout) != OutputCap || r.Data["stdout_truncated"] != true {
			t.Fatalf("%v: %#v", uploads, r)
		}
	}
	if len(uploader.bodies) != 0 {
		t.Fatal("something was uploaded")
	}
}

func TestAnExecNeverLeavesASpoolBehind(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	h := newEnvironment(t)
	h.session()
	h.env.Uploader = &recordingUploader{}
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Stdout: bytes.Repeat([]byte("a"), OutputCap+1)} }
	h.run(h.env.Exec, map[string]any{"cmd": []string{"cat"}, "uploads": map[string]any{"stdout": slotPayload("one", 8<<20)}})
	h.env.Uploader = &recordingUploader{err: errors.New("down")}
	h.run(h.env.Exec, map[string]any{"cmd": []string{"cat"}, "uploads": map[string]any{"stdout": slotPayload("one", 8<<20)}})

	entries, err := os.ReadDir(tmp)
	if err != nil || len(entries) != 0 {
		t.Fatalf("temporary files left: %v %v", entries, err)
	}
}

func TestReadFileUploadsAFileOverTheCap(t *testing.T) {
	tmp := t.TempDir()
	t.Setenv("TMPDIR", tmp)
	h := newEnvironment(t)
	c := h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	content := bytes.Repeat([]byte("log line\n"), OutputCap/4)
	h.put(c, "/tmp/terminal_output.log", &fakeFile{Content: content, Mode: 0o644})

	r := h.run(h.env.ReadFile, map[string]any{
		"path": "/tmp/terminal_output.log", "uploads": map[string]any{"content": slotPayload("one", 64<<20)},
	})

	if r.Status != protocol.StatusOK || r.Data["content"] != nil || r.Data["size"] != int64(len(content)) {
		t.Fatalf("%#v", r)
	}
	if entry := uploadedEntry(t, r, "content"); entry["id"] != "one" || entry["size"] != int64(len(content)) {
		t.Fatalf("uploads %#v", r.Data["uploads"])
	}
	if len(uploader.bodies) != 1 || !bytes.Equal(uploader.bodies[0], content) {
		t.Fatal("the upload is not the file")
	}
	if entries, _ := os.ReadDir(tmp); len(entries) != 0 {
		t.Fatalf("temporary files left: %v", entries)
	}
}

func TestReadFileUnderTheCapStaysInlineEvenWithASlot(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	h.put(c, "/limit", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap), Mode: 0o644})

	r := h.run(h.env.ReadFile, map[string]any{"path": "/limit", "uploads": map[string]any{"content": slotPayload("one", 64<<20)}})

	if r.Status != protocol.StatusOK || r.Data["content"] == nil || r.Data["uploads"] != nil || len(uploader.bodies) != 0 {
		t.Fatalf("%#v", r)
	}
}

func TestReadFileRefusesWhatTheSlotCannotTake(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	h.put(c, "/big", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap+10), Mode: 0o644})

	cases := map[string]any{
		"no slot":              nil,
		"a limit under size":   map[string]any{"content": slotPayload("one", OutputCap+5)},
		"a limit at the cap":   map[string]any{"content": slotPayload("one", OutputCap)},
		"a slot for stdout":    map[string]any{"stdout": slotPayload("one", 64<<20)},
		"a null slot":          map[string]any{"content": nil},
		"a slot with no limit": map[string]any{"content": map[string]any{"id": "one", "url": "https://x.test/u", "max_bytes": 0}},
	}
	for name, uploads := range cases {
		r := h.run(h.env.ReadFile, map[string]any{"path": "/big", "uploads": uploads})
		if r.Error == nil || r.Error.Class != ClassFileTooLarge {
			t.Errorf("%s: %#v", name, r)
		}
	}
	if len(uploader.bodies) != 0 {
		t.Fatal("something was uploaded")
	}
}

func TestReadFileThatFailsToUploadIsFileTooLarge(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.env.Uploader = &recordingUploader{err: errors.New("the upload failed: connection reset")}
	h.put(c, "/big", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap+10), Mode: 0o644})

	r := h.run(h.env.ReadFile, map[string]any{"path": "/big", "uploads": map[string]any{"content": slotPayload("one", 64<<20)}})

	if r.Error == nil || r.Error.Class != ClassFileTooLarge || !strings.Contains(r.Error.Message, "connection reset") {
		t.Fatalf("%#v", r)
	}
}

func TestAnUploadAfterTheOpsDeadlineIsNotTried(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	uploader := &recordingUploader{}
	h.env.Uploader = uploader
	h.put(c, "/big", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap+10), Mode: 0o644})
	h.env.Now = func() time.Time { return time.Now().Add(time.Hour) }
	ctx := protocol.WithOpDeadline(context.Background(), time.Now().Add(time.Minute))

	r := h.env.ReadFile(ctx, sessionID, mustJSON(t, map[string]any{"path": "/big", "uploads": map[string]any{"content": slotPayload("one", 64<<20)}}))

	if r.Error == nil || r.Error.Class != ClassFileTooLarge || !strings.Contains(r.Error.Message, "deadline") || len(uploader.bodies) != 0 {
		t.Fatalf("%#v", r)
	}
}

func TestUploadsOfTheWrongShapeAreInvalidPayloads(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.put(c, "/f", &fakeFile{Content: []byte("x"), Mode: 0o644})
	for name, uploads := range map[string]any{
		"not an object":  "https://x.test/u",
		"no id":          map[string]any{"content": map[string]any{"url": "https://x.test/u", "max_bytes": 5}},
		"no url":         map[string]any{"content": map[string]any{"id": "one", "max_bytes": 5}},
		"negative limit": map[string]any{"content": map[string]any{"id": "one", "url": "https://x.test/u", "max_bytes": -1}},
		"string limit":   map[string]any{"content": map[string]any{"id": "one", "url": "https://x.test/u", "max_bytes": "5"}},
	} {
		if r := h.run(h.env.ReadFile, map[string]any{"path": "/f", "uploads": uploads}); r.Error == nil || r.Error.Class != ClassInvalidPayload {
			t.Errorf("read_file, %s: %#v", name, r)
		}
		if r := h.run(h.env.Exec, map[string]any{"cmd": []string{"true"}, "uploads": uploads}); r.Error == nil || r.Error.Class != ClassInvalidPayload {
			t.Errorf("exec, %s: %#v", name, r)
		}
	}
}

func uploadFile(t *testing.T, content string) (*os.File, int64) {
	t.Helper()
	f, err := os.CreateTemp(t.TempDir(), "body")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { f.Close() })
	if _, err := f.WriteString(content); err != nil {
		t.Fatal(err)
	}
	return f, int64(len(content))
}

func TestHTTPUploaderPutsTheBytesWithTheLengthAndNoCredential(t *testing.T) {
	var method, auth, length, agent string
	var got []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method, auth, length, agent = r.Method, r.Header.Get("Authorization"), r.Header.Get("Content-Length"), r.Header.Get("X-Aixle-Runner-Version")
		got, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	f, size := uploadFile(t, "the whole file")

	err := HTTPUploader{}.Upload(context.Background(), UploadSlot{ID: "one", URL: server.URL + "/cache/one?sig=1", MaxBytes: 1 << 30}, f, size)

	if err != nil {
		t.Fatal(err)
	}
	if method != http.MethodPut || string(got) != "the whole file" || length != "14" || auth != "" || agent != "" {
		t.Fatalf("method %s, body %q, length %s, auth %q, version %q", method, got, length, auth, agent)
	}
}

func TestHTTPUploaderRetriesAFailureThatCanPass(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if string(body) != "payload" {
			t.Errorf("attempt %d sent %q", calls.Load()+1, body)
		}
		if calls.Add(1) < 3 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	f, size := uploadFile(t, "payload")

	err := HTTPUploader{Pauses: []time.Duration{time.Millisecond, time.Millisecond}}.Upload(context.Background(), UploadSlot{ID: "one", URL: server.URL}, f, size)

	if err != nil || calls.Load() != 3 {
		t.Fatalf("%d calls, %v", calls.Load(), err)
	}
}

func TestHTTPUploaderDoesNotRetryARefusedSignature(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusForbidden)
		_, _ = io.WriteString(w, "Request has expired")
	}))
	defer server.Close()
	f, size := uploadFile(t, "payload")

	err := HTTPUploader{Pauses: []time.Duration{time.Millisecond, time.Millisecond}}.Upload(context.Background(), UploadSlot{ID: "one", URL: server.URL + "?X-Amz-Signature=secret"}, f, size)

	if err == nil || !strings.Contains(err.Error(), "403") || !strings.Contains(err.Error(), "expired") || calls.Load() != 1 {
		t.Fatalf("%d calls, %v", calls.Load(), err)
	}
	if strings.Contains(err.Error(), "secret") {
		t.Fatalf("the error carries the signature: %v", err)
	}
}

func TestHTTPUploaderErrorsNeverCarryTheSignedURL(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	url := server.URL + "/cache/one?X-Amz-Signature=secret"
	server.Close()
	f, size := uploadFile(t, "payload")

	err := HTTPUploader{Pauses: []time.Duration{}}.Upload(context.Background(), UploadSlot{ID: "one", URL: url}, f, size)

	if err == nil || strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "/cache/") {
		t.Fatalf("%v", err)
	}
}

func TestHTTPUploaderDoesNotFollowARedirect(t *testing.T) {
	var elsewhere atomic.Int32
	other := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { elsewhere.Add(1) }))
	defer other.Close()
	server := httptest.NewServer(http.RedirectHandler(other.URL, http.StatusTemporaryRedirect))
	defer server.Close()
	f, size := uploadFile(t, "payload")

	err := HTTPUploader{Pauses: []time.Duration{}}.Upload(context.Background(), UploadSlot{ID: "one", URL: server.URL}, f, size)

	if err == nil || elsewhere.Load() != 0 {
		t.Fatalf("err %v, %d requests elsewhere", err, elsewhere.Load())
	}
}

func TestHTTPUploaderTakesOnlyAnHTTPSURLOrALoopbackOne(t *testing.T) {
	f, size := uploadFile(t, "payload")
	for _, url := range []string{"http://uploads.example.test/u", "ftp://x.test/u", "/relative", "", "file:///etc/passwd"} {
		if err := (HTTPUploader{}).Upload(context.Background(), UploadSlot{ID: "one", URL: url}, f, size); err == nil {
			t.Errorf("%q was accepted", url)
		}
	}
	for _, url := range []string{"http://127.0.0.1:3000/u", "http://localhost:3000/u", "http://[::1]:3000/u"} {
		if err := checkSlotURL(url); err != nil {
			t.Errorf("%q: %v", url, err)
		}
	}
}
