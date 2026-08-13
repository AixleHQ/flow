# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class CleanupStaleRunsActivityTest < ActiveSupport::TestCase
      setup do
        @user = create(:user, :with_company)
        @company = @user.companies.first
        @project = create(:project, owner: @user, company: @company)
        @workflow = create(:workflow, scope: @project)
      end

      test "fails a running run that has been running for longer than the stale threshold" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "running", started_at: 5.hours.ago)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "failed", run.reload.state
        assert_match(/stale/i, run.reload.failure_reason)
      end

      test "fails a paused run that has been paused for longer than the stale threshold" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "paused", started_at: 5.hours.ago)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "failed", run.reload.state
      end

      test "does not fail a running run within the stale threshold" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "running", started_at: 1.hour.ago)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "running", run.reload.state
      end

      test "does not fail a pending run (never started)" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "pending")

        run_activity(CleanupStaleRunsActivity)

        assert_equal "pending", run.reload.state
      end

      test "does not fail a run already in a terminal state" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "completed", started_at: 10.hours.ago, completed_at: 9.hours.ago)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "completed", run.reload.state
      end

      test "continues processing other runs when one transition raises" do
        good_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                          state: "running", started_at: 5.hours.ago)
        bad_run  = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                          state: "running", started_at: 5.hours.ago)

        bad_run.stubs(:may_fail?).raises(RuntimeError, "simulated error")

        assert_nothing_raised { run_activity(CleanupStaleRunsActivity) }
        assert_equal "failed", good_run.reload.state
      end

      test "returns counts of cleaned runs" do
        create(:workflow_run, workflow: @workflow, project: @project, user: @user,
               state: "running", started_at: 5.hours.ago)
        create(:workflow_run, workflow: @workflow, project: @project, user: @user,
               state: "paused",  started_at: 5.hours.ago)

        result = run_activity(CleanupStaleRunsActivity)

        assert_equal 1, result[:cleaned_running]
        assert_equal 1, result[:cleaned_paused]
      end

      test "fails active terminal sessions attached to a stale run" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "running", started_at: 5.hours.ago)
        session = create(:terminal_session, :running, user: @user, project: @project,
                         company: @company, state: "ready")
        create(:step_run, :running, workflow_run: run, terminal_session: session)

        SessionService.expects(:fail_session).with(
          session: session,
          error_message: regexp_matches(/stale run reaper/)
        )

        run_activity(CleanupStaleRunsActivity)

        assert_equal "failed", run.reload.state
      end

      test "skips sessions that cannot transition to failed" do
        run = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                     state: "running", started_at: 5.hours.ago)
        session = create(:terminal_session, user: @user, project: @project,
                         company: @company, state: "finished")
        create(:step_run, :running, workflow_run: run, terminal_session: session)

        SessionService.expects(:fail_session).never

        run_activity(CleanupStaleRunsActivity)

        assert_equal "finished", session.reload.state
      end
    end
  end
end
