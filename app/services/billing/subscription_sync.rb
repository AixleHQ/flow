# frozen_string_literal: true

module Billing
  # Reads every paying company's subscription back from Stripe.
  #
  # For companies that were paying before the billing period was recorded, and
  # for any whose webhooks went astray. It writes dates and the card setting
  # only: whether a company runs stays the webhooks' to decide.
  class SubscriptionSync
    def initialize(client: StripeClient.new)
      @client = client
    end

    attr_reader :client

    def call
      Company.billing_billable.where.not(stripe_subscription_id: nil).find_each.map { |company| sync(company) }
    end

    def sync(company)
      subscription = SubscriptionState.from(client.adopt_subscription(subscription_id: company.stripe_subscription_id))
      if subscription.running?
        company.update!(billing_period_starts_at: subscription.period_starts_at,
                        billing_period_ends_at: subscription.period_ends_at,
                        billing_cancels_at: subscription.cancels_at)
      end
      [ company.id, subscription.status ]
    rescue StripeClient::Error => e
      [ company.id, "failed: #{e.message}" ]
    end
  end
end
