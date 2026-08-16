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
          config_item_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Config item IDs (secrets / environment variables) this step's agent may " \
                         "read with `get_config_item`. Attach a credential here instead of writing " \
                         "it into the instructions."
          },
          on_failure: {
            enum: %w[retry skip fail],
            type: "string",
            description: "Failure behavior"
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
          repository_ids: {
            type: "array",
            items: {
              type: "integer"
            },
            description: "Repository IDs cloned into /workspace/repo for this step (in addition to workflow base repositories). Leave empty for steps that do not need code."
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
        repository_ids: params[:repository_ids] || [],
        config_item_ids: params[:config_item_ids] || [],
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
