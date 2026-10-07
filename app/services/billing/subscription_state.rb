# frozen_string_literal: true

module Billing
  # What this application reads off a Stripe subscription.
  #
  # Read from the hash, from both places each field has lived. API 2025-03-31
  # moved the billing period from the subscription onto its items, and the
  # version that shapes a webhook payload belongs to the endpoint, not to this
  # gem — ours were created on the account's default.
  SubscriptionState = Data.define(:id, :status, :period_starts_at, :period_ends_at, :cancels_at, :ended_at) do
    def self.from(object)
      data = (object.respond_to?(:to_hash) ? object.to_hash : object.to_h).deep_symbolize_keys
      item = data.dig(:items, :data, 0) || {}
      period_ends_at = at(item[:current_period_end] || data[:current_period_end])

      new(
        id: data[:id],
        status: data[:status].to_s,
        period_starts_at: at(item[:current_period_start] || data[:current_period_start]),
        period_ends_at: period_ends_at,
        cancels_at: at(data[:cancel_at]) || (data[:cancel_at_period_end] ? period_ends_at : nil),
        ended_at: at(data[:ended_at])
      )
    end

    def self.at(timestamp) = timestamp.present? ? Time.zone.at(timestamp.to_i) : nil

    def running? = %w[active trialing].include?(status)

    # Stripe is retrying a payment, or has given up and left the subscription
    # open (whichever the account's failed-payment setting chose).
    def unpaid? = %w[past_due unpaid].include?(status)

    def ended? = %w[canceled incomplete_expired].include?(status)
  end
end
