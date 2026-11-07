package docker

import (
	"bytes"
	"context"
	"encoding/base64"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// put puts a file into a fake container, as the agent would have written it.
func (h *harness) put(c *fakeContainer, path string, f *fakeFile) {
	h.engine.mu.Lock()
	defer h.engine.mu.Unlock()
	c.Files[path] = f
}

func (h *harness) session() *fakeContainer {
	h.t.Helper()
	h.start(h.env, nil)
	return h.only()
}

func TestExecRunsWithItsUserEnvCwdAndStdin(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.engine.run = func(x *fakeExec, stdin []byte) fakeRun {
		return fakeRun{Stdout: append([]byte("read: "), stdin...), Stderr: []byte("warn\n"), Code: 3}
	}
	stdin := "secret input"
	r := h.run(h.env.Exec, map[string]any{
		"cmd": []string{"cat"}, "env": map[string]string{"B": "2", "A": "1"}, "cwd": "/workspace/repo", "user": "agent", "stdin": stdin,
	})
	if r.Status != protocol.StatusOK || r.ExitCode == nil || *r.ExitCode != 3 || *r.Stdout != "read: secret input" || *r.Stderr != "warn\n" {
		t.Fatalf("%#v", r)
	}
	if r.Data["stdout_truncated"] != false || r.Data["stderr_truncated"] != false {
		t.Fatalf("data %#v", r.Data)
	}
	var x *fakeExec
	for _, e := range h.engine.execs {
		x = e
	}
	req := x.Request
	if x.Container != c.ID || req.User != "agent" || req.WorkingDir != "/workspace/repo" || !reflect.DeepEqual(req.Env, []string{"A=1", "B=2"}) ||
		!reflect.DeepEqual(req.Cmd, []string{"cat"}) || !req.AttachStdin || req.Tty {
		t.Fatalf("exec %#v", req)
	}
}

func TestExecWithoutStdinDoesNotAttachIt(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	r := h.run(h.env.Exec, map[string]any{"cmd": []string{"true"}})
	if r.Status != protocol.StatusOK || *r.ExitCode != 0 || *r.Stdout != "ok\n" {
		t.Fatalf("%#v", r)
	}
	for _, x := range h.engine.execs {
		if x.Request.AttachStdin {
			t.Fatal("stdin was attached")
		}
	}
}

func TestExecCapsEachStreamAndMarksIt(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	// A multi-byte rune straddles the cap on stdout.
	big := append(bytes.Repeat([]byte("a"), OutputCap-1), []byte("é and more")...)
	h.engine.run = func(*fakeExec, []byte) fakeRun {
		return fakeRun{Stdout: big, Stderr: bytes.Repeat([]byte("e"), OutputCap)}
	}
	r := h.run(h.env.Exec, map[string]any{"cmd": []string{"yes"}})
	if r.Status != protocol.StatusOK || len(*r.Stdout) != OutputCap-1 || len(*r.Stderr) != OutputCap {
		t.Fatalf("stdout %d bytes, stderr %d bytes, %v", len(*r.Stdout), len(*r.Stderr), r.Status)
	}
	if r.Data["stdout_truncated"] != true || r.Data["stderr_truncated"] != false {
		t.Fatalf("data %#v", r.Data)
	}
}

func TestExecTimeoutEndsTheCommand(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	h.engine.run = func(x *fakeExec, _ []byte) fakeRun {
		// coreutils `timeout` ends the command after its timeout, with 124.
		if x.Request.Cmd[0] == "timeout" {
			return fakeRun{Delay: time.Second, Code: 124, Stdout: []byte("partial\n")}
		}
		return fakeRun{}
	}
	started := time.Now()
	r := h.run(h.env.Exec, map[string]any{"cmd": []string{"sleep", "600"}, "timeout": 1})
	if r.Status != protocol.StatusError || r.Error.Class != ClassExecTimeout || r.ExitCode == nil || *r.ExitCode != 124 || *r.Stdout != "partial\n" {
		t.Fatalf("%#v %v", r, r.Error)
	}
	if time.Since(started) > 10*time.Second {
		t.Fatal("the timeout did not end the op")
	}
	for _, x := range h.engine.execs {
		if want := []string{"timeout", "-k", "5", "1", "sleep", "600"}; !reflect.DeepEqual(x.Request.Cmd, want) {
			t.Fatalf("cmd %v", x.Request.Cmd)
		}
	}
	// A command that exits 124 on its own, before its timeout, did not time out.
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Code: 124} }
	r = h.run(h.env.Exec, map[string]any{"cmd": []string{"false"}, "timeout": 30})
	if r.Status != protocol.StatusOK || *r.ExitCode != 124 {
		t.Fatalf("%#v", r)
	}
}

