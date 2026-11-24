package relay

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"

	"github.com/aixlehq/aixle-runner-relay/internal/rails"
	"github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// EdgePrefix is where the browser's traffic arrives: `/t/<route_token>/<surface>/<rest>`.
const EdgePrefix = "/t/"

// routeToken is what the platform generates (SecureRandom.hex(16)); the pattern is wider
// than that so a longer token later is not refused, and narrow enough that nothing
// odd reaches Rails in a path.
var routeToken = regexp.MustCompile(`^[0-9A-Za-z_-]{16,64}$`)

// retryAfter is the Retry-After of a session whose tunnel is briefly down (§7.1).
const retryAfter = "2"

// stripped says whether the relay strips `/t/<token>/<surface>` before the request
// reaches the port: the hosted `stripPrefix` middlewares do, except for `ide`, whose
// OpenVSCode runs with `--server-base-path /t/<token>/ide` (§7.2).
func stripped(surface string) bool { return surface != "ide" }

type edgeKey struct{}

// edgeTarget is what the edge handler decided for one request, for the proxy's Rewrite.
type edgeTarget struct {
	surface   string
	sessionID int64
	port      int
	// path and rawPath are the path the port sees.
	path, rawPath string
}

// edgeTokens parses a request path into its token, surface and the rest (starting
// with a slash, or empty). ok is false for anything but the five surfaces and a
// well-formed token.
func edgeTokens(escapedPath string) (token, surface, rest string, ok bool) {
	p, found := strings.CutPrefix(escapedPath, EdgePrefix)
	if !found {
		return "", "", "", false
	}
	token, p, _ = strings.Cut(p, "/")
	if !routeToken.MatchString(token) {
		return "", "", "", false
	}
	idx := strings.IndexByte(p, '/')
	if idx < 0 {
		surface, rest = p, ""
	} else {
		surface, rest = p[:idx], p[idx:]
	}
	for _, s := range Surfaces {
		if s == surface {
			return token, surface, rest, true
		}
	}
	return "", "", "", false
}

// edge is the browser's entry: it finds the session and its machine, checks that
// Traefik's header names the same session, and proxies over a stream (§7.1).
func (s *Server) edge(w http.ResponseWriter, r *http.Request) {
	token, surface, rest, ok := edgeTokens(r.URL.EscapedPath())
	if !ok {
		s.edgeRefuse(w, r, http.StatusNotFound, "not_found", "not_found", "", refusal{reason: "bad_route"})
		return
	}
	route, status, code, why := s.resolve(r.Context(), token)
	if status != 0 {
		retry := ""
		if status == http.StatusServiceUnavailable {
			retry = retryAfter
		}
		why.surface = surface
		s.edgeRefuse(w, r, status, code, code, retry, why)
		return
	}
	// Defence in depth: the header is Traefik's, written after ws_auth, and must name the
	// session the token names.
	if r.Header.Get("X-Session-Id") != strconv.FormatInt(route.SessionID, 10) {
		s.edgeRefuse(w, r, http.StatusForbidden, "forbidden", "session_mismatch", "", refusal{reason: "session_mismatch", route: &route, surface: surface})
		return
	}
	m, connected := s.registry.Machine(route.EnvironmentID)
	port := route.Ports[surface]
	if !connected || port == 0 {
		reason := "machine_not_connected"
		if connected {
			reason = "no_port"
		}
		s.edgeRefuse(w, r, http.StatusServiceUnavailable, "unavailable", reason, retryAfter, refusal{reason: reason, route: &route, surface: surface})
		return
	}

	target := edgeTarget{surface: surface, sessionID: route.SessionID, port: port}
	if stripped(surface) {
		target.rawPath = rest
		if target.rawPath == "" {
			target.rawPath = "/"
		}
	} else {
		target.rawPath = r.URL.EscapedPath()
	}
	unescaped, err := url.PathUnescape(target.rawPath)
	if err != nil {
		s.edgeRefuse(w, r, http.StatusBadRequest, "bad_request", "bad_path", "", refusal{reason: "bad_path", route: &route, surface: surface})
		return
	}
	target.path = unescaped
	if unescaped == target.rawPath {
		target.rawPath = ""
	}

	ctx, cancel := context.WithCancel(context.WithValue(r.Context(), edgeKey{}, target))
	defer cancel()
	end := m.beginRequest(route.SessionID, cancel)
	defer end()
	// The session may have left the machine between the lookup and the registration; a
	// signal updates the registry before it ends the session's requests, so one that
	// registered late sees the change here and does not outlive it.
	if cur, ok := s.registry.Session(route.EnvironmentID); !ok || cur.SessionID != route.SessionID {
		s.edgeRefuse(w, r, http.StatusServiceUnavailable, "unavailable", "session_changed", retryAfter, refusal{reason: "session_changed", route: &route, surface: surface})
		return
	}
	s.metrics.EdgeRequests.WithLabelValues("proxied").Inc()
	m.proxy.ServeHTTP(w, r.WithContext(ctx))
}

