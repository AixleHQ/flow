# frozen_string_literal: true

require "test_helper"

module Activities
  class PullDockerImageActivityTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      @user = create(:user, company: @company)
      @tool = create(:tool, scope: @company)
      @session = create(:terminal_session, user: @user)

      @activity = PullDockerImageActivity.new

      Rails.logger.stubs(:info)
      Rails.logger.stubs(:warn)
      Rails.logger.stubs(:error)
      Rails.logger.stubs(:debug)
    end

    # == Validation Tests ==

    test "raises error for unknown strategy type" do
      input = Hashie::Mash.new(
        strategy_type: "unknown",
        strategy_input: {}
      )

      error = assert_raises(TemporalExceptions::NonRetryableError) do
        @activity.run(input)
      end

      assert_match(/Unknown strategy type/, error.message)
    end

    # == Cached Image Tests (Fast Path) ==

    test "returns cached status when image exists locally" do
      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: @tool.id }
      )

      # Image already cached
      Docker::Image.expects(:get).with(@tool.docker_image).returns(mock("image"))

      result = @activity.run(input)

      assert_equal :cached, result[:status]
      assert_equal @tool.docker_image, result[:image]
      assert_equal 0, result[:duration_seconds]
    end

    test "returns cached for agent auth strategy" do
      input = Hashie::Mash.new(
        strategy_type: "agent_auth",
        strategy_input: {
          user_id: @user.id,
          agent_type: "claude_code",
          session_id: @session.id,
          route_token: @session.route_token
        }
      )

      expected_image = "palad/claude-code:latest"
      Docker::Image.expects(:get).with(expected_image).returns(mock("image"))

      result = @activity.run(input)

      assert_equal :cached, result[:status]
      assert_equal expected_image, result[:image]
    end

    # == Pull Image Tests (Slow Path) ==

    test "pulls image when not cached locally" do
      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: @tool.id }
      )

      image = @tool.docker_image
      image_name, tag = image.include?(":") ? image.rpartition(":").values_at(0, 2) : [image, "latest"]

      # Image not found locally
      Docker::Image.expects(:get).with(image).raises(Docker::Error::NotFoundError)

      # Pull from registry
      Docker::Image.expects(:create).with(
        "fromImage" => image_name,
        "tag" => tag
      ).yields('{"status":"Pulling"}')

      result = @activity.run(input)

      assert_equal :pulled, result[:status]
      assert_equal image, result[:image]
      assert result[:duration_seconds] >= 0
    end

    # == Error Handling Tests ==

    test "raises non-retryable error when image not found in registry" do
      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: @tool.id }
      )

      Docker::Image.expects(:get).raises(Docker::Error::NotFoundError)
      Docker::Image.expects(:create).raises(Docker::Error::NotFoundError)

      error = assert_raises(TemporalExceptions::NonRetryableError) do
        @activity.run(input)
      end

      assert_kind_of Docker::Error::NotFoundError, error.cause
    end

    test "raises retryable error on Docker connection error" do
      input = Hashie::Mash.new(
        strategy_type: "tool_execution",
        strategy_input: { tool_id: @tool.id }
      )

      Docker::Image.expects(:get).raises(Docker::Error::NotFoundError)
      Docker::Image.expects(:create).raises(Docker::Error::DockerError.new("connection refused"))

      error = assert_raises(TemporalExceptions::RetryableError) do
        @activity.run(input)
      end

      assert_match(/connection refused/, error.message)
    end

    # == String Keys Tests ==

    test "handles string keys in input" do
      input = Hashie::Mash.new({
        "strategy_type" => "tool_execution",
        "strategy_input" => { "tool_id" => @tool.id }
      })

      Docker::Image.expects(:get).returns(mock("image"))

      result = @activity.run(input)

      assert_equal :cached, result[:status]
    end
  end
end
