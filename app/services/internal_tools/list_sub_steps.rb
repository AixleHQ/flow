# frozen_string_literal: true

module InternalTools
  class ListSubSteps < Base
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
