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

// Metrics are the service's Prometheus metrics. The ones of the browser path, the
// signals and the calls to Rails come with the tasks that build them.
type Metrics struct {
	Registry          *prometheus.Registry
	MachinesConnected prometheus.Gauge
	TunnelConnects    *prometheus.CounterVec
	Replaced          prometheus.Counter
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
	m.Registry.MustRegister(m.MachinesConnected, m.TunnelConnects, m.Replaced)
	// Every result exists from the start, so a rate() over one that has not happened is 0, not absent.
	for _, r := range []string{ResultOK, ResultBadTicket, ResultReplayed, ResultVersion, ResultUnavailable, ResultHandshake} {
		m.TunnelConnects.WithLabelValues(r)
	}
	return m
}
