package proxy

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The tunnel's way into a session's network namespace, with the default bridge
// network (docs/design/agent-runtimes/runner-relay.md §3.3; PROTOCOL.md §8.12).
//
// The sidecar owns the session's network namespace, so it can reach `127.0.0.1:<port>`
// where the host runner cannot (rootless Docker gives a container no address the machine
// reaches). The relay socket runs from the sidecar to the host runner, so a second socket
// runs the other way: the sidecar listens on `dial.sock`, in a directory of the host
// runner's state directory that is mounted read-write into the sidecar, and the host
// runner connects to it for each stream.
//
//	host runner → sidecar   "<port>\n"
//	sidecar → host runner   "OK\n"            the port answered; bytes follow both ways
//	                        "ERR <reason>\n"  it did not, or the port is not allowed; the sidecar closes
//
// The sidecar takes the allowed ports on its command line, from `container.start`'s
// `tunnel.ports`, and refuses any other, so the socket reaches the session's five ports
// and nothing else in the namespace. It holds no credential.
const (
	// DialSocketName is the socket's file in the dial directory.
	DialSocketName = "dial.sock"
	// DialTimeout bounds the sidecar's dial of the port, and the host runner's wait
	// for the sidecar's answer.
	DialTimeout = 8 * time.Second

	// maxLine bounds a line of the dial protocol: a port, or "ERR " and a reason.
	maxLine = 256
)

// DialRoot is the directory of the dial directories under a state directory.
func DialRoot(stateDir string) string { return filepath.Join(stateDir, "tunnel") }

// DialDir is a session's dial directory, which the sidecar mounts.
func DialDir(stateDir string, sessionID int64) string {
	return filepath.Join(DialRoot(stateDir), strconv.FormatInt(sessionID, 10))
}

// MakeDialDir creates the session's dial directory with a mode the sidecar's user
// (nobody) can create its socket in. The state directory above it is 0700, so no other
// user of the machine reaches it.
func MakeDialDir(stateDir string, sessionID int64) (string, error) {
	abs, err := filepath.Abs(stateDir)
	if err != nil {
		return "", err
	}
	root := DialRoot(abs)
	if err := os.MkdirAll(root, 0o711); err != nil {
		return "", fmt.Errorf("creating %s: %w", root, err)
	}
	dir := DialDir(abs, sessionID)
	if err := os.Mkdir(dir, 0o777); err != nil && !errors.Is(err, os.ErrExist) {
		return "", fmt.Errorf("creating %s: %w", dir, err)
	}
	// The umask must not narrow what the sidecar needs.
	if err := os.Chmod(dir, 0o777); err != nil {
		return "", err
	}
	return dir, nil
}

// DialViaSidecar opens a connection to `127.0.0.1:<port>` in the sidecar's network
// namespace, through the sidecar's dial socket. It returns when the sidecar has dialed
// the port, or with the reason it could not.
func DialViaSidecar(ctx context.Context, socket string, port int) (net.Conn, error) {
	var d net.Dialer
	conn, err := d.DialContext(ctx, "unix", socket)
	if err != nil {
		return nil, fmt.Errorf("the sidecar's dial socket is not reachable: %w", err)
	}
	deadline := time.Now().Add(DialTimeout + 2*time.Second)
	if dl, ok := ctx.Deadline(); ok && dl.Before(deadline) {
		deadline = dl
	}
	conn.SetDeadline(deadline)
	// A cancelled context unblocks the exchange below.
	stop := context.AfterFunc(ctx, func() { conn.SetDeadline(time.Unix(1, 0)) })
	defer stop()
	if _, err := fmt.Fprintf(conn, "%d\n", port); err != nil {
		conn.Close()
		return nil, fmt.Errorf("asking the sidecar to dial port %d: %w", port, err)
	}
	line, err := readLine(conn)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("the sidecar's answer for port %d: %w", port, err)
	}
	if line != "OK" {
		conn.Close()
		return nil, fmt.Errorf("the sidecar could not reach port %d: %s", port, strings.TrimPrefix(line, "ERR "))
	}
	if !stop() {
		conn.Close()
		return nil, ctx.Err()
	}
	conn.SetDeadline(time.Time{})
	return conn, nil
}

// readLine reads up to a newline one byte at a time: a buffered reader would take bytes
// of the stream that follow the line.
func readLine(r io.Reader) (string, error) {
	var line []byte
	one := make([]byte, 1)
	for len(line) <= maxLine {
		if _, err := io.ReadFull(r, one); err != nil {
			return "", err
		}
		if one[0] == '\n' {
			return string(line), nil
		}
		line = append(line, one[0])
	}
	return "", errors.New("a line over the limit of the dial protocol")
}

// ServeDial is the sidecar's side: it listens on socket and, for each connection, reads
// a port, refuses it unless it is one of ports, dials `127.0.0.1:<port>`, answers and
// pipes the two. It runs until ctx is done.
func ServeDial(ctx context.Context, socket string, ports []int, logger *slog.Logger) error {
	if logger == nil {
		logger = slog.Default()
	}
	allowed := map[int]bool{}
	for _, p := range ports {
		allowed[p] = true
	}
	if err := os.Remove(socket); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("removing the stale %s: %w", socket, err)
	}
	listener, err := net.Listen("unix", socket)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", socket, err)
	}
	// The host runner connects as another user.
	if err := os.Chmod(socket, 0o666); err != nil {
		listener.Close()
		return err
	}
	logger.Info("aixle-runner dial socket listening", "socket", socket, "ports", ports)
	go func() { <-ctx.Done(); listener.Close() }()
	for {
		conn, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		go serveDial(ctx, conn, allowed, logger)
	}
}

func serveDial(ctx context.Context, conn net.Conn, allowed map[int]bool, logger *slog.Logger) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(DialTimeout))
	line, err := readLine(conn)
	if err != nil {
		return
	}
	port, err := strconv.Atoi(line)
	if err != nil || !allowed[port] {
		// The request is logged by its port only when it parses.
		logger.Warn("a dial request was refused", "port", line)
		fmt.Fprint(conn, "ERR refused: not one of the session's ports\n")
		return
	}
	dctx, cancel := context.WithTimeout(ctx, DialTimeout)
	var d net.Dialer
	target, err := d.DialContext(dctx, "tcp", net.JoinHostPort("127.0.0.1", line))
	cancel()
	if err != nil {
		fmt.Fprintf(conn, "ERR %s\n", oneLine(err))
		return
	}
	defer target.Close()
	if _, err := fmt.Fprint(conn, "OK\n"); err != nil {
		return
	}
	conn.SetDeadline(time.Time{})
	Pipe(conn, target)
}

func oneLine(err error) string {
	s := strings.NewReplacer("\n", " ", "\r", " ").Replace(err.Error())
	if len(s) > 120 {
		s = s[:120]
	}
	return s
}

// closeWriter is a connection that can half-close: a TCP or Unix connection.
type closeWriter interface{ CloseWrite() error }

// Pipe copies between two connections until both directions end, passing a half-close
// on, and closes both. An error in either direction ends both at once.
func Pipe(a, b net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)
	copyHalf := func(dst, src net.Conn) {
		defer wg.Done()
		_, err := io.Copy(dst, src)
		if cw, ok := dst.(closeWriter); ok && err == nil {
			cw.CloseWrite()
			return
		}
		// A failed direction ends the other: the connection is no use half broken.
		a.Close()
		b.Close()
	}
	go copyHalf(a, b)
	go copyHalf(b, a)
	wg.Wait()
	a.Close()
	b.Close()
}
