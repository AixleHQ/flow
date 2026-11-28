# frozen_string_literal: true

# docs/design/agent-runtimes/DESIGN.md §5.2 and runner-coder.md §6: the states
# of an environment. Every change of `state` goes through one of these events,
# and the event records the reason, as RunnerStateMachine does with
# `status_reason`. The locks, the re-read under the lock and the enqueueing of
# operations stay in the services (Runners::Allocator, Runners::Registration):
# fire an event on a row they hold locked, never from a callback.
#
# Two arms, chosen by `origin` and never mixed. A `manual` machine is created
# `registered`:
#
#   registered ── mark_failed ──▶ failed   (a reset after a session failed, a check-in that reports
#                                           missing prerequisites, a reused refresh token)
#   unregister: registered | failed | gone ──▶ gone
#
# An environment the platform creates (`origin: allocated`) is created
# `provisioning`, held by its session:
#
#   provisioning ─finish_build─▶ booting ─check_in─▶ idle      (idle + a hold = busy)
#   any state but gone ── mark_failed ──▶ failed ── begin_teardown ──▶ tearing_down ─finish_teardown─▶ gone
#   provisioning | booting | idle ── begin_teardown ──▶ tearing_down
#
# `failed` on a `manual` machine is final: it leaves only by a Revoke (`gone`) and
# is registered again with Add machine. On a provisioned environment it is not a
# resting state: it is torn down and replaced. A session's outcome never fails
# an environment.
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
      state :provisioning
      state :booting
      state :idle
      state :failed
      state :tearing_down
      state :gone

      # The machine the integration handed over is being installed on: its
      # build is done, and the runner has not checked in yet.
      event :finish_build do
        transitions from: :provisioning, to: :booting
      end

      # The first check-in after `register` (runner-coder.md §8.4). An environment
      # is never `idle` before its preflight is reported.
      event :check_in do
        transitions from: :booting, to: :idle
      end

      # The environment is deleted, and gone once that is done (`finish_teardown`).
      # It holds no session from here on.
      event :begin_teardown do
        transitions from: %i[provisioning booting idle failed], to: :tearing_down, after: :record_teardown
      end

      event :finish_teardown do
        transitions from: :tearing_down, to: :gone
      end

      # Out of rotation, held by no session, with the reason for people in
      # `state_reason`. A late failure of a machine that is already `failed`
      # replaces its reason; one that is `gone` stays gone.
      event :mark_failed do
        transitions from: %i[registered provisioning booting idle tearing_down failed], to: :failed,
                     after: :record_failure
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

  def record_teardown(reason = nil)
    self.current_session_id = nil
    self.state_reason = reason.to_s.truncate(255) if reason.present?
  end

  def record_failure(reason = nil)
    self.current_session_id = nil
    self.state_reason = reason.to_s.truncate(255)
  end
end
