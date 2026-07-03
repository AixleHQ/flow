# frozen_string_literal: true

module PersonalTools
  class CreateWorkflow < Base
    tool do
      display_name "Create Workflow"
      description "Create a new workflow in a project. See the build_workflow prompt for guidance on structuring steps."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :name, type: :string, description: "Workflow name.", required: true
      param :description, type: :string, description: "Workflow description."
    end

    def execute
      project = find_project!
      authorize!(project, :create?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)

      workflow = project.workflows.create!(name: params[:name], description: params[:description], config: {})
      success(id: workflow.id, name: workflow.name, description: workflow.description)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create workflow: #{e.message}")
    end
  end
end
