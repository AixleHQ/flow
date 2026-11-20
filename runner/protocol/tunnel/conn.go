package tunnel

import (
	"context"
	"fmt"
)

// Conn is a connection that carries messages: one frame per message. The
// WebSocket adapter is in wsconn.go. Methods may be called from different
// goroutines at once, one reader and one writer; Close may be called at any time
// and unblocks both. A slice ReadMessage returns belongs to the caller.
type Conn interface {
	// ReadMessage blocks for the next message. A peer that closed the connection
	// with a code gives a *CloseError.
	ReadMessage(ctx context.Context) ([]byte, error)
	WriteMessage(ctx context.Context, msg []byte) error
	// Close closes the connection with a WebSocket close code and a short reason.
	Close(code int, reason string) error
}

// The close codes of PROTOCOL.md §8.8.
const (
	CloseNormal   = 1000
	CloseProtocol = 1002
	CloseTooLarge = 1009
	CloseTryLater = 1013
	CloseReplaced = 4000
	CloseRevoked  = 4001
	CloseTicket   = 4002
)

// CloseError is the error of a connection the peer closed with a code.
type CloseError struct {
	Code   int
	Reason string
}

func (e *CloseError) Error() string {
	return fmt.Sprintf("tunnel: connection closed by the peer with code %d %q", e.Code, e.Reason)
}
