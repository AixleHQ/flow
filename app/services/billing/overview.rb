# frozen_string_literal: true

module Billing
  # What the billing tab shows a company's administrators: where the
  # subscription stands, and what the period under way has come to so far.
  class Overview
    PRICE_CACHE_TTL = 1.hour

    def initialize(company, client: StripeClient.new)
      @company = company
      @client = client
    end

    attr_reader :company, :client

    def to_h
      {
        status: company.billing_status,
        period_starts_at: company.billing_period_starts_at,
        period_ends_at: company.billing_period_ends_at,
        cancels_at: company.billing_cancels_at,
        usage: usage,
        allowance: allowance,
        can_pay: client.configured?,
        has_unpaid_invoice: company.billing_unpaid_invoice_url.present?,
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
        worker_minutes: minutes.round(1).to_f,
        measured_until: last_hour && (last_hour + 1.hour),
        estimate: estimate(minutes)
      }
    end

    # Priced the way Stripe prices it, so the number does not promise less than
    # the invoice: the price can sell minutes in packs (`transform_quantity`),
    # rounded the way it says.
    def estimate(minutes)
      price = cached_price
      return nil if price.nil?

      unit_amount = BigDecimal((price[:unit_amount] || price[:unit_amount_decimal]).to_s)
      pack = price.dig(:transform_quantity, :divide_by).to_i
      units = pack.positive? ? packs(minutes / pack, price.dig(:transform_quantity, :round)) : minutes

      {
        amount_cents: (units * unit_amount).round.to_i,
        currency: price[:currency],
        unit_amount_cents: unit_amount.to_f,
        minutes_per_unit: pack.positive? ? pack : 1
      }
    rescue ArgumentError, TypeError
      nil
    end

    def packs(quantity, rounding) = rounding == "up" ? quantity.ceil : quantity.floor

    # One request per hour per installation rather than one per page view, and
    # an estimate that is simply absent while Stripe cannot be reached.
    def cached_price
      return nil unless client.configured?

      Rails.cache.fetch([ "billing/price", Settings.stripe&.price_id ], expires_in: PRICE_CACHE_TTL) do
        client.retrieve_price.to_hash.deep_symbolize_keys
      end
    rescue StripeClient::Error => e
      Rails.logger.warn("[Billing::Overview] price unavailable: #{e.message}")
      nil
    end

    # The free allowance, for a company still on it or stopped for spending it.
    def allowance
      return nil unless company.billing_status.in?(%w[trialing allowance])

      { hours: Trial.queue_hours, used_hours: Trial.used_hours(company).to_f }
    end
  end
end
