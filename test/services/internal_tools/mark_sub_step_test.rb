# frozen_string_literal: true

require "test_helper"

class InternalTools::MarkSubStepTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: workflow_run, step: step)

    sub_step = create(:sub_step, step: step, name: "Task", position: 1)
    @ssr = create(:sub_step_run, step_run: @step_run, sub_step: sub_step, state: :pending)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  test "marks sub-step as in_progress with started_at" do
    result = InternalTools::MarkSubStep.new(
      params: { id: @ssr.id, status: "in_progress" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @ssr.reload
    assert_equal "in_progress", @ssr.state
    assert_not_nil @ssr.started_at
  end

  test "marks sub-step as completed with note and data" do
    result = InternalTools::MarkSubStep.new(
      params: { id: @ssr.id, status: "completed", note: "Done", data: { "count" => 5 } },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @ssr.reload
    assert_equal "completed", @ssr.state
    assert_equal "Done", @ssr.note
    assert_equal({ "count" => 5 }, @ssr.data)
    assert_not_nil @ssr.completed_at
  end

  test "marks sub-step as skipped sets completed_at" do
    result = InternalTools::MarkSubStep.new(
      params: { id: @ssr.id, status: "skipped" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @ssr.reload
    assert_equal "skipped", @ssr.state
    assert_not_nil @ssr.completed_at
  end

  test "returns error for invalid status" do
    result = InternalTools::MarkSubStep.new(
      params: { id: @ssr.id, status: "invalid" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "Invalid status"
  end

  test "returns error for non-existent sub-step run" do
    result = InternalTools::MarkSubStep.new(
      params: { id: -1, status: "completed" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  test "cannot update sub-step from another step" do
    other_step = create(:step, workflow: @step_run.step.workflow)
    other_step_run = create(:step_run, workflow_run: @step_run.workflow_run, step: other_step)
    other_sub_step = create(:sub_step, step: other_step, position: 1)
    other_ssr = create(:sub_step_run, step_run: other_step_run, sub_step: other_sub_step)

    result = InternalTools::MarkSubStep.new(
      params: { id: other_ssr.id, status: "completed" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "not found"
  end

  test "raises error outside workflow context" do
    no_wf_session = Object.new
    no_wf_session.define_singleton_method(:step_run) { nil }

    handler = InternalTools::MarkSubStep.new(
      params: { id: @ssr.id, status: "completed" },
      session: no_wf_session
    )
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
