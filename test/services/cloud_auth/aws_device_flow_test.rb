# frozen_string_literal: true

require "test_helper"

module CloudAuth
  # In-flight device-authorization state lives in Rails.cache (same pattern as
  # Oauth::State); the test env is :null_store, so swap in a real store.
  class AwsDeviceFlowTest < ActiveSupport::TestCase
    setup do
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @other = create(:user, company: @company)
      @sso = FakeAwsSsoClient.new(region: "us-west-2")
      @catalog = nil
      factory = @catalog_factory = lambda do |**args|
        @catalog = FakeAwsModelCatalog.new(**args)
        @catalog.profiles = @catalog_profiles if @catalog_profiles
        @catalog.raise_on_list = @catalog_raises if @catalog_raises
        @catalog
      end
      @flow = AwsDeviceFlow.new(user: @user, company: @company, client: @sso, catalog_factory: factory)
    end

    START_URL = "https://example.awsapps.com/start"

    # == start ==

    test "start opens a device authorization and returns the prefilled verification link" do
      started = start_flow

      assert started.handle.present?
      assert_equal "QCFK-N451", started.user_code
      assert_includes started.verification_uri_complete, "user_code=QCFK-N451"
      assert @sso.called?(:register_client)
      assert_equal START_URL, @sso.last_call(:start_device_authorization)[:args][:start_url]
    end

    test "start requires a start url and an identity center region" do
      assert_raises(ArgumentError) { @flow.start(start_url: "", sso_region: "us-west-2") }
      assert_raises(ArgumentError) { @flow.start(start_url: START_URL, sso_region: "") }
    end

    # == poll ==

    test "poll reports pending until the user approves, then returns their accounts" do
      @sso.pending_polls = 1
      started = start_flow

      pending = @flow.poll(handle: started.handle)
      assert_instance_of AwsDeviceFlow::Pending, pending
      assert_equal 5, pending.interval

      approved = @flow.poll(handle: started.handle)
      assert_instance_of AwsDeviceFlow::Approved, approved
      assert_equal [ "111122223333" ], approved.accounts.map(&:account_id)
      assert_equal [ "BedrockUser" ], approved.accounts.first.roles
    end

    test "poll does not redeem the device code twice once approved" do
      started = start_flow
      @flow.poll(handle: started.handle)
      @flow.poll(handle: started.handle)

      assert_equal 1, @sso.call_count(:create_token)
    end

    test "poll on an unknown or expired handle raises ExpiredError" do
      assert_raises(ExpiredError) { @flow.poll(handle: "nope") }
    end

    test "another user cannot poll someone else's handle" do
      started = start_flow

      assert_raises(DeniedError) do
        AwsDeviceFlow.new(user: @other, company: @company, client: @sso).poll(handle: started.handle)
      end
    end

    # == finish ==

    test "finish writes an awsBedrock block pointing at the credential_process helper" do
      credential = complete_flow

      bedrock = credential.config_data.fetch("awsBedrock")
      assert_equal "us-east-1", bedrock["region"]
      assert_equal AwsDeviceFlow::DEFAULT_PROFILE, bedrock["profile"]
      assert_equal AwsDeviceFlow::CREDENTIAL_PROCESS_PATH, bedrock["credential_process"]
    end

    # The container never logs in on this path, so it must not receive login material.
    # "sso_session" is what makes the adapter render an [sso-session] block, and it is
    # reserved for the in-container fallback.
    test "finish stores identity center details server-side and never as sso_session" do
      bedrock = complete_flow.config_data.fetch("awsBedrock")

      assert_nil bedrock["sso_session"]
      idc = bedrock.fetch("identity_center")
      assert_equal START_URL, idc["start_url"]
      assert_equal "us-west-2", idc["sso_region"]
      assert_equal "111122223333", idc["account_id"]
      assert_equal "BedrockUser", idc["role_name"]
      assert_equal "fake-refresh-token", idc.dig("token", "refresh_token")
      assert_equal "fake-client-id", idc.dig("registration", "client_id")
    end

    test "the rendered container config carries the profile but no sso-session block" do
      files = Agents::ClaudeCodeAdapter.new.config_files(complete_flow.config_data)
      aws_config = files.fetch("/home/claude/.aws/config")

      assert_includes aws_config, "[profile #{AwsDeviceFlow::DEFAULT_PROFILE}]"
      assert_includes aws_config, "credential_process = #{AwsDeviceFlow::CREDENTIAL_PROCESS_PATH}"
      assert_not_includes aws_config, "sso-session"
      assert_not_includes aws_config, START_URL
    end

    # Bedrock becomes THE inference credential, so an Anthropic-side login goes: Claude Code
    # would ignore it anyway, and keeping it makes the active provider unknowable. Design
    # authorizes separately and stays.
    test "finish replaces an anthropic-side login and keeps the design token" do
      AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", {
        "claudeAiOauth" => { "accessToken" => "sk-ant-oat01-base" },
        "designOauth" => { "accessToken" => "sk-ant-design" }
      })

      config = complete_flow.config_data

      assert config["awsBedrock"].present?
      assert_nil config["claudeAiOauth"]
      assert_equal "sk-ant-design", config.dig("designOauth", "accessToken")
    end

    # A model pinned against the previous account does not exist in a new one, and
    # resolve_model would keep launching sessions on it until someone noticed.
    test "binding a different account clears the model the user had chosen" do
      credential = complete_flow
      credential.update!(metadata: { "default_model" => "arn:aws:bedrock:us-east-1:999:application-inference-profile/x" })
      @sso.accounts = [ { account_id: "999988887777", account_name: "Other", email: "o@example.com" } ]
      @sso.roles = { "999988887777" => %w[BedrockUser] }

      started = start_flow
      @flow.poll(handle: started.handle)
      @flow.finish(handle: started.handle, account_id: "999988887777", role_name: "BedrockUser", region: "us-east-1")

      assert_nil credential.reload.metadata["default_model"]
    end

    test "reconnecting the same account and role keeps the chosen model" do
      credential = complete_flow
      credential.update!(metadata: { "default_model" => "us.anthropic.claude-sonnet-4-6" })

      complete_flow

      assert_equal "us.anthropic.claude-sonnet-4-6", credential.reload.metadata["default_model"]
    end

    # Narrows Claude Code's own /model picker to what this account can invoke, so the list is
    # taken with the credentials this authorization just produced.
    test "finish records the models this account can actually invoke" do
      @catalog_profiles = [
        FakeAwsModelCatalog.system_profile(
          "us.anthropic.claude-opus-5", model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-opus-5"
        ),
        FakeAwsModelCatalog.system_profile(
          "us.anthropic.claude-3-sonnet-20240229-v1:0",
          model_arn: "arn:aws:bedrock:::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0"
        )
      ]

      block = complete_flow.config_data.fetch("awsBedrock")

      assert_equal [ "us.anthropic.claude-opus-5" ], block["available_models"],
                   "the surcharged legacy generation must not reach the picker"
    end

    # A permission set without bedrock:ListInferenceProfiles is common, and an unrestricted
    # picker is a far better outcome than a failed connect.
    test "a denied model list does not fail the connect" do
      @catalog_raises = DeniedError

      credential = nil
      assert_nothing_raised { credential = complete_flow }

      block = credential.config_data.fetch("awsBedrock")
      assert block["identity_center"].present?, "the connection itself must still be stored"
      assert_nil block["available_models"], "an unrestricted picker beats a failed connect"
    end

    # Bedrock spend is billed to the company whose credential holds the connection, so a
    # user who works for two companies connects each separately and neither overwrites
    # the other.
    test "the connection lands on the company the flow was opened for" do
      other_company = create(:company)
      create(:company_membership, user: @user, company: other_company)

      credential = complete_flow

      other_flow = AwsDeviceFlow.new(user: @user, company: other_company, client: @sso,
                                     catalog_factory: @catalog_factory)
      started = other_flow.start(start_url: START_URL, sso_region: "us-west-2")
      other_flow.poll(handle: started.handle)
      other = other_flow.finish(handle: started.handle, account_id: "111122223333",
                                role_name: "BedrockUser", region: "eu-central-1")

      assert_equal @company.id, credential.company_id
      assert_equal other_company.id, other.company_id
      assert_not_equal credential.id, other.id
      assert_equal "us-east-1", credential.reload.config_data.dig("awsBedrock", "region")
      assert_equal "eu-central-1", other.config_data.dig("awsBedrock", "region")
    end

    test "a flow with no company cannot be started" do
      assert_raises(ArgumentError) do
        AwsDeviceFlow.new(user: @user, company: nil, client: @sso)
          .start(start_url: START_URL, sso_region: "us-west-2")
      end
    end

    test "finish refuses an account or role the authorization did not grant" do
      started = start_flow
      @flow.poll(handle: started.handle)

      assert_raises(DeniedError) do
        @flow.finish(handle: started.handle, account_id: "999988887777",
                     role_name: "BedrockUser", region: "us-east-1")
      end
      assert_raises(DeniedError) do
        @flow.finish(handle: started.handle, account_id: "111122223333",
                     role_name: "AdministratorAccess", region: "us-east-1")
      end
    end

    test "finish before approval raises" do
      started = start_flow
      @sso.pending_polls = 1
      @flow.poll(handle: started.handle)

      assert_raises(Error) do
        @flow.finish(handle: started.handle, account_id: "111122223333",
                     role_name: "BedrockUser", region: "us-east-1")
      end
    end

    test "finish requires a bedrock region" do
      started = start_flow
      @flow.poll(handle: started.handle)

      assert_raises(ArgumentError) do
        @flow.finish(handle: started.handle, account_id: "111122223333",
                     role_name: "BedrockUser", region: "")
      end
    end

    test "finish consumes the handle so it cannot be replayed" do
      started = start_flow
      @flow.poll(handle: started.handle)
      @flow.finish(handle: started.handle, account_id: "111122223333",
                   role_name: "BedrockUser", region: "us-east-1")

      assert_raises(ExpiredError) { @flow.poll(handle: started.handle) }
    end

    test "cancel drops the in-flight authorization" do
      started = start_flow
      @flow.cancel(handle: started.handle)

      assert_raises(ExpiredError) { @flow.poll(handle: started.handle) }
    end

    # == error translation ==

    test "a denied authorization surfaces as a CloudAuth error" do
      started = start_flow
      @sso.raise_on = { create_token: DeniedError }

      assert_raises(DeniedError) { @flow.poll(handle: started.handle) }
    end

    private

    def start_flow
      @flow.start(start_url: START_URL, sso_region: "us-west-2")
    end

    def complete_flow
      started = start_flow
      @flow.poll(handle: started.handle)
      @flow.finish(handle: started.handle, account_id: "111122223333",
                   role_name: "BedrockUser", region: "us-east-1")
    end
  end
end
