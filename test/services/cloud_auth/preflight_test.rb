# frozen_string_literal: true

require "test_helper"

module CloudAuth
  class PreflightTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
    end

    # == nothing to report ==

    test "no credential at all is not a problem" do
      assert_empty preflight
    end

    test "nil user is not a problem" do
      assert_empty Preflight.broken_connections(user: nil, company: @company)
    end

    # Not using Bedrock is not a broken connection — only a rotten one is.
    test "a credential with no AWS connection is not a problem" do
      store({ "primaryApiKey" => "sk-ant-x" })

      assert_empty preflight
    end

    test "a healthy identity center connection is not a problem" do
      store({ "awsBedrock" => connection })

      assert_empty preflight
    end

    test "a bearer-token connection has nothing that can rot" do
      store({ "awsBedrock" => { "region" => "us-east-1", "bearer_token" => "bedrock-api-key-x" } })

      assert_empty preflight
    end

    # An expired access token is fine as long as it can be refreshed.
    test "an expired access token with a refresh token is still usable" do
      store({ "awsBedrock" => connection(token: {
        "access_token" => "stale", "refresh_token" => "r", "expires_at" => 1.hour.ago.iso8601
      }) })

      assert_empty preflight
    end

    # == broken ==

    test "an expired client registration demands reconnection" do
      store({ "awsBedrock" => connection(registration_expires_at: 1.day.ago) })

      entry = preflight.sole
      assert_equal "aws", entry[:provider]
      assert_equal "registration_expired", entry[:reason]
      assert_equal Preflight::CONNECT_PATH, entry[:connect_url]
      assert_equal "AWS 111122223333 / BedrockUser", entry[:name]
    end

    test "an expired token with no refresh token demands reconnection" do
      store({ "awsBedrock" => connection(token: {
        "access_token" => "stale", "expires_at" => 1.hour.ago.iso8601
      }) })

      assert_equal "reauthorization_required", preflight.sole[:reason]
    end

    test "a structurally incomplete connection reports not_connected" do
      [
        connection.except("identity_center"),
        connection(idc_overrides: { "account_id" => nil }),
        connection(idc_overrides: { "role_name" => nil }),
        connection(registration: {}),
        connection(token: {})
      ].each do |block|
        store({ "awsBedrock" => block })

        assert_equal "not_connected", preflight.sole[:reason],
                     "expected #{block.inspect} to report not_connected"
      end
    end

    # Credentials are per (user, company): a session billed to one company must not be
    # blocked by a rotten connection the same person has in another.
    test "a rotten connection in another company does not block this one" do
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)
      store({ "awsBedrock" => connection(registration_expires_at: 1.day.ago) }, company: other_company)
      store({ "awsBedrock" => connection })

      assert_empty preflight
      assert_equal "registration_expired", preflight(company: other_company).sole[:reason]
    end

    test "no company means nothing to check" do
      store({ "awsBedrock" => connection(registration_expires_at: 1.day.ago) })

      assert_empty preflight(company: nil)
    end

    test "an unparseable expiry is treated as expired rather than ignored" do
      store({ "awsBedrock" => connection(registration_expires_at: "not-a-date") })

      assert_equal "registration_expired", preflight.sole[:reason]
    end

    private

    def preflight(user: @user, company: @company)
      Preflight.broken_connections(user: user, company: company)
    end

    def store(config, company: @company)
      AgentCredential.find_by(user_id: @user.id, company_id: company.id, agent_type: "claude_code")&.destroy
      AgentCredential.from_artifacts(@user.id, company.id, "claude_code", config)
    end

    def connection(token: nil, registration: nil, registration_expires_at: 60.days.from_now, idc_overrides: {})
      expires = registration_expires_at.respond_to?(:iso8601) ? registration_expires_at.iso8601 : registration_expires_at
      {
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
            "expires_at" => expires
          },
          "token" => token || {
            "access_token" => "live-access-token",
            "refresh_token" => "live-refresh-token",
            "expires_at" => 1.hour.from_now.iso8601
          }
        }.merge(idc_overrides)
      }
    end
  end
end
