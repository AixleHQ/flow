package tunnel

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func readN(t *testing.T, st *Stream, n int) []byte {
	t.Helper()
	type res struct {
		buf []byte
		err error
	}
	rc := make(chan res, 1)
	go func() {
		buf := make([]byte, n)
		_, err := io.ReadFull(st, buf)
		rc <- res{buf, err}
	}()
	select {
	case r := <-rc:
		if r.err != nil {
			t.Fatalf("read %d bytes: %v", n, r.err)
		}
		return r.buf
	case <-time.After(wait):
		t.Fatalf("read %d bytes: timed out", n)
		return nil
	}
}

// readErr reads one byte and returns the error, which a test expects.
func readErr(t *testing.T, st *Stream) error {
	t.Helper()
	rc := make(chan error, 1)
	go func() { _, err := st.Read(make([]byte, 1)); rc <- err }()
	select {
	case err := <-rc:
		return err
	case <-time.After(wait):
		t.Fatal("Read did not return")
		return nil
	}
}

func write(t *testing.T, st *Stream, s string) {
	t.Helper()
	if n, err := st.Write([]byte(s)); err != nil || n != len(s) {
		t.Fatalf("Write = %d, %v", n, err)
	}
}

func TestOpenAndDataBothWays(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(123, 7681)
	write(t, rs, "hello runner")
	if got := readN(t, ns, 12); string(got) != "hello runner" {
		t.Fatalf("runner read %q", got)
	}
	write(t, ns, "hello relay")
	if got := readN(t, rs, 11); string(got) != "hello relay" {
		t.Fatalf("relay read %q", got)
	}
	if rs.ID() != 1 {
		t.Fatalf("first stream id = %d", rs.ID())
	}
	rs2, _ := p.open(123, 4040)
	if rs2.ID() != 2 {
		t.Fatalf("second stream id = %d, want 2", rs2.ID())
	}
}

func TestLargeTransferIsFramedWithinMaxFrame(t *testing.T) {
	p := newPair(t, Config{MaxFrame: 1024, Window: 4096}, Config{})
	rs, ns := p.open(1, 1)
	data := make([]byte, 100_000)
	for i := range data {
		data[i] = byte(i * 7)
	}
	go func() { rs.Write(data); rs.CloseWrite() }()
	got, err := io.ReadAll(ns)
	if err != nil || len(got) != len(data) {
		t.Fatalf("ReadAll = %d bytes, %v", len(got), err)
	}
	for i := range got {
		if got[i] != data[i] {
			t.Fatalf("byte %d differs", i)
		}
	}
}

func TestHalfCloseRelayFirst(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 80)
	write(t, rs, "request")
	if err := rs.CloseWrite(); err != nil {
		t.Fatal(err)
	}
	if got, err := io.ReadAll(ns); err != nil || string(got) != "request" {
		t.Fatalf("runner ReadAll = %q, %v", got, err)
	}
	write(t, ns, "response") // the runner may keep sending after the relay's CLOSE
	ns.CloseWrite()
	if got, err := io.ReadAll(rs); err != nil || string(got) != "response" {
		t.Fatalf("relay ReadAll = %q, %v", got, err)
	}
	if _, err := rs.Write([]byte("x")); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Write after CloseWrite = %v", err)
	}
	poll(t, "both sessions to drop the stream", func() bool {
		p.relay.mu.Lock()
		defer p.relay.mu.Unlock()
		p.runner.mu.Lock()
		defer p.runner.mu.Unlock()
		return len(p.relay.streams) == 0 && len(p.runner.streams) == 0
	})
}

func TestHalfCloseRunnerFirst(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 80)
	write(t, ns, "banner")
	ns.CloseWrite()
	if got, err := io.ReadAll(rs); err != nil || string(got) != "banner" {
		t.Fatalf("relay ReadAll = %q, %v", got, err)
	}
	write(t, rs, "late")
	rs.CloseWrite()
	if got, err := io.ReadAll(ns); err != nil || string(got) != "late" {
		t.Fatalf("runner ReadAll = %q, %v", got, err)
	}
}

func TestCloseIsAFullClose(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 80)
	if err := rs.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := rs.Read(make([]byte, 1)); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("Read after Close = %v", err)
	}
	// The peer saw CLOSE and then RESET cancelled: a Read between the two frames
	// may see the end of file, and once the second arrives it sees the reset.
	poll(t, "the RESET to arrive", func() bool { return ns.Err() != nil })
	err := readErr(t, ns)
	var re *ResetError
	if !errors.As(err, &re) || re.Code != ResetCancelled {
		t.Fatalf("peer Read = %v, want RESET cancelled", err)
	}
	if err := rs.Close(); !errors.Is(err, net.ErrClosed) {
		t.Fatalf("second Close = %v", err)
	}
}

func TestCloseAfterPeerCloseSendsNoReset(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 80)
	ns.CloseWrite()
	if _, err := rs.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("Read = %v, want EOF", err)
	}
	rs.Close()
	if _, err := ns.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("peer Read = %v, want EOF: the stream ended by two CLOSEs, not by a reset", err)
	}
}

