# frozen_string_literal: true

require "test_helper"

module Workflows
  class UnifiedContainerWorkflowTest < ActiveSupport::TestCase
    setup do
      @workflow = UnifiedContainerWorkflow.new

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)

      # Stub Temporal workflow logger
      temporal_logger = mock("temporal_logger")
      temporal_logger.stubs(:info)
      temporal_logger.stubs(:warn)
      temporal_logger.stubs(:error)
      Temporalio::Workflow.stubs(:logger).returns(temporal_logger)

      # Stub Temporal workflow.timeout to just yield (not available outside workflow env)
      Temporalio::Workflow.stubs(:timeout).yields
    end

    # == Tool Execution Tests ==

    test "runs tool execution workflow without waiting for signal" do
      pull_result = { status: "pulled", duration_seconds: 5.0 }
      execute_result = { container_id: "abc123", exit_code: 0, stdout: "output" }
      cleanup_result = { status: :cleaned_up, artifacts_status: nil }

      activities = setup_activity_mocks(pull_result, execute_result, cleanup_result)
      @workflow.stubs(:activities).returns(activities)

      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: 1, parameters: {} }
      )

      result = @workflow.run(input)

      assert_equal "abc123", result[:container_id]
      assert_equal "pulled", result[:image_pull_status]
      assert_equal :cleaned_up, result[:cleanup_status]
      assert_equal false, result[:cancelled]
    end

    test "respects custom tool timeout" do
      # Test via calculate_execution_timeout directly
      timeout = @workflow.send(:calculate_execution_timeout, :tool_execution,
        Hashie::Mash.new(strategy_input: { timeout: 600 }))

      # 600 + 300 overhead = 900
      assert_equal 900, timeout
    end

    test "caps tool timeout at max value" do
      timeout = @workflow.send(:calculate_execution_timeout, :tool_execution,
        Hashie::Mash.new(strategy_input: { timeout: 5000 }))

      # Max timeout is 1800 + 300 overhead = 2100
      assert_equal 2100, timeout
    end

    # == Agent Auth Tests ==

    test "waits for signal on agent_auth strategy" do
      pull_result = { status: "cached" }
      execute_result = { container_id: "agent123", websocket_url: "ws://localhost" }
      cleanup_result = { status: :cleaned_up, artifacts_status: :collected, credential_id: 42 }

      activities = setup_activity_mocks(pull_result, execute_result, cleanup_result)
      @workflow.stubs(:activities).returns(activities)

      # Simulate signal being received
      Temporalio::Workflow.stubs(:wait_condition).yields.returns(true)

      input = Hashie::Mash.new(
        strategy_type: "agent_auth",
        strategy_input: { user_id: 1, agent_type: "claude_code", session_id: 10, route_token: "tok" }
      )

      result = @workflow.run(input)

      assert_equal "agent123", result[:container_id]
      assert_equal "ws://localhost", result[:websocket_url]
      assert_equal :cleaned_up, result[:cleanup_status]
      assert_equal :collected, result[:artifacts_status]
      assert_equal 42, result[:credential_id]
    end

    test "waits for signal on agent_session strategy" do
      pull_result = { status: "pulled" }
      execute_result = { container_id: "session123" }
      cleanup_result = { status: :cleaned_up }

      activities = setup_activity_mocks(pull_result, execute_result, cleanup_result)
      @workflow.stubs(:activities).returns(activities)

      Temporalio::Workflow.stubs(:wait_condition).yields.returns(true)

      input = Hashie::Mash.new(
        strategy_type: "agent_session",
        strategy_input: { user_id: 1, session_id: 5 }
      )

      result = @workflow.run(input)

      assert_equal "session123", result[:container_id]
    end

    # == Signal Tests ==

    test "container_finished signal sets finished flag" do
      # Initialize flags first (as run does)
      @workflow.instance_variable_set(:@finished, false)
      @workflow.instance_variable_set(:@cancelled, false)

      @workflow.container_finished

      assert_equal true, @workflow.instance_variable_get(:@finished)
      assert_equal false, @workflow.instance_variable_get(:@cancelled)
    end

    test "container_cancelled signal sets both flags" do
      # Initialize flags first (as run does)
      @workflow.instance_variable_set(:@finished, false)
      @workflow.instance_variable_set(:@cancelled, false)

      @workflow.container_cancelled

      assert_equal true, @workflow.instance_variable_get(:@finished)
      assert_equal true, @workflow.instance_variable_get(:@cancelled)
    end

    test "cancelled flag is included in result" do
      pull_result = { status: "cached" }
      execute_result = { container_id: "abc123" }
      cleanup_result = { status: :cleaned_up }

      activities = setup_activity_mocks(pull_result, execute_result, cleanup_result)
      @workflow.stubs(:activities).returns(activities)

      # Simulate cancellation signal
      Temporalio::Workflow.stubs(:wait_condition).with do
        @workflow.container_cancelled
        true
      end.returns(true)

      input = Hashie::Mash.new(
        strategy_type: "agent_auth",
        strategy_input: { session_id: 1 }
      )

      result = @workflow.run(input)

      assert_equal true, result[:cancelled]
    end

    # == Input Handling Tests ==

    test "handles string keys in input" do
      pull_result = { status: "cached" }
      execute_result = { container_id: "abc123" }
      cleanup_result = { status: :cleaned_up }

      activities = setup_activity_mocks(pull_result, execute_result, cleanup_result)
      @workflow.stubs(:activities).returns(activities)

      input = Hashie::Mash.new({
        "strategy_type" => "tool_execution",
        "strategy_input" => { "tool_id" => 1 }
      })

      result = @workflow.run(input)

      assert_equal "abc123", result[:container_id]
    end

    test "extracts session_id from strategy_input" do
      session_id = @workflow.send(:extract_session_id,
        Hashie::Mash.new(strategy_input: { session_id: 42 }))

      assert_equal 42, session_id
    end

    test "extracts session_id from string key input" do
      session_id = @workflow.send(:extract_session_id,
        Hashie::Mash.new({ "strategy_input" => { "session_id" => 42 } }))

      assert_equal 42, session_id
    end

    # == Timeout Calculation Tests ==

    test "uses default timeout for tool execution" do
      timeout = @workflow.send(:calculate_execution_timeout, :tool_execution,
        Hashie::Mash.new(strategy_input: {}))

      # Default 300 + 300 overhead = 600
      assert_equal 600, timeout
    end

    test "uses agent phases timeout for agent strategies" do
      auth_timeout = @workflow.send(:calculate_execution_timeout, :agent_auth, Hashie::Mash.new)
      session_timeout = @workflow.send(:calculate_execution_timeout, :agent_session, Hashie::Mash.new)

      assert_equal 300, auth_timeout
      assert_equal 300, session_timeout
    end

    test "uses default timeout for unknown strategy" do
      timeout = @workflow.send(:calculate_execution_timeout, :unknown, Hashie::Mash.new)

      assert_equal 600, timeout
    end

    # == Cleanup Skipped Tests ==

    test "skips cleanup when no container_id returned" do
      pull_result = { status: "cached" }
      execute_result = { error: "Failed to create container" }

      activities = mock("activities")
      activities.stubs(:pull_docker_image_activity).returns(:pull_activity)
      activities.stubs(:execute_container_activity).returns(:execute_activity)

      @workflow.stubs(:activities).returns(activities)
      @workflow.stubs(:execute_activity).with(:pull_activity, anything, anything).returns(pull_result)
      @workflow.stubs(:execute_activity).with(:execute_activity, anything, anything).returns(execute_result)
      # cleanup_container_activity should NOT be called

      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: 1 }
      )

      result = @workflow.run(input)

      assert_equal "Failed to create container", result[:error]
      assert_nil result[:cleanup_status]
    end

    # == Result Building Tests ==

    test "build_result merges all results correctly" do
      @workflow.instance_variable_set(:@cancelled, false)

      result = { container_id: "abc", exit_code: 0 }
      pull_result = { status: "pulled", duration_seconds: 10.5 }
      cleanup_result = { status: :cleaned_up, artifacts_status: :collected, credential_id: 99 }

      merged = @workflow.send(:build_result, result, pull_result, cleanup_result)

      assert_equal "abc", merged[:container_id]
      assert_equal 0, merged[:exit_code]
      assert_equal "pulled", merged[:image_pull_status]
      assert_equal 10.5, merged[:image_pull_duration]
      assert_equal :cleaned_up, merged[:cleanup_status]
      assert_equal :collected, merged[:artifacts_status]
      assert_equal 99, merged[:credential_id]
      assert_equal false, merged[:cancelled]
    end

    test "build_result handles nil cleanup_result" do
      @workflow.instance_variable_set(:@cancelled, true)

      result = { container_id: "abc" }
      pull_result = { status: "cached" }

      merged = @workflow.send(:build_result, result, pull_result, nil)

      assert_equal "abc", merged[:container_id]
      assert_equal "cached", merged[:image_pull_status]
      assert_nil merged[:cleanup_status]
      assert_equal true, merged[:cancelled]
    end

    test "build_result handles string keys in results" do
      @workflow.instance_variable_set(:@cancelled, false)

      result = { "container_id" => "abc" }
      pull_result = { "status" => "pulled", "duration_seconds" => 5.0 }
      cleanup_result = { "status" => :cleaned_up }

      merged = @workflow.send(:build_result, result, pull_result, cleanup_result)

      assert_equal "pulled", merged[:image_pull_status]
      assert_equal 5.0, merged[:image_pull_duration]
      assert_equal :cleaned_up, merged[:cleanup_status]
    end

    private

    def setup_activity_mocks(pull_result, execute_result, cleanup_result)
      activities = mock("activities")
      activities.stubs(:pull_docker_image_activity).returns(:pull_activity)
      activities.stubs(:execute_container_activity).returns(:execute_activity)
      activities.stubs(:cleanup_container_activity).returns(:cleanup_activity)

      @workflow.stubs(:execute_activity).with(:pull_activity, anything, anything).returns(pull_result)
      @workflow.stubs(:execute_activity).with(:execute_activity, anything, anything).returns(execute_result)
      @workflow.stubs(:execute_activity).with(:cleanup_activity, anything, anything).returns(cleanup_result)

      activities
    end
  end
end
