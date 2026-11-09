package protocol_test

// The Go side of the conformance suite (runner/protocol/fixtures/README.md). A fake
// gateway is built from each fixture: the client is driven through every exchange
// it can express, the fake checks that the client's request is exactly the
// fixture's request, and answers with the fixture's response, its matchers
// instantiated with concrete values. The client must then read that answer the way
// the protocol says: the success value, or a *Refusal with the fixture's status and
// code.
//
// An exchange the client cannot express is skipped, with the fixture's state kept
// going: a request with a protocol header other than 1, a malformed `after`, a
// body this client never sends. Those exchanges test the gateway's checks, which
// the Rails side of the suite runs. A fixture of which no exchange is driven fails,
// unless gatewayOnly names it with the reason.

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

const fixturesDir = "../../protocol/fixtures/v1"

// The version every fixture request carries unless it replaces it.
const fixtureVersion = "1.4.0"

type fixtureFile struct {
	Description string            `json:"description"`
	Steps       []json.RawMessage `json:"steps"`
}

type fixtureRequest struct {
	Method  string             `json:"method"`
	Path    string             `json:"path"`
	Token   *string            `json:"token"`
	Headers map[string]*string `json:"headers"`
	Body    json.RawMessage    `json:"body"`
}

type fixtureResponse struct {
	Status  int                `json:"status"`
	Headers map[string]*string `json:"headers"`
	Body    json.RawMessage    `json:"body"`
}

// world is one scenario's state: its variables and the fake gateway's clock.
type world struct {
	t       *testing.T
	vars    map[string]any
	clock   time.Time
	counter int64
}

func (w *world) define(name string, value any) {
	w.t.Helper()
	if _, ok := w.vars[name]; ok {
		w.t.Fatalf("variable %q is defined twice", name)
	}
	w.vars[name] = value
}

func (w *world) lookup(name string) any {
	w.t.Helper()
	v, ok := w.vars[name]
	if !ok {
		w.t.Fatalf("variable %q is not defined yet", name)
	}
	return v
}

func (w *world) next() int64 { w.counter++; return w.counter }

func (w *world) timestamp(d time.Duration) string {
	return w.clock.Add(d).UTC().Format("2006-01-02T15:04:05Z")
}

func randomToken(prefix string) string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return prefix + hex.EncodeToString(b)
}

var templateVar = regexp.MustCompile(`\{\{([a-z0-9_.]+)\}\}`)

func (w *world) substitute(s string) string {
	return templateVar.ReplaceAllStringFunc(s, func(m string) string {
		return fmt.Sprint(w.lookup(templateVar.FindStringSubmatch(m)[1]))
	})
}

