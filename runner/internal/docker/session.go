package docker

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/pkg/stdcopy"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// Result error classes of the session ops (runner/protocol/PROTOCOL.md §6.3).
const (
	ClassExecFailed      = "exec_failed"
	ClassExecTimeout     = "exec_timeout"
	ClassWriteFailed     = "write_failed"
	ClassFileNotFound    = "file_not_found"
	ClassNotAFile        = "not_a_file"
	ClassFileTooLarge    = "file_too_large"
	ClassBatchStepFailed = "batch_step_failed"
)

// TerminalOutputPath is the file the agent image's entrypoint pipes the agent's
// tmux pane into (DESIGN.md §6.5). `logs` returns its tail.
const TerminalOutputPath = "/tmp/terminal_output.log"

// The exit codes of coreutils `timeout` for a command it ended: 124 after
// SIGTERM, 137 when it needed SIGKILL.
const (
	timeoutExitTerm = 124
	timeoutExitKill = 137
)

// timeoutKillAfter is how long `timeout` waits after SIGTERM before SIGKILL, and
// timeoutGrace how much longer the runner waits for the exec to end after that,
// before it stops reading it.
const (
	timeoutKillAfter = 5
	timeoutGrace     = 15 * time.Second
)

// cappedBuffer keeps the first OutputCap bytes written to it and counts the rest.
type cappedBuffer struct {
	buf       bytes.Buffer
	limit     int
	truncated bool
}

func newCapped() *cappedBuffer { return &cappedBuffer{limit: OutputCap} }

func (c *cappedBuffer) Write(p []byte) (int, error) {
	room := c.limit - c.buf.Len()
	switch {
	case len(p) <= room:
		c.buf.Write(p)
	default:
		if room > 0 {
			c.buf.Write(p[:room])
		}
		c.truncated = true
	}
	// The rest is read and dropped, so the command never blocks on a full pipe.
	return len(p), nil
}

// String is the kept output as a JSON string can carry it: a rune cut by the cap
// is dropped, and bytes that are not UTF-8 become U+FFFD.
func (c *cappedBuffer) String() string {
	b := c.buf.Bytes()
	if c.truncated {
		b = trimPartialRuneEnd(b)
	}
	return strings.ToValidUTF8(string(b), "\uFFFD")
}

func trimPartialRuneEnd(b []byte) []byte {
	for i := len(b) - 1; i >= 0 && i >= len(b)-utf8.UTFMax; i-- {
		if utf8.RuneStart(b[i]) {
			if !utf8.FullRune(b[i:]) {
				return b[:i]
			}
			break
		}
	}
	return b
}

func trimPartialRuneStart(b []byte) []byte {
	for i := 0; i < len(b) && i < utf8.UTFMax; i++ {
		if utf8.RuneStart(b[i]) {
			return b[i:]
		}
	}
	return b
}

// sessionGone says whether a daemon error means the session container is gone
// or stopped, so the op answers `no_session_container`.
func sessionGone(err error) bool {
	return cerrdefs.IsNotFound(err) || cerrdefs.IsConflict(err)
}

func noSession(err error) protocol.Result {
	return protocol.ErrorResult(ClassNoSessionContainer, "the session container is gone or not running: "+err.Error())
}

// ExecPayload is the payload of `exec`.
type ExecPayload struct {
	Cmd     []string          `json:"cmd"`
	Env     map[string]string `json:"env"`
	Cwd     string            `json:"cwd"`
	User    string            `json:"user"`
	Timeout int64             `json:"timeout"`
	Stdin   *string           `json:"stdin"`
}

func (p ExecPayload) validate() *protocol.Result {
	if len(p.Cmd) == 0 || p.Cmd[0] == "" {
		return invalid("`cmd` must be a non-empty array of strings")
	}
	if p.Timeout < 0 {
		return invalid("`timeout` must not be negative, got %d", p.Timeout)
	}
	if p.Cwd != "" && !strings.HasPrefix(p.Cwd, "/") {
		return invalid("`cwd` must be an absolute path, got %q", p.Cwd)
	}
	for name := range p.Env {
		if name == "" || strings.ContainsAny(name, "=\x00") {
			return invalid("`env` has an invalid variable name %q", name)
		}
	}
	return nil
}

