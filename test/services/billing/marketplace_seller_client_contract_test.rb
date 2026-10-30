# frozen_string_literal: true

require "test_helper"

# The adapter and its fake have to stay the same shape, or every test below the
# fake is testing something the application does not do.
class Billing::MarketplaceSellerClientContractTest < ActiveSupport::TestCase
  METHODS = %i[configured? resolve_customer batch_meter_usage].freeze

  def configure!(product_code: "saasproduct", seller_role_arn: "arn:aws:iam::111122223333:role/seller")
    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(
        saas: { product_code: product_code, seller_role_arn: seller_role_arn, region: "us-east-1" }
      )
    )
  end

  test "the fake answers every method the adapter does, with the same arguments" do
    METHODS.each do |name|
      real = Billing::MarketplaceSellerClient.instance_method(name)
      fake = FakeMarketplaceSellerClient.instance_method(name)

      assert_equal real.parameters.map { |kind, key| [ kind, key ] }, fake.parameters.map { |kind, key| [ kind, key ] },
                   "#{name} differs between Billing::MarketplaceSellerClient and its fake"
    end
  end

  test "the fake answers a Customer the adapter could have built" do
    customer = FakeMarketplaceSellerClient.new.resolve_customer(registration_token: "tok")

    assert_instance_of Billing::MarketplaceSellerClient::Customer, customer
    assert customer.license_arn.present?
    assert customer.aws_account_id.present?
    # Concurrent Agreements: AWS stops populating this, and nothing may key on it.
    assert_nil customer.customer_identifier
  end

  test "one token resolves to one licence however often it is presented" do
    client = FakeMarketplaceSellerClient.new
    first = client.resolve_customer(registration_token: "tok")
    second = client.resolve_customer(registration_token: "tok")

    assert_equal first.license_arn, second.license_arn
    assert_not_equal first.license_arn, client.resolve_customer(registration_token: "other").license_arn
  end

  # An installation that does not sell the listing has no role to assume and no
  # product to resolve against, and must not dial out at all.
  test "an installation with no listing configured refuses rather than dialling out" do
    configure!(product_code: nil, seller_role_arn: nil)
    client = Billing::MarketplaceSellerClient.new

    assert_not client.configured?
    error = assert_raises(Billing::MarketplaceSellerClient::Error) do
      client.resolve_customer(registration_token: "tok")
    end
    assert_match(/SaaS listing/, error.message)
  end

  test "a half-configured installation is not configured" do
    configure!(seller_role_arn: nil)
    assert_not Billing::MarketplaceSellerClient.new.configured?

    configure!(product_code: nil)
    assert_not Billing::MarketplaceSellerClient.new.configured?
  end

  test "an empty hour asks AWS for nothing, in the adapter and in the fake alike" do
    assert_empty FakeMarketplaceSellerClient.new.batch_meter_usage([])

    configure!
    assert_empty Billing::MarketplaceSellerClient.new.batch_meter_usage([])
  end

  # The error tree is the contract: a caller has to be able to tell a role it
  # cannot assume from a link the buyer let expire, because they send the person
  # to different places.
  test "every error this adapter raises is one of its own" do
    assert_operator Billing::MarketplaceSellerClient::CredentialsError, :<, Billing::MarketplaceSellerClient::Error
    assert_operator Billing::MarketplaceSellerClient::InvalidToken, :<, Billing::MarketplaceSellerClient::Error
    assert_operator Billing::MarketplaceSellerClient::ForeignProduct, :<, Billing::MarketplaceSellerClient::Error
  end
end
