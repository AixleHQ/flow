# frozen_string_literal: true

module Workflows
  class TrackerPersonalDataWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.trackers_report_personal_data_activity, {},
        start_to_close_timeout: 600,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
