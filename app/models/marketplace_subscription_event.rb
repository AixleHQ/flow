# frozen_string_literal: true

# One notification AWS sent about a subscription, kept rather than acted on and
# forgotten. SQS delivers at least once and in no order, so an event has to be
# recognisable as one already seen -- and an event can arrive before there is
# anything to apply it to, because `Purchase Agreement Created` fires when the
# buyer subscribes and the licence row is written when they reach the fulfilment
# page. Dropped, such an event leaves a paying customer unbilled.
class MarketplaceSubscriptionEvent < ApplicationRecord
  belongs_to :marketplace_license, optional: true

  validates :event_id, presence: true, uniqueness: true
  validates :detail_type, presence: true
  validates :occurred_at, presence: true

  # How long the sweep keeps reconsidering an event it has nothing to apply to.
  # A buyer reaches the fulfilment page within minutes of subscribing, so a week
  # is generous for ours; what it bounds is everyone else's.
  SWEPT_FOR = 7.days

  scope :unapplied, -> { where(applied_at: nil) }
  # Oldest first: the order AWS says they happened in, which is not the order
  # the queue hands them over in.
  scope :in_order, -> { order(:occurred_at, :id) }

  # What the blind sweep looks at. The seller account's rule matches a source
  # and a detail type rather than a product, so this table receives the
  # agreement traffic of every listing that account sells -- none of which will
  # ever match a licence of ours, and all of which an unbounded sweep would
  # reconsider for ever.
  #
  # The rows are kept; only the looking stops, and only for the sweep.
  # #awaiting is unbounded, so a
  # licence that appears late still replays its own events when it is created.
  scope :worth_sweeping, -> { unapplied.where(occurred_at: SWEPT_FOR.ago..) }

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
  def applied!(license, metered: nil, receipts: {})
    update!(marketplace_license: license, applied_at: Time.current, failure: nil,
            metered: metered.presence, metered_receipts: receipts || {})
  end

  # Left unapplied deliberately: a failure that clears is retried by the next
  # sweep, and one that does not is a row somebody can look at.
  def failed!(message)
    update!(failure: message.to_s.truncate(500))
  end
end