func TestResetWhileDataIsInFlight(t *testing.T) {
	for _, side := range []string{"relay", "runner"} {
		t.Run(side+" resets", func(t *testing.T) {
			p := newPair(t, Config{MaxFrame: 1024, Window: 2048}, Config{})
			rs, ns := p.open(1, 80)
			resetter, other := rs, ns
			if side == "runner" {
				resetter, other = ns, rs
			}
			// The other side has more to send than the window: its Write is blocked
			// with DATA on the wire when the reset arrives.
			werr := make(chan error, 1)
			go func() { _, err := other.Write(make([]byte, 10_000)); werr <- err }()
			readN(t, resetter, 1024) // some of it arrived
			resetter.Reset(ResetInternal, "boom")
			var re *ResetError
			if err := <-werr; !errors.As(err, &re) || re.Code != ResetInternal || re.Text != "boom" {
				t.Fatalf("blocked Write = %v, want the reset", err)
			}
			if _, err := resetter.Read(make([]byte, 1)); !errors.As(err, &re) || re.Code != ResetInternal {
				t.Fatalf("Read on the resetting side = %v", err)
			}
			if _, err := other.Read(make([]byte, 1)); !errors.As(err, &re) || re.Code != ResetInternal {
				t.Fatalf("Read on the other side = %v", err)
			}
			// The session is fine, and the id is not reused.
			rs2, ns2 := p.open(1, 80)
			write(t, rs2, "ok")
			readN(t, ns2, 2)
			if rs2.ID() != 2 {
				t.Fatalf("id = %d", rs2.ID())
			}
		})
	}
}

func TestDataForAResetStreamIsDropped(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
	st := openRaw(t, s, r, 1)
	st.Reset(ResetCancelled, "")
	r.expectReset(1, ResetCancelled)
	// The runner's DATA, WINDOW, CLOSE and RESET were in flight: none is an error.
	r.send(Frame{Type: TypeData, Stream: 1, Payload: []byte("late")})
	r.send(WindowFrame(1, 10))
	r.send(Frame{Type: TypeClose, Stream: 1})
	r.send(ResetFrame(1, ResetInternal, ""))
	if err := s.Err(); err != nil {
		t.Fatalf("session ended: %v", err)
	}
}

// openRaw opens stream id against a raw runner and answers OPEN_OK.
func openRaw(t *testing.T, s *Session, r *raw, id uint32) *Stream {
	t.Helper()
	type res struct {
		st  *Stream
		err error
	}
	rc := make(chan res, 1)
	go func() {
		st, err := s.Open(context.Background(), 5, 7681)
		rc <- res{st, err}
	}()
	f := r.expect(TypeOpen, id)
	if o, _ := f.Open(); o.SessionID != 5 || o.Port != 7681 {
		t.Fatalf("OPEN = %+v", o)
	}
	r.send(Frame{Type: TypeOpenOK, Stream: id})
	got := <-rc
	if got.err != nil {
		t.Fatalf("Open: %v", got.err)
	}
	return got.st
}

func TestFlowControlBlocksAtZeroCreditAndWindowReleases(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 2048}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 2048, RunnerVersion: "1"}, 8)
	st := openRaw(t, s, r, 1)
	done := make(chan error, 1)
	go func() { _, err := st.Write(make([]byte, 4096)); done <- err }()
	r.expect(TypeData, 1)
	r.expect(TypeData, 1)
	r.expectQuiet() // two windows' worth... the credit is spent
	select {
	case err := <-done:
		t.Fatalf("Write returned with no credit: %v", err)
	default:
	}
	r.send(WindowFrame(1, 2048))
	r.expect(TypeData, 1)
	r.expect(TypeData, 1)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestFlowControlReceiverOwesWindowAtHalf(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 2048}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 2048, RunnerVersion: "1"}, 8)
	st := openRaw(t, s, r, 1)
	r.send(Frame{Type: TypeData, Stream: 1, Payload: make([]byte, 1024)})
	readN(t, st, 512) // a quarter of the window: nothing owed yet
	r.expectQuiet()
	readN(t, st, 512) // half the window is owed
	f := r.expect(TypeWindow, 1)
	if f.Credit() != 1024 {
		t.Fatalf("WINDOW %d, want 1024", f.Credit())
	}
}

func TestDataOverTheCreditResetsWithFlowViolation(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 2048}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 2048, RunnerVersion: "1"}, 8)
	st := openRaw(t, s, r, 1)
	r.send(Frame{Type: TypeData, Stream: 1, Payload: make([]byte, 1024)})
	r.send(Frame{Type: TypeData, Stream: 1, Payload: make([]byte, 1024)})
	r.send(Frame{Type: TypeData, Stream: 1, Payload: []byte{1}}) // one byte over the window
	r.expectReset(1, ResetFlowViolation)
	var re *ResetError
	if _, err := st.Read(make([]byte, 1)); !errors.As(err, &re) || re.Code != ResetFlowViolation {
		t.Fatalf("Read = %v", err)
	}
	if s.Err() != nil {
		t.Fatalf("a flow violation ends the stream, not the session: %v", s.Err())
	}
}

func TestWindowOverTheWindowResetsWithFlowViolation(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 2048}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 2048, RunnerVersion: "1"}, 8)
	st := openRaw(t, s, r, 1)
	r.send(WindowFrame(1, 1)) // the credit is full already
	r.expectReset(1, ResetFlowViolation)
	var re *ResetError
	if _, err := st.Write([]byte("x")); !errors.As(err, &re) || re.Code != ResetFlowViolation {
		t.Fatalf("Write = %v", err)
	}
}

