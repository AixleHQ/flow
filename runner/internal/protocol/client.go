package protocol

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Endpoint names one of the gateway's endpoints, for Classify.
type Endpoint string

const (
	EndpointRegister     Endpoint = "register"
	EndpointRegistration Endpoint = "registration"
	EndpointToken        Endpoint = "token"
	EndpointOps          Endpoint = "ops"
	EndpointResult       Endpoint = "result"
	EndpointReleases     Endpoint = "releases"
	EndpointProxy        Endpoint = "proxy"
)

// Client calls the gateway. It holds no credentials: every call takes the token
// its endpoint needs (§4), so the caller decides which one it presents.
type Client struct {
	baseURL *url.URL
	version string
	http    *http.Client
	// proxy carries the callback proxy's requests (§5.8). It has no overall
	// timeout: an MCP answer may stream for as long as a tool runs.
	proxy *http.Client
}

// NewClient returns a client of the platform at platformURL, sending version in
// X-Aixle-Runner-Version. The URL must be https, except for a loopback host, which
// is how a local gateway is reached in development.
func NewClient(platformURL, version string, httpClient *http.Client) (*Client, error) {
	u, err := ParsePlatformURL(platformURL)
	if err != nil {
		return nil, err
	}
	var proxyClient *http.Client
	if httpClient == nil {
		httpClient = &http.Client{
			// The long-poll is held for up to 25 s; the margin covers the gateway's own
			// work before and after the wait.
			Timeout: MaxWait + 35*time.Second,
		}
		proxyClient = &http.Client{}
	} else {
		// A copy, so the caller's client keeps its own redirect policy.
		clone := *httpClient
		proxyClient = &clone
	}
	// The endpoint's answer comes back unchanged (§5.8), a redirect included.
	// Following one would send the bearer to a path outside the proxy prefix, or
	// the agent's session-key headers to another origin.
	proxyClient.CheckRedirect = func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}
	return &Client{baseURL: u, version: version, http: httpClient, proxy: proxyClient}, nil
}

// ParsePlatformURL checks the --url a runner is configured with.
func ParsePlatformURL(raw string) (*url.URL, error) {
	u, err := url.Parse(strings.TrimRight(strings.TrimSpace(raw), "/"))
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("the platform URL %q is not an absolute URL", raw)
	}
	if u.RawQuery != "" || u.Fragment != "" || u.User != nil {
		return nil, fmt.Errorf("the platform URL %q must not carry a query, a fragment or user info", raw)
	}
	switch u.Scheme {
	case "https":
	case "http":
		if !isLoopback(u.Hostname()) {
			return nil, fmt.Errorf("the platform URL %q must use https", raw)
		}
	default:
		return nil, fmt.Errorf("the platform URL %q must use https", raw)
	}
	return u, nil
}

