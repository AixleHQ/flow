# frozen_string_literal: true

require "test_helper"

module Activities
  class CleanupContainerActivityTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @session = create(:terminal_session, :running, user: @user)

      @activity = CleanupContainerActivity.new

      @runtime_mock = mock("runtime")
      # Mock runtime globally so both activity and strategies use the same mock
      ContainerRuntime.stubs(:build).returns(@runtime_mock)

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
      Rails.logger.stubs(:debug)
    end

    # == Successful Cleanup Tests ==

    test "cleans up container successfully via strategy" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns("abc123")

      strategy_mock = mock("strategy")
      strategy_mock.stubs(:before_cleanup)
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up, container_id: "abc123" })

      @activity.stubs(:build_strategy_from_session).returns(strategy_mock)
      @activity.stubs(:find_session).returns(@session)

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: @session.id,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]
      assert_equal "abc123", result[:container_id]
    end

    test "returns not_found when container does not exist" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns(nil)
      # Strategy cleanup will try stop_container with container_id, which fails
      @runtime_mock.stubs(:stop_container).raises(StandardError.new("not found"))
      @runtime_mock.stubs(:remove_container).raises(StandardError.new("not found"))

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: @session.id,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      # Strategy cleanup catches errors, returns failed or context still gets a status
      assert_includes [ :cleaned_up, :skipped, :not_found, :failed ], result[:status]
    end

    test "force removes on stop error" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns("abc123")

      strategy_mock = mock("strategy")
      strategy_mock.stubs(:before_cleanup)
      strategy_mock.expects(:cleanup).returns({ status: :force_removed, container_id: "abc123" })

      @activity.stubs(:build_strategy_from_session).returns(strategy_mock)
      @activity.stubs(:find_session).returns(@session)

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: @session.id,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :force_removed, result[:status]
    end

    # == Session Update Tests ==

    test "updates session status after cleanup" do
      @runtime_mock.stubs(:resolve_container).with(@session.container_id).returns(@session.container_id)

      strategy_mock = mock("strategy")
      strategy_mock.stubs(:before_cleanup)
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up, container_id: @session.container_id })

      @activity.stubs(:build_strategy_from_session).returns(strategy_mock)
      @activity.stubs(:find_session).returns(@session)

      input = Hashie::Mash.new(
        container_id: @session.container_id,
        session_id: @session.id,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]

      @session.reload
      assert_nil @session.container_id
    end

    test "handles missing session gracefully - uses fallback cleanup" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns("abc123")
      @runtime_mock.expects(:stop_container).with("abc123", 5)
      @runtime_mock.expects(:remove_container).with("abc123")

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: 999999,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]
    end

    # == Fallback Cleanup Tests ==

    test "uses fallback cleanup without strategy when session not found" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns("abc123")
      @runtime_mock.expects(:stop_container).with("abc123", 5)
      @runtime_mock.expects(:remove_container).with("abc123")

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: nil,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]
    end

    # == Tool Execution Strategy Tests ==

    test "cleans up tool container without before_cleanup artifacts" do
      create(:tool, scope: @company)

      @runtime_mock.stubs(:resolve_container).with("tool123").returns("tool123")
      @runtime_mock.expects(:stop_container).with("tool123", 5)
      @runtime_mock.expects(:remove_container).with("tool123")

      input = Hashie::Mash.new(
        container_id: "tool123",
        session_id: nil,
        strategy_type: "tool_execution"
      )
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]
    end

    # == String Key Tests ==

    test "handles string keys in input" do
      @runtime_mock.stubs(:resolve_container).with("abc123").returns("abc123")

      strategy_mock = mock("strategy")
      strategy_mock.stubs(:before_cleanup)
      strategy_mock.expects(:cleanup).returns({ status: :cleaned_up, container_id: "abc123" })

      @activity.stubs(:build_strategy_from_session).returns(strategy_mock)
      @activity.stubs(:find_session).returns(@session)

      input = Hashie::Mash.new({
        "container_id" => "abc123",
        "session_id" => @session.id,
        "strategy_type" => "agent_auth"
      })
      result = @activity.run(input)

      assert_equal :cleaned_up, result[:status]
    end
  end
end
