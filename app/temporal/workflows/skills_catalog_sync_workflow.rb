# frozen_string_literal: true

module Workflows
  # SkillsCatalogSyncWorkflow — weekly refresh of the mirrored skills.sh catalog.
  # Wired into `app/temporal/schedules.yml`.
  #
  # Weekly, for the same reason the connector sync is: only discovery goes stale.
  # A newly published skill takes up to a week to appear in the default view, and
  # in exchange the sweep spends a couple hundred sequential requests against
  # endpoints that publish no rate limit and disclaim their own availability.
  #
  # A long start_to_close timeout because the sweep is ~200 paced requests plus a
  # bounded metadata backfill. Only two attempts: a failed sweep leaves the
  # previous mirror serving, so a tight retry loop buys nothing.
  class SkillsCatalogSyncWorkflow < Base
    def run(input = nil)
      execute_activity(
        activities.skills_sync_catalog_activity, input || {},
        start_to_close_timeout: 1_800,
        retry_policy: Temporalio::RetryPolicy.new(max_attempts: 2)
      )
    end
  end
end
