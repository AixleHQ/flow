package proxy

import (
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

// SocketName is the relay's socket in a session's socket directory.
const SocketName = "relay.sock"

// Host serves the relay for the sessions of one environment: on a Unix socket
// per session, in a directory that the session's sidecar mounts, or with
// `network: host` on a port of the machine's 127.0.0.1. A session has at most
// one of them, and only while its container runs.
//
// The socket directories are under the state directory, `<state>/proxy/<session>`,
// so that only the runner's own user can reach them on the machine (the state
// directory is 0700). Inside the sidecar the directory is mounted read-only,
// and the socket is 0666, so the sidecar connects as any user.
type Host struct {
	StateDir string
	// Handler is the relay. Host serves it on a socket as it is, and on a local
	// listener behind Local.
	Handler http.Handler
	Logger  *slog.Logger
	// binary is the runner's own executable, which the sidecar runs.
	binary string

	mu      sync.Mutex
	servers map[int64]*http.Server
}

// NewHost returns the relay's host for the state directory. binary is the
// path of the runner's own executable, as the Docker daemon resolves it.
func NewHost(stateDir, binary string, handler http.Handler, logger *slog.Logger) *Host {
	if logger == nil {
		logger = slog.Default()
	}
	// The daemon takes only an absolute bind source.
	if abs, err := filepath.Abs(stateDir); err == nil {
		stateDir = abs
	}
	return &Host{StateDir: stateDir, Handler: handler, Logger: logger, binary: binary, servers: map[int64]*http.Server{}}
}

// Binary is the runner's own executable, bind-mounted into the sidecar.
func (h *Host) Binary() string { return h.binary }

func (h *Host) root() string { return filepath.Join(h.StateDir, "proxy") }

// SocketDir is a session's socket directory.
func (h *Host) SocketDir(sessionID int64) string {
	return filepath.Join(h.root(), strconv.FormatInt(sessionID, 10))
}

// OpenSocket serves the relay on the session's socket and returns its
// directory. A socket left by an earlier start (a restarted host runner) is
// replaced in the same directory. The directory itself is kept: a running
// sidecar has it bind-mounted, and a bind mount follows the directory's inode,
// not its path, so only a socket in that same directory reaches the sidecar.
func (h *Host) OpenSocket(sessionID int64) (string, error) {
	h.stopServer(sessionID)
	if err := os.MkdirAll(h.root(), 0o711); err != nil {
		return "", fmt.Errorf("creating %s: %w", h.root(), err)
	}
	dir := h.SocketDir(sessionID)
	if err := os.Mkdir(dir, 0o755); err != nil && !errors.Is(err, os.ErrExist) {
		return "", fmt.Errorf("creating %s: %w", dir, err)
	}
	// The umask must not narrow what the sidecar needs.
	if err := os.Chmod(dir, 0o755); err != nil {
		return "", err
	}
	path := filepath.Join(dir, SocketName)
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("removing the stale socket %s: %w", path, err)
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return "", fmt.Errorf("listening on %s: %w", path, err)
	}
	if err := os.Chmod(path, 0o666); err != nil {
		listener.Close()
		return "", err
	}
	h.serve(sessionID, listener, h.Handler, "socket", path)
	return dir, nil
}

// OpenListener serves the relay on 127.0.0.1:port of the machine, for a
// session with `network: host`. A port that is taken is an error that wraps
// syscall.EADDRINUSE.
func (h *Host) OpenListener(sessionID int64, port int) error {
	h.stopServer(sessionID)
	address := net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", address, err)
	}
	h.serve(sessionID, listener, Local(h.Handler), "listener", address)
	return nil
}

func (h *Host) serve(sessionID int64, listener net.Listener, handler http.Handler, kind, address string) {
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 30 * time.Second}
	h.mu.Lock()
	h.servers[sessionID] = server
	h.mu.Unlock()
	h.Logger.Info("serving the callback proxy", "session", sessionID, kind, address)
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			h.Logger.Warn("the callback proxy stopped", "session", sessionID, kind, address, "error", err)
		}
	}()
}

// Close stops the session's relay, at once: its container is gone or going,
// and a call still in flight is cut. Its socket directory is removed.
func (h *Host) Close(sessionID int64) {
	h.stopServer(sessionID)
	_ = os.RemoveAll(h.SocketDir(sessionID))
}

// stopServer stops the session's relay server, if it has one, and leaves its
// socket directory.
func (h *Host) stopServer(sessionID int64) {
	h.mu.Lock()
	server := h.servers[sessionID]
	delete(h.servers, sessionID)
	h.mu.Unlock()
	if server != nil {
		_ = server.Close()
	}
}

// CloseAll stops every session's relay and removes every socket directory, as
// a scrub or a reset leaves no session on the environment.
func (h *Host) CloseAll() {
	h.mu.Lock()
	servers := h.servers
	h.servers = map[int64]*http.Server{}
	h.mu.Unlock()
	for _, server := range servers {
		_ = server.Close()
	}
	_ = os.RemoveAll(h.root())
}

// Stop stops every relay when the host runner stops, cutting the calls in
// flight: the agent retries them (DESIGN.md §6.7). The socket directories
// stay, so that a restarted host runner serves the running sidecars in the
// same directories again.
func (h *Host) Stop() {
	h.mu.Lock()
	servers := h.servers
	h.servers = map[int64]*http.Server{}
	h.mu.Unlock()
	for _, server := range servers {
		_ = server.Close()
	}
}
