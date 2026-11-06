// Package protocol is the runner's client of the gateway's wire contract,
// runner/protocol/PROTOCOL.md. It speaks the five endpoints of protocol 1 and turns
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

// RegisterRequest is the body of POST /runner/v1/register (§5.1).
type RegisterRequest struct {
	Name      string         `json:"name"`
	OS        string         `json:"os"`
	Arch      string         `json:"arch"`
	Facts     map[string]any `json:"facts"`
	Ephemeral bool           `json:"ephemeral"`
}

// Registration is the 201 answer of register.
type Registration struct {
	Environment Environment `json:"environment"`
	TokenPair
}

// Op is one op of a GET ops answer (§6).
type Op struct {
	ID         int64           `json:"id"`
	Sequence   int64           `json:"sequence"`
	Op         string          `json:"op"`
	DeadlineAt time.Time       `json:"deadline_at"`
	Payload    json.RawMessage `json:"payload"`
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
