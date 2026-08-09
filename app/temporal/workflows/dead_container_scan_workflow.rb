# frozen_string_literal: true

module Workflows
  class DeadContainerScanWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.session_scan_dead_containers_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
