package docker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strconv"
	"time"

	cerrdefs "github.com/containerd/errdefs"
	"github.com/moby/moby/api/types/container"
	"github.com/moby/moby/client"

	"github.com/aixlehq/aixle-runner/internal/protocol"
)

// The labels the host runner puts on what it creates (DESIGN.md §6.8, §7.2).
// Scrub and reset select by them, never by enumeration.
const (
	LabelEnvironment = "aixle.com/environment"
	LabelSession     = "aixle.com/session"
	// LabelRole marks the short-lived container of `env.scrub` that empties the
	// outputs, so that it is never taken for a session container.
	LabelRole = "aixle.com/role"
)

// Result error classes of the agent-container ops (runner/protocol/PROTOCOL.md §6).
const (
	ClassNoSessionContainer = "no_session_container"
	// ClassSessionMismatch: the environment's session container is labelled with
	// another session than the op's envelope names, so the op does not touch it.
	ClassSessionMismatch = "session_mismatch"
	// ClassSessionRequired: a session op whose envelope names no session.
	ClassSessionRequired = "session_required"
)

// OutputCap is the most an op returns of one stream or one file: 1 MiB
// (runner/protocol/PROTOCOL.md §6). The runner reads no platform settings, so the
// cap is a constant of the protocol.
const OutputCap = 1 << 20

// Handler runs one op, with the `session_id` of its envelope, nil for an
// environment op. It always returns a result: a failure is an `error` result.
type Handler = func(ctx context.Context, sessionID *int64, payload json.RawMessage) protocol.Result

// SessionHandler runs a session op for the envelope's session, which sessionOp
// has checked.
type SessionHandler = func(ctx context.Context, sessionID int64, payload json.RawMessage) protocol.Result

// EnvironmentHandler runs an environment op, which names no session.
type EnvironmentHandler = func(ctx context.Context, payload json.RawMessage) protocol.Result

// Environment is the host runner's view of one environment on the machine's
// Docker daemon: its session container, its volumes, and the ops on them.
type Environment struct {
	API API
	// Key is the environment's key, from the registration. It is opaque: the
	// runner uses it in names and labels and never parses it.
	Key string
	// StateDir is the runner's state directory. No bind mount may expose it.
	StateDir string
	// Now is replaced in tests.
	Now func() time.Time
	// RemoveTimeout bounds the removal after a failed or cut-short
	// `container.start`. Zero is 30 seconds.
	RemoveTimeout time.Duration
	// Logger receives what an op cannot put in its answer. Nil is slog.Default().
	Logger *slog.Logger
}

func (e *Environment) now() time.Time {
	if e.Now == nil {
		return time.Now()
	}
	return e.Now()
}

func (e *Environment) logger() *slog.Logger {
	if e.Logger == nil {
		return slog.Default()
	}
	return e.Logger
}

// ContainerName is the session container's name, `aixle-<key>-<session id>`.
func (e *Environment) ContainerName(sessionID int64) string {
	return "aixle-" + e.Key + "-" + strconv.FormatInt(sessionID, 10)
}

// WorkspaceVolume is the environment's workspace volume, `aixle-ws-<key>`.
func (e *Environment) WorkspaceVolume() string { return "aixle-ws-" + e.Key }

// CacheVolume is a cache volume of the environment, `aixle-cache-<key>-<name>`.
func (e *Environment) CacheVolume(name string) string { return "aixle-cache-" + e.Key + "-" + name }

func (e *Environment) cacheVolumePrefix() string { return "aixle-cache-" + e.Key + "-" }

func (e *Environment) environmentFilter() client.Filters {
	return make(client.Filters).Add("label", LabelEnvironment+"="+e.Key)
}

// containers lists every container of the environment, running or not.
func (e *Environment) containers(ctx context.Context) ([]container.Summary, error) {
	res, err := e.API.ContainerList(ctx, client.ContainerListOptions{All: true, Filters: e.environmentFilter()})
	if err != nil {
		return nil, err
	}
	// The daemon filters, and this checks again: what is removed must carry the
	// environment's label.
	var out []container.Summary
	for _, c := range res.Items {
		if c.Labels[LabelEnvironment] == e.Key {
			out = append(out, c)
		}
	}
	return out, nil
}

