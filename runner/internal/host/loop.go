// Package host is `aixle-runner --mode host`: the ops loop of a machine's host
// runner (DESIGN.md §6.4, §6.7, §6.8). It long-polls the machine's ops one poll at
// a time, runs each op at most once through the journal, and posts each result
// until the gateway accepts it. An answer without ops may offer an update, which
// the loop hands to its Updater (DESIGN.md §14.4).
package host

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/journal"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
	"github.com/aixlehq/aixle-runner/internal/version"
)

// Result error classes the loop itself reports. They are stable: the platform
// reads them.
const (
	// ClassUnsupportedOp: the op is valid in the protocol, but this runner version
	// does not implement it. The platform can be newer than the runner.
	ClassUnsupportedOp = "unsupported_op"
	// ClassInterrupted: the runner stopped while the op ran. At-most-once means it
	// is not run again.
	ClassInterrupted = "interrupted"
	// ClassResultTooLarge: the op ran, but its encoded result is over the gateway's
	// body cap, so this small error is posted in its place (PROTOCOL.md §6).
	ClassResultTooLarge = "result_too_large"
)

// ResultLimit is the largest encoded result the loop posts: the gateway's body cap
// less a margin, so that a result near the cap is never refused with `413`.
const ResultLimit = protocol.MaxBodyBytes - 16<<10

// Handler runs one op, with the `session_id` of its envelope, nil for an
// environment op. It always returns a result: a failure is an `error` result.
type Handler func(ctx context.Context, sessionID *int64, payload json.RawMessage) protocol.Result

// Gateway is the part of the protocol client the loop uses.
type Gateway interface {
	PollOps(ctx context.Context, accessToken string, after int64, wait time.Duration) (protocol.Poll, error)
	PostResult(ctx context.Context, accessToken string, opID int64, result protocol.Result) (protocol.ResultState, error)
}

// Updater takes an update the platform offers (internal/update). It says whether
// it replaced the binary, after which the runner must restart on it.
type Updater interface {
	Apply(ctx context.Context, offer protocol.Update) bool
}

// ErrUpdated ends Run once the Updater has replaced the binary: the process exits,
// and its supervisor (systemd) starts the new binary.
var ErrUpdated = errors.New("aixle-runner was updated and restarts on the new version")

// Loop is the host runner's ops loop.
type Loop struct {
	Gateway  Gateway
	Tokens   *tokens.Source
	Journal  *journal.Journal
	Handlers map[string]Handler
	// Updater, when set, is offered the update of an answer without ops. The loop
	// runs one thing at a time, so no op is running then.
	Updater Updater
	Logger  *slog.Logger
	Backoff *backoff.Backoff
	// Wait is the long-poll's wait. Zero means protocol.MaxWait.
	Wait time.Duration
	// Now and Sleep are replaced in tests.
	Now   func() time.Time
	Sleep func(ctx context.Context, d time.Duration) error
}

func (l *Loop) defaults() {
	if l.Logger == nil {
		l.Logger = slog.Default()
	}
	if l.Backoff == nil {
		l.Backoff = backoff.Default()
	}
	if l.Wait == 0 {
		l.Wait = protocol.MaxWait
	}
	if l.Now == nil {
		l.Now = time.Now
	}
	if l.Sleep == nil {
		l.Sleep = backoff.Sleep
	}
}

