// Package protocol is the runner's client of the gateway's wire contract,
// runner/protocol/PROTOCOL.md. It speaks the endpoints of protocol 1 and turns
// every refusal into a *Refusal. What a runner does about a refusal is decided by
// Classify, not here.
package protocol

import (
	"context"
	"encoding/json"
	"time"
)

// ProtocolVersion is sent in X-Aixle-Runner-Protocol (§1, §7).
const ProtocolVersion = "1"

// MaxWait is the longest long-poll the gateway holds (§5.4).
const MaxWait = 25 * time.Second

// MaxBodyBytes is the gateway's cap on a request body (§2). A larger body is
// answered `413` and never resent.
const MaxBodyBytes = 2 << 20

type deadlineKey struct{}

// WithOpDeadline carries an op's `deadline_at` to its handler. It is a value, not
// a context deadline: the context ending still means that the runner is stopping.
// A handler that must stop at the deadline (`container.start`) derives a context
// deadline from it for its own steps.
func WithOpDeadline(ctx context.Context, deadline time.Time) context.Context {
	return context.WithValue(ctx, deadlineKey{}, deadline)
}

// OpDeadline is the `deadline_at` of the op a handler runs, when the loop set it.
func OpDeadline(ctx context.Context) (time.Time, bool) {
	d, ok := ctx.Value(deadlineKey{}).(time.Time)
	return d, ok && !d.IsZero()
}

// Environment is the machine as register returns it (§5.1). The runner does not
// parse its id or key.
type Environment struct {
	ID          int64  `json:"id"`
	Key         string `json:"key"`
	DisplayName string `json:"display_name"`
	State       string `json:"state"`
}

// TokenPair is what register and token issue (§4, §5.1, §5.3).
type TokenPair struct {
	AccessToken           string    `json:"access_token"`
	AccessTokenExpiresAt  time.Time `json:"access_token_expires_at"`
	RefreshToken          string    `json:"refresh_token"`
	RefreshTokenExpiresAt time.Time `json:"refresh_token_expires_at"`
}

// RegisterRequest is the body of POST /runner/v1/register (§5.1). AutoUpdate is
// sent only as false, by `configure --no-auto-update`; absent means true.
type RegisterRequest struct {
	Name       string         `json:"name"`
	OS         string         `json:"os"`
	Arch       string         `json:"arch"`
	Facts      map[string]any `json:"facts"`
	Ephemeral  bool           `json:"ephemeral"`
	AutoUpdate *bool          `json:"auto_update,omitempty"`
}

// Registration is the 201 answer of register.
type Registration struct {
	Environment Environment `json:"environment"`
	TokenPair
}

// Op is one op of a GET ops answer (§6). SessionID is set on a session op and
// absent on an environment op.
type Op struct {
	ID         int64           `json:"id"`
	Sequence   int64           `json:"sequence"`
	Op         string          `json:"op"`
	SessionID  *int64          `json:"session_id,omitempty"`
	DeadlineAt time.Time       `json:"deadline_at"`
	Payload    json.RawMessage `json:"payload"`
}

// Poll is the answer of GET ops (§5.4). Update is set only on an answer without
// ops, when the platform recommends a newer runner for this idle machine.
type Poll struct {
	Ops    []Op    `json:"ops"`
	Update *Update `json:"update,omitempty"`
}

// Update is the `update` of an empty poll (§5.4): the version the platform
// recommends, and the binary's SHA-256 for this machine's os and arch, from the
// platform's pins. The runner asks its own platform URL for the release.
type Update struct {
	Version string `json:"version"`
	SHA256  string `json:"sha256"`
}

// Checksums is the answer of GET releases/:version/checksums (§5.7): the pinned
// SHA-256 of each binary of the version, by `<os>-<arch>`.
type Checksums struct {
	Version  string            `json:"version"`
	Binaries map[string]Digest `json:"binaries"`
}

// Digest is one binary's pinned digest.
type Digest struct {
	SHA256 string `json:"sha256"`
}

// ReleaseLocation is the `302` of GET releases/:version/:os-:arch (§5.6): where
// the binary is, and the digest it must have.
type ReleaseLocation struct {
	Location string
	SHA256   string
}

// Result statuses (§5.5).
const (
	StatusOK      = "ok"
	StatusError   = "error"
	StatusExpired = "expired"
)

// Result is the body of POST /runner/v1/ops/:id/result (§5.5). Absent fields are
// omitted rather than sent as null.
type Result struct {
	Status   string         `json:"status"`
	ExitCode *int           `json:"exit_code,omitempty"`
	Stdout   *string        `json:"stdout,omitempty"`
	Stderr   *string        `json:"stderr,omitempty"`
	Data     map[string]any `json:"data,omitempty"`
	Error    *ResultError   `json:"error,omitempty"`
}

// ResultError is a result's `error`: exactly a class and a message.
type ResultError struct {
	Class   string `json:"class"`
	Message string `json:"message"`
}

// ErrorResult builds an `error` result.
func ErrorResult(class, message string) Result {
	return Result{Status: StatusError, Error: &ResultError{Class: class, Message: message}}
}

// ResultState is the 200 answer of a result: the op's state after it.
type ResultState struct {
	ID    int64  `json:"id"`
	State string `json:"state"`
}
