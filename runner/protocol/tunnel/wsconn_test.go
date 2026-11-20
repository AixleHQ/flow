package tunnel

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/coder/websocket"
)

// The adapter's own test, over a loopback WebSocket: the two sessions run the
// protocol over real binary messages, and a close code reaches the peer as a
// *CloseError.
func TestWSConn(t *testing.T) {
	srvConn := make(chan Conn, 1)
	finished := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := websocket.Accept(w, r, &websocket.AcceptOptions{Subprotocols: []string{Subprotocol}})
		if err != nil {
			return
		}
		srvConn <- NewWSConn(c)
		<-finished // the handler must outlive the connection it hands over
	}))
	defer srv.Close()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http"), &websocket.DialOptions{Subprotocols: []string{Subprotocol}})
	if err != nil {
		t.Fatal(err)
	}
	if c.Subprotocol() != Subprotocol {
		t.Fatalf("subprotocol %q", c.Subprotocol())
	}
	relayConn, runnerConn := <-srvConn, NewWSConn(c)
	relay, runner := NewRelay(relayConn, Config{}), NewRunner(runnerConn, Config{})
	t.Cleanup(func() { relay.Close(); runner.Close(); close(finished); noLeaks(t) })

	errc := make(chan error, 2)
	go func() { errc <- relay.Handshake(ctx) }()
	go func() { errc <- runner.Handshake(ctx) }()
	for i := 0; i < 2; i++ {
		if err := <-errc; err != nil {
			t.Fatal(err)
		}
	}
	type res struct {
		st  *Stream
		err error
	}
	rc := make(chan res, 1)
	go func() { st, err := relay.Open(ctx, 7, 4040); rc <- res{st, err} }()
	in, err := runner.Accept(ctx)
	if err != nil {
		t.Fatal(err)
	}
	ns, err := in.Accept()
	if err != nil {
		t.Fatal(err)
	}
	r := <-rc
	if r.err != nil {
		t.Fatal(r.err)
	}
	payload := []byte(strings.Repeat("0123456789", 20_000)) // several frames
	go func() { r.st.Write(payload); r.st.CloseWrite() }()
	got, err := io.ReadAll(ns)
	if err != nil || string(got) != string(payload) {
		t.Fatalf("ReadAll = %d bytes, %v", len(got), err)
	}

	// The relay closes with a code; the runner's session ends with it.
	relay.Close()
	<-runner.Done()
	var ce *CloseError
	if !errors.As(runner.Err(), &ce) || ce.Code != CloseNormal {
		t.Fatalf("runner Err = %v", runner.Err())
	}
}

func TestWSConnTextMessageIsAProtocolError(t *testing.T) {
	got := make(chan error, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer c.CloseNow()
		_, err = NewWSConn(c).ReadMessage(r.Context())
		got <- err
	}))
	defer srv.Close()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.CloseNow()
	c.Write(ctx, websocket.MessageText, []byte("hello"))
	var pe *ProtocolError
	if err := <-got; !errors.As(err, &pe) {
		t.Fatalf("ReadMessage = %v", err)
	}
}

func TestWSConnReadLimit(t *testing.T) {
	got := make(chan error, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer c.CloseNow()
		_, err = NewWSConn(c).ReadMessage(r.Context())
		got <- err
	}))
	defer srv.Close()
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	c, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer c.CloseNow()
	go c.Write(ctx, websocket.MessageBinary, make([]byte, MaxMessage+1))
	var ce *CloseError
	if err := <-got; err == nil {
		t.Fatal("an over-limit message was read")
	} else if errors.As(err, &ce) && ce.Code != CloseTooLarge {
		t.Fatalf("closed with %d, want 1009", ce.Code)
	}
}
