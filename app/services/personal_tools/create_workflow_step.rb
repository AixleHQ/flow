# frozen_string_literal: true

module PersonalTools
  class CreateWorkflowStep < Base
    tool do
      display_name "Create Workflow Step"
      description "Add a step to a workflow. Steps run in position order unless dependencies say otherwise."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :name, type: :string, description: "Step name.", required: true
      param :instructions, type: :string, description: "Task-specific instructions (markdown)."
      param :agent_id, type: :integer, description: "Agent id to run this step."
      param :position, type: :integer, description: "0-based position; auto-assigned if omitted."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = Workflow.visible_for_project(project).find_by(id: params[:workflow_id])
      return error("Workflow not found in this project") unless workflow

      position = params[:position] || (workflow.steps.maximum(:position).to_i + 1)
      step = workflow.steps.create!(
        name: params[:name], position: position,
        instructions: params[:instructions], agent_id: params[:agent_id]
      )
      success(id: step.id, workflow_id: workflow.id, name: step.name, position: step.position)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create step: #{e.message}")
    end
  end
end
