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
        usage: usage,
        trial: trial,
        price: price_terms,
        provider: company.billing_provider,
        can_pay: price.client.configured?,
        has_subscription: company.stripe_subscription_id.present?,
        has_unpaid_invoice: company.billing_unpaid_invoice_url.present?,
        final_invoice: final_invoice,
        cancellation_reasons: BillingCancellation::REASONS
      }
    end

    private

    # Read from our own ledger, which is what the meter sends Stripe: the same
    # minutes, an hour behind at most, since an hour is recorded once it closes.
    def usage
      return nil unless company.billing_active? && company.billing_period_starts_at

      rows = CompanyCapacityUsage.where(company_id: company.id).since(company.billing_period_starts_at)
      minutes = BigDecimal(rows.sum(:quantity_seconds)) / 60
      last_hour = rows.maximum(:period_start)

      {
        worker_minutes: minutes.round.to_f,
        measured_until: last_hour && (last_hour + 1.hour),
        estimate: price.estimate(minutes)
      }
    end

    # The rate the page quotes, whatever state the subscription is in.
    def price_terms
      terms = price.terms
      return nil if terms.nil?

      { unit_amount_cents: terms[:unit_amount_cents].to_f, currency: terms[:currency],
        minutes_per_unit: terms[:minutes_per_unit] }
    end

    # The invoice the last cancellation settles. `settling` while its usage is
    # still on its way to Stripe; the page asks again until it is not.
    def final_invoice
      return nil unless company.billing_status == "canceled"

      cancellation = company.billing_cancellations.where.not(settlement_state: nil).order(:created_at).last
      cancellation && { state: cancellation.settlement_state, url: cancellation.final_invoice_url }
    end

    # The free trial, for a company still on it or stopped for spending it.
    def trial
      return nil unless company.billing_status.in?(%w[trialing allowance])

      { days: Trial.length_in_days(company), days_left: Trial.days_left(company), last_day: Trial.last_day(company).iso8601 }
    end
  end
end
