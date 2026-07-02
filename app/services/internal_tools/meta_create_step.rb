# frozen_string_literal: true

module InternalTools
  class MetaCreateStep < Base
    tool do
      display_name "Meta Create Step"
      description "Add a step to the target workflow. Steps are added sequentially unless position is specified."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: %w[name],
        properties: {
          name: {
            type: "string",
            description: "Step name"
          },
          agent_id: {
            type: "integer",
            description: "Agent to run this step"
          },
          position: {
            type: "integer",
            description: "Position in workflow (0-based). Auto-assigned if omitted."
          },
          tool_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Tool IDs available in this step"
          },
          asset_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Asset IDs loaded into this step's container (in addition to workflow base assets)"
          },
          skill_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Skill IDs injected into context"
          },
          on_failure: {
            enum: %w[retry skip fail],
            type: "string",
            description: "Failure behavior"
          },
          description: {
            type: "string",
            description: "Brief description for UI"
          },
          max_retries: {
            type: "integer",
            description: "Retry count on failure"
          },
          skip_policy: {
            enum: %w[never if_outputs_exist manual],
            type: "string",
            description: "When to skip"
          },
          workflow_id: {
            type: "integer",
            description: "Target workflow ID. Defaults to last created workflow."
          },
          instructions: {
            type: "string",
            description: "Focused, task-specific instructions (markdown): what to do and what to produce. Do NOT restate session-completion rules, workspace layout, sub-step tracking, or tool availability — the platform injects those automatically."
          },
          mcp_server_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "MCP server IDs"
          },
          input_asset_specs: {
            type: "array",
            description: "Required input files"
          },
          mount_repositories: {
            type: "boolean",
            description: "Mount Git repos in /workspace"
          },
          output_asset_specs: {
            type: "array",
            description: "Expected output files"
          },
          depends_on_step_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Step IDs this step depends on (DAG)"
          },
          allow_non_interactive: {
            type: "boolean",
            description: "Can run without user interaction"
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = find_target_workflow!
      position = params[:position] || (workflow.steps.maximum(:position).to_i + 1)

      step = workflow.steps.create!(
        name: params[:name],
        position: position,
        description: params[:description],
        instructions: params[:instructions],
        agent_id: params[:agent_id],
        allow_non_interactive: params.fetch(:allow_non_interactive, false),
        skip_policy: params[:skip_policy] || "never",
        on_failure: params[:on_failure] || "fail",
        max_retries: params[:max_retries] || 0,
        tool_ids: params[:tool_ids] || [],
        skill_ids: params[:skill_ids] || [],
        mcp_server_ids: params[:mcp_server_ids] || [],
        asset_ids: params[:asset_ids] || [],
        mount_repositories: params.fetch(:mount_repositories, false),
        preferred_model: params[:preferred_model],
        bmad_enabled: params.fetch(:bmad_enabled, false),
        input_asset_specs: params[:input_asset_specs] || [],
        output_asset_specs: params[:output_asset_specs] || [],
        depends_on_step_ids: params[:depends_on_step_ids] || []
      )

      broadcast_meta_activity(
        action: "created_step",
        entity_type: "Step",
        entity_name: step.name,
        entity_id: step.id,
        details: { workflow_id: workflow.id, position: step.position }
      )

      success({
        id: step.id,
        workflow_id: workflow.id,
        name: step.name,
        position: step.position,
        agent_id: step.agent_id
      }.to_json)
    rescue ActiveRecord::RecordInvalid => e
      error("Failed to create step: #{e.message}")
    rescue RuntimeError => e
      error(e.message)
    end
  end
end
