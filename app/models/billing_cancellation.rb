# frozen_string_literal: true

# An administrator stopping a company's subscription, and why. `cancels_at` is
# when it ended — or, for one made while cancelling waited for the period's end,
# when it was due to. Kept after a resume so the reasons survive for analytics.
class BillingCancellation < ApplicationRecord
  # Stripe's own `cancellation_details.feedback` values, so the same answer is
  # readable in its dashboard and in ours without a mapping between them.
  REASONS = %w[
    too_expensive missing_features unused switched_service
    too_complex low_quality customer_service other
  ].freeze

  COMMENT_MAX = 1000

  # nil on a cancellation made before the final invoice was settled here.
  # `cancelling` is one recorded before Stripe has been told: the subscription
  # named in `stripe_subscription_id` is still to be stopped from the job.
  SETTLEMENT_STATES = %w[cancelling settling settled failed].freeze

  belongs_to :company
  belongs_to :user, optional: true

  validates :reason, inclusion: { in: REASONS }, allow_nil: true
  validates :comment, length: { maximum: COMMENT_MAX }
  validates :cancels_at, presence: true
  validates :settlement_state, inclusion: { in: SETTLEMENT_STATES }, allow_nil: true

  scope :pending, -> { where(resumed_at: nil) }

  def cancelling? = settlement_state == "cancelling"
  def settling? = settlement_state == "settling"

  # Hour => worker-seconds, as the meter keys an hour: the capacity this
  # company was offered that Stripe had not been sent when it cancelled.
  def final_usage_by_hour
    final_usage.to_h { |hour, seconds| [ Time.iso8601(hour).utc, seconds.to_i ] }
  end
end
