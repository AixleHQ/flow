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
	collector "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

type server struct {
	webBaseURL string
	proxyURL   string
	client     *http.Client
}

func main() {
	port := envOrDefault("OTLP_INGEST_PORT", "4318")

	webBaseURL := envOrDefault("OTLP_INGEST_WEB_BASE_URL", "http://web:4000")

	if _, err := url.ParseRequestURI(webBaseURL); err != nil {
		log.Fatalf("invalid OTLP_INGEST_WEB_BASE_URL: %v", err)
	}

	proxyURL := strings.TrimSpace(os.Getenv("OTLP_INGEST_PROXY_URL"))
	if proxyURL != "" {
		if _, err := url.ParseRequestURI(proxyURL); err != nil {
			log.Fatalf("invalid OTLP_INGEST_PROXY_URL: %v", err)
		}
		proxyURL = strings.TrimRight(proxyURL, "/")
	}

	srv := &server{
		webBaseURL: strings.TrimRight(webBaseURL, "/"),
		proxyURL:   proxyURL,
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/metrics", srv.handleMetrics)
	mux.HandleFunc("/v1/metrics/", srv.handleMetrics)
	mux.HandleFunc("/v1/logs", srv.handleLogs)
	mux.HandleFunc("/v1/logs/", srv.handleLogs)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("otlp-ingest listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func (s *server) handleMetrics(w http.ResponseWriter, r *http.Request) {
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

	var req collector.ExportMetricsServiceRequest
	contentType := r.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(body, &req); err != nil {
			log.Printf("metrics json parse error: %v", err)
			http.Error(w, "invalid json payload", http.StatusBadRequest)
			return
		}
	} else {
		if err := proto.Unmarshal(body, &req); err != nil {
			log.Printf("metrics protobuf parse error: %v", err)
			http.Error(w, "invalid protobuf payload", http.StatusBadRequest)
			return
		}
	}

	jsonBody, err := protojson.Marshal(&req)
	if err != nil {
		log.Printf("metrics json marshal error: %v", err)
		http.Error(w, "failed to marshal payload", http.StatusInternalServerError)
		return
	}

	if err := s.postUsage(r.Context(), jsonBody); err != nil {
		log.Printf("forward error: %v", err)
		http.Error(w, "failed to forward metrics", http.StatusInternalServerError)
		return
	}

	if s.proxyURL != "" {
		if err := s.postJSON(r.Context(), s.proxyURL, jsonBody); err != nil {
			log.Printf("proxy error (metrics): %v", err)
		}
	}

	w.WriteHeader(http.StatusOK)
}

func (s *server) handleLogs(w http.ResponseWriter, r *http.Request) {
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

	var req collectorlogs.ExportLogsServiceRequest
	contentType := r.Header.Get("Content-Type")
	if strings.Contains(contentType, "application/json") {
		if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(body, &req); err != nil {
			log.Printf("logs json parse error: %v", err)
			http.Error(w, "invalid json payload", http.StatusBadRequest)
			return
		}
	} else {
		if err := proto.Unmarshal(body, &req); err != nil {
			log.Printf("logs protobuf parse error: %v", err)
			http.Error(w, "invalid protobuf payload", http.StatusBadRequest)
			return
		}
	}

	jsonBody, err := protojson.Marshal(&req)
	if err != nil {
		log.Printf("logs json marshal error: %v", err)
		http.Error(w, "failed to marshal payload", http.StatusInternalServerError)
		return
	}

	if err := s.postUsage(r.Context(), jsonBody); err != nil {
		log.Printf("forward error: %v", err)
		http.Error(w, "failed to forward logs", http.StatusInternalServerError)
		return
	}

	if s.proxyURL != "" {
		if err := s.postJSON(r.Context(), s.proxyURL, jsonBody); err != nil {
			log.Printf("proxy error (logs): %v", err)
		}
	}

	w.WriteHeader(http.StatusOK)
}

func (s *server) postUsage(ctx context.Context, body []byte) error {
	return s.postJSON(ctx, s.webBaseURL+"/api/v1/internal/usage_statistics", body)
}

func (s *server) postJSON(ctx context.Context, endpoint string, body []byte) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

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
		return fmt.Errorf("upstream error: status=%d body=%s", response.StatusCode, strings.TrimSpace(string(snippet)))
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
