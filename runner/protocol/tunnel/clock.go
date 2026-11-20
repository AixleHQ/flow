package tunnel

import (
	"sync"
	"time"
)

// Timer is a scheduled call.
type Timer interface {
	// Stop prevents the call; it returns false if the call already started.
	Stop() bool
}

// Clock is the time the package reads and waits on. Tests use a FakeClock, so the
// heartbeat, the open timeout and the drain run without real waiting.
type Clock interface {
	Now() time.Time
	// AfterFunc calls f after d: in its own goroutine on the real clock, and inside
	// Advance on a FakeClock. f must not wait for the clock.
	AfterFunc(d time.Duration, f func()) Timer
}

type realClock struct{}

// RealClock is the system clock.
var RealClock Clock = realClock{}

func (realClock) Now() time.Time                            { return time.Now() }
func (realClock) AfterFunc(d time.Duration, f func()) Timer { return time.AfterFunc(d, f) }

// FakeClock is a clock that moves only when Advance is called. Timers whose time
// has come are called in order, one at a time, inside Advance.
type FakeClock struct {
	mu     sync.Mutex
	now    time.Time
	timers []*fakeTimer
	seq    int
}

type fakeTimer struct {
	c    *FakeClock
	when time.Time
	seq  int
	f    func()
}

// NewFakeClock starts a fake clock at a fixed time.
func NewFakeClock() *FakeClock {
	return &FakeClock{now: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
}

func (c *FakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *FakeClock) AfterFunc(d time.Duration, f func()) Timer {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.seq++
	t := &fakeTimer{c: c, when: c.now.Add(d), seq: c.seq, f: f}
	c.timers = append(c.timers, t)
	return t
}

// Pending is the number of timers that have not fired or been stopped.
func (c *FakeClock) Pending() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.timers)
}

// Advance moves the clock by d, calling each timer that comes due at its own time,
// including the ones a call schedules inside the window.
func (c *FakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	target := c.now.Add(d)
	for {
		var next *fakeTimer
		for _, t := range c.timers {
			if t.when.After(target) {
				continue
			}
			if next == nil || t.when.Before(next.when) || (t.when.Equal(next.when) && t.seq < next.seq) {
				next = t
			}
		}
		if next == nil {
			break
		}
		c.remove(next)
		if next.when.After(c.now) {
			c.now = next.when
		}
		c.mu.Unlock()
		next.f()
		c.mu.Lock()
	}
	c.now = target
	c.mu.Unlock()
}

func (c *FakeClock) remove(t *fakeTimer) bool {
	for i, x := range c.timers {
		if x == t {
			c.timers = append(c.timers[:i], c.timers[i+1:]...)
			return true
		}
	}
	return false
}

func (t *fakeTimer) Stop() bool {
	t.c.mu.Lock()
	defer t.c.mu.Unlock()
	return t.c.remove(t)
}
