package tunnel

// sendWindow is the credit of one stream's send direction: the bytes the peer
// said it may still receive. It is guarded by the session's mutex.
type sendWindow struct {
	credit int
	limit  int // the negotiated window: credit never exceeds it
}

func newSendWindow(window int) sendWindow { return sendWindow{credit: window, limit: window} }

// grant adds the credit of a WINDOW frame. It reports false, and changes nothing,
// when the credit would pass the window: a flow_violation.
func (w *sendWindow) grant(n int) bool {
	if w.credit+n > w.limit {
		return false
	}
	w.credit += n
	return true
}

// take spends up to want bytes of credit and returns how many.
func (w *sendWindow) take(want int) int {
	n := min(want, w.credit)
	w.credit -= n
	return n
}

// recvWindow is the credit of one stream's receive direction. credit is what the
// peer may still send; owed is what the reader handed on and the peer was not told
// yet. credit + owed + the buffered bytes always equal the window.
type recvWindow struct {
	window int
	credit int
	owed   int
}

func newRecvWindow(window int) recvWindow { return recvWindow{window: window, credit: window} }

// receive accounts n bytes of DATA. It reports false when the peer had less credit.
func (w *recvWindow) receive(n int) bool {
	if n > w.credit {
		return false
	}
	w.credit -= n
	return true
}

// consumed accounts n bytes handed to the reader. When at least half the window is
// owed it returns the amount for a WINDOW frame, and zero otherwise.
func (w *recvWindow) consumed(n int) int {
	w.owed += n
	if w.owed < w.window/2 {
		return 0
	}
	grant := w.owed
	w.credit += grant
	w.owed = 0
	return grant
}
