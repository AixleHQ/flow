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
        transitions from: :running, to: :paused, after: :broadcast_run_update!
      end

      event :resume do
        transitions from: :paused, to: :running, after: :broadcast_run_update!
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
    broadcast_run_update!
  end

  def on_completed
    update_column(:completed_at, Time.current)
    broadcast_run_update!
  end

  def on_cancelled
    update_column(:completed_at, Time.current)
    cancel_active_step_runs!
    broadcast_run_update!
  end

  def cancel_active_step_runs!
    step_runs.where(state: %w[pending running waiting_input]).find_each do |sr|
      cancel_session(sr.terminal_session)
      sr.mark_cancelled!
    rescue StandardError => e
      Rails.logger.warn("[WorkflowRunStateMachine] Failed to cancel step_run ##{sr.id}: #{e.message}")
    end
  end

  def cancel_session(session)
    return unless session

    session.cancel! if session.temporal_workflow_id.present?
    session.fail! if session.may_fail?
  rescue StandardError => e
    Rails.logger.warn("[WorkflowRunStateMachine] Failed to cancel session ##{session.id}: #{e.message}")
  end

  def broadcast_run_update!
    WorkflowRunChannel.broadcast_update(id)
    broadcast_board_event!
  rescue StandardError => e
    Rails.logger.warn("[WorkflowRunStateMachine#broadcast] #{e.message}")
  end

  def broadcast_board_event!
    return unless board_task_id.present?

    record_workflow_activity!
  rescue StandardError => e
    Rails.logger.warn("[WorkflowRunStateMachine#broadcast_board] #{e.message}")
  end

  def record_workflow_activity!
    activity_type = case state
    when "running" then :workflow_started
    when "failed" then :workflow_failed
    when "completed" then :workflow_completed
    when "cancelled" then :workflow_cancelled
    else return
    end

    ActivityRecorder.record(
      board: board_task.board, event_type: activity_type, actor: user,
      actor_type: :system, task: board_task,
      metadata: { workflow_name: workflow.name, workflow_run_id: id }
    )
  end
end
