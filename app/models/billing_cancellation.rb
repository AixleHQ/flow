# frozen_string_literal: true

# An administrator asking for a company's subscription to stop at the end of its
# billing period, and why. Kept after a resume so the reasons survive for
# analytics.
class BillingCancellation < ApplicationRecord
  # Stripe's own `cancellation_details.feedback` values, so the same answer is
  # readable in its dashboard and in ours without a mapping between them.
  REASONS = %w[
    too_expensive missing_features unused switched_service
    too_complex low_quality customer_service other
  ].freeze

  COMMENT_MAX = 1000

  belongs_to :company
  belongs_to :user, optional: true

  validates :reason, inclusion: { in: REASONS }, allow_nil: true
  validates :comment, length: { maximum: COMMENT_MAX }
  validates :cancels_at, presence: true

  scope :pending, -> { where(resumed_at: nil) }
end
