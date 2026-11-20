package tunnel

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"
)

// Role is the end of the connection a Session plays.
type Role uint8

const (
	RoleRelay  Role = iota + 1 // the platform's runner-relay: opens streams
	RoleRunner                 // aixle-runner: accepts them
)

// The defaults of PROTOCOL.md §8.5.
const (
	DefaultMaxFrame      = 32 << 10
	DefaultMaxStreams    = 64
	DefaultWindow        = 256 << 10
	DefaultPingInterval  = 20 * time.Second
	DefaultOpenTimeout   = 10 * time.Second
	DefaultGoAwayTimeout = 30 * time.Second

	silentIntervals = 3 // intervals without a frame before the connection is closed
)

// Config is what one end offers. Zero values take the defaults. The connection
// uses the minimum of each limit of the two ends.
type Config struct {
	MaxFrame   int
	MaxStreams int
	Window     int
	// PingInterval is the relay's offer, in whole seconds; the runner uses the
	// relay's.
	PingInterval time.Duration
	// SessionID is the session the relay's HELLO names; 0 sends null.
	SessionID int64
	// RunnerVersion is the runner's HELLO.runner_version.
	RunnerVersion string
	// Features are the frame types after version 1.0 that this end speaks.
	Features []string

	OpenTimeout   time.Duration // time to OPEN_OK; relay only
	GoAwayTimeout time.Duration // drain time after GOAWAY; relay only
	Clock         Clock         // nil: RealClock
	Logger        *slog.Logger  // nil: no logging; frame types and ids only, at debug level
}

func (c Config) withDefaults() Config {
	if c.MaxFrame == 0 {
		c.MaxFrame = DefaultMaxFrame
	}
	if c.MaxStreams == 0 {
		c.MaxStreams = DefaultMaxStreams
	}
	if c.Window == 0 {
		c.Window = DefaultWindow
	}
	if c.PingInterval == 0 {
		c.PingInterval = DefaultPingInterval
	}
	if c.OpenTimeout == 0 {
		c.OpenTimeout = DefaultOpenTimeout
	}
	if c.GoAwayTimeout == 0 {
		c.GoAwayTimeout = DefaultGoAwayTimeout
	}
	if c.Clock == nil {
		c.Clock = RealClock
	}
	return c
}

// Limits are the values a connection uses after the handshake.
type Limits struct {
	MaxFrame     int
	MaxStreams   int
	Window       int
	PingInterval time.Duration
	// Features are the names both ends listed.
	Features []string
}

func (l Limits) check() error {
	switch {
	case l.MaxFrame < MinMaxFrame || l.MaxFrame > MaxFrameCeiling:
		return protoErr("max_frame %d is outside %d..%d", l.MaxFrame, MinMaxFrame, MaxFrameCeiling)
	case l.Window < l.MaxFrame:
		return protoErr("window %d is under max_frame %d", l.Window, l.MaxFrame)
	case l.MaxStreams < 1:
		return protoErr("max_streams %d", l.MaxStreams)
	case l.PingInterval < time.Second:
		return protoErr("ping_interval is under one second")
	}
	return nil
}

// Session is one end of a relay connection: the reader and the writer goroutine, the
// streams, and the heartbeat. Make one with NewRelay or NewRunner, call Handshake,
// then Open (relay) or Accept (runner).
type Session struct {
	role  Role
	conn  Conn
	cfg   Config
	clock Clock
	log   *slog.Logger

	ctx    context.Context
	cancel context.CancelFunc
	wake   chan struct{} // the writer has work
	done   chan struct{}
	doneMu sync.Once
	wg     sync.WaitGroup

	framesIn atomic.Uint64 // frames the reader has handled; tests wait on it

	mu         sync.Mutex
	started    bool
	err        error
	lim        Limits
	peer       Hello
	streams    map[uint32]*Stream
	lastID     uint32 // relay: the last id assigned; runner: the last id received
	wq         writeQueue
	incoming   []*Incoming
	inSig      chan struct{} // closed and replaced when incoming or goaway changes
	goawaySent bool
	goawayRecv bool
	goawayT    Timer
	beatT      Timer
	lastRecv   time.Time
	pingSeq    uint64
}