// Exec is `exec`: it runs a command in the running session container through the
// daemon's exec API, as `ContainerRuntime::DockerRuntime#exec` does. The result
// carries the exit code, whatever it is, and each stream capped at OutputCap.
func (e *Environment) Exec(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p ExecPayload
	if r := decodePayload(raw, &p, "an exec payload"); r != nil {
		return *r
	}
	if r := p.validate(); r != nil {
		return *r
	}
	return e.exec(ctx, sessionID, p)
}

func (e *Environment) exec(ctx context.Context, sessionID int64, p ExecPayload) protocol.Result {
	c, r := e.requireSession(ctx, sessionID, true)
	if r != nil {
		return *r
	}

	cmd := p.Cmd
	// An exec is bounded by the op's `deadline_at`: after it, nobody waits for
	// the result, and the serial ops loop must move on. A command without a
	// timeout gets the time left until the deadline, and a longer timeout is cut
	// to it.
	timeout, byDeadline := p.Timeout, false
	if deadline, ok := protocol.OpDeadline(ctx); ok {
		left := max(int64(math.Ceil(time.Until(deadline).Seconds())), 1)
		if timeout == 0 || timeout > left {
			timeout, byDeadline = left, true
		}
	}
	if timeout > 0 {
		// The daemon cannot end an exec, so the command runs under coreutils
		// `timeout`, which the agent images have. It signals the command's whole
		// process group.
		cmd = append([]string{"timeout", "-k", strconv.Itoa(timeoutKillAfter), strconv.FormatInt(timeout, 10)}, cmd...)
	}
	env := make([]string, 0, len(p.Env))
	for name, value := range p.Env {
		env = append(env, name+"="+value)
	}
	sort.Strings(env)

	created, err := e.API.ExecCreate(ctx, c.ID, client.ExecCreateOptions{
		User: p.User, Env: env, WorkingDir: p.Cwd, Cmd: cmd,
		AttachStdin: p.Stdin != nil, AttachStdout: true, AttachStderr: true,
	})
	if sessionGone(err) {
		return noSession(err)
	}
	if err != nil {
		return protocol.ErrorResult(ClassExecFailed, "creating the exec failed: "+err.Error())
	}

	runCtx := ctx
	if timeout > 0 {
		var cancel context.CancelFunc
		runCtx, cancel = context.WithTimeout(ctx, time.Duration(timeout)*time.Second+time.Duration(timeoutKillAfter)*time.Second+timeoutGrace)
		defer cancel()
	}
	started := time.Now()
	attached, err := e.API.ExecAttach(runCtx, created.ID, client.ExecAttachOptions{})
	if err != nil {
		if ctx.Err() != nil {
			return protocol.ErrorResult(ClassExecFailed, "the runner stopped: "+ctx.Err().Error())
		}
		return protocol.ErrorResult(ClassExecFailed, "starting the exec failed: "+err.Error())
	}
	defer attached.Close()
	// Closing the connection is what ends the read when the runner stops or the
	// guard runs out. The command itself keeps running in the container.
	stop := context.AfterFunc(runCtx, attached.Close)
	defer stop()

	if p.Stdin != nil {
		go func() {
			_, _ = io.Copy(attached.Conn, strings.NewReader(*p.Stdin))
			_ = attached.CloseWrite()
		}()
	}
	stdout, stderr := newCapped(), newCapped()
	_, copyErr := stdcopy.StdCopy(stdout, stderr, attached.Reader)
	elapsed := time.Since(started)
	if ctx.Err() != nil {
		return protocol.ErrorResult(ClassExecFailed, "the runner stopped while the command ran: "+ctx.Err().Error())
	}
	guardFired := runCtx.Err() != nil

	result := protocol.Result{
		Status: protocol.StatusOK,
		Data: map[string]any{
			"stdout_truncated": stdout.truncated,
			"stderr_truncated": stderr.truncated,
		},
	}
	out, errOut := stdout.String(), stderr.String()
	result.Stdout, result.Stderr = &out, &errOut

	code, running, err := e.execExit(ctx, created.ID)
	switch {
	case err != nil && !guardFired:
		return protocol.ErrorResult(ClassExecFailed, "reading the exit code failed: "+err.Error())
	case !running && err == nil:
		result.ExitCode = &code
	}
	if copyErr != nil && !guardFired && running {
		return protocol.ErrorResult(ClassExecFailed, "reading the output failed: "+copyErr.Error())
	}

	timedOut := guardFired ||
		(timeout > 0 && result.ExitCode != nil && (code == timeoutExitTerm || code == timeoutExitKill) &&
			elapsed >= time.Duration(timeout)*time.Second)
	if timedOut {
		message := fmt.Sprintf("the command did not finish within its timeout of %d s and was ended", timeout)
		switch {
		case byDeadline && p.Timeout == 0:
			message = fmt.Sprintf("the command has no timeout and was still running at the op's deadline_at, %d s after it started; it was ended", timeout)
		case byDeadline:
			message = fmt.Sprintf("the command's timeout of %d s runs past the op's deadline_at; it was still running at the deadline, %d s after it started, and was ended", p.Timeout, timeout)
		}
		result.Status = protocol.StatusError
		result.Error = &protocol.ResultError{Class: ClassExecTimeout, Message: message}
	}
	return result
}

