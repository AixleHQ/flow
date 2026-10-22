# frozen_string_literal: true

# Canonical fake for Billing::MarketplaceSellerClient. Never stub
# ::Aws::MarketplaceMetering or ::Aws::STS directly (docs/testing.md §4, R2/R3):
# this application reaches the SaaS listing through one adapter, and the tests
# below it drive this.
#
#   client = FakeMarketplaceSellerClient.new
#   client.resolve_customer(registration_token: "tok")  # => a Customer
#   client.failure = Billing::MarketplaceSellerClient::InvalidToken
#   client.resolve_customer(registration_token: "tok")  # => raises it
#
# Kept interface-identical by
# test/services/billing/marketplace_seller_client_contract_test.rb.
class FakeMarketplaceSellerClient
  PRODUCT_CODE = "saastestproductcode00000"

  attr_reader :tokens
  attr_accessor :configured, :failure, :customer

  def initialize(configured: true)
    @configured = configured
    @tokens = []
    @customer = nil
  end

  def configured?
    @configured
  end

  # Answers the customer it was given, or a fresh one keyed on the token, so a
  # test that does not care about the licence does not have to build one. A
  # second call with the same token answers the same licence, as AWS does: a
  # buyer who registers twice is one agreement, not two.
  def resolve_customer(registration_token:)
    raise_failure!
    tokens << registration_token

    @customer || Billing::MarketplaceSellerClient::Customer.new(
      license_arn: license_arn_for(registration_token),
      aws_account_id: "111122223333",
      product_code: PRODUCT_CODE,
      agreement_id: "agmt-#{Digest::SHA256.hexdigest(registration_token.to_s)[0, 12]}",
      customer_identifier: nil
    )
  end

  def last_token = tokens.last

  private

  def license_arn_for(token)
    "arn:aws:license-manager:us-east-1:111122223333:license/l-#{Digest::SHA256.hexdigest(token.to_s)[0, 16]}"
  end

  def raise_failure!
    return if failure.blank?

    raise failure if failure.is_a?(Class)

    raise Billing::MarketplaceSellerClient::Error, failure
  end
end
