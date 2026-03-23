# frozen_string_literal: true

module Activities
  module Workflow
    class CreateStepRunActivity < ::Activities::Base
      def execute(input)
        workflow_run = WorkflowRun.find(input["workflow_run_id"])
        step = Step.find(input["step_id"])

        step_run = if input["force_new"]
                     workflow_run.step_runs.create!(step: step, state: :pending)
        else
                     workflow_run.step_runs.find_or_create_by!(step: step)
        end

        { "step_run_id" => step_run.id }
      end
    end
  end
end
