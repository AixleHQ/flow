# frozen_string_literal: true

require "test_helper"

# What the adapter actually sends and reads, against realistic payloads.
#
# The fake cannot catch a misread field — it answers whatever shape it was
# written to answer — so the translation from the wire to Customer is pinned
# here, along with the error mapping a caller depends on to tell a role it
# cannot assume from a link the buyer let expire.
class Billing::MarketplaceSellerClientHttpTest < ActiveSupport::TestCase
  ROLE_ARN = "arn:aws:iam::111122223333:role/aixle-marketplace-saas"
  PRODUCT_CODE = "saasproduct0000000000000"
  LICENSE_ARN = "arn:aws:license-manager:us-east-1:444455556666:license/l-abc123"

  STS_ENDPOINT = "https://sts.us-east-1.amazonaws.com/"
  METERING_ENDPOINT = "https://metering.marketplace.us-east-1.amazonaws.com/"

  # The STS call that assumes the seller role is itself signed by whatever the
  # pod carries — IRSA in production. With nothing in the chain the SDK reaches
  # for the EC2 metadata service, so the chain is given something to find.
  AWS_CHAIN_ENV = { "AWS_ACCESS_KEY_ID" => "AKIAPODIDENTITY", "AWS_SECRET_ACCESS_KEY" => "pod-secret" }.freeze

  setup do
    @restore_env = AWS_CHAIN_ENV.keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    ENV.update(AWS_CHAIN_ENV)

    Settings.stubs(:aws_marketplace).returns(
      Hashie::Mash.new(
        saas: { product_code: PRODUCT_CODE, seller_role_arn: ROLE_ARN, region: "us-east-1" }
      )
    )
    stub_assume_role
  end

  teardown do
    @restore_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def stub_assume_role(status: 200)
    body = <<~XML
      <AssumeRoleResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
        <AssumeRoleResult>
          <Credentials>
            <AccessKeyId>AKIAEXAMPLE</AccessKeyId>
            <SecretAccessKey>secret</SecretAccessKey>
            <SessionToken>session-token</SessionToken>
            <Expiration>#{1.hour.from_now.utc.iso8601}</Expiration>
          </Credentials>
          <AssumedRoleUser>
            <Arn>arn:aws:sts::111122223333:assumed-role/aixle-marketplace-saas/session</Arn>
            <AssumedRoleId>AROAEXAMPLE:session</AssumedRoleId>
          </AssumedRoleUser>
        </AssumeRoleResult>
      </AssumeRoleResponse>
    XML

    stub_request(:post, STS_ENDPOINT).to_return(status: status, body: body)
  end

  def stub_resolve(body:, status: 200)
    stub_request(:post, METERING_ENDPOINT)
      .with(headers: { "X-Amz-Target" => "AWSMPMeteringService.ResolveCustomer" })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/x-amz-json-1.1" })
  end

  def resolved_body(overrides = {})
    {
      "CustomerIdentifier" => nil,
      "ProductCode" => PRODUCT_CODE,
      "CustomerAWSAccountId" => "444455556666",
      "LicenseArn" => LICENSE_ARN,
      "Metadata" => { "AgreementId" => "agmt-9xyz" }
    }.merge(overrides)
  end

  test "it assumes the seller role and reads the licence out of the answer" do
    stub_resolve(body: resolved_body)

    customer = Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")

    assert_equal LICENSE_ARN, customer.license_arn
    assert_equal "444455556666", customer.aws_account_id
    assert_equal PRODUCT_CODE, customer.product_code
    assert_equal "agmt-9xyz", customer.agreement_id
    # Concurrent Agreements: AWS sends null, and `nil` is what callers must see
    # rather than an empty string that reads as a value.
    assert_nil customer.customer_identifier

    assert_requested :post, STS_ENDPOINT, times: 1
    assert_requested(:post, METERING_ENDPOINT) do |request|
      request.body.include?("tok")
    end
  end

  test "the call is signed by the assumed role, not by whatever the pod carries" do
    stub_resolve(body: resolved_body)

    Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")

    assert_requested(:post, METERING_ENDPOINT) do |request|
      request.headers["Authorization"].to_s.include?("AKIAEXAMPLE") &&
        request.headers["X-Amz-Security-Token"] == "session-token"
    end
  end

  test "a token for somebody else's product is refused before anything is bound" do
    stub_resolve(body: resolved_body("ProductCode" => "someoneelsesproduct"))

    error = assert_raises(Billing::MarketplaceSellerClient::ForeignProduct) do
      Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")
    end
    assert_match(/someoneelsesproduct/, error.message)
  end

  test "an expired link is its own error, because the buyer has to start again" do
    stub_resolve(
      status: 400,
      body: { "__type" => "ExpiredTokenException", "message" => "token has expired" }
    )

    assert_raises(Billing::MarketplaceSellerClient::InvalidToken) do
      Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")
    end
  end

  # Re-stubbing the same request wins over the stub `setup` registered, so the
  # successful assume-role is replaced rather than reset away.
  test "a role we cannot assume is its own error, because it is ours to fix" do
    stub_request(:post, STS_ENDPOINT).to_return(
      status: 403,
      body: <<~XML
        <ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
          <Error>
            <Type>Sender</Type>
            <Code>AccessDenied</Code>
            <Message>not authorized to perform sts:AssumeRole</Message>
          </Error>
        </ErrorResponse>
      XML
    )
    stub_resolve(body: resolved_body)

    error = assert_raises(Billing::MarketplaceSellerClient::CredentialsError) do
      Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")
    end
    assert_match(/#{Regexp.escape(ROLE_ARN)}/, error.message)
  end

  test "any other refusal stays a plain adapter error" do
    stub_resolve(
      status: 400,
      body: { "__type" => "DisabledApiException", "message" => "the api is disabled" }
    )

    error = assert_raises(Billing::MarketplaceSellerClient::Error) do
      Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: "tok")
    end
    assert_not_kind_of Billing::MarketplaceSellerClient::InvalidToken, error
    assert_match(/DisabledApiException/, error.message)
  end
end