// resolve finds the session a route token names: from the registry, or with one
// `holders` call on a miss. A non-zero status is the refusal to send, and why says why
// (for the log).
func (s *Server) resolve(ctx context.Context, token string) (route SessionRoute, status int, code string, why refusal) {
	if route, ok := s.registry.ByRouteToken(token); ok && route.SessionID != 0 && len(route.Ports) > 0 {
		return route, 0, "", refusal{}
	}
	if s.opts.Rails == nil {
		return route, http.StatusServiceUnavailable, "unavailable", refusal{reason: "no_platform"}
	}
	gen := s.routeGeneration()
	holder, err := s.opts.Rails.Holders(ctx, token)
	switch {
	case errors.Is(err, rails.ErrNotFound):
		return route, http.StatusNotFound, "not_found", refusal{reason: "unknown_token"}
	case err != nil:
		return route, http.StatusServiceUnavailable, "unavailable", refusal{reason: "holders_error", err: err, quiet: ctx.Err() != nil}
	case holder.EnvironmentID == nil:
		// No machine holds the session now: it is not gone, the machine may be between two
		// sessions' hands or reconnecting.
		return route, http.StatusServiceUnavailable, "unavailable", refusal{reason: "holders_no_machine", sessionID: holder.SessionID}
	}
	route = SessionRoute{SessionID: holder.SessionID, EnvironmentID: *holder.EnvironmentID, RouteToken: token, Ports: holder.Ports}
	if !validPorts(route.Ports) {
		return route, http.StatusServiceUnavailable, "unavailable", refusal{reason: "holders_bad_ports", route: &route}
	}
	// The answer may be older than a signal that arrived while the call was out. If no
	// signal changed a route since the call began, the answer is the newest word the
	// relay has, and it replaces whatever the registry holds for the machine: a session
	// the relay still has there is one whose end or change it never heard of, and
	// keeping it would refuse every request of the real one. Otherwise it is stored
	// only if the registry still has no routed session for the machine (the placeholder
	// a connection's ticket leaves has no token); this request uses it either way.
	s.applyHolders(route, gen)
	return route, 0, "", refusal{}
}

// validPorts says whether ports names every surface with a port of 1024 to 65535.
func validPorts(ports map[string]int) bool {
	for _, surface := range Surfaces {
		if p := ports[surface]; p < 1024 || p > 65535 {
			return false
		}
	}
	return true
}

// refusal says why the edge refused a request or a stream failed, for the log.
type refusal struct {
	reason    string
	route     *SessionRoute
	sessionID int64
	surface   string
	err       error
	// quiet keeps the line out of the log: the browser went away.
	quiet bool
}

