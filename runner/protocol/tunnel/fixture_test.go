package tunnel

// The reader and the runner of the *.frames fixtures in
// runner/protocol/fixtures/v1/tunnel/ (format: runner/protocol/fixtures/README.md).
// Each file runs twice, with the package as the relay and as the runner; the test
// drives the other end from the file, and fails if a frame type or a scenario has
// no file.

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"
)

const fixtureDir = "../fixtures/v1/tunnel"

// requiredFixtures are the files the package's tests insist on: one for each frame
// type, and one for each scenario of PROTOCOL.md §8.
var requiredFixtures = []string{
	"frame_hello", "frame_open", "frame_open_ok", "frame_data", "frame_window", "frame_close",
	"frame_reset", "frame_ping", "frame_pong", "frame_goaway",

	"open_data_both_directions",
	"half_close_relay_first", "half_close_runner_first",
	"reset_in_flight_by_relay", "reset_in_flight_by_runner", "data_after_reset_is_dropped",
	"flow_blocks_at_zero_credit", "flow_data_over_credit_relay", "flow_data_over_credit_runner",
	"flow_window_over_window_relay", "flow_window_over_window_runner",
	"fairness_control_before_data",
	"stream_cap_relay", "stream_cap_runner",
	"open_refused", "open_timeout",
	"heartbeat_timeout_relay", "heartbeat_timeout_runner", "heartbeat_runner_pings",
	"goaway_drain", "goaway_timeout",
	"connection_closed_resets_streams",
	"hello_negotiation_relay", "hello_negotiation_runner",
	"hello_unknown_fields_from_runner", "hello_unknown_fields_from_relay",
	"hello_version_refused_by_relay", "hello_version_refused_by_runner",
	"hello_limits_refused_by_relay", "hello_limits_refused_by_runner",
	"unknown_frame_type_relay", "unknown_frame_type_runner",
	"data_after_close_resets",
}

type fxStep struct {
	line int
	kind string // ">", "<", "do", "advance", "closed", "hangup", "quiet"
	msg  []byte
	verb string
	args map[string]string
	dur  time.Duration
	code int
	side string // from side=, "" for either
}

type fixture struct {
	name   string
	only   string // "relay", "runner" or ""
	config map[string]string
	steps  []fxStep
}

var repeatToken = regexp.MustCompile(`^([0-9a-fA-F]{2})\{(\d+)\}$`)

// parseHexTokens reads hex written as groups, where a byte followed by {n} is that
// byte n times.
func parseHexTokens(tokens []string) ([]byte, error) {
	var out []byte
	for _, tok := range tokens {
		if m := repeatToken.FindStringSubmatch(tok); m != nil {
			b, _ := hex.DecodeString(m[1])
			n, _ := strconv.Atoi(m[2])
			out = append(out, bytes.Repeat(b, n)...)
			continue
		}
		b, err := hex.DecodeString(tok)
		if err != nil {
			return nil, fmt.Errorf("hex %q: %v", tok, err)
		}
		out = append(out, b...)
	}
	return out, nil
}

func parseFixture(t testing.TB, path string) fixture {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	fx := fixture{name: strings.TrimSuffix(filepath.Base(path), ".frames"), config: map[string]string{}}
	for i, ln := range strings.Split(string(raw), "\n") {
		if j := strings.IndexByte(ln, '#'); j >= 0 {
			ln = ln[:j]
		}
		fields := strings.Fields(ln)
		if len(fields) == 0 {
			continue
		}
		step := fxStep{line: i + 1, args: map[string]string{}}
		fail := func(format string, args ...any) {
			t.Fatalf("%s:%d: %s", filepath.Base(path), i+1, fmt.Sprintf(format, args...))
		}
		switch {
		case fields[0] == ">" || fields[0] == "<":
			step.kind = fields[0]
			msg, err := parseHexTokens(fields[1:])
			if err != nil {
				fail("%v", err)
			}
			step.msg = msg
		case strings.HasPrefix(fields[0], "@"):
			word := fields[0][1:]
			rest := fields[1:]
			// Arguments are key=value; the first bare word is the verb or value.
			var bare []string
			for _, f := range rest {
				if k, v, ok := strings.Cut(f, "="); ok {
					step.args[k] = v
				} else {
					bare = append(bare, f)
				}
			}
			step.side = step.args["side"]
			delete(step.args, "side")
			switch word {
			case "config":
				for k, v := range step.args {
					fx.config[k] = v
				}
				continue
			case "only":
				if len(bare) != 1 || (bare[0] != "relay" && bare[0] != "runner") {
					fail("@only takes relay or runner")
				}
				fx.only = bare[0]
				continue
			case "do":
				if len(bare) != 1 {
					fail("@do takes one verb")
				}
				step.kind, step.verb = "do", bare[0]
			case "advance":
				if len(bare) != 1 {
					fail("@advance takes a duration")
				}
				d, err := time.ParseDuration(bare[0])
				if err != nil {
					fail("%v", err)
				}
				step.kind, step.dur = "advance", d
			case "closed":
				if len(bare) != 1 {
					fail("@closed takes a close code")
				}
				step.kind = "closed"
				step.code, err = strconv.Atoi(bare[0])
				if err != nil {
					fail("%v", err)
				}
			case "hangup", "quiet":
				step.kind = word
			default:
				fail("unknown directive @%s", word)
			}
		default:
			fail("a line starts with >, < or @, not %q", fields[0])
		}
		fx.steps = append(fx.steps, step)
	}
	return fx
}

