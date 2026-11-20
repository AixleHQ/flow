package tunnel

import (
	"errors"
	"fmt"
)

var (
	// ErrSessionClosed is returned by a closed session, and wrapped by the error
	// every stream gets when the connection is lost.
	ErrSessionClosed = errors.New("tunnel: session closed")
	// ErrStreamLimit is returned by Open when the negotiated max_streams is reached.
	ErrStreamLimit = errors.New("tunnel: stream limit reached")
	// ErrGoAway is returned by Open and Accept once a GOAWAY was sent or received,
	// and is the Err of a session that closed after the drain.
	ErrGoAway = errors.New("tunnel: going away")
	// ErrHeartbeat is the Err of a session closed after three silent intervals.
	ErrHeartbeat = errors.New("tunnel: heartbeat timeout")

	errWrongRole  = errors.New("tunnel: this call belongs to the other end of the connection")
	errNotStarted = errors.New("tunnel: the handshake has not completed")
	errIDsEnd     = errors.New("tunnel: stream ids are used up")
	errTooLarge   = errors.New("tunnel: DATA frame over max_frame")
)

// ResetError is the error of a stream that ended with RESET, from either side.
type ResetError struct {
	Code ResetCode
	Text string
}

func (e *ResetError) Error() string {
	if e.Text == "" {
		return "tunnel: stream reset: " + e.Code.String()
	}
	return fmt.Sprintf("tunnel: stream reset: %s: %s", e.Code, e.Text)
}

var errAnswered = errors.New("tunnel: the OPEN was answered already")
