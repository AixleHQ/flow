package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	collectorlogs "go.opentelemetry.io/proto/otlp/collector/logs/v1"
	collectormetrics "go.opentelemetry.io/proto/otlp/collector/metrics/v1"
	common "go.opentelemetry.io/proto/otlp/common/v1"
	logs "go.opentelemetry.io/proto/otlp/logs/v1"
	metrics "go.opentelemetry.io/proto/otlp/metrics/v1"
	resource "go.opentelemetry.io/proto/otlp/resource/v1"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

type capturedRequest struct {
	path          string
	contentType   string
	authorization string
	internalToken string
	body          []byte
}

type requestCapture struct {
	mu       sync.Mutex
	requests []capturedRequest
	status   int
}

func (capture *requestCapture) handler(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	capture.mu.Lock()
	capture.requests = append(capture.requests, capturedRequest{
		path:          r.URL.RequestURI(),
		contentType:   r.Header.Get("Content-Type"),
		authorization: r.Header.Get("Authorization"),
		internalToken: r.Header.Get("X-Internal-Token"),
		body:          body,
	})
	capture.mu.Unlock()

	status := capture.status
	if status == 0 {
		status = http.StatusOK
	}
	w.WriteHeader(status)
}

func (capture *requestCapture) snapshot() []capturedRequest {
	capture.mu.Lock()
	defer capture.mu.Unlock()
	return append([]capturedRequest(nil), capture.requests...)
}

func TestHandleLogsFiltersMixedBatchAndPreservesMetadata(t *testing.T) {
	for _, input := range []struct {
		name        string
		contentType string
		marshal     func(proto.Message) ([]byte, error)
	}{
		{name: "json", contentType: "application/json", marshal: protojson.Marshal},
		{name: "protobuf", contentType: "application/x-protobuf", marshal: proto.Marshal},
	} {
		t.Run(input.name, func(t *testing.T) {
			enabledBool := testResourceLogs("enabled-bool", boolValue(true))
			disabled := testResourceLogs("disabled", boolValue(false))
			unset := testResourceLogs("unset", nil)
			enabledString := testResourceLogs("enabled-string", stringValue("true"))
			original := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logs.ResourceLogs{
				enabledBool, disabled, unset, enabledString,
			}}

			railsCapture := &requestCapture{}
			rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
			defer rails.Close()
			proxyCapture := &requestCapture{}
			proxy := httptest.NewServer(http.HandlerFunc(proxyCapture.handler))
			defer proxy.Close()

			proxyURL, err := logsEndpoint(proxy.URL + "/collector")
			if err != nil {
				t.Fatalf("logsEndpoint() error = %v", err)
			}
			srv := &server{webBaseURL: rails.URL, proxyLogsURL: proxyURL, client: http.DefaultClient}
			body, err := input.marshal(original)
			if err != nil {
				t.Fatalf("marshal input: %v", err)
			}
			request := httptest.NewRequest(http.MethodPost, "/v1/logs", bytesReader(body))
			request.Header.Set("Content-Type", input.contentType)
			request.Header.Set("Authorization", "Bearer must-not-leak")
			request.Header.Set("X-Internal-Token", "must-not-leak")
			response := httptest.NewRecorder()

			srv.handleLogs(response, request)

			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
			}
			railsRequests := railsCapture.snapshot()
			if len(railsRequests) != 1 {
				t.Fatalf("Rails requests = %d, want 1", len(railsRequests))
			}
			assertForwardedHeaders(t, railsRequests[0])
			if railsRequests[0].path != "/api/v1/internal/usage_statistics" {
				t.Errorf("Rails path = %q", railsRequests[0].path)
			}
			assertLogsRequestEqual(t, railsRequests[0].body, original)

			proxyRequests := proxyCapture.snapshot()
			if len(proxyRequests) != 1 {
				t.Fatalf("Proxy requests = %d, want 1", len(proxyRequests))
			}
			assertForwardedHeaders(t, proxyRequests[0])
			if proxyRequests[0].path != "/collector/v1/logs" {
				t.Errorf("Proxy path = %q, want /collector/v1/logs", proxyRequests[0].path)
			}
			expected := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logs.ResourceLogs{enabledBool, enabledString}}
			assertLogsRequestEqual(t, proxyRequests[0].body, expected)
		})
	}
}

