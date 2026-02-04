# frozen_string_literal: true

require "test_helper"

module Activities
  class ExecuteContainerActivityTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @tool = create(:tool, scope: @company)
      @session = create(:terminal_session, user: @user)
      @credential = create(:agent_credential, user: @user)

      @activity = ExecuteContainerActivity.new

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
    end

    # == Input Preparation Tests ==

    test "prepares tool input with all fields" do
      input = { tool_id: @tool.id, parameters: { "key" => "value" }, project_id: @project.id, timeout: 600 }

      prepared = @activity.send(:prepare_strategy_input, :tool_execution, input.with_indifferent_access)

      assert_equal @tool, prepared[:tool]
      assert_equal({ "key" => "value" }, prepared[:parameters])
      assert_equal @project, prepared[:project]
      assert_equal 600, prepared[:timeout]
    end

    test "prepares tool input without project" do
      input = { tool_id: @tool.id, parameters: {} }

      prepared = @activity.send(:prepare_strategy_input, :tool_execution, input.with_indifferent_access)

      assert_equal @tool, prepared[:tool]
      assert_nil prepared[:project]
    end

    test "prepares agent auth input" do
      input = { user_id: @user.id, agent_type: "claude_code", session_id: @session.id, route_token: @session.route_token }

      prepared = @activity.send(:prepare_strategy_input, :agent_auth, input.with_indifferent_access)

      assert_equal @user.id, prepared[:user_id]
      assert_equal "claude_code", prepared[:agent_type]
      assert_equal @session.id, prepared[:session_id]
      assert_equal @session.route_token, prepared[:route_token]
    end

    test "prepares agent session input with credential" do
      input = { user_id: @user.id, agent_type: "claude_code", session_id: @session.id, route_token: @session.route_token, credential_id: @credential.id }

      prepared = @activity.send(:prepare_strategy_input, :agent_session, input.with_indifferent_access)

      assert_equal @credential, prepared[:credential]
    end

    test "prepares agent session input without credential" do
      input = { user_id: @user.id, agent_type: "claude_code", session_id: @session.id, route_token: @session.route_token }

      prepared = @activity.send(:prepare_strategy_input, :agent_session, input.with_indifferent_access)

      assert_nil prepared[:credential]
    end

    # == Execution Tests ==

    test "executes tool strategy" do
      expected_result = {
        exit_code: 0,
        stdout: "output",
        stderr: "",
        container_id: "abc123"
      }

      ContainerService.expects(:execute).returns(expected_result)

      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: {
          tool_id: @tool.id,
          parameters: {}
        }
      )

      result = @activity.run(input)

      assert_equal expected_result, result
    end

    test "executes agent auth strategy" do
      expected_result = {
        container_id: "abc123",
        websocket_url: "ws://...",
        watcher_url: "http://..."
      }

      ContainerService.expects(:execute).returns(expected_result)

      input = Hashie::Mash.new(
        strategy_type: "agent_auth",
        strategy_input: {
          user_id: @user.id,
          agent_type: "claude_code",
          session_id: @session.id,
          route_token: @session.route_token
        }
      )

      result = @activity.run(input)

      assert_equal expected_result, result
    end

    test "handles string keys in input" do
      expected_result = { container_id: "abc123" }
      ContainerService.expects(:execute).returns(expected_result)

      input = Hashie::Mash.new({
        "strategy_type" => "agent_auth",
        "strategy_input" => {
          "user_id" => @user.id,
          "agent_type" => "claude_code",
          "session_id" => @session.id,
          "route_token" => @session.route_token
        }
      })

      result = @activity.run(input)

      assert_equal expected_result, result
    end

    test "raises retryable error for execution errors" do
      ContainerService.expects(:execute).raises(
        ContainerService::ExecutionError.new("Container failed")
      )

      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: @tool.id }
      )

      assert_raises(TemporalExceptions::NonRetryableError) do
        @activity.run(input)
      end
    end
  end
end