// NewRelay is the relay's end. conn is the connection the runner opened.
func NewRelay(conn Conn, cfg Config) *Session { return newSession(RoleRelay, conn, cfg) }

// NewRunner is the runner's end.
func NewRunner(conn Conn, cfg Config) *Session { return newSession(RoleRunner, conn, cfg) }

func newSession(role Role, conn Conn, cfg Config) *Session {
	cfg = cfg.withDefaults()
	ctx, cancel := context.WithCancel(context.Background())
	return &Session{
		role: role, conn: conn, cfg: cfg, clock: cfg.Clock, log: cfg.Logger,
		ctx: ctx, cancel: cancel,
		wake: make(chan struct{}, 1), done: make(chan struct{}),
		streams: map[uint32]*Stream{},
	}
}

// Done is closed when the session has ended and its goroutines have stopped.
func (s *Session) Done() <-chan struct{} { return s.done }

// Err is why the session ended: ErrSessionClosed for Close, a *ProtocolError, a
// *CloseError or other read error for a lost connection, ErrHeartbeat, or ErrGoAway
// after the drain. It is nil while the session runs.
func (s *Session) Err() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.err
}

// Limits are the negotiated limits; zero before Handshake.
func (s *Session) Limits() Limits {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.lim
}

// Peer is the other end's HELLO; zero before Handshake.
func (s *Session) Peer() Hello {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.peer
}

// Close ends the session: every stream is reset with shutdown, the connection is
// closed with 1000, and Close returns when the session's goroutines have stopped.
func (s *Session) Close() error {
	s.fail(ErrSessionClosed, CloseNormal, "")
	<-s.done
	return nil
}

// GoAway tells the runner to finish its streams and reconnect (relay only): no new
// Open succeeds, and the connection closes after the last stream ends or after
// GoAwayTimeout.
func (s *Session) GoAway() error {
	if s.role != RoleRelay {
		return errWrongRole
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		return s.err
	}
	if !s.started {
		return errNotStarted
	}
	if s.goawaySent {
		return nil
	}
	s.goawaySent = true
	s.queueLocked(Frame{Type: TypeGoAway})
	s.goawayT = s.clock.AfterFunc(s.cfg.GoAwayTimeout, func() { s.fail(ErrGoAway, CloseNormal, "drain timeout") })
	return nil
}

// Handshake exchanges HELLO and starts the session's goroutines. On an error the
// session is closed.
func (s *Session) Handshake(ctx context.Context) error {
	own := Hello{
		V: ProtocolVersion, MaxFrame: s.cfg.MaxFrame, MaxStreams: s.cfg.MaxStreams, Window: s.cfg.Window,
		PingInterval: int(s.cfg.PingInterval / time.Second), RunnerVersion: s.cfg.RunnerVersion, Features: s.cfg.Features,
	}
	if s.cfg.SessionID != 0 {
		id := s.cfg.SessionID
		own.SessionID = &id
	}
	if err := s.negotiate(ctx, own); err != nil {
		code, reason := closeCodeFor(err)
		s.fail(err, code, reason)
		return err
	}
	s.start()
	return nil
}

func (s *Session) negotiate(ctx context.Context, own Hello) error {
	s.mu.Lock()
	failed := s.err
	started := s.started
	s.mu.Unlock()
	if failed != nil {
		return failed
	}
	if started {
		return errors.New("tunnel: the handshake was done already")
	}
	if err := (Limits{MaxFrame: own.MaxFrame, MaxStreams: own.MaxStreams, Window: own.Window, PingInterval: s.cfg.PingInterval}).check(); err != nil {
		return fmt.Errorf("tunnel: config: %w", err)
	}
	if s.cfg.PingInterval%time.Second != 0 {
		// HELLO carries whole seconds: a fraction would make the two ends time out differently.
		return fmt.Errorf("tunnel: config: ping_interval %v is not a whole number of seconds", s.cfg.PingInterval)
	}
	var peer Hello
	var lim Limits
	if s.role == RoleRelay {
		if err := s.writeFrame(ctx, own.Frame(true)); err != nil {
			return err
		}
		h, err := s.readHello(ctx)
		if err != nil {
			return err
		}
		peer = h
		lim = Limits{
			MaxFrame: min(own.MaxFrame, h.MaxFrame), MaxStreams: min(own.MaxStreams, h.MaxStreams),
			Window: min(own.Window, h.Window), PingInterval: s.cfg.PingInterval,
			Features: intersect(own.Features, h.Features),
		}
	} else {
		h, err := s.readHello(ctx)
		if err != nil {
			return err
		}
		peer = h
		lim = Limits{
			MaxFrame: min(own.MaxFrame, h.MaxFrame), MaxStreams: min(own.MaxStreams, h.MaxStreams),
			Window: min(own.Window, h.Window), PingInterval: time.Duration(h.PingInterval) * time.Second,
			Features: intersect(own.Features, h.Features),
		}
		if err := lim.check(); err != nil {
			return err
		}
		answer := own
		answer.MaxFrame, answer.MaxStreams, answer.Window = lim.MaxFrame, lim.MaxStreams, lim.Window
		if err := s.writeFrame(ctx, answer.Frame(false)); err != nil {
			return err
		}
	}
	if err := lim.check(); err != nil {
		return err
	}
	s.mu.Lock()
	s.lim, s.peer = lim, peer
	s.mu.Unlock()
	return nil
}