func TestAnExecWithoutATimeoutEndsAtTheOpsDeadline(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	h.engine.run = func(x *fakeExec, _ []byte) fakeRun {
		if x.Request.Cmd[0] == "timeout" {
			return fakeRun{Delay: 1100 * time.Millisecond, Code: 124}
		}
		return fakeRun{}
	}
	ctx := protocol.WithOpDeadline(sessionCtx(sessionID), time.Now().Add(time.Second))
	r := h.env.Exec(ctx, mustJSON(t, map[string]any{"cmd": []string{"sleep", "infinity"}}))
	if r.Status != protocol.StatusError || r.Error.Class != ClassExecTimeout || !strings.Contains(r.Error.Message, "deadline_at") {
		t.Fatalf("%#v %v", r, r.Error)
	}
	for _, x := range h.engine.execs {
		if want := []string{"timeout", "-k", "5", "1", "sleep", "infinity"}; !reflect.DeepEqual(x.Request.Cmd, want) {
			t.Fatalf("cmd %v", x.Request.Cmd)
		}
	}
	// An explicit timeout is kept, whatever the deadline.
	h.engine.mu.Lock()
	h.engine.execs = map[string]*fakeExec{}
	h.engine.mu.Unlock()
	ctx = protocol.WithOpDeadline(sessionCtx(sessionID), time.Now().Add(time.Hour))
	if r := h.env.Exec(ctx, mustJSON(t, map[string]any{"cmd": []string{"true"}, "timeout": 30})); r.Status != protocol.StatusOK {
		t.Fatalf("%#v", r)
	}
	for _, x := range h.engine.execs {
		if want := []string{"timeout", "-k", "5", "30", "true"}; !reflect.DeepEqual(x.Request.Cmd, want) {
			t.Fatalf("cmd %v", x.Request.Cmd)
		}
	}
}

func TestExecRefusesInvalidPayloads(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	for _, p := range []map[string]any{
		{},
		{"cmd": []string{}},
		{"cmd": "ls"},
		{"cmd": []string{"ls"}, "timeout": -1},
		{"cmd": []string{"ls"}, "cwd": "relative"},
		{"cmd": []string{"ls"}, "env": map[string]string{"": "x"}},
	} {
		if r := h.run(h.env.Exec, p); r.Error == nil || r.Error.Class != ClassInvalidPayload {
			t.Errorf("%v: %#v", p, r)
		}
	}
	if len(h.engine.execs) != 0 {
		t.Fatal("an invalid exec ran")
	}
}

func TestWriteFileWithItsModeAndOwnerThenReadItBack(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	content := []byte("{\"token\": \"x\"}\n")
	r := h.run(h.env.WriteFile, map[string]any{
		"path": "/home/agent/.claude/.credentials.json", "content": base64.StdEncoding.EncodeToString(content),
		"mode": 0o600, "uid": 1000, "gid": 1001,
	})
	if r.Status != protocol.StatusOK {
		t.Fatalf("%#v %v", r, r.Error)
	}
	f := c.Files["/home/agent/.claude/.credentials.json"]
	if f == nil || !bytes.Equal(f.Content, content) || f.Mode != 0o600 || f.UID != 1000 || f.GID != 1001 {
		t.Fatalf("file %#v", f)
	}

	r = h.run(h.env.ReadFile, map[string]any{"path": "/home/agent/.claude/.credentials.json"})
	if r.Status != protocol.StatusOK || r.Data["content"] != base64.StdEncoding.EncodeToString(content) || r.Data["size"] != len(content) {
		t.Fatalf("%#v", r)
	}
}

func TestWriteFileDefaultsToRoot0644(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.run(h.env.WriteFile, map[string]any{"path": "/tmp/x", "content": ""})
	if f := c.Files["/tmp/x"]; f == nil || f.Mode != 0o644 || f.UID != 0 || f.GID != 0 {
		t.Fatalf("file %#v", f)
	}
	for _, p := range []map[string]any{
		{"path": "relative", "content": ""},
		{"path": "/x", "content": "not base64!"},
		{"path": "/x", "content": "", "mode": 0o10000},
	} {
		if r := h.run(h.env.WriteFile, p); r.Error == nil || r.Error.Class != ClassInvalidPayload {
			t.Errorf("%v: %#v", p, r)
		}
	}
}

