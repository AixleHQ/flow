package ticket

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
)

var key = []byte("a-ticket-key-of-32-characters-xx")

func session(n int64) *int64 { return &n }

func claims(now time.Time) Claims {
	return Claims{Version: Version, EnvironmentID: 42, RunnerID: 7, SessionID: session(123), ID: "jti-1", ExpiresAt: now.Add(60 * time.Second).Unix()}
}

func verifierAt(now time.Time) *Verifier {
	v := NewVerifier(key)
	v.Now = func() time.Time { return now }
	return v
}

func TestVerifyValid(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	got, err := verifierAt(now).Verify(Sign(key, claims(now)))
	if err != nil {
		t.Fatal(err)
	}
	if got.EnvironmentID != 42 || got.RunnerID != 7 || got.SessionID == nil || *got.SessionID != 123 || got.ID != "jti-1" {
		t.Fatalf("claims: %+v", got)
	}
}

func TestVerifyIdleMachineHasNoSession(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	c := claims(now)
	c.SessionID = nil
	got, err := verifierAt(now).Verify(Sign(key, c))
	if err != nil || got.SessionID != nil {
		t.Fatalf("got %+v, %v", got, err)
	}
}

func TestVerifyExpiryWithTolerance(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	token := Sign(key, claims(now))
	exp := time.Unix(claims(now).ExpiresAt, 0)
	if _, err := verifierAt(exp.Add(Tolerance - time.Second)).Verify(token); err != nil {
		t.Fatalf("within the tolerance: %v", err)
	}
	if _, err := verifierAt(exp.Add(Tolerance + time.Second)).Verify(token); err != ErrInvalid {
		t.Fatalf("past the tolerance: %v", err)
	}
}

// signWith signs a JWT with any method and claims, the way a forger would.
func signWith(t *testing.T, method jwt.SigningMethod, signingKey any, c jwt.MapClaims) string {
	t.Helper()
	signed, err := jwt.NewWithClaims(method, c).SignedString(signingKey)
	if err != nil {
		t.Fatal(err)
	}
	return Prefix + signed
}

func validMap(now time.Time) jwt.MapClaims {
	return jwt.MapClaims{"v": 1, "e": 42, "r": 7, "s": 123, "jti": "jti-1", "exp": now.Add(60 * time.Second).Unix()}
}

func TestVerifyRefusals(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	good := Sign(key, claims(now))
	wrongVersion := claims(now)
	wrongVersion.Version = 2
	noID := claims(now)
	noID.ID = ""
	badEnv := claims(now)
	badEnv.EnvironmentID = 0
	noExp := validMap(now)
	delete(noExp, "exp")

	rsaKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(strings.TrimPrefix(good, Prefix), ".")
	none := signWith(t, jwt.SigningMethodNone, jwt.UnsafeAllowNoneSignatureType, validMap(now))

	cases := map[string]string{
		"wrong key":           Sign([]byte("another-key-of-32-characters-xxxx"), claims(now)),
		"wrong version":       Sign(key, wrongVersion),
		"no id":               Sign(key, noID),
		"bad environment":     Sign(key, badEnv),
		"no exp":              signWith(t, jwt.SigningMethodHS256, key, noExp),
		"alg none":            none,
		"alg none, no sig":    strings.TrimSuffix(none, "."),
		"HS512 under the key": signWith(t, jwt.SigningMethodHS512, key, validMap(now)),
		"HS384 under the key": signWith(t, jwt.SigningMethodHS384, key, validMap(now)),
		"RS256":               signWith(t, jwt.SigningMethodRS256, rsaKey, validMap(now)),
		"no prefix":           strings.TrimPrefix(good, Prefix),
		"empty":               "",
		"prefix only":         Prefix,
		"no signature":        Prefix + parts[0] + "." + parts[1],
		"empty signature":     Prefix + parts[0] + "." + parts[1] + ".",
		"tampered claims":     Prefix + parts[0] + "." + parts[1] + "x." + parts[2],
		"tampered signature":  Prefix + parts[0] + "." + parts[1] + "." + parts[2][:len(parts[2])-2] + "AA",
		"four parts":          good + ".x",
		"not base64":          Prefix + parts[0] + ".!!!." + parts[2],
		"too long":            Prefix + strings.Repeat("a", MaxLength) + ".b.c",
	}
	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := verifierAt(now).Verify(token); err != ErrInvalid {
				t.Fatalf("got %v, want ErrInvalid", err)
			}
		})
	}
}

// The shared vector is a ticket minted the way the gateway mints one (the Ruby `jwt`
// gem; test/services/runners/tunnel_ticket_test.rb decodes the same file), so the
// Go verifier is tested against the other end's output.
func TestVerifySharedVector(t *testing.T) {
	raw, err := os.ReadFile("testdata/ticket.txt")
	if err != nil {
		t.Fatal(err)
	}
	got, err := verifierAt(time.Unix(1_800_000_000, 0)).Verify(strings.TrimSpace(string(raw)))
	if err != nil {
		t.Fatal(err)
	}
	if got.Version != 1 || got.EnvironmentID != 42 || got.RunnerID != 7 || got.SessionID == nil || *got.SessionID != 123 ||
		got.ID != "shared-vector-jti" || got.ExpiresAt != 1_800_000_060 {
		t.Fatalf("claims: %+v", got)
	}
}

func TestRedisGuardSingleUse(t *testing.T) {
	mr := miniredis.RunT(t)
	guard := RedisGuard{Client: redis.NewClient(&redis.Options{Addr: mr.Addr()})}
	ctx := context.Background()

	if err := guard.Ping(ctx); err != nil {
		t.Fatal(err)
	}
	if fresh, err := guard.Claim(ctx, "abc"); err != nil || !fresh {
		t.Fatalf("first use: %v %v", fresh, err)
	}
	if fresh, err := guard.Claim(ctx, "abc"); err != nil || fresh {
		t.Fatalf("second use: %v %v", fresh, err)
	}
	if fresh, err := guard.Claim(ctx, "other"); err != nil || !fresh {
		t.Fatalf("another id: %v %v", fresh, err)
	}
	if ttl := mr.TTL("relay:jti:abc"); ttl != 90*time.Second {
		t.Fatalf("ttl = %v, want 90s", ttl)
	}
	mr.FastForward(91 * time.Second)
	if mr.Exists("relay:jti:abc") {
		t.Fatal("the id outlived its TTL")
	}
}

func TestRedisGuardDown(t *testing.T) {
	mr := miniredis.RunT(t)
	guard := RedisGuard{Client: redis.NewClient(&redis.Options{Addr: mr.Addr(), MaxRetries: -1})}
	mr.Close()
	if _, err := guard.Claim(context.Background(), "abc"); err == nil {
		t.Fatal("Claim succeeded with Redis down")
	}
	if err := guard.Ping(context.Background()); err == nil {
		t.Fatal("Ping succeeded with Redis down")
	}
}
