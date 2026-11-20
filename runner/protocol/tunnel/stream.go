package tunnel

import (
	"io"
	"net"
	"os"
	"sync"
	"time"
)

type streamState uint8

const (
	// stateOpening: on the relay, OPEN is sent and OPEN_OK is awaited; on the runner,
	// OPEN arrived and Accept or Reject is awaited. No DATA may flow.
	stateOpening streamState = iota
	stateOpen
)

// Stream is one tunneled connection. It implements net.Conn. Close is a full close
// as net.Conn's is: it sends CLOSE and, when the peer has not sent CLOSE, RESET
// cancelled. CloseWrite is the half-close.
//
// A Read that meets the peer's CLOSE returns io.EOF after the buffered data; a RESET
// makes Read and Write return a *ResetError at once.
//
// All fields below mu's line are guarded by the session's mutex.
type Stream struct {
	s  *Session
	id uint32

	wmu sync.Mutex // one Write at a time
	rdl deadline
	wdl deadline

	state    streamState
	finished bool  // removed from the session: both CLOSEs, or a reset
	closed   bool  // Close was called
	wclosed  bool  // CLOSE sent (CloseWrite or Close)
	rclosed  bool  // CLOSE received
	reset    error // why the stream ended abnormally: a *ResetError, or the session's error

	send  sendWindow
	recv  recvWindow
	rbuf  [][]byte // received DATA, not read yet
	rsize int      // bytes in rbuf

	out    []byte // the bytes of the Write in progress that the writer has not taken
	taken  int    // bytes of that Write the writer took
	queued bool   // in the writer's ring

	openTimer Timer
	sig       chan struct{} // closed, and replaced by the next waiter, on every change
}

func newStream(s *Session, id uint32) *Stream {
	return &Stream{
		s: s, id: id,
		rdl: newDeadline(), wdl: newDeadline(),
		send: newSendWindow(s.lim.Window), recv: newRecvWindow(s.lim.Window),
	}
}

// ID is the stream id, assigned by the relay.
func (st *Stream) ID() uint32 { return st.id }

// Err is why the stream ended abnormally, or nil: a *ResetError for a RESET from
// either side, or the error of a session that was lost.
func (st *Stream) Err() error {
	st.s.mu.Lock()
	defer st.s.mu.Unlock()
	return st.reset
}

// notifyLocked wakes every goroutine that waits on the stream.
func (st *Stream) notifyLocked() {
	if st.sig != nil {
		close(st.sig)
		st.sig = nil
	}
}

func (st *Stream) signalLocked() <-chan struct{} {
	if st.sig == nil {
		st.sig = make(chan struct{})
	}
	return st.sig
}

// waitLocked releases the session's mutex until the stream changes or the deadline
// passes, and takes it again.
func (st *Stream) waitLocked(dl *deadline) {
	ch := st.signalLocked()
	st.s.mu.Unlock()
	select {
	case <-ch:
	case <-dl.wait():
	}
	st.s.mu.Lock()
}

// Read implements net.Conn.
func (st *Stream) Read(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	s := st.s
	s.mu.Lock()
	defer s.mu.Unlock()
	for {
		switch {
		case st.closed:
			return 0, net.ErrClosed
		case st.reset != nil:
			return 0, st.reset
		case st.rsize > 0:
			n := 0
			for n < len(p) && len(st.rbuf) > 0 {
				c := copy(p[n:], st.rbuf[0])
				n += c
				if c == len(st.rbuf[0]) {
					st.rbuf[0] = nil
					st.rbuf = st.rbuf[1:]
				} else {
					st.rbuf[0] = st.rbuf[0][c:]
				}
			}
			st.rsize -= n
			if !st.rclosed {
				if grant := st.recv.consumed(n); grant > 0 {
					s.queueLocked(WindowFrame(st.id, uint32(grant)))
				}
			}
			return n, nil
		case st.rclosed:
			return 0, io.EOF
		case st.rdl.expired():
			return 0, os.ErrDeadlineExceeded
		}
		st.waitLocked(&st.rdl)
	}
}

func (st *Stream) writeErrLocked() error {
	switch {
	case st.closed, st.wclosed && st.reset == nil:
		return net.ErrClosed
	case st.reset != nil:
		return st.reset
	}
	return nil
}

// Write implements net.Conn. It returns when the writer has taken every byte into a
// frame (or the stream ended), so the bytes of p are free to reuse; a sender with no
// credit waits, and the wait is the backpressure.
func (st *Stream) Write(p []byte) (int, error) {
	if len(p) == 0 {
		return 0, nil
	}
	st.wmu.Lock()
	defer st.wmu.Unlock()
	s := st.s
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := st.writeErrLocked(); err != nil {
		return 0, err
	}
	st.out, st.taken = p, 0
	s.wq.markReady(st)
	s.wakeWriter()
	for {
		if st.taken == len(p) {
			return len(p), nil
		}
		err := st.writeErrLocked()
		if err == nil && st.wdl.expired() {
			err = os.ErrDeadlineExceeded
		}
		if err != nil {
			n := st.taken
			st.out = nil
			return n, err
		}
		st.waitLocked(&st.wdl)
	}
}

