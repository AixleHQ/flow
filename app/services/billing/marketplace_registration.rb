# frozen_string_literal: true

module Billing
  # Turns the token AWS posts to our fulfilment URL into the licence row
  # everything else keys on.
  #
  # Idempotent on the licence: a buyer reaches the registration page again from
  # Manage subscriptions whenever they like, with a fresh token each time, and an
  # arrival that made a second workspace would split their data in two.
  class MarketplaceRegistration
    def initialize(client: MarketplaceSellerClient.new)
      @client = client
    end

    attr_reader :client

    def configured? = client.configured?

    # The adapter's errors come through unchanged: an expired token and a role
    # we cannot assume need different things said to different people.
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
      # Two tabs, one buyer. A failure with no row behind it is a real one.
      MarketplaceLicense.find_by(license_arn: customer.license_arn) || raise(e)
    end
  end
end
