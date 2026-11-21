# frozen_string_literal: true

require "test_helper"

class BestEffortBroadcastTest < ActiveSupport::TestCase
  setup do
    @pubsub = ActionCable.server.pubsub
    @pubsub.clear_messages("best_effort")
  end

  test "publishes the block's message as JSON on the channel" do
    BestEffortBroadcast.call("best_effort", context: "test") { { type: "ping", n: 1 } }

    assert_equal [ { "type" => "ping", "n" => 1 } ], @pubsub.broadcasts("best_effort").map { |m| JSON.parse(m) }
  end

  test "a failed publish is logged with its context and swallowed" do
    @pubsub.stubs(:broadcast).raises(StandardError, "redis is down")
    Rails.logger.expects(:warn).with("[Test] ping failed: StandardError: redis is down")

    assert_nothing_raised { BestEffortBroadcast.call("best_effort", context: "[Test] ping") { { type: "ping" } } }
  end

  test "a message that cannot be built is logged and swallowed, and nothing is published" do
    Rails.logger.expects(:warn).with("[Test] ping failed: RuntimeError: gone")

    assert_nothing_raised { BestEffortBroadcast.call("best_effort", context: "[Test] ping") { raise "gone" } }
    assert_empty @pubsub.broadcasts("best_effort")
  end
end
