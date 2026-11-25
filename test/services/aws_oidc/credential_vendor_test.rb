# frozen_string_literal: true

require "test_helper"

module AwsOidc
  class CredentialVendorTest < ActiveSupport::TestCase
    setup do
      @world = aws_oidc_step_session
      @sts = FakeAwsOidcStsClient.new(region: "eu-west-1")
      # The app-owned seam, never Aws::STS (docs/testing.md R2).
      StsClient.stubs(:new).returns(@sts)
      @runtime = stub_container_runtime
    end

    test "an attached role is exchanged with a token naming the step, and the exchange is recorded" do
      with_feature(:aws_oidc, true) do
        issuance = vendor.call

        name, args = @sts.calls.first
        assert_equal :assume_role_with_web_identity, name
        assert_equal @world[:role].role_arn, args[:role_arn]
        assert_equal "flow-session-#{@world[:session].id}", args[:session_name]
        assert_equal 3600, args[:duration_seconds]

        payload = JWT.decode(args[:token], nil, false).first
        assert_equal "workflow:#{@world[:workflow].id}:step:#{@world[:step].id}", payload["sub"]
        assert_equal Issuer.url(@world[:integration]), payload["iss"]
        assert_equal [ @world[:session].id.to_s ], payload.dig(Token::TAGS_CLAIM, "principal_tags", "flow_session")

        assert_equal payload["sub"], issuance.subject
        assert_equal payload["jti"], issuance.jti
        assert_equal @world[:user], issuance.user
        assert_equal @world[:session].step_run, issuance.step_run
      end
    end

    test "the credential-process document carries the vended credentials" do
      with_feature(:aws_oidc, true) do
        doc = JSON.parse(vendor.to_credential_process_json)
        issuance = AwsOidcCredentialIssuance.last

        assert_equal 1, doc["Version"]
        assert_equal issuance.access_key_id, doc["AccessKeyId"]
        assert_equal issuance.secrets["secret_access_key"], doc["SecretAccessKey"]
        assert_equal issuance.secrets["session_token"], doc["SessionToken"]
        assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, doc["Expiration"])
      end
    end

    test "credentials are handed out again until they are close to expiring" do
      with_feature(:aws_oidc, true) do
        first = vendor.call

        assert_equal first, vendor.call
        assert_equal 1, @sts.calls.size

        travel_to(first.expires_at - CredentialVendor::REFRESH_SKEW + 1.second) do
          assert_not_equal first, vendor.call
        end
        assert_equal 2, @sts.calls.size
      end
    end

    test "the vended secrets join the session's redaction list" do
      with_feature(:aws_oidc, true) do
        secrets = vendor.call.secrets

        assert_includes Sessions::SecretRedactor.secret_values_for(@world[:session]), secrets["secret_access_key"]
        assert_includes Sessions::SecretRedactor.secret_values_for(@world[:session]), secrets["session_token"]
      end
    end

    test "the redaction list is written before the credentials leave" do
      with_feature(:aws_oidc, true) do
        secrets = vendor.call.secrets
        list = Base64.decode64(@runtime.fs[Sessions::SecretRegistry::LIST_PATH].lines.first.to_s)

        assert_includes [ secrets["secret_access_key"], secrets["session_token"] ], list
      end
    end

    test "nothing is returned when log redaction cannot be armed" do
      @runtime.fail_write(Sessions::SecretRegistry::LIST_PATH)

      with_feature(:aws_oidc, true) do
        assert_raises(ProviderError) { vendor.call }
      end
    end

    test "a role that is not attached to the step is refused" do
      world = aws_oidc_step_session(attach: false)

      with_feature(:aws_oidc, true) do
        assert_raises(NotEntitledError) { CredentialVendor.new(session: world[:session], role_name: "prod-diag").call }
      end
      assert_empty @sts.calls
    end

    test "an unknown role name is refused" do
      with_feature(:aws_oidc, true) do
        assert_raises(NotEntitledError) { CredentialVendor.new(session: @world[:session], role_name: "other").call }
      end
    end

    test "a session that is not a workflow step is refused" do
      @world[:session].update!(session_type: "agent_session")

      with_feature(:aws_oidc, true) do
        assert_raises(NotEntitledError) { vendor.call }
      end
    end

    test "a disconnected integration or a company without the flag gets nothing" do
      with_feature(:aws_oidc, false) do
        assert_raises(NotEntitledError) { vendor.call }
      end

      @world[:integration].update!(status: "inactive")
      with_feature(:aws_oidc, true) do
        assert_raises(NotEntitledError) { vendor.call }
      end
      assert_empty @sts.calls
    end

    test "a role attached to the workflow's base list reaches every step" do
      @world[:step].update!(aws_oidc_role_ids: [])
      @world[:workflow].update!(config: @world[:workflow].config.merge("base_aws_oidc_role_ids" => [ @world[:role].id ]))

      with_feature(:aws_oidc, true) do
        assert_equal @world[:role], vendor.call.aws_oidc_role
      end
    end

    test "inheriting every project resource does not hand out roles" do
      @world[:step].update!(aws_oidc_role_ids: [])
      @world[:workflow].update!(config: @world[:workflow].config.merge("inherit_all_project_resources" => true))

      with_feature(:aws_oidc, true) do
        assert_raises(NotEntitledError) { vendor.call }
      end
    end

    test "an STS refusal comes out as the translated error and records nothing" do
      @sts.raise_on = { assume_role_with_web_identity: TrustPolicyError.new("not authorized") }

      with_feature(:aws_oidc, true) do
        assert_raises(TrustPolicyError) { vendor.call }
      end
      assert_equal 0, AwsOidcCredentialIssuance.count
    end

    private

    def vendor
      CredentialVendor.new(session: @world[:session], role_name: "prod-diag")
    end
  end
end
