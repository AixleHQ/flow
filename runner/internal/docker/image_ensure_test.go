package docker

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

const (
	image  = "ghcr.io/aixlehq/flow-agent-claude-code"
	digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
)

func payload(t *testing.T, v any) json.RawMessage {
	raw, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func steppingClock() func() time.Time {
	t := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	return func() time.Time { t = t.Add(1500 * time.Millisecond); return t }
}

func TestPullsAnImageTheDaemonDoesNotHave(t *testing.T) {
	f, c := newFakeEngine(t)
	r := ImageEnsure(c, steppingClock())(context.Background(), payload(t, map[string]string{"image": image, "digest": digest}))
	if r.Status != protocol.StatusOK || r.Data["pulled"] != true || r.Data["duration_ms"] != int64(1500) {
		t.Fatalf("result %#v", r)
	}
	if len(f.pulls) != 1 || f.pulls[0] != image+"@"+digest {
		t.Fatalf("pulls %v", f.pulls)
	}
}

func TestDoesNotPullAnImageTheDaemonHas(t *testing.T) {
	f, c := newFakeEngine(t)
	f.images[image+"@"+digest] = true
	r := ImageEnsure(c, steppingClock())(context.Background(), payload(t, map[string]string{"image": image, "digest": digest}))
	if r.Status != protocol.StatusOK || r.Data["pulled"] != false {
		t.Fatalf("result %#v", r)
	}
	if len(f.pulls) != 0 {
		t.Fatalf("pulled %v", f.pulls)
	}
}

func TestAPullFailureCarriesTheRegistrysMessage(t *testing.T) {
	f, c := newFakeEngine(t)
	f.pullError = "manifest for " + image + "@" + digest + " not found: manifest unknown"
	r := ImageEnsure(c, nil)(context.Background(), payload(t, map[string]string{"image": image, "digest": digest}))
	if r.Status != protocol.StatusError || r.Error.Class != ClassImagePull || !strings.Contains(r.Error.Message, "manifest unknown") {
		t.Fatalf("result %#v", r)
	}
}

func TestARefusedPullCarriesTheDaemonsMessage(t *testing.T) {
	f, c := newFakeEngine(t)
	f.pullStatus = 404
	r := ImageEnsure(c, nil)(context.Background(), payload(t, map[string]string{"image": image, "digest": digest}))
	if r.Status != protocol.StatusError || r.Error.Class != ClassImagePull || !strings.Contains(r.Error.Message, "pull access denied") {
		t.Fatalf("result %#v", r)
	}
}

func TestInvalidPayloads(t *testing.T) {
	f, c := newFakeEngine(t)
	for _, p := range []json.RawMessage{
		json.RawMessage(`[]`),
		payload(t, map[string]string{"digest": digest}),
		payload(t, map[string]string{"image": image}),
		payload(t, map[string]string{"image": image, "digest": "sha256:abc"}),
		payload(t, map[string]string{"image": image, "digest": "latest"}),
		payload(t, map[string]string{"image": image + "@" + digest, "digest": digest}),
		payload(t, map[string]string{"image": "Not A Repo", "digest": digest}),
	} {
		r := ImageEnsure(c, nil)(context.Background(), p)
		if r.Status != protocol.StatusError || r.Error.Class != ClassInvalidPayload {
			t.Errorf("%s: result %#v", p, r)
		}
	}
	if len(f.pulls) != 0 {
		t.Fatalf("an invalid payload was pulled: %v", f.pulls)
	}
}

func TestUnknownPayloadFieldsAreIgnored(t *testing.T) {
	// A newer platform may add optional fields (PROTOCOL.md §7).
	_, c := newFakeEngine(t)
	r := ImageEnsure(c, nil)(context.Background(), payload(t, map[string]any{"image": image, "digest": digest, "platform": "linux/amd64"}))
	if r.Status != protocol.StatusOK {
		t.Fatalf("result %#v", r)
	}
}
