# frozen_string_literal: true

module Billing
  # Turns the token AWS posts to our fulfilment URL into the licence row
  # everything else keys on.
  #
  # Idempotent on the licence, which is most of the risk in this whole feature. A
  # buyer reaches the registration page again from Manage subscriptions whenever
  # they like and AWS issues a fresh token each time; an arrival that made a
  # second workspace would be the easiest bug here to write and the hardest to
  # unpick afterwards, because by then both have data in them.
  class MarketplaceRegistration
    def initialize(client: MarketplaceSellerClient.new)
      @client = client
    end

    attr_reader :client

    def configured? = client.configured?

    # Raises the adapter's errors unchanged: a token the buyer let expire and a
    # role we cannot assume need different things said to different people, and
    # flattening them here would take that choice away from the caller.
    def call(registration_token:, offer_type: nil)
      record(client.resolve_customer(registration_token: registration_token), offer_type)
    end

    private

    def record(customer, offer_type)
      license = MarketplaceLicense.find_or_initialize_by(license_arn: customer.license_arn)
      license.customer_aws_account_id = customer.aws_account_id
      license.product_code = customer.product_code
      license.agreement_id = customer.agreement_id if customer.agreement_id.present?
      license.customer_identifier = customer.customer_identifier if customer.customer_identifier.present?
      # Written when an arrival carries one, never cleared. A later arrival that
      # says nothing about the offer has not told us a trial ended; it has only
      # not mentioned it.
      license.registered_offer_type = offer_type if offer_type.present?
      license.save!
      license
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Two tabs, one buyer. Whoever lost the race reads the row the winner made;
      # a failure with no row behind it is a real one and goes up.
      MarketplaceLicense.find_by(license_arn: customer.license_arn) || raise(e)
    end
  end
end
