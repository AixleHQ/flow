package cli

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/url"
	"strings"

	"github.com/aixlehq/aixle-runner/internal/docker"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/tunnel"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// tunnelManager is the interactive tunnel's manager (PROTOCOL.md §8, DESIGN.md §6.9.5), or
// nil when the platform's check-in does not turn the tunnel on: no `config.tunnel`, or a
// mode this runner does not know. A platform that has no relay deployed says nothing, so
// no runner of a machine on it ever tries to connect.
func tunnelManager(answer protocol.CheckIn, client *protocol.Client, source *tokens.Source, env *docker.Environment, serving *tunnel.Serving, override string, logger *slog.Logger) *tunnel.Manager {
	cfg := answer.Config.Tunnel
	if cfg == nil {
		return nil
	}
	if cfg.Mode != tunnel.ModeSession {
		logger.Info("the platform offers a tunnel mode this runner does not know; the tunnel stays off", "mode", cfg.Mode)
		return nil
	}
	var target string
	if override != "" {
		var err error
		if target, err = tunnelOverride(override); err != nil {
			logger.Error("the tunnel stays off: "+TunnelURLEnv+" is not usable", "error", err)
			return nil
		}
	} else {
		target = client.TunnelURL(tunnelPath(cfg.Path))
	}
	return &tunnel.Manager{
		Gateway:   client,
		Tokens:    source,
		Connector: &tunnel.WSConnector{URL: target, Version: version.Version},
		Holds:     env.HoldsSession,
		Serving:   serving,
		Logger:    logger,
	}
}

// TunnelURLEnv names a WebSocket URL that the tunnel connects to instead of the
// platform's own host. The platform's ingress sends the tunnel's path to the relay, so a
// machine never needs it. It is for the development stack, where the runner reaches the
// gateway on its own loopback and nothing splits the tunnel's path off from it.
const TunnelURLEnv = "AIXLE_RUNNER_TUNNEL_URL"

// tunnelOverride checks TunnelURLEnv's value with the rule the platform's URL has: `wss`,
// or `ws` for a loopback host, and no user info, query or fragment.
func tunnelOverride(raw string) (string, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u.Host == "" {
		return "", fmt.Errorf("%q is not an absolute URL", raw)
	}
	if u.User != nil || u.RawQuery != "" || u.Fragment != "" {
		return "", errors.New("it must not carry user info, a query or a fragment")
	}
	switch u.Scheme {
	case "wss":
	case "ws":
		if !loopback(u.Hostname()) {
			return "", errors.New("it must use wss, except for a loopback host")
		}
	default:
		return "", errors.New("it must be a ws:// or wss:// URL")
	}
	return u.String(), nil
}

func loopback(host string) bool {
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// tunnelPath is the path the check-in names, when it is one of the gateway's own
// (`/runner/v1/…`): the platform may route the tunnel elsewhere on its host, and a
// path outside the protocol's prefix is not a tunnel.
func tunnelPath(path string) string {
	if strings.HasPrefix(path, "/runner/v1/") && !strings.ContainsAny(path, "?# ") {
		return path
	}
	return protocol.DefaultTunnelPath
}

// tunnelRunner is what runWithTunnel needs of the manager.
type tunnelRunner interface {
	Run(ctx context.Context) error
}

// runWithTunnel runs the ops loop and, beside it, the tunnel's manager when there is
// one. The tunnel is not a liveness signal and never stops the loop for its own
// trouble: only a refusal that ends the runner's work (a revoked runner, dead
// credentials) is returned, as the loop would return it.
func runWithTunnel(ctx context.Context, run func(context.Context) error, manager tunnelRunner, logger *slog.Logger) error {
	if manager == nil {
		return run(ctx)
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	stopped := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		err := manager.Run(ctx)
		switch {
		case err == nil, errors.Is(err, tunnel.ErrUnsupported):
		default:
			if _, stop := tokens.AsStop(err); stop {
				stopped <- err
				cancel()
				return
			}
			logger.Error("the tunnel manager stopped", "error", err)
		}
	}()
	err := run(ctx)
	cancel()
	<-done
	select {
	case stopErr := <-stopped:
		return stopErr
	default:
		return err
	}
}
