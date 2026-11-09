// Package proxy is the callback proxy of runner/protocol/PROTOCOL.md §5.6
// (DESIGN.md §6.6, §6.9.3). An agent on a runner cannot reach the platform's
// internal address, so it calls `http://127.0.0.1:<port>/<route>/…` instead:
//
//   - The sidecar (`aixle-runner --mode proxy`, RunSidecar) listens there, in
//     the agent's network namespace, and relays every request over a Unix
//     socket to the host runner. It holds no credential.
//   - The host runner (Relay, served by Host on that socket) adds the
//     environment's access token and sends the request to the gateway's
//     `/runner/v1/proxy/<route>/…`, which forwards it to the platform. It
//     serves nothing else on the socket: never ops, results, `token` or
//     `check-in`.
//   - With `network: host` there is no sidecar: Host listens on the machine's
//     127.0.0.1 itself, on the session's own port.
package proxy

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Gateway is the protocol client's proxy call.
type Gateway interface {
	Proxy(ctx context.Context, accessToken, method, path string, header http.Header, body []byte) (*http.Response, error)
}

// Tokens runs a call with the machine's access token, refreshing it once on an
// `invalid_token` (tokens.Source).
type Tokens interface {
	Do(ctx context.Context, call func(accessToken string) error) error
}

// The classes of the refusals the host runner answers itself, in the gateway's
// refusal shape (PROTOCOL.md §3, §5.6).
const (
	// ClassRelayFailed: the host runner could not get an answer from the gateway.
	ClassRelayFailed = "relay_failed"
	// ClassNotProxied: a request on the relay's socket for anything but the proxy
	// route.
	ClassNotProxied = "not_proxied"
	// ClassBodyTooLarge: a body over the gateway's cap, which it would refuse.
	ClassBodyTooLarge = "body_too_large"
)

// hopHeaders are never forwarded in either direction (RFC 9110 §7.6.1), and
// neither are the gateway's own: the relay sets the bearer and the protocol's
// headers itself.
var hopHeaders = []string{
	"Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization", "Proxy-Connection",
	"Te", "Trailer", "Transfer-Encoding", "Upgrade",
}

func dropHop(h http.Header) {
	for _, field := range strings.Split(h.Get("Connection"), ",") {
		if field = strings.TrimSpace(field); field != "" {
			h.Del(field)
		}
	}
	for _, name := range hopHeaders {
		h.Del(name)
	}
}

// Relay is the host runner's end of the proxy: an http.Handler for
// `/runner/v1/proxy/*` that sends each request on to the gateway with the
// environment credential, and streams the answer back. It logs the method and
// path of what it relays, never a header or a body: those carry session keys.
type Relay struct {
	Gateway Gateway
	Tokens  Tokens
	Logger  *slog.Logger
}

func (r *Relay) logger() *slog.Logger {
	if r.Logger == nil {
		return slog.Default()
	}
	return r.Logger
}

func (r *Relay) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	escaped := req.URL.EscapedPath()
	if !strings.HasPrefix(escaped, protocol.ProxyPathPrefix) {
		WriteRefusal(w, http.StatusNotFound, ClassNotProxied, "the host runner serves only the callback proxy here")
		return
	}
	below := strings.TrimPrefix(escaped, protocol.ProxyPathPrefix)
	if req.URL.RawQuery != "" {
		below += "?" + req.URL.RawQuery
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, req.Body, protocol.MaxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			WriteRefusal(w, http.StatusRequestEntityTooLarge, ClassBodyTooLarge, "the request body is over the gateway's 2 MiB cap")
			return
		}
		WriteRefusal(w, http.StatusBadRequest, ClassRelayFailed, "reading the request body failed")
		return
	}
	header := req.Header.Clone()
	dropHop(header)
	header.Del("Authorization")
	for name := range header {
		if strings.HasPrefix(strings.ToLower(name), "x-aixle-runner-") {
			header.Del(name)
		}
	}

	var resp *http.Response
	err = r.Tokens.Do(req.Context(), func(access string) error {
		var err error
		resp, err = r.Gateway.Proxy(req.Context(), access, req.Method, below, header, body)
		return err
	})
	if err != nil {
		route, _, _ := strings.Cut(below, "/")
		if refusal, ok := protocol.AsRefusal(err); ok {
			r.logger().Warn("the gateway refused a proxied request", "method", req.Method, "route", route,
				"status", refusal.Status, "error", refusal.Code)
			code, message := refusal.Code, refusal.Message
			if code == "" {
				code, message = ClassRelayFailed, "the gateway answered "+http.StatusText(refusal.Status)
			}
			WriteRefusal(w, refusal.Status, code, message)
			return
		}
		if req.Context().Err() == nil {
			r.logger().Warn("relaying a proxied request failed", "method", req.Method, "route", route, "error", err)
		}
		WriteRefusal(w, http.StatusBadGateway, ClassRelayFailed, "the host runner could not reach the platform")
		return
	}
	defer resp.Body.Close()

	dropHop(resp.Header)
	for name, values := range resp.Header {
		for _, v := range values {
			w.Header().Add(name, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	Stream(w, resp.Body)
}

// Stream copies body to w, flushing every chunk as it arrives: an MCP answer
// may be a stream of events that must not wait for the end.
func Stream(w http.ResponseWriter, body io.Reader) {
	rc := http.NewResponseController(w)
	buf := make([]byte, 32<<10)
	for {
		n, err := body.Read(buf)
		if n > 0 {
			if _, werr := w.Write(buf[:n]); werr != nil {
				return
			}
			_ = rc.Flush()
		}
		if err != nil {
			return
		}
	}
}

// WriteRefusal answers in the gateway's refusal shape (PROTOCOL.md §3), marked
// as the proxy's own refusal.
func WriteRefusal(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set(protocol.RefusalHeader, code)
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": code, "message": message})
}

// Local is the handler of a local listener: the agent asks for
// `/<route>/…`, which is `/runner/v1/proxy/<route>/…` at the gateway.
func Local(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		out := req.Clone(req.Context())
		out.URL.Path = protocol.ProxyPathPrefix + strings.TrimPrefix(req.URL.Path, "/")
		if req.URL.RawPath != "" {
			out.URL.RawPath = protocol.ProxyPathPrefix + strings.TrimPrefix(req.URL.RawPath, "/")
		}
		next.ServeHTTP(w, out)
	})
}