// execExit reads an exec's exit code. The output stream can end a moment before
// the daemon records the exit, so it asks a few times.
func (e *Environment) execExit(ctx context.Context, id string) (code int, running bool, err error) {
	for i := 0; i < 50; i++ {
		inspected, err := e.API.ExecInspect(ctx, id, client.ExecInspectOptions{})
		if err != nil {
			return 0, false, err
		}
		if !inspected.Running {
			return inspected.ExitCode, false, nil
		}
		select {
		case <-ctx.Done():
			return 0, true, ctx.Err()
		case <-time.After(20 * time.Millisecond):
		}
	}
	return 0, true, nil
}

// WriteFilePayload is the payload of `write_file`.
type WriteFilePayload struct {
	Path string `json:"path"`
	// Content is required: absent and `null` are refused, so that a payload that
	// lost its content never truncates a file. `""` writes an empty file.
	Content *string `json:"content"`
	Mode    *int64  `json:"mode"`
	UID     *int    `json:"uid"`
	GID     *int    `json:"gid"`
}

func (p WriteFilePayload) validate() ([]byte, *protocol.Result) {
	if r := validTarget("path", p.Path); r != nil {
		return nil, r
	}
	if p.Content == nil {
		return nil, invalid("`content` is required: a base64 string, `\"\"` for an empty file")
	}
	content, err := base64.StdEncoding.DecodeString(*p.Content)
	if err != nil {
		return nil, invalid("`content` is not base64: %v", err)
	}
	if p.Mode != nil && (*p.Mode < 0 || *p.Mode > 0o7777) {
		return nil, invalid("`mode` must be a permission between 0 and 0o7777 (4095), got %d", *p.Mode)
	}
	if (p.UID != nil && *p.UID < 0) || (p.GID != nil && *p.GID < 0) {
		return nil, invalid("`uid` and `gid` must not be negative")
	}
	return content, nil
}

// WriteFile is `write_file`: it writes one file into the session container through
// the daemon's archive API (what `docker cp` does), with its mode and owner, as
// `DockerRuntime#write_file` does. Missing parent directories are created.
func (e *Environment) WriteFile(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p WriteFilePayload
	if r := decodePayload(raw, &p, "a write_file payload"); r != nil {
		return *r
	}
	content, r := p.validate()
	if r != nil {
		return *r
	}
	return e.writeFile(ctx, sessionID, p, content)
}

