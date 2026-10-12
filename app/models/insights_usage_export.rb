# frozen_string_literal: true

class InsightsUsageExport < ApplicationRecord
  STATES = %w[pending exported failed skipped].freeze

  # Insights attributes an event only within 7 days of its timestamp (see
  # Ai::CorrelationService::LOOKBACK in db90-rails). A session whose work ended
  # longer ago than this can never be attributed, so it is abandoned (skipped)
  # rather than retried against a collector that will drop it.
  REPLAY_WINDOW = 7.days

  belongs_to :terminal_session
  # Denormalized diagnostics column (optional — nullified if the company is
  # deleted). Correctness resolves the live company from the session.
  belongs_to :company, optional: true

  validates :state, inclusion: { in: STATES }
  validates :attempts, :records_sent,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :unsent, -> { where(state: %w[pending failed]) }
  scope :for_company, ->(company) { where(company_id: company) }

  def exported!(records_sent)
    update!(state: "exported", records_sent: records_sent, error: nil,
            exported_at: Time.current)
  end

  def failed!(message)
    update!(state: "failed", error: message.to_s.truncate(1000), attempts: attempts + 1)
  end

  def skipped!
    update!(state: "skipped")
  end
end
