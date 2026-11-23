package relay

import "github.com/prometheus/client_golang/prometheus"

// The results of runner_relay_tunnel_connects_total (docs/design/agent-runtimes/runner-relay.md §2.4).
const (
	ResultOK          = "ok"
	ResultBadTicket   = "bad_ticket"
	ResultReplayed    = "replayed"
	ResultVersion     = "version"
	ResultUnavailable = "unavailable" // Redis is down, or the relay is draining
	ResultHandshake   = "handshake_failed"
)

// Metrics are the service's Prometheus metrics (§2.4). The frame and byte counters and
// the write queue are the multiplexer's, which exposes no hook for them yet.
type Metrics struct {
	Registry          *prometheus.Registry
	MachinesConnected prometheus.Gauge
	TunnelConnects    *prometheus.CounterVec
	Replaced          prometheus.Counter

	StreamsOpen *prometheus.GaugeVec
	// StreamResets counts the streams the relay ended with a RESET, or that the runner
	// refused to open, by the code's name.
	StreamResets *prometheus.CounterVec
	// DialSeconds is the time from a stream's OPEN to its OPEN_OK or refusal.
	DialSeconds prometheus.Histogram
	// SignalLag is the time from a signal's arrival from Redis to its being applied.
	SignalLag prometheus.Histogram
	// SignalsReceived counts the signals by type, and the ones that were refused.
	SignalsReceived *prometheus.CounterVec
	// ReconcileRevocations counts what a pass closed: a signal was lost.
	ReconcileRevocations prometheus.Counter
	ReconcilePasses      *prometheus.CounterVec
	RailsRequestSeconds  *prometheus.HistogramVec
	EdgeRequests         *prometheus.CounterVec
}

// NewMetrics registers the metrics in a registry of their own, so a test does not
// share state with another.
func NewMetrics() *Metrics {
	m := &Metrics{
		Registry: prometheus.NewRegistry(),
		MachinesConnected: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "runner_relay_machines_connected", Help: "Machines with an open tunnel connection.",
		}),
		TunnelConnects: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "runner_relay_tunnel_connects_total", Help: "Tunnel upgrade attempts, by result.",
		}, []string{"result"}),
		Replaced: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "runner_relay_tunnel_replaced_total", Help: "Connections closed because a newer one of the same machine came.",
		}),
	}
	dial := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name: "runner_relay_dial_seconds", Help: "Time from a stream's OPEN to its OPEN_OK or refusal.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	})
	lag := prometheus.NewHistogram(prometheus.HistogramOpts{
		Name: "runner_relay_signal_lag_seconds", Help: "Time from a signal's arrival from Redis to its being applied.",
		Buckets: []float64{.0005, .001, .005, .01, .05, .1, .5, 1},
	})
	m.DialSeconds, m.SignalLag = dial, lag
	m.StreamsOpen = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "runner_relay_streams_open", Help: "Open streams, by surface.",
	}, []string{"surface"})
	m.StreamResets = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_relay_stream_resets_total", Help: "Streams ended or refused with a RESET, by code.",
	}, []string{"code"})
	m.SignalsReceived = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_relay_signals_total", Help: "Signals from Redis, by type and whether they were applied.",
	}, []string{"type", "result"})
	m.ReconcileRevocations = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "runner_relay_reconcile_revocations_total", Help: "Machines or sessions a reconcile pass closed: a signal was lost.",
	})
	m.ReconcilePasses = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_relay_reconcile_passes_total", Help: "Reconcile passes, by result (ok, rails_error).",
	}, []string{"result"})
	m.RailsRequestSeconds = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "runner_relay_rails_request_seconds", Help: "The relay's short calls to the platform.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	}, []string{"endpoint", "status"})
	m.EdgeRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "runner_relay_edge_requests_total", Help: "Browser requests the edge handler refused or proxied, by result.",
	}, []string{"result"})
	m.Registry.MustRegister(m.MachinesConnected, m.TunnelConnects, m.Replaced, m.StreamsOpen, m.StreamResets,
		dial, lag, m.SignalsReceived, m.ReconcileRevocations, m.ReconcilePasses, m.RailsRequestSeconds, m.EdgeRequests)
	for _, sf := range Surfaces {
		m.StreamsOpen.WithLabelValues(sf)
	}
	for _, r := range []string{"ok", "rails_error"} {
		m.ReconcilePasses.WithLabelValues(r)
	}
	// Every result exists from the start, so a rate() over one that has not happened is 0, not absent.
	for _, r := range []string{ResultOK, ResultBadTicket, ResultReplayed, ResultVersion, ResultUnavailable, ResultHandshake} {
		m.TunnelConnects.WithLabelValues(r)
	}
	return m
}