func (e *Environment) writeFile(ctx context.Context, sessionID int64, p WriteFilePayload, content []byte) protocol.Result {
	c, r := e.requireSession(ctx, sessionID, false)
	if r != nil {
		return *r
	}
	mode, uid, gid := int64(0o644), 0, 0
	if p.Mode != nil {
		mode = *p.Mode
	}
	if p.UID != nil {
		uid = *p.UID
	}
	if p.GID != nil {
		gid = *p.GID
	}

	var archive bytes.Buffer
	tw := tar.NewWriter(&archive)
	header := &tar.Header{
		Typeflag: tar.TypeReg, Name: strings.TrimPrefix(p.Path, "/"),
		Mode: mode, Uid: uid, Gid: gid, Size: int64(len(content)), ModTime: e.now(),
	}
	if err := tw.WriteHeader(header); err != nil {
		return protocol.ErrorResult(ClassWriteFailed, "building the archive failed: "+err.Error())
	}
	if _, err := tw.Write(content); err != nil {
		return protocol.ErrorResult(ClassWriteFailed, "building the archive failed: "+err.Error())
	}
	if err := tw.Close(); err != nil {
		return protocol.ErrorResult(ClassWriteFailed, "building the archive failed: "+err.Error())
	}

	_, err := e.API.CopyToContainer(ctx, c.ID, client.CopyToContainerOptions{DestinationPath: "/", Content: &archive})
	if cerrdefs.IsNotFound(err) {
		if _, gone := e.API.ContainerInspect(ctx, c.ID, client.ContainerInspectOptions{}); cerrdefs.IsNotFound(gone) {
			return noSession(err)
		}
	}
	if err != nil {
		return protocol.ErrorResult(ClassWriteFailed, fmt.Sprintf("writing %s failed: %v", p.Path, err))
	}
	return protocol.Result{Status: protocol.StatusOK}
}

// ReadFilePayload is the payload of `read_file`.
type ReadFilePayload struct {
	Path string `json:"path"`
}

// ReadFile is `read_file`: it reads one file of the session container through the
// archive API, up to OutputCap. A larger file is refused (PROTOCOL.md §6.3).
func (e *Environment) ReadFile(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p ReadFilePayload
	if r := decodePayload(raw, &p, "{path}"); r != nil {
		return *r
	}
	if r := validTarget("path", p.Path); r != nil {
		return *r
	}
	return e.readFile(ctx, sessionID, p)
}

func (e *Environment) readFile(ctx context.Context, sessionID int64, p ReadFilePayload) protocol.Result {
	c, r := e.requireSession(ctx, sessionID, false)
	if r != nil {
		return *r
	}
	content, r := e.copyOut(ctx, c.ID, p.Path, func(stat container.PathStat) *protocol.Result {
		if stat.Size > OutputCap {
			r := protocol.ErrorResult(ClassFileTooLarge, fmt.Sprintf("%s is %d bytes, over the %d-byte limit of read_file", p.Path, stat.Size, OutputCap))
			return &r
		}
		return nil
	}, func(tr io.Reader) ([]byte, error) {
		return io.ReadAll(io.LimitReader(tr, OutputCap+1))
	})
	if r != nil {
		return *r
	}
	if len(content) > OutputCap {
		return protocol.ErrorResult(ClassFileTooLarge, fmt.Sprintf("%s is over the %d-byte limit of read_file", p.Path, OutputCap))
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{
		"content": base64.StdEncoding.EncodeToString(content),
		"size":    len(content),
	}}
}

// copyOut reads one regular file of a container through the archive API. A
// symlink is followed once, to the target the daemon resolved, since the archive
// of a link holds the link and not the file. check sees the file's stat before
// any content is read.
func (e *Environment) copyOut(ctx context.Context, id, path string, check func(container.PathStat) *protocol.Result, read func(io.Reader) ([]byte, error)) ([]byte, *protocol.Result) {
	fail := func(class, format string, args ...any) ([]byte, *protocol.Result) {
		r := protocol.ErrorResult(class, fmt.Sprintf(format, args...))
		return nil, &r
	}
	for follows := 0; ; follows++ {
		res, err := e.API.CopyFromContainer(ctx, id, client.CopyFromContainerOptions{SourcePath: path})
		if cerrdefs.IsNotFound(err) {
			if _, gone := e.API.ContainerInspect(ctx, id, client.ContainerInspectOptions{}); cerrdefs.IsNotFound(gone) {
				r := noSession(err)
				return nil, &r
			}
			return fail(ClassFileNotFound, "%s does not exist in the session container", path)
		}
		if err != nil {
			return fail(ClassDockerError, "reading %s failed: %v", path, err)
		}
		stat := res.Stat
		if stat.Mode&os.ModeSymlink != 0 && stat.LinkTarget != "" && follows == 0 {
			res.Content.Close()
			path = stat.LinkTarget
			continue
		}
		defer res.Content.Close()
		if !stat.Mode.IsRegular() {
			return fail(ClassNotAFile, "%s is not a regular file (%s)", path, stat.Mode.Type())
		}
		if r := check(stat); r != nil {
			return nil, r
		}
		tr := tar.NewReader(res.Content)
		for {
			header, err := tr.Next()
			if errors.Is(err, io.EOF) {
				return fail(ClassDockerError, "the daemon's archive of %s holds no file", path)
			}
			if err != nil {
				return fail(ClassDockerError, "reading the archive of %s failed: %v", path, err)
			}
			if header.Typeflag != tar.TypeReg {
				continue
			}
			content, err := read(tr)
			if err != nil {
				return fail(ClassDockerError, "reading %s failed: %v", path, err)
			}
			return content, nil
		}
	}
}

