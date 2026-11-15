# frozen_string_literal: true

module Activities
  module Workflow
    class StepSessionStatusActivity < Base
      def run(input)
        run = WorkflowRun.find(input.workflow_run_id)
        sessions = run.step_runs.includes(:terminal_session).where(id: input.step_run_ids).map do |step|
          session = step.terminal_session
          admission = session&.session_admission
          state = admission && !admission.released_at && session.concluded? ? "finishing" : session&.state
          [ step.id.to_s, { "state" => state, "step_state" => step.state } ]
        end.to_h
        { "cancelled" => run.stopped?, "sessions" => sessions }
      end
    end
  end
end
