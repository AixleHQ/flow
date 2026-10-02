# frozen_string_literal: true

module Slack
  # Superseded by Chat::RunStatusReporter on the run-transition seam. Kept for
  # one release so a job a previous deploy enqueued still finds its class; the
  # same failure is reported through the seam, so it does nothing.
  class NotifyRunFailureJob < ApplicationJob
    queue_as :default

    def perform(_workflow_run_id); end
  end
end
