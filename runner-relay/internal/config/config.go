// Package config reads the service's configuration from RUNNER_RELAY_* environment
// variables, once, at start (docs/design/agent-runtimes/runner-relay.md §2.2). The
// service never reads config/, app/ or Rails' Settings.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// The defaults of §2.2.
const (
	DefaultListen        = ":8080"
	DefaultAdminListen   = ":9090"
	DefaultMaxStreams    = 64
	DefaultMaxFrame      = 32768
	DefaultStreamWindow  = 262144
	DefaultCheckInterval = 60 * time.Second
)

// Config is the service's configuration. It holds secrets (TicketKey,
// InternalToken): log its fields one by one, never the struct.
type Config struct {
	Listen      string
	AdminListen string

	// RedisURL is the platform's Redis, which holds the single-use record of ticket
	// ids. RedisChannelPrefix is the prefix Action Cable gives its channels
	// (`aixle_<env>_`), for the signals of a later task.
	RedisURL           string
	RedisChannelPrefix string

	// RailsURL and InternalToken are for the short calls to Rails (§8.2), which
	// a later task makes.
	RailsURL      string
	InternalToken string

	// TicketKey verifies tunnel tickets (§3.1). It is never RUNNERS_SECRET_KEY.
	TicketKey []byte

	MaxStreams    int
	MaxFrame      int
	StreamWindow  int
	CheckInterval time.Duration
}

// MinTicketKeyLength is the shortest key the service accepts.
const MinTicketKeyLength = 16

// FromEnv builds the configuration from getenv (os.Getenv in the service). Every
// problem is reported at once, so an operator fixes a deployment in one pass.
func FromEnv(getenv func(string) string) (Config, error) {
	var errs []error
	get := func(name string) string { return strings.TrimSpace(getenv(name)) }
	text := func(name, fallback string) string {
		if v := get(name); v != "" {
			return v
		}
		return fallback
	}
	number := func(name string, fallback int) int {
		v := get(name)
		if v == "" {
			return fallback
		}
		n, err := strconv.Atoi(v)
		if err != nil || n <= 0 {
			errs = append(errs, fmt.Errorf("%s must be a positive integer", name))
			return fallback
		}
		return n
	}

	c := Config{
		Listen:             text("RUNNER_RELAY_LISTEN", DefaultListen),
		AdminListen:        text("RUNNER_RELAY_ADMIN_LISTEN", DefaultAdminListen),
		RedisURL:           get("RUNNER_RELAY_REDIS_URL"),
		RedisChannelPrefix: get("RUNNER_RELAY_REDIS_CHANNEL_PREFIX"),
		RailsURL:           strings.TrimRight(get("RUNNER_RELAY_RAILS_URL"), "/"),
		InternalToken:      get("RUNNER_RELAY_INTERNAL_TOKEN"),
		TicketKey:          []byte(get("RUNNER_RELAY_TICKET_KEY")),
		MaxStreams:         number("RUNNER_RELAY_MAX_STREAMS", DefaultMaxStreams),
		MaxFrame:           number("RUNNER_RELAY_MAX_FRAME", DefaultMaxFrame),
		StreamWindow:       number("RUNNER_RELAY_STREAM_WINDOW", DefaultStreamWindow),
		CheckInterval:      DefaultCheckInterval,
	}
	if v := get("RUNNER_RELAY_CHECK_INTERVAL"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d <= 0 {
			errs = append(errs, errors.New("RUNNER_RELAY_CHECK_INTERVAL must be a positive duration such as 60s"))
		} else {
			c.CheckInterval = d
		}
	}

	if c.RedisURL == "" {
		errs = append(errs, errors.New("RUNNER_RELAY_REDIS_URL is required"))
	} else if u, err := url.Parse(c.RedisURL); err != nil || (u.Scheme != "redis" && u.Scheme != "rediss") || u.Host == "" {
		// The value is not echoed: a Redis URL may carry a password.
		errs = append(errs, errors.New("RUNNER_RELAY_REDIS_URL must be a redis:// or rediss:// URL"))
	}
	if len(c.TicketKey) < MinTicketKeyLength {
		errs = append(errs, fmt.Errorf("RUNNER_RELAY_TICKET_KEY is required and must be at least %d characters", MinTicketKeyLength))
	}
	if c.RailsURL != "" {
		if u, err := url.Parse(c.RailsURL); err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			errs = append(errs, errors.New("RUNNER_RELAY_RAILS_URL must be an http:// or https:// URL"))
		}
	}
	if c.MaxFrame < 1024 || c.MaxFrame > 65536 {
		errs = append(errs, errors.New("RUNNER_RELAY_MAX_FRAME must be between 1024 and 65536"))
	}
	if c.StreamWindow < c.MaxFrame {
		errs = append(errs, errors.New("RUNNER_RELAY_STREAM_WINDOW must be at least RUNNER_RELAY_MAX_FRAME"))
	}
	return c, errors.Join(errs...)
}
