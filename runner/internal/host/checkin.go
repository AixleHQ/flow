package host

import (
	"context"
	"log/slog"
	"time"

	"github.com/aixlehq/aixle-runner/internal/backoff"
	"github.com/aixlehq/aixle-runner/internal/protocol"
	"github.com/aixlehq/aixle-runner/internal/tokens"
)

// CheckInGateway is the part of the protocol client the check-in uses.
type CheckInGateway interface {
	CheckIn(ctx context.Context, accessToken string, req protocol.CheckInRequest) (protocol.CheckIn, error)
}

// DefaultCheckInAttempts is how many times a check-in is tried before the runner
// logs it and starts its ops loop without one.
const DefaultCheckInAttempts = 5

// Checker is the host runner's check-in after a start (PROTOCOL.md §5.9): the
// machine's os, arch and facts, and, in the request's X-Aixle-Runner-Version, the
// version it runs now, which a machine that updated itself has moved on from the
// one it registered with.
type Checker struct {
	Gateway CheckInGateway
	Tokens  *tokens.Source
	Logger  *slog.Logger
	Backoff *backoff.Backoff
	// MaxAttempts bounds the tries of a check-in that fails in a way the runner
	// can wait out. Zero is DefaultCheckInAttempts.
	MaxAttempts int
	// Sleep is replaced in tests.
	Sleep func(ctx context.Context, d time.Duration) error
}

// CheckIn reports the machine, retrying with backoff a failure the runner can
// wait out, at most MaxAttempts times: then it is logged and the runner goes on
// without a check-in, since the ops do not depend on it (a failing check-in
// route must not stop a machine that can work). A refusal that ends the runner's work
// (the credentials, a revoked runner, a version below the platform's minimum) is
// returned as a *tokens.StopError. A refusal of the report itself is a bug in
// this runner: it is logged and the runner goes on without a check-in, since the
// ops do not depend on it. The boolean says whether the platform recorded the
// report.
func (c *Checker) CheckIn(ctx context.Context, report protocol.CheckInRequest) (protocol.CheckIn, bool, error) {
	logger, retry, sleep := c.Logger, c.Backoff, c.Sleep
	if logger == nil {
		logger = slog.Default()
	}
	if retry == nil {
		retry = backoff.Default()
	}
	if sleep == nil {
		sleep = backoff.Sleep
	}
	attempts := c.MaxAttempts
	if attempts <= 0 {
		attempts = DefaultCheckInAttempts
	}
	for attempt := 1; ; attempt++ {
		var answer protocol.CheckIn
		err := c.Tokens.Do(ctx, func(access string) error {
			var err error
			answer, err = c.Gateway.CheckIn(ctx, access, report)
			return err
		})
		if err == nil {
			retry.Reset()
			logger.Info("checked in", "upload_max_bytes", answer.Config.UploadMaxBytes, "update_offered", answer.Update != nil)
			return answer, true, nil
		}
		if ctx.Err() != nil {
			return protocol.CheckIn{}, false, ctx.Err()
		}
		if _, stop := tokens.AsStop(err); stop {
			return protocol.CheckIn{}, false, err
		}
		if protocol.Classify(err) == protocol.ActionBug {
			logger.Error("the platform refused the check-in, which is a bug in aixle-runner; going on without it", "error", err)
			return protocol.CheckIn{}, false, nil
		}
		if attempt >= attempts {
			logger.Error("checking in failed; going on without a check-in, the next start will try again", "attempts", attempt, "error", err)
			return protocol.CheckIn{}, false, nil
		}
		delay := retry.Next()
		logger.Warn("checking in failed, retrying", "error", err, "retry_in", delay.Round(time.Millisecond))
		if err := sleep(ctx, delay); err != nil {
			return protocol.CheckIn{}, false, err
		}
	}
}
