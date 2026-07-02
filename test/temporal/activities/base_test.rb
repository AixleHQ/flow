# frozen_string_literal: true

require "test_helper"

class Activities::BaseTest < ActiveSupport::TestCase
  # Test activity class
  class TestActivity < Activities::Base
    def run(input)
      { result: input&.test_key || "default" }
    end
  end

  # Activity that raises record not found
  class NotFoundActivity < Activities::Base
    def run(_input)
      raise ActiveRecord::RecordNotFound, "Record not found"
    end
  end

  # Activity that raises record invalid
  class InvalidActivity < Activities::Base
    def run(_input)
      raise ActiveRecord::RecordInvalid.new(User.new)
    end
  end

  setup do
    @activity = TestActivity.new
  end

  test "activity_name is set from class name" do
    # TestActivity is nested inside Activities::BaseTest, so the full name
    # results in "base_test_test_activity"
    assert_equal "base_test_test_activity", TestActivity.instance_variable_get(:@activity_name)
  end

  test "name returns activity name" do
    assert_equal "base_test_test_activity", @activity.name
  end

  test "execute wraps input in Hashie::Mash" do
    result = @activity.execute({ test_key: "value" })
    assert_equal({ result: "value" }, result)
  end

  test "execute handles string keys in input" do
    result = @activity.execute({ "test_key" => "string_value" })
    assert_equal({ result: "string_value" }, result)
  end

  test "execute handles nil input" do
    result = @activity.execute(nil)
    assert_equal({ result: "default" }, result)
  end

  test "execute handles non-hash input" do
    activity = TestActivity.new
    activity.define_singleton_method(:run) { |input| { result: input } }

    result = activity.execute("string input")
    assert_equal({ result: "string input" }, result)
  end

  test "execute wraps RecordNotFound in non-retryable exception" do
    activity = NotFoundActivity.new

    error = assert_raises(Temporalio::Error::ApplicationError) do
      activity.execute({})
    end

    assert_includes error.message, "Record not found"
    refute_nil error.non_retryable
  end

  test "execute wraps RecordInvalid in non-retryable exception" do
    activity = InvalidActivity.new

    error = assert_raises(Temporalio::Error::ApplicationError) do
      activity.execute({})
    end

    refute_nil error.non_retryable
  end

  test "log does not log in test environment" do
    Rails.logger.expects(:info).never
    @activity.log(:info, "test message")
  end

  test "serialize_model returns nil for blank model" do
    assert_nil @activity.serialize_model(nil)
    assert_nil @activity.serialize_model("")
  end

  test "serialize_model serializes model" do
    mock_serializer = mock("serializer")
    mock_serializer.expects(:as_json).returns({ id: 1 })

    # Stub the serializer constant
    Object.const_set(:ModelDefinitionSerializer, Class.new) unless Object.const_defined?(:ModelDefinitionSerializer)
    Object::ModelDefinitionSerializer.expects(:new).returns(mock_serializer)

    result = @activity.serialize_model(mock("model"))
    assert_equal({ id: 1 }, result)
  end

  # Test inherited hook - use an existing named class for predictable results
  test "inherited sets activity_name on subclass" do
    # TestActivity already has its name set via inherited hook
    assert_equal "base_test_test_activity", TestActivity.instance_variable_get(:@activity_name)
  end
end
