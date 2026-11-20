// Package tunnel is the relay protocol of the interactive tunnel
// (runner/protocol/PROTOCOL.md §8): a stream multiplexer over one message
// connection, shared by the platform's runner-relay service and by aixle-runner,
// so that both ends frame, window and limit identically.
//
// The package works over an abstract Conn (one message per frame), so it needs no
// HTTP and its tests need no network. Only wsconn.go imports the WebSocket library.
package tunnel

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"strconv"
	"unicode/utf8"
)

const (
	// ProtocolVersion is the relay protocol version this package speaks (HELLO.v).
	ProtocolVersion = 1
	// Subprotocol is the WebSocket subprotocol that carries ProtocolVersion.
	Subprotocol = "aixle-runner-relay.v1"

	// HeaderLen is the size of the frame header: type (1) and stream id (4).
	HeaderLen = 5
	// MinMaxFrame and MaxFrameCeiling bound the negotiated frame payload.
	MinMaxFrame     = 1024
	MaxFrameCeiling = 65536
	// MaxMessage is the largest message a conforming peer sends.
	MaxMessage = HeaderLen + MaxFrameCeiling

	// MaxResetText is the longest text of a RESET frame, in bytes.
	MaxResetText = 256
)

// Type is the type byte of a frame.
type Type uint8

// The ten frame types of protocol 1.
const (
	TypeHello  Type = 0x01
	TypeOpen   Type = 0x02
	TypeOpenOK Type = 0x03
	TypeData   Type = 0x04
	TypeWindow Type = 0x05
	TypeClose  Type = 0x06
	TypeReset  Type = 0x07
	TypePing   Type = 0x08
	TypePong   Type = 0x09
	TypeGoAway Type = 0x0A
)

// AllTypes lists the frame types of protocol 1 in code order.
var AllTypes = []Type{
	TypeHello, TypeOpen, TypeOpenOK, TypeData, TypeWindow,
	TypeClose, TypeReset, TypePing, TypePong, TypeGoAway,
}

var typeNames = map[Type]string{
	TypeHello: "HELLO", TypeOpen: "OPEN", TypeOpenOK: "OPEN_OK", TypeData: "DATA",
	TypeWindow: "WINDOW", TypeClose: "CLOSE", TypeReset: "RESET", TypePing: "PING",
	TypePong: "PONG", TypeGoAway: "GOAWAY",
}

// String is the name of the type as PROTOCOL.md writes it.
func (t Type) String() string {
	if n, ok := typeNames[t]; ok {
		return n
	}
	return fmt.Sprintf("TYPE_0x%02X", uint8(t))
}

// ResetCode is the first payload byte of a RESET frame.
type ResetCode uint8

// The reset codes of protocol 1.
const (
	ResetCancelled     ResetCode = 1
	ResetRefused       ResetCode = 2
	ResetDialFailed    ResetCode = 3
	ResetTimeout       ResetCode = 4
	ResetSessionChange ResetCode = 5
	ResetRevoked       ResetCode = 6
	ResetFlowViolation ResetCode = 7
	ResetProtocol      ResetCode = 8
	ResetInternal      ResetCode = 9
	ResetShutdown      ResetCode = 10
)

var resetNames = map[ResetCode]string{
	ResetCancelled: "cancelled", ResetRefused: "refused", ResetDialFailed: "dial_failed",
	ResetTimeout: "timeout", ResetSessionChange: "session_changed", ResetRevoked: "revoked",
	ResetFlowViolation: "flow_violation", ResetProtocol: "protocol", ResetInternal: "internal",
	ResetShutdown: "shutdown",
}

// String is the name of the code as PROTOCOL.md writes it.
func (c ResetCode) String() string {
	if n, ok := resetNames[c]; ok {
		return n
	}
	return "code_" + strconv.Itoa(int(c))
}

// ParseResetCode is the inverse of ResetCode.String for the ten defined codes.
func ParseResetCode(name string) (ResetCode, bool) {
	for c, n := range resetNames {
		if n == name {
			return c, true
		}
	}
	return 0, false
}

