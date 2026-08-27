# frozen_string_literal: true

module WorkflowRunStateMachine
  extend ActiveSupport::Concern

  included do
    include AASM

    aasm column: :state do
      state :pending, initial: true
      state :running
      state :paused
      state :completed
      state :failed
      state :cancelled

      event :start do
        transitions from: :pending, to: :running, after: :on_started
      end

      event :pause do
        transitions from: :running, to: :paused
      end

      event :resume do
        transitions from: %i[paused failed], to: :running, after: :on_resumed
      end

      event :complete do
        transitions from: %i[running paused], to: :completed, after: :on_completed
      end

      event :fail do
        transitions from: %i[running paused], to: :failed, after: :on_completed
      end

      event :cancel do
        transitions from: %i[pending running paused], to: :cancelled, after: :on_cancelled
      end
    end
  end

  private

  def on_started
    update_column(:started_at, Time.current)
  end

  def on_completed
    update_column(:completed_at, Time.current)
  end

  def on_cancelled
    update_column(:completed_at, Time.current)
  end

  # Clears prior-attempt failure state when resuming a failed run with a fresh
  # execution; a no-op for resuming from paused, which never sets these.
  def on_resumed
    update_columns(completed_at: nil, failure_reason: nil, failed_agent_credential_id: nil)
  end
end
