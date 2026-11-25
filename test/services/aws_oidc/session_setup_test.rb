# frozen_string_literal: true

require "test_helper"

module AwsOidc
  # What reaches a step's container: the vending env, ~/.aws/config written once, and the
  # profiles named in the context file.
  class SessionSetupTest < ActiveSupport::TestCase
    setup do
      @world = aws_oidc_step_session
      @session = @world[:session]
      Rails.logger.stubs(:info)
    end

    test "a step with a role gets the vending env; a session without one gets none" do
      with_feature(:aws_oidc, true) do
        env = SessionSetup.container_env(@session, url: "http://platform/cloud/aws/credentials")

        assert_equal "http://platform/cloud/aws/credentials", env["AIXLE_CLOUD_CREDENTIALS_URL"]
        assert_equal CloudAuth::SessionKey.generate(@session), env["AIXLE_CLOUD_KEY"]

        bare = create(:terminal_session, :running, user: @world[:user], project: @world[:project])
        assert_empty SessionSetup.container_env(bare, url: "http://platform/cloud/aws/credentials")
      end
    end

    test "nothing is delivered while the flag is off" do
      with_feature(:aws_oidc, false) do
        assert_empty SessionSetup.roles(@session)
      end
    end

    test "one role with nothing else claiming the default chain is also the default profile" do
      file = SessionSetup.config_file([ @world[:role] ], default: true)

      assert_equal <<~INI, file
        [default]
        credential_process = /usr/local/bin/aixle-aws-creds --role prod-diag
        region = eu-west-1

        [profile prod-diag]
        credential_process = /usr/local/bin/aixle-aws-creds --role prod-diag
        region = eu-west-1
      INI
    end

    test "with two roles there is no default to guess" do
      second = create(:aws_oidc_role, integration: @world[:integration], name: "staging-rw")
      file = SessionSetup.config_file([ @world[:role], second ], default: true)

      assert_not_includes file, "[default]"
      assert_includes file, "[profile staging-rw]"
    end

    test "an assembly for a runtime without its own AWS config writes the role profiles" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code")
      credential = create(:agent_credential, user: @world[:user], company: @world[:company], agent_type: "claude_code")

      with_feature(:aws_oidc, true) do
        SessionContextService.new("ctr1", @session, runtime: runtime).assemble(credential: credential)
      end

      config = runtime.fs["/home/claude/.aws/config"]
      assert_includes config, "[default]"
      assert_includes config, "[profile prod-diag]"
      context = runtime.fs.find { |path, _| path.end_with?("CLAUDE.md") }&.last.to_s
      assert_includes context, "| `prod-diag` | `#{@world[:role].role_arn}` | 123456789012 | eu-west-1 |"
    end

    test "Claude Code on Bedrock keeps its own profile and gains the role's, with no default" do
      runtime = ContainerRuntime::FakeRuntime.new(agent_type: "claude_code")
      credential = create(:agent_credential, user: @world[:user], company: @world[:company], agent_type: "claude_code",
                                             config_data: { "awsBedrock" => {
                                               "region" => "us-east-1", "profile" => "aixle-bedrock",
                                               "credential_process" => "/usr/local/bin/aixle-aws-creds"
                                             } })

      with_feature(:aws_oidc, true) do
        SessionContextService.new("ctr1", @session, runtime: runtime).assemble(credential: credential)
      end

      config = runtime.fs["/home/claude/.aws/config"]
      assert_includes config, "[profile aixle-bedrock]"
      assert_includes config, "[profile prod-diag]"
      assert_not_includes config, "[default]"
    end
  end
end