// Frame is one message of the protocol. Payload is not copied by Decode: it
// aliases the message it was decoded from.
type Frame struct {
	Type    Type
	Stream  uint32
	Payload []byte
}

// ProtocolError is a message that breaks PROTOCOL.md §8. A session that meets one
// closes the connection with 1002.
type ProtocolError struct{ Reason string }

func (e *ProtocolError) Error() string { return "tunnel: protocol error: " + e.Reason }

func protoErr(format string, args ...any) *ProtocolError {
	return &ProtocolError{Reason: fmt.Sprintf(format, args...)}
}

// Hello is the payload of HELLO. The relay sends it first, the runner answers it.
type Hello struct {
	V            int
	MaxFrame     int
	MaxStreams   int
	Window       int
	PingInterval int    // seconds; the relay's HELLO only
	SessionID    *int64 // the relay's HELLO only; nil is JSON null
	// RunnerVersion is the runner's HELLO only.
	RunnerVersion string
	// Features names the frame types added after version 1.0 that the sender
	// speaks. A new frame type is sent only when both ends list it.
	Features []string
}

type helloJSON struct {
	V             *int     `json:"v"`
	MaxFrame      *int     `json:"max_frame"`
	MaxStreams    *int     `json:"max_streams"`
	Window        *int     `json:"window"`
	PingInterval  *int     `json:"ping_interval"`
	SessionID     *int64   `json:"session_id"`
	RunnerVersion string   `json:"runner_version"`
	Features      []string `json:"features"`
}

// Frame encodes the HELLO as the relay's (fromRelay) or the runner's. The keys are
// written in the order of PROTOCOL.md §8.3, without whitespace.
func (h Hello) Frame(fromRelay bool) Frame {
	var b bytes.Buffer
	fmt.Fprintf(&b, `{"v":%d,"max_frame":%d,"max_streams":%d,"window":%d`, h.V, h.MaxFrame, h.MaxStreams, h.Window)
	if fromRelay {
		fmt.Fprintf(&b, `,"ping_interval":%d,"session_id":`, h.PingInterval)
		if h.SessionID == nil {
			b.WriteString("null")
		} else {
			b.WriteString(strconv.FormatInt(*h.SessionID, 10))
		}
	} else {
		rv, _ := json.Marshal(h.RunnerVersion)
		b.WriteString(`,"runner_version":`)
		b.Write(rv)
	}
	if len(h.Features) > 0 {
		fs, _ := json.Marshal(h.Features)
		b.WriteString(`,"features":`)
		b.Write(fs)
	}
	b.WriteByte('}')
	return Frame{Type: TypeHello, Payload: b.Bytes()}
}

// Hello decodes the payload of a HELLO frame. A missing v, max_frame, max_streams
// or window is an error; the other fields are optional and unknown ones are ignored.
func (f Frame) Hello() (Hello, error) {
	var j helloJSON
	if err := json.Unmarshal(f.Payload, &j); err != nil {
		return Hello{}, protoErr("HELLO payload: %v", err)
	}
	if j.V == nil || j.MaxFrame == nil || j.MaxStreams == nil || j.Window == nil {
		return Hello{}, protoErr("HELLO payload lacks v, max_frame, max_streams or window")
	}
	h := Hello{
		V: *j.V, MaxFrame: *j.MaxFrame, MaxStreams: *j.MaxStreams, Window: *j.Window,
		SessionID: j.SessionID, RunnerVersion: j.RunnerVersion, Features: j.Features,
	}
	if j.PingInterval != nil {
		h.PingInterval = *j.PingInterval
	}
	return h, nil
}

// Open is the payload of OPEN.
type Open struct {
	SessionID int64 `json:"session_id"`
	Port      int   `json:"port"`
}

// OpenFrame is the OPEN frame of stream id.
func OpenFrame(id uint32, o Open) Frame {
	b, _ := json.Marshal(o) // struct order is the key order of §5.8
	return Frame{Type: TypeOpen, Stream: id, Payload: b}
}

