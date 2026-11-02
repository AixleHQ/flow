package backoff

import (
	"context"
	"testing"
	"time"
)

func TestDelaysDoubleUpToTheMaxWithJitterInTheUpperHalf(t *testing.T) {
	b := New(time.Second, 60*time.Second)
	ceilings := []time.Duration{1, 2, 4, 8, 16, 32, 60, 60, 60}
	for _, r := range []float64{0, 0.999999} {
		b.Reset()
		b.Rand = func() float64 { return r }
		for i, c := range ceilings {
			ceiling := c * time.Second
			d := b.Next()
			if d < ceiling/2 || d > ceiling {
				t.Fatalf("attempt %d (rand %v): %v outside [%v, %v]", i, r, d, ceiling/2, ceiling)
			}
		}
	}
}

func TestJitterSpreadsTheDelays(t *testing.T) {
	seen := map[time.Duration]bool{}
	for i := 0; i < 50; i++ {
		b := Default()
		for j := 0; j < 4; j++ {
			b.Next()
		}
		seen[b.Next()] = true
	}
	if len(seen) < 10 {
		t.Fatalf("50 machines drew only %d distinct delays", len(seen))
	}
}

func TestResetStartsOver(t *testing.T) {
	b := New(time.Second, time.Minute)
	b.Rand = func() float64 { return 0.999999 }
	for i := 0; i < 10; i++ {
		b.Next()
	}
	b.Reset()
	if d := b.Next(); d > time.Second {
		t.Fatalf("after a reset the delay is %v", d)
	}
}

func TestManyFailuresDoNotOverflow(t *testing.T) {
	b := Default()
	for i := 0; i < 200; i++ {
		if d := b.Next(); d <= 0 || d > time.Minute {
			t.Fatalf("attempt %d: %v", i, d)
		}
	}
}

func TestSleepStopsWithTheContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := Sleep(ctx, time.Hour); err == nil {
		t.Fatal("Sleep ignored the cancelled context")
	}
}
