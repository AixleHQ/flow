package tunnel

import (
	"context"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/coder/websocket"

	"github.com/aixlehq/aixle-runner/internal/protocol"
	wire "github.com/aixlehq/aixle-runner/protocol/tunnel"
)

// Subprotocol is the WebSocket subprotocol of relay protocol 1 (PROTOCOL.md §8.11).
const Subprotocol = "aixle-runner-relay.v1"

// ConnectTimeout bounds the upgrade and the HELLO exchange together.
const ConnectTimeout = 30 * time.Second

var errNoSubprotocol = errors.New("the relay did not choose the subprotocol " + Subprotocol)

// maxRefusalBytes is what is read of an upgrade's refusal: the JSON shape of §3 is
// a few hundred bytes.
const maxRefusalBytes = 4 << 10

// Connector opens the tunnel's connection with a ticket and completes the handshake.
// An upgrade the relay refused is a *protocol.Refusal, and any other failure to
// connect is a *protocol.NetworkError.
type Connector interface {
	Connect(ctx context.Context, ticket string) (*wire.Session, error)
}

// WSConnector is the Connector of a real relay: a WebSocket to URL, then the
// package's runner end and its HELLO.
type WSConnector struct {
	// URL is `wss://<platform>/runner/v1/tunnel`.
	URL string
	// Version is the runner's version: X-Aixle-Runner-Version and the HELLO's
	// runner_version.
	Version string
	// HTTPClient is nil for the default transport, which honours the machine's proxy
	// settings. It must have no Timeout.
	HTTPClient *http.Client
	// Config is the end's offer of limits; its RunnerVersion is set from Version.
	Config wire.Config
}

// Connect implements Connector. The ticket goes in the Authorization header only,
// and in no error or log line.
func (c *WSConnector) Connect(ctx context.Context, ticket string) (*wire.Session, error) {
	ctx, cancel := context.WithTimeout(ctx, ConnectTimeout)
	defer cancel()

	header := http.Header{}
	header.Set("Authorization", "Bearer "+ticket)
	header.Set("X-Aixle-Runner-Protocol", protocol.ProtocolVersion)
	header.Set("X-Aixle-Runner-Version", c.Version)
	conn, resp, err := websocket.Dial(ctx, c.URL, &websocket.DialOptions{
		HTTPClient: c.HTTPClient, HTTPHeader: header, Subprotocols: []string{Subprotocol},
	})
	if err != nil {
		if resp != nil && resp.StatusCode != http.StatusSwitchingProtocols {
			var body []byte
			if resp.Body != nil {
				body, _ = io.ReadAll(io.LimitReader(resp.Body, maxRefusalBytes))
				resp.Body.Close()
			}
			return nil, protocol.ParseRefusal(protocol.EndpointTunnel, resp.StatusCode, body)
		}
		// The library's error names the URL and the status, never a header.
		return nil, &protocol.NetworkError{Endpoint: protocol.EndpointTunnel, Err: err}
	}
	if conn.Subprotocol() != Subprotocol {
		conn.Close(websocket.StatusProtocolError, "subprotocol")
		return nil, &protocol.NetworkError{Endpoint: protocol.EndpointTunnel, Err: errNoSubprotocol}
	}
	cfg := c.Config
	cfg.RunnerVersion = c.Version
	session := wire.NewRunner(wire.NewWSConn(conn), cfg)
	if err := session.Handshake(ctx); err != nil {
		return nil, &protocol.NetworkError{Endpoint: protocol.EndpointTunnel, Err: err}
	}
	return session, nil
}
