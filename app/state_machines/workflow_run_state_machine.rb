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
        transitions from: %i[running paused], to: :failed, after: :on_completed
      end

      event :cancel do
        transitions from: %i[pending running paused], to: :cancelled, after: :on_completed
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

  def broadcast_run_update!
    WorkflowRunChannel.broadcast_update(id)
    broadcast_board_event!
  rescue StandardError => e
    Rails.logger.warn("[WorkflowRunStateMachine#broadcast] #{e.message}")
  end

  def broadcast_board_event!
    return unless board_task_id.present?

    board = board_task&.board
    return unless board

    event_type = state.in?(%w[running pending paused]) ? "workflow_started" : "workflow_completed"
    BoardChannel.broadcast_event(board, event_type, {
      task_id: board_task_id,
      run_id: id,
      status: state
    })

    record_workflow_activity!(board, event_type)
  rescue StandardError => e
    Rails.logger.warn("[WorkflowRunStateMachine#broadcast_board] #{e.message}")
  end

  def record_workflow_activity!(board, _event_type)
    activity_type = case state
    when "failed" then :workflow_failed
    when "completed" then :workflow_completed
    else return
    end

    ActivityRecorder.record(
      board: board, event_type: activity_type, actor: user,
      actor_type: :system, task: board_task,
      metadata: { workflow_name: workflow.name, workflow_run_id: id }
    )
  end
end
