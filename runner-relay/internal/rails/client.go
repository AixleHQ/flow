// Package rails is the relay's client of the platform's two short internal calls
// (docs/design/agent-runtimes/runner-relay.md §8.2): `holders`, which says which
// machine holds the session a route token names, and `checks`, which the reconcile
// pass asks. Both answer in milliseconds and hold no connection.
package rails

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

// Endpoint names, the label of runner_relay_rails_request_seconds.
const (
	EndpointHolders = "holders"
	EndpointChecks  = "checks"
)

// ErrNotFound is the answer for a route token no runner session has.
var ErrNotFound = errors.New("rails: no runner session has this route token")

// ErrInvalid is the 422 of `checks`: the relay's own body did not match the schema. It
// is a bug in the relay, never a reason to revoke anything.
var ErrInvalid = errors.New("rails: the checks request was refused as invalid")

// maxBody bounds what is read of an answer.
const maxBody = 1 << 20

// Holder is the answer of `holders`. EnvironmentID is nil when no machine holds the
// session now.
type Holder struct {
	SessionID     int64          `json:"session_id"`
	EnvironmentID *int64         `json:"environment_id"`
	State         string         `json:"state"`
	Ports         map[string]int `json:"ports"`
}

// Machine is one entry of a `checks` request: the machine and the session the relay
// believes it holds.
type Machine struct {
	EnvironmentID int64  `json:"environment_id"`
	SessionID     *int64 `json:"session_id"`
}

// Client calls the platform. It carries the internal token, which it never logs.
type Client struct {
	BaseURL string
	Token   string
	HTTP    *http.Client
	// Observe, when set, is told of every call: its endpoint, the status ("200",
	// "error" for no answer) and how long it took.
	Observe func(endpoint, status string, d time.Duration)
}

// New returns a Client with a short timeout: the calls hold nothing.
func New(baseURL, token string) *Client {
	return &Client{BaseURL: baseURL, Token: token, HTTP: &http.Client{Timeout: 10 * time.Second}}
}

// Holders asks which machine holds the session of a route token.
func (c *Client) Holders(ctx context.Context, routeToken string) (Holder, error) {
	var h Holder
	status, body, err := c.do(ctx, EndpointHolders, http.MethodGet, "/api/v1/internal/runner_relay/holders/"+url.PathEscape(routeToken), nil)
	if err != nil {
		return h, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return h, ErrNotFound
	default:
		return h, fmt.Errorf("rails: holders answered %d", status)
	}
	if err := decodeStrict(body, &h); err != nil {
		return h, fmt.Errorf("rails: holders answer: %w", err)
	}
	if h.SessionID <= 0 {
		return h, errors.New("rails: holders answer has no session_id")
	}
	return h, nil
}

// Checks asks, for each machine, whether it is still valid and still holds its
// session. The answers are in the order of the request.
func (c *Client) Checks(ctx context.Context, machines []Machine) ([]bool, error) {
	payload, err := json.Marshal(struct {
		Machines []Machine `json:"machines"`
	}{machines})
	if err != nil {
		return nil, err
	}
	status, body, err := c.do(ctx, EndpointChecks, http.MethodPost, "/api/v1/internal/runner_relay/checks", payload)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusUnprocessableEntity:
		return nil, ErrInvalid
	default:
		return nil, fmt.Errorf("rails: checks answered %d", status)
	}
	var out struct {
		Machines []bool `json:"machines"`
	}
	if err := decodeStrict(body, &out); err != nil {
		return nil, fmt.Errorf("rails: checks answer: %w", err)
	}
	if len(out.Machines) != len(machines) {
		return nil, fmt.Errorf("rails: checks answered %d machines for %d", len(out.Machines), len(machines))
	}
	return out.Machines, nil
}

func (c *Client) do(ctx context.Context, endpoint, method, path string, payload []byte) (int, []byte, error) {
	start := time.Now()
	status := "error"
	defer func() {
		if c.Observe != nil {
			c.Observe(endpoint, status, time.Since(start))
		}
	}()
	var body io.Reader
	if payload != nil {
		body = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.Token)
	req.Header.Set("Accept", "application/json")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		// The library's error names the URL, which holds a route token: not logged whole.
		var uerr *url.Error
		if errors.As(err, &uerr) {
			return 0, nil, fmt.Errorf("rails: %s %s: %w", method, endpoint, uerr.Err)
		}
		return 0, nil, err
	}
	defer resp.Body.Close()
	status = strconv.Itoa(resp.StatusCode)
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxBody))
	if err != nil {
		return 0, nil, fmt.Errorf("rails: reading the %s answer: %w", endpoint, err)
	}
	return resp.StatusCode, data, nil
}

// decodeStrict decodes JSON into typed fields: a field of the wrong type is an error,
// not a coercion. Fields the struct does not name are ignored, so a newer platform is
// not refused by an older relay.
func decodeStrict(data []byte, out any) error {
	return json.Unmarshal(data, out)
}
