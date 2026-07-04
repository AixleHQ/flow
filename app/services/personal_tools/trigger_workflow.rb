# frozen_string_literal: true

module PersonalTools
  class TriggerWorkflow < Base
    tool do
      display_name "Trigger Workflow"
      description "Start a run of a workflow in a project. Returns the run id and state."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :mode, type: :string, description: "Run mode: interactive or non_interactive.", enum: %w[interactive non_interactive]
    end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::WorkflowRunsPolicy, project: project)
      workflow = Workflow.visible_for_project(project).find_by(id: params[:workflow_id])
      return error("Workflow not found in this project") unless workflow

      run = WorkflowService.start(
        workflow: workflow, project: project, user: user,
        mode: (params[:mode].presence || "interactive").to_sym
      )
      return error("Could not start run: #{run.errors.full_messages.to_sentence}") unless run.persisted?

      success(run_id: run.id, workflow_id: workflow.id, state: run.state)
    end
  end
end
