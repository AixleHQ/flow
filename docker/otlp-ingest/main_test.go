package main

import (
	"net/http"
	"testing"

	collectorlogs "go.opentelemetry.io/proto/otlp/collector/logs/v1"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	logspb "go.opentelemetry.io/proto/otlp/logs/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
)

func attr(key, value string) *commonpb.KeyValue {
	return &commonpb.KeyValue{Key: key, Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: value}}}
}

func TestStampSessionFromHeaders(t *testing.T) {
	req := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logspb.ResourceLogs{
		{},
		{Resource: &resourcepb.Resource{Attributes: []*commonpb.KeyValue{attr("terminal_session_token", "own")}}},
	}}
	header := http.Header{}
	header.Set("X-Aixle-Session-Token", "tok")
	header.Set("X-Aixle-Session-Key", "key")

	stampSession(req, header)

	got := req.ResourceLogs[0].Resource.Attributes
	if len(got) != 2 || got[0].Key != "terminal_session_token" || got[0].Value.GetStringValue() != "tok" ||
		got[1].Key != "terminal_session_key" || got[1].Value.GetStringValue() != "key" {
		t.Fatalf("unstamped resource: got %v", got)
	}
	if own := req.ResourceLogs[1].Resource.Attributes; len(own) != 1 || own[0].Value.GetStringValue() != "own" {
		t.Fatalf("a resource naming its own session must keep it: got %v", own)
	}
}

func TestStampSessionWithoutHeadersLeavesTheBatch(t *testing.T) {
	req := &collectorlogs.ExportLogsServiceRequest{ResourceLogs: []*logspb.ResourceLogs{{}}}

	stampSession(req, http.Header{})

	if req.ResourceLogs[0].Resource != nil {
		t.Fatalf("expected no resource to be created, got %v", req.ResourceLogs[0].Resource)
	}
}
