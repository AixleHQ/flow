package tunnel

import (
	"context"
	"net"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"
)

const wait = 3 * time.Second

// memConn is one end of an in-memory Conn pair.
type memConn struct {
	in     chan []byte
	out    chan []byte
	closed chan struct{}
	peer   *memConn

	mu     sync.Mutex
	code   int
	reason string
	once   sync.Once
}

// newMemPair makes two connected ends. buf is the number of messages a writer can
// leave unread; 0 makes every write wait for the read.
func newMemPair(buf int) (*memConn, *memConn) {
	ab, ba := make(chan []byte, buf), make(chan []byte, buf)
	a := &memConn{in: ba, out: ab, closed: make(chan struct{})}
	b := &memConn{in: ab, out: ba, closed: make(chan struct{})}
	a.peer, b.peer = b, a
	return a, b
}

func (c *memConn) ReadMessage(ctx context.Context) ([]byte, error) {
	select {
	case m := <-c.in:
		return m, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-c.closed:
		return nil, net.ErrClosed
	case <-c.peer.closed:
		select {
		case m := <-c.in:
			return m, nil
		default:
		}
		code, reason := c.peer.closeInfo()
		return nil, &CloseError{Code: code, Reason: reason}
	}
}

func (c *memConn) WriteMessage(ctx context.Context, msg []byte) error {
	msg = append([]byte(nil), msg...)
	select {
	case c.out <- msg:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-c.closed:
		return net.ErrClosed
	case <-c.peer.closed:
		return net.ErrClosed
	}
}

func (c *memConn) Close(code int, reason string) error {
	c.once.Do(func() {
		c.mu.Lock()
		c.code, c.reason = code, reason
		c.mu.Unlock()
		close(c.closed)
	})
	return nil
}

func (c *memConn) closeInfo() (int, string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.code, c.reason
}

// poll waits until cond holds.
func poll(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(wait)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(time.Millisecond)
	}
}

// goroutinesLeft lists the goroutines of the package that are still running, apart
// from the test's own.
func goroutinesLeft() []string {
	buf := make([]byte, 1<<20)
	buf = buf[:runtime.Stack(buf, true)]
	var left []string
	for _, g := range strings.Split(string(buf), "\n\n") {
		if strings.Contains(g, "protocol/tunnel.") && !strings.Contains(g, "testing.tRunner") &&
			!strings.Contains(g, "testing.(*T).Run") && !strings.Contains(g, "runtime.Stack") {
			left = append(left, g)
		}
	}
	return left
}

// noLeaks fails the test if a goroutine of the package outlives it.
func noLeaks(t *testing.T) {
	t.Helper()
	deadline := time.Now().Add(wait)
	for {
		left := goroutinesLeft()
		if len(left) == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("goroutines of the package are left:\n%s", strings.Join(left, "\n\n"))
		}
		time.Sleep(time.Millisecond)
	}
}

// pair is two sessions over a memConn pair and one fake clock.
type pair struct {
	t      *testing.T
	clock  *FakeClock
	relay  *Session
	runner *Session
}

func newPair(t *testing.T, relayCfg, runnerCfg Config) *pair {
	t.Helper()
	clock := NewFakeClock()
	relayCfg.Clock, runnerCfg.Clock = clock, clock
	a, b := newMemPair(8)
	p := &pair{t: t, clock: clock, relay: NewRelay(a, relayCfg), runner: NewRunner(b, runnerCfg)}
	errc := make(chan error, 2)
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	go func() { errc <- p.relay.Handshake(ctx) }()
	go func() { errc <- p.runner.Handshake(ctx) }()
	for i := 0; i < 2; i++ {
		if err := <-errc; err != nil {
			t.Fatalf("handshake: %v", err)
		}
	}
	t.Cleanup(func() {
		p.relay.Close()
		p.runner.Close()
		noLeaks(t)
	})
	return p
}

// open opens a stream from the relay and accepts it on the runner.
func (p *pair) open(session int64, port int) (relay, runner *Stream) {
	p.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	type res struct {
		st  *Stream
		err error
	}
	rc := make(chan res, 1)
	go func() {
		st, err := p.relay.Open(ctx, session, port)
		rc <- res{st, err}
	}()
	in, err := p.runner.Accept(ctx)
	if err != nil {
		p.t.Fatalf("Accept: %v", err)
	}
	if in.SessionID != session || in.Port != port {
		p.t.Fatalf("Incoming = %d:%d, want %d:%d", in.SessionID, in.Port, session, port)
	}
	rs, err := in.Accept()
	if err != nil {
		p.t.Fatalf("Incoming.Accept: %v", err)
	}
	r := <-rc
	if r.err != nil {
		p.t.Fatalf("Open: %v", r.err)
	}
	return r.st, rs
}