// CloseWrite sends CLOSE: this side will send no more DATA. The peer may keep
// sending.
func (st *Stream) CloseWrite() error {
	s := st.s
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := st.writeErrLocked(); err != nil {
		return err
	}
	st.closeWriteLocked()
	return nil
}

func (st *Stream) closeWriteLocked() {
	st.wclosed = true
	st.out = nil
	st.s.queueLocked(Frame{Type: TypeClose, Stream: st.id})
	if st.rclosed {
		st.s.finishLocked(st, nil, false)
	}
	st.notifyLocked()
}

// Close ends the stream in both directions. When the peer has not sent CLOSE, the
// peer is told with RESET cancelled, as a browser that went away is (§8.7).
func (st *Stream) Close() error {
	s := st.s
	s.mu.Lock()
	defer s.mu.Unlock()
	if st.closed {
		return net.ErrClosed
	}
	st.closed = true
	if !st.finished {
		if !st.wclosed {
			st.closeWriteLocked()
		}
		if !st.finished {
			s.finishLocked(st, &ResetError{Code: ResetCancelled}, true)
		}
	}
	st.rbuf, st.rsize = nil, 0
	st.notifyLocked()
	return nil
}

// Reset aborts the stream in both directions with a code and a text for the peer's
// log. It does nothing on a stream that has ended.
func (st *Stream) Reset(code ResetCode, text string) error {
	s := st.s
	s.mu.Lock()
	defer s.mu.Unlock()
	if st.finished {
		return nil
	}
	s.finishLocked(st, &ResetError{Code: code, Text: cutText(text)}, true)
	return nil
}

type streamAddr struct{ id uint32 }

func (streamAddr) Network() string  { return "tunnel" }
func (a streamAddr) String() string { return "tunnel-stream" }

func (st *Stream) LocalAddr() net.Addr  { return streamAddr{st.id} }
func (st *Stream) RemoteAddr() net.Addr { return streamAddr{st.id} }

func (st *Stream) SetDeadline(t time.Time) error {
	st.rdl.set(st.s.clock, t)
	st.wdl.set(st.s.clock, t)
	return nil
}

func (st *Stream) SetReadDeadline(t time.Time) error  { st.rdl.set(st.s.clock, t); return nil }
func (st *Stream) SetWriteDeadline(t time.Time) error { st.wdl.set(st.s.clock, t); return nil }

// Incoming is an OPEN the runner has received and not answered yet.
type Incoming struct {
	SessionID int64
	Port      int
	s         *Session
	st        *Stream
}

// Accept answers OPEN_OK: the dial succeeded, and DATA may flow both ways. It
// returns the *ResetError if the relay reset the stream while it waited.
func (in *Incoming) Accept() (*Stream, error) {
	s := in.s
	s.mu.Lock()
	defer s.mu.Unlock()
	st := in.st
	if st.finished {
		return nil, st.reset
	}
	if st.state != stateOpening {
		return nil, errAnswered
	}
	st.state = stateOpen
	s.queueLocked(Frame{Type: TypeOpenOK, Stream: st.id})
	return st, nil
}

// Reject answers RESET with a code (refused, dial_failed, timeout) and a text for
// the log.
func (in *Incoming) Reject(code ResetCode, text string) error {
	s := in.s
	s.mu.Lock()
	defer s.mu.Unlock()
	st := in.st
	if st.finished {
		return st.reset
	}
	if st.state != stateOpening {
		return errAnswered
	}
	s.finishLocked(st, &ResetError{Code: code, Text: cutText(text)}, true)
	return nil
}

// deadline is a net.Conn deadline over the session's Clock, as net.Pipe's.
type deadline struct {
	mu     sync.Mutex
	timer  Timer
	cancel chan struct{} // closed when the deadline has passed
}

func newDeadline() deadline { return deadline{cancel: make(chan struct{})} }

func (d *deadline) set(clk Clock, t time.Time) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.timer != nil && !d.timer.Stop() {
		<-d.cancel // the timer's call is closing it
	}
	d.timer = nil
	closed := isClosed(d.cancel)
	if t.IsZero() {
		if closed {
			d.cancel = make(chan struct{})
		}
		return
	}
	if dur := t.Sub(clk.Now()); dur > 0 {
		if closed {
			d.cancel = make(chan struct{})
		}
		cancel := d.cancel
		d.timer = clk.AfterFunc(dur, func() { close(cancel) })
		return
	}
	if !closed {
		close(d.cancel)
	}
}

func (d *deadline) wait() <-chan struct{} {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.cancel
}

func (d *deadline) expired() bool { return isClosed(d.wait()) }

func isClosed(c <-chan struct{}) bool {
	select {
	case <-c:
		return true
	default:
		return false
	}
}
