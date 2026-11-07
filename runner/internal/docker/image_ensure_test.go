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
	// pinned is the image by digest, the reference most tests start their
	// container from; tagged is the same image by tag.
	pinned = image + "@" + digest
	tagged = image + ":1.4"
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

func ensure(t *testing.T, api API, ref string) protocol.Result {
	t.Helper()
	return ImageEnsure(api, steppingClock())(context.Background(), payload(t, map[string]string{"image": ref}))
}

func TestPullsAnImageTheDaemonDoesNotHave(t *testing.T) {
	for _, ref := range []string{tagged, pinned} {
		f, c := newFakeEngine(t)
		r := ensure(t, c, ref)
		if r.Status != protocol.StatusOK || r.Data["pulled"] != true || r.Data["duration_ms"] != int64(1500) {
			t.Fatalf("%s: result %#v", ref, r)
		}
		if len(f.pulls) != 1 || f.pulls[0] != ref {
			t.Fatalf("%s: pulls %v", ref, f.pulls)
		}
	}
}

func TestAlwaysPullsAndReportsWhetherThePullBroughtANewImage(t *testing.T) {
	f, c := newFakeEngine(t)
	f.images[tagged] = true
	if r := ensure(t, c, tagged); r.Status != protocol.StatusOK || r.Data["pulled"] != false {
		t.Fatalf("an image that is up to date: result %#v", r)
	}
	f.pullNewer = true
	if r := ensure(t, c, tagged); r.Status != protocol.StatusOK || r.Data["pulled"] != true {
		t.Fatalf("a tag that moved: result %#v", r)
	}
	if len(f.pulls) != 2 {
		t.Fatalf("pulls %v: every image.ensure pulls", f.pulls)
	}
}

func TestAReferenceWithoutATagIsPulledAsLatest(t *testing.T) {
	f, c := newFakeEngine(t)
	if r := ensure(t, c, image); r.Status != protocol.StatusOK {
		t.Fatalf("result %#v", r)
	}
	if len(f.pulls) != 1 || f.pulls[0] != image+":latest" {
		t.Fatalf("pulls %v", f.pulls)
	}
}

func TestAPullFailureCarriesTheRegistrysMessage(t *testing.T) {
	f, c := newFakeEngine(t)
	f.images[tagged] = true
	f.pullError = "manifest for " + tagged + " not found: manifest unknown"
	r := ensure(t, c, tagged)
	if r.Status != protocol.StatusError || r.Error.Class != ClassImagePull || !strings.Contains(r.Error.Message, "manifest unknown") {
		t.Fatalf("result %#v: a pull that fails is a failure, even with the image there", r)
	}
}

func TestARefusedPullCarriesTheDaemonsMessage(t *testing.T) {
	f, c := newFakeEngine(t)
	f.pullStatus = 404
	r := ensure(t, c, pinned)
	if r.Status != protocol.StatusError || r.Error.Class != ClassImagePull || !strings.Contains(r.Error.Message, "pull access denied") {
		t.Fatalf("result %#v", r)
	}
}

func TestInvalidPayloads(t *testing.T) {
	f, c := newFakeEngine(t)
	for _, p := range []json.RawMessage{
		json.RawMessage(`[]`),
		payload(t, map[string]string{}),
		payload(t, map[string]string{"image": " "}),
		payload(t, map[string]string{"image": image + "@sha256:abc"}),
		payload(t, map[string]string{"image": "Not A Repo"}),
		payload(t, map[string]any{"image": 7}),
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
	r := ImageEnsure(c, nil)(context.Background(), payload(t, map[string]any{"image": pinned, "platform": "linux/amd64"}))
	if r.Status != protocol.StatusOK {
		t.Fatalf("result %#v", r)
	}
}
