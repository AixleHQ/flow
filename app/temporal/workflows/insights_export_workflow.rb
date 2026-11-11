# frozen_string_literal: true

module Workflows
  # The safety net of the Insights export (docs/design/insights-usage-export.md §6): the
  # inline send covers the happy path, this sweep a send that never ran or must be retried.
  class InsightsExportWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.insights_export_drain_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 3)
      )
    end
  end
end
