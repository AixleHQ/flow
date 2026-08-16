# frozen_string_literal: true

module PersonalTools
  class CreateWorkflowStep < Base
    tool do
      display_name "Create Workflow Step"
      description "Add a step to a workflow, wiring included. Steps run in position order unless dependencies say otherwise."
      audience :user
      tags :workflows
      param :project_id, type: :integer, description: "Project id.", required: true
      param :workflow_id, type: :integer, description: "Workflow id.", required: true
      param :name, type: :string, description: "Step name.", required: true
      param :instructions, type: :string, description: "Task-specific instructions (markdown)."
      param :agent_id, type: :integer, description: "Agent id to run this step."
      param :position, type: :integer, description: "0-based position; auto-assigned if omitted."
      param :tool_ids, type: :array,
            description: "Tool ids available in this step. Replaces the whole list — read the current value " \
                         "with get_workflow_step first.",
            items: { type: "integer" }
      param :skill_ids, type: :array,
            description: "Skill ids injected into context. Replaces the whole list — read the current value " \
                         "with get_workflow_step first.",
            items: { type: "integer" }
      param :mcp_server_ids, type: :array,
            description: "MCP server ids. Replaces the whole list — read the current value with " \
                         "get_workflow_step first.",
            items: { type: "integer" }
      param :config_item_ids, type: :array,
            description: "Config item ids (secrets / environment variables) this step's agent may read with " \
                         "get_config_item. Attach a credential here instead of writing it into the " \
                         "instructions. Replaces the whole list — read the current value with " \
                         "get_workflow_step first.",
            items: { type: "integer" }
      param :depends_on_step_ids, type: :array,
            description: "Step ids this step depends on; they must already exist. Replaces the whole list — " \
                         "read the current value with get_workflow_step first.",
            items: { type: "integer" }
      param :bmad_enabled, type: :boolean, description: "Run this step with the BMAD method enabled."
      param :allow_non_interactive, type: :boolean, description: "Allow this step to run without a human in the loop."
    end

    OPTIONAL = %i[tool_ids skill_ids mcp_server_ids config_item_ids depends_on_step_ids
                bmad_enabled allow_non_interactive].freeze

    def execute
      project = find_project!
      authorize!(project, :update?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)
      workflow = Workflow.visible_for_project(project).find_by(id: params[:workflow_id])
      return error("Workflow not found in this project") unless workflow

      position = params[:position] || (workflow.steps.maximum(:position).to_i + 1)
      step = workflow.steps.create!(
        { name: params[:name], position: position,
          instructions: params[:instructions], agent_id: params[:agent_id] }.merge(wiring)
      )
      success(id: step.id, workflow_id: workflow.id, name: step.name, position: step.position,
              tool_ids: step.tool_ids, skill_ids: step.skill_ids, mcp_server_ids: step.mcp_server_ids,
              config_item_ids: step.config_item_ids,
              depends_on_step_ids: step.depends_on_step_ids, bmad_enabled: step.bmad_enabled,
              allow_non_interactive: step.allow_non_interactive)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create step: #{e.message}")
    end

    private

    def wiring
      OPTIONAL.each_with_object({}) { |k, h| h[k] = params[k] if params.key?(k) }
    end
  end
end
