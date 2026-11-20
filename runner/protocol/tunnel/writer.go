package tunnel

import "encoding/binary"

// maxControlQueue bounds the control frames that wait for the writer. An honest
// peer needs a few per stream; a PING or OPEN flood from a peer that does not read is cut.
const maxControlQueue = 4096

// writeQueue is what the session's one writer goroutine takes from: a FIFO of
// control frames, and a ring of the streams that have bytes and credit. It is
// guarded by the session's mutex.
type writeQueue struct {
	ctrl  [][]byte
	ready []*Stream
}

func (q *writeQueue) pushControl(msg []byte) { q.ctrl = append(q.ctrl, msg) }

// markReady puts a stream in the ring if it has bytes to send and credit to send
// them with.
func (q *writeQueue) markReady(st *Stream) {
	if st.queued || st.finished || len(st.out) == 0 || st.send.credit == 0 {
		return
	}
	st.queued = true
	q.ready = append(q.ready, st)
}

// next returns the next message: a control frame if there is one, otherwise one DATA
// frame, of at most maxFrame bytes, of the stream at the head of the ring, which
// then goes to the back. A control frame therefore waits for one DATA frame at most
// (PROTOCOL.md §8.6).
func (q *writeQueue) next(maxFrame int) []byte {
	if len(q.ctrl) > 0 {
		msg := q.ctrl[0]
		q.ctrl[0] = nil
		q.ctrl = q.ctrl[1:]
		return msg
	}
	for len(q.ready) > 0 {
		st := q.ready[0]
		q.ready[0] = nil
		q.ready = q.ready[1:]
		st.queued = false
		if st.finished || len(st.out) == 0 || st.send.credit == 0 {
			continue
		}
		n := st.send.take(min(len(st.out), maxFrame))
		msg := make([]byte, HeaderLen+n)
		msg[0] = byte(TypeData)
		binary.BigEndian.PutUint32(msg[1:HeaderLen], st.id)
		copy(msg[HeaderLen:], st.out[:n])
		st.out = st.out[n:]
		st.taken += n
		q.markReady(st)
		st.notifyLocked()
		return msg
	}
	return nil
}
