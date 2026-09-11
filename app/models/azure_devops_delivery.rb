# frozen_string_literal: true

# One Service Hook delivery, recorded before it is acted on.
#
# Azure promises nothing about delivery: duplicates and out-of-order arrivals are
# normal, and a subscription that fails repeatedly goes on probation or is
# disabled, losing events entirely. The unique index on
# (subscription, event_id) is what makes a redelivery a no-op instead of a
# second gate resolution.
class AzureDevopsDelivery < ApplicationRecord
  belongs_to :azure_devops_subscription

  validates :event_id, presence: true

  # Returns the new record, or nil when this event has already been seen. The
  # caller acknowledges either way — telling Azure a duplicate failed only earns
  # another redelivery and moves the subscription closer to probation.
  def self.record(subscription:, event_id:, event_type: nil)
    create!(
      azure_devops_subscription: subscription,
      event_id: event_id.to_s,
      event_type: event_type,
      received_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
