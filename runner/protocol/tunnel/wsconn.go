package tunnel

import (
	"context"
	"errors"

	"github.com/coder/websocket"
)

// wsConn adapts a coder/websocket connection to Conn. This file is the only one of
// the package that imports the WebSocket library.
type wsConn struct{ c *websocket.Conn }

// NewWSConn wraps a WebSocket connection: binary messages, one frame each. It sets
// the read limit to MaxMessage, so a message over it closes the connection with
// 1009. A text message is a *ProtocolError. A close the peer sent with a code is a
// *CloseError.
func NewWSConn(c *websocket.Conn) Conn {
	c.SetReadLimit(MaxMessage)
	return &wsConn{c: c}
}

func (w *wsConn) ReadMessage(ctx context.Context) ([]byte, error) {
	typ, msg, err := w.c.Read(ctx)
	if err != nil {
		var ce websocket.CloseError
		if errors.As(err, &ce) {
			return nil, &CloseError{Code: int(ce.Code), Reason: ce.Reason}
		}
		return nil, err
	}
	if typ != websocket.MessageBinary {
		return nil, protoErr("text message")
	}
	return msg, nil
}

func (w *wsConn) WriteMessage(ctx context.Context, msg []byte) error {
	return w.c.Write(ctx, websocket.MessageBinary, msg)
}

func (w *wsConn) Close(code int, reason string) error {
	return w.c.Close(websocket.StatusCode(code), cutCloseReason(reason))
}