// requestValue replaces {"$var": name} in a request body.
func (w *world) requestValue(v any) any {
	switch v := v.(type) {
	case map[string]any:
		if name, ok := v["$var"].(string); ok && len(v) == 1 {
			return w.lookup(name)
		}
		out := map[string]any{}
		for k, e := range v {
			out[k] = w.requestValue(e)
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, e := range v {
			out[i] = w.requestValue(e)
		}
		return out
	}
	return v
}

// instantiate turns a response matcher into a concrete value that matches it.
func (w *world) instantiate(v any) any {
	switch v := v.(type) {
	case map[string]any:
		if len(v) == 1 {
			for k, arg := range v {
				if !strings.HasPrefix(k, "$") {
					break
				}
				switch k {
				case "$var":
					return w.lookup(arg.(string))
				case "$prefix":
					return randomToken(arg.(string))
				case "$type":
					switch arg {
					case "string":
						return "text"
					case "integer":
						return w.next()
					case "boolean":
						return false
					case "object":
						return map[string]any{}
					case "array":
						return []any{}
					case "timestamp":
						return w.timestamp(time.Hour)
					}
				}
				w.t.Fatalf("unknown matcher %s %v", k, arg)
			}
		}
		out := map[string]any{}
		for k, e := range v {
			out[k] = w.instantiate(e)
		}
		return out
	case []any:
		out := make([]any, len(v))
		for i, e := range v {
			out[i] = w.instantiate(e)
		}
		return out
	}
	return v
}

func decode(t *testing.T, raw []byte) any {
	t.Helper()
	var v any
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if err := d.Decode(&v); err != nil {
		t.Fatalf("invalid JSON %s: %v", raw, err)
	}
	return normalize(v)
}

// normalize makes JSON values comparable: every number becomes an int64 when it
// is one, a float64 otherwise.
func normalize(v any) any {
	switch v := v.(type) {
	case json.Number:
		if i, err := v.Int64(); err == nil {
			return i
		}
		f, _ := v.Float64()
		return f
	case int:
		return int64(v)
	case map[string]any:
		for k, e := range v {
			v[k] = normalize(e)
		}
	case []any:
		for i, e := range v {
			v[i] = normalize(e)
		}
	}
	return v
}

func toJSON(t *testing.T, v any) []byte {
	t.Helper()
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

// sameJSON says whether two values serialize to the same JSON value.
func sameJSON(t *testing.T, a, b any) bool {
	t.Helper()
	return reflect.DeepEqual(decode(t, toJSON(t, a)), decode(t, toJSON(t, b)))
}

// strictDecode decodes raw into out, refusing unknown keys, and reports whether
// out serializes back to the same JSON: only then can the client send exactly raw.
func strictDecode(t *testing.T, raw []byte, out any) bool {
	t.Helper()
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(out) != nil {
		return false
	}
	return reflect.DeepEqual(decode(t, raw), decode(t, toJSON(t, out)))
}

// call is one client call an exchange maps to.
type call struct {
	endpoint string
	version  string
	run      func(ctx context.Context, c *protocol.Client) (any, error)
	// check, when set, checks a successful answer the response has no body for.
	check func(t *testing.T, got any, headers map[string]*string)
}

var (
	opsPath       = regexp.MustCompile(`^/runner/v1/ops\?after=(\d+)&wait=(\d+)$`)
	resultPath    = regexp.MustCompile(`^/runner/v1/ops/(\d+)/result$`)
	checksumsPath = regexp.MustCompile(`^/runner/v1/releases/([0-9A-Za-z.+-]+)/checksums$`)
	releasePath   = regexp.MustCompile(`^/runner/v1/releases/([0-9A-Za-z.+-]+)/([a-z0-9]+-[a-z0-9_]+)$`)
)

// gatewayOnly are the fixtures of which this client drives no exchange, each with
// the reason. Every other fixture must drive at least one, so a scenario of an
// endpoint the client speaks cannot pass here by being skipped whole.
var gatewayOnly = map[string]string{}

// clientCall maps an exchange to the client call that sends it, or returns false
// when this client cannot send that request.
func clientCall(t *testing.T, method, path, token string, headers map[string]*string, body []byte) (call, bool) {
	c := call{version: fixtureVersion}
	for name, value := range headers {
		if !strings.EqualFold(name, "X-Aixle-Runner-Version") || value == nil {
			return call{}, false
		}
		c.version = *value
	}

	switch {
	case method == http.MethodPost && path == "/runner/v1/register":
		var req protocol.RegisterRequest
		if body == nil || !strictDecode(t, body, &req) {
			return call{}, false
		}
		c.endpoint = "register"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) { return cl.Register(ctx, token, req) }
	case method == http.MethodPost && path == "/runner/v1/token" && body == nil:
		c.endpoint = "token"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) { return cl.Refresh(ctx, token) }
	case method == http.MethodDelete && path == "/runner/v1/registration" && body == nil:
		c.endpoint = "unregister"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) { return nil, cl.Unregister(ctx, token) }
	case method == http.MethodGet && opsPath.MatchString(path) && body == nil:
		m := opsPath.FindStringSubmatch(path)
		after, err1 := strconv.ParseInt(m[1], 10, 64)
		wait, err2 := strconv.Atoi(m[2])
		if err1 != nil || err2 != nil || strconv.FormatInt(after, 10) != m[1] || strconv.Itoa(wait) != m[2] || wait > 25 {
			return call{}, false
		}
		c.endpoint = "ops"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) {
			poll, err := cl.PollOps(ctx, token, after, time.Duration(wait)*time.Second)
			if err != nil {
				return nil, err
			}
			return poll, nil
		}
	// The release endpoints take no token: the client sends none.
	case method == http.MethodGet && checksumsPath.MatchString(path) && body == nil && token == "":
		v := checksumsPath.FindStringSubmatch(path)[1]
		c.endpoint = "releases"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) { return cl.Checksums(ctx, v) }
	case method == http.MethodGet && releasePath.MatchString(path) && body == nil && token == "":
		m := releasePath.FindStringSubmatch(path)
		c.endpoint = "releases"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) { return cl.Release(ctx, m[1], m[2]) }
		c.check = func(t *testing.T, got any, headers map[string]*string) {
			loc := got.(protocol.ReleaseLocation)
			want := protocol.ReleaseLocation{}
			for name, value := range headers {
				switch {
				case value == nil:
				case strings.EqualFold(name, "Location"):
					want.Location = *value
				case strings.EqualFold(name, "X-Aixle-Runner-Sha256"):
					want.SHA256 = *value
				}
			}
			if loc != want {
				t.Errorf("the client read the redirect as %+v, the gateway sent %+v", loc, want)
			}
		}
	case method == http.MethodPost && resultPath.MatchString(path):
		id, err := strconv.ParseInt(resultPath.FindStringSubmatch(path)[1], 10, 64)
		var result protocol.Result
		if err != nil || body == nil || !strictDecode(t, body, &result) {
			return call{}, false
		}
		c.endpoint = "ops"
		c.run = func(ctx context.Context, cl *protocol.Client) (any, error) {
			return cl.PostResult(ctx, token, id, result)
		}
	default:
		return call{}, false
	}
	return c, true
}

