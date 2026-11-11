# frozen_string_literal: true

# One session on its way to Aixle Insights (docs/design/insights-usage-export.md §6).
# pending → delivered when every chunk was accepted in full; rejected when Insights refused
# records (never retried automatically); failed after a week of transport errors; skipped
# when the connection went away first. A delivered session that gains rows goes back to
# pending, and the re-send upserts.
class InsightsSessionExport < ApplicationRecord
  STATES = %w[pending delivered rejected failed skipped].freeze

  belongs_to :terminal_session
  belongs_to :integration, optional: true

  validates :state, inclusion: { in: STATES }

  scope :due, lambda { |now = Time.current|
    where(state: "pending")
      .where("insights_session_exports.next_attempt_at IS NULL OR insights_session_exports.next_attempt_at <= ?", now)
      .where("insights_session_exports.claimed_until IS NULL OR insights_session_exports.claimed_until < ?", now)
      .joins(:integration).merge(Integration.active)
  }
end