func fixtureFiles(t testing.TB) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(fixtureDir, "*.frames"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no fixtures in %s: %v", fixtureDir, err)
	}
	sort.Strings(files)
	return files
}

// decodeSeeds is every message of every fixture, for FuzzDecode.
func decodeSeeds(t testing.TB) [][]byte {
	t.Helper()
	var seeds [][]byte
	for _, f := range fixtureFiles(t) {
		for _, st := range parseFixture(t, f).steps {
			if st.msg != nil {
				seeds = append(seeds, st.msg)
			}
		}
	}
	return seeds
}

func TestFixturesCoverEveryFrameTypeAndScenario(t *testing.T) {
	have := map[string]bool{}
	types := map[Type]bool{}
	for _, f := range fixtureFiles(t) {
		fx := parseFixture(t, f)
		have[fx.name] = true
		for _, st := range fx.steps {
			if len(st.msg) > 0 {
				types[Type(st.msg[0])] = true
			}
		}
	}
	for _, name := range requiredFixtures {
		if !have[name] {
			t.Errorf("fixtures/v1/tunnel/%s.frames is missing", name)
		}
	}
	for _, typ := range AllTypes {
		if !types[typ] {
			t.Errorf("no fixture has a %s frame", typ)
		}
	}
	// Each frame_<type> file holds the frame it is named for.
	for _, typ := range AllTypes {
		fx := parseFixture(t, filepath.Join(fixtureDir, "frame_"+strings.ToLower(typ.String())+".frames"))
		found := false
		for _, st := range fx.steps {
			if len(st.msg) > 0 && Type(st.msg[0]) == typ {
				found = true
			}
		}
		if !found {
			t.Errorf("frame_%s.frames has no %s frame", strings.ToLower(typ.String()), typ)
		}
	}
	// Every file is one the test knows: a stray file would never be required.
	known := map[string]bool{}
	for _, n := range requiredFixtures {
		known[n] = true
	}
	for name := range have {
		if !known[name] {
			t.Errorf("fixtures/v1/tunnel/%s.frames is not in requiredFixtures", name)
		}
	}
}

func TestFixtures(t *testing.T) {
	for _, f := range fixtureFiles(t) {
		fx := parseFixture(t, f)
		for _, role := range []Role{RoleRelay, RoleRunner} {
			name := "relay"
			if role == RoleRunner {
				name = "runner"
			}
			if fx.only != "" && fx.only != name {
				continue
			}
			t.Run(fx.name+"/"+name+" under test", func(t *testing.T) {
				runFixture(t, fx, role)
			})
		}
	}
}

type openResult struct {
	st  *Stream
	err error
}

type harness struct {
	t     *testing.T
	fx    fixture
	role  Role
	sess  *Session
	raw   *raw
	clock *FakeClock

	hsc       chan error
	hsDone    bool
	hsErr     error
	streams   map[uint32]*Stream
	opens     map[uint32]chan openResult
	openWant  map[uint32]string
	writes    map[uint32]chan error
	writeWant map[uint32]string
	nextID    uint32
}