func isLoopback(host string) bool {
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// Register spends a registration token (§5.1).
func (c *Client) Register(ctx context.Context, registrationToken string, req RegisterRequest) (Registration, error) {
	var out Registration
	err := c.do(ctx, EndpointRegister, http.MethodPost, "/runner/v1/register", registrationToken, req, http.StatusCreated, &out)
	return out, err
}

// Unregister removes this machine and revokes all of its tokens (§5.2).
func (c *Client) Unregister(ctx context.Context, accessToken string) error {
	return c.do(ctx, EndpointRegistration, http.MethodDelete, "/runner/v1/registration", accessToken, nil, http.StatusNoContent, nil)
}

// Refresh spends a refresh token for a new pair (§5.3).
func (c *Client) Refresh(ctx context.Context, refreshToken string) (TokenPair, error) {
	var out TokenPair
	err := c.do(ctx, EndpointToken, http.MethodPost, "/runner/v1/token", refreshToken, nil, http.StatusOK, &out)
	return out, err
}

// PollOps is the long-poll (§5.4). wait is sent in whole seconds.
func (c *Client) PollOps(ctx context.Context, accessToken string, after int64, wait time.Duration) (Poll, error) {
	path := "/runner/v1/ops?after=" + strconv.FormatInt(after, 10) + "&wait=" + strconv.Itoa(int(wait/time.Second))
	var out Poll
	if err := c.do(ctx, EndpointOps, http.MethodGet, path, accessToken, nil, http.StatusOK, &out); err != nil {
		return Poll{}, err
	}
	if out.Ops == nil {
		out.Ops = []Op{}
	}
	return out, nil
}

// Checksums reads the pinned digests of a release (§5.7). It takes no token.
func (c *Client) Checksums(ctx context.Context, version string) (Checksums, error) {
	var out Checksums
	err := c.do(ctx, EndpointReleases, http.MethodGet, releasePath(version, "checksums"), "", nil, http.StatusOK, &out)
	return out, err
}

// Release asks where a release's binary for platform (`linux-amd64`) is (§5.6).
// It does not follow the `302`: it returns its Location and the digest the
// platform pins, so the caller downloads from there and verifies. It takes no
// token.
func (c *Client) Release(ctx context.Context, version, platform string) (ReleaseLocation, error) {
	req, err := c.newRequest(ctx, EndpointReleases, http.MethodGet, releasePath(version, platform), "", nil)
	if err != nil {
		return ReleaseLocation{}, err
	}
	noRedirect := *c.http
	noRedirect.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	resp, err := noRedirect.Do(req)
	if err != nil {
		return ReleaseLocation{}, &NetworkError{Endpoint: EndpointReleases, Err: err}
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return ReleaseLocation{}, &NetworkError{Endpoint: EndpointReleases, Err: err}
	}
	if resp.StatusCode != http.StatusFound {
		return ReleaseLocation{}, newRefusal(EndpointReleases, resp.StatusCode, raw)
	}
	out := ReleaseLocation{Location: resp.Header.Get("Location"), SHA256: resp.Header.Get("X-Aixle-Runner-Sha256")}
	if out.Location == "" || out.SHA256 == "" {
		return ReleaseLocation{}, &NetworkError{Endpoint: EndpointReleases,
			Err: errors.New("the gateway's 302 lacks Location or X-Aixle-Runner-Sha256")}
	}
	return out, nil
}

// releasePath is a release's path. The caller passes a version it has parsed as
// a semantic version and a platform of `[a-z0-9-]`, so neither needs escaping.
func releasePath(version, leaf string) string {
	return "/runner/v1/releases/" + version + "/" + leaf
}

// PostResult reports an op's outcome (§5.5).
func (c *Client) PostResult(ctx context.Context, accessToken string, opID int64, result Result) (ResultState, error) {
	var out ResultState
	path := "/runner/v1/ops/" + strconv.FormatInt(opID, 10) + "/result"
	err := c.do(ctx, EndpointResult, http.MethodPost, path, accessToken, result, http.StatusOK, &out)
	return out, err
}

// Proxy sends one request of the callback proxy (§5.8) to
// `/runner/v1/proxy/<path>`: method, path below the prefix with its query,
// the agent's headers and body, unchanged, with the access token as the bearer
// and the protocol's headers. The gateway's own refusal, which carries
// X-Aixle-Runner-Refusal, is returned as a *Refusal. Any other answer is the
// internal endpoint's, returned as it is, for the caller to stream and close.
func (c *Client) Proxy(ctx context.Context, accessToken, method, path string, header http.Header, body []byte) (*http.Response, error) {
	// path is as the agent sent it, percent-encoded, and stays so.
	below, query, _ := strings.Cut(path, "?")
	parsed, err := url.Parse(strings.TrimRight(c.baseURL.EscapedPath(), "/") + ProxyPathPrefix + strings.TrimLeft(below, "/"))
	if err != nil {
		return nil, fmt.Errorf("building the proxy request: %w", err)
	}
	target := *c.baseURL
	target.Path, target.RawPath, target.RawQuery = parsed.Path, parsed.RawPath, query

	var reader io.Reader
	if len(body) > 0 {
		reader = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, target.String(), reader)
	if err != nil {
		return nil, fmt.Errorf("building the proxy request: %w", err)
	}
	for name, values := range header {
		for _, v := range values {
			req.Header.Add(name, v)
		}
	}
	req.Header.Set("X-Aixle-Runner-Protocol", ProtocolVersion)
	req.Header.Set("X-Aixle-Runner-Version", c.version)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := c.proxy.Do(req)
	if err != nil {
		// net/http names the URL in its error, never a header, so no key is in
		// it. The URL carries the agent's query, so the relay logs only the
		// error it wraps.
		return nil, &NetworkError{Endpoint: EndpointProxy, Err: err}
	}
	if resp.Header.Get(RefusalHeader) == "" {
		return resp, nil
	}
	defer resp.Body.Close()
	refusal, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return nil, &NetworkError{Endpoint: EndpointProxy, Err: err}
	}
	return nil, newRefusal(EndpointProxy, resp.StatusCode, refusal)
}

