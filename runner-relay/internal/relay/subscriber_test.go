package relay

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"
)

const testChannel = "aixle_test:" + SignalChannel

func startSubscriber(t *testing.T, e *edgeHarness) (*redis.Client, context.CancelFunc) {
	t.Helper()
	rdb := redis.NewClient(&redis.Options{Addr: e.redis.Addr()})
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(func() { cancel(); rdb.Close() })
	go e.server.RunSignals(ctx, rdb, testChannel)
	eventually(t, "the subscription", func() bool { return e.server.subscribed.Load() })
	return rdb, cancel
}

func publish(t *testing.T, e *edgeHarness, msg map[string]any) {
	t.Helper()
	payload, _ := json.Marshal(msg)
	if n := e.redis.Publish(testChannel, string(payload)); n != 1 {
		t.Fatalf("%d subscribers got the message", n)
	}
}

func TestTheSubscriberAppliesTheThreeSignalsFromRedis(t *testing.T) {
	e := newEdgeHarness(t)
	e.machine(42, 123)
	startSubscriber(t, e)

	publish(t, e, map[string]any{"type": "machine_session", "environment_id": 42, "session_id": 124, "route_token": tokenB, "ports": bridgePorts})
	eventually(t, "the route", func() bool { r, ok := e.server.Registry().ByRouteToken(tokenB); return ok && r.SessionID == 124 })

	publish(t, e, map[string]any{"type": "session_ended", "session_id": 124})
	eventually(t, "the route to go", func() bool { _, ok := e.server.Registry().ByRouteToken(tokenB); return !ok })

	publish(t, e, map[string]any{"type": "machine_revoked", "environment_id": 42})
	select {
	case <-e.runner.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the machine was not closed")
	}
	if got := testutil.ToFloat64(e.metrics.SignalsReceived.WithLabelValues("machine_session", "applied")); got != 1 {
		t.Fatalf("applied machine_session signals = %v", got)
	}
	if testutil.CollectAndCount(e.metrics.SignalLag) == 0 {
		t.Fatal("no signal lag recorded")
	}
}

func TestTheSubscriberSurvivesAMessageOfTheWrongShape(t *testing.T) {
	e := newEdgeHarness(t)
	startSubscriber(t, e)

	e.redis.Publish(testChannel, "not json")
	publish(t, e, map[string]any{"type": "machine_session", "environment_id": 42, "session_id": 1, "route_token": tokenA, "ports": bridgePorts})

	eventually(t, "the route after the bad message", func() bool { _, ok := e.server.Registry().ByRouteToken(tokenA); return ok })
	if got := testutil.ToFloat64(e.metrics.SignalsReceived.WithLabelValues("unknown", "invalid")); got != 1 {
		t.Fatalf("refused signals = %v", got)
	}
}

func TestEverySubscriptionAsksForAReconcilePass(t *testing.T) {
	e := newEdgeHarness(t, func(o *Options) { o.CheckInterval = time.Hour })
	e.machine(42, 123)
	e.route(42, 123, tokenA)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go e.server.RunReconciler(ctx)
	startSubscriber(t, e)
	// The first subscription's pass (the loop's own first pass may come before or after it).
	eventually(t, "a pass", func() bool { return e.rails.calls() >= 1 })
	before := e.rails.calls()

	// The connection drops, as in a Redis restart: go-redis subscribes again by itself, and a
	// signal sent in between would be lost, so the relay asks the platform.
	e.redis.Close()
	if err := e.redis.Restart(); err != nil {
		t.Fatal(err)
	}

	eventually(t, "a pass after the resubscription", func() bool { return e.rails.calls() > before })
	eventually(t, "the subscription to be live again", func() bool { return e.server.subscribed.Load() })
}