func TestDataBeforeOpenOKAndAfterCloseAreProtocolResets(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
	go s.Open(context.Background(), 5, 1)
	r.expect(TypeOpen, 1)
	r.send(Frame{Type: TypeData, Stream: 1, Payload: []byte("x")})
	r.expectReset(1, ResetProtocol)

	st := openRaw2(t, s, r, 2)
	r.send(Frame{Type: TypeClose, Stream: 2})
	r.send(Frame{Type: TypeData, Stream: 2, Payload: []byte("x")})
	r.expectReset(2, ResetProtocol)
	if _, err := st.Read(make([]byte, 1)); err == nil {
		t.Fatal("Read succeeded on a reset stream")
	}
}

func openRaw2(t *testing.T, s *Session, r *raw, id uint32) *Stream { return openRaw(t, s, r, id) }

func TestDataOverMaxFrameClosesWith1009(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 4096}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 4096, RunnerVersion: "1"}, 8)
	openRaw(t, s, r, 1)
	r.sendNoWait(Frame{Type: TypeData, Stream: 1, Payload: make([]byte, 1025)})
	r.expectClosed(CloseTooLarge)
}

func TestStreamCapOnTheRelay(t *testing.T) {
	p := newPair(t, Config{MaxStreams: 2}, Config{})
	a, _ := p.open(1, 1)
	p.open(1, 2)
	if _, err := p.relay.Open(context.Background(), 1, 3); !errors.Is(err, ErrStreamLimit) {
		t.Fatalf("third Open = %v, want ErrStreamLimit", err)
	}
	// Nothing was sent: the runner has two streams, and its next Accept waits.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if in, err := p.runner.Accept(ctx); err == nil {
		t.Fatalf("the runner got an OPEN: %+v", in)
	}
	a.Reset(ResetCancelled, "")
	poll(t, "the slot to free", func() bool {
		p.relay.mu.Lock()
		defer p.relay.mu.Unlock()
		return len(p.relay.streams) == 1
	})
	p.open(1, 3) // the slot is free again
}

