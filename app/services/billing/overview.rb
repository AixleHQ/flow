# frozen_string_literal: true

module Billing
  # What the billing tab shows a company's administrators: where the
  # subscription stands, and what the period under way has come to so far.
  class Overview
    def initialize(company, price: CardPrice.new)
      @company = company
      @price = price
    end

    attr_reader :company, :price

    def to_h
      {
        status: company.billing_status,
        period_starts_at: company.billing_period_starts_at,
        period_ends_at: company.billing_period_ends_at,
        cancels_at: company.billing_cancels_at,
        trial: trial,
        price: price_terms,
        provider: company.billing_provider,
        can_pay: price.client.configured?,
        has_subscription: company.stripe_subscription_id.present?,
        has_unpaid_invoice: company.billing_unpaid_invoice_url.present?,
        cancellation_reasons: BillingCancellation::REASONS
      }
    end

    private

    # The rate the page quotes, whatever state the subscription is in.
    def price_terms
      terms = price.terms
      return nil if terms.nil?

      { unit_amount_cents: terms[:unit_amount_cents].to_f, currency: terms[:currency],
        minutes_per_unit: terms[:minutes_per_unit] }
    end

    # The free trial, for a company still on it or stopped for spending it.
    def trial
      return nil unless company.billing_status.in?(%w[trialing allowance])

      { days: Trial.length_in_days(company), days_left: Trial.days_left(company), last_day: Trial.last_day(company).iso8601 }
    end
  end
end