func runFixture(t *testing.T, fx fixture, role Role) {
	cfg := Config{RunnerVersion: "1.0.0"}
	buffer := 64 // messages the connection holds before a write waits
	for k, v := range fx.config {
		n, err := strconv.Atoi(v)
		if err != nil {
			t.Fatalf("@config %s=%s: %v", k, v, err)
		}
		switch k {
		case "max_frame":
			cfg.MaxFrame = n
		case "max_streams":
			cfg.MaxStreams = n
		case "window":
			cfg.Window = n
		case "session_id":
			cfg.SessionID = int64(n)
		case "buffer":
			buffer = n
		default:
			t.Fatalf("@config %s is not known", k)
		}
	}
	h := &harness{
		t: t, fx: fx, role: role, clock: NewFakeClock(),
		streams: map[uint32]*Stream{}, opens: map[uint32]chan openResult{}, openWant: map[uint32]string{},
		writes: map[uint32]chan error{}, writeWant: map[uint32]string{}, hsc: make(chan error, 1),
	}
	cfg.Clock = h.clock
	a, b := newMemPair(buffer)
	if role == RoleRelay {
		h.sess = NewRelay(a, cfg)
	} else {
		h.sess = NewRunner(a, cfg)
	}
	h.raw = &raw{t: t, c: b, sess: h.sess}
	t.Cleanup(func() { h.sess.Close(); noLeaks(t) })
	go func() { h.hsc <- h.sess.Handshake(context.Background()) }()

	for _, st := range fx.steps {
		h.step(st)
	}
	h.waitHandshake()
	for id, ch := range h.opens {
		h.settleOpen(id, ch)
	}
	for id := range h.writes {
		h.settleWrite(id)
	}
	h.raw.expectQuiet()
}

func (h *harness) fatalf(st fxStep, format string, args ...any) {
	h.t.Helper()
	h.t.Fatalf("%s.frames:%d: %s", h.fx.name, st.line, fmt.Sprintf(format, args...))
}

func (h *harness) hasClosed() bool {
	for _, st := range h.fx.steps {
		if st.kind == "closed" {
			return true
		}
	}
	return false
}

func (h *harness) waitHandshake() {
	h.t.Helper()
	if h.hsDone {
		return
	}
	select {
	case h.hsErr = <-h.hsc:
		h.hsDone = true
	case <-time.After(wait):
		h.t.Fatalf("the handshake did not finish")
	}
	if h.hsErr != nil && !h.hasClosed() {
		h.t.Fatalf("handshake: %v", h.hsErr)
	}
}

func (h *harness) packageWrites(kind string) bool {
	return (kind == ">") == (h.role == RoleRelay)
}

func (h *harness) step(st fxStep) {
	h.t.Helper()
	if st.side != "" && st.side != h.roleName() {
		return
	}
	switch st.kind {
	case ">", "<":
		if h.packageWrites(st.kind) {
			ctx, cancel := context.WithTimeout(context.Background(), wait)
			defer cancel()
			got, err := h.raw.c.ReadMessage(ctx)
			if err != nil {
				h.fatalf(st, "expected %s, read: %v", showMsg(st.msg), err)
			}
			if !bytes.Equal(got, st.msg) {
				h.fatalf(st, "the %s wrote\n  %s\nwant\n  %s", h.roleName(), showMsg(got), showMsg(st.msg))
			}
			return
		}
		if len(st.msg) == 0 || Type(st.msg[0]) != TypeHello {
			h.waitHandshake()
		}
		before := h.sess.framesIn.Load()
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		defer cancel()
		if err := h.raw.c.WriteMessage(ctx, st.msg); err != nil {
			h.fatalf(st, "write: %v", err)
		}
		if h.hsDone {
			poll(h.t, "the session to handle the frame", func() bool {
				return h.sess.framesIn.Load() > before || isClosed(h.sess.ctx.Done())
			})
		}
	case "advance":
		h.waitHandshake()
		h.clock.Advance(st.dur)
	case "quiet":
		h.waitHandshake()
		h.raw.expectQuiet()
	case "hangup":
		h.waitHandshake()
		h.raw.c.Close(CloseNormal, "")
		select {
		case <-h.sess.Done():
		case <-time.After(wait):
			h.fatalf(st, "the session did not end after the hangup")
		}
	case "closed":
		h.waitHandshake()
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		defer cancel()
		msg, err := h.raw.c.ReadMessage(ctx)
		var ce *CloseError
		if !errors.As(err, &ce) {
			h.fatalf(st, "expected the connection to close with %d, got %x, %v", st.code, msg, err)
		}
		if ce.Code != st.code {
			h.fatalf(st, "closed with %d, want %d", ce.Code, st.code)
		}
	case "do":
		h.do(st)
	}
}