func TestStreamCapOnTheRunner(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{MaxStreams: 2}, Hello{MaxFrame: 32768, MaxStreams: 64, Window: DefaultWindow, PingInterval: 20}, 8)
	for id := uint32(1); id <= 3; id++ {
		r.send(OpenFrame(id, Open{SessionID: 1, Port: 7681}))
	}
	r.expectReset(3, ResetRefused) // the third is answered at once and never reaches Accept
	for id := uint32(1); id <= 2; id++ {
		in, err := s.Accept(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if _, err := in.Accept(); err != nil {
			t.Fatal(err)
		}
		r.expect(TypeOpenOK, id)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if in, err := s.Accept(ctx); err == nil {
		t.Fatalf("Accept returned the refused OPEN: %+v", in)
	}
	// A reset frees the slot.
	r.send(ResetFrame(1, ResetCancelled, ""))
	r.send(OpenFrame(4, Open{SessionID: 1, Port: 7681}))
	in, err := s.Accept(context.Background())
	if err != nil || in.Port != 7681 {
		t.Fatalf("Accept = %+v, %v", in, err)
	}
}

func TestRunnerRefusesOpenWithAnOldIDOrAnIDInUse(t *testing.T) {
	for _, ids := range [][]uint32{{2, 1}, {1, 1}} {
		s, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
		r.send(OpenFrame(ids[0], Open{SessionID: 1, Port: 1}))
		r.sendNoWait(OpenFrame(ids[1], Open{SessionID: 1, Port: 1}))
		r.expectClosed(CloseProtocol)
		<-s.Done()
	}
}

func TestOpenTimeout(t *testing.T) {
	s, r, clock := relayVsRaw(t, Config{}, stdAnswer, 8)
	errc := make(chan error, 1)
	go func() { _, err := s.Open(context.Background(), 5, 7681); errc <- err }()
	r.expect(TypeOpen, 1)
	clock.Advance(DefaultOpenTimeout - time.Second)
	r.expectQuiet()
	clock.Advance(time.Second)
	r.expectReset(1, ResetTimeout)
	var re *ResetError
	if err := <-errc; !errors.As(err, &re) || re.Code != ResetTimeout {
		t.Fatalf("Open = %v, want RESET timeout", err)
	}
	// An OPEN_OK that crosses the RESET is dropped.
	r.send(Frame{Type: TypeOpenOK, Stream: 1})
	if s.Err() != nil {
		t.Fatal(s.Err())
	}
}

func TestOpenContextCancelled(t *testing.T) {
	s, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
	ctx, cancel := context.WithCancel(context.Background())
	errc := make(chan error, 1)
	go func() { _, err := s.Open(ctx, 5, 7681); errc <- err }()
	r.expect(TypeOpen, 1)
	cancel()
	if err := <-errc; !errors.Is(err, context.Canceled) {
		t.Fatalf("Open = %v", err)
	}
	r.expectReset(1, ResetCancelled)
}

func TestRunnerRefusesTheOpen(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	errc := make(chan error, 1)
	go func() { _, err := p.relay.Open(context.Background(), 5, 22); errc <- err }()
	in, err := p.runner.Accept(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if err := in.Reject(ResetRefused, "not a session port"); err != nil {
		t.Fatal(err)
	}
	var re *ResetError
	if err := <-errc; !errors.As(err, &re) || re.Code != ResetRefused || re.Text != "not a session port" {
		t.Fatalf("Open = %v", err)
	}
}

func TestIncomingResetBeforeAccept(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
	r.send(OpenFrame(1, Open{SessionID: 1, Port: 1}))
	in, err := s.Accept(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	r.send(ResetFrame(1, ResetTimeout, ""))
	var re *ResetError
	if _, err := in.Accept(); !errors.As(err, &re) || re.Code != ResetTimeout {
		t.Fatalf("Accept = %v", err)
	}
}

func TestFairnessControlFramesWaitForOneDataFrameAtMost(t *testing.T) {
	// A rendezvous connection: the writer holds one frame at a time, blocked until
	// the test reads it, so the order of the messages is the order the writer chose.
	s, r, _ := relayVsRaw(t, Config{MaxFrame: 1024, Window: 65536}, Hello{MaxFrame: 1024, MaxStreams: 64, Window: 65536, RunnerVersion: "1"}, 0)
	a := openRaw(t, s, r, 1)
	b := openRaw(t, s, r, 2)
	go a.Write(make([]byte, 50_000)) // a busy stream: 49 frames
	poll(t, "the writer to hold the first frame of stream 1", func() bool {
		s.mu.Lock()
		defer s.mu.Unlock()
		return a.taken > 0
	})
	go b.Write([]byte("k")) // a keystroke on another stream
	poll(t, "both streams to be in the ring", func() bool {
		s.mu.Lock()
		defer s.mu.Unlock()
		return len(s.wq.ready) == 2
	})
	r.send(Frame{Type: TypePing, Payload: make([]byte, 8)}) // the PONG is queued

	f := r.read()
	if f.Type != TypeData || f.Stream != 1 {
		t.Fatalf("first: %s on stream %d, want the DATA frame the writer held", f.Type, f.Stream)
	}
	r.expect(TypePong, 0) // a control frame waited for one DATA frame
	f = r.read()
	if f.Type != TypeData || f.Stream != 1 {
		t.Fatalf("third: %s on stream %d, want stream 1's turn", f.Type, f.Stream)
	}
	f = r.expect(TypeData, 2) // the keystroke waited for one frame of the busy stream
	if string(f.Payload) != "k" {
		t.Fatalf("payload %q", f.Payload)
	}
	r.expect(TypeData, 1) // and the busy stream goes on
}

func TestHeartbeat(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	seen := func() uint64 { return p.runner.framesIn.Load() }
	for i := 1; i <= 5; i++ {
		before := seen()
		p.clock.Advance(DefaultPingInterval)
		poll(t, "the PING to arrive", func() bool { return seen() > before })
		// The PONG reaches the relay, which counts it as silence ended.
		poll(t, "the PONG to arrive", func() bool { return p.relay.framesIn.Load() >= uint64(i) })
	}
	if p.relay.Err() != nil || p.runner.Err() != nil {
		t.Fatalf("a live connection closed: %v %v", p.relay.Err(), p.runner.Err())
	}
}

func TestHeartbeatClosesAfterThreeSilentIntervals(t *testing.T) {
	s, r, clock := relayVsRaw(t, Config{}, stdAnswer, 8)
	for i := 1; i <= 2; i++ {
		clock.Advance(DefaultPingInterval)
		f := r.expect(TypePing, 0)
		if got := f.Payload[7]; got != byte(i) {
			t.Fatalf("PING payload %x", f.Payload)
		}
	}
	clock.Advance(DefaultPingInterval - time.Nanosecond)
	if s.Err() != nil {
		t.Fatal("closed before the third interval")
	}
	clock.Advance(time.Nanosecond)
	<-s.Done()
	if !errors.Is(s.Err(), ErrHeartbeat) {
		t.Fatalf("Err = %v", s.Err())
	}
	r.expectClosed(CloseNormal)
}

func TestAnyFrameResetsTheSilence(t *testing.T) {
	s, r, clock := relayVsRaw(t, Config{}, stdAnswer, 8)
	for i := 0; i < 6; i++ {
		clock.Advance(DefaultPingInterval)
		r.expect(TypePing, 0)
		r.send(Frame{Type: TypePong, Payload: make([]byte, 8)})
	}
	if s.Err() != nil {
		t.Fatalf("Err = %v", s.Err())
	}
}

func TestRunnerPingsAfterAnIntervalOfSilence(t *testing.T) {
	s, r, clock := runnerVsRaw(t, Config{}, stdHello, 8)
	clock.Advance(DefaultPingInterval)
	r.expectQuiet() // it heard nothing for exactly one interval: not yet more than one
	clock.Advance(DefaultPingInterval)
	r.expect(TypePing, 0)
	r.send(Frame{Type: TypePing, Payload: make([]byte, 8)})
	r.expect(TypePong, 0)
	clock.Advance(DefaultPingInterval)
	r.expectQuiet() // heard the relay's PING an interval ago
	clock.Advance(2 * DefaultPingInterval)
	<-s.Done()
	if !errors.Is(s.Err(), ErrHeartbeat) {
		t.Fatalf("Err = %v", s.Err())
	}
}

func TestPongEchoesPing(t *testing.T) {
	_, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
	payload := []byte{1, 2, 3, 4, 5, 6, 7, 8}
	r.send(Frame{Type: TypePing, Payload: payload})
	f := r.expect(TypePong, 0)
	if string(f.Payload) != string(payload) {
		t.Fatalf("PONG payload %x", f.Payload)
	}
}

func TestGoAwayDrain(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 80)
	if err := p.relay.GoAway(); err != nil {
		t.Fatal(err)
	}
	if _, err := p.relay.Open(context.Background(), 1, 80); !errors.Is(err, ErrGoAway) {
		t.Fatalf("Open after GoAway = %v", err)
	}
	// The open stream still works.
	write(t, rs, "still here")
	readN(t, ns, 10)
	write(t, ns, "ack")
	readN(t, rs, 3)
	// The runner sees the GOAWAY: no OPEN is waiting, so Accept says so.
	if _, err := p.runner.Accept(context.Background()); !errors.Is(err, ErrGoAway) {
		t.Fatalf("Accept = %v", err)
	}
	select {
	case <-p.relay.Done():
		t.Fatal("the connection closed with a stream open")
	default:
	}
	rs.Close()
	ns.Close()
	<-p.relay.Done()
	if !errors.Is(p.relay.Err(), ErrGoAway) {
		t.Fatalf("relay Err = %v", p.relay.Err())
	}
	<-p.runner.Done() // the runner saw the connection close
}

func TestGoAwayWithNoStreamsClosesAtOnce(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	p.relay.GoAway()
	<-p.relay.Done()
}

func TestGoAwayClosesAfterThirtySeconds(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, _ := p.open(1, 80)
	p.relay.GoAway()
	p.clock.Advance(DefaultGoAwayTimeout - time.Second)
	if p.relay.Err() != nil {
		t.Fatal("closed early")
	}
	p.clock.Advance(time.Second)
	<-p.relay.Done()
	if _, err := rs.Read(make([]byte, 1)); !errors.Is(err, ErrSessionClosed) {
		t.Fatalf("Read = %v", err)
	}
}

func TestGoAwayFromTheRunnerIsAProtocolError(t *testing.T) {
	_, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
	r.sendNoWait(Frame{Type: TypeGoAway})
	r.expectClosed(CloseProtocol)
}

func TestRunnerRefusesOpenAfterGoAway(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
	r.send(Frame{Type: TypeGoAway})
	r.send(OpenFrame(1, Open{SessionID: 1, Port: 1}))
	r.expectReset(1, ResetRefused)
	if _, err := s.Accept(context.Background()); !errors.Is(err, ErrGoAway) {
		t.Fatalf("Accept = %v", err)
	}
}

// The relay's GOAWAY and its close can both be read before the runner calls Accept:
// the drain must still reach it as ErrGoAway (the flake of #278).
func TestRunnerAcceptReportsGoAwayWhenTheCloseFollowsIt(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
	r.send(Frame{Type: TypeGoAway})
	r.c.Close(CloseNormal, "drained")
	<-s.Done()
	if _, err := s.Accept(context.Background()); !errors.Is(err, ErrGoAway) {
		t.Fatalf("Accept = %v, want ErrGoAway", err)
	}
}

func TestRunnerAcceptReportsAClosedSessionWhenTheCloseHasNoGoAway(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{}, stdHello, 8)
	r.c.Close(CloseNormal, "gone")
	<-s.Done()
	if _, err := s.Accept(context.Background()); !errors.Is(err, ErrSessionClosed) {
		t.Fatalf("Accept = %v, want ErrSessionClosed", err)
	}
}

func TestClosedConnectionResetsEveryStreamOnBothSides(t *testing.T) {
	a := newMemPairSessions(t)
	rs1, ns1 := a.open(1, 1)
	rs2, ns2 := a.open(1, 2)
	blocked := make(chan error, 1)
	go func() { _, err := ns2.Read(make([]byte, 1)); blocked <- err }()
	a.conn.Close(CloseNormal, "gone") // the runner's connection drops
	for name, st := range map[string]*Stream{"relay 1": rs1, "relay 2": rs2, "runner 1": ns1, "runner 2": ns2} {
		if err := readErr(t, st); !errors.Is(err, ErrSessionClosed) {
			t.Errorf("%s: Read = %v, want ErrSessionClosed", name, err)
		}
		if _, err := st.Write([]byte("x")); !errors.Is(err, ErrSessionClosed) {
			t.Errorf("%s: Write = %v, want ErrSessionClosed", name, err)
		}
	}
	if err := <-blocked; !errors.Is(err, ErrSessionClosed) {
		t.Errorf("blocked Read = %v", err)
	}
	<-a.relay.Done()
	<-a.runner.Done()
	var ce *CloseError
	if !errors.As(a.relay.Err(), &ce) || ce.Code != CloseNormal || ce.Reason != "gone" {
		t.Errorf("relay Err = %v", a.relay.Err())
	}
	if !errors.Is(a.runner.Err(), net.ErrClosed) {
		t.Errorf("runner Err = %v", a.runner.Err())
	}
}

// memPairSessions is a pair whose connection the test can drop.
type memPairSessions struct {
	*pair
	conn *memConn
}

func newMemPairSessions(t *testing.T) *memPairSessions {
	t.Helper()
	clock := NewFakeClock()
	a, b := newMemPair(8)
	p := &pair{t: t, clock: clock, relay: NewRelay(a, Config{Clock: clock}), runner: NewRunner(b, Config{Clock: clock})}
	errc := make(chan error, 2)
	go func() { errc <- p.relay.Handshake(context.Background()) }()
	go func() { errc <- p.runner.Handshake(context.Background()) }()
	for i := 0; i < 2; i++ {
		if err := <-errc; err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { p.relay.Close(); p.runner.Close(); noLeaks(t) })
	return &memPairSessions{pair: p, conn: b}
}

func TestLocalCloseResetsEveryStreamWithShutdown(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, ns := p.open(1, 1)
	p.relay.Close()
	var re *ResetError
	if _, err := rs.Read(make([]byte, 1)); !errors.As(err, &re) || re.Code != ResetShutdown {
		t.Fatalf("relay Read = %v", err)
	}
	if err := readErr(t, ns); !errors.Is(err, ErrSessionClosed) {
		t.Fatalf("runner Read = %v", err)
	}
	if !errors.Is(p.relay.Err(), ErrSessionClosed) {
		t.Fatalf("Err = %v", p.relay.Err())
	}
	if _, err := p.relay.Open(context.Background(), 1, 1); !errors.Is(err, ErrSessionClosed) {
		t.Fatalf("Open after Close = %v", err)
	}
}

func TestProtocolErrorClosesWith1002AndResetsStreams(t *testing.T) {
	cases := map[string]Frame{
		"unknown frame type":        {Type: Type(0x0b), Payload: nil},
		"HELLO after the handshake": stdHello.Frame(true),
		"OPEN from the runner":      OpenFrame(9, Open{SessionID: 1, Port: 1}),
		"frame for an unopened id":  {Type: TypeClose, Stream: 99},
	}
	for name, f := range cases {
		t.Run(name, func(t *testing.T) {
			s, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
			st := openRaw(t, s, r, 1)
			var msg []byte
			if f.Type == Type(0x0b) {
				msg = []byte{0x0b, 0, 0, 0, 0}
			} else {
				msg, _ = Encode(f)
			}
			ctx, cancel := context.WithTimeout(context.Background(), wait)
			defer cancel()
			r.c.WriteMessage(ctx, msg)
			r.expectClosed(CloseProtocol)
			<-s.Done()
			var pe *ProtocolError
			if !errors.As(s.Err(), &pe) {
				t.Fatalf("Err = %v, want a *ProtocolError", s.Err())
			}
			var re *ResetError
			if _, err := st.Read(make([]byte, 1)); !errors.As(err, &re) || re.Code != ResetProtocol {
				t.Fatalf("Read = %v, want RESET protocol", err)
			}
		})
	}
}

func TestShortMessageClosesWith1002(t *testing.T) {
	_, r, _ := relayVsRaw(t, Config{}, stdAnswer, 8)
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	r.c.WriteMessage(ctx, []byte{1, 2})
	r.expectClosed(CloseProtocol)
}

func TestHelloNegotiation(t *testing.T) {
	t.Run("the minimum of each limit", func(t *testing.T) {
		p := newPair(t,
			Config{MaxFrame: 16384, MaxStreams: 10, Window: 65536, SessionID: 7},
			Config{MaxFrame: 8192, MaxStreams: 20, Window: 131072, RunnerVersion: "1.2.3"})
		want := Limits{MaxFrame: 8192, MaxStreams: 10, Window: 65536, PingInterval: DefaultPingInterval}
		for name, s := range map[string]*Session{"relay": p.relay, "runner": p.runner} {
			got := s.Limits()
			if got.MaxFrame != want.MaxFrame || got.MaxStreams != want.MaxStreams || got.Window != want.Window || got.PingInterval != want.PingInterval {
				t.Errorf("%s Limits = %+v, want %+v", name, got, want)
			}
		}
		if h := p.relay.Peer(); h.RunnerVersion != "1.2.3" {
			t.Errorf("relay Peer = %+v", h)
		}
		if h := p.runner.Peer(); h.SessionID == nil || *h.SessionID != 7 || h.PingInterval != 20 {
			t.Errorf("runner Peer = %+v", h)
		}
	})
	t.Run("features are the names both list", func(t *testing.T) {
		p := newPair(t, Config{Features: []string{"a", "b"}}, Config{Features: []string{"b", "c"}})
		for _, s := range []*Session{p.relay, p.runner} {
			if f := s.Limits().Features; len(f) != 1 || f[0] != "b" {
				t.Errorf("Features = %v", f)
			}
		}
	})
	t.Run("unknown fields are ignored", func(t *testing.T) {
		a, b := newMemPair(8)
		s := NewRunner(a, Config{Clock: NewFakeClock()})
		t.Cleanup(func() { s.Close(); noLeaks(t) })
		ctx := context.Background()
		b.WriteMessage(ctx, append(mustHex(t, "01 00000000"), `{"v":1,"max_frame":4096,"extra":[1],"max_streams":5,"window":8192,"ping_interval":9,"session_id":null,"new":{}}`...))
		if err := s.Handshake(ctx); err != nil {
			t.Fatal(err)
		}
		if l := s.Limits(); l.MaxFrame != 4096 || l.MaxStreams != 5 || l.Window != 8192 || l.PingInterval != 9*time.Second {
			t.Fatalf("Limits = %+v", l)
		}
	})
	t.Run("the runner's answer carries the negotiated values", func(t *testing.T) {
		a, b := newMemPair(8)
		s := NewRunner(a, Config{MaxStreams: 8, RunnerVersion: "3.1.4", Clock: NewFakeClock()})
		t.Cleanup(func() { s.Close(); noLeaks(t) })
		ctx := context.Background()
		b.WriteMessage(ctx, mustEncode(t, Hello{V: 1, MaxFrame: 4096, MaxStreams: 64, Window: 8192, PingInterval: 5}.Frame(true)))
		if err := s.Handshake(ctx); err != nil {
			t.Fatal(err)
		}
		msg, _ := b.ReadMessage(ctx)
		want := mustEncode(t, Hello{V: 1, MaxFrame: 4096, MaxStreams: 8, Window: 8192, RunnerVersion: "3.1.4"}.Frame(false))
		if string(msg) != string(want) {
			t.Fatalf("answer %s, want %s", msg, want)
		}
	})
}

func TestHelloRefusalsCloseWith1002(t *testing.T) {
	bad := map[string]Hello{
		"version 2":              {V: 2, MaxFrame: 32768, MaxStreams: 64, Window: 262144, PingInterval: 20},
		"max_frame under 1024":   {V: 1, MaxFrame: 1023, MaxStreams: 64, Window: 262144, PingInterval: 20},
		"max_frame over 65536":   {V: 1, MaxFrame: 65537, MaxStreams: 64, Window: 262144, PingInterval: 20},
		"window under max_frame": {V: 1, MaxFrame: 32768, MaxStreams: 64, Window: 32767, PingInterval: 20},
		"max_streams of 0":       {V: 1, MaxFrame: 32768, MaxStreams: 0, Window: 262144, PingInterval: 20},
		"ping_interval of 0":     {V: 1, MaxFrame: 32768, MaxStreams: 64, Window: 262144, PingInterval: 0},
	}
	for name, h := range bad {
		t.Run("runner, relay HELLO with "+name, func(t *testing.T) {
			a, b := newMemPair(8)
			s := NewRunner(a, Config{Clock: NewFakeClock()})
			t.Cleanup(func() { s.Close(); noLeaks(t) })
			ctx := context.Background()
			b.WriteMessage(ctx, mustEncode(t, h.Frame(true)))
			err := s.Handshake(ctx)
			var pe *ProtocolError
			if !errors.As(err, &pe) {
				t.Fatalf("Handshake = %v", err)
			}
			if code, _ := b.peerInfo(); code != CloseProtocol {
				t.Fatalf("closed with %d", code)
			}
		})
		if name == "ping_interval of 0" {
			continue // the runner's HELLO has no ping_interval
		}
		t.Run("relay, runner HELLO with "+name, func(t *testing.T) {
			a, b := newMemPair(8)
			s := NewRelay(a, Config{Clock: NewFakeClock()})
			t.Cleanup(func() { s.Close(); noLeaks(t) })
			ctx := context.Background()
			go func() {
				b.ReadMessage(ctx)
				h := h
				h.PingInterval = 0
				b.WriteMessage(ctx, mustEncode(t, h.Frame(false)))
			}()
			err := s.Handshake(ctx)
			var pe *ProtocolError
			if !errors.As(err, &pe) {
				t.Fatalf("Handshake = %v", err)
			}
		})
	}
	t.Run("a frame other than HELLO first", func(t *testing.T) {
		a, b := newMemPair(8)
		s := NewRunner(a, Config{Clock: NewFakeClock()})
		t.Cleanup(func() { s.Close(); noLeaks(t) })
		b.WriteMessage(context.Background(), mustEncode(t, Frame{Type: TypePing, Payload: make([]byte, 8)}))
		if err := s.Handshake(context.Background()); err == nil {
			t.Fatal("Handshake succeeded")
		}
		if code, _ := b.peerInfo(); code != CloseProtocol {
			t.Fatalf("closed with %d", code)
		}
	})
}

func (c *memConn) peerInfo() (int, string) { return c.peer.closeInfo() }

func mustEncode(t *testing.T, f Frame) []byte {
	t.Helper()
	msg, err := Encode(f)
	if err != nil {
		t.Fatal(err)
	}
	return msg
}

func TestHandshakeCancelled(t *testing.T) {
	a, _ := newMemPair(0)
	s := NewRunner(a, Config{Clock: NewFakeClock()})
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := s.Handshake(ctx); err == nil {
		t.Fatal("Handshake succeeded")
	}
	<-s.Done()
	noLeaks(t)
}

func TestWrongRoleCalls(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	if _, err := p.runner.Open(context.Background(), 1, 1); err == nil {
		t.Error("the runner opened a stream")
	}
	if _, err := p.relay.Accept(context.Background()); err == nil {
		t.Error("the relay accepted a stream")
	}
	if err := p.runner.GoAway(); err == nil {
		t.Error("the runner sent GOAWAY")
	}
}

func TestDeadlines(t *testing.T) {
	p := newPair(t, Config{}, Config{})
	rs, _ := p.open(1, 1)
	errc := make(chan error, 1)
	read := func() {
		go func() { _, err := rs.Read(make([]byte, 1)); errc <- err }()
	}
	rs.SetReadDeadline(p.clock.Now().Add(10 * time.Second))
	read()
	poll(t, "the Read to wait", func() bool { return p.clock.Pending() > 0 })
	p.clock.Advance(10 * time.Second)
	var ne net.Error
	if err := <-errc; !errors.Is(err, os.ErrDeadlineExceeded) || !errors.As(err, &ne) || !ne.Timeout() {
		t.Fatalf("Read = %v, want a timeout", err)
	}
	// A deadline in the past fails at once, and one that is cleared lets a Read wait.
	rs.SetDeadline(p.clock.Now().Add(-time.Second))
	if _, err := rs.Write([]byte("x")); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("Write = %v", err)
	}
	rs.SetDeadline(time.Time{})
	read()
	time.Sleep(10 * time.Millisecond)
	select {
	case err := <-errc:
		t.Fatalf("Read returned %v with no deadline", err)
	default:
	}
	// A deadline moved to the past wakes a Read that waits.
	rs.SetReadDeadline(p.clock.Now().Add(-time.Second))
	if err := <-errc; !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("Read = %v", err)
	}
}