func (s *Session) writeFrame(ctx context.Context, f Frame) error {
	msg, err := Encode(f)
	if err != nil {
		return err
	}
	s.logFrame("send", f)
	return s.conn.WriteMessage(ctx, msg)
}

func (s *Session) readHello(ctx context.Context) (Hello, error) {
	msg, err := s.conn.ReadMessage(ctx)
	if err != nil {
		return Hello{}, err
	}
	f, err := Decode(msg)
	if err != nil {
		return Hello{}, err
	}
	s.logFrame("recv", f)
	if f.Type != TypeHello {
		return Hello{}, protoErr("%s before HELLO", f.Type)
	}
	h, err := f.Hello()
	if err != nil {
		return Hello{}, err
	}
	if h.V != ProtocolVersion {
		return Hello{}, protoErr("version %d is not spoken", h.V)
	}
	// The peer's own numbers must be usable too: the minimum of them and ours may
	// hide a value outside the ranges of PROTOCOL.md §8.3.
	ping := time.Second // the runner's HELLO has no ping_interval
	if s.role == RoleRunner {
		ping = time.Duration(h.PingInterval) * time.Second
	}
	if err := (Limits{MaxFrame: h.MaxFrame, MaxStreams: h.MaxStreams, Window: h.Window, PingInterval: ping}).check(); err != nil {
		return Hello{}, err
	}
	return h, nil
}

func intersect(a, b []string) []string {
	var out []string
	for _, x := range a {
		for _, y := range b {
			if x == y {
				out = append(out, x)
				break
			}
		}
	}
	return out
}

func (s *Session) start() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		return
	}
	s.started = true
	s.inSig = make(chan struct{})
	s.lastRecv = s.clock.Now()
	s.wg.Add(2)
	go s.readLoop()
	go s.writeLoop()
	go func() {
		<-s.ctx.Done()
		s.wg.Wait()
		s.doneMu.Do(func() { close(s.done) })
	}()
	s.beatT = s.clock.AfterFunc(s.lim.PingInterval, s.beat)
}

// fail ends the session once: every stream is reset, the connection is closed with
// the code, and the goroutines are told to stop. It does not wait for them.
func (s *Session) fail(cause error, code int, reason string) {
	s.mu.Lock()
	if s.err != nil {
		s.mu.Unlock()
		return
	}
	s.err = cause
	streamErr := streamError(cause)
	for _, st := range s.streams {
		s.finishLocked(st, streamErr, false)
	}
	s.wq = writeQueue{}
	for _, t := range []Timer{s.goawayT, s.beatT} {
		if t != nil {
			t.Stop()
		}
	}
	s.notifyIncomingLocked()
	started := s.started
	s.mu.Unlock()
	// The connection closes first, with its code: a WebSocket whose read is cancelled
	// drops the connection without the close handshake.
	s.conn.Close(code, reason)
	s.cancel()
	if !started {
		s.doneMu.Do(func() { close(s.done) })
	}
}

