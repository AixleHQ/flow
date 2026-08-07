# frozen_string_literal: true

module PersonalTools
  class UpdateWorkflow < Base
    tool do
      display_name "Update Workflow"
      description "Update a workflow's name, description and base resources (tools/skills/MCP servers/" \
                  "repositories granted to every step). Read the current values with get_workflow first."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :name, type: :string, description: "Updated workflow name."
      param :description, type: :string, description: "Updated workflow description."
      param :base_tool_ids, type: :array,
            description: "Tool ids granted to every step of this workflow. Replaces the whole list — " \
                         "read the current value with get_workflow first.",
            items: { type: "integer" }
      param :base_skill_ids, type: :array,
            description: "Skill ids injected into every step of this workflow. Replaces the whole list — " \
                         "read the current value with get_workflow first.",
            items: { type: "integer" }
      param :base_mcp_server_ids, type: :array,
            description: "MCP server ids available to every step of this workflow. Replaces the whole list — " \
                         "read the current value with get_workflow first.",
            items: { type: "integer" }
      param :base_repository_ids, type: :array,
            description: "Repository ids cloned into /workspace/repo for every step of this workflow. " \
                         "Replaces the whole list — read the current value with get_workflow first. " \
                         "Set repositories on the step instead when only some steps need code.",
            items: { type: "integer" }
    end

    ATTRS = %i[name description].freeze
    # Base resources are not columns — they live in workflow.config, behind the
    # model's base_* readers and merge_config! writer.
    CONFIG_ATTRS = %i[base_tool_ids base_skill_ids base_mcp_server_ids base_repository_ids].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = find_workflow!(project)

      attrs = ATTRS.each_with_object({}) { |k, h| h[k] = params[k] if params.key?(k) }
      config = CONFIG_ATTRS.each_with_object({}) { |k, h| h[k] = Array(params[k]).map(&:to_i) if params.key?(k) }
      return error("No fields to update") if attrs.empty? && config.empty?

      ActiveRecord::Base.transaction do
        workflow.update!(attrs) if attrs.any?
        workflow.merge_config!(config) if config.any?
      end

      success(id: workflow.id, name: workflow.name, description: workflow.description,
              base_tool_ids: workflow.base_tool_ids, base_skill_ids: workflow.base_skill_ids,
              base_mcp_server_ids: workflow.base_mcp_server_ids,
              base_repository_ids: workflow.base_repository_ids,
              updated_fields: (attrs.keys + config.keys).map(&:to_s))
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to update workflow: #{e.message}")
    end
  end
end
