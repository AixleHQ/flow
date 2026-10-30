# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261030090000_mark_pending_step_runs_of_completed_runs_skipped")

class MarkPendingStepRunsOfCompletedRunsSkippedTest < ActiveSupport::TestCase
  def migrate
    migration = MarkPendingStepRunsOfCompletedRunsSkipped.new
    migration.suppress_messages { migration.up }
  end

  test "a pending step run of a completed run is marked skipped, as of the run's end" do
    run = create(:workflow_run, :completed, completed_at: Time.zone.parse("2026-10-26 20:00"))
    left_pending = create(:step_run, workflow_run: run)
    ran = create(:step_run, :completed, workflow_run: run)

    migrate
    migrate

    left_pending.reload
    assert_equal "skipped", left_pending.state
    assert_equal "All required outputs already exist from previous steps", left_pending.skip_reason
    assert_equal run.completed_at, left_pending.completed_at
    assert_equal "completed", ran.reload.state
  end

  test "a run still going keeps its pending step runs" do
    run = create(:workflow_run, :running)
    waiting = create(:step_run, workflow_run: run)

    migrate

    assert_equal "pending", waiting.reload.state
  end
end
