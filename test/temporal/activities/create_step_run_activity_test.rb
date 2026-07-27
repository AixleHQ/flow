# frozen_string_literal: true

require "test_helper"

module Activities
  module Workflow
    class CreateStepRunActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, company: @company)
        @project = create(:project, company: @company, owner: @user)
        @workflow = create(:workflow, scope: @project)
        @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
        @step = create(:step, workflow: @workflow)

        Rails.logger.stubs(:info)
        Rails.logger.stubs(:warn)
        Rails.logger.stubs(:error)
      end

      test "creates a new step_run when none exists" do
        result = nil
        assert_difference -> { @run.step_runs.count }, 1 do
          result = run_activity(CreateStepRunActivity,
            { "workflow_run_id" => @run.id, "step_id" => @step.id })
        end

        step_run = StepRun.find(result["step_run_id"])
        assert_equal @run, step_run.workflow_run
        assert_equal @step, step_run.step
        assert step_run.pending?
      end

      test "is idempotent: returns the existing step_run without creating a duplicate" do
        existing = create(:step_run, workflow_run: @run, step: @step)

        result = nil
        assert_no_difference -> { @run.step_runs.count } do
          result = run_activity(CreateStepRunActivity,
            { "workflow_run_id" => @run.id, "step_id" => @step.id })
        end

        assert_equal existing.id, result["step_run_id"]
      end

      test "force_new creates a brand new step_run even when one already exists" do
        existing = create(:step_run, :completed, workflow_run: @run, step: @step)

        result = nil
        assert_difference -> { @run.step_runs.count }, 1 do
          result = run_activity(CreateStepRunActivity,
            { "workflow_run_id" => @run.id, "step_id" => @step.id, "force_new" => true })
        end

        new_step_run = StepRun.find(result["step_run_id"])
        assert_not_equal existing.id, new_step_run.id
        assert_equal @step, new_step_run.step
        assert new_step_run.pending?
      end
    end
  end
end
