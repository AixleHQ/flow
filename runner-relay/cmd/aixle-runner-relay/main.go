// Command aixle-runner-relay is the platform's runner relay: the service that holds
// one WebSocket per machine and, later, every long-held runner connection
// (docs/design/agent-runtimes/runner-relay.md).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/aixlehq/aixle-runner-relay/internal/admin"
	"github.com/aixlehq/aixle-runner-relay/internal/config"
	"github.com/aixlehq/aixle-runner-relay/internal/relay"
	"github.com/aixlehq/aixle-runner-relay/internal/ticket"
)

// drainTime is how long shutdown waits for the connections to finish after GOAWAY
// (§5.4). The Deployment's terminationGracePeriodSeconds is longer (45 s).
const drainTime = 30 * time.Second

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("aixle-runner-relay stopped", "error", err.Error())
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.FromEnv(os.Getenv)
	if err != nil {
		return fmt.Errorf("configuration: %w", err)
	}
	redisOptions, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		return errors.New("RUNNER_RELAY_REDIS_URL is not a Redis URL")
	}
	// The client's own log lines (a connection it could not dial) are JSON like the rest.
	redis.SetLogger(redisLog{logger})
	rdb := redis.NewClient(redisOptions)
	defer rdb.Close()

	metrics := relay.NewMetrics()
	server := relay.New(relay.Options{
		Verifier:   ticket.NewVerifier(cfg.TicketKey),
		Guard:      ticket.RedisGuard{Client: rdb},
		Metrics:    metrics,
		Logger:     logger,
		MaxFrame:   cfg.MaxFrame,
		MaxStreams: cfg.MaxStreams,
		Window:     cfg.StreamWindow,
	})

	public := &http.Server{Handler: server.Handler(), ReadHeaderTimeout: 10 * time.Second}
	adminServer := &http.Server{Handler: admin.Handler(server, metrics.Registry), ReadHeaderTimeout: 10 * time.Second}
	publicLn, err := net.Listen("tcp", cfg.Listen)
	if err != nil {
		return err
	}
	adminLn, err := net.Listen("tcp", cfg.AdminListen)
	if err != nil {
		return err
	}
	logger.Info("aixle-runner-relay starting", "listen", cfg.Listen, "admin_listen", cfg.AdminListen,
		"max_streams", cfg.MaxStreams, "max_frame", cfg.MaxFrame, "stream_window", cfg.StreamWindow)

	failed := make(chan error, 2)
	go func() { failed <- fmt.Errorf("public server: %w", public.Serve(publicLn)) }()
	go func() { failed <- fmt.Errorf("admin server: %w", adminServer.Serve(adminLn)) }()

	stop, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	select {
	case err := <-failed:
		return err
	case <-stop.Done():
	}

	// GOAWAY on every connection, and /readyz fails so no new one is sent here; the
	// runners reconnect (to the next replica), and each connection closes when its
	// streams are done.
	logger.Info("shutting down: draining the tunnel connections")
	server.Drain()
	drainCtx, drainCancel := context.WithTimeout(context.Background(), drainTime)
	defer drainCancel()
	if err := server.Wait(drainCtx); err != nil {
		logger.Warn("connections left after the drain; closing them")
	}
	server.CloseAll()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	public.Shutdown(shutdownCtx)
	adminServer.Shutdown(shutdownCtx)
	return nil
}

// redisLog routes go-redis's log lines to the service's JSON logger. They name an
// address and an error, never a command or a value.
type redisLog struct{ logger *slog.Logger }

func (l redisLog) Printf(ctx context.Context, format string, v ...interface{}) {
	l.logger.WarnContext(ctx, fmt.Sprintf(format, v...), "component", "redis")
}
