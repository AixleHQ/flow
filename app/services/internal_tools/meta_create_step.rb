# frozen_string_literal: true

module InternalTools
  class MetaCreateStep < Base
    include MetaToolHelpers

    def execute
      require_workflow_context!

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
        mount_repositories: params.fetch(:mount_repositories, false),
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