// streamError is what the streams of a failed session return.
func streamError(cause error) error {
	var pe *ProtocolError
	switch {
	case errors.Is(cause, ErrSessionClosed):
		return &ResetError{Code: ResetShutdown, Text: "session closed"}
	case errors.As(cause, &pe):
		return &ResetError{Code: ResetProtocol, Text: cutText(pe.Reason)}
	}
	return fmt.Errorf("%w: %w", ErrSessionClosed, cause)
}

func closeCodeFor(err error) (int, string) {
	var pe *ProtocolError
	switch {
	case errors.As(err, &pe):
		return CloseProtocol, cutCloseReason(pe.Reason)
	case errors.Is(err, errTooLarge):
		return CloseTooLarge, "frame too large"
	}
	return CloseNormal, ""
}

// cutCloseReason keeps a close reason inside the 123 bytes a WebSocket close allows.
func cutCloseReason(s string) string { return cutUTF8(s, 120) }

func (s *Session) logFrame(dir string, f Frame) {
	if s.log != nil {
		s.log.Debug("tunnel frame", "dir", dir, "type", f.Type.String(), "stream", f.Stream, "bytes", len(f.Payload))
	}
}

func (s *Session) wakeWriter() {
	select {
	case s.wake <- struct{}{}:
	default:
	}
}

// queueLocked puts a control frame in the writer's FIFO.
func (s *Session) queueLocked(f Frame) {
	msg, err := Encode(f)
	if err != nil {
		panic("tunnel: internal frame is invalid: " + err.Error())
	}
	s.logFrame("queue", f)
	s.wq.pushControl(msg)
	s.wakeWriter()
}

func (s *Session) notifyIncomingLocked() {
	if s.inSig != nil {
		close(s.inSig)
		s.inSig = make(chan struct{})
	}
}

// finishLocked ends a stream: err is why (nil for both CLOSEs), and send says
// whether the peer is told with RESET. A finished stream leaves the table; frames
// for its id that arrive later are dropped.
func (s *Session) finishLocked(st *Stream, err error, send bool) {
	if st.finished {
		return
	}
	st.finished = true
	if err != nil {
		st.reset = err
		st.rbuf, st.rsize = nil, 0
		if re, ok := err.(*ResetError); ok && send {
			s.queueLocked(ResetFrame(st.id, re.Code, re.Text))
		}
	}
	st.out = nil
	delete(s.streams, st.id)
	if st.openTimer != nil {
		st.openTimer.Stop()
	}
	st.notifyLocked()
	s.wakeWriter() // the drain after GOAWAY may be complete
}

// Open opens a stream to a port of the session (relay only) and waits for OPEN_OK,
// for ctx, or for the open timeout. It returns ErrStreamLimit without sending when
// the negotiated max_streams is reached, ErrGoAway after a GOAWAY, and a
// *ResetError when the runner refused.
func (s *Session) Open(ctx context.Context, sessionID int64, port int) (*Stream, error) {
	if s.role != RoleRelay {
		return nil, errWrongRole
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	switch {
	case s.err != nil:
		return nil, fmt.Errorf("%w: %w", ErrSessionClosed, s.err)
	case !s.started:
		return nil, errNotStarted
	case s.goawaySent || s.goawayRecv:
		return nil, ErrGoAway
	case len(s.streams) >= s.lim.MaxStreams:
		return nil, ErrStreamLimit
	case s.lastID >= 1<<31-1: // the high bit is reserved (PROTOCOL.md §8.4)
		return nil, errIDsEnd
	}
	s.lastID++
	st := newStream(s, s.lastID)
	s.streams[st.id] = st
	s.queueLocked(OpenFrame(st.id, Open{SessionID: sessionID, Port: port}))
	st.openTimer = s.clock.AfterFunc(s.cfg.OpenTimeout, func() { s.openTimedOut(st) })
	for {
		switch {
		case st.finished:
			return nil, st.reset
		case st.state == stateOpen:
			return st, nil
		}
		ch := st.signalLocked()
		s.mu.Unlock()
		select {
		case <-ch:
			s.mu.Lock()
		case <-ctx.Done():
			s.mu.Lock()
			if st.state == stateOpen && !st.finished {
				return st, nil
			}
			code := ResetCancelled
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				code = ResetTimeout
			}
			s.finishLocked(st, &ResetError{Code: code, Text: "open: " + ctx.Err().Error()}, true)
			return nil, ctx.Err()
		}
	}
}

