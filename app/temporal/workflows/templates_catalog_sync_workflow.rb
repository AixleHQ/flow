# frozen_string_literal: true

module Workflows
  # TemplatesCatalogSyncWorkflow — hourly refresh of the mirrored template
  # catalog. Wired into `app/temporal/schedules.yml`.
  #
  # Two attempts only: a failed run leaves the previous mirror serving, and the
  # next hour tries again.
  class TemplatesCatalogSyncWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.templates_sync_catalog_activity, input || {},
        start_to_close_timeout: 300,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