// BatchPayload is the payload of `batch`.
type BatchPayload struct {
	Ops []BatchStep `json:"ops"`
}

// BatchStep is one op of a batch.
type BatchStep struct {
	Op      string          `json:"op"`
	Payload json.RawMessage `json:"payload"`
}

// The ops a batch may hold.
var batchOps = []string{"exec", "write_file", "read_file"}

// Batch is `batch`: it runs its ops in order until the first that fails, which is
// one with an `error` result or an exec with a non-zero exit code. Every step is
// checked before the first runs, so an invalid batch runs nothing.
func (e *Environment) Batch(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p BatchPayload
	if r := decodePayload(raw, &p, "{ops}"); r != nil {
		return *r
	}
	if len(p.Ops) == 0 {
		return *invalid("`ops` must be a non-empty array")
	}
	steps := make([]func(context.Context) protocol.Result, len(p.Ops))
	for i, step := range p.Ops {
		run, r := e.batchStep(sessionID, step)
		if r != nil {
			r.Error.Message = fmt.Sprintf("ops[%d]: %s", i, r.Error.Message)
			return *r
		}
		steps[i] = run
	}

	results := make([]protocol.Result, 0, len(steps))
	for i, run := range steps {
		r := run(ctx)
		results = append(results, r)
		if ctx.Err() != nil {
			return protocol.ErrorResult(ClassBatchStepFailed, "the runner stopped during the batch: "+ctx.Err().Error())
		}
		if failed, why := stepFailed(r); failed {
			return protocol.Result{
				Status: protocol.StatusError,
				Data:   map[string]any{"results": results},
				Error: &protocol.ResultError{Class: ClassBatchStepFailed,
					Message: fmt.Sprintf("ops[%d] (%s) failed: %s; the %d ops after it did not run", i, p.Ops[i].Op, why, len(steps)-i-1)},
			}
		}
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"results": results}}
}

func stepFailed(r protocol.Result) (bool, string) {
	if r.Status != protocol.StatusOK {
		if r.Error != nil {
			return true, r.Error.Class + ": " + r.Error.Message
		}
		return true, r.Status
	}
	if r.ExitCode != nil && *r.ExitCode != 0 {
		return true, fmt.Sprintf("exit code %d", *r.ExitCode)
	}
	return false, ""
}

func (e *Environment) batchStep(sessionID int64, step BatchStep) (func(context.Context) protocol.Result, *protocol.Result) {
	raw := step.Payload
	if len(raw) == 0 || string(raw) == "null" {
		raw = json.RawMessage(`{}`)
	}
	switch step.Op {
	case "exec":
		var p ExecPayload
		if r := decodePayload(raw, &p, "an exec payload"); r != nil {
			return nil, r
		}
		if r := p.validate(); r != nil {
			return nil, r
		}
		return func(ctx context.Context) protocol.Result { return e.exec(ctx, sessionID, p) }, nil
	case "write_file":
		var p WriteFilePayload
		if r := decodePayload(raw, &p, "a write_file payload"); r != nil {
			return nil, r
		}
		content, r := p.validate()
		if r != nil {
			return nil, r
		}
		return func(ctx context.Context) protocol.Result { return e.writeFile(ctx, sessionID, p, content) }, nil
	case "read_file":
		var p ReadFilePayload
		if r := decodePayload(raw, &p, "{path}"); r != nil {
			return nil, r
		}
		if r := validTarget("path", p.Path); r != nil {
			return nil, r
		}
		return func(ctx context.Context) protocol.Result { return e.readFile(ctx, sessionID, p) }, nil
	}
	return nil, invalid("`op` must be one of %s, got %q", strings.Join(batchOps, ", "), step.Op)
}

