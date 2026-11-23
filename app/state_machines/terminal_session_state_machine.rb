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

      # Sessions::Suspension. The cleanup activity writes `suspended` itself, as it
      # writes every final state; these are the moves that happen after it.
      event :mark_restored do
        transitions from: :suspended, to: :restored
      end

      event :expire_suspension do
        transitions from: :suspended, to: :finished
      end
    end
  end
end
