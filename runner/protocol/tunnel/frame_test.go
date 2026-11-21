package tunnel

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"
	"unicode/utf8"
)

func mustHex(t testing.TB, s string) []byte {
	t.Helper()
	b, err := hex.DecodeString(strings.ReplaceAll(s, " ", ""))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestEncodeEveryFrameType(t *testing.T) {
	cases := []struct {
		name  string
		frame Frame
		hex   string
	}{
		{"HELLO from the relay", Hello{V: 1, MaxFrame: 32768, MaxStreams: 64, Window: 262144, PingInterval: 20, SessionID: i64(123)}.Frame(true),
			"01 00000000 " + hex.EncodeToString([]byte(`{"v":1,"max_frame":32768,"max_streams":64,"window":262144,"ping_interval":20,"session_id":123}`))},
		{"HELLO from the relay, no session", Hello{V: 1, MaxFrame: 32768, MaxStreams: 64, Window: 262144, PingInterval: 20}.Frame(true),
			"01 00000000 " + hex.EncodeToString([]byte(`{"v":1,"max_frame":32768,"max_streams":64,"window":262144,"ping_interval":20,"session_id":null}`))},
		{"HELLO from the runner", Hello{V: 1, MaxFrame: 16384, MaxStreams: 8, Window: 65536, RunnerVersion: "1.4.0"}.Frame(false),
			"01 00000000 " + hex.EncodeToString([]byte(`{"v":1,"max_frame":16384,"max_streams":8,"window":65536,"runner_version":"1.4.0"}`))},
		{"HELLO with features", Hello{V: 1, MaxFrame: 1024, MaxStreams: 1, Window: 1024, RunnerVersion: "x", Features: []string{"wake"}}.Frame(false),
			"01 00000000 " + hex.EncodeToString([]byte(`{"v":1,"max_frame":1024,"max_streams":1,"window":1024,"runner_version":"x","features":["wake"]}`))},
		{"OPEN", OpenFrame(1, Open{SessionID: 123, Port: 7681}),
			"02 00000001 " + hex.EncodeToString([]byte(`{"session_id":123,"port":7681}`))},
		{"OPEN_OK", Frame{Type: TypeOpenOK, Stream: 1}, "03 00000001"},
		{"DATA", Frame{Type: TypeData, Stream: 2, Payload: []byte("hi")}, "04 00000002 6869"},
		{"WINDOW", WindowFrame(1, 131072), "05 00000001 00020000"},
		{"CLOSE", Frame{Type: TypeClose, Stream: 7}, "06 00000007"},
		{"RESET with text", ResetFrame(1, ResetTimeout, "slow"), "07 00000001 04 736c6f77"},
		{"RESET without text", ResetFrame(300, ResetCancelled, ""), "07 0000012c 01"},
		{"PING", Frame{Type: TypePing, Payload: []byte{0, 0, 0, 0, 0, 0, 0, 1}}, "08 00000000 0000000000000001"},
		{"PONG", Frame{Type: TypePong, Payload: []byte{0, 0, 0, 0, 0, 0, 0, 1}}, "09 00000000 0000000000000001"},
		{"GOAWAY", Frame{Type: TypeGoAway}, "0a 00000000"},
	}
	seen := map[Type]bool{}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			want := mustHex(t, c.hex)
			got, err := Encode(c.frame)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(got, want) {
				t.Fatalf("Encode = %x, want %x", got, want)
			}
			back, err := Decode(want)
			if err != nil {
				t.Fatal(err)
			}
			if back.Type != c.frame.Type || back.Stream != c.frame.Stream || !bytes.Equal(back.Payload, c.frame.Payload) {
				t.Fatalf("Decode = %+v, want %+v", back, c.frame)
			}
		})
		seen[c.frame.Type] = true
	}
	for _, typ := range AllTypes {
		if !seen[typ] {
			t.Errorf("no case encodes %s", typ)
		}
	}
}

func TestPayloadAccessors(t *testing.T) {
	h, err := Hello{V: 1, MaxFrame: 2048, MaxStreams: 3, Window: 4096, PingInterval: 5, SessionID: i64(9)}.Frame(true).Hello()
	if err != nil || h.MaxFrame != 2048 || h.MaxStreams != 3 || h.Window != 4096 || h.PingInterval != 5 || *h.SessionID != 9 {
		t.Fatalf("Hello = %+v, %v", h, err)
	}
	o, err := OpenFrame(4, Open{SessionID: 5, Port: 6}).Open()
	if err != nil || o != (Open{SessionID: 5, Port: 6}) {
		t.Fatalf("Open = %+v, %v", o, err)
	}
	if c := WindowFrame(1, 77).Credit(); c != 77 {
		t.Fatalf("Credit = %d", c)
	}
	code, text := ResetFrame(1, ResetRevoked, "gone").Reset()
	if code != ResetRevoked || text != "gone" {
		t.Fatalf("Reset = %s %q", code, text)
	}
}

