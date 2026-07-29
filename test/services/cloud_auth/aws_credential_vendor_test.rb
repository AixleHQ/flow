# frozen_string_literal: true

require "test_helper"

module CloudAuth
  class AwsCredentialVendorTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @sso = FakeAwsSsoClient.new(region: "us-west-2")
    end

    # == guard rails ==

    test "raises NotConnectedError when this company has no claude_code credential" do
      assert_raises(NotConnectedError) { vendor.call }
    end

    test "raises NotConnectedError when the credential carries no AWS connection" do
      store({ "primaryApiKey" => "sk-ant-x" })

      assert_raises(NotConnectedError) { vendor.call }
    end

    test "raises NotVendableError for a bearer-token connection" do
      store({ "awsBedrock" => { "region" => "us-east-1", "bearer_token" => "bedrock-api-key-x" } })

      assert_raises(NotVendableError) { vendor.call }
    end

    # == happy path ==

    test "vends role credentials for the connected account and role" do
      connect

      vended = vendor.call

      assert_equal "ASIAFAKEFAKEFAKE", vended.access_key_id
      assert_equal "fake-session-token", vended.session_token
      call = @sso.last_call(:role_credentials)[:args]
      assert_equal "111122223333", call[:account_id]
      assert_equal "BedrockUser", call[:role_name]
      assert_equal "live-access-token", call[:access_token]
    end

    test "does not refresh while the stored access token is still fresh" do
      connect

      vendor.call

      assert_not @sso.called?(:refresh_token)
    end

    # == credential_process contract ==

    test "credential_process JSON uses an unquoted integer Version and RFC3339 Z expiration" do
      connect

      raw = vendor.to_credential_process_json

      assert_includes raw, '"Version":1'
      assert_not_includes raw, '"Version":"1"'
      parsed = JSON.parse(raw)
      assert_equal 1, parsed["Version"]
      assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, parsed["Expiration"])
      assert_equal %w[AccessKeyId Expiration SecretAccessKey SessionToken Version], parsed.keys.sort
    end

    # An Expiration further out than ~15 minutes matters: botocore re-invokes the helper
    # at T-15, so a short-lived blob would mean a round-trip on nearly every request.
    test "vended credentials are valid for well over the SDK refresh window" do
      connect

      assert_operator vendor.call.expiration, :>, 20.minutes.from_now
    end

    # == refresh ==

    test "refreshes an expiring access token and persists the new one" do
      credential = connect(token_expires_at: 1.minute.from_now)

      vended = vendor.call

      assert @sso.called?(:refresh_token)
      assert_equal "fake-access-token-refreshed",
                   @sso.last_call(:role_credentials)[:args][:access_token]
      stored = credential.reload.config_data.dig("awsBedrock", "identity_center", "token")
      assert_equal "fake-access-token-refreshed", stored["access_token"]
      assert vended.access_key_id.present?
    end

    test "a refresh response without a refresh token keeps the stored one" do
      credential = connect(token_expires_at: 1.minute.from_now)
      @sso.refresh_token_value = nil

      vendor.call

      stored = credential.reload.config_data.dig("awsBedrock", "identity_center", "token")
      assert_equal "live-refresh-token", stored["refresh_token"],
                   "losing the refresh token would silently end the connection"
    end

    # Time.zone.parse returns nil for garbage rather than raising, so this would crash
    # inside a credential resolve if the nil case were not handled.
    test "an unparseable token expiry is treated as expiring, not as a crash" do
      connect(token: {
        "access_token" => "live-access-token", "refresh_token" => "live-refresh-token",
        "expires_at" => "not-a-date"
      })

      vendor.call

      assert @sso.called?(:refresh_token)
    end

    test "a token with no recorded expiry is treated as expiring" do
      connect(token: { "access_token" => "live-access-token", "refresh_token" => "live-refresh-token" })

      vendor.call

      assert @sso.called?(:refresh_token)
    end

    # == terminal failures ==

    test "an expired client registration demands re-authorisation rather than refreshing" do
      connect(token_expires_at: 1.minute.from_now, registration_expires_at: 1.day.ago)

      assert_raises(InvalidRegistrationError) { vendor.call }
      assert_not @sso.called?(:refresh_token)
    end

    test "a missing refresh token raises ExpiredError" do
      connect(token: { "access_token" => "stale", "expires_at" => 1.minute.from_now.iso8601 })

      assert_raises(ExpiredError) { vendor.call }
    end

    test "a missing client registration raises InvalidRegistrationError" do
      connect(token_expires_at: 1.minute.from_now, registration: {})

      assert_raises(InvalidRegistrationError) { vendor.call }
    end

    private

    def vendor
      AwsCredentialVendor.new(
        credential: CredentialLookup.claude_code(user_id: @user.id, company_id: @company.id),
        client: @sso
      )
    end

    def store(config)
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", config)
    end

    def connect(token: nil, token_expires_at: 1.hour.from_now, registration: nil, registration_expires_at: 60.days.from_now)
      store({
        "awsBedrock" => {
          "region" => "us-east-1",
          "profile" => "aixle-bedrock",
          "credential_process" => "/usr/local/bin/aixle-aws-creds",
          "identity_center" => {
            "start_url" => "https://example.awsapps.com/start",
            "sso_region" => "us-west-2",
            "account_id" => "111122223333",
            "role_name" => "BedrockUser",
            "registration" => registration || {
              "client_id" => "live-client-id",
              "client_secret" => "live-client-secret",
              "expires_at" => registration_expires_at.iso8601
            },
            "token" => token || {
              "access_token" => "live-access-token",
              "refresh_token" => "live-refresh-token",
              "expires_at" => token_expires_at.iso8601
            }
          }
        }
      })
    end
  end
end