func TestWriteFileWithoutContentTruncatesNothing(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.put(c, "/home/agent/.claude/.credentials.json", &fakeFile{Content: []byte("secret"), Mode: 0o600})
	for _, p := range []map[string]any{
		{"path": "/home/agent/.claude/.credentials.json"},
		{"path": "/home/agent/.claude/.credentials.json", "content": nil},
	} {
		r := h.run(h.env.WriteFile, p)
		if r.Error == nil || r.Error.Class != ClassInvalidPayload || !strings.Contains(r.Error.Message, "`content` is required") {
			t.Errorf("%v: %#v", p, r)
		}
		r = h.run(h.env.Batch, map[string]any{"ops": []map[string]any{{"op": "write_file", "payload": p}}})
		if r.Error == nil || r.Error.Class != ClassInvalidPayload || !strings.Contains(r.Error.Message, "ops[0]: `content` is required") {
			t.Errorf("batch of %v: %#v", p, r)
		}
	}
	if f := c.Files["/home/agent/.claude/.credentials.json"]; string(f.Content) != "secret" {
		t.Fatalf("the file was changed to %q", f.Content)
	}
	// An empty string still writes an empty file.
	if r := h.run(h.env.WriteFile, map[string]any{"path": "/empty", "content": ""}); r.Status != protocol.StatusOK || c.Files["/empty"] == nil || len(c.Files["/empty"].Content) != 0 {
		t.Fatalf("%#v", r)
	}
}

func TestReadFileRefusesWhatItCannotReturn(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.put(c, "/big", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap+1), Mode: 0o644})
	h.put(c, "/limit", &fakeFile{Content: bytes.Repeat([]byte("x"), OutputCap), Mode: 0o644})
	h.put(c, "/dir", &fakeFile{Dir: true, Mode: 0o755})
	h.put(c, "/link", &fakeFile{Link: "/limit"})
	for path, class := range map[string]string{"/big": ClassFileTooLarge, "/dir": ClassNotAFile, "/missing": ClassFileNotFound} {
		if r := h.run(h.env.ReadFile, map[string]any{"path": path}); r.Error == nil || r.Error.Class != class {
			t.Errorf("%s: %#v", path, r)
		}
	}
	for _, path := range []string{"/limit", "/link"} {
		r := h.run(h.env.ReadFile, map[string]any{"path": path})
		if r.Status != protocol.StatusOK || r.Data["size"] != OutputCap {
			t.Errorf("%s: %#v", path, r.Status)
		}
	}
}

func TestBatchStopsAtTheFirstFailure(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.engine.run = func(x *fakeExec, _ []byte) fakeRun {
		if x.Request.Cmd[0] == "false" {
			return fakeRun{Code: 1, Stderr: []byte("no\n")}
		}
		return fakeRun{Stdout: []byte("yes\n")}
	}
	r := h.run(h.env.Batch, map[string]any{"ops": []map[string]any{
		{"op": "write_file", "payload": map[string]any{"path": "/a", "content": base64.StdEncoding.EncodeToString([]byte("1"))}},
		{"op": "exec", "payload": map[string]any{"cmd": []string{"true"}}},
		{"op": "exec", "payload": map[string]any{"cmd": []string{"false"}}},
		{"op": "write_file", "payload": map[string]any{"path": "/b", "content": ""}},
	}})
	if r.Status != protocol.StatusError || r.Error.Class != ClassBatchStepFailed || !strings.Contains(r.Error.Message, "ops[2] (exec)") {
		t.Fatalf("%#v %v", r, r.Error)
	}
	results := r.Data["results"].([]protocol.Result)
	if len(results) != 3 || *results[2].ExitCode != 1 || *results[1].Stdout != "yes\n" {
		t.Fatalf("results %#v", results)
	}
	if c.Files["/a"] == nil || c.Files["/b"] != nil {
		t.Fatal("the batch did not stop at the failure")
	}

	r = h.run(h.env.Batch, map[string]any{"ops": []map[string]any{
		{"op": "write_file", "payload": map[string]any{"path": "/c", "content": ""}},
		{"op": "read_file", "payload": map[string]any{"path": "/c"}},
	}})
	if r.Status != protocol.StatusOK || len(r.Data["results"].([]protocol.Result)) != 2 {
		t.Fatalf("%#v", r)
	}
}

