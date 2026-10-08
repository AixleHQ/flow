# frozen_string_literal: true

module Activities
  module Workflow
    class LaunchStepSessionActivity < ::Activities::Base
      def execute(input)
        step_run = StepRun.find(input["step_run_id"])
        session = SessionService.create_for_workflow_step(step_run: step_run)

        { "terminal_session_id" => session.id, "step_run_id" => step_run.id }
      rescue AgentCredential::PreflightError => e
        step_run.mark_failed!(e.message)
        # The owner reads this on the step; renewing the login is theirs to do.
        raise Temporalio::Error::ApplicationError.new(e.message, type: "PreflightError", non_retryable: true,
                                                      category: TemporalExceptions::BENIGN)
      rescue SessionAdmissionService::Stopped => e
        # The run was cancelled, or its company stopped, before this step launched;
        # a retry finds the same thing.
        raise TemporalExceptions.non_retryable(e, benign: true)
      end
    end
  end
end
