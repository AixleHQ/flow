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

      def execution(run, state)
        TemporalService.stubs(:execution_state).with(run.execution_workflow_id).returns(state)
      end

      def started_run(state: "running", started_at: 1.hour.ago)
        create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: state, started_at: started_at)
      end

      test "fails a running run whose execution has closed" do
        run = started_run
        execution(run, :closed)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "failed", run.reload.state
        assert_equal "stale_run", run.failure_reason
        assert run.stop_requested_at
      end

      test "fails a paused run whose execution Temporal has no record of" do
        run = started_run(state: "paused")
        execution(run, :not_found)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "failed", run.reload.state
      end

      # The age rule this replaced failed these after 4 hours.
      test "leaves a run alone however long it has been going while its execution is running" do
        run = started_run(started_at: 3.days.ago)
        execution(run, :running)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "running", run.reload.state
        assert_nil run.stop_requested_at
      end

      test "a failed probe is not evidence of death" do
        run = started_run(started_at: 3.days.ago)
        execution(run, :unknown)

        run_activity(CleanupStaleRunsActivity)

        assert_equal "running", run.reload.state
      end

      test "does not probe a run younger than a sweep" do
        run = started_run(started_at: 1.minute.ago)
        TemporalService.expects(:execution_state).never

        run_activity(CleanupStaleRunsActivity)

        assert_equal "running", run.reload.state
      end

      test "does not touch pending or terminal runs" do
        pending = create(:workflow_run, workflow: @workflow, project: @project, user: @user, state: "pending")
        done = create(:workflow_run, workflow: @workflow, project: @project, user: @user,
                      state: "completed", started_at: 10.hours.ago, completed_at: 9.hours.ago)
        TemporalService.expects(:execution_state).never

        run_activity(CleanupStaleRunsActivity)

        assert_equal "pending", pending.reload.state
        assert_equal "completed", done.reload.state
      end

      test "continues processing other runs when one transition raises" do
        good_run = started_run
        bad_run = started_run
        TemporalService.stubs(:execution_state).returns(:closed)
        # The first run's stop marker write raises; the second goes through.
        SessionAdmissionService.stubs(:transaction).yields.raises(RuntimeError, "simulated error").then.returns(nil)

        assert_nothing_raised { run_activity(CleanupStaleRunsActivity) }
        assert_equal 1, [ good_run, bad_run ].count { |r| r.reload.state == "failed" }
      end

      test "returns counts of cleaned runs" do
        TemporalService.stubs(:execution_state).returns(:closed)
        started_run
        started_run(state: "paused")

        result = run_activity(CleanupStaleRunsActivity)

        assert_equal 1, result[:cleaned_running]
        assert_equal 1, result[:cleaned_paused]
      end

      test "fails active terminal sessions attached to an orphaned run" do
        run = started_run
        execution(run, :closed)
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
        run = started_run
        execution(run, :closed)
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