func TestWriteBlockedAtZeroCreditHonoursItsDeadline(t *testing.T) {
	p := newPair(t, Config{MaxFrame: 1024, Window: 2048}, Config{})
	rs, _ := p.open(1, 1)
	rs.SetWriteDeadline(p.clock.Now().Add(time.Second))
	type res struct {
		n   int
		err error
	}
	rc := make(chan res, 1)
	go func() { n, err := rs.Write(make([]byte, 8192)); rc <- res{n, err} }()
	poll(t, "the Write to spend its credit", func() bool {
		p.relay.mu.Lock()
		defer p.relay.mu.Unlock()
		return rs.taken == 2048
	})
	p.clock.Advance(time.Second)
	r := <-rc
	if !errors.Is(r.err, os.ErrDeadlineExceeded) || r.n != 2048 {
		t.Fatalf("Write = %d, %v; want 2048 bytes taken, then the deadline", r.n, r.err)
	}
}

func TestTheStreamIsANetConn(t *testing.T) {
	var _ net.Conn = (*Stream)(nil)
	p := newPair(t, Config{}, Config{})
	rs, _ := p.open(1, 1)
	if rs.LocalAddr().Network() != "tunnel" || rs.RemoteAddr().String() == "" {
		t.Fatal("addresses")
	}
}

