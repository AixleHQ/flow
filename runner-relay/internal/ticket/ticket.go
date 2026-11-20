// Package ticket verifies tunnel tickets (docs/design/agent-runtimes/runner-relay.md
// §3.1; runner/protocol/PROTOCOL.md §5.11 and §8).
//
// The gateway mints a ticket for a machine that holds an access token
// (Runners::TunnelTicket in the Rails app), and the machine presents it once as
// `Authorization: Bearer artun_<claims>.<mac>` when it opens the tunnel. The claims
// are base64url (no padding) JSON, the mac is the base64url HMAC-SHA256 of the
// claims text, as it was written, under the key both sides hold:
//
//	{"v":1,"e":<environment id>,"r":<runner id>,"s":<session id or null>,"jti":"…","exp":<unix seconds>}
package ticket

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	// Prefix starts every ticket.
	Prefix = "artun_"
	// Version is the one claims version the service accepts.
	Version = 1
	// Tolerance is how far past `exp` a ticket still verifies, for clock skew
	// between the gateway and the relay.
	Tolerance = 5 * time.Second
	// MaxLength bounds what is parsed: a real ticket is a few hundred bytes.
	MaxLength = 2048
	// ReplayTTL is how long a ticket id is remembered: past its lifetime (60 s) and
	// the tolerance, so a used ticket is never accepted again.
	ReplayTTL = 90 * time.Second
	// ReplayKeyPrefix starts the Redis key of a used ticket id.
	ReplayKeyPrefix = "relay:jti:"
)

// ErrInvalid is returned for a ticket that is malformed, has a bad signature or
// version, or is expired. The caller answers `401 invalid_ticket` and learns
// nothing more about why, so a probe cannot tell the cases apart.
var ErrInvalid = errors.New("ticket: invalid")

// Claims are the ticket's signed claims.
type Claims struct {
	Version       int    `json:"v"`
	EnvironmentID int64  `json:"e"`
	RunnerID      int64  `json:"r"`
	SessionID     *int64 `json:"s"`
	ID            string `json:"jti"`
	ExpiresAt     int64  `json:"exp"`
}

// Verifier checks tickets against one key.
type Verifier struct {
	key []byte
	// Now is replaced in tests.
	Now func() time.Time
}

// NewVerifier returns a Verifier for key.
func NewVerifier(key []byte) *Verifier {
	return &Verifier{key: append([]byte(nil), key...), Now: time.Now}
}

// Sign makes a ticket for claims. The gateway is the signer in production; the
// service uses it in its tests, so the format is pinned against its own verifier.
func Sign(key []byte, claims Claims) string {
	body, err := json.Marshal(claims)
	if err != nil {
		panic("ticket: claims do not encode: " + err.Error())
	}
	text := base64.RawURLEncoding.EncodeToString(body)
	return Prefix + text + "." + base64.RawURLEncoding.EncodeToString(mac(key, text))
}

func mac(key []byte, text string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(text))
	return h.Sum(nil)
}

// Verify checks the signature, the claims' version and `exp` (with Tolerance). It
// does not record the id: single use is the Guard's.
func (v *Verifier) Verify(token string) (Claims, error) {
	if len(token) > MaxLength || !strings.HasPrefix(token, Prefix) {
		return Claims{}, ErrInvalid
	}
	text, sig, ok := strings.Cut(strings.TrimPrefix(token, Prefix), ".")
	if !ok || text == "" || strings.Contains(sig, ".") {
		return Claims{}, ErrInvalid
	}
	given, err := base64.RawURLEncoding.DecodeString(sig)
	if err != nil || !hmac.Equal(given, mac(v.key, text)) {
		return Claims{}, ErrInvalid
	}
	body, err := base64.RawURLEncoding.DecodeString(text)
	if err != nil {
		return Claims{}, ErrInvalid
	}
	var c Claims
	if err := json.Unmarshal(body, &c); err != nil {
		return Claims{}, ErrInvalid
	}
	if c.Version != Version || c.ID == "" || c.EnvironmentID <= 0 || c.RunnerID <= 0 || (c.SessionID != nil && *c.SessionID <= 0) {
		return Claims{}, ErrInvalid
	}
	if v.Now().After(time.Unix(c.ExpiresAt, 0).Add(Tolerance)) {
		return Claims{}, ErrInvalid
	}
	return c, nil
}

// Guard records that a ticket id was used.
type Guard interface {
	// Claim records id. It returns false when the id was recorded before.
	Claim(ctx context.Context, id string) (bool, error)
	// Ping says whether the guard's store answers, for /readyz.
	Ping(ctx context.Context) error
}

// RedisGuard keeps used ids in Redis: `SET relay:jti:<jti> 1 NX EX 90`.
type RedisGuard struct{ Client redis.Cmdable }

// Claim implements Guard.
func (g RedisGuard) Claim(ctx context.Context, id string) (bool, error) {
	ok, err := g.Client.SetNX(ctx, ReplayKeyPrefix+id, 1, ReplayTTL).Result()
	if err != nil {
		return false, fmt.Errorf("recording the ticket id: %w", err)
	}
	return ok, nil
}

// Ping implements Guard.
func (g RedisGuard) Ping(ctx context.Context) error { return g.Client.Ping(ctx).Err() }
