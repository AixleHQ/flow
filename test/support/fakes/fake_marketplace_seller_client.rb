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

  attr_reader :tokens, :recorded, :metered, :refusals
  attr_accessor :configured, :failure, :customer

  def initialize(configured: true)
    @configured = configured
    @tokens = []
    @customer = nil
    @recorded = []
    @metered = []
    @refusals = {}
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

  # One Outcome per record, as AWS answers. A licence already metered for an
  # hour comes back DuplicateRecord rather than failing, which is what makes
  # replaying a whole hour safe.
  def batch_meter_usage(usages)
    raise_failure!
    return [] if usages.empty?

    usages.map do |usage|
      key = [ usage.license_arn, usage.occurred_at, usage.dimension ]
      status = metered.include?(key) ? Billing::MarketplaceSellerClient::DUPLICATE : status_for(usage)
      metered << key

      recorded << usage if status == Billing::MarketplaceSellerClient::SUCCESS
      Billing::MarketplaceSellerClient::Outcome.new(
        license_arn: usage.license_arn, status: status,
        metering_record_id: status == Billing::MarketplaceSellerClient::SUCCESS ? "mr-#{recorded.size}" : nil
      )
    end
  end

  # Make one licence come back refused, as AWS does for one it has never heard of.
  def refuse(license_arn, status: "InvalidLicense")
    refusals[license_arn] = status
  end

  private

  def status_for(usage)
    refusals.fetch(usage.license_arn, Billing::MarketplaceSellerClient::SUCCESS)
  end

  def license_arn_for(token)
    "arn:aws:license-manager:us-east-1:111122223333:license/l-#{Digest::SHA256.hexdigest(token.to_s)[0, 16]}"
  end

  def raise_failure!
    return if failure.blank?

    raise failure if failure.is_a?(Class)

    raise Billing::MarketplaceSellerClient::Error, failure
  end
end
