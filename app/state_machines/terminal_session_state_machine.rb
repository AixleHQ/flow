# frozen_string_literal: true

module TerminalSessionStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    # whiny_persistence: a state that fails to save raises instead of returning
    # false unnoticed.
    aasm column: :state, whiny_persistence: true do
      state :not_started, initial: true
      state :queued
      state :cancelled
      state :running
      state :ready
      state :finishing
      state :finished
      state :failed
      state :suspended
      state :restored

      event :start do
        transitions from: %i[not_started queued], to: :running, after: :on_started
      end

      event :enqueue do
        transitions from: :not_started, to: :queued, after: :on_queued
      end

      event :cancel do
        transitions from: %i[not_started queued running ready finishing], to: :cancelled, after: :on_cancelled
      end

      event :mark_ready do
        transitions from: %i[not_started running], to: :ready, after: :on_ready
      end

      event :start_finishing do
        transitions from: %i[not_started running ready], to: :finishing, after: :on_finishing
      end

      event :finish do
        transitions from: :finishing, to: :finished, after: :on_finished
      end

      event :fail do
        transitions from: %i[not_started queued running ready finishing], to: :failed, after: :on_failed
      end

      # The moves Sessions::Lifecycle.finalize records once the container's work is
      # over (`finish`, `fail` and `cancel` above cover the rest). They are events of
      # their own, not wider `from` lists on `finish` and `fail`, because `may_finish?`
      # and `may_fail?` guard live code: failing a suspended session must stay a no-op.
      #
      # The agent simply exited, with no finish requested. `queued` is a session whose
      # launch ended before the first phase started it.
      event :finish_without_request do
        transitions from: %i[not_started queued running ready], to: :finished, after: :on_ended_by_cleanup
      end

      # Output collection failed after the session had already finished.
      event :fail_after_finish do
        transitions from: :finished, to: :failed, after: :on_ended_by_cleanup
      end

      # Sessions::Suspension. A checkpoint was taken, so the session ends suspended;
      # the moves after it are the three below.
      event :mark_suspended do
        transitions from: %i[running ready finishing], to: :suspended, after: :on_ended_by_cleanup
      end

      event :mark_restored do
        transitions from: :suspended, to: :restored
      end

      event :expire_suspension do
        transitions from: :suspended, to: :finished
      end

      # A suspended workflow step whose restore window closed.
      event :expire_suspended_step do
        transitions from: :suspended, to: :failed
      end
    end
  end
end
