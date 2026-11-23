package admin

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
)

type fake struct {
	ready error
}

func (f *fake) Ready(context.Context) error { return f.ready }

func call(h http.Handler, method, path string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	return rec
}

func TestHealthzServesWhateverTheState(t *testing.T) {
	h := Handler(&fake{ready: errors.New("redis is down")}, prometheus.NewRegistry())
	if rec := call(h, "GET", "/healthz"); rec.Code != 200 {
		t.Fatalf("healthz = %d", rec.Code)
	}
}

func TestReadyzFollowsTheService(t *testing.T) {
	svc := &fake{}
	h := Handler(svc, prometheus.NewRegistry())
	if rec := call(h, "GET", "/readyz"); rec.Code != 200 {
		t.Fatalf("ready = %d", rec.Code)
	}
	svc.ready = errors.New("dial tcp 10.0.0.1:6379: connection refused")
	rec := call(h, "GET", "/readyz")
	if rec.Code != 503 {
		t.Fatalf("not ready = %d", rec.Code)
	}
	if strings.Contains(rec.Body.String(), "10.0.0.1") {
		t.Fatalf("the probe's body holds the reason: %q", rec.Body.String())
	}
}

func TestMetricsServesPrometheusText(t *testing.T) {
	reg := prometheus.NewRegistry()
	g := prometheus.NewGauge(prometheus.GaugeOpts{Name: "runner_relay_machines_connected", Help: "x"})
	reg.MustRegister(g)
	g.Set(3)
	rec := call(Handler(&fake{}, reg), "GET", "/metrics")
	if rec.Code != 200 || !strings.Contains(rec.Body.String(), "runner_relay_machines_connected 3") {
		t.Fatalf("%d %q", rec.Code, rec.Body.String())
	}
}

func TestAdminServesOnlyTheThreeGetRoutes(t *testing.T) {
	h := Handler(&fake{}, prometheus.NewRegistry())
	for _, path := range []string{"/healthz", "/readyz", "/metrics"} {
		if rec := call(h, "GET", path); rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", path, rec.Code)
		}
		if rec := call(h, "POST", path); rec.Code != http.StatusMethodNotAllowed {
			t.Fatalf("POST %s = %d, want 405", path, rec.Code)
		}
	}
	for _, method := range []string{"GET", "POST", "PUT", "DELETE"} {
		if rec := call(h, method, "/drain"); rec.Code != http.StatusNotFound {
			t.Fatalf("%s /drain = %d, want 404", method, rec.Code)
		}
	}
}
