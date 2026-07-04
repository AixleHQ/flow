# frozen_string_literal: true

module PersonalTools
  class CreateSubStep < Base
    tool do
      display_name "Create Sub-Step"
      description "Add a sub-step (checklist item) to a workflow step. Sub-steps track progress within a step."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
      param :name, type: :string, description: "Sub-step name.", required: true
      param :description, type: :string, description: "What this sub-step covers."
      param :instructions, type: :string, description: "Detailed instructions (markdown)."
      param :position, type: :integer, description: "0-based position; auto-assigned if omitted."
      param :required, type: :boolean, description: "Whether the sub-step is required (default true)."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      step = find_step!(find_workflow!(project))

      position = params[:position] || (step.sub_steps.maximum(:position).to_i + 1)
      sub = step.sub_steps.create!(
        name: params[:name], position: position, description: params[:description],
        instructions: params[:instructions], required: params.fetch(:required, true)
      )
      success(id: sub.id, step_id: step.id, name: sub.name, position: sub.position)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create sub-step: #{e.message}")
    end
  end
end
