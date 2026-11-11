package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	collectorlogs "go.opentelemetry.io/proto/otlp/collector/logs/v1"
	collectormetrics "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	collectortrace "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

type server struct {
	webBaseURL string
	client     *http.Client
}

func main() {
	port := envOrDefault("OTLP_INGEST_PORT", "4318")

	webBaseURL := envOrDefault("OTLP_INGEST_WEB_BASE_URL", "http://web:4000")

	if _, err := url.ParseRequestURI(webBaseURL); err != nil {
		log.Fatalf("invalid OTLP_INGEST_WEB_BASE_URL: %v", err)
	}

	srv := &server{
		webBaseURL: strings.TrimRight(webBaseURL, "/"),
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
	mux := http.NewServeMux()
	signals := map[string]func() proto.Message{
		"metrics": func() proto.Message { return &collectormetrics.ExportMetricsServiceRequest{} },
		"logs":    func() proto.Message { return &collectorlogs.ExportLogsServiceRequest{} },
		"traces":  func() proto.Message { return &collectortrace.ExportTraceServiceRequest{} },
	}
	for signal, newRequest := range signals {
		handler := srv.exportHandler(signal, newRequest)
		mux.HandleFunc("/v1/"+signal, handler)
		mux.HandleFunc("/v1/"+signal+"/", handler)
	}
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("otlp-ingest listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// exportHandler accepts one OTLP/HTTP signal, in JSON or protobuf, and forwards it to
// the web app as JSON. Every signal goes to the same endpoint: the app tells them apart
// by their top-level key (resourceMetrics, resourceLogs, resourceSpans).
func (s *server) exportHandler(signal string, newRequest func() proto.Message) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		body, err := io.ReadAll(io.LimitReader(r.Body, 10<<20))
		if err != nil {
			http.Error(w, "failed to read request body", http.StatusBadRequest)
			return
		}
		if len(body) == 0 {
			http.Error(w, "empty request body", http.StatusBadRequest)
			return
		}

		req := newRequest()
		if strings.Contains(r.Header.Get("Content-Type"), "application/json") {
			if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(body, req); err != nil {
				log.Printf("%s json parse error: %v", signal, err)
				http.Error(w, "invalid json payload", http.StatusBadRequest)
				return
			}
		} else {
			if err := proto.Unmarshal(body, req); err != nil {
				log.Printf("%s protobuf parse error: %v", signal, err)
				http.Error(w, "invalid protobuf payload", http.StatusBadRequest)
				return
			}
		}

		jsonBody, err := protojson.Marshal(req)
		if err != nil {
			log.Printf("%s json marshal error: %v", signal, err)
			http.Error(w, "failed to marshal payload", http.StatusInternalServerError)
			return
		}

		if err := s.postUsage(r.Context(), jsonBody); err != nil {
			log.Printf("forward error: %v", err)
			http.Error(w, "failed to forward "+signal, http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
	}
}

func (s *server) postUsage(ctx context.Context, body []byte) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	endpoint := s.webBaseURL + "/api/v1/internal/usage_statistics"
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}

	request.Header.Set("Content-Type", "application/json")

	response, err := s.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return fmt.Errorf("web api error: status=%d body=%s", response.StatusCode, strings.TrimSpace(string(snippet)))
	}

	return nil
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}
