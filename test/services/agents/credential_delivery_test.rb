# frozen_string_literal: true

require "test_helper"

module Agents
  # A delivery writes each holder through its own runtime
  # (ContainerRuntime.for_session): a runner holder's through its machine, a
  # hosted holder's through the hosted runtime. Both are real runtimes,
  # RunnerRuntime with ContainerRuntime::FakeHostRunner and FakeRuntime, which
  # test/support/runtime_transaction_guard.rb checks: no runtime call is made
  # inside a database transaction.
  class CredentialDeliveryTest < ActiveSupport::TestCase
    CREDENTIALS_PATH = "/home/claude/.claude/.credentials.json"

    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @hosted = stub_container_runtime
      @credential = AgentCredential.from_artifacts(@user.id, @company.id, "claude_code", login("at-1", "rt-1"))
    end

    teardown do
      @host_runner&.stop
      cleanup_runtime_overrides
    end

    def login(access_token, refresh_token)
      { "claudeAiOauth" => { "accessToken" => access_token, "refreshToken" => refresh_token,
                             "expiresAt" => (6.hours.from_now.to_f * 1000).to_i } }
    end

    test "delivers to a runner holder and a hosted holder with no runtime call inside a database transaction" do
      hosted_holder = create(:terminal_session, user: @user, company: @company, project: @project, agent_type: "claude_code",
                                                state: "ready", started_at: 1.hour.ago, container_id: "ctr-hosted")
      runner = create(:runner, :manual, company: @company, created_by: @user)
      machine = create(:runner_environment, runner: runner)
      runner_holder = create(:runner_session, environment: machine, user: @user, company: @company, project: @project,
                                              agent_type: "claude_code", state: "ready", started_at: 1.hour.ago,
                                              container_id: "aixle-#{machine.key}-runner")
      machine.update!(current_session: runner_holder)
      ContainerRuntime::FakeHostRunner.identify!(runner_holder, runner_holder.container_id)
      @host_runner = ContainerRuntime::FakeHostRunner.new(machine)
      @host_runner.machine.start(runner_holder.id)

      result = CredentialDelivery.new.deliver(@credential, sessions: [ hosted_holder, runner_holder ])

      assert_equal 2, result.delivered
      assert_equal 0, result.failed
      assert_equal "rt-1", JSON.parse(@hosted.read_file(nil, CREDENTIALS_PATH)).dig("claudeAiOauth", "refreshToken")
      write = @host_runner.operations.find { |op| op[:op] == "write_file" }
      assert write, "the runner holder was written through its machine: #{@host_runner.ops.inspect}"
      assert_equal runner_holder.id, write[:session_id]
      written = @host_runner.machine.container.files.fetch(CREDENTIALS_PATH)
      assert_equal "rt-1", JSON.parse(written).dig("claudeAiOauth", "refreshToken")
      assert_empty RuntimeTransactionGuard.take
    end
  end
end
