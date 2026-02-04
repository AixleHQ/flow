# frozen_string_literal: true

require "test_helper"

class ContainerServiceTest < ActiveSupport::TestCase
  # Simple mock container object
  class MockContainer
    def id
      "abc123def456"
    end

    def kill
      true
    end

    def remove(_options = {})
      true
    end
  end

  # Mock strategy for testing
  class MockStrategy
    attr_accessor :phases_called, :should_timeout, :should_error, :error_phase, :container_mock
    attr_reader :input

    def initialize(input = {})
      @input = input
      @phases_called = []
      @should_timeout = false
      @should_error = false
      @error_phase = nil
      @container_mock = MockContainer.new
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
      context[:container] = @container_mock
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
        sleep(10) # Will trigger timeout
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
    # Stub Rails.logger to avoid nil errors
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)
  end

  # == Phase Execution Order Tests ==

  test "executes all lifecycle phases in correct order" do
    strategy = MockStrategy.new

    result = ContainerService.execute(strategy: strategy, input: {})

    # 6 phases - cleanup is done separately
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

    # Only before_create and exec are implemented
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

    error = assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end

    assert_equal :exec, error.phase
    assert_match(/Simulated error/, error.original_error.message)
  end

  test "performs emergency cleanup on error" do
    cleanup_called = false

    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec

    # Track cleanup via a custom container
    cleanup_container = Object.new
    cleanup_container.define_singleton_method(:kill) { }
    cleanup_container.define_singleton_method(:remove) { |_opts = {}| cleanup_called = true }
    strategy.container_mock = cleanup_container

    assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end

    assert cleanup_called, "Emergency cleanup should have been called"
  end

  test "emergency cleanup handles NotFoundError gracefully" do
    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec

    # Create container that raises NotFoundError on cleanup
    error_container = Object.new
    error_container.define_singleton_method(:kill) { raise Docker::Error::NotFoundError, "not found" }
    error_container.define_singleton_method(:remove) { |_opts = {}| raise Docker::Error::NotFoundError, "not found" }
    strategy.container_mock = error_container

    # Should not raise despite Docker::Error::NotFoundError in cleanup
    assert_raises(ContainerService::PhaseError) do
      ContainerService.execute(strategy: strategy, input: {})
    end
  end

  # == Timeout Tests ==

  test "raises ExecutionTimeout when phase exceeds timeout" do
    strategy = MockStrategy.new

    # Override phase with sleep
    strategy.define_singleton_method(:exec) do |_context|
      sleep(5) # Longer than our test timeout
    end

    # Override timeout to be very short
    strategy.define_singleton_method(:timeout_for) do |phase|
      phase == :exec ? 0.1 : nil
    end

    error = assert_raises(ContainerService::ExecutionTimeout) do
      ContainerService.execute(strategy: strategy, input: {})
    end

    assert_match(/exec exceeded timeout/, error.message)
  end

  # == Default Timeouts Tests ==

  test "uses default timeouts when not configured" do
    service = ContainerService.new(MockStrategy.new, {})

    # Access private method via send
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
    assert_equal 30, service.send(:phase_timeout, :before_create) # Still default
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
