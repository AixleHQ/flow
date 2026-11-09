package docker

import (
	"context"
	"testing"
)

// The self-update waits while the machine holds a session (internal/update).
func TestHoldsSessionWhileTheSessionContainerExists(t *testing.T) {
	h := newEnvironment(t)
	if busy, err := h.env.HoldsSession(context.Background()); err != nil || busy {
		t.Fatalf("an idle environment: %v %v", busy, err)
	}

	h.start(h.env, nil)
	if busy, err := h.env.HoldsSession(context.Background()); err != nil || !busy {
		t.Fatalf("with a session container: %v %v", busy, err)
	}
	// Another environment's session container is not this machine's session.
	if busy, err := h.another("aixle-r9-other").HoldsSession(context.Background()); err != nil || busy {
		t.Fatalf("another environment: %v %v", busy, err)
	}

	h.run(h.env.ContainerStop, map[string]any{})
	if busy, err := h.env.HoldsSession(context.Background()); err != nil || busy {
		t.Fatalf("after container.stop: %v %v", busy, err)
	}
}