// raw is the other end of a session under test, played by the test.
type raw struct {
	t    *testing.T
	c    *memConn
	sess *Session
}

func (r *raw) send(f Frame) {
	r.t.Helper()
	before := r.sess.framesIn.Load()
	r.sendNoWait(f)
	poll(r.t, "the session to handle "+f.Type.String(), func() bool {
		return r.sess.framesIn.Load() > before || isClosed(r.sess.ctx.Done())
	})
}

func (r *raw) sendNoWait(f Frame) {
	r.t.Helper()
	msg, err := Encode(f)
	if err != nil {
		r.t.Fatalf("Encode: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	if err := r.c.WriteMessage(ctx, msg); err != nil {
		r.t.Fatalf("write %s: %v", f.Type, err)
	}
}

func (r *raw) read() Frame {
	r.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	msg, err := r.c.ReadMessage(ctx)
	if err != nil {
		r.t.Fatalf("read: %v", err)
	}
	f, err := Decode(msg)
	if err != nil {
		r.t.Fatalf("Decode: %v", err)
	}
	return f
}

func (r *raw) expect(typ Type, stream uint32) Frame {
	r.t.Helper()
	f := r.read()
	if f.Type != typ || f.Stream != stream {
		r.t.Fatalf("got %s on stream %d (%x), want %s on stream %d", f.Type, f.Stream, f.Payload, typ, stream)
	}
	return f
}

func (r *raw) expectReset(stream uint32, code ResetCode) {
	r.t.Helper()
	f := r.expect(TypeReset, stream)
	if got, _ := f.Reset(); got != code {
		r.t.Fatalf("RESET %s, want %s", got, code)
	}
}

func (r *raw) expectClosed(code int) {
	r.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	for {
		_, err := r.c.ReadMessage(ctx)
		if err == nil {
			continue
		}
		ce, ok := err.(*CloseError)
		if !ok || ce.Code != code {
			r.t.Fatalf("connection ended with %v, want close code %d", err, code)
		}
		return
	}
}

// expectQuiet fails if the session writes anything in a short real interval.
func (r *raw) expectQuiet() {
	r.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if msg, err := r.c.ReadMessage(ctx); err == nil {
		r.t.Fatalf("unexpected message %x", msg)
	}
}

func i64(v int64) *int64 { return &v }

// relayVsRaw starts a relay session against a raw runner, the handshake done.
func relayVsRaw(t *testing.T, cfg Config, answer Hello, buf int) (*Session, *raw, *FakeClock) {
	t.Helper()
	clock := NewFakeClock()
	cfg.Clock = clock
	a, b := newMemPair(buf)
	s := NewRelay(a, cfg)
	r := &raw{t: t, c: b, sess: s}
	t.Cleanup(func() { s.Close(); noLeaks(t) })
	errc := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		defer cancel()
		errc <- s.Handshake(ctx)
	}()
	r.expect(TypeHello, 0)
	if answer.V == 0 {
		answer.V = 1
	}
	r.sendNoWait(answer.Frame(false))
	if err := <-errc; err != nil {
		t.Fatalf("Handshake: %v", err)
	}
	return s, r, clock
}

// runnerVsRaw starts a runner session against a raw relay, the handshake done.
func runnerVsRaw(t *testing.T, cfg Config, hello Hello, buf int) (*Session, *raw, *FakeClock) {
	t.Helper()
	clock := NewFakeClock()
	cfg.Clock = clock
	a, b := newMemPair(buf)
	s := NewRunner(a, cfg)
	r := &raw{t: t, c: b, sess: s}
	t.Cleanup(func() { s.Close(); noLeaks(t) })
	errc := make(chan error, 1)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), wait)
		defer cancel()
		errc <- s.Handshake(ctx)
	}()
	if hello.V == 0 {
		hello.V = 1
	}
	r.sendNoWait(hello.Frame(true))
	r.expect(TypeHello, 0)
	if err := <-errc; err != nil {
		t.Fatalf("Handshake: %v", err)
	}
	return s, r, clock
}

var (
	stdAnswer = Hello{MaxFrame: DefaultMaxFrame, MaxStreams: DefaultMaxStreams, Window: DefaultWindow, RunnerVersion: "1.0.0"}
	stdHello  = Hello{MaxFrame: DefaultMaxFrame, MaxStreams: DefaultMaxStreams, Window: DefaultWindow, PingInterval: 20}
)
