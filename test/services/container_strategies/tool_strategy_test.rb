# frozen_string_literal: true

require "test_helper"

class ContainerStrategies::ToolStrategyTest < ActiveSupport::TestCase
  setup do
    @tool = create(:tool, :internal, name: "ts_test", display_name: "TS Test")
    @tool_result = create(:tool_result, tool: @tool)
  end

  test "phase_config returns correct timeouts" do
    strategy = ContainerStrategies::ToolStrategy.new(timeout: 120)

    exec_config = strategy.phase_config(:exec)
    assert_equal 120, exec_config[:timeout]

    cleanup_config = strategy.phase_config(:cleanup)
    assert_equal 60, cleanup_config[:timeout]
    assert cleanup_config[:always]

    other_config = strategy.phase_config(:pull_image)
    assert_equal 120, other_config[:timeout]
  end

  test "exec_timeout caps at MAX_TIMEOUT" do
    strategy = ContainerStrategies::ToolStrategy.new(timeout: 5000)
    assert_equal 1800, strategy.send(:exec_timeout)
  end

  test "exec_timeout uses DEFAULT_TIMEOUT when not provided" do
    strategy = ContainerStrategies::ToolStrategy.new({})
    assert_equal 300, strategy.send(:exec_timeout)
  end

  test "persist_result completes tool result on success" do
    strategy = ContainerStrategies::ToolStrategy.new(
      tool_result_id: @tool_result.id, timeout: 30
    )

    strategy.send(:persist_result,
      exit_code: 0, stdout: "output", stderr: "", duration_ms: 150)

    @tool_result.reload
    assert_equal "completed", @tool_result.state
    assert_equal 0, @tool_result.exit_code
    assert_equal 150, @tool_result.duration_ms
  end

  test "persist_result marks failed on nonzero exit" do
    strategy = ContainerStrategies::ToolStrategy.new(
      tool_result_id: @tool_result.id, timeout: 30
    )

    strategy.send(:persist_result,
      exit_code: 1, stdout: "", stderr: "err", duration_ms: 200)

    @tool_result.reload
    assert_equal "failed", @tool_result.state
    assert_equal 1, @tool_result.exit_code
  end

  test "persist_result stores error message on timeout" do
    strategy = ContainerStrategies::ToolStrategy.new(
      tool_result_id: @tool_result.id, timeout: 60
    )

    strategy.send(:persist_result,
      exit_code: 124, stdout: "", stderr: "", duration_ms: 60_000,
      error_msg: "Timed out after 60s")

    @tool_result.reload
    assert_equal "failed", @tool_result.state
    assert_equal "Timed out after 60s", @tool_result.error
  end

  test "persist_result skips when no tool_result_id" do
    strategy = ContainerStrategies::ToolStrategy.new(timeout: 30)

    assert_nothing_raised do
      strategy.send(:persist_result,
        exit_code: 0, stdout: "ok", stderr: "", duration_ms: 10)
    end
  end

  # ── heartbeat-sliced wait (Temporal cancellation delivery) ──

  class FakeCancellation
    def initialize(canceled: false) = @canceled = canceled
    def check!
      raise Temporalio::Error::CanceledError, "Canceled" if @canceled
    end
  end

  FakeActivityContext = Struct.new(:cancellation) do
    def heartbeat(*) = true
  end

  test "wait_with_heartbeat retries slices until the container exits" do
    strategy = ContainerStrategies::ToolStrategy.new(timeout: 60)
    runtime = mock
    runtime.expects(:wait_container).twice
           .raises(Docker::Error::TimeoutError).then
           .returns({ "StatusCode" => 0 })
    strategy.stubs(:runtime).returns(runtime)
    strategy.stubs(:activity_context).returns(nil)

    assert_equal 0, strategy.send(:wait_with_heartbeat, "cid", 60)
  end

  test "wait_with_heartbeat returns nil once the overall timeout elapses" do
    strategy = ContainerStrategies::ToolStrategy.new(timeout: 60)
    runtime = mock
    runtime.stubs(:wait_container).raises(Docker::Error::TimeoutError)
    strategy.stubs(:runtime).returns(runtime)
    strategy.stubs(:activity_context).returns(nil)

    assert_nil strategy.send(:wait_with_heartbeat, "cid", 0)
  end

  test "exec kills the container and finalizes the tool result on Temporal cancellation" do
    strategy = ContainerStrategies::ToolStrategy.new(
      tool_result_id: @tool_result.id, timeout: 60
    )
    ctx = FakeActivityContext.new(FakeCancellation.new(canceled: true))
    strategy.stubs(:activity_context).returns(ctx)
    strategy.stubs(:resolve_container).returns("cid")
    runtime = mock
    runtime.expects(:stop_container).with("cid", 5)
    strategy.stubs(:runtime).returns(runtime)

    assert_raises(Temporalio::Error::CanceledError) do
      strategy.exec(container_id: "cid")
    end

    @tool_result.reload
    assert_equal "failed", @tool_result.state
    assert_equal "Execution cancelled", @tool_result.error
  end
end