func TestAnInvalidBatchRunsNothing(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	for _, p := range []map[string]any{
		{"ops": []map[string]any{}},
		{"ops": []map[string]any{{"op": "write_file", "payload": map[string]any{"path": "/a", "content": ""}}, {"op": "status"}}},
		{"ops": []map[string]any{{"op": "write_file", "payload": map[string]any{"path": "/a", "content": ""}}, {"op": "batch", "payload": map[string]any{}}}},
		{"ops": []map[string]any{{"op": "write_file", "payload": map[string]any{"path": "/a", "content": ""}}, {"op": "exec", "payload": map[string]any{}}}},
	} {
		if r := h.run(h.env.Batch, p); r.Error == nil || r.Error.Class != ClassInvalidPayload {
			t.Errorf("%v: %#v", p, r)
		}
	}
	if len(c.Files) != 0 {
		t.Fatal("a step of an invalid batch ran")
	}
}

func TestStatusReadsTheContainerState(t *testing.T) {
	h := newEnvironment(t)
	if r := h.run(h.env.Status, map[string]any{}); r.Status != protocol.StatusOK || r.Data["state"] != StateMissing {
		t.Fatalf("%#v", r)
	}
	c := h.session()
	if r := h.run(h.env.Status, map[string]any{}); r.Data["state"] != StateRunning || r.Data["container_id"] != c.ID {
		t.Fatalf("%#v", r)
	}
	h.engine.mu.Lock()
	c.State.Running, c.State.Status = false, "created"
	h.engine.mu.Unlock()
	if r := h.run(h.env.Status, map[string]any{}); r.Data["state"] != StateStarting {
		t.Fatalf("%#v", r)
	}
	h.engine.mu.Lock()
	h.engine.exit(c, 2)
	c.State.OOMKilled = true
	h.engine.mu.Unlock()
	r := h.run(h.env.Status, map[string]any{})
	if r.Data["state"] != StateTerminated || r.Data["exit_code"] != 2 || r.Data["oom_killed"] != true {
		t.Fatalf("%#v", r)
	}
}

func TestLogsReturnsTheTailOfTheTerminalOutput(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	r := h.run(h.env.Logs, map[string]any{})
	if r.Status != protocol.StatusOK || r.Data["tail"] != "" || r.Data["size"] != int64(0) || r.Data["truncated"] != false {
		t.Fatalf("before any output: %#v", r)
	}
	h.put(c, TerminalOutputPath, &fakeFile{Content: []byte("line 1\nline 2\nlast line\n"), Mode: 0o644})
	r = h.run(h.env.Logs, map[string]any{"bytes": 10})
	if r.Data["tail"] != "last line\n" || r.Data["size"] != int64(24) || r.Data["truncated"] != true {
		t.Fatalf("%#v", r)
	}
	r = h.run(h.env.Logs, map[string]any{})
	if r.Data["tail"] != "line 1\nline 2\nlast line\n" || r.Data["truncated"] != false {
		t.Fatalf("%#v", r)
	}
	if r := h.run(h.env.Logs, map[string]any{"bytes": OutputCap + 1}); r.Error == nil || r.Error.Class != ClassInvalidPayload {
		t.Fatalf("%#v", r)
	}
}

func TestReadTailKeepsTheEnd(t *testing.T) {
	data := bytes.Repeat([]byte("0123456789"), 50_000)
	got, err := readTail(bytes.NewReader(data), 1234)
	if err != nil || !bytes.Equal(got, data[len(data)-1234:]) {
		t.Fatalf("%d bytes, %v", len(got), err)
	}
}

func TestSessionOpsWithoutASessionContainer(t *testing.T) {
	h := newEnvironment(t)
	// Another environment's container is not this environment's session container.
	h.start(h.another("aixle-r7-99999999"), nil)
	ops := map[string]any{
		"exec":       map[string]any{"cmd": []string{"true"}},
		"write_file": map[string]any{"path": "/x", "content": ""},
		"read_file":  map[string]any{"path": "/x"},
		"logs":       map[string]any{},
		"batch":      map[string]any{"ops": []map[string]any{{"op": "exec", "payload": map[string]any{"cmd": []string{"true"}}}}},
	}
	handlers := h.env.Handlers()
	for op, p := range ops {
		r := h.run(handlers[op], p)
		if r.Status != protocol.StatusError {
			t.Errorf("%s: %#v", op, r)
			continue
		}
		class := r.Error.Class
		if op == "batch" {
			class = r.Data["results"].([]protocol.Result)[0].Error.Class
		}
		if class != ClassNoSessionContainer {
			t.Errorf("%s: %#v", op, r.Error)
		}
	}
	for _, x := range h.engine.execs {
		t.Fatalf("an exec ran in %s", x.Container)
	}
}

