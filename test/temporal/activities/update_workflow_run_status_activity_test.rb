# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class UpdateWorkflowRunStatusActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @project)

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      test "starts a pending run when status is running" do
        run = create(:workflow_run, project: @project, workflow: @workflow, user: @user)
        assert_equal "pending", run.state

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "running" })

        assert_equal run.id, result["workflow_run_id"]
        assert_equal "running", result["state"]

        run.reload
        assert_equal "running", run.state
        assert_not_nil run.started_at
      end

      test "completes a running run when status is completed" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "completed" })

        assert_equal "completed", result["state"]

        run.reload
        assert_equal "completed", run.state
        assert_not_nil run.completed_at
      end

      test "fails a running run when status is failed" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "failed" })

        assert_equal "failed", result["state"]

        run.reload
        assert_equal "failed", run.state
        assert_not_nil run.completed_at
      end

      test "pauses a running run when status is paused" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "paused" })

        assert_equal "paused", result["state"]
        assert_equal "paused", run.reload.state
      end

      test "cancels a running run and cancels its active step runs when status is cancelled" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
        step = create(:step, workflow: @workflow)
        step_run = create(:step_run, workflow_run: run, step: step, state: :pending)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "cancelled" })

        assert_equal "cancelled", result["state"]

        run.reload
        assert_equal "cancelled", run.state
        assert_not_nil run.completed_at

        assert_equal "cancelled", step_run.reload.state
      end

      # --- guard / no-op success paths (transition not permitted or unknown status) ---

      test "does not start a run that cannot start and returns its current state" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "running" })

        # may_start? is false for an already-running run, so it stays running.
        assert_equal "running", result["state"]
        assert_equal "running", run.reload.state
      end

      test "ignores an unrecognized status and returns the unchanged state" do
        run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)

        result = run_activity(UpdateWorkflowRunStatusActivity,
                              { "workflow_run_id" => run.id, "status" => "unknown_status" })

        assert_equal run.id, result["workflow_run_id"]
        assert_equal "running", result["state"]
        assert_equal "running", run.reload.state
      end
    end
  end
end
