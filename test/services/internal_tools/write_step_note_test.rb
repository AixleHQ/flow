# frozen_string_literal: true

require "test_helper"

class InternalTools::WriteStepNoteTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    workflow = create(:workflow, scope: @company)
    step = create(:step, workflow: workflow)
    workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user)
    @step_run = create(:step_run, workflow_run: workflow_run, step: step, step_note: nil)

    step_run = @step_run
    project = @project
    @session = Object.new
    @session.define_singleton_method(:project) { project }
    @session.define_singleton_method(:step_run) { step_run }
  end

  test "writes first note to empty step_note" do
    result = InternalTools::WriteStepNote.new(
      params: { note: "First finding" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @step_run.reload
    assert_equal "First finding", @step_run.step_note
    assert_includes result[:stdout], "First finding"
  end

  test "appends note with separator to existing step_note" do
    @step_run.update!(step_note: "Existing note")

    result = InternalTools::WriteStepNote.new(
      params: { note: "Second note" },
      session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    @step_run.reload
    assert_equal "Existing note\n---\nSecond note", @step_run.step_note
  end

  test "returns error for blank note" do
    result = InternalTools::WriteStepNote.new(
      params: { note: "" },
      session: @session
    ).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "required"
  end

  test "raises error outside workflow context" do
    no_wf_session = Object.new
    no_wf_session.define_singleton_method(:step_run) { nil }

    handler = InternalTools::WriteStepNote.new(
      params: { note: "test" },
      session: no_wf_session
    )
    assert_raises(InternalTools::WorkflowContextError) { handler.execute }
  end
end
