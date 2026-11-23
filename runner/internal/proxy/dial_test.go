package proxy

import (
	"context"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// echo listens on 127.0.0.1 and echoes what it gets, standing for a port of the session.
func echo(t *testing.T) int {
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
	return l.Addr().(*net.TCPAddr).Port
}

func startDial(t *testing.T, ports []int) string {
	t.Helper()
	dir, err := MakeDialDir(t.TempDir(), 123)
	if err != nil {
		t.Fatal(err)
	}
	socket := filepath.Join(dir, DialSocketName)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go ServeDial(ctx, socket, ports, nil)
	deadline := time.Now().Add(5 * time.Second)
	for {
		c, err := net.Dial("unix", socket)
		if err == nil {
			c.Close()
			return socket
		}
		if time.Now().After(deadline) {
			t.Fatalf("the dial socket never listened: %v", err)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestTheDialSocketReachesAnAllowedPortAndPipesBothWays(t *testing.T) {
	port := echo(t)
	socket := startDial(t, []int{port})

	conn, err := DialViaSidecar(context.Background(), socket, port)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	// The bytes sent right after the answer are the stream's, not the protocol's.
	if _, err := conn.Write([]byte("hello")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 5)
	if _, err := io.ReadFull(conn, buf); err != nil || string(buf) != "hello" {
		t.Fatalf("got %q, %v", buf, err)
	}
	// A half-close reaches the port, which closes in turn.
	conn.(*net.UnixConn).CloseWrite()
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if _, err := conn.Read(buf); err != io.EOF {
		t.Fatalf("read after the half-close: %v", err)
	}
}

func TestTheDialSocketRefusesAPortOutsideItsList(t *testing.T) {
	allowed, other := echo(t), echo(t) // both answer, only one is the session's
	socket := startDial(t, []int{allowed})

	_, err := DialViaSidecar(context.Background(), socket, other)
	if err == nil || !strings.Contains(err.Error(), "refused") {
		t.Fatalf("a port outside the list: %v", err)
	}
	for _, port := range []int{0, 22, 65535} {
		if _, err := DialViaSidecar(context.Background(), socket, port); err == nil || !strings.Contains(err.Error(), "refused") {
			t.Errorf("port %d: %v", port, err)
		}
	}
}

func TestTheDialSocketRefusesALineThatIsNotAPort(t *testing.T) {
	port := echo(t)
	socket := startDial(t, []int{port})

	for _, line := range []string{"abc\n", "127.0.0.1:" + strconv.Itoa(port) + "\n", "-1\n", "\n", " " + strconv.Itoa(port) + "\n"} {
		c, err := net.Dial("unix", socket)
		if err != nil {
			t.Fatal(err)
		}
		c.Write([]byte(line))
		c.SetReadDeadline(time.Now().Add(5 * time.Second))
		got, _ := io.ReadAll(c)
		c.Close()
		if !strings.HasPrefix(string(got), "ERR ") {
			t.Errorf("%q was answered %q", line, got)
		}
	}
}

func TestADeadPortIsAnErrorAndNotAHang(t *testing.T) {
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()
	socket := startDial(t, []int{port})

	start := time.Now()
	_, err := DialViaSidecar(context.Background(), socket, port)
	if err == nil || time.Since(start) > 3*time.Second {
		t.Fatalf("%v after %v", err, time.Since(start))
	}
}

func TestDialViaSidecarWithNoSidecarIsAnError(t *testing.T) {
	_, err := DialViaSidecar(context.Background(), filepath.Join(t.TempDir(), "none.sock"), 7681)
	if err == nil {
		t.Fatal("want an error")
	}
}

func TestDialViaSidecarStopsWhenItsContextEnds(t *testing.T) {
	// A socket whose listener never answers.
	socket := filepath.Join(t.TempDir(), "silent.sock")
	l, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	start := time.Now()
	if _, err := DialViaSidecar(ctx, socket, 7681); err == nil || time.Since(start) > 3*time.Second {
		t.Fatalf("%v after %v", err, time.Since(start))
	}
}

func TestTheDialDirectoryCanBeWrittenByTheSidecarsUser(t *testing.T) {
	dir, err := MakeDialDir(t.TempDir(), 7)
	if err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(dir)
	if err != nil || st.Mode().Perm() != 0o777 {
		t.Fatalf("mode %v, %v", st.Mode(), err)
	}
}