func TestDecoderAcceptsAnyKeyOrderAndUnknownKeys(t *testing.T) {
	payload := `{"future":{"a":[1,2]},"window":4096,"runner_version":"2.0.0","max_streams":4,"v":1,"max_frame":2048}`
	f, err := Decode(append(mustHex(t, "01 00000000"), payload...))
	if err != nil {
		t.Fatal(err)
	}
	h, err := f.Hello()
	if err != nil || h.MaxFrame != 2048 || h.Window != 4096 || h.RunnerVersion != "2.0.0" {
		t.Fatalf("Hello = %+v, %v", h, err)
	}
	f, err = Decode(append(mustHex(t, "02 00000001"), `{"port":80,"extra":true,"session_id":5}`...))
	if err != nil {
		t.Fatal(err)
	}
	if o, _ := f.Open(); o.Port != 80 || o.SessionID != 5 {
		t.Fatalf("Open = %+v", o)
	}
}

func TestResetTextLimit(t *testing.T) {
	long := strings.Repeat("é", 200) // 400 bytes
	f := ResetFrame(1, ResetInternal, long)
	if n := len(f.Payload) - 1; n > MaxResetText || n%2 != 0 {
		t.Fatalf("sent text of %d bytes, want an even number up to %d (whole characters)", n, MaxResetText)
	}
	// A longer text from another sender is ignored, and the code is kept.
	over := Frame{Type: TypeReset, Stream: 1, Payload: append([]byte{byte(ResetRefused)}, strings.Repeat("x", MaxResetText+1)...)}
	msg, err := Encode(over)
	if err != nil {
		t.Fatal(err)
	}
	back, err := Decode(msg)
	if err != nil {
		t.Fatal(err)
	}
	if code, text := back.Reset(); code != ResetRefused || text != "" {
		t.Fatalf("Reset = %s %q", code, text)
	}
}

func TestResetCodeNames(t *testing.T) {
	want := []string{"cancelled", "refused", "dial_failed", "timeout", "session_changed", "revoked", "flow_violation", "protocol", "internal", "shutdown"}
	for i, name := range want {
		c := ResetCode(i + 1)
		if c.String() != name {
			t.Errorf("ResetCode(%d) = %q, want %q", i+1, c, name)
		}
		if back, ok := ParseResetCode(name); !ok || back != c {
			t.Errorf("ParseResetCode(%q) = %d, %v", name, back, ok)
		}
	}
	if ResetCode(99).String() != "code_99" {
		t.Errorf("unknown code = %q", ResetCode(99))
	}
}

func TestDecodeRefusals(t *testing.T) {
	cases := []struct{ name, hex string }{
		{"empty message", ""},
		{"4 bytes", "04 000000"},
		{"unknown type 0x00", "00 00000001"},
		{"unknown type 0x0b", "0b 00000000"},
		{"unknown type 0xff", "ff 00000001 00"},
		{"HELLO with a stream id", "01 00000001 7b2276223a317d"},
		{"PING with a stream id", "08 00000001 0000000000000001"},
		{"PONG with a stream id", "09 00000001 0000000000000001"},
		{"GOAWAY with a stream id", "0a 00000001"},
		{"OPEN on stream 0", "02 00000000 " + hex.EncodeToString([]byte(`{"session_id":1,"port":2}`))},
		{"OPEN_OK on stream 0", "03 00000000"},
		{"DATA on stream 0", "04 00000000 61"},
		{"WINDOW on stream 0", "05 00000000 00000001"},
		{"CLOSE on stream 0", "06 00000000"},
		{"RESET on stream 0", "07 00000000 01"},
		{"OPEN with bad JSON", "02 00000001 7b"},
		{"OPEN without a port", "02 00000001 " + hex.EncodeToString([]byte(`{"session_id":1}`))},
		{"OPEN with a string port", "02 00000001 " + hex.EncodeToString([]byte(`{"session_id":1,"port":"x"}`))},
		{"HELLO without window", "01 00000000 " + hex.EncodeToString([]byte(`{"v":1,"max_frame":2048,"max_streams":1}`))},
		{"HELLO not an object", "01 00000000 5b5d"},
		{"OPEN_OK with a payload", "03 00000001 00"},
		{"CLOSE with a payload", "06 00000001 00"},
		{"GOAWAY with a payload", "0a 00000000 00"},
		{"WINDOW of 3 bytes", "05 00000001 000001"},
		{"WINDOW of 5 bytes", "05 00000001 0000000100"},
		{"RESET without a code", "07 00000001"},
		{"PING of 7 bytes", "08 00000000 00000000000000"},
		{"PONG of 9 bytes", "09 00000000 000000000000000000"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Decode(mustHex(t, c.hex))
			if _, ok := err.(*ProtocolError); !ok {
				t.Fatalf("Decode(%s) = %v, want a *ProtocolError", c.hex, err)
			}
		})
	}
}

