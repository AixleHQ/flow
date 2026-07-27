# frozen_string_literal: true

require "test_helper"

class StepRunTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @project)
    @step = create(:step, workflow: @workflow)
    @run = create(:workflow_run, :running, project: @project, workflow: @workflow, user: @user)
    @step_run = create(:step_run, workflow_run: @run, step: @step)
  end

  # --- mark_failed! ---

  test "mark_failed! transitions to failed state" do
    @step_run.mark_failed!("something went wrong")
    assert_equal "failed", @step_run.reload.state
    assert_equal "something went wrong", @step_run.error_message
    assert_not_nil @step_run.completed_at
  end

  test "mark_failed! with no message leaves error_message nil" do
    @step_run.mark_failed!
    assert_equal "failed", @step_run.reload.state
    assert_nil @step_run.error_message
  end

  test "mark_failed! with error_category stores the category" do
    @step_run.mark_failed!("quota exceeded by account", error_category: :quota_exceeded)
    @step_run.reload
    assert_equal "failed", @step_run.state
    assert_equal "quota_exceeded", @step_run.error_category
  end

  test "mark_failed! without error_category leaves error_category nil" do
    @step_run.mark_failed!("generic error")
    @step_run.reload
    assert_nil @step_run.error_category
  end
end
