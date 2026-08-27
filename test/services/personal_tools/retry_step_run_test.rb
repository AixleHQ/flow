# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class RetryStepRunTest < ActiveSupport::TestCase
    setup do
      # TemporalService is the app-owned boundary to the Temporal gem; fake it so
      # WorkflowService.retry_step signals a no-op instead of touching a server.
      TemporalService.stubs(:workflow_open?).returns(true)
      TemporalService.stubs(:send_signal).returns({ ok: true })

      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      @workflow = create(:workflow, scope: @project)
      @step = create(:step, workflow: @workflow, position: 1)
      @run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user)
    end

    def execute(project_id: @project.id, run_id: @run.id)
      RetryStepRun.new(params: { project_id: project_id, run_id: run_id }, user: @user).execute
    end

    test "retries the run's failed step: creates a fresh pending step_run and returns success" do
      failed_step_run = create(:step_run, :failed, workflow_run: @run, step: @step)

      result = nil
      assert_difference("StepRun.count", 1) do
        result = execute
      end

      assert_equal 0, result[:exit_code]
      assert_equal "", result[:stderr]

      payload = JSON.parse(result[:stdout])
      assert_equal @run.id, payload["run_id"]
      assert_equal failed_step_run.id, payload["retried_step_run_id"]

      # WorkflowService.retry_step clones the failed step into a new pending run.
      new_step_run = @run.step_runs.where(step: @step).order(:created_at).last
      assert_not_equal failed_step_run.id, new_step_run.id
      assert_equal "pending", new_step_run.state
      assert_equal @step.id, new_step_run.step_id
    end

    test "retries the most recently updated failed step when several have failed" do
      other_step = create(:step, workflow: @workflow, position: 2)
      older_failure = create(:step_run, :failed, workflow_run: @run, step: @step)
      newer_failure = create(:step_run, :failed, workflow_run: @run, step: other_step)
      older_failure.update!(updated_at: 2.hours.ago)
      newer_failure.update!(updated_at: 1.minute.ago)

      result = nil
      assert_difference("StepRun.count", 1) do
        result = execute
      end

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_equal newer_failure.id, payload["retried_step_run_id"]

      new_step_run = @run.step_runs.where(step: other_step).order(:created_at).last
      assert_equal "pending", new_step_run.state
      assert_equal other_step.id, new_step_run.step_id
    end

    test "starts a new run and reports its id when the original run's execution has already closed" do
      TemporalService.stubs(:workflow_open?).returns(false)
      TemporalWorkflowRegistry.stubs(:start_workflow_execution).returns(ok: true)
      @run.update!(state: "failed")
      failed_step_run = create(:step_run, :failed, workflow_run: @run, step: @step)

      result = nil
      assert_difference("WorkflowRun.count", 1) do
        result = execute
      end

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      new_run = WorkflowRun.order(:created_at).last
      assert_equal new_run.id, payload["run_id"]
      assert_not_equal @run.id, payload["run_id"]
      assert_nil payload["retried_step_run_id"]
      assert_equal "failed", @run.reload.state
      assert_equal "failed", failed_step_run.reload.state
    end
  end
end