func TestEncodeRefusesWhatDecodeRefuses(t *testing.T) {
	for _, f := range []Frame{
		{Type: TypeData},
		{Type: TypeHello, Stream: 1, Payload: []byte(`{}`)},
		{Type: Type(0x0b)},
		{Type: TypePing, Payload: []byte{1}},
	} {
		if _, err := Encode(f); err == nil {
			t.Errorf("Encode(%+v) succeeded", f)
		}
	}
}

func TestTypeNames(t *testing.T) {
	want := []string{"HELLO", "OPEN", "OPEN_OK", "DATA", "WINDOW", "CLOSE", "RESET", "PING", "PONG", "GOAWAY"}
	if len(AllTypes) != len(want) {
		t.Fatalf("%d types", len(AllTypes))
	}
	for i, typ := range AllTypes {
		if typ.String() != want[i] || int(typ) != i+1 {
			t.Errorf("type %d is %s (0x%02x)", i+1, typ, uint8(typ))
		}
	}
}

func TestFuzzSeedsHold(t *testing.T) {
	for _, seed := range decodeSeeds(t) {
		f, err := Decode(seed)
		if err != nil {
			continue
		}
		msg, err := Encode(f)
		if err != nil || !bytes.Equal(msg, seed) {
			t.Errorf("Decode then Encode of %x = %x, %v", seed, msg, err)
		}
	}
}

func FuzzDecode(f *testing.F) {
	for _, seed := range decodeSeeds(f) {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, msg []byte) {
		fr, err := Decode(msg)
		if err != nil {
			if _, ok := err.(*ProtocolError); !ok {
				t.Fatalf("Decode returned %T, not a *ProtocolError", err)
			}
			return
		}
		again, err := Encode(fr)
		if err != nil {
			t.Fatalf("a decoded frame does not encode: %v", err)
		}
		if !bytes.Equal(again, msg) {
			t.Fatalf("Decode then Encode changed the message: %x -> %x", msg, again)
		}
		switch fr.Type {
		case TypeHello:
			fr.Hello()
		case TypeOpen:
			fr.Open()
		case TypeReset:
			fr.Reset()
		case TypeWindow:
			fr.Credit()
		}
	})
}

// cutText and cutCloseReason share one helper with their own limits.
func TestCutUTF8CutsOnACharacterBoundary(t *testing.T) {
	for _, tc := range []struct {
		in    string
		limit int
		want  string
	}{
		{"abc", 3, "abc"},
		{"abcd", 3, "abc"},
		{"aé", 2, "a"},   // é is two bytes: the cut would split it
		{"aé", 3, "aé"},  // it fits
		{"日本語", 4, "日"},  // three bytes each
		{"日本語", 8, "日本"}, // 6 bytes fit, the third character does not
		{"😀😀", 5, "😀"},   // four bytes each
		{"", 0, ""},
		{"abc", 0, ""},
	} {
		got := cutUTF8(tc.in, tc.limit)
		if got != tc.want || !utf8.ValidString(got) {
			t.Errorf("cutUTF8(%q, %d) = %q, want %q", tc.in, tc.limit, got, tc.want)
		}
	}
	if got := cutText(strings.Repeat("é", MaxResetText)); len(got) != MaxResetText {
		t.Errorf("cutText kept %d bytes, want %d (whole characters)", len(got), MaxResetText)
	}
	if got := cutText(strings.Repeat("é", MaxResetText) + "x"); len(got) != MaxResetText {
		t.Errorf("cutText over the limit kept %d bytes", len(got))
	}
	if got := cutCloseReason(strings.Repeat("é", 100)); len(got) != 120 || !utf8.ValidString(got) {
		t.Errorf("cutCloseReason kept %d bytes", len(got))
	}
}
