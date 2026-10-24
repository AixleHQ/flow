# frozen_string_literal: true

# One AWS Marketplace agreement for the SaaS listing, and the company it bought.
#
# Keyed on the licence rather than the customer or the AWS account: under
# Concurrent Agreements one account may hold several live agreements for the same
# product, and `CustomerIdentifier` is no longer populated at all.
class MarketplaceLicense < ApplicationRecord
  # State machine (pending -> active, close, finish); `ended` is terminal.
  include MarketplaceLicenseStateMachine

  belongs_to :company, optional: true

  REGISTRATION_VALID_FOR = 15.minutes
  # Carries the licence from the POST AWS makes to the GET that follows it; the
  # POST holds no session to put it in (SameSite withholds the cookie).
  generates_token_for :registration, expires_in: REGISTRATION_VALID_FOR

  #   pending  resolved at registration; AWS discards metering sent now
  #   active   confirmed, and metering is accepted
  #   ending   closing, with about one hour left to report the last usage
  #   ended    over; AWS accepts nothing further
  #
  # Which moves are legal is MarketplaceLicenseStateMachine's; this list is what
  # the column itself will hold, so a write that goes round the machine still
  # cannot invent a state.
  STATES = %w[pending active ending ended].freeze

  validates :license_arn, presence: true, uniqueness: true
  validates :customer_aws_account_id, presence: true
  validates :product_code, presence: true
  validates :subscription_state, inclusion: { in: STATES }
  validates :company_id, uniqueness: true, allow_nil: true

  scope :bound, -> { where.not(company_id: nil) }
  # Somebody is being billed and has no way into the product. The first report of
  # that must not be theirs.
  scope :unregistered, -> { where(company_id: nil).where.not(subscription_state: "ended") }

  def bound? = company_id.present?

  # `ending` counts: the hour AWS allows after an agreement closes is exactly
  # when the last usage has to go.
  def meterable? = bound? && (active? || ending?)

  private

  # When AWS first confirmed the agreement. `||=` because `confirm` accepts its
  # own result, so a redelivered creation must not move the date.
  def set_subscribed_at
    self.subscribed_at ||= Time.current
  end

  # When the licence was finished here, which is within a minute or so of AWS
  # deprovisioning it rather than AWS's own timestamp. Nothing bills off this —
  # the last usage is bounded by the final meter's own `until_time` — so it is
  # a record of what happened, not an input to it.
  def set_ended_at
    self.ended_at = Time.current
  end
end
