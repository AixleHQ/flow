# frozen_string_literal: true

require "test_helper"

class ContainerServiceTest < ActiveSupport::TestCase
  class MockStrategy
    attr_accessor :phases_called, :should_error, :error_phase

    def initialize
      @phases_called = []
      @should_error = false
      @error_phase = nil
    end

    def before_create_container(**)
      @phases_called << :before_create_container
      { image: "test-image:latest", env_vars: [ "TEST=1" ], labels: { "test" => "true" }, host_config: { "NetworkMode" => "bridge" } }
    end

    def create_container(image:, **)
      @phases_called << :create_container
      raise StandardError, "Simulated error in create_container" if @should_error && @error_phase == :create_container

      { container_id: "mock-container-123" }
    end

    def before_start_container(**)
      @phases_called << :before_start_container
      {}
    end

    def start_container(container_id:, **)
      @phases_called << :start_container
      {}
    end

    def before_exec(**)
      @phases_called << :before_exec
      {}
    end

    def exec(container_id:, **)
      @phases_called << :exec
      raise StandardError, "Simulated error in exec" if @should_error && @error_phase == :exec

      { exit_code: 0, stdout: "success" }
    end

    def before_cleanup(**)
      @phases_called << :before_cleanup
      {}
    end

    def cleanup(container_id:, **)
      @phases_called << :cleanup
      { status: :cleaned_up }
    end
  end

  class PartialStrategy
    attr_reader :phases_called

    def initialize
      @phases_called = []
    end

    def before_create_container(**)
      @phases_called << :before_create_container
      { image: "test:latest" }
    end

    def create_container(image:, **)
      @phases_called << :create_container
      { container_id: "partial-123" }
    end

    def exec(container_id:, **)
      @phases_called << :exec
      { status: :done }
    end
  end

  setup do
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.stubs(:error)
  end

  test "run_phase create_container executes before_create_container, create_container, after_create_container" do
    strategy = MockStrategy.new
    service = ContainerService.new(strategy: strategy, state: {})

    state = service.run_phase(:create_container)

    assert_equal [ :before_create_container, :create_container ], strategy.phases_called
    assert_equal "mock-container-123", state[:container_id]
    assert_equal "test-image:latest", state[:image]
  end

  test "run_phase exec passes container_id and returns merged state" do
    strategy = MockStrategy.new
    service = ContainerService.new(strategy: strategy, state: { container_id: "abc" })

    state = service.run_phase(:exec)

    assert_equal [ :before_exec, :exec ], strategy.phases_called
    assert_equal 0, state[:exit_code]
    assert_equal "success", state[:stdout]
    assert_equal "abc", state[:container_id]
  end

  test "run_phase skips hooks strategy does not implement" do
    strategy = PartialStrategy.new
    service = ContainerService.new(strategy: strategy, state: {})

    state = service.run_phase(:create_container)

    assert_equal [ :before_create_container, :create_container ], strategy.phases_called
    assert_equal "partial-123", state[:container_id]
  end

  test "run_phase cleanup executes before_cleanup and cleanup" do
    strategy = MockStrategy.new
    service = ContainerService.new(strategy: strategy, state: { container_id: "container-abc" })

    state = service.run_phase(:cleanup)

    assert_equal [ :before_cleanup, :cleanup ], strategy.phases_called
    assert_equal :cleaned_up, state[:status]
  end

  test "wraps phase errors in PhaseError" do
    strategy = MockStrategy.new
    strategy.should_error = true
    strategy.error_phase = :exec
    service = ContainerService.new(strategy: strategy, state: { container_id: "abc" })

    error = assert_raises(ContainerService::PhaseError) do
      service.run_phase(:exec)
    end

    assert_equal :exec, error.phase
    assert_match(/Simulated error/, error.original_error.message)
  end

  test "merges state between phases" do
    strategy = MockStrategy.new
    service = ContainerService.new(strategy: strategy, state: { session_id: 1, foo: "bar" })

    state = service.run_phase(:create_container)

    assert_equal 1, state[:session_id]
    assert_equal "bar", state[:foo]
    assert_equal "mock-container-123", state[:container_id]
  end
end
