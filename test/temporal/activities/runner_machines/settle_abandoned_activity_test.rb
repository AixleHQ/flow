# frozen_string_literal: true

require "test_helper"

class Activities::RunnerMachines::SettleAbandonedActivityTest < ActiveSupport::TestCase
  test "does nothing, and says so, when no machine is held by an abandoned session" do
    create(:runner_environment, runner: create(:runner, :manual))

    result = run_activity(Activities::RunnerMachines::SettleAbandonedActivity)

    assert_equal({ checked: 0, reset_sent: 0, released: 0, failed: 0, errors: 0 }, result.symbolize_keys)
  end

  test "sends the reset of a machine a stale session holds" do
    machine = create(:runner_environment, runner: create(:runner, :manual))
    session = create(:runner_session, environment: machine, runner_environment: nil, state: "failed")
    Runners::Allocator.acquire!(session)

    result = run_activity(Activities::RunnerMachines::SettleAbandonedActivity)

    assert_equal 1, result.symbolize_keys[:reset_sent]
    assert_equal "env.reset", RunnerOperation.latest_reset(machine, session).op
  end
end
