# frozen_string_literal: true

# One notification AWS sent about a subscription, kept rather than acted on and
# forgotten.
#
# It is kept for two reasons, and the second is the one that costs money if it
# is missed. The obvious one is that SQS delivers at least once and in no
# particular order, so an event has to be recognisable as one already seen.
#
# The other is that an event can arrive before there is anything to apply it to.
# `Purchase Agreement Created` fires when the buyer subscribes, and the licence
# row is written when they reach the fulfilment page, which may be minutes
# later or never. Applied and dropped, such an event leaves a paying customer
# unbilled; held here, it is applied the moment the licence appears.
class MarketplaceSubscriptionEvent < ApplicationRecord
  belongs_to :marketplace_license, optional: true

  validates :event_id, presence: true, uniqueness: true
  validates :detail_type, presence: true
  validates :occurred_at, presence: true

  scope :unapplied, -> { where(applied_at: nil) }
  # Oldest first: the order AWS says they happened in, which is not the order
  # the queue hands them over in.
  scope :in_order, -> { order(:occurred_at, :id) }

  # Everything still waiting for the licence it names to exist. Matched on
  # either key, because agreement events carry no licence ARN and licence events
  # carry no agreement of their own that we store.
  scope :awaiting, ->(license) {
    unapplied.where(license_arn: license.license_arn)
             .or(unapplied.where(agreement_id: license.agreement_id.presence))
  }

  def applied? = applied_at.present?

  # `metered` is what the final meter sent, when this event was the one that
  # ran it. Nil for every other event, which is most of them.
  def applied!(license, metered: nil)
    update!(marketplace_license: license, applied_at: Time.current, failure: nil, metered: metered.presence)
  end

  # Left unapplied deliberately: a failure that clears is retried by the next
  # sweep, and one that does not is a row somebody can look at.
  def failed!(message)
    update!(failure: message.to_s.truncate(500))
  end
end