func TestHandleLogsProxyMarker(t *testing.T) {
	for _, test := range []struct {
		name      string
		marker    *common.AnyValue
		proxyCall bool
	}{
		{name: "bool true", marker: boolValue(true), proxyCall: true},
		{name: "string true", marker: stringValue("true"), proxyCall: true},
		{name: "bool false", marker: boolValue(false), proxyCall: false},
		{name: "string false", marker: stringValue("false"), proxyCall: false},
		{name: "unset", marker: nil, proxyCall: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			payload := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logs.ResourceLogs{
				testResourceLogs(test.name, test.marker),
			}}
			railsCapture := &requestCapture{}
			rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
			defer rails.Close()
			proxyCapture := &requestCapture{}
			proxy := httptest.NewServer(http.HandlerFunc(proxyCapture.handler))
			defer proxy.Close()
			srv := &server{webBaseURL: rails.URL, proxyLogsURL: proxy.URL + "/v1/logs", client: http.DefaultClient}
			body, err := protojson.Marshal(payload)
			if err != nil {
				t.Fatalf("marshal input: %v", err)
			}
			request := httptest.NewRequest(http.MethodPost, "/v1/logs", bytesReader(body))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()

			srv.handleLogs(response, request)

			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
			}
			if got := len(railsCapture.snapshot()); got != 1 {
				t.Errorf("Rails requests = %d, want 1", got)
			}
			wantProxy := 0
			if test.proxyCall {
				wantProxy = 1
			}
			if got := len(proxyCapture.snapshot()); got != wantProxy {
				t.Errorf("Proxy requests = %d, want %d", got, wantProxy)
			}
		})
	}
}

func TestHandleLogsSkipsEmptyProxyURL(t *testing.T) {
	payload := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logs.ResourceLogs{
		testResourceLogs("enabled", boolValue(true)),
	}}
	railsCapture := &requestCapture{}
	rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
	defer rails.Close()
	srv := &server{webBaseURL: rails.URL, client: http.DefaultClient}
	body, err := protojson.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal input: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/logs", bytesReader(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	srv.handleLogs(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
	}
	if got := len(railsCapture.snapshot()); got != 1 {
		t.Errorf("Rails requests = %d, want 1", got)
	}
}

func TestHandleLogsProxyFailureDoesNotFailRailsPath(t *testing.T) {
	payload := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logs.ResourceLogs{
		testResourceLogs("enabled", boolValue(true)),
	}}
	railsCapture := &requestCapture{}
	rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
	defer rails.Close()
	proxyCapture := &requestCapture{status: http.StatusServiceUnavailable}
	proxy := httptest.NewServer(http.HandlerFunc(proxyCapture.handler))
	defer proxy.Close()
	srv := &server{webBaseURL: rails.URL, proxyLogsURL: proxy.URL + "/v1/logs", client: http.DefaultClient}
	body, err := proto.Marshal(payload)
	if err != nil {
		t.Fatalf("marshal input: %v", err)
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/logs", bytesReader(body))
	request.Header.Set("Content-Type", "application/x-protobuf")
	response := httptest.NewRecorder()

	srv.handleLogs(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
	}
	if got := len(railsCapture.snapshot()); got != 1 {
		t.Errorf("Rails requests = %d, want 1", got)
	}
	if got := len(proxyCapture.snapshot()); got != 1 {
		t.Errorf("Proxy requests = %d, want 1", got)
	}
}

