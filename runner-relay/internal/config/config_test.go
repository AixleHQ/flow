package config

import (
	"strings"
	"testing"
	"time"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestFromEnvDefaults(t *testing.T) {
	c, err := FromEnv(env(map[string]string{
		"RUNNER_RELAY_REDIS_URL":      "redis://redis:6379/1",
		"RUNNER_RELAY_TICKET_KEY":     "0123456789abcdef0123",
		"RUNNER_RELAY_RAILS_URL":      "http://web:4000",
		"RUNNER_RELAY_INTERNAL_TOKEN": "tok",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Listen != ":8080" || c.AdminListen != ":9090" || c.MaxStreams != 64 || c.MaxFrame != 32768 ||
		c.StreamWindow != 262144 || c.CheckInterval != 60*time.Second {
		t.Fatalf("defaults: %+v", c)
	}
}

func TestFromEnvValues(t *testing.T) {
	c, err := FromEnv(env(map[string]string{
		"RUNNER_RELAY_LISTEN":               "127.0.0.1:1",
		"RUNNER_RELAY_ADMIN_LISTEN":         "127.0.0.1:2",
		"RUNNER_RELAY_REDIS_URL":            "rediss://:pw@redis:6380/2",
		"RUNNER_RELAY_RAILS_URL":            "http://web:4000/",
		"RUNNER_RELAY_TICKET_KEY":           " 0123456789abcdef0123 ",
		"RUNNER_RELAY_MAX_STREAMS":          "8",
		"RUNNER_RELAY_CHECK_INTERVAL":       "5s",
		"RUNNER_RELAY_INTERNAL_TOKEN":       "tok",
		"RUNNER_RELAY_STREAM_WINDOW":        "65536",
		"RUNNER_RELAY_MAX_FRAME":            "16384",
		"RUNNER_RELAY_REDIS_CHANNEL_PREFIX": "aixle_dev_",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if c.Listen != "127.0.0.1:1" || c.RailsURL != "http://web:4000" || string(c.TicketKey) != "0123456789abcdef0123" ||
		c.MaxStreams != 8 || c.CheckInterval != 5*time.Second || c.RedisChannelPrefix != "aixle_dev_" {
		t.Fatalf("values: %+v", c)
	}
}

func TestFromEnvReportsEveryProblemWithoutEchoingSecrets(t *testing.T) {
	_, err := FromEnv(env(map[string]string{
		"RUNNER_RELAY_REDIS_URL":      "http://:s3cret@redis",
		"RUNNER_RELAY_TICKET_KEY":     "short",
		"RUNNER_RELAY_MAX_STREAMS":    "zero",
		"RUNNER_RELAY_CHECK_INTERVAL": "soon",
		"RUNNER_RELAY_RAILS_URL":      "ftp://x",
	}))
	if err == nil {
		t.Fatal("want an error")
	}
	msg := err.Error()
	for _, want := range []string{"RUNNER_RELAY_REDIS_URL", "RUNNER_RELAY_TICKET_KEY", "RUNNER_RELAY_MAX_STREAMS",
		"RUNNER_RELAY_CHECK_INTERVAL", "RUNNER_RELAY_RAILS_URL"} {
		if !strings.Contains(msg, want) {
			t.Errorf("the error does not mention %s: %v", want, msg)
		}
	}
	if strings.Contains(msg, "s3cret") || strings.Contains(msg, "short") {
		t.Errorf("the error echoes a secret: %v", msg)
	}
}

func TestFromEnvRequiresRedisAndKey(t *testing.T) {
	_, err := FromEnv(env(nil))
	if err == nil || !strings.Contains(err.Error(), "RUNNER_RELAY_REDIS_URL is required") ||
		!strings.Contains(err.Error(), "RUNNER_RELAY_TICKET_KEY") ||
		!strings.Contains(err.Error(), "RUNNER_RELAY_RAILS_URL is required") ||
		!strings.Contains(err.Error(), "RUNNER_RELAY_INTERNAL_TOKEN is required") {
		t.Fatalf("got %v", err)
	}
}
