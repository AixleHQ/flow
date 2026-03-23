# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepListActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        steps = workflow_run.workflow.steps.active.order(:position)
        overrides = workflow_run.step_overrides || {}

        steps.map do |step|
          existing_run = workflow_run.step_runs.find_by(step: step)
          step_override = overrides[step.id.to_s] || {}
          auto_run = step_override.key?("auto_run") ? step_override["auto_run"] : step.allow_non_interactive

          {
            "step_id" => step.id,
            "step_run_id" => existing_run&.id,
            "position" => step.position,
            "auto_run" => auto_run,
            "depends_on_step_ids" => step.depends_on_step_ids || [],
            "on_failure" => step.on_failure.to_s,
            "max_retries" => step.max_retries.to_i,
            "skip_policy" => step.skip_policy.to_s
          }
        end
      end
    end
  end
end
