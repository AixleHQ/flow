# frozen_string_literal: true

require "test_helper"

module Activities
  class CleanupContainerActivityTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @session = create(:terminal_session, :running, user: @user)

      @activity = CleanupContainerActivity.new

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
      Rails.logger.stubs(:debug)
    end

    # == Successful Cleanup Tests ==

    test "cleans up container successfully via strategy" do
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:exec).returns([ [], [], 1 ]) # No auth files found
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

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
      Docker::Container.stubs(:get).raises(Docker::Error::NotFoundError)

      input = Hashie::Mash.new(
        container_id: "abc123",
        session_id: @session.id,
        strategy_type: "agent_auth"
      )
      result = @activity.run(input)

      assert_equal :not_found, result[:status]
    end

    test "force removes on stop error" do
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:exec).returns([ [], [], 1 ])
      container_mock.expects(:stop).raises(Docker::Error::DockerError.new("stop failed"))
      container_mock.expects(:remove).with(force: true)

      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

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
      container_mock = mock("container")
      container_mock.stubs(:id).returns(@session.container_id + "000000")
      container_mock.stubs(:exec).returns([ [], [], 1 ])
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with(@session.container_id).returns(container_mock)

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
      container_mock = mock("container")
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

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
      container_mock = mock("container")
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

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
      tool = create(:tool, scope: @company)

      container_mock = mock("container")
      container_mock.stubs(:id).returns("tool123456789")
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with("tool123").returns(container_mock)

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
      container_mock = mock("container")
      container_mock.stubs(:id).returns("abc123456789")
      container_mock.stubs(:exec).returns([ [], [], 1 ])
      container_mock.expects(:stop).with("t" => 5)
      container_mock.expects(:remove)

      Docker::Container.stubs(:get).with("abc123").returns(container_mock)

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
