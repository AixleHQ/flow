# frozen_string_literal: true

module Activities
  module Workflow
    class CheckSkipActivity < ::Activities::Base
      def execute(input)
        run = WorkflowRun.find(input["workflow_run_id"])
        step = Step.find(input["step_id"])
        evaluator = StepSkipEvaluator.new(step, run)

        {
          "should_skip" => evaluator.should_skip?,
          "reason" => evaluator.skip_reason
        }
      end
    end
  end
end