func (h *harness) roleName() string {
	if h.role == RoleRelay {
		return "relay"
	}
	return "runner"
}

func showMsg(b []byte) string {
	if len(b) > 48 {
		return hex.EncodeToString(b[:48]) + fmt.Sprintf("... (%d bytes)", len(b))
	}
	return hex.EncodeToString(b)
}

var defaultSide = map[string]string{"open": "relay", "goaway": "relay", "accept": "runner", "reject": "runner"}

func (h *harness) do(st fxStep) {
	h.t.Helper()
	side := st.side
	if side == "" {
		side = defaultSide[st.verb]
	}
	if side == "" {
		h.fatalf(st, "@do %s needs side=relay or side=runner", st.verb)
	}
	if side != h.roleName() {
		return // the other end: the file's lines drive it
	}
	h.waitHandshake()
	id := uint32(1)
	if v, ok := st.args["stream"]; ok {
		n, err := strconv.Atoi(v)
		if err != nil {
			h.fatalf(st, "stream=%s", v)
		}
		id = uint32(n)
	}
	num := func(key string) int {
		n, err := strconv.Atoi(st.args[key])
		if err != nil {
			h.fatalf(st, "%s=%q is not a number", key, st.args[key])
		}
		return n
	}
	switch st.verb {
	case "open":
		if want := st.args["err"]; want != "" {
			_, err := h.sess.Open(context.Background(), int64(num("session")), num("port"))
			target := map[string]error{"limit": ErrStreamLimit, "goaway": ErrGoAway}[want]
			if target == nil || !errors.Is(err, target) {
				h.fatalf(st, "Open = %v, want %s", err, want)
			}
			return
		}
		h.nextID++
		id = h.nextID
		ch := make(chan openResult, 1)
		h.opens[id] = ch
		h.openWant[id] = st.args["reset"]
		go func() {
			s, err := h.sess.Open(context.Background(), int64(num("session")), num("port"))
			ch <- openResult{s, err}
		}()
		poll(h.t, "Open to take its stream id", func() bool {
			h.sess.mu.Lock()
			defer h.sess.mu.Unlock()
			return h.sess.lastID >= id
		})
	case "accept", "reject":
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		defer cancel()
		in, err := h.sess.Accept(ctx)
		if want := st.args["err"]; want != "" {
			if want != "goaway" || !errors.Is(err, ErrGoAway) {
				h.fatalf(st, "Accept = %v, want goaway", err)
			}
			return
		}
		if err != nil {
			h.fatalf(st, "Accept: %v", err)
		}
		if v, ok := st.args["session"]; ok && in.SessionID != int64(num("session")) {
			h.fatalf(st, "session_id %d, want %s", in.SessionID, v)
		}
		if v, ok := st.args["port"]; ok && in.Port != num("port") {
			h.fatalf(st, "port %d, want %s", in.Port, v)
		}
		if st.verb == "reject" {
			code, ok := ParseResetCode(st.args["code"])
			if !ok {
				h.fatalf(st, "code=%q", st.args["code"])
			}
			if err := in.Reject(code, st.args["text"]); err != nil {
				h.fatalf(st, "Reject: %v", err)
			}
			return
		}
		stream, err := in.Accept()
		if want := st.args["reset"]; want != "" {
			h.expectReset(st, err, want)
			return
		}
		if err != nil {
			h.fatalf(st, "Incoming.Accept: %v", err)
		}
		h.streams[stream.ID()] = stream
	case "write":
		data, err := parseHexTokens([]string{st.args["data"]})
		if err != nil {
			h.fatalf(st, "%v", err)
		}
		s := h.stream(st, id)
		if prev := h.writes[id]; prev != nil {
			h.settleWrite(id)
		}
		ch := make(chan error, 1)
		h.writes[id], h.writeWant[id] = ch, st.args["reset"]
		go func() { _, err := s.Write(data); ch <- err }()
		poll(h.t, "the writer to take the first frame", func() bool {
			h.sess.mu.Lock()
			defer h.sess.mu.Unlock()
			return s.taken > 0 || s.finished
		})
	case "read":
		s := h.stream(st, id)
		h.read(st, s)
	case "closewrite":
		if err := h.stream(st, id).CloseWrite(); err != nil {
			h.fatalf(st, "CloseWrite: %v", err)
		}
	case "close":
		if err := h.stream(st, id).Close(); err != nil {
			h.fatalf(st, "Close: %v", err)
		}
	case "reset":
		code, ok := ParseResetCode(st.args["code"])
		if !ok {
			h.fatalf(st, "code=%q", st.args["code"])
		}
		h.stream(st, id).Reset(code, st.args["text"])
	case "goaway":
		if err := h.sess.GoAway(); err != nil {
			h.fatalf(st, "GoAway: %v", err)
		}
	default:
		h.fatalf(st, "@do %s is not a verb", st.verb)
	}
}

