# frozen_string_literal: true

module Activities
  module Workflow
    class MarkStepSkippedActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        step_run.mark_skipped!(input["reason"])

        { "step_run_id" => step_run.id, "state" => step_run.state }
      end
    end
  end
end
