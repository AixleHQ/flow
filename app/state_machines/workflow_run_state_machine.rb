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
        transitions from: :paused, to: :running
      end

      event :complete do
        transitions from: %i[running paused], to: :completed, after: :on_completed
      end

      event :fail do
        transitions from: %i[running paused], to: :failed, after: %i[on_completed announce_failure]
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

  # On the transition rather than in WorkflowService.fail, because that is not
  # the only way a run ends up failed — the stale-run sweeper calls `fail!`
  # straight on the record, and a run reaped as stale is precisely the kind of
  # failure nobody is watching for.
  def announce_failure
    Slack::NotifyRunFailureJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[WorkflowRun] Failed to enqueue the Slack failure notice for run ##{id}: #{e.message}")
  end
end
