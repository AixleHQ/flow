# frozen_string_literal: true

require "test_helper"

class Billing::MarketplaceRegistrationTest < ActiveSupport::TestCase
  setup do
    @client = FakeMarketplaceSellerClient.new
    @registration = Billing::MarketplaceRegistration.new(client: @client)
  end

  test "it writes the licence the token resolves to" do
    license = @registration.call(registration_token: "tok")

    assert_equal "tok", @client.last_token
    assert_equal "111122223333", license.customer_aws_account_id
    assert_equal FakeMarketplaceSellerClient::PRODUCT_CODE, license.product_code
    assert license.agreement_id.present?
    assert license.pending?, "a licence starts unconfirmed: AWS discards metering until it says otherwise"
    assert_not license.bound?
  end

  # The whole point. A buyer can come back from Manage subscriptions whenever
  # they like, with a fresh token every time.
  test "a second arrival for the same licence writes no second row" do
    first = @registration.call(registration_token: "tok")
    second = @registration.call(registration_token: "another-token-same-licence")

    assert_equal 2, @client.tokens.size
    assert_not_equal first.id, second.id, "the fake keys its licence on the token, so this should differ"

    # Now the real case: the same licence arriving twice.
    @client.customer = Billing::MarketplaceSellerClient::Customer.new(
      license_arn: first.license_arn, aws_account_id: "111122223333",
      product_code: FakeMarketplaceSellerClient::PRODUCT_CODE,
      agreement_id: "agmt-1", customer_identifier: nil
    )

    assert_no_difference -> { MarketplaceLicense.count } do
      again = @registration.call(registration_token: "a-third-token")

      assert_equal first.id, again.id
    end
  end

  test "a returning buyer does not lose the company their licence is already bound to" do
    license = @registration.call(registration_token: "tok")
    company = create(:company)
    license.update!(company: company, subscription_state: "active")

    @client.customer = Billing::MarketplaceSellerClient::Customer.new(
      license_arn: license.license_arn, aws_account_id: "111122223333",
      product_code: FakeMarketplaceSellerClient::PRODUCT_CODE,
      agreement_id: "agmt-1", customer_identifier: nil
    )
    again = @registration.call(registration_token: "fresh")

    assert_equal company, again.company
    assert again.active?, "registering again must not undo what AWS told us"
  end

  test "the offer type is kept once seen and not cleared by an arrival that is silent about it" do
    license = @registration.call(registration_token: "tok", offer_type: "free-trial")

    assert_equal "free-trial", license.registered_offer_type

    @client.customer = Billing::MarketplaceSellerClient::Customer.new(
      license_arn: license.license_arn, aws_account_id: "111122223333",
      product_code: FakeMarketplaceSellerClient::PRODUCT_CODE,
      agreement_id: "agmt-1", customer_identifier: nil
    )
    again = @registration.call(registration_token: "fresh")

    assert_equal "free-trial", again.registered_offer_type
  end

  # The caller has to be able to tell these apart: one sends the buyer back to
  # AWS, the other is ours and says nothing useful to them.
  test "the adapter's errors come through unchanged" do
    @client.failure = Billing::MarketplaceSellerClient::InvalidToken
    assert_raises(Billing::MarketplaceSellerClient::InvalidToken) { @registration.call(registration_token: "tok") }

    @client.failure = Billing::MarketplaceSellerClient::CredentialsError
    assert_raises(Billing::MarketplaceSellerClient::CredentialsError) { @registration.call(registration_token: "tok") }

    assert_equal 0, MarketplaceLicense.count
  end
end