// The states `status` answers.
const (
	StateRunning    = "running"
	StateStarting   = "starting"
	StateTerminated = "terminated"
	StateMissing    = "missing"
)

// Status is `status`: the session container's state, read the way
// `DockerRuntime#container_status` reads it. A paused container counts as
// running: it has not exited. A terminated one also reports its exit code. A
// container of another session is refused with `session_mismatch`.
func (e *Environment) Status(ctx context.Context, sessionID int64, _ json.RawMessage) protocol.Result {
	c, err := e.sessionContainer(ctx)
	if err != nil {
		return protocol.ErrorResult(ClassDockerError, "finding the session container failed: "+err.Error())
	}
	if c == nil {
		return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{"state": StateMissing}}
	}
	if r := checkSession(c, sessionID); r != nil {
		return *r
	}
	data := map[string]any{"container_id": c.ID, "name": trimName(c.Name)}
	state := c.State
	if state == nil {
		state = &container.State{}
	}
	switch {
	case state.Running:
		data["state"] = StateRunning
	case state.Status == container.StateCreated || state.Status == container.StateRestarting:
		data["state"] = StateStarting
	case state.Status == container.StateExited || state.Status == container.StateDead || state.Status == container.StateRemoving:
		data["state"] = StateTerminated
		data["exit_code"] = state.ExitCode
		data["oom_killed"] = state.OOMKilled
	default:
		return protocol.ErrorResult(ClassDockerError, fmt.Sprintf("the session container is in a state the runner does not know: %q", state.Status))
	}
	return protocol.Result{Status: protocol.StatusOK, Data: data}
}

// LogsPayload is the payload of `logs`.
type LogsPayload struct {
	// Bytes is how much of the end of the file to return. Zero means OutputCap.
	Bytes int64 `json:"bytes"`
}

// Logs is `logs`: the tail of the terminal-output file the entrypoint writes,
// /tmp/terminal_output.log (DESIGN.md §6.5). Before the agent has written
// anything the file does not exist, and the tail is empty.
func (e *Environment) Logs(ctx context.Context, sessionID int64, raw json.RawMessage) protocol.Result {
	var p LogsPayload
	if r := decodePayload(raw, &p, "{bytes}"); r != nil {
		return *r
	}
	if p.Bytes < 0 || p.Bytes > OutputCap {
		return *invalid("`bytes` must be between 1 and %d, got %d", OutputCap, p.Bytes)
	}
	limit := p.Bytes
	if limit == 0 {
		limit = OutputCap
	}
	c, r := e.requireSession(ctx, sessionID, false)
	if r != nil {
		return *r
	}
	var size int64
	tail, r := e.copyOut(ctx, c.ID, TerminalOutputPath, func(stat container.PathStat) *protocol.Result {
		size = stat.Size
		return nil
	}, func(tr io.Reader) ([]byte, error) {
		return readTail(tr, limit)
	})
	if r != nil {
		if r.Error.Class != ClassFileNotFound {
			return *r
		}
		tail, size = nil, 0
	}
	cut := int64(len(tail)) < size
	if cut {
		tail = trimPartialRuneStart(tail)
	}
	return protocol.Result{Status: protocol.StatusOK, Data: map[string]any{
		"tail":      strings.ToValidUTF8(string(tail), "\uFFFD"),
		"size":      size,
		"truncated": cut,
	}}
}

// readTail reads r to its end and keeps its last limit bytes.
func readTail(r io.Reader, limit int64) ([]byte, error) {
	keep := make([]byte, 0, 2*limit)
	chunk := make([]byte, 64<<10)
	for {
		n, err := r.Read(chunk)
		keep = append(keep, chunk[:n]...)
		if int64(len(keep)) > 2*limit {
			keep = append(keep[:0], keep[int64(len(keep))-limit:]...)
		}
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, err
		}
	}
	if int64(len(keep)) > limit {
		keep = keep[int64(len(keep))-limit:]
	}
	return keep, nil
}
