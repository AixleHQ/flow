# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §5.2: the states of a machine. Every
# change of `state` goes through one of these events, and the event records the
# reason, as RunnerStateMachine does with `status_reason`. The locks, the
# re-read under the lock and the enqueueing of operations stay in the services
# (Runners::Machines, Runners::Registration): fire an event on a row they hold
# locked, never from a callback.
#
#   registered ── mark_failed ──▶ failed   (a reset after a session failed, a check-in that reports
#                                           missing prerequisites, a reused refresh token)
#
#   unregister: registered | failed | gone ──▶ gone
#
# `failed` is final: the machine leaves it only by a Revoke (`gone`), and is registered
# again with Add machine. A session's outcome never fails a machine.
module RunnerEnvironmentStateMachine
  extend ActiveSupport::Concern

  # `state_reason` of a `gone` machine: it unregistered itself, or was revoked from the runner page.
  UNREGISTERED = "unregistered"
  REVOKED = "revoked"

  included do
    include AASM

    # whiny_persistence: a state that fails to save raises instead of returning
    # false unnoticed. A machine left `registered` by a lost
    # write would take sessions it must not take.
    aasm column: :state, whiny_persistence: true do
      state :registered, initial: true
      state :failed
      state :gone

      # Out of rotation, held by no session, with the reason for people in
      # `state_reason`. A late failure of a machine that is already `failed`
      # replaces its reason; one that is `gone` stays gone.
      event :mark_failed do
        transitions from: %i[registered failed], to: :failed, after: :record_failure
      end

      # `aixle-runner unregister`, or a Revoke on the runner page (`unregister(REVOKED)`):
      # the machine leaves for good, and `state_reason` says which of the two. Idempotent:
      # a machine already `gone` keeps the reason it left with.
      event :unregister do
        transitions from: %i[registered failed gone], to: :gone, after: :record_departure
      end
    end
  end

  private

  def record_departure(reason = UNREGISTERED)
    self.current_session_id = nil
    self.state_reason = reason if aasm.from_state != :gone
  end

  def record_failure(reason = nil)
    self.current_session_id = nil
    self.state_reason = reason.to_s.truncate(255)
  end
end
