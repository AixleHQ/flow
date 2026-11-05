package docker

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/aixlehq/aixle-runner/internal/host"
)

// The ops fixtures (runner/protocol/fixtures/v1/ops/) carry the payloads the
// platform sends and the results a runner posts. The conformance test drives them
// through the protocol client; this test ties them to the handlers: every payload
// a fixture enqueues for an op the runner implements is one its handler accepts,
// and every error class a fixture posts is one the runner reports.
func TestTheOpsFixturesMatchTheHandlers(t *testing.T) {
	files, err := filepath.Glob("../../protocol/fixtures/v1/ops/*.json")
	if err != nil || len(files) == 0 {
		t.Fatalf("no ops fixtures: %v", err)
	}
	classes := map[string]bool{
		host.ClassUnsupportedOp: true, host.ClassInterrupted: true,
		ClassInvalidPayload: true, ClassDockerError: true, ClassImagePull: true,
		ClassNoSessionContainer: true, ClassContainerExists: true, ClassImageNotFound: true,
		ClassForbiddenMount: true, ClassContainerStartFailed: true,
		ClassExecFailed: true, ClassExecTimeout: true, ClassWriteFailed: true, ClassFileNotFound: true,
		ClassNotAFile: true, ClassFileTooLarge: true, ClassBatchStepFailed: true,
		ClassScrubFailed: true, ClassResetFailed: true,
	}
	h := newEnvironment(t)
	handlers := h.env.Handlers()
	checked := 0
	for _, file := range files {
		raw, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		var f struct {
			Steps []struct {
				Given   string          `json:"given"`
				As      string          `json:"as"`
				Op      string          `json:"op"`
				Payload json.RawMessage `json:"payload"`
				Request *struct {
					Path string         `json:"path"`
					Body map[string]any `json:"body"`
				} `json:"request"`
				Response *struct {
					Status int `json:"status"`
				} `json:"response"`
			} `json:"steps"`
		}
		if err := json.Unmarshal(raw, &f); err != nil {
			t.Fatalf("%s: %v", file, err)
		}
		ops := map[string]string{}
		for _, step := range f.Steps {
			if step.Given == "op_enqueued" {
				ops[step.As] = step.Op
				handler, ok := handlers[step.Op]
				if !ok {
					continue
				}
				// Each payload runs against an empty daemon: what matters is that it
				// gets past the payload's checks.
				r := handler(context.Background(), step.Payload)
				if r.Error != nil && r.Error.Class == ClassInvalidPayload {
					t.Errorf("%s: the %s payload %s is refused: %s", filepath.Base(file), step.Op, step.Payload, r.Error.Message)
				}
				checked++
			}
			// A result of an op the runner implements that the gateway accepts: its
			// class must be one the runner reports.
			if step.Request != nil && step.Response != nil && step.Response.Status == 200 && resultOf(step.Request.Path, ops, handlers) {
				if e, ok := step.Request.Body["error"].(map[string]any); ok {
					if class, _ := e["class"].(string); !classes[class] {
						t.Errorf("%s: the runner never reports the class %q", filepath.Base(file), class)
					}
				}
			}
		}
	}
	if checked == 0 {
		t.Fatal("no payload was checked")
	}
}

var resultPath = regexp.MustCompile(`^/runner/v1/ops/\{\{([a-z0-9_.]+)\.id\}\}/result$`)

// resultOf says whether a request path posts the result of an op the runner
// implements.
func resultOf(path string, ops map[string]string, handlers map[string]Handler) bool {
	m := resultPath.FindStringSubmatch(path)
	if m == nil {
		return false
	}
	_, ok := handlers[ops[m[1]]]
	return ok || ops[m[1]] == "session.start" || ops[m[1]] == "session.stop"
}
