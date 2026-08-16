# frozen_string_literal: true

require "test_helper"

class InternalTools::BoardListGatesTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user    = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @board   = create(:board, project: @project)
    @column  = create(:board_column, board: @board, name: "In Progress", position: 1)
    @task    = create(:board_task, board: @board, board_column: @column, title: "My task")

    workflow      = create(:workflow, scope: @project)
    step          = create(:step, workflow: workflow)
    @workflow_run = create(:workflow_run, workflow: workflow, project: @project, user: @user, board_task: @task)
    @step_run     = create(:step_run, workflow_run: @workflow_run, step: step)

    @session = create(:terminal_session, :running, :agent_session,
      user: @user, project: @project, mode: "non_interactive", initial_prompt: "do work")
    @step_run.update!(terminal_session: @session)
    @session.reload
  end

  def execute(**params)
    InternalTools::BoardListGates.new(params: params, session: @session).execute
  end

  def payload(result) = JSON.parse(result[:stdout])

  def create_gate(task: @task, **attributes)
    task.gates.create!({ gate_type: "github_checks_completed", creator: @user,
                         metadata: { "repo_full_name" => "org/app", "pr_number" => 7 } }.merge(attributes))
  end

  test "defaults to the workflow run's bound task and lists its gates oldest first" do
    older = create_gate(created_at: 2.hours.ago)
    newer = create_gate(gate_type: "github_workflow_completed",
                        metadata: { "repo_full_name" => "org/app", "run_id" => 99 })

    body = payload(execute)

    assert_equal @task.id, body["task_id"]
    assert_equal [ older.id, newer.id ], body["gates"].map { |gate| gate["id"] }
  end

  test "a gate row explains what the task is waiting on and how the wait can end" do
    create_gate

    row = payload(execute)["gates"].sole

    assert_equal "pending", row["status"]
    assert_equal "pending", row["ci_status"]
    assert_equal "github", row["source"]["provider"]
    assert_equal "org/app", row["source"]["repo_full_name"]
    assert_equal 7, row["source"]["reference"]
    assert_equal false, row["expired"] # rubocop:disable Minitest/RefuteFalse
    assert_operator Time.zone.parse(row["expires_at"]), :>, Time.current
  end

  test "a stale gate carries the diagnosis of why nothing could resolve it" do
    create_gate(status: "stale", diagnostic_reason: "run not found",
                reconciliation_log: [ { "at" => "2026-08-01T00:00:00Z", "outcome" => "unreadable" } ])

    row = payload(execute)["gates"].sole

    assert_equal "stale", row["ci_status"]
    assert_equal "run not found", row["diagnostic_reason"]
    assert_equal "unreadable", row["reconciliation_log"].first["outcome"]
  end

  test "status narrows the listing" do
    pending_gate = create_gate
    create_gate(status: "resolved", resolved_at: Time.current, resolution_data: { "conclusion" => "success" })

    body = payload(execute(status: "pending"))

    assert_equal [ pending_gate.id ], body["gates"].map { |gate| gate["id"] }
    assert_equal "pending", body["status"]
  end

  test "a resolved gate reports the provider's verdict" do
    create_gate(status: "resolved", resolved_at: Time.current, resolution_data: { "conclusion" => "failure" })

    row = payload(execute(status: "resolved"))["gates"].sole

    assert_equal "failed", row["ci_status"]
    assert_equal "failure", row["conclusion"]
  end

  test "an unknown status is refused, naming the allowed values" do
    result = execute(status: "wedged")

    assert_equal 1, result[:exit_code]
    assert_match(/pending, resolved, stale, all/, result[:stderr])
  end

  test "a task on another project's board is not found" do
    other_project = create(:project, company: @company, owner: @user)
    other_board   = create(:board, project: other_project)
    other_column  = create(:board_column, board: other_board, name: "Todo", position: 1)
    other_task    = create(:board_task, board: other_board, board_column: other_column, title: "Theirs")
    create_gate(task: other_task)

    result = execute(task_id: other_task.id)

    assert_equal 1, result[:exit_code]
    assert_match(/not found on this board/, result[:stderr])
  end

  test "a session without a workflow context cannot read gates" do
    loose = create(:terminal_session, :running, :agent_session, user: @user, project: @project)

    assert_raises(InternalTools::WorkflowContextError) do
      InternalTools::BoardListGates.new(params: {}, session: loose).execute
    end
  end
end
