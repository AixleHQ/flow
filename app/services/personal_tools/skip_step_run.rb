# frozen_string_literal: true

module PersonalTools
  class SkipStepRun < Base
    tool do
      display_name "Skip Step Run"
      description "Skip the current step of a workflow run."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :run_id, type: :integer, description: "Workflow run id.", required: true
      param :reason, type: :string, description: "Why the step is being skipped."
    end

    def execute
      project = find_project!
      authorize!(project, :skip_step?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      run = find_controllable_run!(project)

      step_run = run.current_step_run
      return error("No current step to skip") unless step_run

      WorkflowService.skip_step(step_run: step_run, reason: params[:reason])
      success(run_id: run.id, skipped_step_run_id: step_run.id)
    end
  end
end
