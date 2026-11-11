# frozen_string_literal: true

module Billing
  # The metered price capacity is billed against, as Stripe prices it: the
  # price can sell minutes in packs (`transform_quantity`), rounded the way it
  # says, and an estimate must not promise less than the invoice will. Read once
  # an hour per installation rather than once per page view, and simply absent
  # while Stripe cannot be reached.
  class CardPrice
    CACHE_TTL = 1.hour

    def initialize(client: StripeClient.new)
      @client = client
    end

    attr_reader :client

    # The rate on the price, or nil while it cannot be read.
    def terms
      return @terms if defined?(@terms)

      @terms = read_terms
    end

    # What `minutes` come to, in packs, as the card is invoiced.
    def estimate(minutes)
      return nil if terms.nil?

      minutes = BigDecimal(minutes.to_s)
      pack = BigDecimal(terms[:minutes_per_unit])
      # A price that sells no pack bills the minutes as the meter sent them,
      # fractions included; rounding them here would promise less than the invoice.
      units = terms[:rounding] ? round(minutes / pack, terms[:rounding]) : minutes / pack

      {
        amount_cents: (units * terms[:unit_amount_cents]).round.to_i,
        currency: terms[:currency],
        unit_amount_cents: terms[:unit_amount_cents].to_f,
        minutes_per_unit: terms[:minutes_per_unit]
      }
    end

    private

    def round(quantity, rounding) = rounding == "up" ? quantity.ceil : quantity.floor

    def read_terms
      price = cached_price
      return nil if price.nil?

      pack = price.dig(:transform_quantity, :divide_by).to_i
      {
        unit_amount_cents: BigDecimal((price[:unit_amount] || price[:unit_amount_decimal]).to_s),
        currency: price[:currency],
        minutes_per_unit: pack.positive? ? pack : 1,
        rounding: price.dig(:transform_quantity, :round)
      }
    rescue ArgumentError, TypeError
      nil
    end

    def cached_price
      return nil unless client.configured?

      Rails.cache.fetch([ "billing/price", Settings.stripe&.price_id ], expires_in: CACHE_TTL) do
        client.retrieve_price.to_hash.deep_symbolize_keys
      end
    rescue StripeClient::Error => e
      Rails.logger.warn("[Billing::CardPrice] price unavailable: #{e.message}")
      nil
    end
  end
end
