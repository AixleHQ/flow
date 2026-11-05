package protocol

import (
	"errors"
	"net/http"
)

// Action is what a runner does about a failed request, per the table "What a runner
// does on each refusal" of PROTOCOL.md §3.
type Action int

const (
	// ActionBackoff: keep everything, back off with jitter and retry. `runners_disabled`,
	// `429`, a 5xx and a network error.
	ActionBackoff Action = iota + 1
	// ActionRefresh: an access endpoint said `invalid_token`. Refresh once and retry
	// with the new access token.
	ActionRefresh
	// ActionReregister: the credentials are dead. Stop and ask for re-registration.
	ActionReregister
	// ActionReuseDetected: someone else held the refresh token. Delete the stored
	// credentials and stop.
	ActionReuseDetected
	// ActionRevoked: the runner was revoked or deleted. Stop.
	ActionRevoked
	// ActionUpdate: the gateway does not speak this runner's protocol or version.
	// Stop and report that aixle-runner must be updated.
	ActionUpdate
	// ActionBug: the runner sent something the gateway cannot take (`invalid_request`,
	// `invalid_result`, a body that is not JSON, a 413). Report it and do not resend
	// the same request.
	ActionBug
	// ActionDrop: a result for an op that is not this machine's (`404 not_found`).
	// Drop the result.
	ActionDrop
	// ActionNewRegistrationToken: register said `invalid_token`. The registration
	// token is unknown, used or expired; the operator needs a new one.
	ActionNewRegistrationToken
	// ActionFixConfiguration: register refused the body (`invalid_registration`,
	// `ephemeral_not_supported`). The token is not spent, so configure can be run
	// again once the input is fixed.
	ActionFixConfiguration
)

func (a Action) String() string {
	switch a {
	case ActionBackoff:
		return "backoff"
	case ActionRefresh:
		return "refresh"
	case ActionReregister:
		return "reregister"
	case ActionReuseDetected:
		return "reuse_detected"
	case ActionRevoked:
		return "revoked"
	case ActionUpdate:
		return "update"
	case ActionBug:
		return "bug"
	case ActionDrop:
		return "drop"
	case ActionNewRegistrationToken:
		return "new_registration_token"
	case ActionFixConfiguration:
		return "fix_configuration"
	}
	return "unknown"
}

// Classify maps a failed call to its action. A nil error has no action.
func Classify(err error) Action {
	var netErr *NetworkError
	if errors.As(err, &netErr) {
		return ActionBackoff
	}
	r, ok := AsRefusal(err)
	if !ok {
		// Not an answer of the gateway at all, e.g. a cancelled context.
		return ActionBackoff
	}

	switch r.Code {
	case "unsupported_protocol", "invalid_runner_version":
		return ActionUpdate
	case "invalid_token":
		switch r.Endpoint {
		case EndpointRegister:
			return ActionNewRegistrationToken
		case EndpointToken:
			return ActionReregister
		default:
			return ActionRefresh
		}
	case "credential_reuse_detected":
		return ActionReuseDetected
	case "runner_revoked":
		return ActionRevoked
	case "runners_disabled":
		return ActionBackoff
	case "not_found":
		if r.Endpoint == EndpointResult {
			return ActionDrop
		}
		return ActionBug
	case "invalid_registration", "ephemeral_not_supported":
		return ActionFixConfiguration
	case "invalid_request", "invalid_result":
		return ActionBug
	}

	switch {
	case r.Status == http.StatusTooManyRequests:
		return ActionBackoff
	case r.Status >= 500:
		// The gateway or a proxy in front of it failed; nothing in the request is wrong.
		return ActionBackoff
	}
	// 413, a 400 without the JSON shape, and any other 4xx this version does not know.
	return ActionBug
}
