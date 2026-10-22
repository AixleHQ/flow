# frozen_string_literal: true

# One AWS Marketplace agreement for the SaaS listing, and the company it bought.
#
# Keyed on the licence rather than the customer or the AWS account: under
# Concurrent Agreements one account may hold several live agreements for the same
# product, and `CustomerIdentifier` is no longer populated at all.
class MarketplaceLicense < ApplicationRecord
  belongs_to :company, optional: true

  REGISTRATION_VALID_FOR = 15.minutes
  # Carries the licence from the POST AWS makes to the GET that follows it; the
  # POST holds no session to put it in (SameSite withholds the cookie).
  generates_token_for :registration, expires_in: REGISTRATION_VALID_FOR

  # Nothing here moves it yet: rows are created `pending` by the column default
  # and the events that advance them arrive over SQS, which this does not read.
  #
  #   pending  resolved at registration; AWS discards metering sent now
  #   active   confirmed, and metering is accepted
  #   ending   closing, with about one hour left to report the last usage
  #   ended    over; AWS accepts nothing further
  #
  # When that reader is built this belongs in app/state_machines, and the reason
  # is the delivery rather than the shape: SQS does not order messages and
  # redelivers them, so a stale `active` can arrive after `ended`. Assigned, it
  # would be applied in silence -- and this column decides whether an hour is
  # billed, so applying it means charging for an hour nobody ran, or dropping
  # the last one. A machine refuses the transition instead.
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

  def pending? = subscription_state == "pending"
  def active? = subscription_state == "active"
  def ending? = subscription_state == "ending"
  def ended? = subscription_state == "ended"

  def bound? = company_id.present?

  # `ending` counts: the hour AWS allows after an agreement closes is exactly
  # when the last usage has to go.
  def meterable? = bound? && (active? || ending?)
end
