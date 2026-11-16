# frozen_string_literal: true

module Workflows
  class RunnerHealthCheckWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.runner_health_check_activity, {},
        start_to_close_timeout: 120,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