// sessionContainer finds the environment's session container by its labels, as a
// restarted host runner does: the container belongs to the daemon, not to the
// runner, so nothing about it is kept in the runner's memory or state. It answers
// nil when the environment has none. `container.start` refuses to start a second
// one, so there is at most one.
func (e *Environment) sessionContainer(ctx context.Context) (*container.InspectResponse, error) {
	filters := e.environmentFilter().Add("label", LabelSession)
	res, err := e.API.ContainerList(ctx, client.ContainerListOptions{All: true, Filters: filters})
	if err != nil {
		return nil, err
	}
	for _, c := range res.Items {
		if c.Labels[LabelEnvironment] != e.Key || c.Labels[LabelSession] == "" {
			continue
		}
		inspected, err := e.API.ContainerInspect(ctx, c.ID, client.ContainerInspectOptions{})
		if cerrdefs.IsNotFound(err) {
			// Removed between the list and the inspect.
			continue
		}
		if err != nil {
			return nil, err
		}
		return &inspected.Container, nil
	}
	return nil, nil
}

// requireSession is the session container a session op acts on. `running` asks
// for a running one, as `exec` needs; the archive API of the file ops works on a
// container that has exited too. Without one, the op answers
// `no_session_container`. The container must carry sessionID, the session of the
// op's envelope: one labelled with another session answers `session_mismatch`, so
// a late op of a finished session never reaches the next session's container.
func (e *Environment) requireSession(ctx context.Context, sessionID int64, running bool) (*container.InspectResponse, *protocol.Result) {
	c, err := e.sessionContainer(ctx)
	if err != nil {
		r := protocol.ErrorResult(ClassDockerError, "finding the session container failed: "+err.Error())
		return nil, &r
	}
	if c == nil {
		r := protocol.ErrorResult(ClassNoSessionContainer, fmt.Sprintf("environment %s has no session container: run container.start first", e.Key))
		return nil, &r
	}
	if r := checkSession(c, sessionID); r != nil {
		return nil, r
	}
	if running && (c.State == nil || !c.State.Running) {
		status := "unknown"
		if c.State != nil {
			status = string(c.State.Status)
		}
		r := protocol.ErrorResult(ClassNoSessionContainer, fmt.Sprintf("the session container %s is not running (%s)", trimName(c.Name), status))
		return nil, &r
	}
	return c, nil
}

// checkSession refuses a container that is labelled with another session than id.
func checkSession(c *container.InspectResponse, id int64) *protocol.Result {
	var label string
	if c.Config != nil {
		label = c.Config.Labels[LabelSession]
	}
	if label != strconv.FormatInt(id, 10) {
		r := protocol.ErrorResult(ClassSessionMismatch, fmt.Sprintf(
			"the session container %s carries %s=%s, not the op's session %d; the op was not run", trimName(c.Name), LabelSession, label, id))
		return &r
	}
	return nil
}

// sessionOp reads the envelope's `session_id` once and passes it on. A session op
// whose envelope names no session, or not a positive id, is refused before its
// payload is read.
func sessionOp(h SessionHandler) Handler {
	return func(ctx context.Context, sessionID *int64, payload json.RawMessage) protocol.Result {
		if sessionID == nil || *sessionID <= 0 {
			return protocol.ErrorResult(ClassSessionRequired, "a session op needs the session_id of its envelope, a positive integer; the op was not run")
		}
		return h(ctx, *sessionID, payload)
	}
}

// environmentOp runs an environment op. It takes no session, and the platform
// sends it none (PROTOCOL.md §5.4).
func environmentOp(h EnvironmentHandler) Handler {
	return func(ctx context.Context, _ *int64, payload json.RawMessage) protocol.Result {
		return h(ctx, payload)
	}
}

func trimName(name string) string {
	if len(name) > 0 && name[0] == '/' {
		return name[1:]
	}
	return name
}

// Handlers are the ops the host runner runs against this environment. Of the op
// names of protocol 1, `session.start` and `session.stop` stay reserved and have
// no handler, so the loop answers them `unsupported_op` (PROTOCOL.md §6). Every
// session op needs the envelope's `session_id`; the environment ops take none.
func (e *Environment) Handlers() map[string]Handler {
	return map[string]Handler{
		"container.start": sessionOp(e.ContainerStart),
		"container.stop":  sessionOp(e.ContainerStop),
		"exec":            sessionOp(e.Exec),
		"write_file":      sessionOp(e.WriteFile),
		"read_file":       sessionOp(e.ReadFile),
		"batch":           sessionOp(e.Batch),
		"status":          sessionOp(e.Status),
		"logs":            sessionOp(e.Logs),
		"env.scrub":       environmentOp(e.Scrub),
		"env.reset":       environmentOp(e.Reset),
	}
}
