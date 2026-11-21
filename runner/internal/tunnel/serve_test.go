package tunnel

import (
	"context"
	"errors"
	"io"
	"net"
	"path/filepath"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/proxy"
	wire "github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// echoPort listens on 127.0.0.1, echoing, as a port of the session's container.
func echoPort(t *testing.T) (port int, stop func()) {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	return l.Addr().(*net.TCPAddr).Port, func() { l.Close() }
}

func open(t *testing.T, s *wire.Session, sessionID int64, port int) (*wire.Stream, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return s.Open(ctx, sessionID, port)
}

func wantReset(t *testing.T, err error, code wire.ResetCode) {
	t.Helper()
	var reset *wire.ResetError
	if !errors.As(err, &reset) || reset.Code != code {
		t.Fatalf("got %v, want RESET %s", err, code)
	}
}

func roundTrip(t *testing.T, st *wire.Stream) {
	t.Helper()
	st.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := st.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	if _, err := io.ReadFull(st, buf); err != nil || string(buf) != "ping" {
		t.Fatalf("got %q, %v", buf, err)
	}
}

func TestItServesTheGrantedSessionsPortsOverTheTunnel(t *testing.T) {
	h := newHarness(t)
	port, _ := echoPort(t)
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)

	st, err := open(t, session, 123, port)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	roundTrip(t, st)
	// A half-close from the browser's side ends the port's side, and the stream with it.
	st.CloseWrite()
	st.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := st.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("read after the half-close: %v", err)
	}
}

func TestItRefusesAnOpenForAnotherSessionOrAPortOutsideTheGrant(t *testing.T) {
	h := newHarness(t)
	port, _ := echoPort(t)
	other, _ := echoPort(t) // listens, but is not one of the session's
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)

	for _, tc := range []struct {
		session int64
		port    int
	}{{124, port}, {123, other}, {123, 22}, {0, port}} {
		_, err := open(t, session, tc.session, tc.port)
		wantReset(t, err, wire.ResetRefused)
	}
	// The refusals did not touch the granted session.
	st, err := open(t, session, 123, port)
	if err != nil {
		t.Fatal(err)
	}
	st.Close()
}

func TestItRefusesEveryOpenWithoutAGrant(t *testing.T) {
	h := newHarness(t)
	port, _ := echoPort(t)
	h.manager.Serving = &Serving{}
	h.run()
	session := h.relay.next(t)

	_, err := open(t, session, 123, port)
	wantReset(t, err, wire.ResetRefused)
}

func TestItAnswersDialFailedWhenThePortDoesNotAnswer(t *testing.T) {
	h := newHarness(t)
	port, stop := echoPort(t)
	stop()
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)

	_, err := open(t, session, 123, port)
	wantReset(t, err, wire.ResetDialFailed)
}

func TestClearingTheGrantResetsItsStreamsWithSessionChanged(t *testing.T) {
	h := newHarness(t)
	port, _ := echoPort(t)
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)
	st, err := open(t, session, 123, port)
	if err != nil {
		t.Fatal(err)
	}
	roundTrip(t, st)

	h.manager.Serving.Clear(123)

	st.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, err = st.Read(make([]byte, 1))
	wantReset(t, err, wire.ResetSessionChange)
	_, err = open(t, session, 123, port)
	wantReset(t, err, wire.ResetRefused)
}

func TestGrantingAnotherSessionResetsTheOldOnesStreams(t *testing.T) {
	h := newHarness(t)
	port, _ := echoPort(t)
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)
	st, _ := open(t, session, 123, port)
	roundTrip(t, st)

	h.manager.Serving.Set(Grant{SessionID: 124, Ports: []int{port}, Dialer: LoopbackDialer{}})

	st.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, err := st.Read(make([]byte, 1))
	wantReset(t, err, wire.ResetSessionChange)
	// Clearing a session that is not the granted one changes nothing.
	h.manager.Serving.Clear(123)
	if _, ok := h.manager.Serving.Authorize(124, port); !ok {
		t.Fatal("the new session is not served")
	}
}

func TestAPortThatEndsClosesTheStream(t *testing.T) {
	h := newHarness(t)
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	defer l.Close()
	go func() {
		c, err := l.Accept()
		if err == nil {
			c.Write([]byte("bye"))
			c.Close()
		}
	}()
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{l.Addr().(*net.TCPAddr).Port}, Dialer: LoopbackDialer{}})
	h.run()
	session := h.relay.next(t)

	st, err := open(t, session, 123, l.Addr().(*net.TCPAddr).Port)
	if err != nil {
		t.Fatal(err)
	}
	st.SetReadDeadline(time.Now().Add(5 * time.Second))
	got, err := io.ReadAll(st)
	if err != nil || string(got) != "bye" {
		t.Fatalf("got %q, %v", got, err)
	}
}

func TestTheSocketDialerReachesAPortThroughTheSidecarsSocket(t *testing.T) {
	port, _ := echoPort(t)
	dir, err := proxy.MakeDialDir(t.TempDir(), 123)
	if err != nil {
		t.Fatal(err)
	}
	socket := filepath.Join(dir, proxy.DialSocketName)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go proxy.ServeDial(ctx, socket, []int{port}, nil)
	for i := 0; i < 500; i++ {
		if c, err := net.Dial("unix", socket); err == nil {
			c.Close()
			break
		}
		time.Sleep(5 * time.Millisecond)
	}

	h := newHarness(t)
	h.manager.Serving = &Serving{}
	h.manager.Serving.Set(Grant{SessionID: 123, Ports: []int{port}, Dialer: SocketDialer{Socket: socket}})
	h.run()
	session := h.relay.next(t)

	st, err := open(t, session, 123, port)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	roundTrip(t, st)
}

func TestTheLoopbackDialerDialsTheMachinesOwn127(t *testing.T) {
	port, _ := echoPort(t)
	conn, err := LoopbackDialer{}.Dial(context.Background(), port)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
}
