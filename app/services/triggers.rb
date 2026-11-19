# frozen_string_literal: true

# Telling the source that started a run what became of it — a tracker issue,
# a chat thread — and starting the run a pull request's skipped events wait for.
# The seam is shared with the Teams design (docs/design/teams-integration.md
# §17): one enqueue point on run transitions, one job per reporter, each
# reporter acting on the run's current state.
module Triggers
  ORIGIN_REPORTERS = %w[Trackers::RunStatusReporter Chat::RunStatusReporter PullRequests::FollowUpRun].freeze

  def self.origin_reporters
    ORIGIN_REPORTERS.map(&:constantize)
  end

  # `transition` is the state a run entered (running, completed, failed,
  # cancelled), or what became of the dispatch that had no run to enter one:
  # dispatched or skipped.
  def self.announce(dispatch_id, transition)
    ReportRunTransitionJob.perform_later(dispatch_id, transition.to_s)
  end
end
