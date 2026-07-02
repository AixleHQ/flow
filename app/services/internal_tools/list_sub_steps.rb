# frozen_string_literal: true

module InternalTools
  class ListSubSteps < Base
    tool do
      display_name "List Sub-Steps"
      description "List current step's sub-steps with their statuses. Only available during workflow execution."
      tags :workflow_control
      inject_when :workflow_step_session
      user_attachable false
      input_schema({
        type: "object",
        properties: {}
      })
    end

    def execute
      require_workflow_context!

      sub_step_runs = step_run.sub_step_runs
        .includes(:sub_step)
        .order("sub_steps.position")

      result = sub_step_runs.map do |ssr|
        {
          id: ssr.id,
          position: ssr.sub_step.position,
          name: ssr.sub_step.name,
          description: ssr.sub_step.description,
          status: ssr.state,
          note: ssr.note,
          data: ssr.data
        }
      end

      success(result.to_json)
    end
  end
end