func (s *Session) openTimedOut(st *Stream) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if !st.finished && st.state == stateOpening {
		s.finishLocked(st, &ResetError{Code: ResetTimeout, Text: "no OPEN_OK in time"}, true)
	}
}

// Accept waits for the next OPEN (runner only). It returns ErrGoAway once the
// relay sent GOAWAY and no OPEN is left, and an error when the session ended.
func (s *Session) Accept(ctx context.Context) (*Incoming, error) {
	if s.role != RoleRunner {
		return nil, errWrongRole
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for {
		switch {
		case s.err != nil:
			return nil, fmt.Errorf("%w: %w", ErrSessionClosed, s.err)
		case !s.started:
			return nil, errNotStarted
		case len(s.incoming) > 0:
			in := s.incoming[0]
			s.incoming = s.incoming[1:]
			return in, nil
		case s.goawayRecv:
			return nil, ErrGoAway
		}
		ch := s.inSig
		s.mu.Unlock()
		select {
		case <-ch:
		case <-ctx.Done():
			s.mu.Lock()
			return nil, ctx.Err()
		}
		s.mu.Lock()
	}
}

// beat is the heartbeat, called every ping interval. The relay sends PING each time;
// the runner sends one only if it heard nothing for a whole interval. Either end
// closes the connection after three silent intervals (PROTOCOL.md §8.8).
func (s *Session) beat() {
	s.mu.Lock()
	if s.err != nil {
		s.mu.Unlock()
		return
	}
	silent := s.clock.Now().Sub(s.lastRecv)
	if silent >= silentIntervals*s.lim.PingInterval {
		s.mu.Unlock()
		s.fail(ErrHeartbeat, CloseNormal, "heartbeat timeout")
		return
	}
	if s.role == RoleRelay || silent > s.lim.PingInterval {
		s.pingSeq++
		s.queueLocked(Frame{Type: TypePing, Payload: binary.BigEndian.AppendUint64(nil, s.pingSeq)})
	}
	s.beatT = s.clock.AfterFunc(s.lim.PingInterval, s.beat)
	s.mu.Unlock()
}

func (s *Session) readLoop() {
	defer s.wg.Done()
	for {
		msg, err := s.conn.ReadMessage(s.ctx)
		if err != nil {
			s.connLost(err)
			return
		}
		f, err := Decode(msg)
		if err == nil {
			s.logFrame("recv", f)
			err = s.dispatch(f)
		}
		if err != nil {
			code, reason := closeCodeFor(err)
			s.fail(err, code, reason)
			return
		}
		s.framesIn.Add(1)
	}
}

func (s *Session) writeLoop() {
	defer s.wg.Done()
	for {
		msg := s.nextMessage()
		if msg == nil {
			return
		}
		if err := s.conn.WriteMessage(s.ctx, msg); err != nil {
			s.connLost(err)
			return
		}
	}
}

// connLost ends the session after a read or write error, unless it was ended
// already, which is how those errors look after Close.
func (s *Session) connLost(err error) {
	var pe *ProtocolError
	if errors.As(err, &pe) {
		s.fail(err, CloseProtocol, cutCloseReason(pe.Reason))
		return
	}
	s.fail(err, CloseNormal, "")
}

// nextMessage blocks until the writer has a message, and returns nil when the session
// has ended. After GOAWAY it closes the connection when the last stream is gone and
// everything queued was written.
func (s *Session) nextMessage() []byte {
	for {
		s.mu.Lock()
		if s.err != nil {
			s.mu.Unlock()
			return nil
		}
		if msg := s.wq.next(s.lim.MaxFrame); msg != nil {
			s.mu.Unlock()
			return msg
		}
		if s.goawaySent && len(s.streams) == 0 {
			s.mu.Unlock()
			s.fail(ErrGoAway, CloseNormal, "drained")
			return nil
		}
		s.mu.Unlock()
		select {
		case <-s.wake:
		case <-s.ctx.Done():
			return nil
		}
	}
}

// dispatch applies one received frame. A returned error is fatal to the connection.
func (s *Session) dispatch(f Frame) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.err != nil {
		return nil
	}
	s.lastRecv = s.clock.Now()
	switch f.Type {
	case TypeHello:
		return protoErr("HELLO after the handshake")
	case TypePing:
		if len(s.wq.ctrl) < maxControlQueue {
			s.queueLocked(Frame{Type: TypePong, Payload: f.Payload})
		}
		return nil
	case TypePong:
		return nil
	case TypeGoAway:
		if s.role != RoleRunner {
			return protoErr("GOAWAY from the runner")
		}
		s.goawayRecv = true
		s.notifyIncomingLocked()
		return nil
	case TypeOpen:
		if s.role != RoleRunner {
			return protoErr("OPEN from the runner")
		}
		return s.onOpenLocked(f)
	case TypeOpenOK:
		if s.role != RoleRelay {
			return protoErr("OPEN_OK from the relay")
		}
	case TypeData:
		if len(f.Payload) > s.lim.MaxFrame {
			return fmt.Errorf("%w: %d bytes, max_frame is %d", errTooLarge, len(f.Payload), s.lim.MaxFrame)
		}
	}
	st := s.streams[f.Stream]
	if st == nil {
		if f.Stream > s.lastID {
			return protoErr("%s for stream %d, which was never opened", f.Type, f.Stream)
		}
		return nil // the stream ended; frames in flight are dropped (§8.4)
	}
	switch f.Type {
	case TypeOpenOK:
		if st.state != stateOpening {
			s.protocolResetLocked(st, "OPEN_OK on an open stream")
			return nil
		}
		st.state = stateOpen
		if st.openTimer != nil {
			st.openTimer.Stop()
		}
		st.notifyLocked()
	case TypeData:
		s.onDataLocked(st, f.Payload)
	case TypeWindow:
		if !st.send.grant(int(f.Credit())) {
			s.finishLocked(st, &ResetError{Code: ResetFlowViolation, Text: "WINDOW over the window"}, true)
			return nil
		}
		s.wq.markReady(st)
		s.wakeWriter()
	case TypeClose:
		switch {
		case st.state != stateOpen:
			s.protocolResetLocked(st, "CLOSE before the stream opened")
		case st.rclosed:
			s.protocolResetLocked(st, "second CLOSE")
		default:
			st.rclosed = true
			st.notifyLocked()
			if st.wclosed {
				s.finishLocked(st, nil, false)
			}
		}
	case TypeReset:
		code, text := f.Reset()
		s.finishLocked(st, &ResetError{Code: code, Text: text}, false)
	}
	return nil
}

