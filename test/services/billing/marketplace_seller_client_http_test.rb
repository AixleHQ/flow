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

  def stub_meter(body:, status: 200)
    stub_request(:post, METERING_ENDPOINT)
      .with(headers: { "X-Amz-Target" => "AWSMPMeteringService.BatchMeterUsage" })
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/x-amz-json-1.1" })
  end

  def usage(license_arn: LICENSE_ARN, quantity: 60)
    Billing::MarketplaceSellerClient::Usage.new(
      license_arn: license_arn, customer_aws_account_id: "444455556666", dimension: "worker_minute",
      quantity: quantity, occurred_at: Time.utc(2026, 10, 22, 9)
    )
  end

  # For a product on Concurrent Agreements AWS takes the licence and refuses a
  # product code; sending both keyings would bill the hour twice rather than be
  # refused, because the one-record-per-hour limit counts each separately.
  test "a usage record names the licence and carries no product code" do
    stub_meter(body: { "Results" => [
      { "UsageRecord" => { "LicenseArn" => LICENSE_ARN }, "MeteringRecordId" => "mr-1", "Status" => "Success" }
    ], "UnprocessedRecords" => [] })

    outcomes = Billing::MarketplaceSellerClient.new.batch_meter_usage([ usage ])

    assert_equal [ LICENSE_ARN ], outcomes.map(&:license_arn)
    assert outcomes.sole.accepted?
    assert_requested(:post, METERING_ENDPOINT) do |request|
      body = JSON.parse(request.body)
      record = body.fetch("UsageRecords").sole

      body["ProductCode"].nil? && record["LicenseArn"] == LICENSE_ARN &&
        record["Dimension"] == "worker_minute" && record["Quantity"] == 60 &&
        # Measured against the real listing: without it AWS answers
        # "CustomerIdentifier or CustomerAWSAccountId is required".
        record["CustomerAWSAccountId"] == "444455556666" &&
        record["CustomerIdentifier"].nil?
    end
  end

  # AWS: "the UsageRecord was invalid and not honored. A previously metered
  # UsageRecord had the same customer, dimension, and time, but a DIFFERENT
  # quantity." So it is neither acceptance nor something a retry can settle --
  # the quantity that lost will lose every time.
  test "a duplicate is not acceptance and is not worth retrying" do
    stub_meter(body: { "Results" => [
      { "UsageRecord" => { "LicenseArn" => LICENSE_ARN }, "MeteringRecordId" => nil, "Status" => "DuplicateRecord" }
    ], "UnprocessedRecords" => [] })

    outcome = Billing::MarketplaceSellerClient.new.batch_meter_usage([ usage ]).sole

    assert_not outcome.accepted?
    assert outcome.duplicate?
    assert_not outcome.retryable?
  end

  # A record AWS could not process comes back under its own key. Dropping it
  # would count an hour as delivered that nobody was charged for.
  test "records AWS could not process are reported, not discarded" do
    other = "arn:aws:license-manager:us-east-1:444455556666:license/l-other"
    stub_meter(body: {
      "Results" => [
        { "UsageRecord" => { "LicenseArn" => LICENSE_ARN }, "MeteringRecordId" => "mr-1", "Status" => "Success" }
      ],
      "UnprocessedRecords" => [ { "LicenseArn" => other, "Dimension" => "worker_minute", "Quantity" => 60 } ]
    })

    outcomes = Billing::MarketplaceSellerClient.new.batch_meter_usage([ usage, usage(license_arn: other) ])

    assert_equal 2, outcomes.size
    assert_equal [ false ], outcomes.reject(&:accepted?).map(&:accepted?)
    assert_equal other, outcomes.reject(&:accepted?).sole.license_arn
  end

  test "more than twenty-five records go in more than one call" do
    stub_meter(body: { "Results" => [], "UnprocessedRecords" => [] })

    usages = Array.new(Billing::MarketplaceSellerClient::BATCH_SIZE + 1) do |n|
      usage(license_arn: "arn:aws:license-manager:us-east-1:444455556666:license/l-#{n}")
    end
    Billing::MarketplaceSellerClient.new.batch_meter_usage(usages)

    assert_requested :post, METERING_ENDPOINT, times: 2
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
  # Reachable without credentials by design, so an empty POST is anyone's to
  # send. It must refuse like a stale link rather than raise out of the SDK.
  test "a missing token is refused here, before the SDK is asked" do
    assert_raises(Billing::MarketplaceSellerClient::InvalidToken) do
      Billing::MarketplaceSellerClient.new.resolve_customer(registration_token: nil)
    end

    assert_not_requested :post, METERING_ENDPOINT
  end
end