func (h *harness) expectReset(st fxStep, err error, name string) {
	h.t.Helper()
	var re *ResetError
	want, _ := ParseResetCode(name)
	if !errors.As(err, &re) || re.Code != want {
		h.fatalf(st, "got %v, want a reset with %s", err, name)
	}
}

func (h *harness) stream(st fxStep, id uint32) *Stream {
	h.t.Helper()
	if ch := h.opens[id]; ch != nil {
		h.settleOpen(id, ch)
	}
	s := h.streams[id]
	if s == nil {
		h.fatalf(st, "stream %d is not open", id)
	}
	return s
}

func (h *harness) settleOpen(id uint32, ch chan openResult) {
	h.t.Helper()
	select {
	case r := <-ch:
		delete(h.opens, id)
		want := h.openWant[id]
		if want != "" {
			h.expectReset(fxStep{}, r.err, want)
			return
		}
		if r.err != nil {
			h.t.Fatalf("%s: Open of stream %d: %v", h.fx.name, id, r.err)
		}
		h.streams[id] = r.st
	case <-time.After(wait):
		h.t.Fatalf("%s: Open of stream %d did not return", h.fx.name, id)
	}
}

func (h *harness) settleWrite(id uint32) {
	h.t.Helper()
	ch := h.writes[id]
	select {
	case err := <-ch:
		delete(h.writes, id)
		if want := h.writeWant[id]; want != "" {
			h.expectReset(fxStep{}, err, want)
		} else if err != nil {
			h.t.Fatalf("%s: Write on stream %d: %v", h.fx.name, id, err)
		}
	case <-time.After(wait):
		h.t.Fatalf("%s: Write on stream %d did not return", h.fx.name, id)
	}
}

func (h *harness) read(st fxStep, s *Stream) {
	h.t.Helper()
	type res struct {
		data []byte
		err  error
	}
	ch := make(chan res, 1)
	var want []byte
	if v, ok := st.args["data"]; ok {
		var err error
		if want, err = parseHexTokens([]string{v}); err != nil {
			h.fatalf(st, "%v", err)
		}
	}
	go func() {
		if st.args["data"] != "" {
			buf := make([]byte, len(want))
			_, err := io.ReadFull(s, buf)
			ch <- res{buf, err}
			return
		}
		data, err := io.ReadAll(s)
		ch <- res{data, err}
	}()
	var r res
	select {
	case r = <-ch:
	case <-time.After(wait):
		h.fatalf(st, "read did not return")
	}
	switch {
	case st.args["data"] != "":
		if r.err != nil || !bytes.Equal(r.data, want) {
			h.fatalf(st, "read %s, %v; want %s", showMsg(r.data), r.err, showMsg(want))
		}
	case st.args["eof"] != "":
		if r.err != nil || len(r.data) != 0 {
			h.fatalf(st, "read to EOF gave %s, %v", showMsg(r.data), r.err)
		}
	case st.args["reset"] != "":
		h.expectReset(st, r.err, st.args["reset"])
	case st.args["closed"] != "":
		if !errors.Is(r.err, ErrSessionClosed) {
			h.fatalf(st, "read gave %v, want ErrSessionClosed", r.err)
		}
	default:
		h.fatalf(st, "@do read needs data=, eof=, reset= or closed=")
	}
}
