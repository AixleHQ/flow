# frozen_string_literal: true

# One webhook delivery, recorded before it is acknowledged. Trackers promise
# nothing about duplicates, so the unique (subscription, dedup_key) index turns
# a redelivery into a no-op. Only identifiers and change hints are stored.
class TrackerDelivery < ApplicationRecord
  belongs_to :tracker_subscription

  validates :dedup_key, presence: true

  # The new record, or nil when this delivery was already seen.
  def self.record(subscription:, dedup_key:, notifications:)
    create!(tracker_subscription: subscription, dedup_key: dedup_key, notifications: notifications.map(&:to_h))
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def notification_objects
    notifications.map do |attributes|
      attributes = attributes.deep_symbolize_keys
      Trackers::Notification.build(**attributes.slice(*Trackers::Notification.members).merge(kind: attributes[:kind].to_sym))
    end
  end
end
