// Package backoff spaces out retries: the delay doubles from Base up to Max, and
// each delay is drawn at random from its upper half, so a fleet of machines that
// failed together does not retry together (runner/protocol/PROTOCOL.md §3).
package backoff

import (
	"context"
	"math/rand/v2"
	"time"
)

// Backoff counts consecutive failures. The zero value is not usable: use New.
type Backoff struct {
	Base time.Duration
	Max  time.Duration
	// Rand returns a number in [0, 1). Replaced in tests.
	Rand func() float64

	failures int
}

// New returns a backoff from base up to max.
func New(base, max time.Duration) *Backoff {
	return &Backoff{Base: base, Max: max, Rand: rand.Float64}
}

// Default is the runner's backoff: 1 s doubling up to 60 s, the length of the
// gateway's rate-limit window.
func Default() *Backoff {
	return New(time.Second, 60*time.Second)
}

// Next returns the delay before the next attempt and counts a failure.
func (b *Backoff) Next() time.Duration {
	ceiling := b.Max
	if b.failures < 32 {
		if d := b.Base << b.failures; d > 0 && d < b.Max {
			ceiling = d
		}
	}
	b.failures++
	half := ceiling / 2
	return half + time.Duration(b.Rand()*float64(ceiling-half))
}

// Reset forgets the failures after a success.
func (b *Backoff) Reset() { b.failures = 0 }

// Sleep waits d, or until ctx is done.
func Sleep(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}
