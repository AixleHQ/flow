# frozen_string_literal: true

module Workflows
  class RunnerAbandonedMachinesWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.runner_machines_settle_abandoned_activity, {},
        start_to_close_timeout: 120,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