func TestManyStreamsAtOnce(t *testing.T) {
	p := newPair(t, Config{MaxFrame: 1024, Window: 4096}, Config{})
	const n = 32
	done := make(chan error, n)
	for i := 0; i < n; i++ {
		go func(i int) {
			ctx := context.Background()
			rs, err := p.relay.Open(ctx, int64(i), 80)
			if err != nil {
				done <- err
				return
			}
			payload := make([]byte, 20_000)
			for j := range payload {
				payload[j] = byte(i)
			}
			go func() { rs.Write(payload); rs.CloseWrite() }()
			got, err := io.ReadAll(rs)
			if err == nil && len(got) != len(payload) {
				err = io.ErrShortBuffer
			}
			done <- err
		}(i)
	}
	go func() {
		for i := 0; i < n; i++ {
			in, err := p.runner.Accept(context.Background())
			if err != nil {
				return
			}
			go func() {
				st, err := in.Accept()
				if err != nil {
					return
				}
				io.Copy(st, st) // echo
				st.Close()
			}()
		}
	}()
	for i := 0; i < n; i++ {
		if err := <-done; err != nil {
			t.Fatal(err)
		}
	}
}

func TestRefusalsAreDroppedPastTheControlQueueCap(t *testing.T) {
	s, r, _ := runnerVsRaw(t, Config{MaxStreams: 1}, stdHello, 8)
	const sent = maxControlQueue + 200
	for id := uint32(1); id <= sent; id++ {
		r.sendNoWait(OpenFrame(id, Open{SessionID: 1, Port: 7681}))
	}
	// The raw end reads nothing, so the writer stalls and the refusals queue up.
	poll(t, "the runner to read every OPEN", func() bool { return s.framesIn.Load() >= sent })
	s.mu.Lock()
	queued := len(s.wq.ctrl)
	s.mu.Unlock()
	if queued > maxControlQueue {
		t.Fatalf("control queue holds %d frames, cap is %d", queued, maxControlQueue)
	}
	if s.Err() != nil {
		t.Fatalf("the session ended: %v", s.Err())
	}
}

func TestPingIntervalMustBeWholeSeconds(t *testing.T) {
	for name, mk := range map[string]func(Conn, Config) *Session{"relay": NewRelay, "runner": NewRunner} {
		t.Run(name, func(t *testing.T) {
			a, _ := newMemPair(8)
			s := mk(a, Config{PingInterval: 1500 * time.Millisecond, Clock: NewFakeClock()})
			t.Cleanup(func() { s.Close(); noLeaks(t) })
			err := s.Handshake(context.Background())
			if err == nil || !strings.Contains(err.Error(), "whole number of seconds") {
				t.Fatalf("Handshake = %v", err)
			}
		})
	}
}

func TestCutCloseReasonKeepsValidUTF8(t *testing.T) {
	long := strings.Repeat("a", 119) + "é" // the two bytes of é straddle byte 120
	got := cutCloseReason(long)
	if !utf8.ValidString(got) || len(got) > 120 {
		t.Fatalf("cutCloseReason = %q (%d bytes)", got, len(got))
	}
	if got != strings.Repeat("a", 119) {
		t.Fatalf("cutCloseReason = %q", got)
	}
	if short := "ünder"; cutCloseReason(short) != short {
		t.Fatal("a short reason changed")
	}
}
