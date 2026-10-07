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
        transitions from: :pending, to: :running, after: %i[on_started announce_running]
      end

      event :pause do
        transitions from: :running, to: :paused
      end

      event :resume do
        transitions from: :paused, to: :running
      end

      event :complete do
        transitions from: %i[running paused], to: :completed, after: %i[on_completed announce_completed]
      end

      event :fail do
        transitions from: %i[running paused], to: :failed, after: %i[on_completed announce_failed]
      end

      event :cancel do
        transitions from: %i[pending running paused], to: :cancelled, after: %i[on_cancelled announce_cancelled]
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
  def announce_running = announce_transition("running")
  def announce_completed = announce_transition("completed")
  def announce_failed = announce_transition("failed")
  def announce_cancelled = announce_transition("cancelled")

  # The shared run-transition seam (Triggers::ORIGIN_REPORTERS): one job per
  # dispatch that started this run.
  def announce_transition(transition)
    TriggerDispatch.where(workflow_run_id: id).pluck(:id).each do |dispatch_id|
      Triggers.announce(dispatch_id, transition)
    end
  rescue StandardError => e
    Rails.logger.error("[WorkflowRun] Failed to announce #{transition} for run ##{id}: #{e.message}")
  end
end
