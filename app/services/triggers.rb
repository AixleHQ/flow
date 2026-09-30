# frozen_string_literal: true

# Telling the source that started a run what became of it — a tracker issue,
# a chat thread. The seam is shared with the Teams design
# (docs/design/teams-integration.md §17): one enqueue point on run transitions,
# one job per reporter, each reporter acting on the run's current state.
module Triggers
  ORIGIN_REPORTERS = %w[Trackers::RunStatusReporter].freeze

  def self.origin_reporters
    ORIGIN_REPORTERS.map(&:constantize)
  end
end
