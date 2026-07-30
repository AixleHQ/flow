# frozen_string_literal: true

# Canonical fake for CloudAuth::AwsSsoClient — the one seam tests stub for the AWS
# Identity Center device flow. Never stub Aws::SSOOIDC / Aws::SSO directly
# (docs/testing.md §4, R2/R3). Kept interface-identical to the real client by
# test/services/cloud_auth/aws_sso_client_contract_test.rb.
#
# Scripting:
#   fake = FakeAwsSsoClient.new(region: "us-east-1")
#   fake.pending_polls = 2                    # create_token returns nil twice, then a Token
#   fake.accounts = [{ account_id: "1", account_name: "Prod", email: "a@b.c" }]
#   fake.roles = { "1" => %w[BedrockUser] }
#   fake.raise_on = { create_token: CloudAuth::DeniedError }
class FakeAwsSsoClient
  Registration = CloudAuth::AwsSsoClient::Registration
  DeviceAuthorization = CloudAuth::AwsSsoClient::DeviceAuthorization
  Token = CloudAuth::AwsSsoClient::Token
  Account = CloudAuth::AwsSsoClient::Account
  RoleCredentials = CloudAuth::AwsSsoClient::RoleCredentials

  attr_reader :region, :calls
  attr_accessor :pending_polls, :accounts, :roles, :raise_on, :refresh_token_value

  def initialize(region:)
    @region = region
    @calls = []
    @pending_polls = 0
    @accounts = [ { account_id: "111122223333", account_name: "Fake Account", email: "owner@example.com" } ]
    @roles = { "111122223333" => %w[BedrockUser] }
    @raise_on = {}
    @refresh_token_value = "fake-refresh-token"
  end

  def register_client(client_name:)
    record(:register_client, client_name: client_name)
    Registration.new(
      client_id: "fake-client-id",
      client_secret: "fake-client-secret",
      expires_at: 90.days.from_now
    )
  end

  def start_device_authorization(registration:, start_url:)
    record(:start_device_authorization, registration: registration, start_url: start_url)
    DeviceAuthorization.new(
      device_code: "fake-device-code",
      user_code: "QCFK-N451",
      verification_uri: "https://ssoins-fake.us-east-1.portal.amazonaws.com/#/device",
      # Deliberately a per-instance host, not device.sso.<region>.amazonaws.com — that
      # documented host does not resolve, so nothing may construct or parse this value.
      verification_uri_complete:
        "https://ssoins-fake.us-east-1.portal.amazonaws.com/#/device?user_code=QCFK-N451",
      interval: 5,
      expires_in: 600
    )
  end

  # Returns nil while the user has not approved yet, mirroring the real client's
  # handling of AuthorizationPending/SlowDown.
  def create_token(registration:, device_code:)
    record(:create_token, registration: registration, device_code: device_code)
    if @pending_polls.to_i.positive?
      @pending_polls -= 1
      return nil
    end
    build_token("fake-access-token")
  end

  def refresh_token(registration:, refresh_token:)
    record(:refresh_token, registration: registration, refresh_token: refresh_token)
    build_token("fake-access-token-refreshed")
  end

  def list_accounts(access_token:)
    record(:list_accounts, access_token: access_token)
    @accounts.map { |a| Account.new(**a) }
  end

  def list_account_roles(access_token:, account_id:)
    record(:list_account_roles, access_token: access_token, account_id: account_id)
    @roles.fetch(account_id, [])
  end

  def role_credentials(access_token:, account_id:, role_name:)
    record(:role_credentials, access_token: access_token, account_id: account_id, role_name: role_name)
    RoleCredentials.new(
      access_key_id: "ASIAFAKEFAKEFAKE",
      secret_access_key: "fake-secret",
      session_token: "fake-session-token",
      expiration: 1.hour.from_now
    )
  end

  # -- Introspection ---------------------------------------------------------

  def called?(name)
    @calls.any? { |c| c[:name] == name }
  end

  def call_count(name)
    @calls.count { |c| c[:name] == name }
  end

  def last_call(name)
    @calls.reverse.find { |c| c[:name] == name }
  end

  private

  def record(name, **args)
    @calls << { name: name, args: args }
    error = @raise_on[name]
    raise error, "FakeAwsSsoClient scripted failure for #{name}" if error
  end

  def build_token(access_token)
    Token.new(
      access_token: access_token,
      refresh_token: @refresh_token_value,
      expires_at: 1.hour.from_now
    )
  end
end
