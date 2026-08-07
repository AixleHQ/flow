# frozen_string_literal: true

module PersonalTools
  class UpdateSubStep < Base
    tool do
      display_name "Update Sub-Step"
      description "Update a sub-step (checklist item) of a workflow step. Read the step with " \
                  "get_workflow_step first — it reports each sub-step's id."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
      param :sub_step_id, type: :integer, description: "Sub-step id (from get_workflow_step).", required: true
      param :name, type: :string, description: "Updated name."
      param :instructions, type: :string, description: "Updated instructions (markdown)."
      param :position, type: :integer, description: "Updated position within the step."
      param :required, type: :boolean, description: "Whether the sub-step is required."
    end

    UPDATABLE = %i[name instructions position required].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      step = find_step!(find_workflow!(project))
      sub_step = find_sub_step!(step)

      attrs = UPDATABLE.each_with_object({}) { |k, h| h[k] = params[k] if params.key?(k) }
      return error("No fields to update") if attrs.empty?

      sub_step.update!(attrs)
      success(id: sub_step.id, step_id: step.id, name: sub_step.name, position: sub_step.position,
              updated_fields: attrs.keys.map(&:to_s))
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update sub-step: #{e.message}")
    end
  end
end
