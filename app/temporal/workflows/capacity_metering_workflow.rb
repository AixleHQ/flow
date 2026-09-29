# frozen_string_literal: true

module Workflows
  # Hourly capacity metering (see app/temporal/schedules.yml).
  #
  # max_attempts: 1 is load-bearing, not caution. AWS Marketplace counts its
  # once-per-hour rule per EKS pod, so a retried activity that runs on another
  # replica finds a fresh budget and emits a second record for the same hour —
  # which AWS accepts and bills. The ledger is what recovers a failed send, on
  # the next run, within the six hours AWS still accepts records for.
  class CapacityMeteringWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.billing_report_capacity_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 1)
      )
    end
  end
end
