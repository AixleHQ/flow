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

  # Hashie logs a nested key named like a Mash method, and a logger call inside a
  # workflow is a NondeterminismError (#329). Plain Hashie::Mash proves the capture works.
  test "wraps nested keys named like Hash methods without logging" do
    input = { "parameters" => { "max" => 5, "count" => 1 } }

    wrapped, log = capture_hashie_log { TemporalInput.wrap(input) }
    _, plain_log = capture_hashie_log { Hashie::Mash.new(input) }

    assert_kind_of TemporalInput::Mash, wrapped[:parameters]
    assert_equal 5, wrapped[:parameters]["max"]
    assert_equal 1, wrapped[:parameters]["count"]
    assert_empty log
    assert_match "max", plain_log
  end

  test "passes anything that is not a hash through" do
    assert_equal 42, TemporalInput.wrap(42)
    assert_nil TemporalInput.wrap(nil)
  end

  private

  def capture_hashie_log
    original = Hashie.logger
    io = StringIO.new
    Hashie.logger = Logger.new(io)
    [yield, io.string]
  ensure
    Hashie.logger = original
  end
end
