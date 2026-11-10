package proxy

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"strings"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// SidecarOptions are the inputs of `aixle-runner --mode proxy`.
type SidecarOptions struct {
	// Socket is the host runner's relay socket, mounted into the sidecar.
	Socket string
	// Listen is the address the agent calls, 127.0.0.1:<protocol.ProxyPort>.
	Listen string
	Logger *slog.Logger
	// Ready, when set, receives the listener's address once it accepts.
	Ready chan<- string
}

// RunSidecar is `aixle-runner --mode proxy`: it listens on opts.Listen, in the
// agent's network namespace, and relays every request to the host runner's
// socket as `/runner/v1/proxy/<route>/…`, streaming the answer back. It holds
// no credential and reads nothing but the socket. It runs until ctx is done.
func RunSidecar(ctx context.Context, opts SidecarOptions) error {
	logger := opts.Logger
	if logger == nil {
		logger = slog.Default()
	}
	if opts.Socket == "" || opts.Listen == "" {
		return errors.New("the proxy needs --socket and --listen")
	}
	listener, err := net.Listen("tcp", opts.Listen)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", opts.Listen, err)
	}
	server := &http.Server{Handler: SidecarHandler(opts.Socket, logger), ReadHeaderTimeout: 30 * time.Second}
	logger.Info("aixle-runner proxy listening", "listen", listener.Addr().String(), "socket", opts.Socket)
	if opts.Ready != nil {
		opts.Ready <- listener.Addr().String()
	}

	done := make(chan error, 1)
	go func() { done <- server.Serve(listener) }()
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
		return nil
	}
}

// SidecarHandler relays to the relay socket at socket, under the proxy route's
// prefix. It reads the request's body first, within bodyReadTimeout and up to
// the gateway's cap, as the relay does.
func SidecarHandler(socket string, logger *slog.Logger) http.Handler {
	relay := sidecarProxy(socket, logger)
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		body, ok := readBody(w, req)
		if !ok {
			return
		}
		req.TransferEncoding = nil
		req.ContentLength = int64(len(body))
		req.Body = http.NoBody
		if len(body) > 0 {
			req.Body = io.NopCloser(bytes.NewReader(body))
		}
		relay.ServeHTTP(w, req)
	})
}

func sidecarProxy(socket string, logger *slog.Logger) *httputil.ReverseProxy {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, "unix", socket)
		},
		MaxIdleConns:    16,
		IdleConnTimeout: 90 * time.Second,
	}
	return &httputil.ReverseProxy{
		// Rewrite, not Director: no X-Forwarded-* header is added, and the
		// hop-by-hop headers are dropped.
		Rewrite: func(r *httputil.ProxyRequest) {
			r.Out.URL.Scheme = "http"
			r.Out.URL.Host = "relay"
			r.Out.Host = "relay"
			r.Out.URL.Path = protocol.ProxyPathPrefix + strings.TrimPrefix(r.In.URL.Path, "/")
			if r.In.URL.RawPath != "" {
				r.Out.URL.RawPath = protocol.ProxyPathPrefix + strings.TrimPrefix(r.In.URL.RawPath, "/")
			}
		},
		Transport: transport,
		// Every chunk at once: an MCP answer may be a stream of events.
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			if r.Context().Err() == nil {
				logger.Warn("relaying to the host runner failed", "method", r.Method, "error", err)
			}
			WriteRefusal(w, http.StatusBadGateway, ClassRelayFailed, "the host runner does not answer on its socket")
		},
	}
}
