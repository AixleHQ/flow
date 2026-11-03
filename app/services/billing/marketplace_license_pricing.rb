# frozen_string_literal: true

module Billing
  # Writes onto a licence what AWS charges for it, read from the agreement's
  # accepted terms. Kept on the row rather than asked for on every page view:
  # a subscription that ended keeps the price it was billed at even after the
  # buyer moves to another offer, and the Billing tab never dials AWS.
  #
  # Asked whenever the agreement is read anyway -- at registration, and when an
  # event creates or amends the agreement -- so a private offer's price arrives
  # with the agreement that carries it.
  module MarketplaceLicensePricing
    # Nothing written when the terms cannot be read, or carry no price for the
    # metered dimension: the row keeps what it had, and the page shows minutes
    # without a sum.
    def self.record!(license, client:)
      pricing = client.agreement_pricing(agreement_id: license.agreement_id)
      rate = pricing&.rate_for(Meter::AwsMarketplaceSaas::DIMENSION)
      return license if rate.nil?

      license.update!(price_per_minute: rate, price_currency: pricing.currency)
      license
    end
  end
end
