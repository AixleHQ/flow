# frozen_string_literal: true

require "test_helper"

class TemporalInputTest < ActiveSupport::TestCase
  test "reads keys as methods and by name, either spelling" do
    input = TemporalInput.wrap({ "session_id" => 7, "state" => { "container_id" => "c-1" } })

    assert_equal 7, input.session_id
    assert_equal "c-1", input[:state][:container_id]
  end

  test "refuses a key that a Hash method would answer instead" do
    error = assert_raises(ArgumentError) { TemporalInput.wrap({ "count" => 3, "zip" => "12345" }) }

    assert_match "count, zip", error.message
  end

  test "wraps nested keys named like Hash methods without logging, readable by key" do
    log = StringIO.new
    original_logger = Hashie.logger
    Hashie.logger = Logger.new(log)
    nested = { "parameters" => { "max" => 5, "count" => 1 } }

    Hashie::Mash.new(nested)
    assert_match "max", log.string, "a plain Mash logs the collision, so the capture below is live"
    log.truncate(0)
    log.rewind

    input = TemporalInput.wrap(nested)

    assert_empty log.string
    assert_instance_of TemporalInput::Mash, input.parameters
    assert_equal 5, input.parameters[:max]
    assert_equal 1, input.parameters["count"]
  ensure
    Hashie.logger = original_logger
  end

  test "passes anything that is not a hash through" do
    assert_equal 42, TemporalInput.wrap(42)
    assert_nil TemporalInput.wrap(nil)
  end
end
