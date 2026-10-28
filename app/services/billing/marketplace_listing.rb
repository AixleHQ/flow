# frozen_string_literal: true

module Billing
  # Where a buyer is sent to act on the subscription in AWS. Two places, for
  # two states: the subscription library manages one that is running, and the
  # listing's own page is where a new one is taken out -- the library shows an
  # ended subscription and offers nothing to do about it.
  module MarketplaceListing
    SUBSCRIPTIONS_URL = "https://aws.amazon.com/marketplace/library"

    def self.subscriptions_url = SUBSCRIPTIONS_URL

    def self.listing_url
      ::Settings.aws_marketplace&.saas&.listing_url.presence || SUBSCRIPTIONS_URL
    end
  end
end