// log writes one line for a refused request: the status, a reason code, the session,
// the surface and the environment. The route token, the ticket and the headers are
// never in it.
func (s *Server) logRefusal(r *http.Request, status int, why refusal) {
	if why.quiet || why.reason == "" {
		return
	}
	attrs := []any{"status", status, "reason", why.reason, "surface", why.surface}
	sessionID := why.sessionID
	if why.route != nil {
		sessionID = why.route.SessionID
		attrs = append(attrs, "environment_id", why.route.EnvironmentID)
	}
	if sessionID != 0 {
		attrs = append(attrs, "session_id", sessionID)
	}
	if why.err != nil {
		attrs = append(attrs, "error", why.err.Error())
	}
	level := slog.LevelWarn
	if status < 500 {
		level = slog.LevelInfo
	}
	s.log.Log(r.Context(), level, "the edge refused a request", attrs...)
}

func (s *Server) edgeRefuse(w http.ResponseWriter, r *http.Request, status int, code, result, retry string, why refusal) {
	s.metrics.EdgeRequests.WithLabelValues(result).Inc()
	s.logRefusal(r, status, why)
	if retry != "" {
		w.Header().Set("Retry-After", retry)
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": code})
}

// newProxy builds a machine's transport and reverse proxy: the transport dials by
// opening a stream, so keep-alive, WebSocket upgrades, chunked bodies and the IDE's
// parallel requests are net/http's (§4).
func (s *Server) newProxy(m *Machine) {
	m.transport = &http.Transport{
		DialContext: func(ctx context.Context, _, addr string) (net.Conn, error) {
			return s.dial(ctx, m, addr)
		},
		// The bytes are the browser's: nothing is decompressed or recompressed here.
		DisableCompression:  true,
		MaxIdleConnsPerHost: 2,
		IdleConnTimeout:     20 * time.Second,
		// The tunnel's streams are scarce (64 per machine), so the pool stays small.
		MaxIdleConns: 10,
	}
	m.proxy = &httputil.ReverseProxy{
		Transport: m.transport,
		Rewrite: func(pr *httputil.ProxyRequest) {
			t, _ := pr.In.Context().Value(edgeKey{}).(edgeTarget)
			out := pr.Out
			out.URL.Scheme = "http"
			out.URL.Host = streamHost(t)
			out.URL.Path, out.URL.RawPath = t.path, t.rawPath
			// The Host header stays the browser's, as Traefik sent it: OpenVSCode and ttyd
			// compare it with the Origin of a WebSocket.
			out.Host = pr.In.Host
			// Rewrite drops the forwarding headers; what Traefik added is kept as it is.
			for _, h := range []string{"Forwarded", "X-Forwarded-For", "X-Forwarded-Host", "X-Forwarded-Proto"} {
				if v, ok := pr.In.Header[h]; ok {
					out.Header[h] = v
				}
			}
			// Which user and session it is was Traefik's to say, and the port has no use of it.
			out.Header.Del("X-User-Id")
			out.Header.Del("X-Session-Id")
		},
		FlushInterval: -1,
		ErrorHandler:  s.proxyError,
		// A read that broke mid-body is an ordinary end of a browser's connection here.
		ErrorLog: slog.NewLogLogger(s.log.Handler(), slog.LevelDebug),
	}
}

// streamHost is the host the transport dials: the stream's target in the name, so each
// (session, port) has a pool of its own and DialContext knows what to open.
func streamHost(t edgeTarget) string {
	return fmt.Sprintf("%s.%d.%d.tunnel", t.surface, t.sessionID, t.port)
}

func parseStreamHost(addr string) (surface string, sessionID int64, port int, err error) {
	host, _, splitErr := net.SplitHostPort(addr)
	if splitErr != nil {
		host = addr
	}
	parts := strings.Split(strings.TrimSuffix(host, ".tunnel"), ".")
	if len(parts) != 3 {
		return "", 0, 0, fmt.Errorf("not a stream host: %q", host)
	}
	sessionID, err = strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return "", 0, 0, err
	}
	port, err = strconv.Atoi(parts[2])
	return parts[0], sessionID, port, err
}

