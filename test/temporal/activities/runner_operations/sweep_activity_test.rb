# frozen_string_literal: true

require "test_helper"

class Activities::RunnerOperations::SweepActivityTest < ActiveSupport::TestCase
  test "expires the ops past their deadline and prunes the old finished ones" do
    environment = create(:runner_environment)
    holder = create(:runner_session, :holding, environment: environment)
    overdue = Runners::Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: 1.hour.ago, session: holder)
    old = Runners::Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: 1.minute.from_now, session: holder)
    Runners::Operations.record_result!(old, { "status" => "ok" })
    old.update_columns(completed_at: 8.days.ago)
    Runners::Operations.enqueue!(environment, op: "env.reset", payload: {}, deadline_at: 1.minute.from_now, session: holder)

    result = run_activity(Activities::RunnerOperations::SweepActivity)

    assert_equal({ expired: 1, pruned: 1 }, result.symbolize_keys)
    assert overdue.reload.expired?
    assert_not RunnerOperation.exists?(old.id)
  end
end
