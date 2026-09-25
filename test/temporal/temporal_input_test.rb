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

  test "passes anything that is not a hash through" do
    assert_equal 42, TemporalInput.wrap(42)
    assert_nil TemporalInput.wrap(nil)
  end
end
