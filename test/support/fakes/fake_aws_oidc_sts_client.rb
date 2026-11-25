# frozen_string_literal: true

# Canonical fake for AwsOidc::StsClient — the one seam tests stub for the STS exchange.
# Never stub Aws::STS directly (docs/testing.md §4, R2/R3). Kept interface-identical to
# the real client by test/services/aws_oidc/sts_client_contract_test.rb.
#
# Scripting:
#   fake = FakeAwsOidcStsClient.new(region: "eu-west-1")
#   fake.raise_on = { assume_role_with_web_identity: AwsOidc::TrustPolicyError.new("denied") }
#   fake.calls  # => [[:assume_role_with_web_identity, { role_arn:, session_name:, token:, duration_seconds: }]]
class FakeAwsOidcStsClient
  Credentials = AwsOidc::StsClient::Credentials

  attr_reader :region, :calls
  attr_accessor :raise_on

  def initialize(region:)
    @region = region
    @calls = []
    @raise_on = {}
    @sequence = 0
  end

  def assume_role_with_web_identity(role_arn:, session_name:, token:, duration_seconds:)
    record(:assume_role_with_web_identity, role_arn: role_arn, session_name: session_name, token: token,
                                           duration_seconds: duration_seconds)
    @sequence += 1
    role_name = role_arn.split("/").last
    account = role_arn[/::(\d{12}):/, 1]
    Credentials.new(
      access_key_id: format("ASIAFAKE%012d", @sequence),
      secret_access_key: "fake-secret-#{@sequence}-#{SecureRandom.hex(8)}",
      session_token: "fake-session-token-#{@sequence}-#{SecureRandom.hex(16)}",
      expiration: Time.current + duration_seconds,
      assumed_role_arn: "arn:aws:sts::#{account}:assumed-role/#{role_name}/#{session_name}"
    )
  end

  def caller_arn(credentials:)
    record(:caller_arn, credentials: credentials)
    credentials.assumed_role_arn
  end

  private

  def record(name, **args)
    @calls << [ name, args ]
    error = @raise_on[name]
    raise error if error
  end
end
