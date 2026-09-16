# frozen_string_literal: true

# The one recurring job that is NOT a Temporal schedule, on purpose — see
# QueueHealthCheck for why, and config/recurring.yml for the cadence.
#
# It runs in the Solid Queue supervisor (the `jobs` deployment), which is the
# whole point: it has to survive the failure it exists to report.
class QueueHealthCheckJob < ApplicationJob
  queue_as :default

  # Never retry. The next tick is a minute away and carries a fresher answer; a
  # retried watchdog would report state that has already moved on.
  discard_on StandardError do |_job, error|
    Rails.logger.error("[QueueHealth] check failed: #{error.class}: #{error.message}")
    Sentry.capture_exception(error) if Sentry.initialized?
  end

  def perform
    QueueHealthCheck.call
  end
end
