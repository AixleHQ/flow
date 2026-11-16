# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §5.2: the states of a machine. Every
# change of `state` goes through one of these events, and the event records the
# reason, as RunnerStateMachine does with `status_reason`. The locks, the
# re-read under the lock and the enqueueing of operations stay in the services
# (Runners::Machines, Runners::Registration): fire an event on a row they hold
# locked, never from a callback.
#
#   registered ── mark_failed ──────────▶ failed   (a reset after a session failed, a reused
#      ▲                                    │        refresh token, `runners.max_consecutive_failures`)
#      │                          begin_return_to_service
#      │                                    ▼
#      └──────── finish_reset ───────── resetting ── mark_failed ──▶ failed (the reset failed)
#
#   unregister: registered | resetting | failed | gone ──▶ gone
module RunnerEnvironmentStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    # whiny_persistence: a state that fails to save raises instead of returning
    # false unnoticed. A machine left `resetting` or `registered` by a lost
    # write would take sessions it must not take.
    aasm column: :state, whiny_persistence: true do
      state :registered, initial: true
      state :resetting
      state :failed
      state :gone

      # Out of rotation, held by no session, with the reason for people in
      # `state_reason`. A late failure of a machine that is already `failed`
      # replaces its reason; one that is `gone` stays gone.
      event :mark_failed do
        transitions from: %i[registered resetting failed], to: :failed, after: :record_failure
      end

      # Return to service: the machine takes no session while its `env.reset` runs.
      event :begin_return_to_service do
        transitions from: :failed, to: :resetting, after: :clear_hold_and_reason
      end

      # The `env.reset` of a Return to service succeeded: free again, with a
      # clean streak.
      event :finish_reset do
        transitions from: :resetting, to: :registered, after: :clear_failure_record
      end

      # `aixle-runner unregister`: the machine leaves for good. Idempotent.
      event :unregister do
        transitions from: %i[registered resetting failed gone], to: :gone, after: -> { self.current_session_id = nil }
      end
    end
  end

  private

  def record_failure(reason = nil)
    self.current_session_id = nil
    self.state_reason = reason.to_s.truncate(255)
  end

  def clear_hold_and_reason(*)
    self.current_session_id = nil
    self.state_reason = nil
  end

  def clear_failure_record(*)
    self.state_reason = nil
    self.consecutive_failures = 0
  end
end
