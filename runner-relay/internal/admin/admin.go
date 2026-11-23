// Package admin is the service's admin server (docs/design/agent-runtimes/runner-relay.md
// §2.2, §2.4): `/healthz`, `/readyz` and `/metrics`. It listens on its own
// port, which the ingress never routes. Nothing on it changes state: a drain comes from
// SIGTERM (cmd/aixle-runner-relay), not from this port.
package admin

import (
	"context"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Service is what the admin server asks of the relay.
type Service interface {
	// Ready says whether the service takes connections.
	Ready(ctx context.Context) error
}

// ReadyTimeout bounds one readiness probe.
const ReadyTimeout = 2 * time.Second

// Handler serves the admin routes.
//
//	GET  /healthz  200 while the process serves
//	GET  /readyz   200 when Redis answers and no drain is under way, else 503
//	GET  /metrics  Prometheus text
//
// Any other route or method is not served.
func Handler(svc Service, gatherer prometheus.Gatherer) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), ReadyTimeout)
		defer cancel()
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		if err := svc.Ready(ctx); err != nil {
			// The reason is not in the body: the probe's reader is not an operator.
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte("not ready\n"))
			return
		}
		w.Write([]byte("ready\n"))
	})
	mux.Handle("GET /metrics", promhttp.HandlerFor(gatherer, promhttp.HandlerOpts{}))
	return mux
}
