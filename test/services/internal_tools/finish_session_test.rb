# frozen_string_literal: true

require "test_helper"

class InternalTools::FinishSessionTest < ActiveSupport::TestCase
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

  test "finishes non-interactive session" do
    result = InternalTools::FinishSession.new(
      params: {},
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    assert_includes result[:stdout], "finished successfully"
  end

  test "appends note to step_run when provided" do
    @step_run.update!(step_note: "Existing note")

    InternalTools::FinishSession.new(
      params: { note: "Final note" },
      session: @session
    ).execute

    @step_run.reload
    assert_equal "Existing note\n---\nFinal note", @step_run.step_note
  end

  test "writes first note to empty step_note" do
    InternalTools::FinishSession.new(
      params: { note: "First finding" },
      session: @session
    ).execute

    @step_run.reload
    assert_equal "First finding", @step_run.step_note
  end

  test "returns error for interactive session" do
    session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, step_run: @step_run, mode: "interactive")

    result = InternalTools::FinishSession.new(
      params: {},
      session: session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "non-interactive"
  end
end
