# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Cloud
      # Browser-driven AWS Identity Center device flow: create → poll → complete.
      class AwsConnectionsTest < ActionDispatch::IntegrationTest
        setup do
          Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
          @company = create(:company)
          @user = create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
          @sso = FakeAwsSsoClient.new(region: "us-west-2")
          # Stub the app-owned seams, never the vendor SDK (docs/testing.md R2). Completing a
          # connection also lists the account's models, so that seam needs a fake too.
          CloudAuth::AwsSsoClient.stubs(:new).returns(@sso)
          CloudAuth::AwsModelCatalog.stubs(:new).returns(
            FakeAwsModelCatalog.new(region: "us-east-1", access_key_id: "A",
                                    secret_access_key: "S", session_token: "T")
          )
          sign_in_as @user
        end

        START_URL = "https://example.awsapps.com/start"

        # == auth ==

        test "requires authentication" do
          reset!
          get api_v1_cloud_aws_connection_path

          assert_response :unauthorized
        end

        test "a viewer may read connection state but not connect" do
          reset!
          viewer = create(:user, :viewer, :onboarding_completed, company: @company,
                                          password: AuthHelper::TEST_PASSWORD)
          sign_in_as viewer

          get api_v1_cloud_aws_connection_path
          assert_response :success

          post api_v1_cloud_aws_connection_path, params: { start_url: START_URL, sso_region: "us-west-2" }
          assert_response :forbidden
        end

        # == show ==

        test "show reports no connection for a fresh user" do
          get api_v1_cloud_aws_connection_path

          assert_response :success
          refute response.parsed_body["connected"]
        end

        # == create ==

        test "create requires a start url and an identity center region" do
          post api_v1_cloud_aws_connection_path, params: { sso_region: "us-west-2" }
          assert_response :unprocessable_entity
          assert_equal "missing_parameter", response.parsed_body["error"]

          post api_v1_cloud_aws_connection_path, params: { start_url: START_URL }
          assert_response :unprocessable_entity
        end

        # The verification URL is passed through verbatim — never constructed. The
        # documented device.sso.<region> host does not resolve.
        test "create returns a handle and the prefilled verification url" do
          post api_v1_cloud_aws_connection_path, params: { start_url: START_URL, sso_region: "us-west-2" }

          assert_response :created
          body = response.parsed_body
          assert body["handle"].present?
          assert_equal "QCFK-N451", body["user_code"]
          assert_includes body["verification_url"], "user_code=QCFK-N451"
          assert_not_includes body["verification_url"], "device.sso."
        end

        # == poll ==

        test "poll reports pending until approval, then the granted accounts" do
          @sso.pending_polls = 1
          handle = start_flow

          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }
          assert_response :success
          assert_equal "pending", response.parsed_body["status"]

          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }
          assert_response :success
          body = response.parsed_body
          assert_equal "approved", body["status"]
          assert_equal "111122223333", body.dig("accounts", 0, "account_id")
          assert_equal [ "BedrockUser" ], body.dig("accounts", 0, "roles")
        end

        # 410 tells the UI to restart the flow rather than keep polling a dead handle.
        test "poll on a dead handle is gone, not pending" do
          post poll_api_v1_cloud_aws_connection_path, params: { handle: "nope" }

          assert_response :gone
        end

        test "poll requires a handle" do
          post poll_api_v1_cloud_aws_connection_path

          assert_response :unprocessable_entity
        end

        # == complete ==

        test "complete binds the chosen account and role and reports connected" do
          handle = start_flow
          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }

          post complete_api_v1_cloud_aws_connection_path,
               params: { handle: handle, account_id: "111122223333", role_name: "BedrockUser", region: "us-east-1" }

          assert_response :success
          body = response.parsed_body
          assert body["connected"]
          assert_equal "111122223333", body["account_id"]
          assert_equal "us-east-1", body["region"]
          assert_nil body["reason"]
        end

        test "complete refuses a role the authorization did not grant" do
          handle = start_flow
          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }

          post complete_api_v1_cloud_aws_connection_path,
               params: { handle: handle, account_id: "111122223333", role_name: "AdministratorAccess",
                         region: "us-east-1" }

          assert_response :forbidden
        end

        test "complete requires every binding parameter" do
          handle = start_flow
          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }

          post complete_api_v1_cloud_aws_connection_path,
               params: { handle: handle, account_id: "111122223333", role_name: "BedrockUser" }

          assert_response :unprocessable_entity
        end

        # == health ==

        test "health reports not_connected for a user with no connection" do
          post health_api_v1_cloud_aws_connection_path

          assert_response :success
          body = response.parsed_body
          refute body["ok"]
          assert_equal "not_connected", body["stage"]
        end

        # A failed probe is a successful diagnosis — the caller gets 200 and the reason,
        # not an error status it has to interpret.
        test "health answers 200 with the provider message when the probe fails" do
          check = mock("health_check")
          check.stubs(:call).returns(CloudAuth::AwsHealthCheck::Result.new(
                                      ok: false, stage: :invoke, model_id: "m",
                                      error_code: "AccessDeniedException",
                                      error_message: "not authorized to perform bedrock:InvokeModel"
                                    ))
          CloudAuth::AwsHealthCheck.stubs(:new).returns(check)

          post health_api_v1_cloud_aws_connection_path

          assert_response :success
          body = response.parsed_body
          refute body["ok"]
          assert_equal "invoke", body["stage"]
          assert_equal "not authorized to perform bedrock:InvokeModel", body["error_message"]
        end

        test "a viewer may not spend a token probing" do
          reset!
          viewer = create(:user, :viewer, :onboarding_completed, company: @company,
                                          password: AuthHelper::TEST_PASSWORD)
          sign_in_as viewer

          post health_api_v1_cloud_aws_connection_path

          assert_response :forbidden
        end

        # == destroy ==

        # Design authorizes separately from inference, so removing the AWS connection must not
        # cost the user their design login.
        test "destroy removes the AWS connection but keeps the design token" do
          AgentCredential.from_artifacts(@user.id, @company.id, "claude_code",
                                         { "designOauth" => { "accessToken" => "sk-ant-design" } })
          handle = start_flow
          post poll_api_v1_cloud_aws_connection_path, params: { handle: handle }
          post complete_api_v1_cloud_aws_connection_path,
               params: { handle: handle, account_id: "111122223333", role_name: "BedrockUser", region: "us-east-1" }

          delete api_v1_cloud_aws_connection_path

          assert_response :success
          refute response.parsed_body["connected"]
          config = AgentCredential.find_by(user_id: @user.id, company_id: @company.id, agent_type: "claude_code").config_data
          assert_nil config["awsBedrock"]
          assert_equal "sk-ant-design", config.dig("designOauth", "accessToken")
        end

        test "destroy is harmless when nothing is connected" do
          delete api_v1_cloud_aws_connection_path

          assert_response :success
        end

        private

        def start_flow
          post api_v1_cloud_aws_connection_path, params: { start_url: START_URL, sso_region: "us-west-2" }
          response.parsed_body.fetch("handle")
        end
      end
    end
  end
end
