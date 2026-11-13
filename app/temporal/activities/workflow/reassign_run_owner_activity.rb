# frozen_string_literal: true

module Activities
  module Workflow
    # A step stopped on its owner's quota or login: hand the run to the next member
    # of its team, if it has one who can take it (ProjectTeams::Handoff).
    class ReassignRunOwnerActivity < ::Activities::Base
      def execute(input)
        run = WorkflowRun.find(input["workflow_run_id"])
        step_run = run.step_runs.find_by(id: input["step_run_id"])
        { "reassigned" => ProjectTeams::Handoff.reassign!(run, step_run: step_run) }
      end
    end
  end
end