// Run polls until ctx is done, which returns nil, or until a refusal stops the
// runner, which returns a *tokens.StopError, or until the journal cannot be
// written, or until an update replaced the binary, which returns ErrUpdated.
func (l *Loop) Run(ctx context.Context) error {
	l.defaults()
	l.Logger.Info("polling for ops", "after", l.Journal.After())
	for {
		if ctx.Err() != nil {
			return nil
		}
		answer, err := l.poll(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		ops := answer.Ops
		if len(ops) == 0 && answer.Update != nil && l.Updater != nil && ctx.Err() == nil {
			if l.Updater.Apply(ctx, *answer.Update) {
				return ErrUpdated
			}
		}
		for _, op := range ops {
			if err := l.handle(ctx, op); err != nil {
				if ctx.Err() != nil {
					return nil
				}
				return err
			}
		}
	}
}

// poll makes one long-poll, retrying with backoff until it gets an answer. It is
// the only request in flight while it waits: the loop never overlaps two polls.
func (l *Loop) poll(ctx context.Context) (protocol.Poll, error) {
	for {
		after := l.Journal.After()
		var answer protocol.Poll
		err := l.Tokens.Do(ctx, func(access string) error {
			var err error
			answer, err = l.Gateway.PollOps(ctx, access, after, l.Wait)
			return err
		})
		if err == nil {
			l.Backoff.Reset()
			ops := answer.Ops
			sort.Slice(ops, func(i, k int) bool { return ops[i].Sequence < ops[k].Sequence })
			return answer, nil
		}
		if ctx.Err() != nil {
			return protocol.Poll{}, ctx.Err()
		}
		if _, stop := tokens.AsStop(err); stop {
			return protocol.Poll{}, err
		}
		if protocol.Classify(err) == protocol.ActionBug {
			// The same poll would be refused again: nothing the loop can change.
			return protocol.Poll{}, fmt.Errorf("the gateway refused the long-poll, which is a bug in aixle-runner: %w", err)
		}
		if err := l.backoff(ctx, "polling for ops failed", err); err != nil {
			return protocol.Poll{}, err
		}
	}
}

func (l *Loop) handle(ctx context.Context, op protocol.Op) error {
	log := l.Logger.With("op_id", op.ID, "sequence", op.Sequence, "op", op.Op)
	result, err := l.resultFor(ctx, op, log)
	if err != nil {
		return err
	}
	if result == nil {
		// Settled before a restart; only `after` was not moved yet.
		return l.Journal.Acknowledge(op.ID)
	}
	if err := l.post(ctx, op, *result, log); err != nil {
		return err
	}
	return l.Journal.Acknowledge(op.ID)
}

// resultFor runs the op, or answers it from the journal. A nil result means the
// op is already settled.
func (l *Loop) resultFor(ctx context.Context, op protocol.Op, log *slog.Logger) (*protocol.Result, error) {
	if entry, seen := l.Journal.Lookup(op.ID); seen {
		switch {
		case entry.Accepted:
			return nil, nil
		case entry.Result != nil:
			log.Info("op redelivered, answering from the journal")
			return entry.Result, nil
		default:
			log.Warn("op was interrupted by a restart, not running it again")
			result := protocol.ErrorResult(ClassInterrupted, "aixle-runner stopped while this op ran; it is not run again")
			if err := l.Journal.Finish(op.ID, result); err != nil {
				return nil, err
			}
			return &result, nil
		}
	}

	if l.Now().After(op.DeadlineAt) {
		log.Warn("op received after its deadline, not running it", "deadline_at", op.DeadlineAt)
		result := protocol.Result{Status: protocol.StatusExpired}
		return &result, l.Journal.Record(op, result)
	}

	handler, ok := l.Handlers[op.Op]
	if !ok {
		log.Warn("op not implemented by this aixle-runner version")
		result := protocol.ErrorResult(ClassUnsupportedOp,
			fmt.Sprintf("aixle-runner %s does not implement the op %q", version.Version, op.Op))
		return &result, l.Journal.Record(op, result)
	}

	if err := l.Journal.Begin(op); err != nil {
		return nil, err
	}
	log.Info("running op")
	started := l.Now()
	result := handler(protocol.WithOpDeadline(ctx, op.DeadlineAt), op.SessionID, op.Payload)
	if ctx.Err() != nil {
		// The runner is stopping, so the handler's result says why it was cut short,
		// not how the op went. The entry stays begun: the next start answers
		// `interrupted` (PROTOCOL.md §6).
		log.Warn("the runner stopped while the op ran; its result is not journalled",
			"elapsed", l.Now().Sub(started).Round(time.Millisecond))
		return nil, ctx.Err()
	}
	log.Info("op finished", "status", result.Status, "elapsed", l.Now().Sub(started).Round(time.Millisecond))
	result = fitResult(op, result, log)
	if err := l.Journal.Finish(op.ID, result); err != nil {
		return nil, err
	}
	return &result, nil
}

// fitResult replaces a result whose encoded body is over ResultLimit with a
// `result_too_large` error. The gateway would refuse the body with `413`, which is
// not resent, and the op would never be answered.
func fitResult(op protocol.Op, result protocol.Result, log *slog.Logger) protocol.Result {
	encoded, err := json.Marshal(result)
	if err != nil || len(encoded) <= ResultLimit {
		// A result that cannot be encoded fails the same way in the client.
		return result
	}
	message := fmt.Sprintf("%s's result is %d bytes, over the gateway's %d-byte cap", op.Op, len(encoded), protocol.MaxBodyBytes)
	if op.Op == "batch" {
		var p struct {
			Ops []json.RawMessage `json:"ops"`
		}
		_ = json.Unmarshal(op.Payload, &p)
		ran := 0
		if steps, ok := result.Data["results"].([]protocol.Result); ok {
			ran = len(steps)
		}
		message += fmt.Sprintf("; the batch has %d steps, of which %d ran", len(p.Ops), ran)
	}
	log.Warn("the op's result is over the gateway's body cap, answering result_too_large instead",
		"bytes", len(encoded), "status", result.Status)
	return protocol.ErrorResult(ClassResultTooLarge, message)
}

// post sends the result until the gateway accepts it (§5.5: the first result wins,
// so a resend is safe), or until the gateway answers that it will never take it.
func (l *Loop) post(ctx context.Context, op protocol.Op, result protocol.Result, log *slog.Logger) error {
	for {
		var state protocol.ResultState
		err := l.Tokens.Do(ctx, func(access string) error {
			var err error
			state, err = l.Gateway.PostResult(ctx, access, op.ID, result)
			return err
		})
		if err == nil {
			l.Backoff.Reset()
			log.Info("result accepted", "state", state.State)
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if _, stop := tokens.AsStop(err); stop {
			return err
		}
		switch protocol.Classify(err) {
		case protocol.ActionDrop:
			log.Warn("the gateway does not know this op for this machine, dropping its result", "error", err)
			return nil
		case protocol.ActionBug:
			log.Error("the gateway refused the result, which is a bug in aixle-runner; not resending it", "error", err)
			return nil
		}
		if err := l.backoff(ctx, "posting the result failed", err); err != nil {
			return err
		}
	}
}

func (l *Loop) backoff(ctx context.Context, msg string, err error) error {
	delay := l.Backoff.Next()
	l.Logger.Warn(msg+", retrying", "error", err, "retry_in", delay.Round(time.Millisecond))
	if sleepErr := l.Sleep(ctx, delay); sleepErr != nil {
		return errors.Join(sleepErr, err)
	}
	return nil
}
