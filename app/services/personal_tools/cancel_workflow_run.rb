# frozen_string_literal: true

module PersonalTools
  class CancelWorkflowRun < Base
    tool do
      display_name "Cancel Workflow Run"
      description "Cancel an in-progress workflow run."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :run_id, type: :integer, description: "Workflow run id.", required: true
    end

    def execute
      project = find_project!
      authorize!(project, :cancel?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      run = find_controllable_run!(project)

      WorkflowService.cancel(run: run)
      success(run_id: run.id, state: run.reload.state)
    end
  end
end
