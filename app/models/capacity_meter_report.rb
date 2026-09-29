# frozen_string_literal: true

class CapacityMeterReport < ApplicationRecord
  STATES = %w[pending reported failed skipped].freeze

  # AWS Marketplace rejects a record more than six hours after the event. The
  # replay window is the same number, so an hour that failed is retried by the
  # next few runs and then abandoned rather than retried forever against an
  # endpoint that will never accept it.
  REPLAY_WINDOW = 6.hours

  validates :provider, presence: true
  validates :period_start, presence: true, uniqueness: { scope: :provider }
  validates :quantity_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :state, inclusion: { in: STATES }

  scope :unsent, -> { where(state: %w[pending failed]) }
  scope :replayable, ->(now) { unsent.where(period_start: (now - REPLAY_WINDOW)...) }

  # What a provider is sent, and what anyone reads. Exact to the second, so a
  # provider that accepts a fraction is given one.
  def quantity_minutes = (BigDecimal(quantity_seconds) / 60).round(4)

  # Per company, in the same unit.
  def breakdown_minutes
    breakdown.transform_values { |value| (BigDecimal(value.to_s) / 60).round(4) }
  end

  def reported!(external_id)
    update!(state: "reported", external_id: external_id, error: nil, reported_at: Time.current)
  end

  def failed!(message)
    update!(state: "failed", error: message.to_s.truncate(1000), attempts: attempts + 1)
  end
end
