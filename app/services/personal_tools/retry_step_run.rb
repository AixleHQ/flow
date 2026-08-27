# frozen_string_literal: true

module PersonalTools
  class RetryStepRun < Base
    tool do
      display_name "Retry Step Run"
      description "Retry the current or latest failed step of a workflow run."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :run_id, type: :integer, description: "Workflow run id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :retry_step?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      run = WorkflowRun.where(project: project).find_by(id: params[:run_id])
      return error("Run not found in this project") unless run

      step_run = run.current_step_run || run.latest_failed_step_run
      return error("No retryable step") unless step_run&.retryable?

      result = WorkflowService.retry_step(step_run: step_run)
      return error(result[:error]) unless result[:ok]

      success(run_id: run.id, retried_step_run_id: step_run.id)
    end
  end
end
