# frozen_string_literal: true

module Activities
  module Workflow
    class FetchModeActivity < ::Activities::Base
      def execute(input)
        run = WorkflowRun.find(input["workflow_run_id"])
        { "mode" => run.mode.to_s }
      end
    end
  end
end