func TestHandleLogsRejectsInvalidPayload(t *testing.T) {
	for _, input := range []struct {
		name        string
		contentType string
		body        []byte
	}{
		{name: "json", contentType: "application/json", body: []byte("{")},
		{name: "protobuf", contentType: "application/x-protobuf", body: []byte{0xff}},
	} {
		t.Run(input.name, func(t *testing.T) {
			railsCapture := &requestCapture{}
			rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
			defer rails.Close()
			proxyCapture := &requestCapture{}
			proxy := httptest.NewServer(http.HandlerFunc(proxyCapture.handler))
			defer proxy.Close()
			srv := &server{webBaseURL: rails.URL, proxyLogsURL: proxy.URL + "/v1/logs", client: http.DefaultClient}
			request := httptest.NewRequest(http.MethodPost, "/v1/logs", bytesReader(input.body))
			request.Header.Set("Content-Type", input.contentType)
			response := httptest.NewRecorder()

			srv.handleLogs(response, request)

			if response.Code != http.StatusBadRequest {
				t.Fatalf("status = %d, want %d; body = %q", response.Code, http.StatusBadRequest, response.Body.String())
			}
			if got := len(railsCapture.snapshot()); got != 0 {
				t.Errorf("Rails requests = %d, want 0", got)
			}
			if got := len(proxyCapture.snapshot()); got != 0 {
				t.Errorf("Proxy requests = %d, want 0", got)
			}
		})
	}
}

func TestHandleMetricsNeverForwardsToProxy(t *testing.T) {
	for _, input := range []struct {
		name        string
		contentType string
		marshal     func(proto.Message) ([]byte, error)
	}{
		{name: "json", contentType: "application/json", marshal: protojson.Marshal},
		{name: "protobuf", contentType: "application/x-protobuf", marshal: proto.Marshal},
	} {
		t.Run(input.name, func(t *testing.T) {
			payload := &collectormetrics.ExportMetricsServiceRequest{ResourceMetrics: []*metrics.ResourceMetrics{{
				Resource: &resource.Resource{Attributes: []*common.KeyValue{{Key: "service.name", Value: stringValue("metrics-agent")}}},
			}}}
			railsCapture := &requestCapture{}
			rails := httptest.NewServer(http.HandlerFunc(railsCapture.handler))
			defer rails.Close()
			proxyCapture := &requestCapture{}
			proxy := httptest.NewServer(http.HandlerFunc(proxyCapture.handler))
			defer proxy.Close()
			srv := &server{webBaseURL: rails.URL, proxyLogsURL: proxy.URL + "/v1/logs", client: http.DefaultClient}
			body, err := input.marshal(payload)
			if err != nil {
				t.Fatalf("marshal input: %v", err)
			}
			request := httptest.NewRequest(http.MethodPost, "/v1/metrics", bytesReader(body))
			request.Header.Set("Content-Type", input.contentType)
			request.Header.Set("Authorization", "Bearer must-not-leak")
			response := httptest.NewRecorder()

			srv.handleMetrics(response, request)

			if response.Code != http.StatusOK {
				t.Fatalf("status = %d, body = %q", response.Code, response.Body.String())
			}
			railsRequests := railsCapture.snapshot()
			if len(railsRequests) != 1 {
				t.Fatalf("Rails requests = %d, want 1", len(railsRequests))
			}
			assertForwardedHeaders(t, railsRequests[0])
			var forwarded collectormetrics.ExportMetricsServiceRequest
			if err := protojson.Unmarshal(railsRequests[0].body, &forwarded); err != nil {
				t.Fatalf("decode Rails metrics: %v", err)
			}
			if !proto.Equal(&forwarded, payload) {
				t.Errorf("Rails metrics differ\ngot:  %v\nwant: %v", &forwarded, payload)
			}
			if got := len(proxyCapture.snapshot()); got != 0 {
				t.Errorf("Proxy requests = %d, want 0", got)
			}
		})
	}
}

