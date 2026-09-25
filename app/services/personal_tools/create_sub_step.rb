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
      param :instructions, type: :string, description: "What the agent must do in this sub-step (markdown)."
      param :position, type: :integer, description: "0-based position; auto-assigned if omitted."
      param :required, type: :boolean, description: "Whether the sub-step is required (default true)."
      param :base_version, type: :integer, description: "The workflow version you read (current_version_number). A newer one means someone else saved since, and the change is refused."
    end

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)
      step = find_step!(workflow)

      position = params[:position] || (step.sub_steps.maximum(:position).to_i + 1)
      sub = nil
      Versions.save!(workflow, actor: version_actor, base_version: base_version) do
        sub = step.sub_steps.create!(
          name: params[:name], position: position,
          instructions: params[:instructions], required: params.fetch(:required, true)
        )
      end
      success(id: sub.id, step_id: step.id, name: sub.name, position: sub.position)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create sub-step: #{e.message}")
    end
  end
end
