# frozen_string_literal: true

module Workflows
  # Scheduled Aixle Insights usage export (see app/temporal/schedules.yml,
  # every 15 minutes, overlap: skip).
  #
  # max_attempts: 1 — recovery is the ledger, not a Temporal retry. The exporter
  # records every send in InsightsUsageExport and replays `unsent` rows on the
  # next run (within the 7-day window), so a failed sweep is recovered by the
  # following tick rather than by retrying inside this one. A retry would only
  # repeat work the next run already does.
  class InsightsUsageExportWorkflow < Base
    def run(_input = nil)
      execute_activity(
        activities.aixle_insights_export_usage_activity, {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 1)
      )
    end
  end
end