// Open decodes the payload of an OPEN frame.
func (f Frame) Open() (Open, error) {
	var o struct {
		SessionID *int64 `json:"session_id"`
		Port      *int   `json:"port"`
	}
	if err := json.Unmarshal(f.Payload, &o); err != nil {
		return Open{}, protoErr("OPEN payload: %v", err)
	}
	if o.SessionID == nil || o.Port == nil {
		return Open{}, protoErr("OPEN payload lacks session_id or port")
	}
	return Open{SessionID: *o.SessionID, Port: *o.Port}, nil
}

// WindowFrame is the WINDOW frame of stream id granting credit bytes.
func WindowFrame(id uint32, credit uint32) Frame {
	return Frame{Type: TypeWindow, Stream: id, Payload: binary.BigEndian.AppendUint32(nil, credit)}
}

// Credit is the credit of a WINDOW frame.
func (f Frame) Credit() uint32 { return binary.BigEndian.Uint32(f.Payload) }

// ResetFrame is the RESET frame of stream id. The text is cut to MaxResetText
// bytes, on a character boundary.
func ResetFrame(id uint32, code ResetCode, text string) Frame {
	text = cutText(text)
	return Frame{Type: TypeReset, Stream: id, Payload: append([]byte{byte(code)}, text...)}
}

// Reset is the code and the text of a RESET frame. A text over MaxResetText bytes
// is ignored by the receiver, which keeps the code.
func (f Frame) Reset() (ResetCode, string) {
	text := ""
	if len(f.Payload) > 1 && len(f.Payload)-1 <= MaxResetText {
		text = string(f.Payload[1:])
	}
	return ResetCode(f.Payload[0]), text
}

func cutText(s string) string {
	if len(s) <= MaxResetText {
		return s
	}
	s = s[:MaxResetText]
	for len(s) > 0 && !utf8.ValidString(s) {
		s = s[:len(s)-1]
	}
	return s
}

// Encode returns the message of f. It refuses a frame that Decode would refuse.
func Encode(f Frame) ([]byte, error) {
	if err := validate(f); err != nil {
		return nil, err
	}
	msg := make([]byte, HeaderLen+len(f.Payload))
	msg[0] = byte(f.Type)
	binary.BigEndian.PutUint32(msg[1:HeaderLen], f.Stream)
	copy(msg[HeaderLen:], f.Payload)
	return msg, nil
}

// Decode parses one message. It returns a *ProtocolError for each refusal of
// PROTOCOL.md §8.2: a message under 5 bytes, an unknown type, a stream id that does
// not fit the type, or a payload that does not.
func Decode(msg []byte) (Frame, error) {
	if len(msg) < HeaderLen {
		return Frame{}, protoErr("message of %d bytes is shorter than the header", len(msg))
	}
	f := Frame{Type: Type(msg[0]), Stream: binary.BigEndian.Uint32(msg[1:HeaderLen]), Payload: msg[HeaderLen:]}
	if err := validate(f); err != nil {
		return Frame{}, err
	}
	return f, nil
}

func validate(f Frame) error {
	if _, ok := typeNames[f.Type]; !ok {
		return protoErr("unknown frame type 0x%02X", uint8(f.Type))
	}
	switch f.Type {
	case TypeHello, TypePing, TypePong, TypeGoAway:
		if f.Stream != 0 {
			return protoErr("%s with stream id %d", f.Type, f.Stream)
		}
	default:
		if f.Stream == 0 {
			return protoErr("%s with stream id 0", f.Type)
		}
	}
	switch f.Type {
	case TypeHello:
		_, err := f.Hello()
		return err
	case TypeOpen:
		_, err := f.Open()
		return err
	case TypeOpenOK, TypeClose, TypeGoAway:
		if len(f.Payload) != 0 {
			return protoErr("%s with a payload", f.Type)
		}
	case TypeWindow:
		if len(f.Payload) != 4 {
			return protoErr("WINDOW payload of %d bytes", len(f.Payload))
		}
	case TypeReset:
		if len(f.Payload) < 1 {
			return protoErr("RESET without a code")
		}
	case TypePing, TypePong:
		if len(f.Payload) != 8 {
			return protoErr("%s payload of %d bytes", f.Type, len(f.Payload))
		}
	}
	return nil
}
