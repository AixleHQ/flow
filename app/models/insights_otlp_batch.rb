# frozen_string_literal: true

# One OTLP request on its way to Aixle Insights (docs/design/insights-otlp-relay.md §5):
# what a session's agent sent, enriched with Flow's metadata and masked, gzipped. A row is
# deleted once Insights accepts it; it turns `failed` when Insights refuses it or after a
# week of transport errors, and is swept a week after that.
class InsightsOtlpBatch < ApplicationRecord
  STATES = %w[pending failed].freeze
  SIGNALS = %w[logs metrics traces].freeze

  belongs_to :integration
  belongs_to :project
  belongs_to :terminal_session

  validates :state, inclusion: { in: STATES }
  validates :signal, inclusion: { in: SIGNALS }

  scope :due, lambda { |now = Time.current|
    where(state: "pending")
      .where("insights_otlp_batches.next_attempt_at IS NULL OR insights_otlp_batches.next_attempt_at <= ?", now)
      .where("insights_otlp_batches.claimed_until IS NULL OR insights_otlp_batches.claimed_until < ?", now)
  }

  def self.wrap(request) = Zlib.gzip(request.to_json)

  def request = JSON.parse(Zlib.gunzip(payload))
end
