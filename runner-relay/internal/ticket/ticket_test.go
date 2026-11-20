package ticket

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
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
	if _, err := verifierAt(exp.Add(Tolerance)).Verify(token); err != nil {
		t.Fatalf("at exp+tolerance: %v", err)
	}
	if _, err := verifierAt(exp.Add(Tolerance + time.Second)).Verify(token); err != ErrInvalid {
		t.Fatalf("past the tolerance: %v", err)
	}
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
	text, sig, _ := strings.Cut(strings.TrimPrefix(good, Prefix), ".")

	cases := map[string]string{
		"wrong key":       Sign([]byte("another-key-of-32-characters-xxxx"), claims(now)),
		"wrong version":   Sign(key, wrongVersion),
		"no id":           Sign(key, noID),
		"bad environment": Sign(key, badEnv),
		"no prefix":       strings.TrimPrefix(good, Prefix),
		"empty":           "",
		"prefix only":     Prefix,
		"no mac":          Prefix + text,
		"empty mac":       Prefix + text + ".",
		"tampered claims": Prefix + text + "x." + sig,
		"tampered mac":    Prefix + text + "." + sig[:len(sig)-2] + "AA",
		"two dots":        good + ".x",
		"not base64":      Prefix + "!!!." + sig,
		"too long":        Prefix + strings.Repeat("a", MaxLength) + ".b",
	}
	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := verifierAt(now).Verify(token); err != ErrInvalid {
				t.Fatalf("got %v, want ErrInvalid", err)
			}
		})
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
