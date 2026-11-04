// Package host is `aixle-runner --mode host`: the ops loop of a machine's host
// runner (DESIGN.md §6.4, §6.7, §6.8). It long-polls the machine's ops one poll at
// a time, runs each op at most once through the journal, and posts each result
// until the gateway accepts it.
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
)

// Handler runs one op. It always returns a result: a failure is an `error` result.
type Handler func(ctx context.Context, payload json.RawMessage) protocol.Result

// Gateway is the part of the protocol client the loop uses.
type Gateway interface {
	PollOps(ctx context.Context, accessToken string, after int64, wait time.Duration) ([]protocol.Op, error)
	PostResult(ctx context.Context, accessToken string, opID int64, result protocol.Result) (protocol.ResultState, error)
}

// Loop is the host runner's ops loop.
type Loop struct {
	Gateway  Gateway
	Tokens   *tokens.Source
	Journal  *journal.Journal
	Handlers map[string]Handler
	Logger   *slog.Logger
	Backoff  *backoff.Backoff
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
// runner, which returns a *tokens.StopError, or until the journal cannot be written.
func (l *Loop) Run(ctx context.Context) error {
	l.defaults()
	l.Logger.Info("polling for ops", "after", l.Journal.After())
	for {
		if ctx.Err() != nil {
			return nil
		}
		ops, err := l.poll(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
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
func (l *Loop) poll(ctx context.Context) ([]protocol.Op, error) {
	for {
		after := l.Journal.After()
		var ops []protocol.Op
		err := l.Tokens.Do(ctx, func(access string) error {
			var err error
			ops, err = l.Gateway.PollOps(ctx, access, after, l.Wait)
			return err
		})
		if err == nil {
			l.Backoff.Reset()
			sort.Slice(ops, func(i, k int) bool { return ops[i].Sequence < ops[k].Sequence })
			return ops, nil
		}
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		if _, stop := tokens.AsStop(err); stop {
			return nil, err
		}
		if protocol.Classify(err) == protocol.ActionBug {
			// The same poll would be refused again: nothing the loop can change.
			return nil, fmt.Errorf("the gateway refused the long-poll, which is a bug in aixle-runner: %w", err)
		}
		if err := l.backoff(ctx, "polling for ops failed", err); err != nil {
			return nil, err
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
	result := handler(ctx, op.Payload)
	if ctx.Err() != nil {
		// The runner is stopping, so the handler's result says why it was cut short,
		// not how the op went. The entry stays begun: the next start answers
		// `interrupted` (PROTOCOL.md §6).
		log.Warn("the runner stopped while the op ran; its result is not journalled",
			"elapsed", l.Now().Sub(started).Round(time.Millisecond))
		return nil, ctx.Err()
	}
	log.Info("op finished", "status", result.Status, "elapsed", l.Now().Sub(started).Round(time.Millisecond))
	if err := l.Journal.Finish(op.ID, result); err != nil {
		return nil, err
	}
	return &result, nil
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
