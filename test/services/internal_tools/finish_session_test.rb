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

  test "required evidence cannot be replaced by a success note" do
    @session.update!(metadata: @session.metadata.to_h.merge("completion_evidence_required" => true))

    result = InternalTools::FinishSession.new(params: { note: "All tests passed" }, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_includes result[:stderr], "evidence"
    assert_equal "running", @session.reload.state
    assert_nil @step_run.reload.step_note
  end

  test "successful current-session executions are saved as completion receipts" do
    @session.update!(metadata: @session.metadata.to_h.merge("completion_evidence_required" => true, "keep" => "value"))
    execution = create(:tool_result, :completed, terminal_session: @session, step_run: @step_run)

    result = InternalTools::FinishSession.new(
      params: { evidence_execution_ids: [ execution.execution_id ] }, session: @session
    ).execute

    assert_equal 0, result[:exit_code]
    receipt = @session.reload.metadata.fetch("completion_evidence").first
    assert_equal execution.execution_id, receipt["execution_id"]
    assert_equal 0, receipt["exit_code"]
    assert_equal "value", @session.metadata["keep"]
    assert_not receipt.key?("stdout")
  end

  test "supplied evidence rejects failed pending unknown and foreign executions without side effects" do
    foreign = create(:terminal_session, :agent_session, user: @user, project: @project)
    tool = create(:tool, :internal)
    executions = [
      create(:tool_result, :completed, tool: tool, terminal_session: foreign),
      create(:tool_result, :failed, tool: tool, terminal_session: @session),
      create(:tool_result, :completed, tool: tool, terminal_session: @session, exit_code: 1),
      create(:tool_result, :expired, tool: tool, terminal_session: @session),
      create(:tool_result, tool: tool, terminal_session: @session)
    ]

    (executions.map(&:execution_id) + [ "tr-does-not-exist" ]).each do |id|
      result = InternalTools::FinishSession.new(
        params: { evidence_execution_ids: [ id ], note: "Should not persist" }, session: @session
      ).execute
      assert_equal 1, result[:exit_code]
      assert_equal "running", @session.reload.state
      assert_nil @step_run.reload.step_note
      assert_nil @session.metadata.to_h["completion_evidence"]
    end
  end

  test "malformed or excessive evidence is rejected" do
    [ "tr-string", [ nil ], [ "" ], Array.new(21) { |i| "tr-#{i}" } ].each do |ids|
      result = InternalTools::FinishSession.new(params: { evidence_execution_ids: ids }, session: @session).execute

      assert_equal 1, result[:exit_code]
      assert_equal "running", @session.reload.state
    end
  end

  test "workflow config can require completion evidence" do
    @step_run.workflow_run.workflow.update!(config: { "completion_evidence_required" => true })
    @session.update!(metadata: @session.metadata.to_h.merge("completion_evidence_required" => false))

    result = InternalTools::FinishSession.new(params: {}, session: @session).execute

    assert_equal 1, result[:exit_code]
    assert_equal "running", @session.reload.state
  end
end
