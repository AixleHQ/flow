# frozen_string_literal: true

module PersonalTools
  class TriggerTaskWorkflow < Base
    tool do
      display_name "Trigger Task Workflow"
      description "Run the workflow bound to a board task's column. A task that already has a " \
                  "run in flight is refused; pass force to cancel that run first and start a " \
                  "fresh one. The run is attributed to the task's assignee (whose agent " \
                  "credential it spends and whose bill it lands on) — the response says which " \
                  "account under `runs_as`."
      audience :user
      tags :board, :workflows
      destructive
      param :project_id, type: :integer, description: "Project id.", required: true
      param :task_number, type: :integer, description: TASK_NUMBER_PARAM
      param :task_id, type: :integer, description: TASK_ID_PARAM
      param :force, type: :boolean,
                    description: "Cancel the task's in-flight run and re-trigger (default false)."
      runner = param :runner_id, type: :integer,
                     description: "Runner to run on instead of the workflow's own (null for hosted). Omit it to use " \
                                  "the workflow's runner. Refused unless external runners are enabled for the company."
      runner["type"] = %w[integer null]
    end

    ACTIVE_RUN_STATES = %w[pending running paused].freeze

    def execute
      project = find_project!
      authorize!(project, :trigger_workflow?, policy: Api::V1::Projects::Board::TasksPolicy, project: project)

      task = find_task(project.board&.board_tasks)
      return error(task_not_found) unless task

      active_run = active_run_for(task)
      if active_run && !params[:force]
        return error("Workflow run #{active_run.id} is #{active_run.state} for this task — " \
                     "pass force: true to cancel it and start a new one")
      end

      find_controllable_run!(project, active_run.id) if active_run

      # Refused before the in-flight run is cancelled for a launch that cannot happen.
      if params.key?(:runner_id) && (refusal = Runners::Selection.error(params[:runner_id], project: project))
        return error(refusal)
      end

      # Not just a state change: WorkflowService.cancel drives each active step's
      # session through SessionService.cancel, and that Temporal cancellation
      # still runs the container workflow's cleanup phase — so the pod is
      # reclaimed and the terminal log collected before the retrigger.
      WorkflowService.cancel(run: active_run) if active_run

      result = TaskService.trigger_workflow(task: task, binding: task.board_column.column_workflow_binding, actor: user,
                                            **runner_pick)
      return error(result[:error]) if result.is_a?(Hash) && result[:error]

      # `runs_as` is read off the run rather than predicted here. TaskService owns
      # who a run belongs to (the assignee, falling back to whoever asked), and a
      # second copy of that rule in the caller is exactly what drifts. The account
      # is worth reporting because it is the one whose agent credential the run
      # spends and whose bill it lands on.
      success(task_id: task.id, task_number: task.number, run_id: result.id, state: result.state,
              runs_as: result.user&.email, cancelled_run_id: active_run&.id)
    end

    private

    def runner_pick = params.key?(:runner_id) ? { runner_id: params[:runner_id] } : {}

    def active_run_for(task)
      task.workflow_runs.where(state: ACTIVE_RUN_STATES).order(created_at: :desc).first
    end
  end
end
