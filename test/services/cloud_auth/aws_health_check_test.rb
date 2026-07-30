# frozen_string_literal: true

require "test_helper"

module CloudAuth
  class AwsHealthCheckTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @sso = FakeAwsSsoClient.new(region: "us-west-2")
      @probe = nil
    end

    test "reports not_connected when there is no AWS connection" do
      result = check.call

      assert_not_predicate result, :ok?
      assert_equal :not_connected, result.stage
    end

    # The connection checked is the acting company's, not "the user's": a connection made
    # for another company is billed there and is not this company's to probe.
    test "reports not_connected when the only connection belongs to another company" do
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)
      connect(company: other_company)

      assert_equal :not_connected, check.call.stage
    end

    test "reports ok when credentials vend and the model answers" do
      connect

      result = check.call

      assert_predicate result, :ok?
      assert_equal :ok, result.stage
      assert_equal "us.anthropic.claude-sonnet-4-6", result.model_id
    end

    test "probes the connection's pinned sonnet model when it has one" do
      connect(models: { "sonnet" => "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/abc" })

      check.call

      assert_equal [ "arn:aws:bedrock:us-east-1:111122223333:application-inference-profile/abc" ],
                   @probe.probed_models
    end

    # The stage is what lets the UI say "reconnect" instead of "check your model access".
    test "a dead connection fails at the credentials stage, never reaching bedrock" do
      connect(registration_expires_at: 1.day.ago, token_expires_at: 1.minute.from_now)

      result = check.call

      assert_not_predicate result, :ok?
      assert_equal :credentials, result.stage
      assert_equal "invalid_registration_error", result.error_code
      assert_nil @probe
    end

    # The provider's own wording is the point: it is what tells the user what to fix.
    test "an access-denied model failure surfaces the provider message verbatim" do
      connect
      @probe_failure = { code: "AccessDeniedException",
                         message: "User is not authorized to perform bedrock:InvokeModel" }

      result = check.call

      assert_not_predicate result, :ok?
      assert_equal :invoke, result.stage
      assert_equal "AccessDeniedException", result.error_code
      assert_equal "User is not authorized to perform bedrock:InvokeModel", result.error_message
    end

    test "the probe receives the vended credentials and the bedrock region" do
      connect

      check.call

      assert_equal "us-east-1", @probe.region
      assert_equal "ASIAFAKEFAKEFAKE", @probe.access_key_id
      assert_equal "fake-session-token", @probe.session_token
    end

    private

    def check
      factory = lambda do |**args|
        @probe = FakeAwsBedrockProbe.new(**args)
        @probe.failure = @probe_failure
        @probe
      end
      AwsHealthCheck.new(
        user: @user,
        company: @company,
        vendor: AwsCredentialVendor.new(
          credential: CredentialLookup.claude_code(user_id: @user.id, company_id: @company.id),
          client: @sso
        ),
        probe_factory: factory
      )
    end

    def connect(models: nil, token_expires_at: 1.hour.from_now, registration_expires_at: 60.days.from_now,
                company: @company)
      AgentCredential.from_artifacts(@user.id, company.id, "claude_code", {
        "awsBedrock" => {
          "region" => "us-east-1",
          "profile" => "aixle-bedrock",
          "credential_process" => "/usr/local/bin/aixle-aws-creds",
          "models" => models,
          "identity_center" => {
            "start_url" => "https://example.awsapps.com/start",
            "sso_region" => "us-west-2",
            "account_id" => "111122223333",
            "role_name" => "BedrockUser",
            "registration" => {
              "client_id" => "live-client-id",
              "client_secret" => "live-client-secret",
              "expires_at" => registration_expires_at.iso8601
            },
            "token" => {
              "access_token" => "live-access-token",
              "refresh_token" => "live-refresh-token",
              "expires_at" => token_expires_at.iso8601
            }
          }
        }.compact
      })
    end
  end
end
