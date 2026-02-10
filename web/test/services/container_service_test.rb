# frozen_string_literal: true

require "test_helper"

class ContainerServiceTest < ActiveSupport::TestCase
  # Mock strategy for testing
  class MockStrategy
    attr_accessor :phases_called, :should_timeout, :should_error, :error_phase
    attr_reader :input

    def initialize(input = {})
      @input = input
      @phases_called = []
      @should_timeout = false
      @should_error = false
      @error_phase = nil
    end

    def before_create(context)
      @phases_called << :before_create
      context[:image] = "test-image:latest"
      context[:env_vars] = [ "TEST=1" ]
      context[:labels] = { "test" => "true" }
      context[:host_config] = { "NetworkMode" => "bridge" }
      maybe_timeout_or_error(:before_create)
    end

    def create(context)
      @phases_called << :create
      context[:container] = "mock-container-123"
      context[:container_id] = "mock-container-123"
      maybe_timeout_or_error(:create)
    end

    def before_start(context)
      @phases_called << :before_start
      maybe_timeout_or_error(:before_start)
    end

    def start(context)
      @phases_called << :start
      maybe_timeout_or_error(:start)
    end

    def before_exec(context)
      @phases_called << :before_exec
      maybe_timeout_or_error(:before_exec)
    end

    def exec(context)
      @phases_called << :exec
      context[:result] = { exit_code: 0, stdout: "success" }
      maybe_timeout_or_error(:exec)
    end

    def before_cleanup(context)
      @phases_called << :before_cleanup
      maybe_timeout_or_error(:before_cleanup)
    end

    def cleanup(context)
      @phases_called << :cleanup
      maybe_timeout_or_error(:cleanup)
    end

    def timeout_for(_phase)
      nil
    end

    private

    def maybe_timeout_or_error(phase)
      if @should_timeout && @error_phase == phase
        sleep(10)
      end

      if @should_error && @error_phase == phase
        raise StandardError, "Simulated error in #{phase}"
      end
    end
  end

  # Strategy without some phases
  class PartialStrategy
    attr_reader :phases_called

    def initialize(_input = {})
      @phases_called = []
    end

    def before_create(context)
      @phases_called << :before_create
      context[:image] = "test:latest"
    end

    def exec(context)
      @phases_called << :exec
      context[:result] = { status: :done }
    end
  end

  setup do
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)

    @runtime_mock = mock("runtime")
    ContainerRuntime.stubs(:build).returns(@runtime_mock)
  end

  # == Phase Execution Order Tests ==

  test "executes all lifecycle phases in correct order" do
    strategy = MockStrategy.new

    result = ContainerService.execute(strategy: strategy, input: {})

    expected_order = [
      :before_create,
      :create,
      :before_start,
      :start,
      :before_exec,
      :exec
    ]

    assert_equal expected_order, strategy.phases_called
    assert_equal 0, result[:exit_code]
    assert_equal "success", result[:stdout]
  end

  test "skips phases that strategy does not implement" do
    strategy = PartialStrategy.new

    result = ContainerService.execute(strategy: strategy, input: {})

    assert_equal [ :before_create, :exec ], strategy.phases_called
    assert_equal :done, result[:status]
  end

  # == Context Sharing Tests ==

  test "shares context between phases" do
    context_received = {}

    strategy = MockStrategy.new
    strategy.define_singleton_method(:exec) do |context|
      context_received[:image] = context[:image]
      context_received[:container] = context[:container]
      context[:result] = { received_context: true }
    end

    ContainerService.execute(strategy: strategy, input: { foo: "bar" })

    assert_equal "test-image:latest", context_received[:image]
    assert_not_nil context_received[:container]
  end

  test "input is available in context" do
    received_input = nil

    strategy = MockStrategy.new
    strategy.define_singleton_method(:before_create) do |context|
      received_input = context[:input]
      context[:image] = "test:latest"
    end

    ContainerService.execute(strategy: strategy, input: { key: "value" })

    assert_equal "value", received_input[:key]
  end

  # == Error Handling Tests ==

  test "wraps phase errors in PhaseError" do
    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec

    # Emergency cleanup via runtime
    @runtime_mock.stubs(:stop_container)
    @runtime_mock.stubs(:remove_container)

    error = assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end

    assert_equal :exec, error.phase
    assert_match(/Simulated error/, error.original_error.message)
  end

  test "performs emergency cleanup on error" do
    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec

    @runtime_mock.expects(:stop_container).with("mock-container-123", 5)
    @runtime_mock.expects(:remove_container).with("mock-container-123", force: true)

    assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end
  end

  test "emergency cleanup handles errors gracefully" do
    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec

    @runtime_mock.stubs(:stop_container).raises(StandardError.new("stop failed"))
    @runtime_mock.stubs(:remove_container).raises(StandardError.new("remove failed"))

    assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end
  end

  # == Timeout Tests ==

  test "raises ExecutionTimeout when phase exceeds timeout" do
    strategy = MockStrategy.new

    strategy.define_singleton_method(:exec) do |_context|
      sleep(5)
    end

    strategy.define_singleton_method(:timeout_for) do |phase|
      phase == :exec ? 0.1 : nil
    end

    @runtime_mock.stubs(:stop_container)
    @runtime_mock.stubs(:remove_container)

    error = assert_raises(ContainerService::ExecutionTimeout) do
      ContainerService.execute(strategy: strategy, input: {})
    end

    assert_match(/exec exceeded timeout/, error.message)
  end

  # == Default Timeouts Tests ==

  test "uses default timeouts when not configured" do
    service = ContainerService.new(MockStrategy.new, {})

    assert_equal 30, service.send(:phase_timeout, :before_create)
    assert_equal 60, service.send(:phase_timeout, :create)
    assert_equal 300, service.send(:phase_timeout, :exec)
  end

  test "strategy can override timeout" do
    strategy = MockStrategy.new
    strategy.define_singleton_method(:timeout_for) do |phase|
      phase == :exec ? 999 : nil
    end

    service = ContainerService.new(strategy, {})

    assert_equal 999, service.send(:phase_timeout, :exec)
    assert_equal 30, service.send(:phase_timeout, :before_create)
  end

  # == Result Tests ==

  test "returns result from context" do
    strategy = MockStrategy.new

    result = ContainerService.execute(strategy: strategy, input: {})

    assert_equal 0, result[:exit_code]
    assert_equal "success", result[:stdout]
  end

  test "returns empty hash when no result set" do
    strategy = PartialStrategy.new
    strategy.define_singleton_method(:exec) do |_context|
      # Don't set context[:result]
    end

    result = ContainerService.execute(strategy: strategy, input: {})

    assert_equal({}, result)
  end
end
