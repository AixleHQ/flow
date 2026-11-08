# frozen_string_literal: true

module Workflows
  class RunnerOperationsSweepWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.runner_operations_sweep_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