// fakeGateway answers the one request it expects.
type fakeGateway struct {
	mu       sync.Mutex
	t        *testing.T
	expected *expectedExchange
	seen     int
}

type expectedExchange struct {
	method, path, token, version string
	body                         []byte
	status                       int
	headers                      map[string]*string
	response                     []byte
}

func (g *fakeGateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.seen++
	e := g.expected
	if e == nil {
		g.t.Errorf("unexpected request %s %s", r.Method, r.URL)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	g.expected = nil

	if r.Method != e.method || r.URL.RequestURI() != e.path {
		g.t.Errorf("request is %s %s, the fixture's is %s %s", r.Method, r.URL.RequestURI(), e.method, e.path)
	}
	if got := r.Header.Get("X-Aixle-Runner-Protocol"); got != "1" {
		g.t.Errorf("X-Aixle-Runner-Protocol is %q", got)
	}
	if got := r.Header.Get("X-Aixle-Runner-Version"); got != e.version {
		g.t.Errorf("X-Aixle-Runner-Version is %q, the fixture's is %q", got, e.version)
	}
	wantAuth := ""
	if e.token != "" {
		wantAuth = "Bearer " + e.token
	}
	if got := r.Header.Get("Authorization"); got != wantAuth {
		g.t.Errorf("Authorization is %q, the fixture's is %q", got, wantAuth)
	}
	got, _ := io.ReadAll(r.Body)
	if e.body == nil {
		if len(got) != 0 {
			g.t.Errorf("request has a body %s, the fixture's has none", got)
		}
	} else {
		if ct := r.Header.Get("Content-Type"); ct != "application/json" {
			g.t.Errorf("Content-Type is %q", ct)
		}
		if !reflect.DeepEqual(decode(g.t, got), decode(g.t, e.body)) {
			g.t.Errorf("request body is %s, the fixture's is %s", got, e.body)
		}
	}

	for name, value := range e.headers {
		if value != nil {
			w.Header().Set(name, *value)
		}
	}
	if e.response != nil {
		w.Header().Set("Content-Type", "application/json")
	}
	w.WriteHeader(e.status)
	_, _ = w.Write(e.response)
}

// defaultBody stands in for a success body the fixture does not check.
func (w *world) defaultBody(method, path string) any {
	pair := map[string]any{
		"access_token": randomToken("aracc_"), "access_token_expires_at": w.timestamp(time.Hour),
		"refresh_token": randomToken("arref_"), "refresh_token_expires_at": w.timestamp(30 * 24 * time.Hour),
	}
	switch {
	case method == http.MethodPost && path == "/runner/v1/register":
		pair["environment"] = map[string]any{"id": w.next(), "key": "aixle-r1-0000", "display_name": "build", "state": "registered"}
		return pair
	case method == http.MethodPost && path == "/runner/v1/token":
		return pair
	case method == http.MethodGet && strings.HasPrefix(path, "/runner/v1/ops"):
		return map[string]any{"ops": []any{}}
	case method == http.MethodPost && resultPath.MatchString(path):
		return map[string]any{"id": int64(1), "state": "completed"}
	}
	return nil
}

type coverage struct {
	mu      sync.Mutex
	driven  map[string]int
	skipped int
	// fixtures counts the driven exchanges of each fixture file.
	fixtures map[string]int
}

func TestConformanceFixtures(t *testing.T) {
	files, err := filepath.Glob(filepath.Join(fixturesDir, "*", "*.json"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no fixtures under %s: %v", fixturesDir, err)
	}
	sort.Strings(files)
	cov := &coverage{driven: map[string]int{}, fixtures: map[string]int{}}

	names := map[string]bool{}
	for _, file := range files {
		name := strings.TrimSuffix(strings.TrimPrefix(filepath.ToSlash(file), fixturesDir+"/"), ".json")
		names[name] = true
		t.Run(name, func(t *testing.T) {
			runFixture(t, file, cov)
			cov.mu.Lock()
			driven := cov.fixtures[file]
			cov.mu.Unlock()
			reason, listed := gatewayOnly[name]
			switch {
			case driven == 0 && !listed:
				t.Errorf("no exchange of %s was driven through the client: drive one, or add it to gatewayOnly with the reason", name)
			case driven > 0 && listed:
				t.Errorf("%s is in gatewayOnly (%s), and the client drives %d of its exchanges: take it off the list", name, reason, driven)
			}
		})
	}
	for name := range gatewayOnly {
		if !names[name] {
			t.Errorf("gatewayOnly names %s, which is no fixture", name)
		}
	}

	// The scenarios the client uses must really have been driven.
	for _, endpoint := range []string{"register", "token", "unregister", "ops", "releases"} {
		if cov.driven[endpoint] == 0 {
			t.Errorf("no %s exchange was driven through the client", endpoint)
		}
	}
	t.Logf("driven exchanges per endpoint: %v; skipped (not expressible by the client): %d", cov.driven, cov.skipped)
}

func runFixture(t *testing.T, file string, cov *coverage) {
	raw, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	var f fixtureFile
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&f); err != nil {
		t.Fatalf("invalid fixture: %v", err)
	}
	if f.Description == "" || len(f.Steps) == 0 {
		t.Fatal("a fixture needs a description and steps")
	}

	w := &world{t: t, vars: map[string]any{}, clock: time.Date(2026, 10, 31, 14, 0, 0, 0, time.UTC)}
	gateway := &fakeGateway{t: t}
	server := httptest.NewServer(gateway)
	defer server.Close()

	for i, rawStep := range f.Steps {
		var keys map[string]json.RawMessage
		if err := json.Unmarshal(rawStep, &keys); err != nil {
			t.Fatalf("step %d: %v", i, err)
		}
		if _, ok := keys["given"]; ok {
			setup(t, w, rawStep)
			continue
		}
		exchange(t, w, gateway, server.URL, file, i, rawStep, cov)
	}
}

func setup(t *testing.T, w *world, raw json.RawMessage) {
	var s struct {
		Given              string          `json:"given"`
		As                 string          `json:"as"`
		Name               string          `json:"name"`
		Machine            string          `json:"machine"`
		Session            string          `json:"session"`
		Op                 string          `json:"op"`
		Payload            json.RawMessage `json:"payload"`
		Seconds            int64           `json:"seconds"`
		MinVersion         *string         `json:"min_version"`
		RecommendedVersion *string         `json:"recommended_version"`
		Binaries           json.RawMessage `json:"binaries"`
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&s); err != nil {
		t.Fatalf("invalid setup step %s: %v", raw, err)
	}
	switch s.Given {
	case "registration_token":
		w.define(s.As, randomToken("arreg_"))
	case "registered_machine":
		w.define(s.As+".access_token", randomToken("aracc_"))
		w.define(s.As+".refresh_token", randomToken("arref_"))
		w.define(s.As+".environment_id", w.next())
	case "session_on_machine":
		w.lookup(s.Machine + ".access_token")
		w.define(s.As+".id", w.next())
	case "op_enqueued":
		w.lookup(s.Machine + ".access_token")
		if s.Session != "" {
			w.lookup(s.Session + ".id")
		}
		var payload map[string]any
		if json.Unmarshal(s.Payload, &payload) != nil || s.Op == "" {
			t.Fatalf("op_enqueued needs an op and an object payload: %s", raw)
		}
		w.define(s.As+".id", w.next())
		w.define(s.As+".sequence", w.next())
		w.define(s.As+".deadline_at", w.timestamp(5*time.Minute))
	case "time_passes":
		w.clock = w.clock.Add(time.Duration(s.Seconds) * time.Second)
	case "runner_revoked", "flag_off", "flag_on", "release_pins":
		// The gateway's state is in the fixture's expected answers, which the fake
		// replays.
	default:
		t.Fatalf("unknown setup step %q", s.Given)
	}
}

func exchange(t *testing.T, w *world, gateway *fakeGateway, baseURL, file string, index int, raw json.RawMessage, cov *coverage) {
	var x struct {
		Request  fixtureRequest    `json:"request"`
		Response fixtureResponse   `json:"response"`
		Capture  map[string]string `json:"capture"`
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(&x); err != nil {
		t.Fatalf("step %d: invalid exchange: %v", index, err)
	}

	path := w.substitute(x.Request.Path)
	token := ""
	if x.Request.Token != nil {
		token = w.substitute(*x.Request.Token)
	}
	headers := map[string]*string{}
	for k, v := range x.Request.Headers {
		if v != nil {
			s := w.substitute(*v)
			v = &s
		}
		headers[k] = v
	}
	var body []byte
	if len(x.Request.Body) > 0 {
		body = toJSON(t, w.requestValue(decode(t, x.Request.Body)))
	}

	// The answer the fake sends, and that the client must read back.
	var answer any
	hasAnswer := false
	switch {
	case len(x.Response.Body) > 0 && string(x.Response.Body) != "null":
		answer, hasAnswer = w.instantiate(decode(t, x.Response.Body)), true
	case len(x.Response.Body) == 0 && x.Response.Status < 300:
		answer = w.defaultBody(x.Request.Method, path)
	}
	var response []byte
	if answer != nil {
		response = toJSON(t, answer)
	}
	for name, ptr := range x.Capture {
		value, ok := pointer(answer, ptr)
		if !ok {
			t.Fatalf("step %d: capture %s points at nothing", index, ptr)
		}
		w.define(name, value)
	}

	c, ok := clientCall(t, x.Request.Method, path, token, headers, body)
	if !ok {
		cov.mu.Lock()
		cov.skipped++
		cov.mu.Unlock()
		return
	}
	cov.mu.Lock()
	cov.driven[c.endpoint]++
	cov.fixtures[file]++
	cov.mu.Unlock()

	gateway.mu.Lock()
	gateway.expected = &expectedExchange{
		method: x.Request.Method, path: path, token: token, version: c.version, body: body,
		status: x.Response.Status, headers: x.Response.Headers, response: response,
	}
	seenBefore := gateway.seen
	gateway.mu.Unlock()

	client, err := protocol.NewClient(baseURL, c.version, nil)
	if err != nil {
		t.Fatal(err)
	}
	got, err := c.run(context.Background(), client)

	gateway.mu.Lock()
	if gateway.seen != seenBefore+1 {
		t.Errorf("step %d: the client sent %d requests, not one", index, gateway.seen-seenBefore)
	}
	gateway.mu.Unlock()

	// A 302 is the release endpoint's success (PROTOCOL.md §5.6).
	if x.Response.Status < 400 {
		if err != nil {
			t.Fatalf("step %d: %s %s: the client failed on a %d: %v", index, x.Request.Method, path, x.Response.Status, err)
		}
		if hasAnswer && !sameJSON(t, got, answer) {
			t.Errorf("step %d: the client read %s, the gateway sent %s", index, toJSON(t, got), response)
		}
		if c.check != nil {
			c.check(t, got, x.Response.Headers)
		}
		return
	}

	refusal, ok := protocol.AsRefusal(err)
	if !ok {
		t.Fatalf("step %d: %s %s: a %d must be a *Refusal, got %v", index, x.Request.Method, path, x.Response.Status, err)
	}
	wantCode := ""
	if m, ok := answer.(map[string]any); ok {
		wantCode, _ = m["error"].(string)
	}
	if refusal.Status != x.Response.Status || refusal.Code != wantCode {
		t.Errorf("step %d: refusal read as %d %q, the gateway sent %d %q", index, refusal.Status, refusal.Code, x.Response.Status, wantCode)
	}
	if strings.Contains(refusal.Error(), token) && token != "" {
		t.Errorf("step %d: the refusal's message carries the token", index)
	}
}

// pointer resolves an RFC 6901 JSON Pointer.
func pointer(v any, ptr string) (any, bool) {
	if ptr == "" {
		return v, true
	}
	if !strings.HasPrefix(ptr, "/") {
		return nil, false
	}
	for _, part := range strings.Split(ptr[1:], "/") {
		part = strings.ReplaceAll(strings.ReplaceAll(part, "~1", "/"), "~0", "~")
		switch node := v.(type) {
		case map[string]any:
			next, ok := node[part]
			if !ok {
				return nil, false
			}
			v = next
		case []any:
			i, err := strconv.Atoi(part)
			if err != nil || i < 0 || i >= len(node) {
				return nil, false
			}
			v = node[i]
		default:
			return nil, false
		}
	}
	return v, true
}
