# frozen_string_literal: true

module PersonalTools
  class TriggerTaskWorkflow < Base
    tool do
      display_name "Trigger Task Workflow"
      description "Run the workflow bound to a board task's column — the same thing the Run " \
                  "workflow button on the task card does. A task that already has a run in " \
                  "flight is refused; pass force to cancel that run first and start a fresh one."
      audience :user
      tags :board, :workflows
      destructive
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_id, type: :integer, description: "Board task id.", required: true
      param :force, type: :boolean,
                    description: "Cancel the task's in-flight run and re-trigger (default false)."
    end

    ACTIVE_RUN_STATES = %w[pending running paused].freeze

    def execute
      project = find_project!
      authorize!(project, :trigger_workflow?, policy: Api::V1::Projects::Board::TasksPolicy, project: project)

      task = find_task(project)
      return error("Task #{params[:task_id]} not found in this project") unless task

      active_run = active_run_for(task)
      if active_run && !params[:force]
        return error("Workflow run #{active_run.id} is #{active_run.state} for this task — " \
                     "pass force: true to cancel it and start a new one")
      end

      # Not just a state change: WorkflowService.cancel drives each active step's
      # session through SessionService.cancel, and that Temporal cancellation
      # still runs the container workflow's cleanup phase — so the pod is
      # reclaimed and the terminal log collected before the retrigger.
      WorkflowService.cancel(run: active_run) if active_run

      result = TaskService.trigger_workflow(task: task, binding: task.board_column.column_workflow_binding, actor: user)
      return error(result[:error]) if result.is_a?(Hash) && result[:error]

      success(task_id: task.id, run_id: result.id, state: result.state, cancelled_run_id: active_run&.id)
    end

    private

    def find_task(project)
      project.board&.board_tasks&.find_by(id: params[:task_id])
    end

    def active_run_for(task)
      task.workflow_runs.where(state: ACTIVE_RUN_STATES).order(created_at: :desc).first
    end
  end
end
