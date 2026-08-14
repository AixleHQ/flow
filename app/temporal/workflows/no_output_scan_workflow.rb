# frozen_string_literal: true

module Workflows
  class NoOutputScanWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.workflow_scan_no_output_sessions_activity, {},
        start_to_close_timeout: 120,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 1)
      )
    end
  end
end
