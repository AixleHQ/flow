# frozen_string_literal: true

require "test_helper"

class Activities::RunnerHealth::CheckActivityTest < ActiveSupport::TestCase
  test "sets the status of each live runner from its machines" do
    runner = create(:runner, :manual)
    create(:runner_environment, runner: runner, last_heartbeat_at: Time.current)

    result = run_activity(Activities::RunnerHealth::CheckActivity)

    assert_equal({ checked: 1, changed: 1, failed: 0 }, result.symbolize_keys)
    assert_equal "connected", runner.reload.status
  end
end
