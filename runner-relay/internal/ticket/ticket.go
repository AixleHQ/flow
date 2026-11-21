// Package ticket verifies tunnel tickets (docs/design/agent-runtimes/runner-relay.md
// §3.1; runner/protocol/PROTOCOL.md §5.11 and §8).
//
// The gateway mints a ticket for a machine that holds an access token
// (Runners::TunnelTicket in the Rails app), and the machine presents it once as
// `Authorization: Bearer artun_<JWT>` when it opens the tunnel. The JWT is a standard
// compact one, HS256 under the key both sides hold, signed by the `jwt` gem on the
// gateway and verified here with github.com/golang-jwt/jwt/v5. The claims:
//
//	{"v":1,"e":<environment id>,"r":<runner id>,"s":<session id or null>,"jti":"…","exp":<unix seconds>}
package ticket

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
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

// ErrInvalid is returned for a ticket that is malformed, has a bad signature,
// algorithm or version, or is expired. The caller answers `401 invalid_ticket` and learns
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

// wireClaims is the JWT's payload: the ticket's claims, with `jti` and `exp` as the
// registered claims the library validates.
type wireClaims struct {
	Version       int    `json:"v"`
	EnvironmentID int64  `json:"e"`
	RunnerID      int64  `json:"r"`
	SessionID     *int64 `json:"s"`
	jwt.RegisteredClaims
}

// Sign makes a ticket for claims. The gateway is the signer in production; the
// service uses it in its tests, so the format is pinned against its own verifier.
func Sign(key []byte, claims Claims) string {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, wireClaims{
		Version: claims.Version, EnvironmentID: claims.EnvironmentID, RunnerID: claims.RunnerID, SessionID: claims.SessionID,
		RegisteredClaims: jwt.RegisteredClaims{ID: claims.ID, ExpiresAt: jwt.NewNumericDate(time.Unix(claims.ExpiresAt, 0))},
	})
	signed, err := token.SignedString(key)
	if err != nil {
		panic("ticket: claims do not sign: " + err.Error())
	}
	return Prefix + signed
}

// Verify checks the signature (HS256 only: `none` and every other algorithm are
// refused), `exp` (required, with Tolerance) and the claims' version. It does not
// record the id: single use is the Guard's.
func (v *Verifier) Verify(token string) (Claims, error) {
	if len(token) > MaxLength || !strings.HasPrefix(token, Prefix) {
		return Claims{}, ErrInvalid
	}
	var w wireClaims
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(Tolerance),
		jwt.WithTimeFunc(v.Now),
	)
	if _, err := parser.ParseWithClaims(strings.TrimPrefix(token, Prefix), &w, func(*jwt.Token) (any, error) { return v.key, nil }); err != nil {
		return Claims{}, ErrInvalid
	}
	c := Claims{
		Version: w.Version, EnvironmentID: w.EnvironmentID, RunnerID: w.RunnerID, SessionID: w.SessionID,
		ID: w.ID, ExpiresAt: w.ExpiresAt.Unix(),
	}
	if c.Version != Version || c.ID == "" || c.EnvironmentID <= 0 || c.RunnerID <= 0 || (c.SessionID != nil && *c.SessionID <= 0) {
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
