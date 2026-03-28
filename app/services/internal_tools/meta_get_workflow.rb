# frozen_string_literal: true

module InternalTools
  class MetaGetWorkflow < Base
    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = find_target_workflow!

      steps_data = workflow.steps.not_deleted.includes(:sub_steps, :agent).order(:position).map do |step|
        {
          id: step.id,
          name: step.name,
          position: step.position,
          description: step.description,
          instructions: step.instructions&.truncate(500),
          agent: step.agent ? { id: step.agent.id, title: step.agent.title } : nil,
          allow_non_interactive: step.allow_non_interactive,
          skip_policy: step.skip_policy,
          on_failure: step.on_failure,
          max_retries: step.max_retries,
          tool_ids: step.tool_ids,
          skill_ids: step.skill_ids,
          mcp_server_ids: step.mcp_server_ids,
          depends_on_step_ids: step.depends_on_step_ids,
          sub_steps: step.sub_steps.active.order(:position).map do |ss|
            {
              id: ss.id,
              name: ss.name,
              position: ss.position,
              description: ss.description,
              required: ss.required
            }
          end
        }
      end

      success({
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        scope_type: workflow.scope_type,
        scope_id: workflow.scope_id,
        steps_count: steps_data.size,
        steps: steps_data
      }.to_json)
    rescue RuntimeError => e
      error(e.message)
    end
  end
end
