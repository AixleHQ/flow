# frozen_string_literal: true

module Activities
  module Workflow
    class CreateStepRunActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        step = Step.find(input["step_id"])
        step_run = workflow_run.step_runs.create!(step: step)

        { "step_run_id" => step_run.id }
      end
    end
  end
end
