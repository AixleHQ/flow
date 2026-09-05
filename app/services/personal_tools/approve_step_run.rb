# frozen_string_literal: true

module PersonalTools
  class ApproveStepRun < Base
    tool do
      display_name "Approve Step Run"
      description "Approve the current pending step of a workflow run so it can proceed."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :run_id, type: :integer, description: "Workflow run id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :approve_step?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      run = find_controllable_run!(project)

      step_run = run.current_step_run
      return error("No current step to approve") unless step_run

      WorkflowService.approve_step(step_run: step_run)
      success(run_id: run.id, approved_step_run_id: step_run.id)
    end
  end
end
