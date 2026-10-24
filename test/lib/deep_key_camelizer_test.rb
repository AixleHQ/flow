# frozen_string_literal: true

require "test_helper"

class DeepKeyCamelizerTest < ActiveSupport::TestCase
  test "camelizes keys at every depth and leaves values alone" do
    payload = { "task_id" => 1, recent_runs: [ { "duration_seconds" => 5, "createdAt" => "x" } ], "ok" => "snake_value" }

    assert_equal(
      { "taskId" => 1, "recentRuns" => [ { "durationSeconds" => 5, "createdAt" => "x" } ], "ok" => "snake_value" },
      DeepKeyCamelizer.call(payload)
    )
  end

  test "a hash keeps the keys it lists under _preserveKeys, and the marker is dropped" do
    payload = { "env" => { "MY_TOKEN" => "a", "_preserveKeys" => [] }, "_preserveKeys" => [ "env" ], "extra_key" => 1 }

    assert_equal({ "env" => { "MY_TOKEN" => "a" }, "extraKey" => 1 }, DeepKeyCamelizer.call(payload))
  end
end
