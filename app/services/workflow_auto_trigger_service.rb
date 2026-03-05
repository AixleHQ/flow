# frozen_string_literal: true

class WorkflowAutoTriggerService
  def self.check!(task:, column: nil, actor:, actor_type: :human)
    new(task: task, column: column || task.board_column, actor: actor, actor_type: actor_type).check!
  end

  def initialize(task:, column:, actor:, actor_type:)
    @task = task
    @column = column
    @actor = actor
    @actor_type = actor_type
  end

  def check!
    binding = @column.column_workflow_binding
    return unless binding&.trigger_mode&.to_sym == :auto

    cancel_active_runs!

    run = WorkflowRun.create!(
      workflow: binding.workflow,
      project: @column.board.project,
      user: @actor,
      board_task_id: @task.id,
      mode: :non_interactive
    )

    WorkflowService.start_workflow_execution(run)
  rescue StandardError => e
    Rails.logger.error("[WorkflowAutoTriggerService] #{e.message}")
  end

  private

  def cancel_active_runs!
    @task.workflow_runs.where(state: %w[pending running paused]).find_each do |run|
      temporal_workflow_id = "workflow-execution-#{run.id}"
      TemporalService.send_signal(temporal_workflow_id, "workflow_cancelled")
      TemporalService.cancel_workflow(temporal_workflow_id)
      run.cancel! if run.may_cancel?
    rescue StandardError => e
      Rails.logger.warn("[WorkflowAutoTriggerService] Could not cancel run ##{run.id}: #{e.message}")
    end
  end
end
