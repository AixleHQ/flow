# frozen_string_literal: true

module InternalTools
  class MetaGetWorkflow < Base
    tool do
      display_name "Meta Get Workflow"
      description "Get the full definition of a workflow including all steps and sub-steps."
      tags :builder
      user_attachable false
      input_schema({
        type: "object",
        required: [],
        properties: {
          workflow_id: {
            type: "integer",
            description: "Workflow ID. Defaults to last created workflow."
          }
        }
      })
    end

    include MetaToolHelpers

    def execute
      require_project_context!

      workflow = find_target_workflow!

      steps_data = workflow.steps.not_deleted.includes(:sub_steps, :agent).order(:position).map do |step|
        {
          id: step.id,
          name: step.name,
          position: step.position,
          # Whole text, like sub-steps below: a 500-char cut here made every
          # meta_update_workflow_step that echoed instructions back a silent
          # truncation of the step it was editing.
          instructions: step.instructions,
          agent: step.agent ? { id: step.agent.id, title: step.agent.title } : nil,
          allow_non_interactive: step.allow_non_interactive,
          skip_policy: step.skip_policy,
          on_failure: step.on_failure,
          max_retries: step.max_retries,
          tool_ids: step.tool_ids,
          skill_ids: step.skill_ids,
          mcp_server_ids: step.mcp_server_ids,
          asset_ids: step.asset_ids,
          depends_on_step_ids: step.depends_on_step_ids,
          sub_steps: step.sub_steps.active.order(:position).map do |ss|
            {
              id: ss.id,
              name: ss.name,
              position: ss.position,
              instructions: ss.instructions,
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
