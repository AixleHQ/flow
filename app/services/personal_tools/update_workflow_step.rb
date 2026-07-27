# frozen_string_literal: true

module PersonalTools
  class UpdateWorkflowStep < Base
    tool do
      display_name "Update Workflow Step"
      description "Update a workflow step's fields (name, instructions, agent, tools, skills, deps)."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :step_id, type: :integer, description: "Step id.", required: true
      param :name, type: :string, description: "Updated name."
      param :instructions, type: :string, description: "Updated instructions (markdown)."
      param :agent_id, type: :integer, description: "Agent id to run this step."
      param :tool_ids, type: :array, description: "Tool ids available in this step.", items: { type: "integer" }
      param :skill_ids, type: :array, description: "Skill ids injected into context.", items: { type: "integer" }
      param :mcp_server_ids, type: :array, description: "MCP server ids.", items: { type: "integer" }
      param :depends_on_step_ids, type: :array, description: "Step ids this step depends on.", items: { type: "integer" }
    end

    UPDATABLE = %i[name instructions agent_id tool_ids skill_ids mcp_server_ids depends_on_step_ids].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      step = find_step!(find_workflow!(project))

      attrs = UPDATABLE.each_with_object({}) { |k, h| h[k] = params[k] if params.key?(k) }
      return error("No fields to update") if attrs.empty?

      step.update!(attrs)
      success(id: step.id, name: step.name, updated_fields: attrs.keys.map(&:to_s))
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update step: #{e.message}")
    end
  end
end
