# frozen_string_literal: true

# One AWS Marketplace agreement for the SaaS listing, and the company it bought
# a workspace for.
#
# The licence is the identity, not the customer and not the AWS account: under
# Concurrent Agreements one account may hold several live agreements for the
# same product, and `CustomerIdentifier` is no longer populated at all. Two
# arrivals from one AWS account carrying different licences are two purchases
# and get two workspaces; two carrying the same licence are one purchase and
# must land on the same one.
class MarketplaceLicense < ApplicationRecord
  belongs_to :company, optional: true

  # Driven entirely by what AWS tells us, so these are not an AASM lifecycle
  # anybody here may move through: nothing in the product advances a licence.
  #
  #   pending  resolved at registration, not yet confirmed. Metering records
  #            sent now are discarded by AWS, so nothing may be sent.
  #   active   AWS has confirmed the agreement and accepts metering.
  #   ending   the agreement is closing and roughly one hour remains to report
  #            the last of its usage.
  #   ended    over. AWS accepts nothing further.
  STATES = %w[pending active ending ended].freeze

  validates :license_arn, presence: true, uniqueness: true
  validates :customer_aws_account_id, presence: true
  validates :product_code, presence: true
  validates :subscription_state, inclusion: { in: STATES }
  validates :company_id, uniqueness: true, allow_nil: true

  scope :bound, -> { where.not(company_id: nil) }
  # A subscription nobody has registered against. Visible on purpose: somebody is
  # being billed and has no way in, and the first report of it must not be theirs.
  scope :unregistered, -> { where(company_id: nil).where.not(subscription_state: "ended") }

  def pending? = subscription_state == "pending"
  def active? = subscription_state == "active"
  def ending? = subscription_state == "ending"
  def ended? = subscription_state == "ended"

  def bound? = company_id.present?

  # Whether AWS would accept usage for this licence now. `ending` still counts:
  # the hour it allows is exactly when the last of the usage has to go.
  def meterable? = bound? && (active? || ending?)
end
