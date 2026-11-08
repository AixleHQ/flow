# frozen_string_literal: true

require "test_helper"

module Sessions
  # On an external runner the list's write is an op, which the runner's gateway
  # sees only once it is committed. Publication enqueues it outside any
  # transaction and waits for its result, so the write is answered at once, not
  # at its deadline (ContainerRuntime::BaseRuntime, "Transactions"). A real
  # RunnerRuntime, whose ops ContainerRuntime::FakeHostRunner answers, not
  # FakeRuntime; test/support/runtime_transaction_guard.rb fails the test if
  # the write is made inside a transaction.
  class SecretRegistryRunnerTest < ActiveSupport::TestCase
    setup do
      runner = create(:runner, :manual)
      @environment = create(:runner_environment, runner: runner, key: "aixle-r9-5c6d7e8f")
      @session = create(:runner_session, environment: @environment, runner_environment: nil)
      @host_runner = ContainerRuntime::FakeHostRunner.new(@environment)
      @runtime = ContainerRuntime::RunnerRuntime.new
      ContainerRuntime::FakeHostRunner.identify!(@session, @runtime.session_identity(@session))
      @container = @runtime.create_container(image: "ghcr.io/aixlehq/flow-claude-code:latest", env_vars: [], host_config: {},
                                             labels: { "aixle.session_id" => @session.id.to_s })
      ContainerRuntime::FakeHostRunner.identify!(@session, @container)
    end

    teardown { @host_runner.stop }

    test "publication on a runner writes the list and returns before the op's deadline" do
      item = create(:config_item, :secret, scope: @session.project, name: "STRIPE_KEY", value: "sk_live_abc")
      ConfigItemAccess.record!(config_item: item, session: @session, user: @session.user)
      started = Time.current

      assert SecretRegistry.publish!(@session, runtime: @runtime, container: @container)

      write = RunnerOperation.find_by!(op: "write_file")
      assert_equal "completed", write.state.to_s, "the write was answered, not expired"
      assert_operator Time.current - started, :<, 5
      assert_operator write.completed_at, :<, write.deadline_at
      assert_equal @session.id, write.terminal_session_id
      list = @host_runner.machine.container.files.fetch(SecretRegistry::LIST_PATH)
      assert_equal [ "sk_live_abc" ], list.split("\n").map { |line| Base64.strict_decode64(line) }
    end
  end
end