func (c *Client) do(ctx context.Context, endpoint Endpoint, method, path, token string, body any, want int, out any) error {
	req, err := c.newRequest(ctx, endpoint, method, path, token, body)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		// net/http names the URL in its error, never a header, so no token is in it.
		return &NetworkError{Endpoint: endpoint, Err: err}
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return &NetworkError{Endpoint: endpoint, Err: err}
	}

	if resp.StatusCode != want {
		return newRefusal(endpoint, resp.StatusCode, raw)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return &NetworkError{Endpoint: endpoint, Err: fmt.Errorf("the gateway's %d answer is not the expected JSON: %w", resp.StatusCode, err)}
	}
	return nil
}

// newRequest builds a request with the protocol's headers (§1), and the token as
// the bearer when there is one. The release endpoints take neither protocol
// header (§1, §5.6, §5.7): an operator downloads a binary before the machine has
// a version or a protocol to report, so the runner sends them none either.
func (c *Client) newRequest(ctx context.Context, endpoint Endpoint, method, path, token string, body any) (*http.Request, error) {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("encoding the %s request: %w", endpoint, err)
		}
		reader = bytes.NewReader(encoded)
	}

	target := *c.baseURL
	target.Path = strings.TrimRight(target.Path, "/") + path
	if i := strings.IndexByte(target.Path, '?'); i >= 0 {
		target.RawQuery = target.Path[i+1:]
		target.Path = target.Path[:i]
	}

	req, err := http.NewRequestWithContext(ctx, method, target.String(), reader)
	if err != nil {
		return nil, fmt.Errorf("building the %s request: %w", endpoint, err)
	}
	if endpoint != EndpointReleases {
		req.Header.Set("X-Aixle-Runner-Protocol", ProtocolVersion)
		req.Header.Set("X-Aixle-Runner-Version", c.version)
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	return req, nil
}

// maxResponseBytes bounds what the runner reads of one answer. The largest is a
// batch of 20 ops, each payload well under the gateway's own 2 MiB body cap.
const maxResponseBytes = 64 << 20

// NetworkError is a request that got no usable answer: the connection failed, it
// timed out, or the body could not be read. It is retried with backoff.
type NetworkError struct {
	Endpoint Endpoint
	Err      error
}

func (e *NetworkError) Error() string {
	return fmt.Sprintf("%s: %v", e.Endpoint, e.Err)
}

func (e *NetworkError) Unwrap() error { return e.Err }

// Refusal is any answer other than the endpoint's success status (§3).
type Refusal struct {
	Endpoint Endpoint
	Status   int
	// Code is the refusal's `error`, or "" when the body is not the JSON refusal
	// shape (413, 429, an unserved path's 404, a 400 for a body that is not JSON).
	Code string
	// Message is for people and may change.
	Message string
}

func (r *Refusal) Error() string {
	if r.Code == "" {
		return fmt.Sprintf("%s: the gateway answered %d", r.Endpoint, r.Status)
	}
	return fmt.Sprintf("%s: the gateway answered %d %s: %s", r.Endpoint, r.Status, r.Code, r.Message)
}

func newRefusal(endpoint Endpoint, status int, raw []byte) *Refusal {
	r := &Refusal{Endpoint: endpoint, Status: status}
	var shape map[string]json.RawMessage
	if json.Unmarshal(raw, &shape) != nil || len(shape) != 2 {
		return r
	}
	var code, message string
	if json.Unmarshal(shape["error"], &code) != nil || json.Unmarshal(shape["message"], &message) != nil {
		return r
	}
	r.Code, r.Message = code, message
	return r
}

// AsRefusal returns the refusal inside err, if there is one.
func AsRefusal(err error) (*Refusal, bool) {
	var r *Refusal
	ok := errors.As(err, &r)
	return r, ok
}
