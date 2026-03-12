# frozen_string_literal: true

module Activities
  module Workflow
    class LaunchStepSessionActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        session = SessionService.create_for_workflow_step(step_run: step_run)

        { "terminal_session_id" => session.id, "step_run_id" => step_run.id }
      end
    end
  end
end