func (s *Session) protocolResetLocked(st *Stream, text string) {
	s.finishLocked(st, &ResetError{Code: ResetProtocol, Text: text}, true)
}

func (s *Session) onDataLocked(st *Stream, payload []byte) {
	switch {
	case st.state != stateOpen:
		s.protocolResetLocked(st, "DATA before the stream opened")
	case st.rclosed:
		s.protocolResetLocked(st, "DATA after CLOSE")
	case len(payload) == 0:
	case !st.recv.receive(len(payload)):
		s.finishLocked(st, &ResetError{Code: ResetFlowViolation, Text: "DATA over the credit"}, true)
	default:
		st.rbuf = append(st.rbuf, payload)
		st.rsize += len(payload)
		st.notifyLocked()
	}
}

func (s *Session) onOpenLocked(f Frame) error {
	if f.Stream <= s.lastID {
		return protoErr("OPEN of stream %d, not above %d", f.Stream, s.lastID)
	}
	s.lastID = f.Stream
	o, err := f.Open()
	if err != nil {
		return err
	}
	if s.goawayRecv || len(s.streams) >= s.lim.MaxStreams {
		// Past the control queue cap the refusal is dropped, as a PONG is: the relay's
		// open timeout ends that stream, and a relay that does not read cannot grow
		// this end's memory.
		if len(s.wq.ctrl) < maxControlQueue {
			s.queueLocked(ResetFrame(f.Stream, ResetRefused, "no stream is accepted"))
		}
		return nil
	}
	st := newStream(s, f.Stream)
	s.streams[st.id] = st
	s.incoming = append(s.incoming, &Incoming{SessionID: o.SessionID, Port: o.Port, s: s, st: st})
	s.notifyIncomingLocked()
	return nil
}
