# frozen_string_literal: true

require "test_helper"

class InternalTools::FailSessionTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @project)
    step = create(:step, workflow: workflow)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: workflow_run, step: step, step_note: nil)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project,
      mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
    @session.stubs(:signal_workflow)
  end

  test "fails non-interactive session with reason" do
    result = InternalTools::FailSession.new(
      params: { reason: "Missing repository" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_includes result[:stdout], "Missing repository"
    assert_equal "Missing repository", @step_run.reload.error_message
  end

  test "transitions session to failed state (not finished)" do
    result = InternalTools::FailSession.new(
      params: { reason: "Out of tokens" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_equal "failed", @session.reload.state
  end

  test "uses default reason when none provided" do
    result = InternalTools::FailSession.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_includes @step_run.reload.error_message, "no reason provided"
  end

  test "appends note to step_run when provided" do
    InternalTools::FailSession.new(
      params: { reason: "Error", note: "Some details" },
      session: @session
    ).execute

    @step_run.reload
    assert_equal "Some details", @step_run.step_note
  end

  test "returns error for interactive session" do
    session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, step_run: @step_run, mode: "interactive")

    result = InternalTools::FailSession.new(
      params: { reason: "test" },
      session: session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "non-interactive"
  end
end