func TestExecNeedsARunningContainerButFilesDoNot(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.put(c, TerminalOutputPath, &fakeFile{Content: []byte("bye\n"), Mode: 0o644})
	h.engine.mu.Lock()
	h.engine.exit(c, 0)
	h.engine.mu.Unlock()
	if r := h.run(h.env.Exec, map[string]any{"cmd": []string{"true"}}); r.Error == nil || r.Error.Class != ClassNoSessionContainer {
		t.Fatalf("%#v", r)
	}
	if r := h.run(h.env.Logs, map[string]any{}); r.Status != protocol.StatusOK || r.Data["tail"] != "bye\n" {
		t.Fatalf("%#v", r)
	}
}

func TestAStoppingRunnerCutsAnExecShort(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	block := make(chan struct{})
	h.engine.run = func(*fakeExec, []byte) fakeRun { return fakeRun{Block: block} }
	ctx, cancel := context.WithCancel(sessionCtx(sessionID))
	done := make(chan protocol.Result)
	go func() { done <- h.env.Exec(ctx, mustJSON(t, map[string]any{"cmd": []string{"sleep", "30"}})) }()
	time.Sleep(100 * time.Millisecond)
	cancel()
	select {
	case r := <-done:
		if r.Status != protocol.StatusError {
			t.Fatalf("%#v", r)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the exec did not return when the runner stopped")
	}
	close(block)
}

func TestASessionOpOfAnotherSessionIsRefused(t *testing.T) {
	h := newEnvironment(t)
	c := h.session()
	h.put(c, "/tmp/notes", &fakeFile{Content: []byte("mine"), Mode: 0o644})
	ops := map[string]any{
		"exec":       map[string]any{"cmd": []string{"true"}},
		"write_file": map[string]any{"path": "/tmp/notes", "content": base64.StdEncoding.EncodeToString([]byte("theirs"))},
		"read_file":  map[string]any{"path": "/tmp/notes"},
		"logs":       map[string]any{},
		"status":     map[string]any{},
		"batch":      map[string]any{"ops": []map[string]any{{"op": "exec", "payload": map[string]any{"cmd": []string{"true"}}}}},
	}
	handlers := h.env.Handlers()
	for op, p := range ops {
		r := h.runAs(124, handlers[op], p)
		if r.Status != protocol.StatusError {
			t.Errorf("%s: %#v", op, r)
			continue
		}
		class, message := r.Error.Class, r.Error.Message
		if op == "batch" {
			step := r.Data["results"].([]protocol.Result)[0]
			class, message = step.Error.Class, step.Error.Message
		}
		if class != ClassSessionMismatch || !strings.Contains(message, "124") {
			t.Errorf("%s: %#v", op, r.Error)
		}
	}
	for _, x := range h.engine.execs {
		t.Fatalf("an exec ran in %s", x.Container)
	}
	if got := string(c.Files["/tmp/notes"].Content); got != "mine" {
		t.Fatalf("the other session's write reached the container: %q", got)
	}
	// container.stop acts on its own session's name, so the running container
	// of another session is left alone.
	if r := h.runAs(124, handlers["container.stop"], map[string]any{}); r.Status != protocol.StatusOK || r.Data["removed"] != false {
		t.Fatalf("%#v", r)
	}
	if after := h.only(); after.ID != c.ID || !after.State.Running {
		t.Fatal("the container was stopped or removed")
	}
}

func TestASessionOpWithoutASessionIsRefused(t *testing.T) {
	h := newEnvironment(t)
	h.session()
	handlers := h.env.Handlers()
	for _, op := range []string{"container.start", "container.stop", "exec", "write_file", "read_file", "batch", "status", "logs"} {
		r := handlers[op](context.Background(), mustJSON(t, map[string]any{}))
		if r.Status != protocol.StatusError || r.Error.Class != ClassSessionRequired {
			t.Errorf("%s: %#v", op, r)
		}
	}
	if len(h.engine.execs) != 0 || len(h.engine.creates) != 1 {
		t.Fatalf("%d execs, %d creates", len(h.engine.execs), len(h.engine.creates))
	}
	if !h.only().State.Running {
		t.Fatal("the session container was stopped")
	}
}
