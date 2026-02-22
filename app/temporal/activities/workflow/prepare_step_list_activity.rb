# frozen_string_literal: true

module Activities
  module Workflow
    class PrepareStepListActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        steps = workflow_run.workflow.steps.order(:position)

        steps.map do |step|
          existing_run = workflow_run.step_runs.find_by(step: step)
          {
            "step_id" => step.id,
            "step_run_id" => existing_run&.id,
            "position" => step.position,
            "allow_non_interactive" => step.allow_non_interactive,
            "on_failure" => step.on_failure.to_s,
            "max_retries" => step.max_retries.to_i,
            "skip_policy" => step.skip_policy.to_s
          }
        end
      end
    end
  end
end