// dial opens a stream to a port of a session on the machine.
func (s *Server) dial(ctx context.Context, m *Machine, addr string) (net.Conn, error) {
	surface, sessionID, port, err := parseStreamHost(addr)
	if err != nil {
		return nil, err
	}
	start := time.Now()
	st, err := m.sess.Open(ctx, sessionID, port)
	s.metrics.DialSeconds.Observe(time.Since(start).Seconds())
	if err != nil {
		var reset *tunnel.ResetError
		if errors.As(err, &reset) {
			s.metrics.StreamResets.WithLabelValues(reset.Code.String()).Inc()
		}
		return nil, err
	}
	conn := &stream{Stream: st, surface: surface, sessionID: sessionID, machine: m, server: s}
	m.track(sessionID, conn)
	s.metrics.StreamsOpen.WithLabelValues(surface).Inc()
	return conn, nil
}

// stream is a tunnel stream as the transport's connection: it leaves the machine's
// table and the gauge when it closes.
type stream struct {
	*tunnel.Stream
	surface   string
	sessionID int64
	machine   *Machine
	server    *Server
	done      atomic.Bool
}

func (c *stream) Close() error {
	c.release()
	return c.Stream.Close()
}

// Reset ends the stream with a code, counts it, and releases it.
func (c *stream) Reset(code tunnel.ResetCode, text string) error {
	c.server.metrics.StreamResets.WithLabelValues(code.String()).Inc()
	c.release()
	return c.Stream.Reset(code, text)
}

func (c *stream) release() {
	if c.done.CompareAndSwap(false, true) {
		c.machine.untrack(c.sessionID, c)
		c.server.metrics.StreamsOpen.WithLabelValues(c.surface).Dec()
	}
}

// proxyError answers the browser when the stream could not be opened or broke.
func (s *Server) proxyError(w http.ResponseWriter, r *http.Request, err error) {
	t, _ := r.Context().Value(edgeKey{}).(edgeTarget)
	route := &SessionRoute{SessionID: t.sessionID}
	if cur, ok := s.registry.BySession(t.sessionID); ok {
		route.EnvironmentID = cur.EnvironmentID
	}
	why := refusal{route: route, surface: t.surface, err: err}
	var reset *tunnel.ResetError
	switch {
	case errors.Is(err, context.Canceled) || r.Context().Err() != nil:
		// The browser went away, or the session ended: nobody is left to answer.
		s.metrics.EdgeRequests.WithLabelValues("cancelled").Inc()
		w.WriteHeader(http.StatusBadGateway)
	case errors.Is(err, tunnel.ErrStreamLimit), errors.Is(err, tunnel.ErrGoAway), errors.Is(err, tunnel.ErrSessionClosed):
		why.reason = "tunnel_unavailable"
		s.edgeRefuse(w, r, http.StatusServiceUnavailable, "unavailable", "unavailable", retryAfter, why)
	case errors.As(err, &reset) && reset.Code == tunnel.ResetSessionChange:
		why.reason = "stream_reset"
		s.edgeRefuse(w, r, http.StatusServiceUnavailable, "unavailable", "session_changed", retryAfter, why)
	case errors.As(err, &reset):
		// refused, dial_failed, timeout: the runner or the port did not take the stream.
		// A terminal that is not listening yet is the window of §9, and ttyd's own client
		// retries.
		if reset.Code == tunnel.ResetRefused {
			why.reason = "stream_refused"
		} else {
			why.reason = "stream_reset"
		}
		s.edgeRefuse(w, r, http.StatusBadGateway, "bad_gateway", "bad_gateway", "", why)
	default:
		why.reason = "proxy_error"
		s.edgeRefuse(w, r, http.StatusBadGateway, "bad_gateway", "bad_gateway", "", why)
	}
}