func TestLogsEndpoint(t *testing.T) {
	for _, test := range []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{name: "empty disables", input: "  ", want: ""},
		{name: "base URL", input: "https://proxy.example", want: "https://proxy.example/v1/logs"},
		{name: "base URL trailing slash", input: "https://proxy.example/", want: "https://proxy.example/v1/logs"},
		{name: "base path", input: "https://proxy.example/otlp", want: "https://proxy.example/otlp/v1/logs"},
		{name: "complete endpoint", input: "https://proxy.example/v1/logs", want: "https://proxy.example/v1/logs"},
		{name: "complete endpoint trailing slash", input: "https://proxy.example/v1/logs/", want: "https://proxy.example/v1/logs"},
		{name: "query preserved", input: "https://proxy.example/otlp?tenant=one", want: "https://proxy.example/otlp/v1/logs?tenant=one"},
		{name: "similar suffix gets endpoint", input: "https://proxy.example/v1/logs-extra", want: "https://proxy.example/v1/logs-extra/v1/logs"},
		{name: "relative URL rejected", input: "/collector", wantErr: true},
		{name: "non-http URL rejected", input: "ftp://proxy.example", wantErr: true},
		{name: "malformed URL rejected", input: "://bad", wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			got, err := logsEndpoint(test.input)
			if test.wantErr {
				if err == nil {
					t.Fatalf("logsEndpoint(%q) error = nil", test.input)
				}
				return
			}
			if err != nil {
				t.Fatalf("logsEndpoint(%q) error = %v", test.input, err)
			}
			if got != test.want {
				t.Errorf("logsEndpoint(%q) = %q, want %q", test.input, got, test.want)
			}
		})
	}
}

func testResourceLogs(name string, marker *common.AnyValue) *logs.ResourceLogs {
	attributes := []*common.KeyValue{
		{Key: "service.name", Value: stringValue("agent-" + name)},
		{Key: "deployment.environment", Value: stringValue("test")},
	}
	if marker != nil {
		attributes = append(attributes, &common.KeyValue{Key: proxyMarkerKey, Value: marker})
	}
	return &logs.ResourceLogs{
		Resource:  &resource.Resource{Attributes: attributes, DroppedAttributesCount: 2},
		SchemaUrl: "https://opentelemetry.io/schemas/1.27.0",
		ScopeLogs: []*logs.ScopeLogs{{
			Scope: &common.InstrumentationScope{
				Name:                   "test-scope-" + name,
				Version:                "1.2.3",
				Attributes:             []*common.KeyValue{{Key: "scope.attribute", Value: stringValue("preserved")}},
				DroppedAttributesCount: 1,
			},
			SchemaUrl: "https://opentelemetry.io/schemas/1.26.0",
			LogRecords: []*logs.LogRecord{{
				TimeUnixNano:         1234,
				ObservedTimeUnixNano: 1250,
				SeverityText:         "INFO",
				Body:                 stringValue("log-" + name),
				Attributes: []*common.KeyValue{
					{Key: "standard.attribute", Value: stringValue("preserved")},
				},
				DroppedAttributesCount: 3,
				TraceId:                []byte("0123456789abcdef"),
				SpanId:                 []byte("01234567"),
			}},
		}},
	}
}

func boolValue(value bool) *common.AnyValue {
	return &common.AnyValue{Value: &common.AnyValue_BoolValue{BoolValue: value}}
}

func stringValue(value string) *common.AnyValue {
	return &common.AnyValue{Value: &common.AnyValue_StringValue{StringValue: value}}
}

func assertForwardedHeaders(t *testing.T, request capturedRequest) {
	t.Helper()
	if request.contentType != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", request.contentType)
	}
	if request.authorization != "" {
		t.Errorf("Authorization leaked: %q", request.authorization)
	}
	if request.internalToken != "" {
		t.Errorf("X-Internal-Token leaked: %q", request.internalToken)
	}
}

func assertLogsRequestEqual(t *testing.T, body []byte, want *collectorlogs.ExportLogsServiceRequest) {
	t.Helper()
	var got collectorlogs.ExportLogsServiceRequest
	if err := protojson.Unmarshal(body, &got); err != nil {
		t.Fatalf("decode forwarded logs: %v", err)
	}
	if !proto.Equal(&got, want) {
		t.Errorf("forwarded logs differ\ngot:  %v\nwant: %v", &got, want)
	}
}

func bytesReader(body []byte) io.Reader {
	return &byteReader{body: body}
}

type byteReader struct {
	body []byte
}

func (reader *byteReader) Read(destination []byte) (int, error) {
	if len(reader.body) == 0 {
		return 0, io.EOF
	}
	count := copy(destination, reader.body)
	reader.body = reader.body[count:]
	return count, nil
}
